#!/usr/bin/env bash
# infra/cloudflare/build.sh - build the Astro/Starlight handbook for Pages.
# Docs remain authoritative in ../docs; site/src/content/docs is staging output.
set -euo pipefail

export PLAYWRIGHT_BROWSERS_PATH=0

node --version
node -e 'const [major, minor] = process.versions.node.split(".").map(Number); process.exit(major > 22 || (major === 22 && minor >= 12) ? 0 : 1)' \
    || { echo "[fail] Node.js >=22.12 is required by site/package.json" >&2; exit 1; }
npm --version
npm --prefix site ci --ignore-scripts
npx --prefix site --no-install playwright install chromium
npm --prefix site run verify

echo "[ok] Handbook verified → site/dist/"
