#!/usr/bin/env bash
# install/brew-shell.sh - interactive Homebrew shell inside the manylinux container
#
# Useful for debugging package builds, testing bottles vs. source, and
# verifying binaries work inside and outside the container.
#
# Usage:
#   bash install/brew-shell.sh                          # interactive shell (default brew prefix)
#   bash install/brew-shell.sh -- brew install jq       # run a single command and exit
#   bash install/brew-shell.sh -- brew install jq bat   # install multiple packages
#
# Override the brew prefix:
#   BREW_PREFIX=/tmp/test-brew bash install/brew-shell.sh
#
# Inside the shell:
#   brew install <formula>    install a package (bottles by default)
#   brew install --build-from-source <formula>   build from source
#   brew test <formula>       run formula tests
#   ldd <binary>              check shared library dependencies
#   file <binary>             check arch / ELF type
#   exit                      return to host
#
# After exiting, test on the host:
#   $BREW_PREFIX/bin/jq --version
#   file $BREW_PREFIX/bin/jq
#   ldd $BREW_PREFIX/bin/jq

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

[[ "$OS" == "linux" ]] || { log_warn "brew-shell.sh is Linux-only"; exit 1; }

### Container runtime ###

if has docker; then
    RUNTIME="docker"
elif has podman; then
    RUNTIME="podman"
else
    die "Docker or Podman is required"
fi

### Image ###

case "$ARCH" in
    aarch64) IMAGE="quay.io/pypa/manylinux_2_28_aarch64" ;;
    x86_64)  IMAGE="quay.io/pypa/manylinux_2_28_x86_64"  ;;
    *)       die "No manylinux image for arch: $ARCH" ;;
esac

### Paths ###

# Resolve through symlinks so Docker can mount the real filesystem path.
_REAL_LOCAL="$(readlink -f "$HOME/.local")"
_REAL_LOCAL_PLAT="$_REAL_LOCAL/$PLAT"
_DEFAULT_BREW_PREFIX="$_REAL_LOCAL_PLAT/brew"
BREW_PREFIX="${BREW_PREFIX:-$_DEFAULT_BREW_PREFIX}"
# Resolve prefix itself in case it's under a symlink dir
mkdir -p "$BREW_PREFIX"
BREW_PREFIX="$(readlink -f "$BREW_PREFIX")"

### passwd/group so `whoami` works (required by Homebrew) ###

_PASSWD_TMP="$(mktemp)"
_GROUP_TMP="$(mktemp)"
trap 'rm -f "$_PASSWD_TMP" "$_GROUP_TMP"' EXIT
{ cat /etc/passwd 2>/dev/null; getent passwd "$(whoami)" 2>/dev/null; } \
    | sort -u -t: -k3,3n > "$_PASSWD_TMP"
{ cat /etc/group 2>/dev/null; getent group "$(id -gn)" 2>/dev/null; } \
    | sort -u -t: -k3,3n > "$_GROUP_TMP"

### Startup script (runs first inside the container) ###

_BREW_INIT=$(cat << 'INIT_EOF'
set -euo pipefail

if [[ ! -x "$BREW_PREFIX/bin/brew" ]]; then
    echo "[info] Cloning Homebrew → $BREW_PREFIX"
    git clone --depth=1 https://github.com/Homebrew/brew "$BREW_PREFIX" 2>&1 \
        | grep -v "^remote:" || true
    echo "[ok]   Homebrew cloned"
else
    echo "[ok]   Homebrew already at $BREW_PREFIX"
fi

eval "$($BREW_PREFIX/bin/brew shellenv)"
export HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ANALYTICS=1 HOMEBREW_NO_ENV_HINTS=1

_glibc_ver=$(ldd --version 2>&1 | head -1 | grep -oP '\d+\.\d+$' || echo "?")
_brew_ver=$(brew --version 2>/dev/null | head -1 || echo "?")
echo ""
echo "  $_brew_ver"
echo "  prefix:  $BREW_PREFIX"
echo "  glibc:   $_glibc_ver (container)"
echo "  arch:    $(uname -m)"
echo ""
INIT_EOF
)

### Mode: interactive vs. single command ###

if [[ $# -gt 0 && "$1" == "--" ]]; then
    # Non-interactive: run the command after --
    shift
    _CMD="$_BREW_INIT; $*"
    _DOCKER_IT=()
    log_info "Running in container: $*"
else
    # Interactive: drop into a shell
    _CMD="$_BREW_INIT; exec bash --norc --noprofile -i"
    _DOCKER_IT=(-it)
    log_info "Launching interactive brew shell"
fi

log_info "Image:  $IMAGE"
log_info "Prefix: $BREW_PREFIX"
log_info ""

"$RUNTIME" run --rm "${_DOCKER_IT[@]}" \
    --user "$(id -u):$(id -g)" \
    -v "$_PASSWD_TMP:/etc/passwd:ro" \
    -v "$_GROUP_TMP:/etc/group:ro" \
    -v "$BREW_PREFIX:$BREW_PREFIX" \
    -e HOME="$(dirname "$BREW_PREFIX")" \
    -e BREW_PREFIX="$BREW_PREFIX" \
    -e HOMEBREW_NO_AUTO_UPDATE=1 \
    -e HOMEBREW_NO_ANALYTICS=1 \
    -e HOMEBREW_NO_ENV_HINTS=1 \
    "$IMAGE" \
    bash -c "$_CMD"
