#!/usr/bin/env bash

_agent_layout="$HOME/.config/dotfiles/agent-layout"
if [[ -z "${DF_USE_PLAT+x}" && -f "$_agent_layout" ]]; then
    DF_USE_PLAT="$(<"$_agent_layout")"
    case "$DF_USE_PLAT" in
        0|1) export DF_USE_PLAT ;;
        *) printf 'Invalid agent layout in %s; run chezmoi apply\n' "$_agent_layout" >&2; exit 1 ;;
    esac
fi
unset _agent_layout

if [[ "${1:-}" == --runtime-only ]]; then
    # Runtime callers need paths, not installer traps, credential files,
    # compiler flags, or package-manager environment changes.
    _agent_install="${BASH_SOURCE[0]%/*}"
    # shellcheck source=install/_runtime-paths.sh
    source "$_agent_install/_runtime-paths.sh"
    _normalize_plat_layout
    PLAT=""
    if [[ "$DF_USE_PLAT" == 1 ]]; then
        _detect_plat "$_agent_install/.."
        [[ -n "$PLAT" ]] || {
            printf 'DF_USE_PLAT=1 but no matching plat spec in %s/plat/\n' "$_agent_install" >&2
            return 1
        }
    fi
    _resolve_local_plat
    ARCH_BIN="$LOCAL_PLAT/bin"
    PYTHON_ENV="$LOCAL_PLAT/python"
    UV_TOOL_BIN_DIR="$ARCH_BIN"
    UV_TOOL_DIR="$LOCAL_PLAT/uv/tools"
    UV_PYTHON_INSTALL_DIR="$LOCAL_PLAT/uv/python"
    export DF_USE_PLAT PLAT ARCH_BIN PYTHON_ENV UV_TOOL_BIN_DIR UV_TOOL_DIR UV_PYTHON_INSTALL_DIR
    unset _agent_install
else
    # Installers retain the full initialization contract.
    # shellcheck source=install/_lib.sh
    source "${BASH_SOURCE[0]%/*}/_lib.sh"
fi
