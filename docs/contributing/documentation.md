---
title: Write documentation
description: Edit the authoritative Markdown, preview its Starlight staging output, and keep examples and assets verifiable.
---

## Source, staging, and production

Write content under `docs/`. The Astro generator copies it to
`site/src/content/docs/`, where Starlight renders it; `site/dist/` is the static
production artifact. The latter two directories are generated and must not be
edited. `npm --prefix site run generate` is useful when inspecting the staged
Markdown, but normal development and builds invoke generation themselves.

```bash
npm --prefix site ci --ignore-scripts
npx --prefix site --no-install playwright install chromium
npm --prefix site run dev
```

Mermaid fences render to inline SVG during the Astro build. Chromium is a build
dependency for that rendering, so an otherwise valid Markdown edit still needs
the browser installation before `build` or `verify`. Use [Mermaid's syntax
reference](https://mermaid.js.org/syntax/flowchart.html) for diagrams, keep
labels short, and prefer a table when a diagram would only restate a few facts.

## Write a feature page that can be operated

Lead with the task and a working example. Keep one authoritative explanation;
link it from related workflows rather than repeating its defaults.

| Include | Use |
| --- | --- |
| Purpose | One sentence: what the reader can do |
| Choice | A small decision table when options matter |
| Example | Prerequisites → copyable command → expected result |
| Architecture | A diagram for flow, ownership, or lifecycle; short labels |
| References | Relevant guide sections, local source files, upstream docs |
| Limits | Specific untested behavior beside the relevant claim |

Use YAML `title` and `description`. If managed behavior changes, update
[`features.json`](../_data/features.json) and add the page to the task-ordered
[navigation](../../site/src/navigation.mjs).

Use a focused screenshot or runnable demo only when it makes visual or
interactive behavior easier to assess. State what was actually exercised. A
measurement needs its environment, date, method, and sample scope; do not turn
one local measurement into a general performance claim.

### Link to the useful part

```md title="Links in docs/usage/example.md"
[Choose a profile](../agents/codex.md#pick-a-session-profile-for-the-work)
[Shell configuration](../reference/managed-configuration.md#shells)
[Browser skill](/reference/skills/#browser-workbench)
[Source template](../../home/dot_zshrc.tmpl)
```

Relative Markdown links become website routes; links outside `docs/` become
GitHub source links. Headings and catalog names have permalinks. **Copy link**
also preserves a catalog's filters. Keep existing heading IDs when editing so
shared links continue to work; the docs gate checks internal destinations.

## Images and snippets

Keep source images and their provenance with the feature when possible. Use SVG
for diagrams and interface-independent illustrations. For photographic or
screen assets, use appropriately sized WebP files; inspect the rendered image
at its intended viewport rather than relying on a conversion command alone.

Commands must be copyable and must name prerequisites that are not provided by
the repository. Show expected output only when it is stable and useful for a
reader to compare. Do not include credentials, machine-specific private paths,
or a command that changes external state without making that effect clear.

## Canonical verification

```bash
./tests/ci.sh docs
```

This runs `astro check`, builds the handbook, and verifies rendered artifacts,
source mapping, and feature coverage. It never runs `npm install` for you. The
production and Cloudflare build path use the same `npm --prefix site run verify`
command after their explicit dependency and Chromium setup.
