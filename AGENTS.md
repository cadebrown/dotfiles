# AGENTS.md

## Repo Purpose

Personal dotfiles for macOS and Linux, managed with chezmoi and bootstrapped by `bootstrap.sh`.
The repo is designed for:
- cross-platform support
- shared NFS home directories
- PLAT-specific binary isolation under `~/.local/$PLAT/`
- idempotent re-runs

## Read This First

- Start with [REPO-MAP.md](/Users/cade/dotfiles/REPO-MAP.md) for a compact repo map.
- Read [install/_lib.sh](/Users/cade/dotfiles/install/_lib.sh) before changing install scripts.
- Read the nearest nested `AGENTS.md` before editing `install/`, `home/`, `tests/`, or `docs/`.

## Canonical Commands

- Full bootstrap: `~/dotfiles/bootstrap.sh`
- Update existing machine: `~/dotfiles/bootstrap.sh update`
- Upgrade existing machine: `~/dotfiles/bootstrap.sh upgrade`
- Run tests: `./tests/run.sh`
- Serve docs locally: `mdbook serve docs/ --open`
- Preview dotfile changes: `chezmoi diff`

## High-Value Invariants

- Compiled binaries belong under `~/.local/$PLAT/`, not shared arch-neutral paths.
- Linux setup must avoid sudo.
- Install scripts must be idempotent.
- Dotfile sources live in `home/`; rendered targets in `~/` are not the source of truth.
- `docs/book/` is generated output. Edit Markdown under `docs/`, not generated HTML.
- Avoid duplicate package ownership across Cargo, npm, pip, and Homebrew.

## Editing Guidance

- Prefer changing the authoritative source file over patching secondary docs.
- When touching install behavior, verify the corresponding `DF_DO_*` flow in `bootstrap.sh`.
- When touching package ownership, check the package lists for duplicates first.
- When touching shell environment behavior, keep zsh and bash login profiles aligned unless divergence is intentional.

## Validation

- For bootstrap/install logic, prefer `./tests/run.sh`.
- For docs-only changes, make sure the edited source is under `docs/`, not `docs/book/`.
- For chezmoi-managed files, reason about both the source in `home/` and the deployed target path in `~/`.
