#!/usr/bin/env bash
# install/patch-homebrew-pkgconf.sh — patch pkgconf.rb for Linux custom-prefix builds
#
# ─── WHY THIS EXISTS ────────────────────────────────────────────────────────────
#
# pkgconf bundles gnulib, which includes the macro
# AC_C_UNDECLARED_BUILTIN_OPTIONS. This macro has the same broken probe as
# m4 1.4.21: it tries to determine compiler flags needed to treat calls to
# undeclared builtins as errors, by compiling a test program that calls
# memcpy/strchr without a header.
#
# In Homebrew's build environment, GCC treats memcpy/strchr as compiler
# builtins (__builtin_memcpy etc.), so they compile without a declaration
# even without -Wimplicit flags. The probe can't trigger an error, so it
# records "cannot detect" and configure aborts with:
#   configure: error: cannot make gcc-NN report undeclared builtins
#
# This is the same root cause as m4 1.4.21 and is a known gnulib bug.
#
# Even after bypassing the probe, pkgconf's configure and compilation also
# require Linux kernel headers transitively via Homebrew glibc:
#   glibc/include/bits/errno.h → <linux/errno.h>  (kernel)
# Without linux-headers@6.8 in the include path, the actual compilation
# of libpkgconf source files fails with:
#   fatal error: linux/errno.h: No such file or directory
#
# ─── WHAT THE PATCH DOES ────────────────────────────────────────────────────────
#
# Prepends to the install def:
#   on_linux do
#     ENV['ac_cv_c_undeclared_builtin_options'] = \
#       '-Wimplicit-function-declaration -Werror=implicit-function-declaration'
#     ENV.prepend_path 'CPATH', Formula['linux-headers@6.8'].include.to_s
#   end
#
# (1) Autoconf reads ac_cv_* variables as pre-cached answers, skipping the
#     broken gnulib probe entirely.
#
# (2) ENV.prepend_path "CPATH" is used rather than ENV.append "CPPFLAGS"
#     because pkgconf's automake/libtool Makefile does not consistently
#     propagate $(CPPFLAGS) to .lo compile rules. GCC reads CPATH directly,
#     so it works for both configure probes and actual compilation.
#
# ─── SIDE EFFECTS ───────────────────────────────────────────────────────────────
#
# None. pkgconf builds and works correctly. The env-var approach is the standard
# autoconf mechanism for overriding configure probes.
#
# ─── WHEN TO REMOVE ─────────────────────────────────────────────────────────────
#
# When the upstream pkgconf formula uses a version with the fixed gnulib and
# explicitly handles linux-headers. Check against a PRISTINE formula
# (`git -C "$(brew --repo homebrew/core)" show HEAD:Formula/p/pkgconf.rb`) —
# grepping the working copy matches this patch's own marker.
#
# ─── SKIP FLAG ──────────────────────────────────────────────────────────────────
#
# Set DF_PATCH_BREW_PKGCONF=0 to skip:
#   DF_PATCH_BREW_PKGCONF=0 bash install/linux-packages.sh
#
# ────────────────────────────────────────────────────────────────────────────────
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

[[ "$OS" == "linux" ]] || { log_okay "Not on Linux — skipping pkgconf patch"; exit 0; }

if [[ "${DF_PATCH_BREW_PKGCONF:-1}" == "0" ]]; then
    log_info "DF_PATCH_BREW_PKGCONF=0 — skipping pkgconf formula patch"
    exit 0
fi

PKGCONF_RB="$LOCAL_PLAT/brew/Homebrew/Library/Taps/homebrew/homebrew-core/Formula/p/pkgconf.rb"

[[ -f "$PKGCONF_RB" ]] || { log_warn "pkgconf.rb not found at $PKGCONF_RB — skipping"; exit 0; }

log_section "Patching pkgconf formula for Linux (bypass undeclared-builtin probe + linux-headers)"

# Anchored on the `def install` line alone, not the body: upstream rewrites the
# body freely (2.5.1's autotools-only install became 3.0.4's meson-for-HEAD
# split), and a whole-block match silently degrades to "target not found" every
# time that happens. `ac_cv_c_undeclared_builtin_options` is the idempotency
# marker — it appears only in this patch.
_ANCHOR='  def install
'
_INJECT='  def install
    on_linux do
      # pkgconf bundles a gnulib whose undeclared-builtin probe is broken: GCC
      # treats memcpy/strchr as compiler builtins, so the test program compiles
      # silently and configure aborts with "cannot detect". Pre-set the autoconf
      # cache variable to skip the probe (standard AC mechanism).
      ENV["ac_cv_c_undeclared_builtin_options"] = \
        "-Wimplicit-function-declaration -Werror=implicit-function-declaration"
      # linux-headers@6.8 provides asm/ioctls.h, linux/limits.h, linux/errno.h,
      # etc. Homebrew glibc requires these kernel headers transitively, but pkgconf
      # does not declare the dependency. Using CPATH (not CPPFLAGS) because pkgconf
      # libtool Makefile does not consistently propagate $(CPPFLAGS) to .lo compile
      # rules. GCC always checks CPATH regardless of Makefile structure.
      ENV.prepend_path "CPATH", Formula["linux-headers@6.8"].include.to_s
    end
'

_result=$(python3 -c "
import sys
path, anchor, inject = sys.argv[1], sys.argv[2], sys.argv[3]
txt = open(path).read()
if 'ac_cv_c_undeclared_builtin_options' in txt:
    print('already')
elif anchor in txt:
    open(path,'w').write(txt.replace(anchor, inject, 1))
    print('patched')
else:
    print('notfound')
" "$PKGCONF_RB" "$_ANCHOR" "$_INJECT")
case "$_result" in
    already)  log_okay "pkgconf patch (probe bypass + linux-headers CPATH) already applied" ;;
    patched)  log_okay "Patched: pkgconf probe bypass + linux-headers CPATH added for Linux" ;;
    notfound) log_warn "pkgconf patch target not found — formula may have changed; check pkgconf.rb" ;;
esac
unset _ANCHOR _INJECT _result

log_okay "pkgconf.rb patch done"
