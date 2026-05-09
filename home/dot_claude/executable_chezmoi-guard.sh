#!/usr/bin/env bash
# ~/.claude/chezmoi-guard.sh — PreToolUse hook
# Block edits to chezmoi-managed deployed dotfiles. The source-of-truth lives
# in ~/dotfiles/home/ (or an overlay). Edit the source and run `chezmoi apply`.
# Exit 2 = block the tool call.
set -uo pipefail

command -v jq &>/dev/null      || exit 0
command -v chezmoi &>/dev/null || exit 0

data=$(cat)
file=$(echo "$data" | jq -r '.tool_input.file_path // .tool_input.filePath // empty')
[[ -z "$file" ]] && exit 0

# Resolve to absolute path so chezmoi can recognize it.
file=$(cd "$(dirname "$file")" 2>/dev/null && echo "$(pwd)/$(basename "$file")" || echo "$file")

# Ask chezmoi if this exact path is managed. Fast (~10ms), single source of
# truth — no hardcoded list to keep in sync. Exits non-zero on "not managed",
# "not in destination directory", or anything we don't understand → allow.
src=$(chezmoi source-path "$file" 2>/dev/null) || exit 0
[[ -n "$src" ]] || exit 0

echo "Blocked: $file is managed by chezmoi." >&2
echo "Edit the source: $src" >&2
echo "(then run 'chezmoi apply' to deploy)" >&2
exit 2
