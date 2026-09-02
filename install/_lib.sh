#!/usr/bin/env bash
# install/_lib.sh - shared helpers for all install scripts
# Usage: source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

# Bash 5.3 on macOS can deadlock while writing heredocs into pipelines.
if [[ "${BASH_SOURCE[1]:-}" == "$0" && "$(uname -s)" == "Darwin" ]] \
    && (( BASH_VERSINFO[0] > 5 || (BASH_VERSINFO[0] == 5 && BASH_VERSINFO[1] >= 3) )) \
    && [[ "$BASH" != "/bin/bash" ]]; then
    exec /bin/bash "$0" "$@"
fi

set -euo pipefail

### COLORS ###

# Respect NO_COLOR convention and non-interactive output
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    _RESET='\033[0m'
    _BOLD='\033[1m'
    _DIM='\033[2m'
    _BLUE='\033[0;34m'
    _GREEN='\033[0;32m'
    _YELLOW='\033[0;33m'
    _RED='\033[0;31m'
    _CYAN='\033[0;36m'
    _WHITE='\033[1;37m'
else
    _RESET='' _BOLD='' _DIM='' _BLUE='' _GREEN='' _YELLOW='' _RED='' _CYAN='' _WHITE=''
fi

### LOGGING ###

DF_DEBUG="${DF_DEBUG:-0}"

log_info()    { printf "${_BLUE}${_BOLD}[info]${_RESET}  %s\n"    "$*"; }
log_okay()    { printf "${_GREEN}${_BOLD}[okay]${_RESET}  %s\n"   "$*"; }
log_warn() {
    printf "${_YELLOW}${_BOLD}[warn]${_RESET}  %s\n"  "$*"
    # Record degradations (skipped installs, failed-but-non-fatal steps) so
    # bootstrap can print one consolidated summary at the end — otherwise a
    # real gap (e.g. cass didn't build) scrolls past unnoticed. DF_DEGRADE_LOG
    # is exported by bootstrap.sh; each install script runs as a child and
    # appends to the same file. Never let this fail the caller (set -e).
    if [[ -n "${DF_DEGRADE_LOG:-}" ]]; then
        printf '%s\n' "$*" >> "$DF_DEGRADE_LOG" 2>/dev/null || true
    fi
    return 0
}
log_fail()    { printf "${_RED}${_BOLD}[fail]${_RESET}  %s\n"     "$*" >&2; }
log_debug()   { [[ "$DF_DEBUG" == "1" ]] && printf "${_CYAN}[dbug]${_RESET}  ${_DIM}%s${_RESET}\n" "$*" || true; }

_SECTION_START=$SECONDS
log_section() {
    local _prev_elapsed=$(( SECONDS - _SECTION_START ))
    # Print elapsed time of previous section (skip if first section or < 1s)
    if [[ "$DF_DEBUG" == "1" && "$_prev_elapsed" -gt 0 ]]; then
        printf '%s      (%ss)%s\n' "$_DIM" "$_prev_elapsed" "$_RESET"
    fi
    printf "\n${_WHITE}=== %s ===${_RESET}\n\n" "$*"
    _SECTION_START=$SECONDS
}

die() {
    log_fail "$*"
    exit 1
}

### ERROR TRAP ###

_on_error() {
    local exit_code=$?
    local line=$1
    log_fail "Script failed at line $line (exit code $exit_code)"
    exit "$exit_code"
}
trap '_on_error $LINENO' ERR

### PATHS ###

# Root of the dotfiles repo (parent of install/)
DF_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DF_PACKAGES="$DF_ROOT/packages"

DF_PROFILE="${DF_PROFILE:-full}"
case "$DF_PROFILE" in
    core|full) ;;
    *) die "DF_PROFILE must be 'core' or 'full' (got '$DF_PROFILE')" ;;
esac

### PLATFORM ###

# DF_USE_PLAT controls per-architecture directory isolation. Default: off.
#
# DF_USE_PLAT=0 (default): flat ~/.local/ layout — single-machine setup.
#   Compiled tools live at ~/.local/bin/. Cargo/nvm/uv/rustup state lives at
#   ~/.local/{cargo,nvm,uv,rustup}/. Capability-tuned compiler flags from
#   .plat_env.sh (CFLAGS, RUSTFLAGS, HOMEBREW_OPTFLAGS) are still loaded —
#   PLAT detection is independent of directory layout.
#
# DF_USE_PLAT=1: per-PLAT directory isolation — for shared NFS homes only.
#   Compiled tools live at ~/.local/$PLAT/bin/, etc. Two machines on the same
#   NFS home with different architectures install side-by-side without
#   clobbering each other.
#
# Set DF_USE_PLAT=1 only if you actually share $HOME across machines with
# different CPU architectures (rare). Most users want the default.
#
# PLAT format: plat_{OS}_{cpu-target} (e.g. plat_Linux_x86-64-v3, plat_Darwin_arm64).
# Detection scans install/plat/plat_${OS}_*/ (highest level first), runs
# .plat_check.sh, picks the first that exits 0, then sources .plat_env.sh.

OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
[[ "$OS" == "darwin" ]] && OS="darwin" || OS="linux"

ARCH="$(uname -m)"
# Normalize to aarch64: macOS reports arm64, Linux reports aarch64 for the same ISA.
# Using aarch64 everywhere avoids per-OS conditionals in install scripts.
[[ "$ARCH" == "arm64" ]] && ARCH="aarch64"

