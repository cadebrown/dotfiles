#!/usr/bin/env bash
# install/vscode.sh - install VS Code extensions from vscode-extensions.txt
#
# Subcommands:
#   install (default)      — install extensions from vscode-extensions.txt
#   sync-extensions|sync   — union VS Code's installed extensions back into vscode-extensions.txt
#
# Note: settings.json is NOT tracked — it contains embedded credentials
# (cmake.configureEnvironment GitLab token). Extensions only.
#
# The VS Code application itself is user-managed (not in Brewfile).
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

_CMD="${1:-install}"

### sync-extensions: union installed extensions back into vscode-extensions.txt ###

if [[ "$_CMD" == "sync-extensions" || "$_CMD" == "sync" ]]; then
    log_section "VS Code extension sync"

    if ! has code; then
        die "code CLI not found — run 'Shell Command: Install code command in PATH' from the VS Code command palette"
    fi

    EXT_TXT="$DF_PACKAGES/vscode-extensions.txt"
    [[ -f "$EXT_TXT" ]] || die "No vscode-extensions.txt at $EXT_TXT"

    # Get installed extensions from VS Code
    _vscode_exts="$(code --list-extensions 2>/dev/null)" \
        || die "Failed to list VS Code extensions"

    # Read existing entries (skip comments and blanks)
    _file_exts="$(grep -v '^\s*#' "$EXT_TXT" | grep -v '^\s*$' || true)"

    # Union both sets
    _union="$(printf '%s\n%s\n' "$_file_exts" "$_vscode_exts" | sort -u)"

    # Find what's new
    _new="$(comm -23 <(echo "$_union") <(echo "$_file_exts" | sort -u))"

    if [[ -z "$_new" ]]; then
        log_okay "No new extensions to add"
        exit 0
    fi

    # Preserve comment header (lines starting with #), then write sorted union
    _header="$(grep '^\s*#' "$EXT_TXT" || true)"
    printf '%s\n%s\n' "$_header" "$_union" > "$EXT_TXT"

    _count="$(echo "$_new" | wc -l | tr -d ' ')"
    log_info "Added $_count new extension(s):"
    while IFS= read -r ext; do
        log_info "  + $ext"
    done <<< "$_new"

    # Show the diff
    git -C "$DF_ROOT" diff -- packages/vscode-extensions.txt 2>/dev/null || true
    log_okay "Run 'chezmoi apply' then commit when ready"
    exit 0
fi

if [[ "$_CMD" != "install" ]]; then
    die "Usage: vscode.sh [install|sync-extensions]"
fi

log_section "VS Code extensions"

if ! has code; then
    log_warn "code CLI not found — skipping extensions (run 'Shell Command: Install code command in PATH' from VS Code)"
    exit 0
fi

EXT_TXT="$DF_PACKAGES/vscode-extensions.txt"
[[ -f "$EXT_TXT" ]] || { log_warn "No vscode-extensions.txt at $EXT_TXT — skipping"; exit 0; }

# Get currently installed extensions once
_installed="$(code --list-extensions 2>/dev/null || true)"

_ok=0 _skip=0 _fail=0

while IFS= read -r line; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    ext="${line%% *}"

    if echo "$_installed" | grep -qxF "$ext"; then
        log_debug "  skip  $ext (already installed)"
        (( _skip++ )) || true
        continue
    fi

    log_info "  $ext"
    if code --install-extension "$ext" --force >/dev/null 2>&1; then
        log_okay "  installed $ext"
        (( _ok++ )) || true
    else
        log_warn "  fail  $ext"
        (( _fail++ )) || true
    fi
done < "$EXT_TXT"

log_okay "VS Code extensions: ${_ok} installed, ${_skip} already present, ${_fail} failed"
