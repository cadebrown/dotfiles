#!/usr/bin/env bash
# install/vscode.sh - link VS Code settings + install extensions
#
# Subcommands:
#   install (default)      — link settings, install extensions from vscode-extensions.txt
#   sync-extensions|sync   — union VS Code's installed extensions back into vscode-extensions.txt
#
# Settings live in chezmoi at ~/.config/vscode/ and are symlinked into VS Code's
# native User dir, the same shape as install/cursor.sh. Credentials never enter
# the repo: `cmake.configureEnvironment` holds `${env:GITLAB_ACCESS_TOKEN}` /
# `${env:GITLAB_USER}` references, which CMake Tools expands from the process
# environment — the values come from ~/.gitlab.env (auth.sh, chmod 600, sourced
# by the shell profile along with every other ~/.<service>.env).
#
# `update.mode` stays "none" on purpose: the app is a Homebrew cask, and letting
# it self-update would desync brew's receipt. homebrew.sh's greedy sweep is the
# update path.
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

    # Get installed extensions from VS Code. Over Remote-SSH the CLI prefixes a
    # banner line ("Extensions installed on SSH: <host>:"), so keep only IDs.
    _vscode_exts="$(code --list-extensions 2>/dev/null | grep -E '^[A-Za-z0-9][A-Za-z0-9_-]*\.[A-Za-z0-9][A-Za-z0-9_-]*$' || true)"
    [[ -n "$_vscode_exts" ]] || die "Failed to list VS Code extensions"

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

### Settings symlinks ###

log_section "VS Code"

_SRC_DIR="$HOME/.config/vscode"
_FILES=(settings.json keybindings.json)

case "$OS" in
    darwin) _CODE_DIR="$HOME/Library/Application Support/Code/User" ;;
    linux)  _CODE_DIR="$HOME/.config/Code/User" ;;
    *)      die "Unsupported OS: $OS" ;;
esac

if [[ ! -d "$_SRC_DIR" ]]; then
    log_warn "Source dir $_SRC_DIR not found — run chezmoi apply first"
else
    ensure_dir "$_CODE_DIR"

    for _f in "${_FILES[@]}"; do
        _src="$_SRC_DIR/$_f"
        _dst="$_CODE_DIR/$_f"

        if [[ ! -f "$_src" ]]; then
            log_debug "Source $_src not found — skipping"
            continue
        fi

        if [[ -L "$_dst" ]]; then
            _cur="$(readlink "$_dst")"
            if [[ "$_cur" == "$_src" ]]; then
                log_okay "$_f already linked"
                continue
            else
                log_info "Updating symlink: $_f (was → $_cur)"
                ln -sfn "$_src" "$_dst"
                log_okay "$_f re-linked → $_src"
            fi
        elif [[ -f "$_dst" ]]; then
            _bak="${_dst}.bak.$(date +%Y%m%d%H%M%S)"
            mv "$_dst" "$_bak"
            log_info "Backed up $_f → $_bak"
            ln -sfn "$_src" "$_dst"
            log_okay "$_f linked → $_src"
        else
            ln -sfn "$_src" "$_dst"
            log_okay "$_f linked → $_src"
        fi
    done
fi

unset _SRC_DIR _CODE_DIR _FILES _f _src _dst _cur _bak

### Extensions ###

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

# Upgrades go through the editor's own bulk pass, never a per-extension
# `--install-extension --force`: forcing a reinstall re-resolves every ID
# against the marketplace, which fails for extensions VS Code now bundles
# (github.copilot-chat) even though they are current.
if [[ "${DF_MODE:-}" == "upgrade" ]]; then
    log_info "Updating installed extensions"
    code --update-extensions >/dev/null 2>&1 || \
        log_warn "Extension update pass failed — run 'code --update-extensions'"
fi

log_okay "VS Code extensions: ${_ok} installed, ${_skip} already present, ${_fail} failed"
