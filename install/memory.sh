#!/usr/bin/env bash
# install/memory.sh - set up the agent memory stack (L2 knowledge + L3 history)
#
# Three memory layers (see docs/usage/agents.md "Memory layers"):
#   L1  Claude native auto-memory     — built in, nothing to install
#   L2  ~/kb markdown knowledge base  — searched by qmd (npm.txt) via a warm
#       MCP daemon on localhost:8181 (IPv6 ::1) shared by Claude/Codex/opencode
#   L3  agent session history         — indexed by cass (hybrid BM25+local
#       ONNX embeddings) across Claude Code, Codex, opencode, and pi
#
# cass installs from GitHub releases with checksum verification (same pattern
# as install/claude.sh) — its brew tap lags asset re-uploads. On Linux the
# prebuilt binary needs host glibc >= 2.38; older hosts fall back to
# `cargo install --git` when cargo is available.
#
# Indexes live under ~/.cache (scratch-linked on NFS machines) — never synced.
# ~/kb is a git repo and IS the thing you sync across machines.
#
# Modes:
#   setup     -> install/verify cass + qmd config + daemon (no cass indexing)
#   index     -> refresh the cass lexical index
#   semantic  -> process one bounded cass semantic batch
#   reindex   -> force qmd re-embed and rebuild the cass lexical index
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

_mode="${1:-setup}"
case "$_mode" in
    setup|index|semantic|reindex) ;;
    *) die "Usage: memory.sh [setup|index|semantic|reindex]" ;;
esac

log_section "Agent memory stack ($_mode)"

# ~/.cass, not ~/.cache/cass: cass holds the only surviving copy of conversations
# whose transcripts the harnesses have rotated away, so this is an archive, not a
# cache, and nothing may treat it as reclaimable. On scratch machines scratch.sh
# symlinks ~/.cass into scratch (10 TB there vs a quota'd NFS home) — the path
# stays identical either way, so forcing $HOME/.cass is scratch-safe. Forced, not
# defaulted: an inherited value splits the archive in two, silently.
if [[ -n "${CASS_DATA_DIR:-}" && "$CASS_DATA_DIR" != "$HOME/.cass" ]]; then
    log_warn "cass: ignoring inherited CASS_DATA_DIR=$CASS_DATA_DIR — the archive is $HOME/.cass"
fi
export CASS_DATA_DIR="$HOME/.cass"
export CASS_SEMANTIC_EMBEDDER="${CASS_SEMANTIC_EMBEDDER:-minilm}"
# Aider histories are project-local, so discovery crawls this root. Defaulted to
# $HOME it walks every TCC-protected dir on macOS and prompts once per scan.
# Aider projects outside this root go unindexed — widen it if that changes.
# Manual cass index modes inherit this bounded discovery root.
[[ "$OS" == "darwin" ]] && export CASS_AIDER_DATA_ROOT="${CASS_AIDER_DATA_ROOT:-$HOME/dev}"

### cass — session-history search (L3) ###

_CASS_REPO="Dicklesworthstone/coding_agent_session_search"

_cass_platform() {
    case "$OS-$ARCH" in
        darwin-aarch64) echo "darwin-arm64" ;;
        darwin-x86_64)  return 1 ;;  # no x86 darwin release asset — build from source
        linux-aarch64)  echo "linux-arm64" ;;
        linux-x86_64)
            # The optimized build targets x86-64-v3 (AVX2); older CPUs need
            # the baseline asset. PLAT detection encodes the capability level.
            case "${PLAT:-}" in
                *x86-64-v3*|*x86-64-v4*) echo "linux-amd64" ;;
                *)                       echo "linux-amd64-baseline" ;;
            esac ;;
        *) return 1 ;;
    esac
}

