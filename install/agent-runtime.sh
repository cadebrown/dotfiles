#!/usr/bin/env bash

_agent_install="${BASH_SOURCE[0]%/*}"
_agent_root="$(cd "$_agent_install/.." && pwd)"
# shellcheck source=install/_host-config.sh
source "$_agent_install/_host-config.sh"
_host_config_resolve "$_agent_root" || return 1

if [[ "${1:-}" == --runtime-only ]]; then
    # Runtime callers need paths, not installer traps, credential files,
    # compiler flags, or package-manager environment changes.
    # shellcheck source=install/_runtime-paths.sh
    source "$_agent_install/_runtime-paths.sh"
    _normalize_plat_layout
    PLAT=""
    if [[ "$DF_USE_PLAT" == 1 ]]; then
        _detect_plat "$_agent_install/.." || { printf 'DF_PLAT=%s is not supported by this host\n' "$DF_PLAT" >&2; return 1; }
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
    export DF_USE_PLAT DF_PLAT PLAT ARCH_BIN PYTHON_ENV UV_TOOL_BIN_DIR UV_TOOL_DIR UV_PYTHON_INSTALL_DIR
    unset _agent_install _agent_root
else
    # Installers retain the full initialization contract.
    # shellcheck source=install/_lib.sh
    source "${BASH_SOURCE[0]%/*}/_lib.sh"
fi
