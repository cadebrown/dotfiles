#!/usr/bin/env bash
# install/linux-packages.sh - install packages on Linux via Homebrew
#
# Runs Homebrew directly on the host — no container, no Docker, no sudo.
# Homebrew installs its own glibc 2.35 so binaries are self-contained and
# portable across Linux systems regardless of the host glibc version.
#
# Most packages pour as precompiled bottles. glibc builds from source (~2 min)
# on first install and is installed explicitly before brew bundle so that all
# subsequent bottles link against Homebrew's glibc rather than the system one.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

[[ "$OS" == "linux" ]] || { log_warn "Not on Linux — skipping"; exit 0; }

DF_INSTALL_DIR="${DF_INSTALL_DIR:-$DF_ROOT/install}"

log_section "Linux packages (Homebrew)"

BREW_PREFIX="${BREW_PREFIX:-$LOCAL_PLAT/brew}"
log_info "Homebrew prefix:   $BREW_PREFIX"

### Resolve symlinks ###
# readlink -f so paths are real filesystem paths (NFS homes may have symlinks).
mkdir -p "$BREW_PREFIX"
_REAL_BREW_PREFIX="$(readlink -f "$BREW_PREFIX")"
_REAL_LOCAL_PLAT="$(dirname "$_REAL_BREW_PREFIX")"

_BREWFILE_TMP="$_REAL_LOCAL_PLAT/.Brewfile"
trap 'rm -f "$_BREWFILE_TMP" 2>/dev/null || true' EXIT
cp "$DF_PACKAGES/Brewfile" "$_BREWFILE_TMP"

log_info "Resolved prefix:   $_REAL_BREW_PREFIX"
log_info "Brewfile:          $_BREWFILE_TMP"

### Install Homebrew ###

if [[ ! -x "$_REAL_BREW_PREFIX/bin/brew" ]]; then
    log_info "Installing Homebrew → $_REAL_BREW_PREFIX"
    git clone --depth=1 https://github.com/Homebrew/brew "$_REAL_BREW_PREFIX/Homebrew"
    mkdir -p "$_REAL_BREW_PREFIX/bin"
    ln -sf "$_REAL_BREW_PREFIX/Homebrew/bin/brew" "$_REAL_BREW_PREFIX/bin/brew"
else
    log_okay "Homebrew already installed at $_REAL_BREW_PREFIX"
fi

# Capture git path before brew shellenv modifies PATH.
_GIT_PATH="$(command -v git 2>/dev/null || true)"
eval "$($_REAL_BREW_PREFIX/bin/brew shellenv)"
export HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ANALYTICS=1 HOMEBREW_NO_ENV_HINTS=1
[[ -n "$_GIT_PATH" ]] && export HOMEBREW_GIT_PATH="$_GIT_PATH"
unset _GIT_PATH

### Install glibc first ###
#
# Homebrew's glibc (2.35) makes all bottles self-contained — binaries use
# Homebrew's own loader (brew/lib/ld.so → opt/glibc/bin/ld.so) which resolves
# libc from the Cellar rather than the host system. Without this step, machines
# whose system glibc is already ≥ 2.35 would skip glibc and binaries would
# silently depend on the host glibc — breaking portability to older systems.
if brew list glibc &>/dev/null; then
    log_okay "glibc already installed"
else
    log_info "Installing glibc (builds from source, ~2 min)..."
    brew install glibc 2>&1
fi

### Fix Homebrew OpenSSL cert.pem symlink ###
#
# openssl@3 expects its cert.pem at $BREW_PREFIX/etc/openssl@3/cert.pem, but
# the ca-certificates formula only populates $BREW_PREFIX/etc/ca-certificates/cert.pem.
# On standard Homebrew installs a symlink is created automatically; on custom prefixes
# (non-/home/linuxbrew/.linuxbrew) the post-install hook sometimes doesn't fire.
# Without the symlink, Brew's Python/OpenSSL can't verify SSL certs, causing build
# failures when tools like meson try to download crates.io subproject sources.
_openssl_cert="$_REAL_BREW_PREFIX/etc/openssl@3/cert.pem"
_brew_ca_cert="$_REAL_BREW_PREFIX/etc/ca-certificates/cert.pem"
if [[ ! -e "$_openssl_cert" && -f "$_brew_ca_cert" ]]; then
    mkdir -p "$(dirname "$_openssl_cert")"
    ln -sf "$_brew_ca_cert" "$_openssl_cert"
    log_okay "Created $BREW_PREFIX/etc/openssl@3/cert.pem → ca-certificates/cert.pem"
elif [[ -e "$_openssl_cert" ]]; then
    log_okay "openssl@3/cert.pem already exists"
else
    log_warn "ca-certificates/cert.pem not found — SSL may fail for source builds"
fi
unset _openssl_cert _brew_ca_cert

