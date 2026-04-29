#!/usr/bin/env bash
# install/blender-mcp.sh - install the blender-mcp Blender addon
#
# Downloads addon.py from github.com/ahujasid/blender-mcp, places it in the
# user's Blender scripts/addons directory, and enables it via a headless
# Blender invocation. Skips gracefully if Blender is not installed.
#
# The MCP *server* side is wired up separately via packages/claude-mcp.txt
# (`blender stdio cmd: uvx blender-mcp`). This script handles only the
# Blender-side addon, which must live inside Blender's own scripts/addons
# directory and be toggled on in user preferences.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

log_section "Blender MCP addon"

# Locate blender. The macOS cask installs /Applications/Blender.app but does
# not put `blender` on PATH, so fall back to the app bundle's executable.
_BLENDER=""
if has blender; then
    _BLENDER="$(command -v blender)"
elif [[ -x /Applications/Blender.app/Contents/MacOS/Blender ]]; then
    _BLENDER="/Applications/Blender.app/Contents/MacOS/Blender"
fi

if [[ -z "$_BLENDER" ]]; then
    log_okay "Blender not installed — skipping blender-mcp addon"
    exit 0
fi
log_info "Blender: $_BLENDER"

# Detect major.minor (e.g. "4.2") — Blender stores per-version config dirs
_VERSION="$("$_BLENDER" --version 2>/dev/null \
    | awk '/^Blender/ {split($2, v, "."); printf "%s.%s", v[1], v[2]; exit}')"
if [[ -z "$_VERSION" ]]; then
    log_warn "Could not detect Blender version — skipping"
    exit 0
fi
log_info "Blender version: $_VERSION"

# Per-OS user addons dir
case "$OS" in
    darwin) _ADDON_DIR="$HOME/Library/Application Support/Blender/$_VERSION/scripts/addons" ;;
    linux)  _ADDON_DIR="$HOME/.config/blender/$_VERSION/scripts/addons" ;;
    *)      log_warn "Unsupported OS for Blender addon install: $OS"; exit 0 ;;
esac
ensure_dir "$_ADDON_DIR"

# Install as blender_mcp.py so the module name is unique (upstream filename
# is the generic `addon.py`, which collides with other addons named the same)
_ADDON_URL="https://raw.githubusercontent.com/ahujasid/blender-mcp/main/addon.py"
_ADDON_FILE="$_ADDON_DIR/blender_mcp.py"

log_info "Downloading addon.py → $_ADDON_FILE"
_TMP="$(mktemp)"
if ! download "$_ADDON_URL" "$_TMP"; then
    log_warn "Failed to download $_ADDON_URL — skipping"
    rm -f "$_TMP"
    exit 0
fi
mv "$_TMP" "$_ADDON_FILE"
log_okay "Addon file installed"

# Enable the addon and persist in user prefs. Running blender in --background
# mode writes to ~/Library/... (macOS) or ~/.config/... (Linux) userpref.blend.
log_info "Enabling addon in Blender user preferences"
if "$_BLENDER" --background --python-expr "
import bpy
bpy.ops.preferences.addon_enable(module='blender_mcp')
bpy.ops.wm.save_userpref()
" >/dev/null 2>&1; then
    log_okay "Addon enabled — look for 'BlenderMCP' tab in the 3D view sidebar (N)"
else
    log_warn "Could not auto-enable — toggle manually in Blender: Edit > Preferences > Add-ons > 'Interface: Blender MCP'"
fi
