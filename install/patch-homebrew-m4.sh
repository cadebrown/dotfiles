#!/usr/bin/env bash
# install/patch-homebrew-m4.sh — patch m4.rb for Linux custom-prefix builds
#
# ─── WHY THIS EXISTS ────────────────────────────────────────────────────────────
#
# m4 1.4.21 bundles gnulib, which includes the macro
# AC_C_UNDECLARED_BUILTIN_OPTIONS. This macro tries to determine compiler flags
# needed to treat calls to undeclared builtins as errors, by compiling a test
# program that calls memcpy/strchr without a header. If every variation compiles
# successfully (no warning), the macro records "cannot detect" and configure
# aborts with:
#   configure: error: cannot make gcc-NN report undeclared builtins
#
# Why the test succeeds silently in our environment:
#   - Homebrew's build environment sets _GNU_SOURCE (and many other feature
#     macros) in confdefs.h before the configure test runs.
#   - GCC treats memcpy/strchr as compiler builtins (__builtin_memcpy etc.)
#     so they compile without a declaration even without -Wimplicit flags.
#   - Combined: the probe can't trigger an error, so it cannot detect any
#     working option, and configure aborts.
#
# This is a gnulib bug fixed in gnulib HEAD (post-m4 1.4.21 release). The
# fix changes the test to use a non-builtin undeclared function, but it hasn't
# been backported to a released m4 version yet.
#
# Even after bypassing the gnulib probe, m4 build also requires Linux kernel
# headers transitively via Homebrew glibc:
#   glibc/include/bits/errno.h → <linux/errno.h>     (kernel)
#   glibc/include/bits/sockaddr.h → <linux/socket.h> (kernel)
# Without linux-headers@6.8 in the include path, the configure tests fail at
# socklen_t (and others), and the actual compilation fails with:
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
#     because m4's gnulib Makefile subdirectories do not propagate $(CPPFLAGS)
#     to all compile rules. GCC reads CPATH directly, so it works for both
#     configure probes and the actual compilation regardless of Makefile structure.
#
# ─── SIDE EFFECTS ───────────────────────────────────────────────────────────────
#
# None. m4 builds and works correctly. The env-var approach is the standard
# autoconf mechanism for overriding configure probes.
#
# ─── WHEN TO REMOVE ─────────────────────────────────────────────────────────────
#
# When the upstream m4 formula uses a version with the fixed gnulib (likely
# m4 1.4.22 or later), or when the formula explicitly handles this probe.
# Check: brew info m4 — if version > 1.4.21, try removing the patch first.
#
# ─── SKIP FLAG ──────────────────────────────────────────────────────────────────
#
# Set DF_PATCH_BREW_M4=0 to skip:
#   DF_PATCH_BREW_M4=0 bash install/linux-packages.sh
#
# ────────────────────────────────────────────────────────────────────────────────
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

[[ "$OS" == "linux" ]] || { log_okay "Not on Linux — skipping m4 patch"; exit 0; }

if [[ "${DF_PATCH_BREW_M4:-1}" == "0" ]]; then
    log_info "DF_PATCH_BREW_M4=0 — skipping m4 formula patch"
    exit 0
fi

M4_RB="$LOCAL_PLAT/brew/Homebrew/Library/Taps/homebrew/homebrew-core/Formula/m/m4.rb"

[[ -f "$M4_RB" ]] || { log_warn "m4.rb not found at $M4_RB — skipping"; exit 0; }

log_section "Patching m4 formula for Linux (bypass undeclared-builtin probe + linux-headers)"

_ORIG='  def install
    system "./configure", "--disable-dependency-tracking", "--prefix=#{prefix}"'

