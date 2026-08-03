#!/usr/bin/env bash
# install/linux-packages.sh - install packages on Linux via Homebrew
#
# Runs Homebrew directly on the host — no container, no Docker, no sudo.
# Homebrew installs its own glibc so binaries are self-contained and portable
# across Linux systems regardless of the host glibc version.
#
# Most packages pour as precompiled bottles. glibc builds from source (~2 min)
# and is installed — and kept in step with the formula — before brew bundle, so
# that all subsequent bottles link against Homebrew's glibc, and so that the
# keg is never older than the bottles Homebrew's CI is currently producing.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

# _ver_lt A B — true when A sorts strictly before B in version order.
_ver_lt() {
    [[ "$1" != "$2" && "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -1)" == "$1" ]]
}

# _glibc_keg_version PREFIX — version of the *linked* glibc keg. `brew list
# --versions` lists every keg in the Cellar, and an upgrade leaves the previous
# one there until cleanup; only the one opt/glibc points at is loaded.
_glibc_keg_version() {
    local _keg
    _keg="$(readlink -f "$1/opt/glibc" 2>/dev/null || true)"
    [[ -n "$_keg" ]] && basename "$_keg" || true
}

# _glibc_provided LIBC — highest GLIBC_x.y symbol version a libc.so.6 defines.
_glibc_provided() {
    grep -aoE 'GLIBC_[0-9]+\.[0-9]+(\.[0-9]+)?' "$1" 2>/dev/null | sort -Vu | tail -1
}

# _glibc_offenders PROVIDED < NUL-separated paths — prints "<path>\t<GLIBC_x.y>"
# for every file needing a symbol version beyond PROVIDED.
#
# Reads the version strings straight out of .dynstr with grep -a instead of
# readelf/objdump: when this check matters, brew's binutils is itself among the
# binaries the loader refuses to start.
_glibc_offenders() {
    xargs -0 -r grep -aoHE 'GLIBC_[0-9]+\.[0-9]+(\.[0-9]+)?' 2>/dev/null \
        | awk -F: -v provided="${1#GLIBC_}" '
            function num(v,   p) { split(v, p, "."); return p[1] * 1000000 + p[2] * 1000 + p[3] }
            BEGIN { limit = num(provided) }
            {
                sub(/^GLIBC_/, "", $2)
                n = num($2)
                if (n > limit && n > seen[$1]) { seen[$1] = n; need[$1] = $2 }
            }
            END { for (f in seen) print f "\tGLIBC_" need[f] }'
}

# Source-guard: tests/brew-glibc.bats sources this file for the helpers above —
# everything below only runs when executed directly.
[[ "${BASH_SOURCE[0]}" != "$0" ]] && return 0

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

# Temporarily allow the JSON API for initial formula lookups (glibc, gcc@13).
# ~/.profile exports HOMEBREW_NO_INSTALL_FROM_API=1 so that the patches block
# later can edit local formula files in-place — but at this point in the script
# the homebrew/core tap hasn't been cloned yet, so without the API brew can't
# resolve ANY formula name. Re-exported below right before brew tap + patches.
unset HOMEBREW_NO_INSTALL_FROM_API

### Warn on a concurrent brew ###
#
# Homebrew holds an flock per formula under var/homebrew/locks, so a brew
# already working in this prefix makes this run fail formula by formula with
#   A `brew install <x>` process has already locked .../Cellar/<dep>
# naming the *other* process's command, which reads like corruption rather than
# contention — and `brew bundle` reports it as a plain install failure. Say it
# once, up front. Only local processes are visible; a brew on another machine
# sharing this prefix looks the same to Homebrew and is unsupported either way.
if pgrep -f "$_REAL_BREW_PREFIX/Homebrew" &>/dev/null; then
    log_warn "Another brew process is using this prefix — installs below will fail on formula locks:"
    while IFS= read -r _proc; do
        log_warn "  $_proc"
    done < <(pgrep -af "$_REAL_BREW_PREFIX/Homebrew" | cut -c1-100 | head -3)
    log_warn "  Wait for it to finish (or terminate it) and re-run."
    unset _proc
fi

