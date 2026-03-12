#!/usr/bin/env bash
# tests/entrypoint.sh - runs inside the Docker container
# 1. Bootstraps the dotfiles (skipping OS packages, which need host privileges)
# 2. Sources the runtime environment
# 3. Runs all bats test suites

set -euo pipefail

DOTFILES="$HOME/dotfiles"

# Source _lib.sh to get all PLAT vars (LOCAL_PLAT, RUSTUP_HOME, CARGO_HOME,
# VENV, UV_*) — these are inherited by bats tests.
# This also sets GIT_CONFIG_GLOBAL=/dev/null which prevents SSH URL rewrites
# from interfering with chezmoi diff and other git operations in tests.
source "$DOTFILES/install/_lib.sh"

# Source nvm so node/npm are available for the test suite
# shellcheck source=/dev/null
[[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh" && nvm use default --silent 2>/dev/null || true

# Extend PATH with all PLAT tool paths so tests can invoke tools directly
export PATH="$ARCH_BIN:$CARGO_HOME/bin:$HOME/.local/bin:$PATH"

echo "=== Bootstrap ==="
echo "PLAT: $PLAT"
echo "HOME: $HOME"
echo ""

# INSTALL_NIX=0:     Nix requires /nix on the root filesystem, not available in Docker
# INSTALL_PACKAGES=0: Homebrew Linux needs Docker-in-Docker, not available here
# INSTALL_CLAUDE=0:  Claude plugins require a running claude binary + auth
INSTALL_NIX=0 INSTALL_PACKAGES=0 INSTALL_CLAUDE=0 \
    bash "$DOTFILES/bootstrap.sh"

echo ""
echo "=== Test suite ==="
exec bats "$DOTFILES/tests/"*.bats
