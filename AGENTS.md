# AGENTS.md

## Repo Purpose

Personal dotfiles for macOS and Linux, managed with chezmoi and bootstrapped by `bootstrap.sh`.
The repo is designed for:
- cross-platform support
- shared NFS home directories
- optional PLAT-specific binary isolation under `~/.local/$PLAT/` for shared homes
- idempotent re-runs

## Read This First

- Start with [REPO-MAP.md](/Users/cade/dotfiles/REPO-MAP.md) for a compact repo map.
- Read [install/_lib.sh](/Users/cade/dotfiles/install/_lib.sh) before changing install scripts.
- Read the nearest nested `AGENTS.md` before editing `install/`, `home/`, `tests/`, or `docs/`.
- [docs/usage/troubleshooting.md](/Users/cade/dotfiles/docs/usage/troubleshooting.md) is the FAQ of known failure modes (symptom → root-cause chain → fix). Check it before re-diagnosing an issue; add newly root-caused issues there.

## Canonical Commands

- Full bootstrap: `~/dotfiles/bootstrap.sh`
- Update existing machine: `~/dotfiles/bootstrap.sh update`
- Upgrade existing machine: `~/dotfiles/bootstrap.sh upgrade`
- Full local CI validation: `./tests/ci.sh full`
- Docker bootstrap tests only: `./tests/run.sh`
- Enable this checkout's push gate: `./tests/install-hooks.sh`
- Serve docs locally: `mdbook serve docs/ --open`
- Preview dotfile changes: `chezmoi diff`

## High-Value Invariants

- Compiled binaries belong under `~/.local/` by default, or `~/.local/$PLAT/` when `DF_USE_PLAT=1`.
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
- Agent instructions share `home/.chezmoitemplates/agents-common.md`; tone lives in `voice-common.md`. Keep tool inventories, provider setup, and registry maintenance in this repo's docs and skills rather than global prompts.
- `packages/agent-skills.txt` owns installer-managed skills; repo-owned skills live under `home/dot_claude/skills/`. Never give a skill both owners. `bash install/skills-sync.sh check` is read-only; `npx skills check` may update skills.
- Use the installed `writing-skills` workflow and the selected model for meaningful instruction or skill comparisons. Preserve native memory-write permissions; benchmarking does not authorize memory updates.

## Validation

- CI and local validation share `tests/ci.sh`; keep commands there rather than duplicating them in workflow YAML.
- Keep the repository push gate enabled. It validates each outgoing commit in an isolated checkout; working-tree fixes and earlier test runs do not validate an uncorrected commit.
- After an authorized push, verify the hosted CI result for that commit before reporting CI success. Local validation cannot establish another OS/architecture's result.
- For bootstrap/install logic, prefer `./tests/run.sh`.
- For docs-only changes, make sure the edited source is under `docs/`, not `docs/book/`.
- For chezmoi-managed files, reason about both the source in `home/` and the deployed target path in `~/`.