# brew_glibc_build install|upgrade glibc — source-build glibc for the baseline
# ISA rather than the build host's.
#
# Homebrew's Linux ENV hardcodes -march=native (see patch-homebrew-optflags.sh),
# which bakes the build machine's ISA into the one library every binary in the
# prefix loads. A prefix built on an AVX-512 node then dies on every older CPU
# that mounts the same home with "Fatal glibc error: CPU does not support
# x86-64-v4". glibc selects its tuned memcpy/strlen through IFUNC resolvers at
# load time, so the baseline build keeps the fast paths regardless.
#
# HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK is the second half of the job. Left
# unset, `brew upgrade glibc` follows up by rebuilding every dependent whose
# linkage it considers stale — on a custom prefix that means source-building
# most of the Cellar, hours of work for a library that is backward compatible by
# design and whose existing kegs keep running untouched (Aug 2026: an unguarded
# upgrade was still rebuilding dependents 45 minutes later, holding formula
# locks that failed every other brew command in the meantime).
brew_glibc_build() {
    local _baseline
    case "$ARCH" in
        x86_64)  _baseline="-march=x86-64" ;;
        aarch64) _baseline="-march=armv8-a" ;;
        *)       _baseline="" ;;
    esac
    (
        bash "$DF_INSTALL_DIR/patch-homebrew-optflags.sh" || true
        export HOMEBREW_OPTFLAGS_PLAT="$_baseline"
        export HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK=1
        brew "$@" 2>&1
    )
}

### Reconcile glibc first ###
#
# Homebrew's glibc makes all bottles self-contained — binaries use Homebrew's
# own loader (brew/lib/ld.so → opt/glibc/bin/ld.so) which resolves libc from the
# Cellar rather than the host system. Without this step, machines whose system
# glibc is already recent enough would skip glibc and binaries would silently
# depend on the host glibc — breaking portability to older systems.
#
# The keg must then be kept in step with the formula, because Homebrew's Linux
# bottles are only guaranteed to run against the glibc Homebrew itself ships.
# When homebrew-core moves its builder image (Ubuntu 22.04 → 24.04, Jul 2026) it
# bumps the glibc formula (2.35 → 2.39) in the same breath, and every bottle
# poured afterwards carries the newer floor. An installed-but-stale keg then
# fails *only* on freshly poured formulas, with an error that names the binary
# rather than the cause:
#   .../bin/as: .../opt/glibc/lib/libc.so.6: version `GLIBC_2.38' not found
# The check at the end of this script catches any that slip through.
#
# Exception: Homebrew refuses to source-build glibc when host glibc is strictly
# newer than its own (e.g. Ubuntu 24.04 / Debian 13 aarch64 ship glibc 2.39 vs
# Homebrew's 2.35). The safety check fires because any future source-built
# formula on that host would link against host symbols and crash at runtime
# trying to load Homebrew's older loader. Bottle pour fallback can't save us
# either — bottles are not relocatable, /home/linuxbrew/... paths are baked in.
# On those hosts we skip glibc entirely; bottles will link against the host
# loader. Portability to older hosts is lost — acceptable on a host whose
# daily driver is itself a newer host.
_glibc_changed=0
_sys_glibc="$(ldd --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+$' || true)"

if ! brew list glibc &>/dev/null; then
    _brew_glibc="$(brew info glibc 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1 || true)"
    # Strictly older: brew refuses; skip with warning. Equal or newer: proceed.
    if [[ -n "$_sys_glibc" && -n "$_brew_glibc" ]] && _ver_lt "$_brew_glibc" "$_sys_glibc"; then
        log_warn "Host glibc $_sys_glibc > Homebrew glibc $_brew_glibc — skipping brew glibc install"
        log_warn "  Bottles will link against the host loader. Binaries are not portable to hosts with glibc < $_sys_glibc."
    else
        log_info "Installing glibc (builds from source, ~2 min)..."
        brew_glibc_build install glibc
        _glibc_changed=1
    fi
    unset _brew_glibc
