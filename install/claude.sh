#!/usr/bin/env bash
# install/claude.sh - install Claude Code CLI and plugins
#
# Downloads the native binary from Anthropic's release bucket and places
# it in $ARCH_BIN (PLAT-isolated for shared home directory safety).
# Works on both macOS and Linux — no Homebrew cask needed.
#
# To update, re-run this script — it always downloads latest.
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

log_section "Claude Code"

### Binary install ###

# Map our normalized arch to Anthropic's platform naming
case "$ARCH" in
    aarch64) _plat_arch="arm64" ;;
    x86_64)  _plat_arch="x64" ;;
    *) die "Unsupported architecture: $ARCH" ;;
esac

# Build platform string
if [[ "$OS" == "darwin" ]]; then
    _platform="darwin-${_plat_arch}"
elif ldd --version 2>&1 | grep -q musl; then
    _platform="linux-${_plat_arch}-musl"
else
    _platform="linux-${_plat_arch}"
fi

_BUCKET="https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases"

log_info "Fetching latest version tag..."
_version=$(curl -fsSL "$_BUCKET/latest")
log_info "Latest: $_version"

_dest="$ARCH_BIN/claude"

# Skip if already on this version
if [[ -x "$_dest" ]] && "$_dest" --version 2>/dev/null | grep -qF "$_version"; then
    log_okay "claude $_version already installed at $_dest"
else
    # Download to a temp file in the same dir, then atomically rename.
    # Writing directly to $_dest fails with curl error 23 on network-mounted
    # filesystems when an existing binary is already open/executing.
    _tmp="${_dest}.tmp.$$"
    # shellcheck disable=SC2064
    trap "rm -f '$_tmp'" EXIT

    log_info "Downloading claude $_version for $_platform..."
    ensure_dir "$ARCH_BIN"

    _manifest=$(curl -fsSL "$_BUCKET/$_version/manifest.json")
    if has jq; then
        _checksum=$(echo "$_manifest" | jq -r ".platforms[\"$_platform\"].checksum // empty")
    else
        # Fallback: extract checksum with bash regex
        if [[ $_manifest =~ \"$_platform\"[^}]*\"checksum\"[[:space:]]*:[[:space:]]*\"([a-f0-9]{64})\" ]]; then
            _checksum="${BASH_REMATCH[1]}"
        else
            _checksum=""
        fi
    fi

    download "$_BUCKET/$_version/$_platform/claude" "$_tmp"
    chmod +x "$_tmp"

    # Verify checksum if we got one
    if [[ -n "$_checksum" ]]; then
        if [[ "$OS" == "darwin" ]]; then
            _actual=$(shasum -a 256 "$_tmp" | cut -d' ' -f1)
        else
            _actual=$(sha256sum "$_tmp" | cut -d' ' -f1)
        fi
        if [[ "$_actual" != "$_checksum" ]]; then
            rm -f "$_tmp"
            die "Checksum mismatch for claude $_version ($_platform)"
        fi
        log_okay "Checksum verified"
    fi

    mv -f "$_tmp" "$_dest"
    trap - EXIT
    log_okay "Installed claude $_version → $_dest"
fi

unset _plat_arch _platform _BUCKET _version _dest _tmp _checksum _actual _manifest

### PLUGINS (all platforms) ###

log_section "Claude Code plugins"

has claude || { log_warn "claude not found — skipping plugins"; exit 0; }

PLUGINS_TXT="$DF_PACKAGES/claude-plugins.txt"
[[ -f "$PLUGINS_TXT" ]] || { log_warn "No claude-plugins.txt at $PLUGINS_TXT — skipping"; exit 0; }

_ok=0 _skip=0 _fail=0

while IFS= read -r line; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    plugin="${line%% *}"

    log_info "  $plugin"
    output=$(claude plugin install "$plugin" 2>&1) && status=0 || status=$?

    if [[ $status -eq 0 ]]; then
        log_okay "  installed $plugin"
        (( _ok++ )) || true
    elif echo "$output" | grep -qi "already installed\|already enabled"; then
        log_info "  skip  $plugin (already installed)"
        (( _skip++ )) || true
    else
        log_warn "  fail  $plugin: $output"
        (( _fail++ )) || true
    fi
done < "$PLUGINS_TXT"

log_okay "Claude plugins: ${_ok} installed, ${_skip} already present, ${_fail} failed"

### MCP SERVERS (all platforms) ###

log_section "Claude Code MCP servers"

MCP_TXT="$DF_PACKAGES/claude-mcp.txt"
[[ -f "$MCP_TXT" ]] || { log_warn "No claude-mcp.txt at $MCP_TXT — skipping"; exit 0; }

_ok=0 _skip=0 _fail=0

while IFS= read -r line; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    # Parse: <name> <transport> <url>  OR  <name> stdio cmd: <command...>
    _name="${line%% *}"; _rest="${line#* }"
    _transport="${_rest%% *}"

    if claude mcp list 2>/dev/null | grep -qE "^$_name\b"; then
        log_info "  skip  $_name (already registered)"
        (( _skip++ )) || true
        continue
    fi

    if [[ "$_transport" == "stdio" && "$_rest" == *"cmd: "* ]]; then
        # Stdio format: <name> stdio cmd: <command...>
        _cmd="${_rest#*cmd: }"
        log_info "  $_name (stdio) → $_cmd"
        # shellcheck disable=SC2086
        if claude mcp add --scope user "$_name" -- $_cmd 2>/dev/null; then
            log_okay "  registered $_name"
            (( _ok++ )) || true
        else
            log_warn "  fail  $_name"
            (( _fail++ )) || true
        fi
    else
        # HTTP/SSE format: <name> <transport> <url>
        _url="${_rest#* }"
        log_info "  $_name ($_transport) → $_url"
        if claude mcp add --transport "$_transport" --scope user "$_name" "$_url" 2>/dev/null; then
            log_okay "  registered $_name"
            (( _ok++ )) || true
        else
            log_warn "  fail  $_name"
            (( _fail++ )) || true
        fi
    fi
done < "$MCP_TXT"

log_okay "MCP servers: ${_ok} registered, ${_skip} already present, ${_fail} failed"
