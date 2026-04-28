#!/usr/bin/env bash
# install/macos-quick-actions.sh - install Finder right-click Quick Actions
#
# Deploys every *.workflow bundle under install/macos-quick-actions/ into
# ~/Library/Services/. These show up as top-level entries in Finder's
# right-click menu (under "Quick Actions") and can also be bound to a
# keyboard shortcut via System Settings → Keyboard → Keyboard Shortcuts → Services.
#
# Bundles are plain XML plists — inspect or tweak with:
#   plutil -p "<bundle>/Contents/Info.plist"
#   plutil -p "<bundle>/Contents/document.wflow"
#
# Idempotent: diff source vs installed; only re-copy on change. After any
# change, `pbs -flush` is called to refresh the system Services cache so the
# new/updated action appears immediately (no logout required).
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

log_section "macOS Quick Actions"

[[ "$OS" == "darwin" ]] || { log_info "Not macOS — skipping"; exit 0; }

_SRC_DIR="$DF_ROOT/install/macos-quick-actions"
_DST_DIR="$HOME/Library/Services"

[[ -d "$_SRC_DIR" ]] || { log_warn "No source dir $_SRC_DIR — skipping"; exit 0; }

ensure_dir "$_DST_DIR"

_changed=0

# Iterate source .workflow bundles. Null-delimited so names with spaces work.
while IFS= read -r -d '' _src; do
    _name="$(basename "$_src")"
    _dst="$_DST_DIR/$_name"

    if [[ -d "$_dst" ]]; then
        # diff -r exits non-zero on any content or structural difference
        if diff -r -q "$_src" "$_dst" >/dev/null 2>&1; then
            log_okay "$_name already up to date"
            continue
        fi
        log_info "Updating $_name"
        rm -rf "$_dst"
    else
        log_info "Installing $_name"
    fi

    cp -R "$_src" "$_dst"
    # Strip extended attributes that macOS adds during copy (quarantine, etc.)
    # so the bundle is byte-identical to source for future diff checks.
    xattr -cr "$_dst" 2>/dev/null || true
    log_okay "$_name installed → $_dst"
    _changed=1
done < <(find "$_SRC_DIR" -maxdepth 1 -type d -name '*.workflow' -print0)

# Refresh the Services cache so new/changed actions appear without logout.
if [[ "$_changed" == "1" ]]; then
    log_info "Flushing Services cache (pbs -flush)"
    /System/Library/CoreServices/pbs -flush >/dev/null 2>&1 || true
    log_okay "Services cache flushed"
fi

log_okay "Quick Actions configured"
log_info "Enable/rebind in System Settings → Keyboard → Keyboard Shortcuts → Services"