else
    # `brew outdated --verbose` prints "glibc (2.35_2) < 2.39_1", nothing when
    # current. Revision suffixes (_1) are Homebrew's, not glibc's — strip before
    # comparing against the host.
    _glibc_outdated="$(brew outdated --formula --verbose glibc 2>/dev/null | head -1 || true)"
    _glibc_have="$(_glibc_keg_version "$_REAL_BREW_PREFIX")"
    _glibc_want="${_glibc_outdated##* }"

    if [[ -z "$_glibc_outdated" ]]; then
        log_okay "brew glibc ${_glibc_have:-installed} is current"
    elif [[ -n "$_sys_glibc" ]] && _ver_lt "$_sys_glibc" "${_glibc_want%%_*}"; then
        # Homebrew won't build a glibc newer than the host's, and this is the one
        # combination it can't dig itself out of: the keg stays behind the
        # bottles. Upgrading the host, or dropping the keg and reinstalling every
        # formula against the host loader, are the only ways out.
        log_warn "brew glibc $_glibc_have is behind formula $_glibc_want, but host glibc is only $_sys_glibc"
        log_warn "  Homebrew refuses to build a glibc newer than the host — newly poured bottles will fail to load."
        log_warn "  See docs/usage/troubleshooting.md (\"GLIBC_x.y not found\")."
    else
        log_info "Upgrading brew glibc $_glibc_have → $_glibc_want (builds from source, ~2 min)..."
        if brew_glibc_build upgrade glibc; then
            _glibc_changed=1
            log_okay "brew glibc upgraded to $_glibc_want"
        else
            log_warn "brew glibc upgrade failed — bottles newer than $_glibc_have will not load"
        fi
    fi
    unset _glibc_outdated _glibc_have _glibc_want
fi

### Pre-install gcc@13 and pin source-build compiler ###
#
# The unversioned 'gcc' formula tracks the latest GCC release. As of GCC 15,
# implicit function declarations are errors by default (previously warnings).
# This breaks configure scripts in m4 1.4.21 (gnulib probe fails with
# "cannot make gcc-15 report undeclared builtins") and ncurses 6.6 (all
# function checks return 'no', leading to "getopt is required for building
# programs"). Both packages must be built from source on a custom prefix
# (our prefix ≠ /home/linuxbrew/.linuxbrew, so bottles can't be used).
#
# Fix: ensure gcc@13 is installed before brew bundle runs, then set
# HOMEBREW_CC=gcc-13 so all source builds use it instead of gcc-15.
# gcc@13 is stable for everything in the Brewfile and is explicitly pinned
# there. On fresh installs where gcc-13 isn't present yet, we install it
# here (one-time ~10 min build using the system compiler).
if brew list gcc@13 &>/dev/null; then
    log_okay "gcc@13 already installed"
else
    log_info "Pre-installing gcc@13 (source-build compiler before brew bundle)..."
    brew install gcc@13 2>&1
fi
export HOMEBREW_CC=gcc-13
export HOMEBREW_CXX=g++-13
log_info "Source-build compiler pinned to gcc-13 (gcc-15 breaks m4/ncurses configure)"

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

### Refresh formula definitions ###
#
# Must stay explicit: HOMEBREW_NO_AUTO_UPDATE=1 (set above) means nothing else
# ever refreshes the tap, so without this it stays frozen at its clone date and
# no amount of re-running bootstrap moves a formula version.
#
# Must stay BEFORE the patch block, and must discard first: `brew update`
# stashes dirty files and pops them afterwards, so an upstream edit to a patched
# line leaves the checkout mid-conflict. Both checkouts carry patches — formulae
# in the homebrew-core tap, superenv/stdenv/shim in Homebrew's own Library.
#
# Refreshing definitions is NOT upgrading: DF_BREW_UPGRADE still governs whether
# installed kegs move.
log_info "Refreshing Homebrew (discarding patches first, re-applied below)..."
_core_repo="$(brew --repo homebrew/core)"
_brew_repo="$(brew --repo)"
[[ -d "$_core_repo/.git" ]] && { git -C "$_core_repo" checkout -- Formula/ 2>/dev/null || true; }
[[ -d "$_brew_repo/.git" ]] && { git -C "$_brew_repo" checkout -- Library/ 2>/dev/null || true; }
run_logged brew update || log_warn "brew update failed — formula definitions may be stale"
unset _core_repo _brew_repo

if [[ "${DF_PATCH_BREW_ALL:-1}" == "0" ]]; then
    log_info "DF_PATCH_BREW_ALL=0 — skipping all Homebrew formula patches"
