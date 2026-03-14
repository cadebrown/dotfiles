#!/usr/bin/env bash
# ~/.claude/format-hook.sh — PostToolUse hook for auto-formatting
# Reads tool result JSON from stdin, formats the edited file if a formatter is available.
# Always exits 0 (non-blocking).
set -uo pipefail

command -v jq &>/dev/null || exit 0

data=$(cat)
file=$(echo "$data" | jq -r '.tool_input.file_path // .tool_input.filePath // empty')
[[ -z "$file" || ! -f "$file" ]] && exit 0

ext="${file##*.}"

case "$ext" in
    rs)
        command -v rustfmt &>/dev/null && rustfmt --edition 2021 "$file" 2>/dev/null
        ;;
    py)
        command -v ruff &>/dev/null && ruff format --quiet "$file" 2>/dev/null
        ;;
    ts|tsx|js|jsx|json|css|scss|html|md|yaml|yml)
        command -v prettier &>/dev/null && prettier --write --log-level silent "$file" 2>/dev/null
        ;;
    c|cpp|cc|cxx|h|hpp)
        command -v clang-format &>/dev/null && clang-format -i "$file" 2>/dev/null
        ;;
esac

exit 0
