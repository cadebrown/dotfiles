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
# shellcheck source=install/_lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"
