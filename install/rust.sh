#!/usr/bin/env bash
# install/rust.sh - install rustup + cargo tools from cargo.txt
#
# macOS: uses Homebrew's rustup (code-signed, avoids macOS linker sandbox restrictions)
# Linux: downloads rustup-init directly from sh.rustup.rs (no Homebrew)
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

# Print the crate's binaries that fail to start with a dynamic-loader error
# (gnu prebuilts from modern CI runners can require a newer glibc than the
# host provides; ld.so then refuses to load them at exec time, so binstall
# reports success but every invocation fails). musl and source builds never
# trip this. Bin names come from cargo's install registry — binstall updates
# it too, and bins often differ from crate names (yazi-fm → yazi).
_glibc_broken_bins() {
    local _crate="$1" _bin _err
    has jq || return 0
    [[ -f "$CARGO_HOME/.crates2.json" ]] || return 0
    while IFS= read -r _bin; do
        [[ -x "$CARGO_HOME/bin/$_bin" ]] || continue
        if has timeout; then
            _err="$(timeout 10 "$CARGO_HOME/bin/$_bin" --version </dev/null 2>&1 >/dev/null)" || true
        else
            _err="$("$CARGO_HOME/bin/$_bin" --version </dev/null 2>&1 >/dev/null)" || true
        fi
        if [[ "$_err" == *"GLIBC_"* || "$_err" == *"libc.so"* ]]; then
            printf '%s\n' "$_bin"
        fi
    done < <(jq -r --arg c "$_crate " \
        '.installs | to_entries[] | select(.key | startswith($c)) | .value.bins[]' \
        "$CARGO_HOME/.crates2.json" 2>/dev/null)
    return 0
}

_link_homebrew_rustup_proxies() {
    local _prefix="$1" _proxy _source _dest
    ensure_dir "$CARGO_HOME/bin"

    for _proxy in rustup cargo rustc rustdoc rustfmt rust-analyzer \
        cargo-clippy cargo-fmt cargo-miri clippy-driver rls \
        rust-gdb rust-gdbgui rust-lldb; do
        _source="$_prefix/bin/$_proxy"
        _dest="$CARGO_HOME/bin/$_proxy"
        [[ -x "$_source" ]] || continue
        if [[ -e "$_dest" && ! -L "$_dest" ]]; then
            continue
        fi
        ln -sfn "$_source" "$_dest"
    done

    [[ -x "$CARGO_HOME/bin/rustup" && -x "$CARGO_HOME/bin/rustc" \
        && -x "$CARGO_HOME/bin/cargo" ]]
}

# Source-guard: tests/rust-glibc-smoke.bats sources this file for
# _glibc_broken_bins — everything below only runs when executed directly.
[[ "${BASH_SOURCE[0]}" != "$0" ]] && return 0

log_section "Rust"

# RUSTUP_HOME and CARGO_HOME are rooted under $LOCAL_PLAT by _lib.sh.

### rustup ###

if [[ "$OS" == "darwin" ]]; then
    # macOS: Homebrew's rustup is code-signed, which is required for the macOS
    # linker to open compiled object files (com.apple.provenance enforcement).
    # The keg is intentionally unlinked and no longer ships rustup-init, so
    # expose its per-proxy wrappers from the PLAT-local Cargo bin directory.
    _rustup_prefix="$(brew --prefix rustup 2>/dev/null || true)"
    _brew_rustup_bin="${_rustup_prefix:+$_rustup_prefix/bin/rustup}"

    if [[ -z "$_rustup_prefix" || ! -x "$_brew_rustup_bin" ]]; then
        die "Homebrew rustup not found — packages/Brewfile must install it before rust.sh"
    fi
    _link_homebrew_rustup_proxies "$_rustup_prefix" \
        || die "Homebrew rustup proxy setup failed under $CARGO_HOME/bin"
    RUSTUP_BIN="$CARGO_HOME/bin/rustup"

    if "$RUSTUP_BIN" toolchain list 2>/dev/null | grep -Eq '^stable'; then
        log_okay "Rust toolchain already in PLAT dir: $("$CARGO_HOME/bin/rustc" --version 2>/dev/null)"
        log_info "Updating stable toolchain"
        _rustup_cmd=("$RUSTUP_BIN" update stable)
        _rustup_cmd+=(--no-self-update)
        run_logged "${_rustup_cmd[@]}"
        unset _rustup_cmd
    else
        log_info "Installing stable toolchain (Homebrew rustup) → $RUSTUP_HOME"
        run_logged "$RUSTUP_BIN" set profile default
        run_logged "$RUSTUP_BIN" toolchain install stable --no-self-update
        run_logged "$RUSTUP_BIN" default stable
        log_okay "rustup initialized"
    fi
    unset _rustup_prefix _brew_rustup_bin
