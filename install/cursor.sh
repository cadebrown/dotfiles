#!/usr/bin/env bash
# install/cursor.sh - symlink Cursor settings from chezmoi-managed source + install extensions
#
# Settings source of truth: ~/.config/cursor/{settings,keybindings}.json
# (deployed by chezmoi from home/dot_config/cursor/)
#
# On macOS: symlinks from ~/Library/Application Support/Cursor/User/
# On Linux: symlinks from ~/.config/Cursor/User/
#
# Edits made in Cursor's UI go through the symlink and land directly in
# the dotfiles-managed copy — no manual sync needed.
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

log_section "Cursor"

### Settings symlinks ###

_SRC_DIR="$HOME/.config/cursor"
_FILES=(settings.json keybindings.json)

# Determine Cursor's native config dir
case "$OS" in
    darwin) _CURSOR_DIR="$HOME/Library/Application Support/Cursor/User" ;;
    linux)  _CURSOR_DIR="$HOME/.config/Cursor/User" ;;
    *)      die "Unsupported OS: $OS" ;;
esac

if [[ ! -d "$_SRC_DIR" ]]; then
    log_warn "Source dir $_SRC_DIR not found — run chezmoi apply first"
    exit 0
fi

ensure_dir "$_CURSOR_DIR"

for _f in "${_FILES[@]}"; do
    _src="$_SRC_DIR/$_f"
    _dst="$_CURSOR_DIR/$_f"

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
        # Back up existing file before replacing with symlink
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

unset _SRC_DIR _CURSOR_DIR _FILES _f _src _dst _cur _bak

### Extensions ###

log_section "Cursor extensions"

if ! has cursor; then
    log_warn "cursor CLI not found — skipping extensions"
    exit 0
fi

EXT_TXT="$DF_PACKAGES/cursor-extensions.txt"
[[ -f "$EXT_TXT" ]] || { log_warn "No cursor-extensions.txt at $EXT_TXT — skipping"; exit 0; }

# Get currently installed extensions once
_installed="$(cursor --list-extensions 2>/dev/null || true)"

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
    if cursor --install-extension "$ext" --force >/dev/null 2>&1; then
        log_okay "  installed $ext"
        (( _ok++ )) || true
    else
        log_warn "  fail  $ext"
        (( _fail++ )) || true
    fi
done < "$EXT_TXT"

log_okay "Cursor extensions: ${_ok} installed, ${_skip} already present, ${_fail} failed"
