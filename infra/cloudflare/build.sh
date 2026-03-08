#!/usr/bin/env bash
# infra/cloudflare/build.sh - build mdBook docs for Cloudflare Pages
#
# Cloudflare Pages build image has Rust/cargo at /opt/buildhome/.cargo but
# that bin dir isn't always on PATH. cargo-binstall downloads precompiled
# binaries, making this much faster than `cargo install mdbook` from source.
set -euo pipefail

# Cloudflare Pages puts cargo here; ensure it's on PATH for this script
export PATH="/opt/buildhome/.cargo/bin:$PATH"

echo "[info] Installing cargo-binstall..."
curl -L --proto '=https' --tlsv1.2 -sSf \
    https://raw.githubusercontent.com/cargo-bins/cargo-binstall/main/install-from-binstall-release.sh \
    | bash

# binstall self-installs into $CARGO_HOME/bin — re-export to pick it up
export PATH="/opt/buildhome/.cargo/bin:$PATH"

echo "[info] Installing mdbook..."
cargo-binstall mdbook --no-confirm || cargo install mdbook --locked

echo "[info] Building docs..."
mdbook build docs

echo "[ok]   Build complete → docs/book/"