else
    # Linux: install rustup-init directly — Homebrew not available or not needed
    if [[ -x "$CARGO_HOME/bin/rustup" ]]; then
        log_okay "rustup already installed: $("$CARGO_HOME/bin/rustup" --version 2>&1)"
        log_info "Updating stable toolchain"
        _rustup_cmd=("$CARGO_HOME/bin/rustup" update stable)
        [[ "${DF_MODE:-}" == "upgrade" ]] || _rustup_cmd+=(--no-self-update)
        run_logged "${_rustup_cmd[@]}"
        unset _rustup_cmd
    else
        log_info "Installing rustup → $CARGO_HOME/bin"
        ensure_dir "$CARGO_HOME/bin"
        _rustup_script="$(mktemp)"
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs -o "$_rustup_script"
        run_logged bash "$_rustup_script" -y --no-modify-path --default-toolchain stable
        rm -f "$_rustup_script"
        log_okay "rustup installed"
    fi
fi

# A floating nightly is an explicit rolling channel. Update it in upgrade mode,
# but leave dated nightlies and exact project toolchains untouched.
if [[ "${DF_MODE:-}" == "upgrade" ]] \
    && "$CARGO_HOME/bin/rustup" toolchain list 2>/dev/null | grep -Eq '^nightly(-[^ ]+)?( |$)' \
    && "$CARGO_HOME/bin/rustup" toolchain list 2>/dev/null | grep -Eq '^nightly-(aarch64|x86_64|arm|i686)-'; then
    log_info "Updating floating nightly toolchain"
    run_logged "$CARGO_HOME/bin/rustup" update nightly --no-self-update
elif [[ "${DF_MODE:-}" == "upgrade" ]] \
    && "$CARGO_HOME/bin/rustup" toolchain list 2>/dev/null | grep -Eq '^nightly( |$)'; then
    log_info "Updating floating nightly toolchain"
    run_logged "$CARGO_HOME/bin/rustup" update nightly --no-self-update
fi

# Ensure cargo is on PATH for this session
export PATH="$CARGO_HOME/bin:$PATH"

### sccache for EVERY cargo invocation (not just profile/install envs) ###
# RUSTC_WRAPPER (set by the shell profiles + _lib.sh) only reaches processes
# that inherit it — a bare cron/CI job or non-login shell running `cargo build`
# misses it. $CARGO_HOME/config.toml is read by cargo itself, everywhere, so it
# closes that gap. CARGO_HOME is per-machine (scratch), NOT shared across the NFS
# fleet, so this can't break another machine; guarded on sccache being present
# (Brewfile installs it earlier). sccache passes incremental (dev) builds
# straight through, so the only builds it caches are the clean/release ones that
# benefit. We never clobber a hand-written config.
if has sccache; then
    _cargo_cfg="$CARGO_HOME/config.toml"
    _cargo_marker="# managed by install/rust.sh — sccache rustc-wrapper"
    if [[ ! -e "$_cargo_cfg" ]]; then
        ensure_dir "$CARGO_HOME"
        printf '%s\n[build]\nrustc-wrapper = "sccache"\n' "$_cargo_marker" > "$_cargo_cfg"
        log_okay "cargo: rustc-wrapper=sccache → config.toml (covers cron/CI/non-login builds)"
    elif grep -q 'rustc-wrapper' "$_cargo_cfg"; then
        log_okay "cargo: rustc-wrapper already configured"
    else
        log_warn "cargo: $_cargo_cfg exists without rustc-wrapper — not touching it; add [build] rustc-wrapper=\"sccache\" to cache non-login cargo builds"
    fi
    unset _cargo_cfg _cargo_marker
