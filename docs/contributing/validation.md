---
title: Validate handbook changes
description: Use the canonical local and hosted checks, and understand what each documentation result establishes.
---

## The local gate

Install the locked site dependencies and Chromium explicitly once for this
checkout, then run the canonical documentation mode:

```bash
npm --prefix site ci --ignore-scripts
npx --prefix site --no-install playwright install chromium
./tests/ci.sh docs
```

`tests/docs.sh` fails clearly when `site/node_modules` is absent. It sets an
isolated `DOCS_OUT_DIR`, runs `npm --prefix site run check`, then runs
`npm --prefix site run verify`. `check` is Astro's type and content check;
`verify` builds, then checks the rendered artifact against source and coverage
contracts. Neither result establishes that Cloudflare deployed the site.

## Where the hosted checks run

The quality job installs Node 24, executes the locked npm install without
lifecycle scripts, installs Playwright Chromium, then calls the shared
`./tests/ci.sh quality` command. Cloudflare follows the same build contract and
publishes `site/dist/` only after verification. OpenTofu validation checks the
configuration but never plans or applies production changes.

For a broader repository change, keep the documentation gate alongside its
domain checks:

```bash
./tests/ci.sh shell
./tests/ci.sh docs
./tests/ci.sh infrastructure
```

Use `./tests/ci.sh full` only when the Docker bootstrap suite is also in scope.
It is intentionally broader than a documentation edit.