# Normalize DF_USE_PLAT: accept 1/true/yes/on as enabled (matches the chezmoi
# template, which writes use_plat=true|false). Without this, `DF_USE_PLAT=true`
# would silently render profiles PLAT-on while install scripts go flat.
case "${DF_USE_PLAT:-0}" in
    1|true|yes|on|TRUE|YES|ON) DF_USE_PLAT=1 ;;
    *) DF_USE_PLAT=0 ;;
esac

# PLAT detection: scan install/plat/ for .plat_check.sh scripts (highest level first).
# Always run regardless of DF_USE_PLAT — capability flags from .plat_env.sh
# (RUSTFLAGS=-Ctarget-cpu=..., HOMEBREW_OPTFLAGS=-march=..., etc.) are still
# useful in flat mode for binaries this machine actually compiles.
PLAT=""
_PLAT_SCRIPT_DIR="$DF_ROOT/install/plat"
if [[ -d "$_PLAT_SCRIPT_DIR" ]]; then
    _PLAT_OS="$(uname -s)"
    while IFS= read -r _plat_dir; do
        _check="$_plat_dir/.plat_check.sh"
        if [[ -f "$_check" ]] && /bin/sh "$_check" 2>/dev/null; then
            PLAT="$(basename "$_plat_dir")"
            [[ -f "$_plat_dir/.plat_env.sh" ]] && source "$_plat_dir/.plat_env.sh"
            break
        fi
    done < <(ls -1d "$_PLAT_SCRIPT_DIR"/plat_"${_PLAT_OS}"_*/ 2>/dev/null | sort -r)
    unset _PLAT_OS _plat_dir _check
fi
unset _PLAT_SCRIPT_DIR

# When PLAT isolation is on, a matching spec is required (the directory name
# embeds $PLAT). When off, missing spec is fine — capability flags just don't
# get tuned. Both cases are non-fatal in flat mode.
if [[ "$DF_USE_PLAT" == "1" && -z "$PLAT" \
      && "${DF_DEFER_PLAT_REQUIRE:-0}" != "1" ]]; then
    die "DF_USE_PLAT=1 but no matching plat spec in $DF_ROOT/install/plat/ for $(uname -s) $(uname -m)"
fi

# Resolve ~/.local through any symlink so tool configs (rustup, cargo, nvm)
# store the real physical path. Prevents stale entries if ~/.local moves.
_LOCAL_ROOT="$HOME/.local"
if [[ -L "$_LOCAL_ROOT" ]]; then
    _LOCAL_ROOT="$(readlink -f "$_LOCAL_ROOT")"
fi

if [[ "$DF_USE_PLAT" == "1" ]]; then
    LOCAL_PLAT="$_LOCAL_ROOT/$PLAT"
else
    LOCAL_PLAT="$_LOCAL_ROOT"
fi
unset _LOCAL_ROOT
ARCH_BIN="$LOCAL_PLAT/bin"

# Standard per-machine tool paths — always derived from LOCAL_PLAT.
# Never inherit from env (stale RUSTUP_HOME etc. causes installs to wrong dir).
RUSTUP_HOME="$LOCAL_PLAT/rustup"
CARGO_HOME="$LOCAL_PLAT/cargo"
# macOS Sequoia+ blocks ar/ld from writing .rlib archives in system temp
# (/var/folders/.../T/). Redirect cargo build artifacts to a home-dir path.
CARGO_TARGET_DIR="$LOCAL_PLAT/cargo-build"

# uv: keep all arch-specific state under LOCAL_PLAT
UV_TOOL_BIN_DIR="$ARCH_BIN"
UV_TOOL_DIR="$LOCAL_PLAT/uv/tools"
UV_PYTHON_INSTALL_DIR="$LOCAL_PLAT/uv/python"
PYTHON_ENV="$LOCAL_PLAT/python"

# nvm: per-PLAT so arch-specific node binaries don't collide on shared homes
NVM_DIR="$LOCAL_PLAT/nvm"

# conan: per-PLAT — cache has compiled binaries, default profile is machine-specific,
# and the cache is not concurrency-safe (multiple NFS clients would corrupt it).
CONAN_HOME="$LOCAL_PLAT/conan2"

# Go: GOBIN=ARCH_BIN lands `go install` binaries alongside cargo/uv ones, so
# packages/go.txt entries don't need a second bin dir on PATH. GOPATH (module
# cache + workspace) and GOCACHE (build cache) are PLAT-isolated by necessity —
# both contain compiled artifacts that aren't portable across architectures.
GOPATH="$LOCAL_PLAT/go"
GOBIN="$ARCH_BIN"
GOCACHE="$LOCAL_PLAT/go-build"

# elan (Lean toolchains) + julia depots: arch-specific compiled artifacts,
# PLAT-isolated like rustup. Same paths as the shell profiles.
ELAN_HOME="$LOCAL_PLAT/elan"
JULIAUP_DEPOT_PATH="$LOCAL_PLAT/julia/juliaup"
JULIA_DEPOT_PATH="$LOCAL_PLAT/julia/depot"

