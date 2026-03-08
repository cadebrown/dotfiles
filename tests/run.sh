#!/usr/bin/env bash
# tests/run.sh - build the test image and run bats tests (or an interactive shell)
#
# Usage:
#   ./tests/run.sh           # run full test suite
#   ./tests/run.sh --shell   # bootstrap then drop into interactive zsh
#
# Environment variables:
#   CHEZMOI_NAME     — display name for chezmoi config (default: "Test User")
#   CHEZMOI_EMAIL    — email for chezmoi config (default: "test@example.com")
#   DOCKER_BUILD     — set to 0 to skip rebuilding the image (faster re-runs)

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$TESTS_DIR")"

SHELL_MODE=0
[[ "${1:-}" == "--shell" ]] && SHELL_MODE=1

if [[ "${DOCKER_BUILD:-1}" != "0" ]]; then
    echo "==> Building test image"
    docker buildx build --load -t dotfiles-test "$TESTS_DIR"
fi

if [[ "$SHELL_MODE" == "1" ]]; then
    echo "==> Bootstrapping + dropping into interactive shell"
    echo "    (Packages, Nix, and Claude skipped — no Docker-in-Docker)"
    echo ""
    docker run --rm -it \
        -v "$REPO_ROOT:/home/user/dotfiles" \
        -e CHEZMOI_NAME="${CHEZMOI_NAME:-Test User}" \
        -e CHEZMOI_EMAIL="${CHEZMOI_EMAIL:-test@example.com}" \
        dotfiles-test \
        bash -c 'INSTALL_NIX=0 INSTALL_PACKAGES=0 INSTALL_CLAUDE=0 \
                 bash /home/user/dotfiles/bootstrap.sh && exec zsh -l'
else
    echo "==> Running tests"
    docker run --rm \
        -v "$REPO_ROOT:/home/user/dotfiles" \
        -e CHEZMOI_NAME="${CHEZMOI_NAME:-Test User}" \
        -e CHEZMOI_EMAIL="${CHEZMOI_EMAIL:-test@example.com}" \
        dotfiles-test \
        bash /home/user/dotfiles/tests/entrypoint.sh
fi
