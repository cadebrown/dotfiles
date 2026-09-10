#!/usr/bin/env bash
# Per-host policy resolver. Host files are data only; they are never sourced.
# Usage: _host_config_resolve /absolute/dotfiles/root

_host_config_keys='DF_PROFILE
DF_USE_PLAT
DF_PLAT
DF_TOOLS_ROOT
DF_STATE_ROOT
DF_DO_AUTH
DF_DO_BLENDER_MCP
DF_DO_CLAUDE
DF_DO_CLAUDE_DESKTOP
DF_DO_CMAKE
DF_DO_CODEX
DF_DO_CODEX_DESKTOP
DF_DO_CURSOR
DF_DO_DIRS
DF_DO_GO
DF_DO_JULIA
DF_DO_LATEX
DF_DO_LEAN
DF_DO_LINEARMOUSE
DF_DO_LLDB
DF_DO_LOCAL_LLM
DF_DO_MACOS_QUICK_ACTIONS
DF_DO_MACOS_SERVICES
DF_DO_MACOS_SETTINGS
DF_DO_MEMORY
DF_DO_NODE
DF_DO_OPENCODE
DF_DO_OVERLAYS
DF_DO_PACKAGES
DF_DO_PYTHON
DF_DO_QUARTO
DF_DO_RUST
DF_DO_SCRATCH
DF_DO_SKILLS
DF_DO_VSCODE
DF_DO_ZSH'
_host_config_bad() { printf 'Invalid host configuration: %s\n' "$*" >&2; return 1; }

# Bookkeeping remains in this shell only: child processes capture their own
# invocation environment instead of inheriting resolver implementation state.
_host_config_capture_callers() {
    [[ -n "${DF_HOST_CONFIG_INITIALIZED+x}" ]] && return 0
    local _key _value
    DF_HOST_CONFIG_CALLER_KEYS=''
    while IFS= read -r _key; do
        if _value="$(printenv "$_key" 2>/dev/null)"; then DF_HOST_CONFIG_CALLER_KEYS+=" $_key"; fi
    done <<EOF
$_host_config_keys
CODEX_HOME
EOF
    DF_HOST_CONFIG_INITIALIZED=1
}
_host_config_caller_set() { [[ " $DF_HOST_CONFIG_CALLER_KEYS " == *" $1 "* ]]; }
_host_config_key_allowed() { [[ $'\n'"$_host_config_keys"$'\n' == *$'\n'"$1"$'\n'* ]]; }