# Compiler cache for INSTALL-TIME builds. The shell profiles export these for
# interactive shells, but install scripts run in bootstrap's non-login bash
# (and possibly cron/CI) which never sources a profile — so without this,
# install-time cargo builds (rust.sh, the cass source build) silently miss the
# sccache cache. Guard on sccache being present (Brewfile installs it at step 4,
# before rust/memory at step 6). Same SCCACHE_DIR as the profile → one shared
# cache on scratch. `:-` respects an inherited value / user override.
if command -v sccache >/dev/null 2>&1; then
    export RUSTC_WRAPPER="${RUSTC_WRAPPER:-sccache}"
    export SCCACHE_DIR="${SCCACHE_DIR:-$HOME/.cache/sccache}"
fi

# Scratch space for NFS homes with small quotas.
#
# When scratch is configured, install/scratch.sh symlinks large home dirs
# from $HOME into $PATHS/ (a subdir of scratch), keeping the NFS home lean.
#
# How to configure (pick one):
#   a) Create ~/scratch as a symlink to large local storage:
#        ln -s /local/disk/$USER ~/scratch
#   b) Set DF_SCRATCH before running bootstrap:
#        DF_SCRATCH=/local/disk/$USER ~/dotfiles/bootstrap.sh
#
# Variable reference:
#   DF_SCRATCH       — actual scratch directory on local disk
#   DF_SCRATCH_LINK  — symlink in $HOME pointing to scratch (default: ~/scratch)
#                      bootstrap.sh creates this symlink if DF_SCRATCH is set.
#   DF_LINKS         — colon-separated list of home dirs to redirect to scratch
#                      (default: ~/.local:~/.cache)
#   SCRATCH          — resolved absolute path to scratch root (empty if none)
#   PATHS            — $SCRATCH/.paths — where all symlinked dirs live

DF_SCRATCH="${DF_SCRATCH:-}"
DF_SCRATCH_LINK="${DF_SCRATCH_LINK:-$HOME/scratch}"
if [[ -z "${DF_SCRATCH:-}" && -e "$DF_SCRATCH_LINK" ]]; then
    DF_SCRATCH="$(cd "$DF_SCRATCH_LINK" && pwd -P)"
fi
SCRATCH="${DF_SCRATCH:-}"
PATHS="${SCRATCH:+$SCRATCH/.paths}"
export DF_SCRATCH DF_SCRATCH_LINK SCRATCH PATHS

export OS ARCH DF_ROOT DF_PACKAGES DF_PROFILE DF_USE_PLAT \
       PLAT LOCAL_PLAT ARCH_BIN RUSTUP_HOME CARGO_HOME CARGO_TARGET_DIR \
       UV_TOOL_BIN_DIR UV_TOOL_DIR UV_PYTHON_INSTALL_DIR PYTHON_ENV \
       NVM_DIR CONAN_HOME \
       GOPATH GOBIN GOCACHE \
       ELAN_HOME JULIAUP_DEPOT_PATH JULIA_DEPOT_PATH

# resolve_nvm_default_bin — print the bin directory selected by nvm's default
# alias. install/node.sh keeps that alias on the supported LTS major; resolving
# it here keeps bootstrap and login shells on the same Node/npm global tree even
# when an older experimental major is still installed beside it.
resolve_nvm_default_bin() {
    local _default _dir
    [[ -r "$NVM_DIR/alias/default" ]] || return 1
    IFS= read -r _default < "$NVM_DIR/alias/default"
    _default="${_default#v}"
    [[ "$_default" =~ ^[0-9]+([.][0-9]+){0,2}$ ]] || return 1

    _dir="$NVM_DIR/versions/node/v$_default"
    if [[ ! -d "$_dir/bin" ]]; then
        _dir="$(printf '%s\n' "$NVM_DIR/versions/node/v${_default}".* 2>/dev/null | sort -V | tail -1)"
    fi
    [[ -d "$_dir/bin" ]] || return 1
    printf '%s/bin\n' "$_dir"
}

# Node comes from nvm, ahead of whatever else is on PATH — the same order the
# shell profiles establish, restated here because install scripts inherit the
# caller's PATH and `brew shellenv` puts brew's bin in front of it.
#
# This is not cosmetic: native npm addons are ABI-locked to the Node major that
# built them, so a global installed under nvm's node dies the moment Homebrew's
# node runs it —
#   better_sqlite3.node was compiled against NODE_MODULE_VERSION 141.
#   This version of Node.js requires NODE_MODULE_VERSION 147
# — and only for the subcommands that actually load the addon, which is how it
# stayed hidden (`qmd collection show` passes, `qmd update` aborts).
if _nvm_bin="$(resolve_nvm_default_bin 2>/dev/null)"; then
    PATH="$_nvm_bin:$PATH"
    unset _nvm_bin
    export PATH
fi

# Install scripts clone public repos and must not be affected by the user's
# gitconfig (which may have url.insteadOf SSH rewrites, breaking clones on
# machines without SSH keys — Docker, CI, fresh Linux boxes).
export GIT_CONFIG_GLOBAL=/dev/null

