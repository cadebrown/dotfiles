#!/usr/bin/env bash
# tests/entrypoint.sh - runs inside the Docker container
# 1. Bootstraps the dotfiles (skipping OS packages, which need host privileges)
# 2. Sources the runtime environment
# 3. Runs all bats test suites

set -euo pipefail

DOTFILES="$HOME/dotfiles"

# The Docker test image specifically exercises PLAT-on isolation — that's the
# layout that needs the most verification (NFS-shared-home invariants). The
# default for normal users is the flat layout (DF_USE_PLAT=0).
export DF_USE_PLAT=1
export DF_PROFILE=core

# Source _lib.sh to get all PLAT vars (LOCAL_PLAT, RUSTUP_HOME, CARGO_HOME,
# PYTHON_ENV, UV_*) — these are inherited by bats tests.
# This also sets GIT_CONFIG_GLOBAL=/dev/null which prevents SSH URL rewrites
# from interfering with chezmoi diff and other git operations in tests.
source "$DOTFILES/install/_lib.sh"

# Source nvm so node/npm are available for the test suite
# shellcheck source=/dev/null
[[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh" && nvm use default --silent 2>/dev/null || true

# Keep ARCH_BIN off PATH during bootstrap. Installers must invoke binaries in
# their owned PLAT directly; the login environment adds these paths afterward.
export PATH="$CARGO_HOME/bin:$HOME/.local/bin:$PATH"

echo "=== Bootstrap ==="
echo "PLAT: $PLAT"
echo "HOME: $HOME"
echo ""

# DF_PROFILE=core: skips workstation-only Python tools such as Manim/WhisperX
# DF_DO_PACKAGES=0: Homebrew Linux needs Docker-in-Docker, not available here
# DF_DO_GO=0 / DF_DO_LOCAL_LLM=0: both depend on Brewfile commands in this image
# DF_DO_CLAUDE=0:  Claude plugins require a running claude binary + auth
# DF_DO_MEMORY=0 / DF_DO_SKILLS=0: avoid model downloads and remote skill installs
# DF_DO_JULIA=0 / DF_DO_LEAN=0 / DF_DO_LATEX=0: large language toolchains are
#   covered by static contract tests rather than downloaded on every test run.
# DF_DO_QUARTO=0: the archive installer is covered by the same contract tests.
# DF_DO_OVERLAYS=0: local/private overlay bootstraps have their own dependencies.
DF_DO_PACKAGES=0 DF_DO_LLDB=0 DF_DO_GO=0 DF_DO_LOCAL_LLM=0 \
    DF_DO_CLAUDE=0 DF_DO_CODEX=0 DF_DO_MEMORY=0 DF_DO_SKILLS=0 \
    DF_DO_QUARTO=0 DF_DO_JULIA=0 DF_DO_LEAN=0 DF_DO_LATEX=0 \
    DF_DO_OVERLAYS="${DF_DO_OVERLAYS:-0}" \
    bash "$DOTFILES/bootstrap.sh"

export PATH="$ARCH_BIN:$PATH"

echo ""
echo "=== Test suite ==="
exec bats "$DOTFILES/tests/"*.bats
