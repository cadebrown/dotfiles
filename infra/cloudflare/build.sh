#!/usr/bin/env bash
# infra/cloudflare/build.sh - build mdBook docs for Cloudflare Pages
#
# Why this is curl-and-untar rather than `cargo install` / `cargo-binstall`:
# Cloudflare's build image is x86_64 Linux but does NOT reliably ship a usable
# `cargo`, and `cargo-binstall` resolves release artifacts through the GitHub
# REST API (api.github.com) — which 403s under the unauthenticated rate limit
# on Cloudflare's shared build IPs. When that happens binstall falls back to a
# source build, hits the missing `cargo`, and the deploy dies with exit 127.
# (That's exactly what broke production deploys starting 2026-05-22.)
#
# So we depend on neither: pull pinned, prebuilt binaries straight from the
# GitHub release CDN. `releases/download/...` is a plain object redirect, NOT an
# API call, so it isn't rate-limited. Bump the pinned versions below to upgrade.
set -euo pipefail

MDBOOK_VERSION="0.5.3"
MDBOOK_MERMAID_VERSION="0.17.0"
TARGET="x86_64-unknown-linux-gnu"

# Stage binaries in a throwaway dir and put it first on PATH.
BIN_DIR="$(mktemp -d)/bin"
mkdir -p "$BIN_DIR"
export PATH="$BIN_DIR:$PATH"

# fetch <url> — stream a .tar.gz from the GitHub release CDN straight into $BIN_DIR.
# Both archives contain a single binary at the root, so no strip-components needed.
fetch() {
    local url="$1"
    echo "[info] Fetching $url"
    curl -fL --proto '=https' --tlsv1.2 --retry 5 --retry-delay 2 -sS "$url" \
        | tar -xz -C "$BIN_DIR"
}

echo "[info] Installing mdbook $MDBOOK_VERSION + mdbook-mermaid $MDBOOK_MERMAID_VERSION (prebuilt)..."
fetch "https://github.com/rust-lang/mdBook/releases/download/v${MDBOOK_VERSION}/mdbook-v${MDBOOK_VERSION}-${TARGET}.tar.gz"
fetch "https://github.com/badboy/mdbook-mermaid/releases/download/v${MDBOOK_MERMAID_VERSION}/mdbook-mermaid-v${MDBOOK_MERMAID_VERSION}-${TARGET}.tar.gz"

# Fail loudly here instead of with a confusing "command not found" inside mdbook.
command -v mdbook         >/dev/null || { echo "[fail] mdbook missing after download"         >&2; exit 1; }
command -v mdbook-mermaid >/dev/null || { echo "[fail] mdbook-mermaid missing after download" >&2; exit 1; }
echo "[info] $(mdbook --version), $(mdbook-mermaid --version)"

echo "[info] Building docs..."
mdbook build docs

echo "[ok]   Build complete → docs/book/"
