#!/usr/bin/env bash
# install/linux-packages.sh - install packages on Linux via Homebrew
#
# Runs Homebrew inside a manylinux_2_28 container (AlmaLinux 8, glibc 2.28) so
# compiled binaries work on any Linux since ~2018 — no glibc version conflicts.
# Most packages pour as precompiled bottles; Homebrew bundles its own glibc 2.35.
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

# manylinux_2_28 = AlmaLinux 8 = glibc 2.28
# Bottles pour directly; Homebrew bundles glibc 2.35 so binaries are self-contained.
case "$ARCH" in
    aarch64) IMAGE="quay.io/pypa/manylinux_2_28_aarch64" ;;
    x86_64)  IMAGE="quay.io/pypa/manylinux_2_28_x86_64"  ;;
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

log_info "Running brew bundle in container (first run installs bottles + builds glibc — takes ~10 min)"

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

# Install Homebrew via git clone to user-local prefix (no sudo).
# The official installer forces /home/linuxbrew/.linuxbrew — git clone is the
# supported alternative for custom prefixes.
if [[ ! -x "$BREW_PREFIX/bin/brew" ]]; then
    echo "[info] Installing Homebrew → $BREW_PREFIX"
    mkdir -p "$BREW_PREFIX"
    git clone --depth=1 https://github.com/Homebrew/brew "$BREW_PREFIX/Homebrew"
    mkdir -p "$BREW_PREFIX/bin"
    ln -sf "$BREW_PREFIX/Homebrew/bin/brew" "$BREW_PREFIX/bin/brew"
else
    echo "[ok]   Homebrew already installed at $BREW_PREFIX"
fi

eval "$($BREW_PREFIX/bin/brew shellenv)"

# if OS.mac? blocks in Brewfile are skipped automatically on Linux
echo "[info] Running brew bundle (--no-upgrade for idempotency)"
brew bundle install --file="$BREWFILE" --no-upgrade
EOF

log_ok "Linux packages installed at $BREW_PREFIX"
log_info "Activate with: eval \"\$($BREW_PREFIX/bin/brew shellenv)\""