# Build cass from source. The repo (coding_agent_session_search) holds two
# packages — the main `coding-agent-search` plus a `cass-fuzz` fuzz crate — and
# the main package builds several bins, so cargo errors with "multiple packages
# with binaries found" unless BOTH the package and the bin are pinned.
_cass_build_from_source() {
    # Two hazards, both learned the hard way:
    #  1. cass needs a NIGHTLY toolchain — a dep gates `#![feature(try_trait_v2)]`
    #     and the repo pins channel="nightly". Stable fails (E0554 on stable, or
    #     an MSRV error on an older stable). Install nightly on demand.
    #  2. Use the rustup cargo/rustup EXPLICITLY, never PATH `cargo`: a Homebrew
    #     `rust` formula (a lingering build-dep) can shadow rustup in bootstrap's
    #     PATH at an old version, which is what silently broke this for months.
    local _cargo="$CARGO_HOME/bin/cargo" _rustup="$CARGO_HOME/bin/rustup"
    if [[ ! -x "$_cargo" || ! -x "$_rustup" ]]; then
        log_warn "cass: rustup toolchain not found under $CARGO_HOME/bin — run install/rust.sh first"
        return 1
    fi
    if ! "$_rustup" toolchain list 2>/dev/null | grep -q '^nightly'; then
        log_info "cass: installing nightly toolchain (cass requires it to build)"
        run_logged "$_rustup" toolchain install nightly --profile minimal \
            || { log_warn "cass: nightly toolchain install failed"; return 1; }
    fi
    run_logged "$_cargo" +nightly install --git "https://github.com/$_CASS_REPO" \
        coding-agent-search --bin cass --locked --root "${ARCH_BIN%/bin}"
}

_cass_works() {
    [[ -x "$1" ]] && "$1" --version >/dev/null 2>&1
}

_install_cass() {
    local _plat _ver _dest _tmp _url _want _got _meta
    _dest="$ARCH_BIN/cass"
    if ! _plat="$(_cass_platform)"; then
        log_info "cass: no release asset for $OS-$ARCH; building from source"
        _cass_build_from_source || return 1
        _cass_works "$_dest"
        return
    fi

    # Resolve the latest release tag via the GitHub API. Route through download()
    # (not raw curl) so it sends Authorization when GITHUB_TOKEN is set: the
    # unauthenticated API limit is 60/hr per IP and is exhausted constantly on
    # shared NAT'd networks (NVIDIA clusters), which returns 403. The `if` keeps
    # a failure non-fatal under `set -e` so we fall back to a source build
    # instead of aborting all of memory.sh on a transient API hiccup.
    _meta="$(mktemp)"
    if download "https://api.github.com/repos/$_CASS_REPO/releases/latest" "$_meta" 2>/dev/null; then
        _ver="$(jq -r '.tag_name // empty' "$_meta")"
    fi
    rm -f "$_meta"
    if [[ -z "${_ver:-}" ]]; then
        log_warn "cass: GitHub API release lookup failed — rate-limited or offline."
        log_warn "cass: set GITHUB_TOKEN (run 'bash install/auth.sh github') to raise the 60/hr limit."
        if _cass_works "$_dest"; then
            log_warn "cass: using the installed version because the release service is unavailable"
            return 0
        fi
        log_info "cass: no working cached binary; building from source"
        _cass_build_from_source || return 1
        _cass_works "$_dest"
        return
    fi

    if _cass_works "$_dest" && "$_dest" --version 2>/dev/null | grep -qF "${_ver#v}"; then
        log_okay "cass ${_ver} already installed at $_dest"
        return 0
    fi

    # Linux prebuilts link system glibc and need >= 2.38.
    if [[ "$OS" == "linux" ]]; then
        local _glibc
        _glibc="$(ldd --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+$' || echo 0)"
        if ! awk -v v="$_glibc" 'BEGIN { exit !(v >= 2.38) }'; then
            log_info "cass: host glibc $_glibc < 2.38; building from source"
            _cass_build_from_source || return 1
            _cass_works "$_dest"
            return
        fi
    fi

    _tmp="$(mktemp -d)"
    # shellcheck disable=SC2064
    trap "rm -rf '$_tmp'" RETURN
    _url="https://github.com/$_CASS_REPO/releases/download/$_ver"
    log_info "Downloading cass $_ver ($_plat)..."
    if ! download "$_url/cass-$_plat.tar.gz" "$_tmp/cass.tar.gz" \
        || ! download "$_url/cass-$_plat.tar.gz.sha256" "$_tmp/cass.tar.gz.sha256"; then
        if _cass_works "$_dest"; then
            log_warn "cass: release asset unavailable; keeping the working installed version"
            return 0
        fi
        return 1
    fi
    _want="$(awk '{print $1}' "$_tmp/cass.tar.gz.sha256")"
    if [[ "$OS" == "darwin" ]]; then
        _got="$(shasum -a 256 "$_tmp/cass.tar.gz" | awk '{print $1}')"
    else
        _got="$(sha256sum "$_tmp/cass.tar.gz" | awk '{print $1}')"
    fi
    [[ "$_got" == "$_want" ]] || die "cass: checksum mismatch for $_ver/$_plat"
    tar -xzf "$_tmp/cass.tar.gz" -C "$_tmp"
    ensure_dir "$ARCH_BIN"
    install -m 755 "$(fd -t f '^cass$' "$_tmp" | head -1 || find "$_tmp" -type f -name cass | head -1)" "$_dest"
    _cass_works "$_dest" || return 1
    log_okay "Installed cass $_ver → $_dest"
}