else
    # superenv: the primary fix for Linux custom-prefix source builds. Patches
    # Homebrew's superenv (the compiler shim layer used by most formula builds):
    # (1) Adds linux-headers@6.8 to homebrew_extra_isystem_paths so the shim
    #     injects -isystem into every gcc call (configure tests AND make builds).
    #     Homebrew glibc headers chain to kernel headers transitively; without
    #     this, builds fail with "fatal error: linux/errno.h: No such file".
    # (2) Pre-sets ac_cv_c_undeclared_builtin_options in the build env to bypass
    #     the broken gnulib probe that affects m4, pkgconf, libx11, attr, etc.
    # See install/patch-homebrew-superenv.sh for full details.
    [[ -f "$DF_INSTALL_DIR/patch-homebrew-superenv.sh" ]] && bash "$DF_INSTALL_DIR/patch-homebrew-superenv.sh"

    # stdenv: same two fixes for the rare formula builds that use stdenv instead
    # of superenv (most don't, but belt-and-suspenders).
    # See install/patch-homebrew-stdenv.sh for full details.
    [[ -f "$DF_INSTALL_DIR/patch-homebrew-stdenv.sh" ]] && bash "$DF_INSTALL_DIR/patch-homebrew-stdenv.sh"

    # python@3.14: fixes uuid module and test_datetime PGO build failures on custom prefix.
    # See install/patch-homebrew-python.sh for full details.
    [[ -f "$DF_INSTALL_DIR/patch-homebrew-python.sh" ]] && bash "$DF_INSTALL_DIR/patch-homebrew-python.sh"

    # mesa: installs pyyaml from its binary wheel instead of building from source.
    # venv.pip_install always passes --no-binary=:all:, forcing a source build;
    # pyyaml's Cython get_requires_for_build_wheel subprocess receives SIGILL (exit -4)
    # in the Homebrew superenv on a custom prefix.
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

    # rpm: fixes cmake's FindLua failure caused by LUA_MATH_LIBRARY (libm) not being
    # found in the superenv. glibc is keg-only so its lib dir is not in cmake's
    # search path; FindLua computes LUA_LIBRARIES = "liblua;NOTFOUND" and fails.
    # See install/patch-homebrew-rpm.sh for full details.
    [[ -f "$DF_INSTALL_DIR/patch-homebrew-rpm.sh" ]] && bash "$DF_INSTALL_DIR/patch-homebrew-rpm.sh"

    # systemd: installs lxml from its binary wheel instead of building from source.
    # venv.pip_install always passes --no-binary=:all:, forcing a source build; building
    # lxml from source fails with SIGILL (exit -4) in the Homebrew superenv on a custom
    # prefix (Cython get_requires_for_build_wheel subprocess killed by illegal instruction).
    # See install/patch-homebrew-systemd.sh for full details.
    [[ -f "$DF_INSTALL_DIR/patch-homebrew-systemd.sh" ]] && bash "$DF_INSTALL_DIR/patch-homebrew-systemd.sh"

    # ncurses: adds linux-headers@6.8 CPATH (via stdenv patch) and also has its own
    # per-formula CPATH entry for belt-and-suspenders. ncurses subdirectory Makefiles
    # do not propagate $(CPPFLAGS) so CPATH is required.
    # See install/patch-homebrew-ncurses.sh for full details.
    [[ -f "$DF_INSTALL_DIR/patch-homebrew-ncurses.sh" ]] && bash "$DF_INSTALL_DIR/patch-homebrew-ncurses.sh"

    # cc65: adds linux-headers@6.8 via CPATH (the raw Makefile uses $(CC) $(CFLAGS)
    # without $(CPPFLAGS), so CPATH is required for GCC to find linux/errno.h).
    # See install/patch-homebrew-cc65.sh for full details.
    [[ -f "$DF_INSTALL_DIR/patch-homebrew-cc65.sh" ]] && bash "$DF_INSTALL_DIR/patch-homebrew-cc65.sh"

    # m4: pre-sets ac_cv_c_undeclared_builtin_options to bypass a broken gnulib probe
    # (m4 1.4.21). GCC treats memcpy/strchr as builtins so the probe compiles silently
    # and configure aborts with "cannot make gcc-NN report undeclared builtins".
    # linux-headers CPATH is now handled by the stdenv patch.
    # See install/patch-homebrew-m4.sh for full details.
    [[ -f "$DF_INSTALL_DIR/patch-homebrew-m4.sh" ]] && bash "$DF_INSTALL_DIR/patch-homebrew-m4.sh"

    # pkgconf: same gnulib undeclared-builtin probe failure as m4. pkgconf is a
    # widely-used dependency (openssh, podman, fish, etc.) so this patch is critical.
    # linux-headers CPATH is now handled by the stdenv patch.
    # See install/patch-homebrew-pkgconf.sh for full details.
    [[ -f "$DF_INSTALL_DIR/patch-homebrew-pkgconf.sh" ]] && bash "$DF_INSTALL_DIR/patch-homebrew-pkgconf.sh"

    # gecode: builds without Gist (its Qt search-tree viewer) on Linux, which is
    # the only reason gecode — and therefore minizinc — pulls in qtbase. qtbase
    # links the wrong ICU on a custom prefix and fails outright.
    # See install/patch-homebrew-gecode.sh for full details.
    [[ -f "$DF_INSTALL_DIR/patch-homebrew-gecode.sh" ]] && bash "$DF_INSTALL_DIR/patch-homebrew-gecode.sh"

    # netpbm: GCC 15 changed its default C standard from C17 to C23. C23 makes
    # `bool` a keyword, breaking netpbm's `typedef unsigned char bool` in buildtools/
    # libopt.c. Fix: force -std=gnu17 on Linux via ENV.append_to_cflags.
    # See install/patch-homebrew-netpbm.sh for full details.
    [[ -f "$DF_INSTALL_DIR/patch-homebrew-netpbm.sh" ]] && bash "$DF_INSTALL_DIR/patch-homebrew-netpbm.sh"
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

