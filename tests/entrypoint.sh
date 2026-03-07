#!/usr/bin/env bash
# tests/entrypoint.sh - runs inside the Docker container
# 1. Bootstraps the dotfiles (skipping OS packages, which need host privileges)
# 2. Sources the runtime environment
# 3. Runs all bats test suites

set -euo pipefail

DOTFILES="$HOME/dotfiles"

# Source _lib.sh to get all PLAT vars (LOCAL_PLAT, NVM_DIR, RUSTUP_HOME,
# CARGO_HOME, VENV, UV_*) — these are inherited by bats tests.
# This also sets GIT_CONFIG_GLOBAL=/dev/null which prevents SSH URL rewrites
# from interfering with chezmoi diff and other git operations in tests.
source "$DOTFILES/install/_lib.sh"

# Extend PATH with all PLAT tool paths so tests can invoke tools directly
export PATH="$ARCH_BIN:$CARGO_HOME/bin:$HOME/.local/bin:$PATH"

echo "=== Bootstrap ==="
echo "PLAT: $PLAT"
echo "HOME: $HOME"
echo ""

# INSTALL_PACKAGES=0: skip Homebrew/Nix — requires host-level privileges in Docker
INSTALL_PACKAGES=0 bash "$DOTFILES/bootstrap.sh"

# Source nvm into this session so node is on PATH for tests
# (bootstrap installs it but doesn't source it for the current process)
if [[ -s "$NVM_DIR/nvm.sh" ]]; then
    # shellcheck disable=SC1091
    source "$NVM_DIR/nvm.sh"
fi

echo ""
echo "=== Test suite ==="
exec bats "$DOTFILES/tests/"*.bats
