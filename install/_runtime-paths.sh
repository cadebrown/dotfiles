#!/usr/bin/env bash
# Path contract shared by installers and frequently invoked agent launchers.
# Keep this free of installer setup, credentials, and compiler environment.

_normalize_plat_layout() {
    case "${DF_USE_PLAT:-0}" in
        1|true|yes|on|TRUE|YES|ON) DF_USE_PLAT=1 ;;
        *) DF_USE_PLAT=0 ;;
    esac
}

_detect_plat() {
    local _spec_root="$1/install/plat" _os _directory _check
    PLAT=""
    [[ -d "$_spec_root" ]] || return 0
    if [[ "${DF_PLAT:-auto}" != auto ]]; then
        _check="$_spec_root/$DF_PLAT/.plat_check.sh"
        [[ -f "$_check" ]] && /bin/sh "$_check" 2>/dev/null || return 1
        PLAT="$DF_PLAT"
        return 0
    fi
    _os="$(uname -s)"
    while IFS= read -r _directory; do
        _check="$_directory/.plat_check.sh"
        if [[ -f "$_check" ]] && /bin/sh "$_check" 2>/dev/null; then
            _directory="${_directory%/}"
            PLAT="${_directory##*/}"
            break
        fi
    done < <(printf '%s\n' "$_spec_root"/plat_"${_os}"_*/ | sort -r)
}

# Resolve scratch symlinks each time; persisted physical paths become stale
# when ~/.local moves. PLAT is detected on this host, never stored in NFS HOME.
_resolve_local_plat() {
    local _root="${DF_TOOLS_ROOT:-$HOME/.local}"
    # An explicit host root is already the physical per-host destination.
    # Only the legacy shared-home default follows ~/.local's scratch symlink.
    [[ "${DF_TOOLS_ROOT_EXPLICIT:-0}" != 1 ]] \
        && [[ -L "$_root" ]] && _root="$(readlink -f "$_root")"
    if [[ "${DF_USE_PLAT:-0}" == "1" ]]; then
        LOCAL_PLAT="$_root/$PLAT"
    else
        LOCAL_PLAT="$_root"
    fi
    export LOCAL_PLAT
}