_install_cass || die "cass: installation did not produce a working command"

_cass="$ARCH_BIN/cass"
_cass_works "$_cass" || die "cass: installation did not produce a working command"

# MiniLM is cass's architecture-verified native embedder. Nomic's removed
# ONNX path is still downloadable in cass 0.6.22 but cannot build an index.
# `models status` prints a per-model block; an installed model's Status
# line does NOT contain "not acquired". -y is required: without it the
# installer prompts and silently cancels on non-tty stdin (exit 0!).
if "$_cass" models status 2>/dev/null | grep -A6 -i 'minilm' | grep -i 'status:' | grep -qiv 'not acquired'; then
    log_okay "cass: all-MiniLM-L6-v2 model already installed"
else
    log_info "cass: installing all-MiniLM-L6-v2 model (~87MB, one-time)"
    run_logged "$_cass" models install --model all-minilm-l6-v2 -y \
        || die "cass: model installation failed"
    if ! "$_cass" models status 2>/dev/null | grep -A6 -i 'minilm' | grep -i 'status:' | grep -qiv 'not acquired'; then
        die "cass: all-MiniLM-L6-v2 model is still unavailable after installation"
    fi
fi

# cass indexing is deliberately manual. Raw session archives can be large,
# so install/upgrade must not wait for derived lexical or semantic assets.
if [[ "$_mode" == "reindex" ]]; then
    if pgrep -f "cass index" >/dev/null 2>&1; then
        die "cass: index already running; refusing a concurrent rebuild"
    else
        log_info "cass: full lexical index rebuild"
        run_logged "$_cass" index --full \
            || die "cass full index failed — run 'cass doctor'"
    fi
elif [[ "$_mode" == "index" ]]; then
    if pgrep -f "cass index" >/dev/null 2>&1; then
        die "cass: index already running; refusing a concurrent refresh"
    else
        log_info "cass: refreshing lexical session index"
        run_logged "$_cass" index \
            || die "cass index failed — run 'cass doctor'"
    fi
elif [[ "$_mode" == "semantic" ]]; then
    if pgrep -f "cass index" >/dev/null 2>&1; then
        die "cass: lexical index is running; retry the semantic batch after it finishes"
    else
        log_info "cass: processing one bounded semantic batch"
        run_logged "$_cass" models backfill --tier quality --embedder fastembed --batch-conversations 64 \
            || die "cass semantic batch failed — run 'cass doctor'"
    fi
else
    log_info "cass: indexing is manual (memory.sh index / memory.sh semantic)"
fi

### ~/kb — markdown knowledge base (L2 source of truth) ###

if [[ ! -d "$HOME/kb/.git" ]]; then
    log_info "Creating ~/kb knowledge-base repo"
    ensure_dir "$HOME/kb/decisions" ; ensure_dir "$HOME/kb/notes" ; ensure_dir "$HOME/kb/snippets"
    if [[ ! -f "$HOME/kb/README.md" ]]; then
        cat > "$HOME/kb/README.md" <<'EOF'
# kb — cross-project knowledge base

Plain markdown, one topic per file, searched semantically by qmd (and any
agent with file tools). Layout:

- `decisions/` — choices made and why (tech picks, architecture, conventions)
- `notes/`     — durable how-tos, environment quirks, research findings
- `snippets/`  — reusable code/config fragments worth keeping

Written by both me and agents. Commit like code. Synced via git remote;
search indexes rebuild per machine (never synced).
EOF
    fi
    git -C "$HOME/kb" init -q
    # _lib.sh exports GIT_CONFIG_GLOBAL=/dev/null (intentionally — see its
    # comment), which hides ~/.gitconfig identity; commit with it restored.
    env -u GIT_CONFIG_GLOBAL git -C "$HOME/kb" add -A
    env -u GIT_CONFIG_GLOBAL git -C "$HOME/kb" commit -qm "kb: initial layout" \
        || die "kb: initial commit failed — set git identity and retry"
    log_okay "$HOME/kb initialized (add a private remote to sync across machines)"
else
    log_okay "$HOME/kb already a git repo"
fi

### qmd — knowledge search daemon (L2 search) ###

if ! has qmd; then
    die "qmd not found — run install/node.sh (npm.txt has @tobilu/qmd)"
