#!/usr/bin/env bash
# install/patch-homebrew-coreutils.sh — give Linux coreutils an explicit OpenSSL
# dependency for its SHA utilities.
#
# GNU coreutils 9.12's configure detects a globally linked openssl@3 when it is
# present, but the formula does not declare that dependency.  The resulting
# sha256sum carries a libcrypto.so.3 need with only Homebrew's generic lib path
# in RUNPATH; removing the old global OpenSSL links then makes it unloadable.
# Declare openssl@4 and force configure to use it so superenv records a stable,
# versioned dependency path in the produced binary and Homebrew receipt.
#
# Set DF_PATCH_BREW_COREUTILS=0 to skip:
#   DF_PATCH_BREW_COREUTILS=0 bash install/linux-packages.sh

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

[[ "$OS" == "linux" ]] || { log_okay "Not on Linux — skipping coreutils patch"; exit 0; }

if [[ "${DF_PATCH_BREW_ALL:-1}" == "0" ]]; then
    log_info "DF_PATCH_BREW_ALL=0 — skipping all Homebrew formula patches"
    exit 0
fi

if [[ "${DF_PATCH_BREW_COREUTILS:-1}" == "0" ]]; then
    log_info "DF_PATCH_BREW_COREUTILS=0 — skipping coreutils formula patch"
    exit 0
fi

COREUTILS_RB="$LOCAL_PLAT/brew/Homebrew/Library/Taps/homebrew/homebrew-core/Formula/c/coreutils.rb"
if [[ ! -f "$COREUTILS_RB" ]]; then
    log_warn "coreutils.rb not found at $COREUTILS_RB — refusing to start source builds"
    exit 1
fi

log_section "Patching coreutils formula for Linux OpenSSL linkage"

_DEP_ANCHOR='  on_linux do
    depends_on "acl"
    depends_on "attr"
  end'
_DEP_FIX='  on_linux do
    depends_on "acl"
    depends_on "attr"
    depends_on "openssl@4"
  end'
_ARGS_ANCHOR='      --program-prefix=g
      --with-libgmp
      --without-selinux'
_ARGS_FIX='      --program-prefix=g
      --with-libgmp
      --with-openssl=yes
      --without-selinux'

_result=$(python3 -c '
import sys

path, dep_anchor, dep_fix, args_anchor, args_fix = sys.argv[1:]
text = open(path).read()
original = text
missing = []

if dep_fix not in text:
    if dep_anchor in text:
        text = text.replace(dep_anchor, dep_fix, 1)
    else:
        missing.append("Linux dependency block")

if args_fix not in text:
    if args_anchor in text:
        text = text.replace(args_anchor, args_fix, 1)
    else:
        missing.append("configure arguments")

if missing:
    print("notfound:" + ",".join(missing))
elif text == original:
    print("already")
else:
    open(path, "w").write(text)
    print("patched")
' "$COREUTILS_RB" "$_DEP_ANCHOR" "$_DEP_FIX" "$_ARGS_ANCHOR" "$_ARGS_FIX")

case "$_result" in
    already) log_okay "coreutils OpenSSL dependency patch already applied" ;;
    patched) log_okay "Patched: coreutils builds against declared openssl@4" ;;
    notfound:*)
        log_warn "coreutils patch target not found (${_result#notfound:}) — refusing to start source builds"
        exit 1
        ;;
esac

unset _DEP_ANCHOR _DEP_FIX _ARGS_ANCHOR _ARGS_FIX _result
log_okay "coreutils.rb patch done"
