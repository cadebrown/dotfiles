#!/usr/bin/env bash
# Validate the Astro/Starlight handbook from the authoritative docs/ sources.
# Dependencies are intentionally not installed here: local and hosted callers
# must make their dependency setup explicit.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
site_root="$repo_root/site"

if [[ ! -f "$site_root/package.json" ]]; then
    printf 'docs: missing site/package.json; the handbook source is incomplete\n' >&2
    exit 1
fi
if [[ ! -d "$site_root/node_modules" ]]; then
    printf 'docs: dependencies are missing at %s/node_modules; run npm --prefix site ci --ignore-scripts first\n' "$site_root" >&2
    exit 127
fi
if ! command -v npm >/dev/null 2>&1; then
    printf 'docs: npm is required; install a supported Node.js runtime (>=22.12), then rerun\n' >&2
    exit 127
fi

docs_out_dir="${DOCS_OUT_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-docs.XXXXXX")}"
cleanup=0
if [[ -z "${DOCS_OUT_DIR:-}" ]]; then cleanup=1; fi
cleanup_docs() {
    if [[ "$cleanup" == 1 ]]; then rm -rf "$docs_out_dir"; fi
}
trap cleanup_docs EXIT

mkdir -p "$docs_out_dir"
printf '==> Documentation check\n'
DOCS_OUT_DIR="$docs_out_dir" npm --prefix "$site_root" run check
printf '==> Documentation build and artifact verification\n'
DOCS_OUT_DIR="$docs_out_dir" npm --prefix "$site_root" run verify
