#!/usr/bin/env bash
# install/agent-tools.sh - deploy architecture-independent agent helper commands

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=install/agent-runtime.sh
source "$SCRIPT_DIR/agent-runtime.sh"

log_section "agent helper commands"

ensure_dir "$ARCH_BIN"
ensure_dir "$HOME/.config/dotfiles"
printf '%s\n' "$DF_USE_PLAT" > "$HOME/.config/dotfiles/agent-layout"

for _command in df-agent-doctor plugin-eval local-agent df-task df-browser df-google-mcp df-gemini; do
    _source="$DF_ROOT/home/dot_local/bin/executable_$_command"
    _destination="$ARCH_BIN/$_command"
    [[ -f "$_source" ]] || die "Missing $_command source: $_source"

    if [[ -x "$_destination" ]] && cmp -s "$_source" "$_destination"; then
        log_okay "$_command is current: $_destination"
    else
        install -m 755 "$_source" "$_destination"
        log_okay "Installed $_command → $_destination"
    fi

    [[ -x "$_destination" ]] || die "$_command is not executable: $_destination"
    cmp -s "$_source" "$_destination" || die "$_command deployment does not match its source"
done

ensure_dir "$HOME/.local/lib/dotfiles"
install -m 644 "$DF_ROOT/home/dot_local/lib/dotfiles/df_task.py" \
    "$HOME/.local/lib/dotfiles/df_task.py"

# MCP clients launched from the Dock need architecture-neutral entrypoints.
if [[ "$ARCH_BIN" != "$HOME/.local/bin" ]]; then
    ensure_dir "$HOME/.local/bin"
    for _command in df-task df-browser df-google-mcp df-gemini; do
        install -m 755 "$DF_ROOT/home/dot_local/bin/executable_$_command" \
            "$HOME/.local/bin/$_command"
    done
fi
