#!/usr/bin/env bash
# install/linux-packages.sh - install packages on Linux via Homebrew
#
# By default, runs Homebrew inside a manylinux_2_28 container (AlmaLinux 8,
# glibc 2.28) so compiled binaries work on any Linux since ~2018.
# Set HOMEBREW_NO_CONTAINER=1 to run directly on the host instead — useful
# when Docker/Podman is unavailable or the user lacks permission to use it.
#
# Most packages pour as precompiled bottles; Homebrew bundles its own glibc 2.35.
# glibc is the only package built from source (no bottle for custom prefixes).

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

[[ "$OS" == "linux" ]] || { log_warn "Not on Linux — skipping"; exit 0; }

log_section "Linux packages (Homebrew)"

### Detect container runtime ###

_USE_CONTAINER=1
if [[ "${HOMEBREW_NO_CONTAINER:-0}" == "1" ]]; then
    _USE_CONTAINER=0
    log_info "Container: disabled (HOMEBREW_NO_CONTAINER=1)"
elif has docker && docker info >/dev/null 2>&1; then
    RUNTIME="docker"
elif has podman; then
    RUNTIME="podman"
else
    _USE_CONTAINER=0
    log_warn "Docker/Podman not available or not accessible — running on host"
fi

if [[ $_USE_CONTAINER == 1 ]]; then
    log_info "Container runtime: $RUNTIME"

    case "$ARCH" in
        aarch64) IMAGE="quay.io/pypa/manylinux_2_28_aarch64" ;;
        x86_64)  IMAGE="quay.io/pypa/manylinux_2_28_x86_64"  ;;
        *)       log_error "No manylinux image for arch: $ARCH"; exit 1 ;;
    esac
    log_info "Build image:       $IMAGE"
else
    log_info "Running directly on host (native glibc, no isolation)"
fi

BREW_PREFIX="${BREW_PREFIX:-$LOCAL_PLAT/brew}"
log_info "Homebrew prefix:   $BREW_PREFIX"

### Resolve paths ###

# Resolve symlinks so Docker can mount real filesystem paths.
# On NFS homes with scratch symlinks, Docker can't mount NFS paths directly.
mkdir -p "$BREW_PREFIX"
_REAL_BREW_PREFIX="$(readlink -f "$BREW_PREFIX")"
_REAL_LOCAL_PLAT="$(dirname "$_REAL_BREW_PREFIX")"

_BREWFILE_TMP="$_REAL_LOCAL_PLAT/.Brewfile"
_SCRIPT_TMP="$(mktemp --suffix=.sh)"
trap 'rm -f "$_BREWFILE_TMP" "$_SCRIPT_TMP" 2>/dev/null || true' EXIT

cp "$PACKAGES_DIR/Brewfile" "$_BREWFILE_TMP"

### HOMEBREW_OPTFLAGS ###

# Controls the -march= flag for packages built from source (only glibc).
# In container mode, this is passed as HOMEBREW_OPTFLAGS_PLAT to override
# Homebrew's native detection. In no-container mode (native), we leave
# HOMEBREW_OPTFLAGS_PLAT unset so Homebrew detects the real CPU natively.
HOMEBREW_OPTFLAGS="${HOMEBREW_OPTFLAGS:--march=x86-64-v2 -O2}"
log_info "HOMEBREW_OPTFLAGS: $HOMEBREW_OPTFLAGS"

log_info "Resolved paths:"
log_info "  BREW_PREFIX: $_REAL_BREW_PREFIX"
log_info "  Brewfile:    $_BREWFILE_TMP"

### Inner install script ###
#
# Shared between container and no-container paths.
# Env vars are injected by the caller (docker -e or env prefix).

cat > "$_SCRIPT_TMP" << 'SCRIPT_EOF'
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

# Capture git path before brew shellenv modifies PATH.
_GIT_PATH="$(command -v git 2>/dev/null || true)"
eval "$($BREW_PREFIX/bin/brew shellenv)"
export HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ANALYTICS=1 HOMEBREW_NO_ENV_HINTS=1
[[ -n "$_GIT_PATH" ]] && export HOMEBREW_GIT_PATH="$_GIT_PATH"
unset _GIT_PATH