# git_clone_url <host> <path> [ssh_port] — resolve a clone URL for <host>/<path>,
# preferring SSH when a key authenticates to <host>, else HTTPS (which relies on
# ~/.netrc). The scp-less ssh:// form is uniform for `git clone` and uv/pip
# `git+ssh://…`. ssh_port defaults to 22 (gitlab-master's git SSH is on 12051 —
# port 22 there is a different service that rejects git auth). Force a scheme with
# DF_GIT_PROTO=ssh|https (default: auto = prefer SSH). The SSH probe is BatchMode +
# ConnectTimeout bounded and never aborts the caller (set -e safe): a blocked port
# or missing key resolves to https.
git_clone_url() {
    local host="$1" path="${2#/}" ssh_port="${3:-22}" proto="${DF_GIT_PROTO:-auto}" rc=0
    path="${path%.git}"
    if [[ "$proto" == auto ]]; then
        proto=https
        if has ssh; then
            ssh -o BatchMode=yes -o ConnectTimeout=6 -o StrictHostKeyChecking=accept-new \
                -p "$ssh_port" -T "git@$host" </dev/null >/dev/null 2>&1 || rc=$?
            # rc 255 = connect/auth failure → HTTPS; 0 (GitLab welcome) or other
            # non-255 (e.g. hosts that deny shell with rc 1) = authenticated → SSH.
            [[ $rc -ne 255 ]] && proto=ssh || true
        fi
    fi
    if [[ "$proto" != ssh ]]; then
        printf 'https://%s/%s.git' "$host" "$path"
    elif [[ "$ssh_port" == 22 ]]; then
        printf 'ssh://git@%s/%s.git' "$host" "$path"
    else
        printf 'ssh://git@%s:%s/%s.git' "$host" "$ssh_port" "$path"
    fi
}

# Source credential env files (e.g. ~/.github.env with GITHUB_TOKEN) so that
# install scripts can authenticate with GitHub APIs (cargo-binstall, gh, etc.).
# Uses bash globbing — no error if no files match.
for _envfile in "$HOME"/.*.env; do
    # shellcheck disable=SC1090
    [[ -f "$_envfile" ]] && source "$_envfile"
done
unset _envfile

### OVERLAYS ###

# Discover overlay repos (dotfiles-*/). Each overlay can provide its own
# packages/ dir mirroring the parent layout (e.g. mcp-servers.txt, cargo.txt).
# Install scripts use overlay_package_files() to iterate over all copies of a
# given package list — base first, then each overlay in sorted order.
#
# Example:
#   while IFS= read -r _file; do
#       _process_entries_from "$_file"
#   done < <(overlay_package_files "mcp-servers.txt")

DF_OVERLAYS=()
for _overlay_dir in "$DF_ROOT"/dotfiles-*/; do
    [[ -d "$_overlay_dir" ]] && DF_OVERLAYS+=("${_overlay_dir%/}")
done
unset _overlay_dir

# Print paths to every copy of a package file: $DF_PACKAGES/<name> first,
# then $overlay/packages/<name> for each overlay that has it.
overlay_package_files() {
    local name="$1" _dir
    [[ -f "$DF_PACKAGES/$name" ]] && printf '%s\n' "$DF_PACKAGES/$name"
    for _dir in "${DF_OVERLAYS[@]-}"; do
        [[ -f "$_dir/packages/$name" ]] && printf '%s\n' "$_dir/packages/$name"
    done
    return 0
}

# Print the base package list and, for the full profile, its disjoint
# <stem>-full.<ext> companion. The same overlay rules apply to both files.
profile_package_files() {
    local name="$1" stem extension
    overlay_package_files "$name"
    [[ "$DF_PROFILE" == "full" ]] || return 0

    stem="${name%.*}"
    extension="${name##*.}"
    overlay_package_files "${stem}-full.${extension}"
}

# mcp_profile_enabled PROFILE — true for core entries and profiles selected in
# DF_MCP_PROFILES. The opt-in list accepts colon, comma, or whitespace separators.
mcp_profile_enabled() {
    local _want="${1:-core}" _enabled _profiles="${DF_MCP_PROFILES:-}"
    [[ "$_want" == "core" ]] && return 0
    _profiles="${_profiles//:/ }"
    _profiles="${_profiles//,/ }"
    for _enabled in $_profiles; do
        [[ "$_enabled" == "$_want" || "$_enabled" == "*" ]] && return 0
    done
    return 1
}

