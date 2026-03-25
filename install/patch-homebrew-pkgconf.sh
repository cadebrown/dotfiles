#!/usr/bin/env bash
# install/patch-homebrew-pkgconf.sh — patch pkgconf.rb for Linux custom-prefix builds
#
# ─── WHY THIS EXISTS ────────────────────────────────────────────────────────────
#
# pkgconf 2.5.1 bundles gnulib, which includes the macro
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
# explicitly handles linux-headers. Check:
# grep -c 'ac_cv_c_undeclared' pkgconf.rb — if > 0, upstream handles it.
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

_ORIG='  def install
    if build.head?
      ENV["LIBTOOLIZE"] = "glibtoolize"
      system "./autogen.sh"
    end'

# v1: only gnulib probe fix, no linux-headers
_PROBE_ONLY_FIX='  def install
    on_linux do
      # pkgconf 2.5.1 bundled gnulib has a broken probe for undeclared builtins:
      # GCC treats memcpy/strchr as compiler builtins, so the test program
      # compiles silently and configure aborts with "cannot detect". Pre-set
      # the autoconf cache variable to skip the probe (standard AC mechanism).
      # Remove when pkgconf upgrades to a version with the fixed gnulib.
      ENV["ac_cv_c_undeclared_builtin_options"] = \
        "-Wimplicit-function-declaration -Werror=implicit-function-declaration"
    end
    if build.head?
      ENV["LIBTOOLIZE"] = "glibtoolize"
      system "./autogen.sh"
    end'

# v2: probe fix + CPPFLAGS — fixes configure tests but not .lo compilation;
# pkgconf's libtool Makefile does not consistently propagate $(CPPFLAGS).
_CPPFLAGS_FIX='  def install
    on_linux do
      # pkgconf 2.5.1 bundled gnulib has a broken probe for undeclared builtins:
      # GCC treats memcpy/strchr as compiler builtins, so the test program
      # compiles silently and configure aborts with "cannot detect". Pre-set
      # the autoconf cache variable to skip the probe (standard AC mechanism).
      # Remove when pkgconf upgrades to a version with the fixed gnulib.
      ENV["ac_cv_c_undeclared_builtin_options"] = \
        "-Wimplicit-function-declaration -Werror=implicit-function-declaration"
      # linux-headers@6.8 provides asm/ioctls.h, linux/limits.h, etc.
      # Homebrew glibc requires these kernel headers transitively, but pkgconf
      # does not declare the dependency. Without this, configure tests for
      # socklen_t and others fail because glibc headers cannot be included.
      ENV.append "CPPFLAGS", "-I#{Formula["linux-headers@6.8"].include}"
    end
    if build.head?
      ENV["LIBTOOLIZE"] = "glibtoolize"
      system "./autogen.sh"
    end'

# v3 (correct): probe fix + CPATH — GCC reads CPATH directly, works for both
# configure tests and actual .lo compilation regardless of Makefile structure.
_CPATH_FIX='  def install
    on_linux do
      # pkgconf 2.5.1 bundled gnulib has a broken probe for undeclared builtins:
      # GCC treats memcpy/strchr as compiler builtins, so the test program
      # compiles silently and configure aborts with "cannot detect". Pre-set
      # the autoconf cache variable to skip the probe (standard AC mechanism).
      # Remove when pkgconf upgrades to a version with the fixed gnulib.
      ENV["ac_cv_c_undeclared_builtin_options"] = \
        "-Wimplicit-function-declaration -Werror=implicit-function-declaration"
      # linux-headers@6.8 provides asm/ioctls.h, linux/limits.h, linux/errno.h,
      # etc. Homebrew glibc requires these kernel headers transitively, but pkgconf
      # does not declare the dependency. Using CPATH (not CPPFLAGS) because pkgconf
      # libtool Makefile does not consistently propagate $(CPPFLAGS) to .lo compile
      # rules. GCC always checks CPATH regardless of Makefile structure.
      ENV.prepend_path "CPATH", Formula["linux-headers@6.8"].include.to_s
    end
    if build.head?
      ENV["LIBTOOLIZE"] = "glibtoolize"
      system "./autogen.sh"
    end'

_result=$(python3 -c "
import sys
path = sys.argv[1]
orig, probe_only, cppflags_fix, cpath_fix = sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]
txt = open(path).read()
if cpath_fix in txt:
    print('already')
elif cppflags_fix in txt:
    open(path,'w').write(txt.replace(cppflags_fix, cpath_fix, 1))
    print('migrated_cppflags')
elif probe_only in txt:
    open(path,'w').write(txt.replace(probe_only, cpath_fix, 1))
    print('migrated_probe')
elif orig in txt:
    open(path,'w').write(txt.replace(orig, cpath_fix, 1))
    print('patched')
else:
    print('notfound')
" "$PKGCONF_RB" "$_ORIG" "$_PROBE_ONLY_FIX" "$_CPPFLAGS_FIX" "$_CPATH_FIX")
case "$_result" in
    already)           log_okay "pkgconf full patch (probe bypass + linux-headers CPATH) already applied" ;;
    migrated_cppflags) log_okay "Migrated: pkgconf linux-headers changed from CPPFLAGS to CPATH" ;;
    migrated_probe)    log_okay "Migrated: pkgconf patch updated from probe-only to probe + CPATH" ;;
    patched)           log_okay "Patched: pkgconf probe bypass + linux-headers CPATH added for Linux" ;;
    notfound)          log_warn "pkgconf patch target not found — formula may have changed; check pkgconf.rb" ;;
esac
unset _ORIG _PROBE_ONLY_FIX _CPPFLAGS_FIX _CPATH_FIX _result

log_okay "pkgconf.rb patch done"
