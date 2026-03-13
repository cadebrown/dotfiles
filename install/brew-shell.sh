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
# HOME inside the container is the parent of BREW_PREFIX (the PLAT dir).
# We mount this parent so Homebrew can write its cache there.
_BREW_HOME="$(dirname "$BREW_PREFIX")"
mkdir -p "$_BREW_HOME"

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

# Capture git path before brew shellenv modifies PATH.
# Homebrew needs git but brew shellenv prepends its own bin/ first, and on a
# fresh install there's no brew-installed git yet. HOMEBREW_GIT_PATH pins it.
_GIT_PATH="$(command -v git 2>/dev/null || true)"

eval "$($BREW_PREFIX/bin/brew shellenv)"
export HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ANALYTICS=1 HOMEBREW_NO_ENV_HINTS=1
[[ -n "$_GIT_PATH" ]] && export HOMEBREW_GIT_PATH="$_GIT_PATH"
unset _GIT_PATH

# Patch Homebrew's Ruby build env to respect HOMEBREW_OPTFLAGS_PLAT.
#
# Problem: Library/Homebrew/extend/ENV/super.rb line ~95 unconditionally runs:
#   self["HOMEBREW_OPTFLAGS"] = determine_optflags
# On Linux, determine_optflags always returns "-march=native" because
# Library/Homebrew/extend/os/linux/extend/ENV/shared.rb hardcodes:
#   effective_arch → :native  (for Intel and ARM, regardless of OS env).
# This overwrites any HOMEBREW_OPTFLAGS we pass in from outside.
# glibc.rb then reads: cflags = "-O2 #{ENV["HOMEBREW_OPTFLAGS"]}"
# On an AVX-512 host that produces glibc compiled for x86-64-v4, crashing on
# AVX2-only machines: "Fatal glibc error: CPU does not support x86-64-v4".
#
# Fix: patch super.rb to check HOMEBREW_OPTFLAGS_PLAT first.
# We pass HOMEBREW_OPTFLAGS_PLAT (= our target march flags) via docker -e.
# The patch is idempotent — guarded by grep.
# HOMEBREW_REPOSITORY is set by brew shellenv — it's the git clone root.
_SUPER_RB="$HOMEBREW_REPOSITORY/Library/Homebrew/extend/ENV/super.rb"
if [[ -f "$_SUPER_RB" ]] && ! grep -q "HOMEBREW_OPTFLAGS_PLAT" "$_SUPER_RB"; then
    sed -i \
        's/self\["HOMEBREW_OPTFLAGS"\] = determine_optflags/self["HOMEBREW_OPTFLAGS"] = ENV["HOMEBREW_OPTFLAGS_PLAT"] || determine_optflags/' \
        "$_SUPER_RB"
    echo "[info] Patched super.rb: HOMEBREW_OPTFLAGS_PLAT overrides native detection"
elif [[ -f "$_SUPER_RB" ]]; then
    echo "[ok]   super.rb already patched"
else
    echo "[warn] super.rb not found at $_SUPER_RB — skipping patch"
fi
unset _SUPER_RB
# The glibc bootstrap gcc (an older, stripped-down GCC) doesn't support the
# x86-64-v{n} syntax added in GCC 11. Translate to baseline -march=x86-64 so
# configure can compile its test file. glibc is the only source-built package;
# user tools (jq, bat, etc.) pour as pre-compiled bottles and are unaffected.
HOMEBREW_OPTFLAGS_PLAT="${HOMEBREW_OPTFLAGS_PLAT//-march=x86-64-v?/-march=x86-64}"
export HOMEBREW_OPTFLAGS_PLAT
echo "[info] HOMEBREW_OPTFLAGS_PLAT: ${HOMEBREW_OPTFLAGS_PLAT:-<unset>}"

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
    -v "$_BREW_HOME:$_BREW_HOME" \
    -e HOME="$_BREW_HOME" \
    -e BREW_PREFIX="$BREW_PREFIX" \
    -e HOMEBREW_NO_AUTO_UPDATE=1 \
    -e HOMEBREW_NO_ANALYTICS=1 \
    -e HOMEBREW_NO_ENV_HINTS=1 \
    -e HOMEBREW_OPTFLAGS="${HOMEBREW_OPTFLAGS:-}" \
    -e HOMEBREW_OPTFLAGS_PLAT="${HOMEBREW_OPTFLAGS:-}" \
    "$IMAGE" \
    bash -c "$_CMD"
