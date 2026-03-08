#!/usr/bin/env bash
# install/claude.sh - install Claude Code CLI (Linux) and plugins (all platforms)
#
# macOS: Claude Code is installed via Homebrew cask (packages/Brewfile).
#        This script only installs plugins on macOS.
#
# Linux: Downloads the native binary from Anthropic's release bucket and places
#        it in $ARCH_BIN (PLAT-isolated for shared home directory safety).
#        URL pattern derived from the official installer: https://claude.ai/install.sh
#
# To update the CLI on Linux, re-run this script — it always downloads latest.
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

### LINUX: native binary install ###

if [[ "$OS" == "linux" ]]; then
    log_section "Claude Code CLI (Linux native binary)"

    # Map our normalized arch (aarch64/x86_64) to Anthropic's platform naming (arm64/x64).
    # _lib.sh normalizes arm64→aarch64; here we reverse for the GCS path.
    case "$ARCH" in
        aarch64) _plat_arch="arm64" ;;
        x86_64)  _plat_arch="x64" ;;
        *) die "Unsupported architecture: $ARCH" ;;
    esac

    # Detect musl libc (Alpine, static builds) vs glibc (Debian, Ubuntu, RHEL)
    if ldd --version 2>&1 | grep -q musl; then
        _platform="linux-${_plat_arch}-musl"
    else
        _platform="linux-${_plat_arch}"
    fi

    # Anthropic's release bucket — same source as https://claude.ai/install.sh
    _BUCKET="https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases"

    log_info "Fetching latest version tag..."
    _version=$(curl -fsSL "$_BUCKET/latest")
    log_info "Latest: $_version"

    _dest="$ARCH_BIN/claude"
    _url="$_BUCKET/$_version/$_platform/claude"

    # Skip if already on this version
    if [[ -x "$_dest" ]] && "$_dest" --version 2>/dev/null | grep -qF "$_version"; then
        log_ok "claude $_version already installed at $_dest"
    else
        log_info "Downloading claude $_version for $_platform..."
        ensure_dir "$ARCH_BIN"
        download "$_url" "$_dest"
        chmod +x "$_dest"
        log_ok "Installed claude $_version → $_dest"
    fi

    unset _plat_arch _platform _BUCKET _version _dest _url
fi

### PLUGINS (all platforms) ###

log_section "Claude Code plugins"

has claude || { log_warn "claude not found — skipping plugins"; exit 0; }

PLUGINS_TXT="$PACKAGES_DIR/claude-plugins.txt"
[[ -f "$PLUGINS_TXT" ]] || { log_warn "No claude-plugins.txt at $PLUGINS_TXT — skipping"; exit 0; }

_ok=0 _skip=0 _fail=0

while IFS= read -r line; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    plugin="${line%% *}"

    log_info "  $plugin"
    output=$(claude plugin install "$plugin" 2>&1) && status=0 || status=$?

    if [[ $status -eq 0 ]]; then
        log_ok "  installed $plugin"
        (( _ok++ )) || true
    elif echo "$output" | grep -qi "already installed\|already enabled"; then
        log_info "  skip  $plugin (already installed)"
        (( _skip++ )) || true
    else
        log_warn "  fail  $plugin: $output"
        (( _fail++ )) || true
    fi
done < "$PLUGINS_TXT"

log_ok "Claude plugins: ${_ok} installed, ${_skip} already present, ${_fail} failed"