# v1: only gnulib probe fix, no linux-headers
_PROBE_ONLY_FIX='  def install
    on_linux do
      # m4 1.4.21 bundled gnulib has a broken probe for undeclared builtins:
      # GCC treats memcpy/strchr as compiler builtins, so the test program
      # compiles silently and configure aborts with "cannot detect". Pre-set
      # the autoconf cache variable to skip the probe (standard AC mechanism).
      # Remove when m4 upgrades to a version with the fixed gnulib.
      ENV["ac_cv_c_undeclared_builtin_options"] = \
        "-Wimplicit-function-declaration -Werror=implicit-function-declaration"
    end
    system "./configure", "--disable-dependency-tracking", "--prefix=#{prefix}"'

# v2: probe fix + CPPFLAGS — fixes configure tests but not make; m4 gnulib
# subdirectory Makefiles do not propagate $(CPPFLAGS) to compile rules.
_CPPFLAGS_FIX='  def install
    on_linux do
      # m4 1.4.21 bundled gnulib has a broken probe for undeclared builtins:
      # GCC treats memcpy/strchr as compiler builtins, so the test program
      # compiles silently and configure aborts with "cannot detect". Pre-set
      # the autoconf cache variable to skip the probe (standard AC mechanism).
      # Remove when m4 upgrades to a version with the fixed gnulib.
      ENV["ac_cv_c_undeclared_builtin_options"] = \
        "-Wimplicit-function-declaration -Werror=implicit-function-declaration"
      # linux-headers@6.8 provides asm/ioctls.h, linux/limits.h, etc.
      # Homebrew glibc requires these kernel headers transitively, but m4
      # does not declare the dependency. Without this, configure tests for
      # socklen_t and others fail because glibc headers cannot be included.
      ENV.append "CPPFLAGS", "-I#{Formula["linux-headers@6.8"].include}"
    end
    system "./configure", "--disable-dependency-tracking", "--prefix=#{prefix}"'

# v3 (correct): probe fix + CPATH — GCC reads CPATH directly, works for both
# configure tests and actual compilation regardless of Makefile structure.
_CPATH_FIX='  def install
    on_linux do
      # m4 1.4.21 bundled gnulib has a broken probe for undeclared builtins:
      # GCC treats memcpy/strchr as compiler builtins, so the test program
      # compiles silently and configure aborts with "cannot detect". Pre-set
      # the autoconf cache variable to skip the probe (standard AC mechanism).
      # Remove when m4 upgrades to a version with the fixed gnulib.
      ENV["ac_cv_c_undeclared_builtin_options"] = \
        "-Wimplicit-function-declaration -Werror=implicit-function-declaration"
      # linux-headers@6.8 provides asm/ioctls.h, linux/limits.h, linux/errno.h,
      # etc. Homebrew glibc requires these kernel headers transitively, but m4
      # does not declare the dependency. Using CPATH (not CPPFLAGS) because m4
      # gnulib subdirectory Makefiles do not propagate $(CPPFLAGS) to compile
      # rules. GCC always checks CPATH regardless of Makefile structure.
      ENV.prepend_path "CPATH", Formula["linux-headers@6.8"].include.to_s
    end
    system "./configure", "--disable-dependency-tracking", "--prefix=#{prefix}"'

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
" "$M4_RB" "$_ORIG" "$_PROBE_ONLY_FIX" "$_CPPFLAGS_FIX" "$_CPATH_FIX")
case "$_result" in
    already)           log_okay "m4 full patch (probe bypass + linux-headers CPATH) already applied" ;;
    migrated_cppflags) log_okay "Migrated: m4 linux-headers changed from CPPFLAGS to CPATH" ;;
    migrated_probe)    log_okay "Migrated: m4 patch updated from probe-only to probe + CPATH" ;;
    patched)           log_okay "Patched: m4 probe bypass + linux-headers CPATH added for Linux" ;;
    notfound)          log_warn "m4 patch target not found — formula may have changed; check m4.rb" ;;
esac
unset _ORIG _PROBE_ONLY_FIX _CPPFLAGS_FIX _CPATH_FIX _result

log_okay "m4.rb patches done"
