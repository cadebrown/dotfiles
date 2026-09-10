#!/usr/bin/env bash
# Manage the small data-only per-host policy file consumed by _host-config.sh.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DF_ROOT="${DF_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
# shellcheck source=install/_host-config.sh
source "$SCRIPT_DIR/_host-config.sh"

_host_name="$(hostname)"
_host_file="$HOME/.config/dotfiles/hosts/$_host_name.env"

_show() {
    _host_config_resolve "$DF_ROOT"
    source "$SCRIPT_DIR/_runtime-paths.sh"
    _normalize_plat_layout
    _detect_plat "$DF_ROOT"
    _resolve_local_plat
    printf 'host=%s\nlocal_file=%s\nlocal_config=%s\noverlay_files=%s\nDF_PROFILE=%s\nDF_USE_PLAT=%s\nDF_PLAT=%s\nPLAT=%s\nDF_TOOLS_ROOT=%s\nLOCAL_PLAT=%s\nDF_STATE_ROOT=%s\nCODEX_HOME=%s\n' \
        "$_host_name" "$DF_HOST_CONFIG_FILE" "$DF_HOST_CONFIG_PRESENT" "${DF_HOST_CONFIG_OVERLAY_FILES:-}" "$DF_PROFILE" "$DF_USE_PLAT" "$DF_PLAT" "$PLAT" "$DF_TOOLS_ROOT" "$LOCAL_PLAT" "${DF_STATE_ROOT:-}" "${CODEX_HOME:-}"
}

_prompt() {
    local _label="$1" _default="$2" _answer
    printf '%s [%s]: ' "$_label" "$_default" >&2
    read -r _answer
    printf '%s' "${_answer:-$_default}"
}

_configure() {
    [[ -t 0 && -t 1 ]] || { printf 'host configure requires an interactive terminal\n' >&2; return 2; }
    if [[ -f "$_host_file" ]]; then
        printf '%s already exists; replace it? [y/N]: ' "$_host_file"
        read -r _replace
        [[ "$_replace" == y || "$_replace" == Y ]] || return 0
    fi
    _host_config_resolve "$DF_ROOT"
    local _profile _use_plat _plat _tools_root _state_root _directory _temporary _tools_default='' _clear_tools=0 _clear_state=0
    [[ "$DF_TOOLS_ROOT_EXPLICIT" == 1 ]] && _tools_default="$DF_TOOLS_ROOT"
    _profile="$(_prompt 'Profile (core/full)' "$DF_PROFILE")"
    _use_plat="$(_prompt 'Use PLAT isolation (0/1)' "$DF_USE_PLAT")"
    _plat="$(_prompt 'PLAT selector (auto or plat_...)' "$DF_PLAT")"
    _tools_root="$(_prompt 'Tools root (absolute; - clears inherited root)' "$_tools_default")"
    _state_root="$(_prompt 'Persistent state root (absolute; - clears inherited root)' "${DF_STATE_ROOT:-}")"
    [[ "$_tools_root" == - ]] && { _tools_root=''; _clear_tools=1; }
    [[ "$_state_root" == - ]] && { _state_root=''; _clear_state=1; }
    _host_config_validate_value DF_PROFILE "$_profile" "$DF_ROOT"
    _host_config_validate_value DF_USE_PLAT "$_use_plat" "$DF_ROOT"
    _host_config_validate_value DF_PLAT "$_plat" "$DF_ROOT"
    _host_config_validate_value DF_TOOLS_ROOT "$_tools_root" "$DF_ROOT"
    _host_config_validate_value DF_STATE_ROOT "$_state_root" "$DF_ROOT"
    _directory="${_host_file%/*}"
    (umask 077; mkdir -p "$_directory"; chmod 700 "$_directory"; _temporary="$(mktemp "$_directory/.${_host_name}.XXXXXX")"; {
        printf '# Per-host dotfiles policy. Data only: KEY=value.\n'
        printf 'DF_PROFILE=%s\nDF_USE_PLAT=%s\nDF_PLAT=%s\n' "$_profile" "$_use_plat" "$_plat"
        if (( _clear_tools )); then printf 'DF_TOOLS_ROOT=\n'; elif [[ -n "$_tools_root" ]]; then printf 'DF_TOOLS_ROOT=%s\n' "$_tools_root"; fi
        if (( _clear_state )); then printf 'DF_STATE_ROOT=\n'; elif [[ -n "$_state_root" ]]; then printf 'DF_STATE_ROOT=%s\n' "$_state_root"; fi
        true
    } > "$_temporary"; chmod 600 "$_temporary"; mv -f "$_temporary" "$_host_file")
    printf 'Wrote %s\n' "$_host_file"
}

case "${1:-show}" in
    show) _show ;;
    configure) _configure ;;
    *) printf 'Usage: %s [show|configure]\n' "$0" >&2; exit 2 ;;
esac
