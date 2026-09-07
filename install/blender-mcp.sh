#!/usr/bin/env bash
# Install the addon bundled with the same pinned release as the MCP server.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

log_section "Blender MCP addon"
_RELEASE=1.9.1
_WHEEL_URL=https://files.pythonhosted.org/packages/98/93/3e8656c0436c7df6397775064cc05261910c05be009c598d38dda0eda816/blender_mcp-1.9.1-py3-none-any.whl
_WHEEL_SHA=ede3aed34926f77142b8f00ee4f8544f68067d2dc747da8295d1c456171355b2
_ADDON_SHA=f43469c8518c7021e0060e32cfe52e3beb126b0f62fbae7293106642a3ebda89

_BLENDER="${BLENDER_BIN:-}"
if [[ -z "$_BLENDER" ]] && has blender; then
    _BLENDER="$(command -v blender)"
elif [[ -z "$_BLENDER" && -x /Applications/Blender.app/Contents/MacOS/Blender ]]; then
    _BLENDER=/Applications/Blender.app/Contents/MacOS/Blender
fi
[[ -x "$_BLENDER" ]] || die "Blender is not installed; set DF_DO_BLENDER_MCP=0 or install Blender"
_VERSION="$("$_BLENDER" --version | awk '/^Blender/ && !seen++ {split($2, v, "."); printf "%s.%s", v[1], v[2]}')"
[[ "$_VERSION" =~ ^[0-9]+[.][0-9]+$ ]] || die "Could not detect Blender version"
case "$OS" in
    darwin) _USER_DIR="$HOME/Library/Application Support/Blender/$_VERSION" ;;
    linux)  _USER_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/blender/$_VERSION" ;;
    *) die "Unsupported OS: $OS" ;;
esac
_ADDON_DIR="$_USER_DIR/scripts/addons"
_ADDON_FILE="$_ADDON_DIR/blender_mcp.py"
_STATE_DIR="$LOCAL_PLAT/share/blender-mcp/$_VERSION"
ensure_dir "$_ADDON_DIR"
ensure_dir "$_STATE_DIR/backups"

_sha256() {
    if has sha256sum; then sha256sum "$1" | awk '{print $1}'
    else shasum -a 256 "$1" | awk '{print $1}'; fi
}
_backup() {
    [[ -f "$1" ]] || return 0
    local _target
    _target="$_STATE_DIR/backups/$(basename "$1").$(_sha256 "$1")"
    [[ -f "$_target" ]] || cp -p "$1" "$_target"
}

_TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$_TMP_DIR"' EXIT
if [[ ! -f "$_ADDON_FILE" ]] || [[ "$(_sha256 "$_ADDON_FILE")" != "$_ADDON_SHA" ]]; then
    has unzip || die "unzip is required to extract the release addon"
    download "$_WHEEL_URL" "$_TMP_DIR/release.whl" || die "Could not download Blender MCP $_RELEASE"
    [[ "$(_sha256 "$_TMP_DIR/release.whl")" == "$_WHEEL_SHA" ]] || die "Blender MCP release checksum mismatch"
    unzip -p "$_TMP_DIR/release.whl" blender_mcp/bundled/addon.py > "$_TMP_DIR/blender_mcp.py"
    [[ "$(_sha256 "$_TMP_DIR/blender_mcp.py")" == "$_ADDON_SHA" ]] || die "Blender MCP addon checksum mismatch"
    _backup "$_ADDON_FILE"
    mv "$_TMP_DIR/blender_mcp.py" "$_ADDON_FILE"
    log_okay "Installed Blender MCP $_RELEASE bundled addon"
else
    log_okay "Blender MCP $_RELEASE addon checksum matches"
fi

_backup "$_USER_DIR/config/userpref.blend"
cat > "$_TMP_DIR/enable.py" <<'PY'
import bpy

changed = 'blender_mcp' not in bpy.context.preferences.addons
if changed:
    result = bpy.ops.preferences.addon_enable(module='blender_mcp')
    if result != {'FINISHED'}:
        raise RuntimeError(f'Addon enable failed: {result}')
prefs = bpy.context.preferences.addons['blender_mcp'].preferences
if prefs.telemetry_consent:
    prefs.telemetry_consent = False
    changed = True
if changed:
    bpy.ops.wm.save_userpref()
assert not prefs.telemetry_consent
print('BLENDER_MCP_READY telemetry=false')
PY
DISABLE_TELEMETRY=true "$_BLENDER" --background --disable-autoexec --python-exit-code 1 \
    --python "$_TMP_DIR/enable.py" > "$_TMP_DIR/enable.log" 2>&1 || {
    tail -30 "$_TMP_DIR/enable.log" >&2
    die "Could not configure Blender MCP preferences"
}
DISABLE_TELEMETRY=true "$_BLENDER" --background --disable-autoexec --python-exit-code 1 \
    --python-expr "import bpy; assert 'blender_mcp' in bpy.context.preferences.addons; assert not bpy.context.preferences.addons['blender_mcp'].preferences.telemetry_consent" \
    > "$_TMP_DIR/verify.log" 2>&1 || {
    tail -30 "$_TMP_DIR/verify.log" >&2
    die "Blender MCP preference verification failed"
}
cat > "$_STATE_DIR/install-receipt.json" <<EOF
{"schema":1,"release":"$_RELEASE","wheel_sha256":"$_WHEEL_SHA","addon_sha256":"$_ADDON_SHA","telemetry_consent":false,"blender":"$_VERSION","source":"$_WHEEL_URL"}
EOF
log_okay "Addon enabled; telemetry disabled; existing preferences preserved"
log_info "The live MCP bridge needs GUI Blender. Headless bpy rendering works independently."