### Patch Homebrew formulas for Linux compatibility ###
#
# Several Homebrew formulas don't build cleanly on a custom Linux prefix due to
# upstream assumptions about the build environment. We patch formula Ruby files
# in-place before running brew bundle. All patches are idempotent (safe to re-run)
# and print 'already applied' if the target formula has already been patched.
#
# Each patch script documents:
#   - WHY: the root cause and upstream issue
#   - WHAT: exactly what the patch changes
#   - SIDE EFFECTS: what you lose (usually nothing useful on a headless server)
#   - WHEN TO REMOVE: the conditions under which the patch is no longer needed
#   - SKIP FLAG: per-patch DF_PATCH_BREW_* env var to disable individually
#
# Master skip: DF_PATCH_BREW_ALL=0 disables all formula patches at once (useful
# to test whether upstream has fixed things, or if you've already applied them):
#   DF_PATCH_BREW_ALL=0 bash install/linux-packages.sh
#
# Individual skips (also supported, see each script's header):
#   DF_PATCH_BREW_MESA=0 DF_PATCH_BREW_FISH=0 bash install/linux-packages.sh
#
# Patching requires the tap to be cloned locally (HOMEBREW_NO_INSTALL_FROM_API=1).
# Without this, Homebrew uses a pre-built JSON API and formula files aren't present.
export HOMEBREW_NO_INSTALL_FROM_API=1
log_info "Tapping homebrew-core for editable formulas..."
# Note: grep -v exits 1 if it matches nothing (no Warning lines), which would kill
# the script under set -euo pipefail. The '|| true' absorbs that non-fatal exit.
brew tap homebrew/core --force 2>&1 | grep -v "^Warning" | head -5 || true

if [[ "${DF_PATCH_BREW_ALL:-1}" == "0" ]]; then
    log_info "DF_PATCH_BREW_ALL=0 — skipping all Homebrew formula patches"
else
    # python@3.14: fixes uuid module and test_datetime PGO build failures on custom prefix.
    # See install/patch-homebrew-python.sh for full details.
    [[ -f "$DF_INSTALL_DIR/patch-homebrew-python.sh" ]] && bash "$DF_INSTALL_DIR/patch-homebrew-python.sh"

    # mesa: fixes GCC 12 AVX2 compile errors in ARM GPU drivers that are built even on
    # x86 hosts. Two patches: drivers=auto and strip ARM entries from -Dtools=.
    # See install/patch-homebrew-mesa.sh for full details.
    [[ -f "$DF_INSTALL_DIR/patch-homebrew-mesa.sh" ]] && bash "$DF_INSTALL_DIR/patch-homebrew-mesa.sh"

    # fastfetch: disables WSL GPU detection (ENABLE_DIRECTX_HEADERS=OFF) which fails to
    # compile at a custom prefix due to a shim/include-path interaction with directx-headers.
    # WSL GPU detection is a no-op on bare-metal Linux anyway.
    # See install/patch-homebrew-fastfetch.sh for full details.
    [[ -f "$DF_INSTALL_DIR/patch-homebrew-fastfetch.sh" ]] && bash "$DF_INSTALL_DIR/patch-homebrew-fastfetch.sh"

    # fish: disables sphinx man page generation (WITH_DOCS=OFF) which fails on headless
    # cluster nodes due to locale not being configured (locale.Error: unsupported locale).
    # See install/patch-homebrew-fish.sh for full details.
    [[ -f "$DF_INSTALL_DIR/patch-homebrew-fish.sh" ]] && bash "$DF_INSTALL_DIR/patch-homebrew-fish.sh"
fi

### Install all packages ###

# DF_BREW_UPGRADE controls whether existing packages are upgraded.
# Linux default: NO upgrade. Upgrades on a custom prefix are risky:
#   - glibc upgrade can break every installed binary until rebuild completes
#   - gcc/llvm upgrades invalidate compiler symlinks (need re-run to refresh)
#   - Python formula upgrades overwrite our patches (uuid, test_datetime)
#   - source builds (Python, Perl, git, vim) take 10-30 min each
# Override: DF_BREW_UPGRADE=1 to force upgrades (then re-run this script to
# refresh compiler symlinks and re-apply Python patches).
_brew_upgrade="${DF_BREW_UPGRADE:-0}"
_bundle_flags="--no-upgrade"
[[ "$_brew_upgrade" == "1" ]] && _bundle_flags=""

if [[ -z "$_bundle_flags" ]]; then
    log_info "Running brew bundle (with upgrades)..."
    log_warn "Linux upgrades can be slow — source builds for Python/Perl/git/vim"
else
    log_info "Running brew bundle (install only, no upgrades)..."
fi