# Trust + tap the Brewfile's third-party taps so brew bundle can resolve them.
ensure_brewfile_taps "$_BREWFILE_TMP"

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
#
# The archive is glibc's own binary format and is read by the loader that
# generated it, so a version stamp forces a regenerate whenever the keg moves.

BREW_GLIBC="$LOCAL_PLAT/brew/opt/glibc"
LOCALE_DIR="$LOCAL_PLAT/locale"
_LOCALE_STAMP="$LOCALE_DIR/.glibc-version"
_glibc_installed="$(_glibc_keg_version "$_REAL_BREW_PREFIX")"

if [[ -x "$BREW_GLIBC/bin/localedef" ]]; then
    if [[ -f "$LOCALE_DIR/en_US.UTF-8/LC_CTYPE" \
          && "$(cat "$_LOCALE_STAMP" 2>/dev/null || true)" == "$_glibc_installed" ]]; then
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
        printf '%s\n' "$_glibc_installed" > "$_LOCALE_STAMP"
        log_okay "locale generated"
    fi
else
    log_warn "brew glibc localedef not found — skipping locale generation"
fi
unset _LOCALE_STAMP

### SYSTEM LDCONFIG (brew's ld.so needs to find system driver libs) ###
#
# Homebrew's ld.so has its own ldconfig cache, separate from the system's.
# By default, it only searches brew-owned directories (opt/glibc/lib, brew/lib).
# Brew ships a 99-system-ld.so.conf.example that includes system paths — we
# enable it so brew programs can discover system-provided driver libraries
# (libcuda.so.1, libnvidia-ml.so.1, etc.) via ldconfig instead of LD_LIBRARY_PATH.
#
# This is safe: brew glibc is first in brew's ld.so.conf (sorts before 99-),
# so brew glibc always wins. System paths only provide libraries that brew
# doesn't have (driver stubs, vendor-specific libs).
#
# Without this, cuda_use() would need /usr/lib/<arch> in LD_LIBRARY_PATH,
# which poisons brew binaries: they find system libc before brew glibc
# (LD_LIBRARY_PATH is searched before ldconfig).

_BREW_LDCONF_D="$_REAL_BREW_PREFIX/etc/ld.so.conf.d"
_BREW_LDCONFIG="$BREW_GLIBC/sbin/ldconfig"
_SYS_CONF="$_BREW_LDCONF_D/99-system-ld.so.conf"
_SYS_CONF_EXAMPLE="${_SYS_CONF}.example"

if [[ -x "$_BREW_LDCONFIG" ]]; then
    if [[ -f "$_SYS_CONF" && "$_glibc_changed" == "1" ]]; then
        # The cache records Cellar paths, which the upgrade just moved.
        log_info "Rebuilding brew ldconfig cache after glibc change"
        run_logged "$_BREW_LDCONFIG"
        log_okay "brew ldconfig rebuilt"
    elif [[ -f "$_SYS_CONF" ]]; then
        log_okay "brew ldconfig already includes system paths"
    elif [[ -f "$_SYS_CONF_EXAMPLE" ]]; then
        log_info "Enabling system paths in brew ldconfig (99-system-ld.so.conf)"
        cp "$_SYS_CONF_EXAMPLE" "$_SYS_CONF"
        run_logged "$_BREW_LDCONFIG"
        log_okay "brew ldconfig rebuilt with system paths"
    else
        log_warn "99-system-ld.so.conf.example not found — brew programs may not find system driver libs"
    fi