# mcp_servers_each [--all] — the ONE parser for packages/mcp-servers.txt (+ overlays).
# Emits one normalized JSON object per entry on stdout:
#   {"name","kind":"stdio"|"remote","transport","cmd","url","auth",
#    "codex_client_id","codex_bearer","profile","risk","extras"}
# Untagged rows remain core/read entries. profile=<name> makes a row opt-in via
# DF_MCP_PROFILES; --all returns every profile for validation and inventory.
# risk is read, local-write, or external-write.
# Policy-free: no {VAR} substitution, no credential resolution — the per-tool
# renderers (install/{claude,codex,opencode,cursor}.sh) own that. `extras` is
# the passthrough token string minus auth=, --codex-client-id, and
# --codex-bearer (+ their values), i.e. exactly what `claude mcp add` should
# receive. Consume with:
#   while IFS= read -r _name && IFS= read -r _kind && ...; do ...
#   done < <(mcp_servers_each | jq -r '.name, .kind, ...')
# (one field per line — TSV would collapse empty fields under `read`).
# Tested by tests/mcp-emitters.bats; four emitters once diverged silently
# from hand-rolled copies of this loop — extend it HERE, not in a renderer.
mcp_servers_each() {
    local _include_all=0 _file _line _name _transport _url _cmd _metadata
    local _kind _auth _codex_client_id _codex_bearer _profile _risk _extras
    local _grab_ccid _grab_cbear _tok
    [[ "${1:-}" == "--all" ]] && _include_all=1
    while IFS= read -r _file; do
        while IFS= read -r _line; do
            [[ -z "$_line" || "$_line" == \#* ]] && continue
            _cmd="" _url="" _kind="remote"
            _auth="" _codex_client_id="" _codex_bearer="" _profile="core" _risk="read" _extras=""
            _grab_ccid=0 _grab_cbear=0

            read -r _name _transport _url _metadata <<< "$_line"
            if [[ "$_transport" == "stdio" && "$_line" == *"cmd: "* ]]; then
                _kind="stdio"
                _cmd="${_line#*cmd: }"
                _metadata="${_line%%cmd: *}"
                read -r _name _transport _metadata <<< "$_metadata"
                _url=""
            else
                _metadata="${_metadata:-}"
            fi

            for _tok in $_metadata; do
                    if [[ "$_kind" == "stdio" ]]; then
                        case "$_tok" in
                            profile=*) _profile="${_tok#profile=}" ;;
                            risk=*)    _risk="${_tok#risk=}" ;;
                            *) log_fail "Unsupported stdio MCP metadata for $_name: $_tok"; return 1 ;;
                        esac
                        continue
                    fi
                    if (( _grab_ccid )); then _codex_client_id="$_tok"; _grab_ccid=0; continue; fi
                    if (( _grab_cbear )); then _codex_bearer="$_tok"; _grab_cbear=0; continue; fi
                    case "$_tok" in
                        auth=*)            _auth="${_tok#auth=}" ;;
                        profile=*)         _profile="${_tok#profile=}" ;;
                        risk=*)            _risk="${_tok#risk=}" ;;
                        --codex-client-id) _grab_ccid=1 ;;
                        --codex-bearer)    _grab_cbear=1 ;;
                        *)                 _extras="${_extras:+$_extras }$_tok" ;;
                    esac
            done

            [[ "$_profile" =~ ^[a-z0-9][a-z0-9-]*$ ]] \
                || { log_fail "Invalid MCP profile for $_name: $_profile"; return 1; }
            case "$_risk" in
                read|local-write|external-write) ;;
                *) log_fail "Invalid MCP risk for $_name: $_risk"; return 1 ;;
            esac
            (( _include_all )) || mcp_profile_enabled "$_profile" || continue

            jq -nc --arg n "$_name" --arg k "$_kind" --arg t "$_transport" \
                   --arg cmd "$_cmd" --arg url "$_url" --arg auth "$_auth" \
                   --arg ccid "$_codex_client_id" --arg cbear "$_codex_bearer" \
                   --arg profile "$_profile" --arg risk "$_risk" --arg ex "$_extras" \
                '{name:$n, kind:$k, transport:$t, cmd:$cmd, url:$url, auth:$auth,
                  codex_client_id:$ccid, codex_bearer:$cbear, profile:$profile,
                  risk:$risk, extras:$ex}'
        done < "$_file"
    done < <(overlay_package_files "mcp-servers.txt")
    return 0
}

mcp_registry_validate() {
    mcp_servers_each --all >/dev/null
}

# mcp_url_substitute URL — expand every {VAR} placeholder from the
# environment (env files are sourced globally by this library). On success
# prints the substituted URL and returns 0. On the first unset VAR prints
# that variable's NAME instead and returns 1 — callers decide whether a
# missing key means skip (claude/cursor) or emit-inert (codex).
mcp_url_substitute() {
    local _url="$1" _ph _val
    while [[ "$_url" =~ \{([A-Za-z_][A-Za-z0-9_]*)\} ]]; do
        _ph="${BASH_REMATCH[1]}"; _val="${!_ph:-}"
        if [[ -z "$_val" ]]; then printf '%s' "$_ph"; return 1; fi
        _url="${_url//\{$_ph\}/$_val}"
    done
    printf '%s' "$_url"
    return 0
}

# Bundle package workers share the cache and install cleanup; keep reconciliation sequential.
export HOMEBREW_BUNDLE_NO_JOBS=1

# ensure_brewfile_taps FILE
# Trust AND tap every third-party tap referenced by a Brewfile so `brew
# bundle` can resolve its formulae/casks. Two distinct Homebrew refusals:
#  - untrusted tap → "Refusing to load formula ... from untrusted tap"
#    (gated by $HOMEBREW_REQUIRE_TAP_TRUST); fixed by `brew trust`.
#  - untapped tap → "No available formula ... This command requires the tap
#    ... tap it explicitly". Homebrew no longer auto-taps from a
#    fully-qualified `owner/repo/formula` name, and `brew bundle` can hit
#    formula resolution (e.g. the upgrade check for a same-named formula
#    already installed from core, like rtk) before its own `tap` directive
#    runs — so tap here, before the bundle, instead of relying on the
#    Brewfile's `tap` lines.
#
# The Brewfile is the single source of truth: taps come from both explicit
# `tap "owner/repo"` lines and the `owner/repo` prefix of three-part
# `brew`/`cask "owner/repo/formula"` references. Both `brew trust` and
# `brew tap` are idempotent, and we parse with awk rather than rg because rg
# is a cargo tool installed long after Homebrew during bootstrap.
ensure_brewfile_taps() {
    local brewfile="$1" _tap _has_trust=1
    [[ -f "$brewfile" ]] || return 0
    has brew || return 0
    # Older Homebrew has no `trust` subcommand — tap-only on those.
    brew trust --help >/dev/null 2>&1 || _has_trust=0

    while IFS= read -r _tap; do
        [[ -n "$_tap" ]] || continue
        if [[ "$_has_trust" == "1" ]]; then
            run_logged brew trust --tap "$_tap" || log_warn "Could not trust tap: $_tap"
        fi
        if ! brew tap | grep -qFx "$(echo "$_tap" | tr '[:upper:]' '[:lower:]')"; then
            run_logged brew tap "$_tap" || log_warn "Could not tap: $_tap — its packages will fail below"
        fi
    done < <(
        awk '
            /^[[:space:]]*tap[[:space:]]+"/ {
                match($0, /"[^"]+"/); print substr($0, RSTART+1, RLENGTH-2); next
            }
            /^[[:space:]]*(brew|cask)[[:space:]]+"[^"]+\/[^"]+\/[^"]+"/ {
                match($0, /"[^"]+"/); s = substr($0, RSTART+1, RLENGTH-2)
                if (split(s, a, "/") >= 3) print a[1] "/" a[2]
            }
        ' "$brewfile" | sort -u
    )
    return 0
}

