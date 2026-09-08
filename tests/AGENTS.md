# AGENTS.md

## Scope

Instructions for the Docker-based bats suite under `tests/`.

## Test Entry Point

- Full local CI command: `./tests/ci.sh full`
- Docker bootstrap suite: `./tests/run.sh`
- Shared quality, macOS, and infrastructure commands live in `tests/ci.sh`; workflow jobs invoke those modes directly.
- Handbook validation is `./tests/ci.sh docs`; it runs `tests/docs.sh` against already-installed `site/node_modules` and an isolated `DOCS_OUT_DIR`.

## Structure

- [tests/run.sh](/Users/cade/dotfiles/tests/run.sh): builds the Docker image and runs the suite
- [tests/entrypoint.sh](/Users/cade/dotfiles/tests/entrypoint.sh): container-side bootstrap entry
- `*.bats`: behavior checks
- [tests/Dockerfile](/Users/cade/dotfiles/tests/Dockerfile): test environment definition

## Rules

- Prefer testing observable behavior over implementation details.
- Keep tests aligned with the bootstrap contract rather than incidental log wording.
- Test the push gate against temporary bare remotes, including committed failures hidden by dirty working-tree repairs. Never use the real remote for a negative test.
- If changing bootstrap semantics, update the relevant bats expectations in the same change.

## Validation Guidance

- Run the full suite for meaningful bootstrap or install-path changes.
- If a change only affects docs or global agent config, test updates are usually unnecessary.
- Documentation pipeline changes need fixture coverage in `ci-entrypoint.bats` and must preserve the rule that local checks never install npm dependencies or browser binaries.
