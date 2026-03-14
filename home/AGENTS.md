# AGENTS.md

## Scope

Instructions for chezmoi-managed dotfile sources under `home/`.

## Core Rule

Files here are the source of truth. The deployed files in `~/` are outputs.

## Rules

- Edit the source file under `home/`, not the rendered target in the home directory.
- `.tmpl` files are Go templates rendered by chezmoi.
- Avoid machine-specific template rendering on shared homes. Do not use per-machine values like `{{ .chezmoi.arch }}` in templates when that would cause machines to fight each other.
- Keep mirrored shell profile behavior aligned unless divergence is intentional and documented.
- `create_` files are write-once chezmoi sources; preserve runtime-managed sections when updating live targets.

## Important Areas

- [home/dot_zprofile.tmpl](/Users/cade/dotfiles/home/dot_zprofile.tmpl) and [home/dot_bash_profile.tmpl](/Users/cade/dotfiles/home/dot_bash_profile.tmpl): login environment and PATH setup
- [home/dot_claude/](/Users/cade/dotfiles/home/dot_claude): Claude-specific config and hooks
- [home/dot_codex/](/Users/cade/dotfiles/home/dot_codex): Codex-specific config, skills, and rules

## Validation

- Reason about both the source file path and the target path in `~/`.
- For behavior changes, use `chezmoi diff` to preview the rendered result.
