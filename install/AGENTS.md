# AGENTS.md

## Scope

Instructions for `install/` scripts and bootstrap-related setup logic.

## Read First

- [install/_lib.sh](/Users/cade/dotfiles/install/_lib.sh) is the central contract.
- [bootstrap.sh](/Users/cade/dotfiles/bootstrap.sh) defines orchestration order and `DF_DO_*` gates.

## Rules

- Every install script must source `_lib.sh`.
- Keep scripts idempotent: check current state first, install only what is missing.
- Use exported path variables from `_lib.sh`; do not invent parallel path logic.
- Preserve PLAT isolation under `~/.local/$PLAT/`.
- Linux paths must remain rootless.
- If a script is gated in bootstrap, keep its `DF_DO_*` behavior coherent with the docs.

## Editing Guidance

- Prefer extending existing helpers over duplicating path or logging logic.
- If changing a runtime install path, verify the effect on PATH assembly in the shell profile templates.
- If adding a new installer, make the bootstrap integration explicit.

## Validation

- Use `./tests/run.sh` for meaningful changes.
- For package-manager changes, also inspect the package lists for duplicate ownership.