else
    _qmd="$(command -v qmd)"
    run_logged "$_qmd" --version || die "qmd command is installed but does not run"
    # Collections: kb + Claude auto-memory + dotfiles docs.
    #
    # `collection show` answers by exit code (0 present, 1 absent). The guard
    # used to grep `collection list`, whose output is a human-readable report
    # and whose stderr was discarded — so any hiccup in that one command read as
    # "collection absent", and the add that followed exits non-zero on an
    # existing collection and killed the whole script under set -e.
    _qmd_add() {
        local _name="$1"; shift
        if "$_qmd" collection show "$_name" >/dev/null 2>&1; then
            log_okay "  qmd collection $_name already indexed"
        elif run_logged "$_qmd" collection add "$@" --name "$_name"; then
            log_okay "  qmd collection $_name added"
        else
            return 1
        fi
        "$_qmd" collection show "$_name" >/dev/null 2>&1
    }
    _qmd_add kb "$HOME/kb" || die "qmd collection kb could not be configured"
    _qmd_add agent-memory "$HOME/.claude/projects" --mask '**/memory/*.md' \
        || die "qmd collection agent-memory could not be configured"
    _qmd_add dotfiles-docs "$DF_ROOT/docs" --mask '**/*.md' \
        || die "qmd collection dotfiles-docs could not be configured"

    if [[ "$_mode" == "reindex" ]]; then
        run_logged "$_qmd" update || die "qmd update failed"
        run_logged "$_qmd" embed -f || die "qmd forced embedding failed"
    elif [[ "$_mode" == "setup" ]]; then
        # Incremental: cheap when nothing changed. Models download on first use.
        run_logged "$_qmd" update || die "qmd update failed"
        run_logged "$_qmd" embed || die "qmd embedding failed"
    else
        log_info "qmd: unchanged for cass $_mode"
    fi
    run_logged "$_qmd" status || die "qmd status check failed"
fi

### Daemons ###

if [[ "$OS" == "darwin" ]]; then
    # launchd does NOT create parent dirs for StandardOut/ErrorPath — without
    # these the jobs fail to spawn silently.
    ensure_dir "$HOME/.local/share/qmd"
    # Cass indexing used to be scheduled. Remove loaded legacy jobs; chezmoi
    # removes their plist files via home/.chezmoiremove.
    for _agent in dev.cade.cass-watch dev.cade.cass-semantic; do
        if launchctl print "gui/$(id -u)/$_agent" >/dev/null 2>&1; then
            launchctl bootout "gui/$(id -u)/$_agent" >/dev/null 2>&1 \
                && log_okay "removed scheduled $_agent"
        fi
    done
    # The qmd MCP daemon remains automatic; it serves requests but does not
    # schedule cass indexing.
    _agent=dev.cade.qmd
    _plist="$HOME/Library/LaunchAgents/$_agent.plist"
    if [[ ! -f "$_plist" ]]; then
        die "$_agent.plist missing — run chezmoi apply"
    elif launchctl print "gui/$(id -u)/$_agent" >/dev/null 2>&1; then
        if _qmd_daemon_healthy; then
            log_okay "$_agent already loaded"
        else
            launchctl kickstart -k "gui/$(id -u)/$_agent" \
                || die "could not restart unhealthy $_agent"
            log_okay "restarted $_agent"
        fi
    else
        # Clear any disabled override first: bootstrap on a disabled label
        # returns success but launchd never runs the job.
        launchctl enable "gui/$(id -u)/$_agent" 2>/dev/null || true
        if launchctl bootstrap "gui/$(id -u)" "$_plist" 2>/dev/null; then
            log_okay "loaded $_agent"
        else
            die "could not load $_agent (launchctl bootstrap failed)"
        fi
    fi
else
    # No launchd: lazy-start (also done by shell profiles on login).
    if qmd_daemon_running && ! _qmd_daemon_healthy; then
        log_info "restarting unhealthy qmd MCP daemon"
        qmd_daemon_stop
        qmd_daemon_running && die "could not stop unhealthy qmd MCP daemon"
        qmd_daemon_start || die "could not restart qmd MCP daemon"
        log_okay "restarted qmd mcp daemon"
    elif ! qmd_daemon_running; then
        qmd_daemon_start || die "could not start qmd MCP daemon"
        log_okay "started qmd mcp daemon"
    fi
fi

_qmd_wait_healthy || die "qmd MCP daemon failed its health check on localhost:8181"

log_okay "Memory stack ready (qmd MCP on localhost:8181; cass archive at $CASS_DATA_DIR)"
