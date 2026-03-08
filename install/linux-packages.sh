#!/usr/bin/env bash
# install/linux-packages.sh - install packages on Linux via Homebrew
#
# Runs Homebrew inside a manylinux_2_17 container (glibc 2.17, CentOS 7) so
# compiled binaries work on any Linux since ~2014 — no glibc version conflicts.
#
# Requires Docker (rootless) or Podman. No sudo needed on the host.
# See docs/setup/bootstrap.md for setup instructions.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

[[ "$OS" == "linux" ]] || { log_warn "Not on Linux — skipping"; exit 0; }

log_section "Linux packages (Homebrew via manylinux container)"

### Detect container runtime ###

if has docker; then
    RUNTIME="docker"
elif has podman; then
    RUNTIME="podman"
else
    log_error "Docker (rootless) or Podman is required for Linux package install."
    log_info "See docs/setup/bootstrap.md for installation instructions."
    exit 1
fi
log_info "Container runtime: $RUNTIME"

### Select image ###

# manylinux_2_17 = CentOS 7 = glibc 2.17
# Binaries compiled here run on any Linux with glibc >= 2.17 (~2014+)
case "$ARCH" in
    aarch64) IMAGE="quay.io/pypa/manylinux_2_17_aarch64" ;;
    x86_64)  IMAGE="quay.io/pypa/manylinux_2_17_x86_64"  ;;
    *)       log_error "No manylinux image for arch: $ARCH"; exit 1 ;;
esac
log_info "Build image:       $IMAGE"

BREW_PREFIX="$LOCAL_PLAT/brew"
log_info "Homebrew prefix:   $BREW_PREFIX"

log_info "Pulling $IMAGE"
"$RUNTIME" pull "$IMAGE"

### Run Homebrew inside the container ###
#
# Key design points:
#   - $HOME mounted at the same path → compiled RPATH entries resolve on host
#   - /etc/passwd + /etc/group mounted read-only → `whoami` works (required by Homebrew)
#   - --user $(id -u):$(id -g) → Homebrew refuses to run as root
#   - BREW_PREFIX and BREWFILE passed via -e → inner script uses them
#   - if OS.mac? blocks in Brewfile are automatically skipped (Linux host)

log_info "Running brew bundle in container (first run compiles from source — this takes a while)"

"$RUNTIME" run --rm \
    --user "$(id -u):$(id -g)" \
    -v /etc/passwd:/etc/passwd:ro \
    -v /etc/group:/etc/group:ro \
    -v "$HOME:$HOME" \
    -v "$DOTFILES_ROOT:$DOTFILES_ROOT" \
    -e HOME="$HOME" \
    -e BREW_PREFIX="$BREW_PREFIX" \
    -e BREWFILE="$PACKAGES_DIR/Brewfile" \
    -e HOMEBREW_NO_AUTO_UPDATE=1 \
    -e HOMEBREW_NO_ANALYTICS=1 \
    -e HOMEBREW_NO_ENV_HINTS=1 \
    "$IMAGE" \
    bash << 'EOF'
set -euo pipefail

# Install Homebrew to the PLAT-specific prefix if not already there
if [[ ! -x "$BREW_PREFIX/bin/brew" ]]; then
    echo "[info] Installing Homebrew → $BREW_PREFIX"
    mkdir -p "$BREW_PREFIX"
    curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh \
        | NONINTERACTIVE=1 HOMEBREW_PREFIX="$BREW_PREFIX" bash
else
    echo "[ok]   Homebrew already installed at $BREW_PREFIX"
fi

export PATH="$BREW_PREFIX/bin:$PATH"

# if OS.mac? blocks in Brewfile are skipped automatically on Linux
echo "[info] Running brew bundle (--no-upgrade for idempotency)"
brew bundle install --file="$BREWFILE" --no-upgrade
EOF

log_ok "Linux packages installed at $BREW_PREFIX"
log_info "Activate with: eval \"\$($BREW_PREFIX/bin/brew shellenv)\""
