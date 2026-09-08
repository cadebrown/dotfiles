---
title: Docs and hosting
description: The Astro/Starlight build, rendered artifact verification, Cloudflare Pages handoff, and OpenTofu boundary.
---

## Docs and hosting

The handbook at [dotfiles.cade.io](https://dotfiles.cade.io) is rendered with
[Astro](https://docs.astro.build/) 7.3.2 and
[Starlight](https://starlight.astro.build/) 0.42. Markdown under `docs/` is the
authoritative source; the generator stages it under `site/src/content/docs/`,
and the verified static artifact is `site/dist/`.

[`.node-version`](../../.node-version) selects Node 24 for GitHub CI and
Cloudflare Pages. Pages reads this repository file before running the build;
see [build image version overrides](https://developers.cloudflare.com/pages/configuration/build-image/).

The mdBook-to-Astro migration also changes the Pages project's output directory
from `docs/book` to `site/dist`. Updating `main.tf` in Git does not update the
live project. Before the first Astro publication, review and apply that
infrastructure change through the workflow below, then verify the actual Pages
build and deployed URLs. Local builds and configuration validation establish
neither of those remote outcomes.

## How it works

```text
push to main
  → Cloudflare Pages detects the push
  → runs infra/cloudflare/build.sh
    → npm ci --ignore-scripts in site/
    → installs Playwright Chromium for Mermaid SVG rendering
    → runs `npm --prefix site run verify`
  → deploys site/dist/ to dotfiles.cade.io
```

The entire pipeline is defined in two files:

- **`infra/cloudflare/main.tf`** -- OpenTofu config that creates the Cloudflare Pages project, binds the custom domain (`dotfiles.cade.io`), and sets up the CNAME DNS record
- **`infra/cloudflare/build.sh`** -- build script that installs locked site dependencies, Chromium, and runs the same rendered-artifact verifier

## Local development

```sh
npm --prefix site ci --ignore-scripts
npx --prefix site --no-install playwright install chromium
npm --prefix site run dev
```

Changes to Markdown under `docs/` are staged into the running handbook. See
[author handbook documentation](../contributing/documentation.md) for source,
SVG, WebP, and snippet guidance.

## Doc structure

```
docs/                       # authoritative Markdown and feature data
site/
├── astro.config.mjs         # Starlight navigation and rendering
├── scripts/generate.mjs     # source → staging generator
├── src/content/docs/        # generated staging; do not edit
└── dist/                    # verified static output; do not edit
```

## Infrastructure management

The Cloudflare Pages project is managed with OpenTofu (open-source Terraform):

```sh
cd infra/cloudflare
export CLOUDFLARE_API_TOKEN=...
tofu plan -out=tfplan  # write a reviewable plan
tofu show tfplan       # inspect the exact saved plan
tofu apply tfplan      # apply only that reviewed plan
```

`terraform.tfvars` holds `account_id` and `github_owner` -- gitignored, copy from `terraform.tfvars.example` on each machine.

### What OpenTofu creates

| Resource | Purpose |
| --- | --- |
| `cloudflare_pages_project` | Pages project linked to GitHub, runs `build.sh` on push |
| `cloudflare_pages_domain` | Binds `dotfiles.cade.io` to the project |
| `cloudflare_dns_record` | CNAME `dotfiles.cade.io` → `<project>.pages.dev` (proxied) |

### Cloudflare provider v5 migration

Commit `f8a35b6` is the latest-v4 checkpoint required by Cloudflare's v5 migration path. Before the first v5 plan against an existing deployment, back up the remote state, check out that commit, run `tofu init -upgrade` and a refresh-only plan, then return to the v5 configuration and review a saved plan. CI validates configuration only; it never plans or applies Cloudflare changes.
