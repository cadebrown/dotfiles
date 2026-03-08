#!/usr/bin/env bash
# infra/cloudflare/build.sh - build mdBook docs for Cloudflare Pages
#
# Cloudflare Pages build image has Rust/cargo available but not mdbook.
# cargo-binstall downloads precompiled binaries, making this much faster
# than `cargo install mdbook` (which compiles from source, ~2 min).
set -euo pipefail

echo "[info] Installing cargo-binstall..."
curl -L --proto '=https' --tlsv1.2 -sSf \
    https://raw.githubusercontent.com/cargo-bins/cargo-binstall/main/install-from-binstall-release.sh \
    | bash

echo "[info] Installing mdbook..."
cargo-binstall mdbook --no-confirm || cargo install mdbook --locked

echo "[info] Building docs..."
mdbook build docs

echo "[ok]   Build complete → docs/book/"