_host_config_validate_value() {
    local _key="$1" _value="$2" _root="$3"
    _host_config_key_allowed "$_key" || { _host_config_bad "unknown key '$_key'"; return 1; }
    [[ "$_value" != *'$'* && "$_value" != *'`'* && "$_value" != *';'* && "$_value" != *'|'* && "$_value" != *'&'* && "$_value" != *'\\'* && "$_value" != *'"'* && "$_value" != *"'"* && "$_value" != *'('* && "$_value" != *')'* && "$_value" != *'<'* && "$_value" != *'>'* ]] || { _host_config_bad "$_key contains shell syntax"; return 1; }
    case "$_key" in
        DF_PROFILE) [[ "$_value" == core || "$_value" == full ]] || _host_config_bad 'DF_PROFILE must be core or full' ;;
        DF_USE_PLAT) case "$_value" in 0|1|false|true|no|yes|off|on|FALSE|TRUE|NO|YES|OFF|ON) ;; *) _host_config_bad 'DF_USE_PLAT must be boolean' ;; esac ;;
        DF_PLAT) [[ "$_value" == auto || ( "$_value" == plat_* && ( -d "$_root/install/plat/$_value" || "${DF_DEFER_PLAT_REQUIRE:-0}" == 1 ) ) ]] || _host_config_bad 'DF_PLAT must be auto or a supported plat selector' ;;
        DF_TOOLS_ROOT|DF_STATE_ROOT) [[ -z "$_value" || "$_value" == /* ]] || _host_config_bad "$_key must be an absolute path" ;;
        DF_DO_*) [[ "$_value" == 0 || "$_value" == 1 ]] || _host_config_bad "$_key must be 0 or 1" ;;
    esac
}

_host_config_read_file() {
    local _file="$1" _root="$2" _line _key _value
    if [[ -e "$_file" || -L "$_file" ]]; then [[ -f "$_file" && ! -L "$_file" ]] || { _host_config_bad "$_file must be a regular file"; return 1; }; else return 0; fi
    while IFS= read -r _line || [[ -n "$_line" ]]; do
        [[ -z "$_line" || "$_line" == \#* ]] && continue
        [[ "$_line" == *=* ]] || { _host_config_bad "$_file has a non KEY=value line"; return 1; }
        _key="${_line%%=*}" _value="${_line#*=}"
        [[ "$_key" =~ ^[A-Z][A-Z0-9_]*$ ]] || { _host_config_bad "$_file has a non KEY=value line"; return 1; }
        _host_config_validate_value "$_key" "$_value" "$_root" || return 1
        _host_config_caller_set "$_key" || export "$_key=$_value"
        [[ "$_key" == DF_TOOLS_ROOT ]] && DF_TOOLS_ROOT_EXPLICIT=1
    done < "$_file"
    return 0
}

_host_config_clear_derived() {
    local _key
    while IFS= read -r _key; do _host_config_caller_set "$_key" || unset "$_key"; done <<EOF
$_host_config_keys
EOF
}

_host_config_resolve() {
    local _root="$1" _hostname _overlay
    [[ -d "$_root/install" ]] || { _host_config_bad "root has no install directory: $_root"; return 1; }
    # Bash leaves an unmatched glob literal; Zsh's default NOMATCH aborts.
    # Keep this local so sourcing the resolver never changes caller options.
    if [[ -n "${ZSH_VERSION:-}" ]]; then setopt localoptions nullglob; fi
    _host_config_capture_callers; _host_config_clear_derived; DF_TOOLS_ROOT_EXPLICIT=0
    _hostname="$(hostname)" || return 1
    [[ -n "$_hostname" && "$_hostname" != */* ]] || { _host_config_bad 'unsafe hostname'; return 1; }
    DF_HOST_CONFIG_OVERLAY_FILES=''
    for _overlay in "$_root"/dotfiles-*/; do
        [[ -d "$_overlay" ]] || continue
        [[ -f "${_overlay%/}/hosts/$_hostname.env" ]] && DF_HOST_CONFIG_OVERLAY_FILES+="${DF_HOST_CONFIG_OVERLAY_FILES:+:}${_overlay%/}/hosts/$_hostname.env"
        _host_config_read_file "${_overlay%/}/hosts/$_hostname.env" "$_root" || return 1
    done
    DF_HOST_CONFIG_FILE="$HOME/.config/dotfiles/hosts/$_hostname.env"; DF_HOST_CONFIG_PRESENT=0
    [[ -f "$DF_HOST_CONFIG_FILE" && ! -L "$DF_HOST_CONFIG_FILE" ]] && DF_HOST_CONFIG_PRESENT=1
    _host_config_read_file "$DF_HOST_CONFIG_FILE" "$_root" || return 1
    # Read by _resolve_local_plat in the separately sourced runtime helper.
    # shellcheck disable=SC2034
    _host_config_caller_set DF_TOOLS_ROOT && DF_TOOLS_ROOT_EXPLICIT=1
    : "${DF_PROFILE:=full}" "${DF_USE_PLAT:=0}" "${DF_PLAT:=auto}" "${DF_TOOLS_ROOT:=$HOME/.local}"
    if [[ -n "${DF_STATE_ROOT:-}" ]] && ! _host_config_caller_set CODEX_HOME; then CODEX_HOME="$DF_STATE_ROOT/codex"; fi
    export DF_HOST_CONFIG_FILE DF_HOST_CONFIG_PRESENT DF_PROFILE DF_USE_PLAT DF_PLAT
    [[ -n "${DF_STATE_ROOT:-}" ]] && export DF_STATE_ROOT CODEX_HOME
    return 0
}
