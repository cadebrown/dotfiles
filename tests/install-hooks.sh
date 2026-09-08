#!/usr/bin/env bash
# Opt this checkout into the versioned push gate without replacing other hooks.
set -euo pipefail
repo_root="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$repo_root"
[[ "$(git rev-parse --show-toplevel)" == "$repo_root" ]] || {
    printf 'Run hook installation from a dotfiles Git checkout.\n' >&2
    exit 1
}
current_hooks="$(git config --get core.hooksPath || true)"
[[ -x .githooks/pre-push && -f tests/pre-push.sh && -x tests/ci.sh ]] || {
    printf 'Missing executable .githooks/pre-push or validation entrypoint.\n' >&2
    exit 1
}
if [[ "$current_hooks" == .githooks ]]; then
    printf 'Dotfiles push gate already enabled.\n'
    exit 0
fi
if [[ -n "$current_hooks" ]]; then
    printf 'Existing core.hooksPath=%s; integrate .githooks/pre-push there before replacing it.\n' "$current_hooks" >&2
    exit 1
fi
hooks_dir="$(git rev-parse --git-path hooks)"
for hook_file in "$hooks_dir"/*; do
    [[ -f "$hook_file" && -x "$hook_file" ]] || continue
    case "$hook_file" in *.sample) continue ;; esac
    printf 'Existing executable hook %s; integrate it before selecting .githooks.\n' "$hook_file" >&2
    exit 1
done
git config --local core.hooksPath .githooks
printf 'Enabled the commit validation gate for this dotfiles checkout.\n'
