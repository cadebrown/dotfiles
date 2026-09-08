---
title: Feature coverage manifest
description: How the handbook maps bootstrap sources to discoverable feature documentation.
---

## Coverage is explicit

[`docs/_data/features.json`](../_data/features.json) maps each public bootstrap entrypoint, installer, PLAT helper, package declaration, and chezmoi-managed `home/` source to one logical feature. `AGENTS.md` files and `home/dot_claude/skills/` are deliberately outside this manifest because instruction ownership and skill metadata have their own catalogs. Generated Python bytecode is not managed configuration.

The manifest has no wildcard category. The rendered-artifact verifier enumerates these source roots and rejects an unmapped or multiply mapped package or managed configuration file. That makes a new declarative package list, shell profile, editor setting, or service template incomplete until its feature page, demonstration, and source ownership are explicit.

The site generator reads the same manifest and produces the [feature catalog](/reference/features/). Each row links back to its authoritative source. The public catalog never executes its examples; commands remain examples for an operator to assess in the appropriate environment.

## Generated reference catalogs

- [Features](/reference/features/) maps installers, package declarations, and managed configuration to practical feature groups.
- [Packages](/reference/packages/) lists declarative packages, plugins, extensions, and models without treating every entry as an npm package.
- [Skills](/reference/skills/) records installer versus repository ownership.
- [MCP servers](/reference/mcp/) exposes public transport, profile, and risk metadata without credentials.

## Review a source addition

1. Add the new public installer, package file, or managed configuration path to exactly one feature’s `sources` list.
2. Describe the operator-visible capability and point `page` at the relevant handbook route.
3. Use a read-only `demo` or `check` command. Do not encode a mutating installer, credential flow, or host-specific secret lookup as a demonstration.
4. Regenerate the catalog in a staging site root and inspect source links and counts.

This creates a reviewable claim about documentation ownership and source coverage. It does not establish that software is installed, a credential is valid, a service is running, or a host-specific workflow succeeded; those require the feature’s stated observation or demonstration.