# Patch Homebrew's Ruby build env to respect HOMEBREW_OPTFLAGS_PLAT.
#
# Problem: Library/Homebrew/extend/ENV/super.rb unconditionally runs:
#   self["HOMEBREW_OPTFLAGS"] = determine_optflags
# On Linux, determine_optflags always returns "-march=native" because
# Library/Homebrew/extend/os/linux/extend/ENV/shared.rb hardcodes
# effective_arch → :native, overwriting any HOMEBREW_OPTFLAGS we pass in.
# glibc.rb then reads: cflags = "-O2 #{ENV["HOMEBREW_OPTFLAGS"]}"
#
# Fix: patch super.rb to check HOMEBREW_OPTFLAGS_PLAT first.
# In container mode: HOMEBREW_OPTFLAGS_PLAT is passed via docker -e.
#   The x86-64-v{n} march values are translated to x86-64 (GCC 9 bootstrap
#   gcc doesn't support the newer syntax). glibc builds with -O2 -march=x86-64.
# In no-container (native) mode: HOMEBREW_OPTFLAGS_PLAT is NOT set, so
#   determine_optflags runs normally → -march=native = real CPU march → correct.
if [[ -n "${HOMEBREW_OPTFLAGS_PLAT:-}" ]]; then
    # Translate x86-64-v{n} → x86-64 for bootstrap gcc (GCC 9) compatibility.
    HOMEBREW_OPTFLAGS_PLAT="${HOMEBREW_OPTFLAGS_PLAT//-march=x86-64-v?/-march=x86-64}"
    export HOMEBREW_OPTFLAGS_PLAT
    echo "[info] HOMEBREW_OPTFLAGS_PLAT: $HOMEBREW_OPTFLAGS_PLAT"
else
    echo "[info] HOMEBREW_OPTFLAGS_PLAT: <unset — using native CPU detection>"
fi

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

brew bundle install --file="$BREWFILE" --no-upgrade 2>&1
SCRIPT_EOF

### Run ###

if [[ $_USE_CONTAINER == 1 ]]; then
    _PASSWD_TMP="$(mktemp)"
    _GROUP_TMP="$(mktemp)"
    trap 'rm -f "$_BREWFILE_TMP" "$_SCRIPT_TMP" "$_PASSWD_TMP" "$_GROUP_TMP" 2>/dev/null || true' EXIT
    { cat /etc/passwd 2>/dev/null; getent passwd "$(whoami)" 2>/dev/null; } | sort -u -t: -k3,3n > "$_PASSWD_TMP"
    { cat /etc/group 2>/dev/null; getent group "$(id -gn)" 2>/dev/null; } | sort -u -t: -k3,3n > "$_GROUP_TMP"

    log_info "Pulling $IMAGE"
    "$RUNTIME" pull "$IMAGE"
    log_info "Running brew bundle in container (first run builds glibc ~10 min; subsequent runs pour bottles)"

    "$RUNTIME" run --rm -i \
        --user "$(id -u):$(id -g)" \
        -v "$_PASSWD_TMP:/etc/passwd:ro" \
        -v "$_GROUP_TMP:/etc/group:ro" \
        -v "$_REAL_LOCAL_PLAT:$_REAL_LOCAL_PLAT" \
        -v "$_SCRIPT_TMP:$_SCRIPT_TMP:ro" \
        -e HOME="$_REAL_LOCAL_PLAT" \
        -e BREW_PREFIX="$_REAL_BREW_PREFIX" \
        -e BREWFILE="$_BREWFILE_TMP" \
        -e HOMEBREW_NO_AUTO_UPDATE=1 \
        -e HOMEBREW_NO_ANALYTICS=1 \
        -e HOMEBREW_NO_ENV_HINTS=1 \
        -e HOMEBREW_OPTFLAGS="$HOMEBREW_OPTFLAGS" \
        -e HOMEBREW_OPTFLAGS_PLAT="$HOMEBREW_OPTFLAGS" \
        "$IMAGE" \
        bash "$_SCRIPT_TMP"
else
    log_info "Running brew bundle on host (first run builds glibc ~10 min; subsequent runs pour bottles)"
    BREW_PREFIX="$_REAL_BREW_PREFIX" \
    BREWFILE="$_BREWFILE_TMP" \
    HOMEBREW_NO_AUTO_UPDATE=1 \
    HOMEBREW_NO_ANALYTICS=1 \
    HOMEBREW_NO_ENV_HINTS=1 \
    HOMEBREW_OPTFLAGS="$HOMEBREW_OPTFLAGS" \
    bash "$_SCRIPT_TMP"
fi

log_ok "Linux packages installed at $BREW_PREFIX"
log_info "Activate with: eval \"\$($BREW_PREFIX/bin/brew shellenv)\""
