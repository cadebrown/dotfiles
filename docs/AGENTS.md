# AGENTS.md

## Scope

Instructions for the mdBook source under `docs/`.

## Core Rule

Edit source Markdown in `docs/`. Do not edit generated files under `docs/book/`.

## Structure

- [SUMMARY.md](SUMMARY.md): book navigation
- [book.toml](book.toml): mdBook config
- `setup/`: setup and bootstrap docs
- `usage/`: day-to-day workflow docs
- `infra/`: hosting and infrastructure docs

## Editing Guidance

- Keep docs aligned with the actual scripts and file paths.
- Prefer updating one authoritative explanation rather than duplicating subtle behavior in several pages.
- When documenting commands, prefer the canonical repo entrypoints already used in README and scripts.

## Validation

- Use `mdbook serve docs/ --open` when you need to preview or verify navigation.
- If a docs change describes bootstrap behavior, cross-check the underlying script.
