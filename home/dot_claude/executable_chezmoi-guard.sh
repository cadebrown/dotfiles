#!/usr/bin/env bash
# Backward-compatible Claude hook entrypoint. The implementation is shared with
# Codex so the chezmoi invariant has one owner.
exec "$HOME/.local/bin/df-chezmoi-guard" "$@"