### UTILITIES ###

has() {
    command -v "$1" >/dev/null 2>&1
}

ensure_dir() {
    [[ -d "$1" ]] || mkdir -p "$1"
}

download() {
    local url="$1" dest="$2"
    local _auth_header=""

    # GitHub API + asset downloads benefit from authentication: unauthenticated
    # limit is 60 req/hr per IP, authenticated is 5000/hr. Several install
    # scripts (codex, claude, cargo-binstall fallbacks) hit api.github.com or
    # release assets on github.com, and on shared NAT'd networks (CI, NVIDIA
    # GPU clusters) 60/hr is exhausted quickly. Inject Authorization for
    # GitHub-owned hosts only when GITHUB_TOKEN is set. The redirect chain
    # api.github.com → objects.githubusercontent.com stays within GitHub, so
    # forwarding the header on redirect (curl's default) is safe.
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        case "$url" in
            https://api.github.com/*|\
            https://github.com/*|\
            https://*.github.com/*|\
            https://*.githubusercontent.com/*)
                _auth_header="Authorization: Bearer $GITHUB_TOKEN"
                ;;
        esac
    fi

    if has curl; then
        if [[ -n "$_auth_header" ]]; then
            curl --retry 4 --retry-all-errors --retry-delay 2 \
                --connect-timeout 20 -fsSL -H "$_auth_header" "$url" -o "$dest"
        else
            curl --retry 4 --retry-all-errors --retry-delay 2 \
                --connect-timeout 20 -fsSL "$url" -o "$dest"
        fi
    elif has wget; then
        if [[ -n "$_auth_header" ]]; then
            wget -q --tries=4 --timeout=20 --header="$_auth_header" "$url" -O "$dest"
        else
            wget -q --tries=4 --timeout=20 "$url" -O "$dest"
        fi
    else
        die "Neither curl nor wget found — cannot download files"
    fi
}

run_logged() {
    log_debug "exec: $*"
    local _start=$SECONDS
    "$@" 2>&1 | sed 's/^/    /'
    local _rc=${PIPESTATUS[0]}
    if [[ "$DF_DEBUG" == "1" ]]; then
        log_debug "exit=$_rc elapsed=$(( SECONDS - _start ))s"
    fi
    return "$_rc"
}

_collect_process_tree() {
    local _pid="$1" _child _children=""
    if command -v pgrep >/dev/null 2>&1; then
        _children="$(pgrep -P "$_pid" 2>/dev/null || true)"
        for _child in $_children; do
            _collect_process_tree "$_child"
        done
    fi
    printf '%s\n' "$_pid"
}

_kill_process_tree() {
    local _pid="$1" _signal="$2" _process _processes
    if [[ "$_signal" == "KILL" && "${_DF_PROCESS_TREE_ROOT:-}" == "$_pid" ]]; then
        _processes="${_DF_PROCESS_TREE_PIDS:-$_pid}"
    else
        _processes="$(_collect_process_tree "$_pid")"
    fi
    if [[ "$_signal" == "TERM" ]]; then
        _DF_PROCESS_TREE_ROOT="$_pid"
        _DF_PROCESS_TREE_PIDS="$_processes"
    fi
    for _process in $_processes; do
        kill "-$_signal" "$_process" 2>/dev/null || true
    done
    if [[ "$_signal" == "KILL" ]]; then
        unset _DF_PROCESS_TREE_ROOT _DF_PROCESS_TREE_PIDS
    fi
}

run_bounded() {
    local _seconds="$1" _pid _watchdog _rc _marker
    shift
    _marker="$(mktemp "${TMPDIR:-/tmp}/dotfiles-bounded.XXXXXX")" || return 1
    rm -f "$_marker"
    "$@" &
    _pid=$!
    (
        sleep "$_seconds"
        kill -0 "$_pid" 2>/dev/null || exit 0
        : > "$_marker"
        _kill_process_tree "$_pid" TERM
        sleep 0.1
        _kill_process_tree "$_pid" KILL
    ) </dev/null >/dev/null 2>&1 &
    _watchdog=$!
    wait "$_pid" 2>/dev/null && _rc=0 || _rc=$?
    kill "$_watchdog" 2>/dev/null || true
    wait "$_watchdog" 2>/dev/null || true
    if [[ -e "$_marker" ]]; then
        rm -f "$_marker"
        return 124
    fi
    rm -f "$_marker"
    return "$_rc"
}