else
    log_warn "brew ldconfig not found — skipping system path registration"
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

# LLVM is versioned (llvm@21, llvm@22, etc.) — pick the highest installed.
# The '|| true' absorbs the exit code 2 from ls when no llvm@* dirs exist yet
# (e.g. first bootstrap run before llvm@XX has been installed); without it,
# set -eo pipefail kills the script even though the empty result is intentional.
_LLVM_LATEST=$(ls -1d "$_REAL_BREW_PREFIX/opt/llvm@"*/bin 2>/dev/null | sort -Vr | head -1 || true)
if [[ -n "$_LLVM_LATEST" ]]; then
    _LLVM_VER=$(basename "$(dirname "$_LLVM_LATEST")")
    ln -sf "$_LLVM_LATEST/clang" "$_PLAT_BIN/clang"
    ln -sf "$_LLVM_LATEST/clang++" "$_PLAT_BIN/clang++"
    ln -sf "$_LLVM_LATEST/clang-format" "$_PLAT_BIN/clang-format"
    ln -sf "$_LLVM_LATEST/clang-tidy" "$_PLAT_BIN/clang-tidy"
    echo "[ok]   Linked $_LLVM_VER → $_PLAT_BIN/clang"
fi

### Verify kegs against the glibc keg ###
#
# A bottle poured from a builder image newer than the glibc keg loads nothing:
#   .../bin/as: .../opt/glibc/lib/libc.so.6: version `GLIBC_2.38' not found
# Nothing upstream announces the floor, and the message names the victim rather
# than the cause, so check for it here instead of discovering it a month later
# in a build log. Only relevant while a brew glibc keg exists — without one,
# bottles resolve against the host loader, which brew already required to be new
# enough before skipping the keg.
#
# Scanning every keg costs ~30s of NFS reads, so the stamp file scopes routine
# runs to kegs installed since the last scan. A glibc change invalidates the
# stamp and forces a full pass — exactly when every keg's floor is back in play.

_GLIBC_LIBC="$_REAL_BREW_PREFIX/opt/glibc/lib/libc.so.6"
_SCAN_STAMP="$_REAL_LOCAL_PLAT/.brew-glibc-scan"

if [[ -f "$_GLIBC_LIBC" ]]; then
    _provided="$(_glibc_provided "$_GLIBC_LIBC")"
    _find_args=()
    if [[ "$(cat "$_SCAN_STAMP" 2>/dev/null || true)" == "$_provided" ]]; then
        _find_args=(-newer "$_SCAN_STAMP")
        log_info "Checking kegs installed since the last scan against $_provided"
    else
        log_info "Checking all kegs against $_provided (glibc changed or first run)"
    fi

    _offenders="$(
        find "$_REAL_BREW_PREFIX/Cellar" -mindepth 3 -maxdepth 4 -type f \
            \( -path '*/bin/*' -o -path '*/sbin/*' \) "${_find_args[@]}" -print0 2>/dev/null \
            | _glibc_offenders "$_provided" \
            | sed -E "s|^$_REAL_BREW_PREFIX/Cellar/([^/]+)/([^/]+)/.*\t|\1 \2\t|" \
            | sort -u | awk -F'\t' '!seen[$1]++'
    )"

    if [[ -z "$_offenders" ]]; then
        log_okay "All scanned kegs load against brew glibc ($_provided)"
        printf '%s\n' "$_provided" > "$_SCAN_STAMP"
    else
        log_warn "Kegs needing a newer glibc than the brew keg provides ($_provided):"
        while IFS=$'\t' read -r _keg _need; do
            log_warn "  $_keg → $_need"
        done <<< "$_offenders"
        log_warn "  Their binaries fail with \"version \`GLIBC_x.y' not found\"."
        log_warn "  See docs/usage/troubleshooting.md (\"GLIBC_x.y not found\")."
        rm -f "$_SCAN_STAMP"
    fi
    unset _provided _find_args _offenders _keg _need
fi
unset _GLIBC_LIBC _SCAN_STAMP

log_okay "Linux packages installed at $_REAL_BREW_PREFIX"
log_info "Compilers: gcc, g++, clang, clang++ → $_PLAT_BIN/"
log_info "Activate with: eval \"\$($_REAL_BREW_PREFIX/bin/brew shellenv)\""