fi

### rust-analyzer (rustup component) ###
# Backs the rust-analyzer-lsp Claude Code plugin. A rustup component (not a
# cargo.txt crate) so it always matches the active toolchain version.
if "$CARGO_HOME/bin/rustup" component list 2>/dev/null | grep -q '^rust-analyzer.*(installed)'; then
    log_okay "rust-analyzer component already installed"
else
    log_info "Adding rust-analyzer rustup component"
    run_logged "$CARGO_HOME/bin/rustup" component add rust-analyzer
fi

if [[ "$DF_PROFILE" == "core" ]]; then
    log_info "Core profile: skipping optional cargo.txt tools"
    exit 0
fi

### cargo-binstall ###
# cargo-binstall downloads pre-compiled binaries from GitHub releases when available,
# falling back to `cargo install` (source compilation) otherwise.
# This avoids slow compilation for common tools and works around macOS linker
# sandbox restrictions in restricted shell environments.

if cargo binstall -V &>/dev/null 2>&1; then
    log_okay "cargo-binstall already installed: $(cargo binstall -V 2>/dev/null)"
else
    log_info "Installing cargo-binstall (pre-built binary)"
    # Official installer: downloads a pre-built binary, no compilation needed
    run_logged bash <(curl -L --proto '=https' --tlsv1.2 -sSf \
        https://raw.githubusercontent.com/cargo-bins/cargo-binstall/main/install-from-binstall-release.sh)
    log_okay "cargo-binstall installed"
fi

### cargo tools ###

CARGO_TXT="$DF_PACKAGES/cargo.txt"
[[ -f "$CARGO_TXT" ]] || { log_warn "No cargo.txt at $CARGO_TXT — skipping"; exit 0; }

log_info "Installing/upgrading cargo tools from cargo.txt"

# cargo binstall handles idempotency for installs, but it never upgrades on
# its own — an installed crate satisfies the default `*` requirement and skips
# with "already installed, use --force to override", regardless of newer
# releases. Upgrade mode therefore force-reinstalls every crate.
# Falls back to source compilation if no pre-built binary is available.
#
# DF_CARGO_STRATEGIES: override prebuilt resolution. "compile" skips binstall
#   and uses cargo install directly.
# GITHUB_TOKEN: if set, passed to binstall to authenticate GitHub API calls
#   and raise the rate limit from 60 to 5000 req/hr.
_binstall_flags=(--no-confirm --log-level warn --locked)
_compile_only=0
if [[ "${DF_CARGO_STRATEGIES:-}" == "compile" ]]; then
    _compile_only=1
elif [[ -n "${DF_CARGO_STRATEGIES:-}" ]]; then
    _binstall_flags+=(--strategies "$DF_CARGO_STRATEGIES" --disable-strategies compile)
else
    _binstall_flags+=(--disable-strategies compile)
fi
[[ -n "${GITHUB_TOKEN:-}" ]] && _binstall_flags+=(--github-token "$GITHUB_TOKEN")

# Linux: prefer musl prebuilts (static, zero glibc dependency) over gnu.
# GitHub's ubuntu-latest runners moved to 24.04 (glibc 2.39), so upstream gnu
# prebuilts increasingly refuse to start on older hosts (Ubuntu 22.04 = 2.35:
# atuin/xan/yazi, July 2026). binstall's default order tries gnu first —
# --targets flips it; gnu stays as fallback for crates without musl assets,
# and the post-install smoke test below catches those. NB: the flag is
# repeated, not comma-joined — binstall 1.17 parses "a,b" as one triple and
# aborts the install with "Unrecognized environment".
if [[ "$OS" == "linux" ]]; then
    _mach="$(uname -m)"
    _binstall_flags+=(--targets "${_mach}-unknown-linux-musl" --targets "${_mach}-unknown-linux-gnu")
    unset _mach
elif [[ "$OS" == "darwin" ]]; then
    # Rosetta-compatible x86 assets must not enter an Apple Silicon tool tree.
    _binstall_flags+=(--targets "${ARCH}-apple-darwin")
fi

_ok=0 _fail=0

_install_crate() {
    local crate="$1"
    local _cargo_cmd=(cargo install --locked)
    local _binstall_cmd=(cargo binstall "${_binstall_flags[@]}")
    if [[ "${DF_MODE:-}" == "upgrade" ]]; then
        _cargo_cmd+=(--force)
        _binstall_cmd+=(--force)
    fi
    _cargo_cmd+=("$crate")
    _binstall_cmd+=("$crate")
    if [[ "$_compile_only" == "1" ]]; then
        run_logged "${_cargo_cmd[@]}"
    else
        run_logged "${_binstall_cmd[@]}" || run_logged "${_cargo_cmd[@]}"
    fi
}

while IFS= read -r pkg; do
    log_info "  binstall $pkg"
    # --locked on the source fallback: cargo install ignores the crate's
    # shipped Cargo.lock by default, resolving newest semver-compatible deps.
    # That drifts into API-incompatible transitive versions (atuin-ai vs its
    # 0.3.1 terminal-UI widget dependency) and trips crates that reject
    # unlocked builds.
    # (cargo-nextest's locked-tripwire). --locked honors the tested lockfile.
    if _install_crate "$pkg"; then
        # binstall "success" can still leave a binary the loader rejects
        # (gnu prebuilt wanting newer glibc — also hit when binstall skips an
        # already-latest-but-broken install). Heal in two steps: force-refetch
        # (musl-first targets may land a static build), else build from
        # source, which links the host glibc by construction.
        if [[ "$OS" == "linux" ]] && _bad="$(_glibc_broken_bins "$pkg")" && [[ -n "$_bad" ]]; then
            log_warn "  $pkg prebuilt needs newer glibc (${_bad//$'\n'/, }) — refetching"
            run_logged cargo binstall "${_binstall_flags[@]}" --force "$pkg" || true
            _bad="$(_glibc_broken_bins "$pkg")"
            if [[ -n "$_bad" ]]; then
                log_warn "  $pkg has no runnable prebuilt — building from source"
                if run_logged cargo install --locked --force "$pkg"; then
                    log_okay "  ok    $pkg (source build)"
                    (( _ok++ )) || true
                else
                    log_warn "  fail  $pkg (prebuilt incompatible with host glibc, source build failed)"
                    (( _fail++ )) || true
                fi
                continue
            fi
        fi
        log_okay "  ok    $pkg"
        (( _ok++ )) || true
    else
        log_warn "  fail  $pkg"
        (( _fail++ )) || true
    fi
done < <(_read_package_list "$CARGO_TXT")

log_okay "cargo tools: ${_ok} ok, ${_fail} failed"

### rust-docs-mcp pinned nightly ###
# rust-docs-mcp (cargo.txt → the `rust-docs` MCP server) generates rustdoc
# JSON with an EXACT pinned nightly (JSON format stability). The pin lives
# inside the binary and moves with releases, so ask its doctor: the pin only
# appears in the output while missing — nothing to do once installed.
if [[ -x "$CARGO_HOME/bin/rust-docs-mcp" ]]; then
    _rdm_pin="$("$CARGO_HOME/bin/rust-docs-mcp" doctor 2>&1 \
        | grep -oE 'nightly-[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1 || true)"
    if [[ -n "$_rdm_pin" ]]; then
        log_info "Installing rust-docs-mcp pinned toolchain $_rdm_pin"
        run_logged "$CARGO_HOME/bin/rustup" toolchain install "$_rdm_pin" --profile minimal \
            || log_warn "rust-docs-mcp toolchain install failed — run 'rust-docs-mcp doctor'"
    else
        log_okay "rust-docs-mcp rustdoc toolchain satisfied"
    fi
    unset _rdm_pin
fi
