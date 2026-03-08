#!/usr/bin/env bash
# tests/run.sh - build the test image and run all bats test suites in Docker
#
# Usage:
#   ./tests/run.sh
#
# Environment variables:
#   CHEZMOI_NAME     — display name for chezmoi config (default: "Test User")
#   CHEZMOI_EMAIL    — email for chezmoi config (default: "test@example.com")
#   DOCKER_BUILD     — set to 0 to skip rebuilding the image (faster re-runs)

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$TESTS_DIR")"

if [[ "${DOCKER_BUILD:-1}" != "0" ]]; then
    echo "==> Building test image"
    docker buildx build --load -t dotfiles-test "$TESTS_DIR"
fi

echo "==> Running tests"
docker run --rm \
    -v "$REPO_ROOT:/home/user/dotfiles" \
    -e CHEZMOI_NAME="${CHEZMOI_NAME:-Test User}" \
    -e CHEZMOI_EMAIL="${CHEZMOI_EMAIL:-test@example.com}" \
    dotfiles-test \
    bash /home/user/dotfiles/tests/entrypoint.sh