tool_entrypoint_healthy() {
    local _path="$1" _timeout="${DF_TOOL_SMOKE_TIMEOUT:-10}"
    [[ -x "$_path" ]] || return 1
    run_bounded "$_timeout" "$_path" --version </dev/null >/dev/null 2>&1 \
        || run_bounded "$_timeout" "$_path" --help </dev/null >/dev/null 2>&1
}

activate_homebrew() {
    local _brew="${DF_HOMEBREW_BIN:-}"
    [[ -n "$_brew" ]] || _brew="$(command -v brew 2>/dev/null || true)"
    if [[ -z "$_brew" && "$OS" == "darwin" ]]; then
        if [[ -x /opt/homebrew/bin/brew ]]; then
            _brew=/opt/homebrew/bin/brew
        elif [[ -x /usr/local/bin/brew ]]; then
            _brew=/usr/local/bin/brew
        fi
    elif [[ -z "$_brew" && "$OS" == "linux" && -x "$LOCAL_PLAT/brew/bin/brew" ]]; then
        _brew="$LOCAL_PLAT/brew/bin/brew"
    fi
    [[ -x "$_brew" ]] || return 1
    eval "$("$_brew" shellenv)" || return 1
    has brew
}

# qmd MCP daemon lifecycle (Linux / no-launchd path; macOS uses the launchd
# agent instead). The daemon mmaps native addons (sqlite-vec, node-llama-cpp,
# better-sqlite3). On an NFS home a global `npm install -g @tobilu/qmd` fails
# with EBUSY: deleting a file the daemon holds open silly-renames it to
# .nfsXXXX and keeps it until the fd closes, so npm can't unlink the old tree.
# node.sh stops the daemon around the upgrade; node.sh + memory.sh + the shell
# profiles start it. Shared here so the start command has one definition.
qmd_daemon_running() {
    # The daemonized process re-execs as ".../qmd.js mcp --http" (not
    # ".../qmd mcp ..."), so allow an optional non-space suffix after "qmd".
    # A bare "qmd mcp --http" pattern only matches the transient launcher.
    pgrep -f "qmd[^ ]* mcp --http" >/dev/null 2>&1
}

qmd_daemon_stop() {
    qmd_daemon_running || return 0
    pkill -TERM -f "qmd[^ ]* mcp --http" 2>/dev/null || true
    local _i
    _i=0
    while (( _i < 50 )); do
        qmd_daemon_running || return 0
        sleep 0.1
        (( _i++ )) || true
    done
    # Still holding fds after 5s — force it so NFS can reap the .nfs* files.
    pkill -KILL -f "qmd[^ ]* mcp --http" 2>/dev/null || true
    _i=0
    while (( _i < 20 )); do
        qmd_daemon_running || break
        sleep 0.1
        (( _i++ )) || true
    done
}

qmd_daemon_start() {
    has qmd || return 1
    qmd_daemon_running && return 0
    (qmd mcp --http --daemon >/dev/null 2>&1 &)
}

_qmd_daemon_healthy() {
    curl -fsS --max-time 2 http://localhost:8181/health 2>/dev/null \
        | grep -Eq '"status"[[:space:]]*:[[:space:]]*"ok"'
}

_qmd_wait_healthy() {
    local _i=0
    while (( _i < 150 )); do
        _qmd_daemon_healthy && return 0
        sleep 0.1
        (( _i++ )) || true
    done
    return 1
}

# Resolve LOCAL_PLAT from current $HOME/.local (handling symlinks) and the
# DF_USE_PLAT flag. Sets LOCAL_PLAT but does NOT touch derived vars — call
# _re_derive_plat_vars after this if anything else has changed.
_resolve_local_plat() {
    local _root="$HOME/.local"
    [[ -L "$_root" ]] && _root="$(readlink -f "$_root")"
    if [[ "${DF_USE_PLAT:-0}" == "1" ]]; then
        LOCAL_PLAT="$_root/$PLAT"
    else
        LOCAL_PLAT="$_root"
    fi
}

# Re-derive all PLAT-dependent variables from the current LOCAL_PLAT.
# Call this after LOCAL_PLAT changes (e.g. scratch symlink resolution,
# PLAT re-detection in bootstrap.sh).
_re_derive_plat_vars() {
    ARCH_BIN="$LOCAL_PLAT/bin"
    RUSTUP_HOME="$LOCAL_PLAT/rustup"
    CARGO_HOME="$LOCAL_PLAT/cargo"
    CARGO_TARGET_DIR="$LOCAL_PLAT/cargo-build"
    UV_TOOL_BIN_DIR="$ARCH_BIN"
    UV_TOOL_DIR="$LOCAL_PLAT/uv/tools"
    UV_PYTHON_INSTALL_DIR="$LOCAL_PLAT/uv/python"
    PYTHON_ENV="$LOCAL_PLAT/python"
    NVM_DIR="$LOCAL_PLAT/nvm"
    CONAN_HOME="$LOCAL_PLAT/conan2"
    # Go: GOBIN=ARCH_BIN lands `go install` binaries alongside cargo/uv ones
    # (no second bin dir on PATH). GOPATH + GOCACHE are PLAT-isolated so NFS-shared
    # homes don't collide; the build cache is per-arch by necessity.
    GOPATH="$LOCAL_PLAT/go"
    GOBIN="$ARCH_BIN"
    GOCACHE="$LOCAL_PLAT/go-build"
    ELAN_HOME="$LOCAL_PLAT/elan"
    JULIAUP_DEPOT_PATH="$LOCAL_PLAT/julia/juliaup"
    JULIA_DEPOT_PATH="$LOCAL_PLAT/julia/depot"
    export PLAT LOCAL_PLAT ARCH_BIN RUSTUP_HOME CARGO_HOME CARGO_TARGET_DIR \
           UV_TOOL_BIN_DIR UV_TOOL_DIR UV_PYTHON_INSTALL_DIR PYTHON_ENV NVM_DIR CONAN_HOME \
           GOPATH GOBIN GOCACHE ELAN_HOME JULIAUP_DEPOT_PATH JULIA_DEPOT_PATH
}

