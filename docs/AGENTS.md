# AGENTS.md

## Scope

Instructions for the authoritative Markdown source under `docs/`. Astro/Starlight
stages it into `site/src/content/docs/` and publishes `site/dist/`.

## Core Rule

Edit source Markdown in `docs/`. Do not edit generated files under
`site/src/content/docs/` or `site/dist/`.

## Structure

- `site/astro.config.mjs`: Starlight navigation and renderer configuration
- `site/scripts/generate.mjs`: source-to-staging generator
- `setup/`: setup and bootstrap docs
- `usage/`: day-to-day workflow docs
- `infra/`: hosting and infrastructure docs
- `contributing/`: authoring and validation guidance

## Editing Guidance

- Keep docs aligned with the actual scripts and file paths.
- Lead with the task and a concrete example. Pair runnable commands with prerequisites and expected results, and use diagrams to explain actual data or execution paths. Prefer direct guide text over promotional copy.
- Prefer updating one authoritative explanation rather than duplicating subtle behavior in several pages.
- Keep guides concise: one task sentence, prerequisites, a concrete example, and expected results. Use short option tables and diagrams for real flows. Preserve technical defaults, failure modes, and complete reference coverage; link the detailed reference instead of replacing it with vague instructions.
- Add useful cross-links to exact headings, catalog entries, and repository sources. Preserve shared heading IDs during rewrites. Place new pages in the task order in `site/src/navigation.mjs`; sidebar labels should be short verbs or recognizable tool names.
- When documenting commands, prefer the canonical repo entrypoints already used in README and scripts.
- `usage/troubleshooting.md` is the repo FAQ. Entries follow symptom → root-cause chain → confirm → fix; newly root-caused issues belong there.

## Validation

- Use `npm --prefix site run dev` to preview the generated handbook.
- Run `./tests/ci.sh docs` to execute Astro type checks, build, and rendered-artifact verification. It requires existing `site/node_modules`; install them explicitly with `npm --prefix site ci --ignore-scripts`.
- If a docs change describes bootstrap behavior, cross-check the underlying script. Update `docs/_data/features.json` whenever installer, runtime, package, or managed-configuration behavior changes.
