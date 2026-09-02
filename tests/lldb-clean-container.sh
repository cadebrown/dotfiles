#!/usr/bin/env bash
set -euo pipefail

repo="${1:-$HOME/dotfiles}"
export DF_USE_PLAT=1
export DF_MODE=install

source "$repo/install/_lib.sh"
bash "$repo/install/lldb.sh"

"$ARCH_BIN/lldb" --batch -o 'target create /bin/true' -o quit </dev/null
"$ARCH_BIN/lldb-dap" --help </dev/null >/dev/null