# Read a package list file, skipping blank lines and comments.
# Outputs one package name per line (strips trailing comments/args).
_read_package_list() {
    local file="$1"
    while IFS= read -r line; do
        [[ -z "$line" || "$line" == \#* ]] && continue
        printf '%s\n' "${line%% *}"
    done < "$file"
}

### AUTH HELPERS (NETRC / CURLRC) ###
#
# Generic block-level upsert/remove for ~/.netrc and option-level upsert for
# ~/.curlrc. Service definitions (which hosts use which credentials) live in
# the caller — these helpers are host-agnostic so overlays can wire their
# own hosts (e.g. dotfiles-nvidia plugs in urm.nvidia.com + artifactory.nvidia.com).
#
# netrc semantics handled: `machine <host>` blocks with indented `login` /
# `password` continuation lines, plus a top-level `default` block left alone.
# `macdef` blocks are not specifically handled — don't mix them with managed
# entries.

# Strip any existing `machine $host` block from the netrc body on stdin.
# Continuation lines (indented login/password) are dropped along with the
# `machine` header. Other `machine`/`default` blocks pass through verbatim.
_netrc_strip_host() {
    awk -v target="$1" '
        BEGIN { skip = 0 }
        /^machine[[:space:]]+/ {
            if ($2 == target) { skip = 1; next }
            skip = 0
            print
            next
        }
        /^default([[:space:]]|$)/ { skip = 0; print; next }
        !skip { print }
    '
}

# Upsert a netrc entry for host $1 with login $2 / password $3. Preserves
# every other block. Atomic via tmpfile + rename. File ends up at chmod 600.
_netrc_upsert() {
    local host="$1" user="$2" token="$3"
    local file="$HOME/.netrc"
    local tmp="${file}.tmp.$$"

    [[ -n "$host" && -n "$user" && -n "$token" ]] || return 1

    if [[ -f "$file" ]]; then
        _netrc_strip_host "$host" < "$file" > "$tmp" || { rm -f "$tmp"; return 1; }
    else
        : > "$tmp"
    fi

    {
        printf 'machine %s\n' "$host"
        printf '  login %s\n' "$user"
        printf '  password %s\n' "$token"
    } >> "$tmp"

    chmod 600 "$tmp"
    mv -f "$tmp" "$file"
}

# Remove the netrc entry for host $1. No-op if file or entry is absent.
# If only whitespace remains afterwards, deletes the file.
_netrc_remove() {
    local host="$1"
    local file="$HOME/.netrc"
    local tmp="${file}.tmp.$$"

    [[ -n "$host" ]] || return 1
    [[ -f "$file" ]] || return 0

    _netrc_strip_host "$host" < "$file" > "$tmp" || { rm -f "$tmp"; return 1; }
    chmod 600 "$tmp"
    mv -f "$tmp" "$file"

    if ! grep -q '[^[:space:]]' "$file" 2>/dev/null; then
        rm -f "$file"
    fi
}

# Print the `login` recorded for host $1; empty when the host has no block.
# Lets callers detect drift between a netrc entry and the credential source it
# was written from (netrc keeps whatever login it was last given).
_netrc_login() {
    local host="$1" file="$HOME/.netrc"
    [[ -n "$host" && -f "$file" ]] || return 0
    awk -v target="$host" '
        /^machine[[:space:]]+/ {
            inblock = ($2 == target)
            if (inblock)
                for (i = 3; i < NF; i++) if ($i == "login") { print $(i+1); exit }
            next
        }
        /^default([[:space:]]|$)/ { inblock = 0; next }
        inblock {
            for (i = 1; i < NF; i++) if ($i == "login") { print $(i+1); exit }
        }
    ' "$file"
}

# Idempotently add option $1 (e.g. "--netrc", "--location") to ~/.curlrc.
# Other options pass through untouched. Creates the file at chmod 600 if
# missing. Match is anchored — `--netrc` will not be confused with
# `--netrc-file` or `--netrc-optional`.
_curlrc_ensure() {
    local opt="$1"
    local file="$HOME/.curlrc"

    [[ -n "$opt" ]] || return 1
    if [[ -f "$file" ]] && grep -qE "^${opt}([[:space:]]|$)" "$file"; then
        return 0
    fi
    printf '%s\n' "$opt" >> "$file"
    chmod 600 "$file"
}