# shellcheck disable=SC2086
_bundle_exit=0
brew bundle install $_bundle_flags --file="$_BREWFILE_TMP" 2>&1 || _bundle_exit=$?
if [[ "$_bundle_exit" -ne 0 ]]; then
    log_warn "brew bundle completed with failures (exit $_bundle_exit) — some packages may not be installed"
    log_warn "Run 'brew bundle install --file=~/dotfiles/packages/Brewfile' to retry"
fi

### LOCALE (brew glibc needs its own locale archive) ###
#
# Homebrew's glibc has no locale archive by default — localedef is present but
# $prefix/lib/locale/ is empty. Without locale data, setlocale() falls back to
# C/ASCII (CODESET: ANSI_X3.4-1968), which makes wcwidth() count bytes instead
# of display columns. This breaks ZLE cursor positioning in brew zsh: every
# tab-completion leaves remnant characters on screen.
#
# Fix: generate en_US.UTF-8 into $LOCAL_PLAT/locale/ using brew's own localedef
# and i18n data. The shell profiles export LOCPATH pointing there so brew zsh
# picks it up at startup.

BREW_GLIBC="$LOCAL_PLAT/brew/opt/glibc"
LOCALE_DIR="$LOCAL_PLAT/locale"

if [[ -x "$BREW_GLIBC/bin/localedef" ]]; then
    if [[ -f "$LOCALE_DIR/en_US.UTF-8/LC_CTYPE" ]]; then
        log_okay "brew glibc locale already generated"
    else
        log_info "Generating en_US.UTF-8 locale for brew glibc → $LOCALE_DIR"
        ensure_dir "$LOCALE_DIR"
        I18NPATH="$BREW_GLIBC/share/i18n" \
        GCONV_PATH="$BREW_GLIBC/lib/gconv" \
            run_logged "$BREW_GLIBC/bin/localedef" \
                --prefix="$LOCALE_DIR" \
                -i en_US -f UTF-8 \
                "$LOCALE_DIR/en_US.UTF-8"
        log_okay "locale generated"
    fi
else
    log_warn "brew glibc localedef not found — skipping locale generation"
fi

### Create unversioned compiler symlinks ###
#
# gcc and llvm are keg-only — Homebrew doesn't link gcc/g++/clang/clang++ into
# brew/bin to avoid shadowing system compilers. Create symlinks in $LOCAL_PLAT/bin
# (which is on PATH ahead of brew/bin) so `gcc` resolves to Homebrew's version.
_PLAT_BIN="$(dirname "$_REAL_BREW_PREFIX")/bin"
ensure_dir "$_PLAT_BIN"

if [[ -d "$_REAL_BREW_PREFIX/opt/gcc/bin" ]]; then
    _GCC_VER=$(ls "$_REAL_BREW_PREFIX/opt/gcc/bin"/gcc-* 2>/dev/null | grep -oP 'gcc-\K[0-9]+' | sort -n | tail -1)
    if [[ -n "$_GCC_VER" ]]; then
        ln -sf "$_REAL_BREW_PREFIX/bin/gcc-$_GCC_VER" "$_PLAT_BIN/gcc"
        ln -sf "$_REAL_BREW_PREFIX/bin/g++-$_GCC_VER" "$_PLAT_BIN/g++"
        ln -sf "$_REAL_BREW_PREFIX/bin/gcc-ar-$_GCC_VER" "$_PLAT_BIN/gcc-ar"
        ln -sf "$_REAL_BREW_PREFIX/bin/gcc-nm-$_GCC_VER" "$_PLAT_BIN/gcc-nm"
        ln -sf "$_REAL_BREW_PREFIX/bin/gcc-ranlib-$_GCC_VER" "$_PLAT_BIN/gcc-ranlib"
        echo "[ok]   Linked gcc-$_GCC_VER → $_PLAT_BIN/gcc"
    fi
fi

# LLVM is versioned (llvm@21, llvm@20, etc.) — pick the highest installed
_LLVM_LATEST=$(ls -1d "$_REAL_BREW_PREFIX/opt/llvm@"*/bin 2>/dev/null | sort -Vr | head -1)
if [[ -n "$_LLVM_LATEST" ]]; then
    _LLVM_VER=$(basename "$(dirname "$_LLVM_LATEST")")
    ln -sf "$_LLVM_LATEST/clang" "$_PLAT_BIN/clang"
    ln -sf "$_LLVM_LATEST/clang++" "$_PLAT_BIN/clang++"
    ln -sf "$_LLVM_LATEST/clang-format" "$_PLAT_BIN/clang-format"
    ln -sf "$_LLVM_LATEST/clang-tidy" "$_PLAT_BIN/clang-tidy"
    echo "[ok]   Linked $_LLVM_VER → $_PLAT_BIN/clang"
fi

log_okay "Linux packages installed at $_REAL_BREW_PREFIX"
log_info "Compilers: gcc, g++, clang, clang++ → $_PLAT_BIN/"
log_info "Activate with: eval \"\$($_REAL_BREW_PREFIX/bin/brew shellenv)\""
