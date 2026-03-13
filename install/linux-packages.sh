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

BREW_PREFIX="${BREW_PREFIX:-$LOCAL_PLAT/brew}"
log_info "Homebrew prefix:   $BREW_PREFIX"

log_info "Pulling $IMAGE"
"$RUNTIME" pull "$IMAGE"

### Run Homebrew inside the container ###
#
# Key design points:
#   - Resolve all paths to real (non-symlink) locations so Docker can mount them.
#     On NFS homes with scratch symlinks, $HOME and $LOCAL_PLAT may be on different
#     filesystems. Docker can't always mount NFS paths, so we resolve through symlinks
#     and mount the real paths at their real locations.
#   - BREW_PREFIX resolves to real scratch path → compiled RPATH entries resolve on host
#   - /etc/passwd + /etc/group mounted read-only → `whoami` works (required by Homebrew)
#   - --user $(id -u):$(id -g) → Homebrew refuses to run as root
#   - BREW_PREFIX and BREWFILE passed via -e → inner script uses them
#   - if OS.mac? blocks in Brewfile are automatically skipped (Linux host)

# Resolve symlinks so Docker mounts the real filesystem paths.
# On NFS homes with scratch symlinks, Docker can't mount NFS paths directly.
# If BREW_PREFIX was overridden (e.g. building v3 from a v4 machine), resolve
# from that path; otherwise derive from LOCAL_PLAT as usual.
mkdir -p "$BREW_PREFIX"
_REAL_BREW_PREFIX="$(readlink -f "$BREW_PREFIX")"
_REAL_LOCAL_PLAT="$(dirname "$_REAL_BREW_PREFIX")"

# Copy Brewfile to scratch so it's accessible inside the container.
# The source repo may be on NFS which Docker can't mount.
_BREWFILE_TMP="$_REAL_LOCAL_PLAT/.Brewfile"
cp "$PACKAGES_DIR/Brewfile" "$_BREWFILE_TMP"

# Generate a passwd/group file for the container. On LDAP/NIS systems the
# current user may not be in /etc/passwd, but Homebrew requires `whoami` to
# work. We merge the system file with the current user's entry.
# Use /tmp so Docker can mount these regardless of NFS restrictions.
_PASSWD_TMP="$(mktemp)"
_GROUP_TMP="$(mktemp)"
{ cat /etc/passwd 2>/dev/null; getent passwd "$(whoami)" 2>/dev/null; } | sort -u -t: -k3,3n > "$_PASSWD_TMP"
{ cat /etc/group 2>/dev/null; getent group "$(id -gn)" 2>/dev/null; } | sort -u -t: -k3,3n > "$_GROUP_TMP"

log_info "Resolved paths:"
log_info "  BREW_PREFIX: $_REAL_BREW_PREFIX"
log_info "  Brewfile:    $_BREWFILE_TMP"

# HOMEBREW_OPTFLAGS controls the -march= flag for packages built from source.
# The main package that always builds from source is glibc (no bottle for
# custom prefixes). Other packages pour as precompiled bottles and are not
# affected by this flag.
#
# Source: set by .plat_env.sh when _lib.sh detects PLAT (e.g. plat_Linux_x86-64-v3).
# Each PLAT on an NFS home gets its own brew prefix, so glibc is compiled with
# the right -march= for the machines that share that PLAT dir.
# If HOMEBREW_OPTFLAGS is unset (e.g. curl|bash first run before PLAT detection),
# fall back to x86-64-v2 as a safe generic baseline.
HOMEBREW_OPTFLAGS="${HOMEBREW_OPTFLAGS:--march=x86-64-v2 -O2}"
log_info "HOMEBREW_OPTFLAGS: $HOMEBREW_OPTFLAGS"

log_info "Running brew bundle in container (first run builds glibc from source — ~10 min; subsequent runs pour bottles)"

"$RUNTIME" run --rm -i \
    --user "$(id -u):$(id -g)" \
    -v "$_PASSWD_TMP:/etc/passwd:ro" \
    -v "$_GROUP_TMP:/etc/group:ro" \
    -v "$_REAL_LOCAL_PLAT:$_REAL_LOCAL_PLAT" \
    -e HOME="$_REAL_LOCAL_PLAT" \
    -e BREW_PREFIX="$_REAL_BREW_PREFIX" \
    -e BREWFILE="$_BREWFILE_TMP" \
    -e HOMEBREW_NO_AUTO_UPDATE=1 \
    -e HOMEBREW_NO_ANALYTICS=1 \
    -e HOMEBREW_NO_ENV_HINTS=1 \
    -e HOMEBREW_OPTFLAGS="$HOMEBREW_OPTFLAGS" \
    -e HOMEBREW_OPTFLAGS_PLAT="$HOMEBREW_OPTFLAGS" \
    "$IMAGE" \
    bash << 'OUTER_EOF'
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

_GIT_PATH="$(command -v git 2>/dev/null || true)"
eval "$($BREW_PREFIX/bin/brew shellenv)"
[[ -n "$_GIT_PATH" ]] && export HOMEBREW_GIT_PATH="$_GIT_PATH"
unset _GIT_PATH

# Patch Homebrew's Ruby build env to respect HOMEBREW_OPTFLAGS_PLAT.
# super.rb unconditionally sets self["HOMEBREW_OPTFLAGS"] = determine_optflags,
# and on Linux determine_optflags always returns "-march=native".
# This patch makes it check HOMEBREW_OPTFLAGS_PLAT first (passed via docker -e).
# The glibc bootstrap gcc (an older, stripped-down GCC) doesn't support the
# x86-64-v{n} syntax added in GCC 11. Translate to baseline -march=x86-64 so
# configure can compile its test file. glibc is the only source-built package;
# user tools (jq, bat, etc.) pour as pre-compiled bottles and are unaffected.
HOMEBREW_OPTFLAGS_PLAT="${HOMEBREW_OPTFLAGS_PLAT//-march=x86-64-v?/-march=x86-64}"
export HOMEBREW_OPTFLAGS_PLAT
echo "[info] HOMEBREW_OPTFLAGS_PLAT: ${HOMEBREW_OPTFLAGS_PLAT:-<unset>}"
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

brew bundle install --file="$BREWFILE" --no-upgrade 2>&1
OUTER_EOF

rm -f "$_BREWFILE_TMP" "$_PASSWD_TMP" "$_GROUP_TMP" 2>/dev/null || true

log_ok "Linux packages installed at $BREW_PREFIX"
log_info "Activate with: eval \"\$($BREW_PREFIX/bin/brew shellenv)\""
