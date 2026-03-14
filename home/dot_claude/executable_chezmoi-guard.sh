#!/usr/bin/env bash
# ~/.claude/chezmoi-guard.sh — PreToolUse hook to block edits to deployed dotfiles
# These files are managed by chezmoi — edit the sources in ~/dotfiles/home/ instead.
# Exit 2 = block the tool call.
set -uo pipefail

command -v jq &>/dev/null || exit 0

data=$(cat)
file=$(echo "$data" | jq -r '.tool_input.file_path // .tool_input.filePath // empty')
[[ -z "$file" ]] && exit 0

# Resolve to absolute path
file=$(cd "$(dirname "$file")" 2>/dev/null && echo "$(pwd)/$(basename "$file")" || echo "$file")

home="$HOME"
blocked=(
    "$home/.zshrc"
    "$home/.zprofile"
    "$home/.bash_profile"
    "$home/.bashrc"
    "$home/.gitconfig"
    "$home/.gitignore_global"
    "$home/.vimrc"
    "$home/.tmux.conf"
)

for b in "${blocked[@]}"; do
    if [[ "$file" == "$b" ]]; then
        echo "Blocked: $file is managed by chezmoi." >&2
        echo "Edit the source in ~/dotfiles/home/ instead." >&2
        exit 2
    fi
done

exit 0
