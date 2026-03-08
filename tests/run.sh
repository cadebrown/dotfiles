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
    echo "==> Dropping into dotfiles shell (via chezmoi docker run)"
    echo ""
    _name="${CHEZMOI_NAME:-Test User}"
    _email="${CHEZMOI_EMAIL:-test@example.com}"
    chezmoi docker run dotfiles-test cadebrown \
        --data "{\"name\":\"$_name\",\"email\":\"$_email\"}"
else
    echo "==> Running tests"
    docker run --rm \
        -v "$REPO_ROOT:/home/user/dotfiles" \
        -e CHEZMOI_NAME="${CHEZMOI_NAME:-Test User}" \
        -e CHEZMOI_EMAIL="${CHEZMOI_EMAIL:-test@example.com}" \
        dotfiles-test \
        bash /home/user/dotfiles/tests/entrypoint.sh
fi
