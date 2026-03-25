#!/usr/bin/env bash
# install/patch-homebrew-superenv.sh — patch Homebrew's Linux superenv to fix
# three endemic build failures on a custom prefix
#
# ─── WHY THIS EXISTS ────────────────────────────────────────────────────────────
#
# On Linux with a custom Homebrew prefix, all packages must be built from source
# (bottles are path-locked). Three systematic failures affect many packages:
#
# (1) MISSING KERNEL HEADERS
#     Homebrew glibc headers chain to Linux kernel headers:
#       glibc/include/bits/errno.h     → <linux/errno.h>
#       glibc/include/bits/local_lim.h → <linux/limits.h>
#       glibc/include/bits/ioctls.h    → <asm/ioctls.h>
#       glibc/include/bits/sockaddr.h  → <linux/socket.h>
#       glibc/include/bits/fcntl-linux.h → <linux/falloc.h>
#     Homebrew provides linux-headers@6.8 for this, but it is keg-only — not in
#     HOMEBREW_PREFIX/include, and not added to HOMEBREW_ISYSTEM_PATHS automatically.
#
# (2) MISSING GLIBC -L PATH (versioned symbol resolution failure)
#     The shim's ldflags_linux adds -Wl,-rpath-link=/brew/opt/glibc/lib to help
#     the linker resolve DT_NEEDED chains. But -rpath-link alone is insufficient
#     for versioned symbol lookups when building with LLVM against GCC's libstdc++.
#     When clang++ links a test binary, the linker pulls in /brew/opt/gcc/lib/gcc/15/
#     libstdc++.so, which in turn has DT_NEEDED for libc.so.6 and needs symbols like
#     fstat@GLIBC_2.33, pthread_key_create@GLIBC_2.34, etc. With only -rpath-link,
#     the linker finds glibc's libc.so.6 for file-level DT_NEEDED resolution but
#     cannot resolve versioned symbols from it — it falls back to the system glibc
#     2.31 which lacks GLIBC_2.33+. Adding -L/brew/opt/glibc/lib makes the linker
#     use glibc 2.39's libc.so.6 for both file lookup AND symbol resolution.
#
#     Root cause: HOMEBREW_LIBRARY_PATHS does not include glibc's opt_lib despite
#     glibc being a keg-only dep (cause unclear — likely a Homebrew internals issue).
#     The shim comment says "-L will only handle direct dependencies" but that is
#     inaccurate; -L is needed here for versioned symbol resolution in DT_NEEDED libs.
#
# (3) BROKEN GNULIB PROBE
#     Many packages bundle gnulib, which includes AC_C_UNDECLARED_BUILTIN_OPTIONS.
#     GCC treats memcpy/strchr as compiler builtins in Homebrew's environment, so
#     the probe compiles silently regardless of flags. Configure aborts with:
#       configure: error: cannot make gcc-NN report undeclared builtins
#
# ─── HOW SUPERENV HANDLES INCLUDE PATHS ─────────────────────────────────────────
#
# Most formula builds use superenv (not stdenv). Superenv uses compiler shim
# scripts in .../shims/linux/super/ that intercept every gcc/clang call.
#
# The shim reads HOMEBREW_ISYSTEM_PATHS (set by setup_build_environment via
# determine_isystem_paths → homebrew_extra_isystem_paths) and adds -isystem
# flags to EVERY compiler invocation, for both ./configure tests AND make builds.
#
# This means: adding linux-headers@6.8 to homebrew_extra_isystem_paths fixes
# BOTH configure-time header failures AND compile-time make failures globally,
# without patching any individual formula.
#
# ─── WHAT THE PATCHES DO ────────────────────────────────────────────────────────
#
# Patch 1 (super.rb): In the Linux-specific super.rb, modifies
# homebrew_extra_isystem_paths to also include linux-headers@6.8:
#
#   linux_headers = begin
#     ::Formula["linux-headers@6.8"]
#   rescue ::FormulaUnavailableError
#     nil
#   end
#   paths << linux_headers.include if linux_headers
#
# Patch 2 (super.rb): adds to setup_build_environment:
#
#   self["ac_cv_c_undeclared_builtin_options"] = \
#     "-Wimplicit-function-declaration -Werror=implicit-function-declaration"
#
# Patch 3 (llvm_clang++ shim): in ldflags_linux, alongside the existing
# -Wl,-rpath-link for glibc, also adds -L so the linker can resolve versioned
# symbols from glibc's libc.so.6. Applies to both plain glibc and glibc@X:
#
#   args << "#{wl}-rpath-link=#{@opt}/glibc/lib"
#   args << "-L#{@opt}/glibc/lib"         # ← added
#
# ─── INTERACTION WITH PER-FORMULA PATCHES ───────────────────────────────────────
#
# Per-formula CPATH patches (ncurses, m4, pkgconf, cc65) are now redundant for
# the include path part. The per-formula ac_cv_c_undeclared_builtin_options
# settings (m4, pkgconf) are also now redundant. All are harmless — setting the
# same value twice has no ill effect. They can be removed over time.
#
# ─── INTERACTION WITH STDENV PATCH ───────────────────────────────────────────────
#
# install/patch-homebrew-stdenv.sh patches std.rb for the rare stdenv builds.
# This patch covers superenv builds (the vast majority). Both are needed.
#
# ─── SIDE EFFECTS ───────────────────────────────────────────────────────────────
#
# All superenv source builds on Linux see linux-headers@6.8 as a -isystem path
# and have the gnulib probe pre-answered. This is correct behavior.
#
# ─── WHEN TO REMOVE ─────────────────────────────────────────────────────────────
#
# When upstream Homebrew adds linux-headers@6.8 as an implicit system include for
# all Linux source builds, AND when gnulib fixes the broken probe universally.
#
# ─── SKIP FLAG ──────────────────────────────────────────────────────────────────
#
# Set DF_PATCH_BREW_SUPERENV=0 to skip:
#   DF_PATCH_BREW_SUPERENV=0 bash install/linux-packages.sh
#
# ────────────────────────────────────────────────────────────────────────────────
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

[[ "$OS" == "linux" ]] || { log_okay "Not on Linux — skipping superenv patch"; exit 0; }

if [[ "${DF_PATCH_BREW_SUPERENV:-1}" == "0" ]]; then
    log_info "DF_PATCH_BREW_SUPERENV=0 — skipping Homebrew superenv patch"
    exit 0
fi

SUPERENV_RB="$LOCAL_PLAT/brew/Homebrew/Library/Homebrew/extend/os/linux/extend/ENV/super.rb"
SUPERENV_SHIM="$LOCAL_PLAT/brew/Homebrew/Library/Homebrew/shims/linux/super/llvm_clang++"

[[ -f "$SUPERENV_RB" ]] || { log_warn "super.rb not found at $SUPERENV_RB — skipping"; exit 0; }

log_section "Patching Homebrew superenv for Linux (linux-headers isystem + gnulib probe + glibc -L)"

# ── Patch 1: homebrew_extra_isystem_paths ────────────────────────────────────
# Add linux-headers@6.8 to the isystem paths that the shim adds to every gcc call.

_ISYSTEM_ORIG='      sig { returns(T::Array[::Pathname]) }
      def homebrew_extra_isystem_paths
        paths = []
        # Add paths for GCC headers when building against versioned glibc because we have to use -nostdinc.
        if deps.any? { |d| d.name.match?(/^glibc@.+$/) }
          gcc_include_dir = Utils.safe_popen_read(cc, "--print-file-name=include").chomp
          gcc_include_fixed_dir = Utils.safe_popen_read(cc, "--print-file-name=include-fixed").chomp
          paths << gcc_include_dir << gcc_include_fixed_dir
        end
        paths.map { |p| ::Pathname.new(p) }
      end'

_ISYSTEM_FIX='      sig { returns(T::Array[::Pathname]) }
      def homebrew_extra_isystem_paths
        paths = []
        # linux-headers@6.8 provides kernel headers required by Homebrew glibc
        # transitively (bits/errno.h → linux/errno.h, bits/local_lim.h →
        # linux/limits.h, etc.). Any formula built from source on a custom prefix
        # needs these headers. linux-headers@6.8 is keg-only so it is not in
        # HOMEBREW_PREFIX/include — add it as a -isystem path so the compiler
        # shim injects it into every gcc call (configure tests AND make builds).
        # The rescue guard makes this a no-op before linux-headers@6.8 is installed.
        linux_headers = begin
          ::Formula["linux-headers@6.8"]
        rescue ::FormulaUnavailableError
          nil
        end
        paths << linux_headers.include if linux_headers
        # Add paths for GCC headers when building against versioned glibc because we have to use -nostdinc.
        if deps.any? { |d| d.name.match?(/^glibc@.+$/) }
          gcc_include_dir = Utils.safe_popen_read(cc, "--print-file-name=include").chomp
          gcc_include_fixed_dir = Utils.safe_popen_read(cc, "--print-file-name=include-fixed").chomp
          paths << gcc_include_dir << gcc_include_fixed_dir
        end
        paths.map { |p| ::Pathname.new(p) }
      end'

_isystem_result=$(python3 -c "
import sys
path, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
txt = open(path).read()
if new in txt:    print('already')
elif old in txt:  open(path,'w').write(txt.replace(old, new, 1)); print('patched')
else:             print('notfound')
" "$SUPERENV_RB" "$_ISYSTEM_ORIG" "$_ISYSTEM_FIX")
case "$_isystem_result" in
    already)  log_okay "superenv linux-headers isystem patch already applied" ;;
    patched)  log_okay "Patched: linux-headers@6.8 added to homebrew_extra_isystem_paths" ;;
    notfound) log_warn "superenv isystem patch target not found — super.rb may have changed; check manually" ;;
esac
unset _ISYSTEM_ORIG _ISYSTEM_FIX _isystem_result

# ── Patch 2: setup_build_environment — gnulib probe fix ──────────────────────
# Pre-set ac_cv_c_undeclared_builtin_options to skip the broken gnulib probe.

_PROBE_ORIG='        self["JEMALLOC_SYS_WITH_LG_PAGE"] = "16"

        # Workaround patchelf.rb bug causing segfaults and preventing bottling on ARM64/AArch64
        # https://github.com/Homebrew/homebrew-core/issues/163826
        self["CGO_ENABLED"] = "0"'

# Note: this inserts the probe fix BEFORE the ARM64-specific block, which is
# guarded by `return unless ::Hardware::CPU.arm64?` so it runs on all arches.
_PROBE_SEARCH='        self["HOMEBREW_OPTIMIZATION_LEVEL"] = "O2"
        self["HOMEBREW_DYNAMIC_LINKER"] = determine_dynamic_linker_path
        self["HOMEBREW_RPATH_PATHS"] = determine_rpath_paths(formula)
        m4_path_deps = ["libtool", "bison"]
        self["M4"] = "#{HOMEBREW_PREFIX}/opt/m4/bin/m4" if deps.any? { m4_path_deps.include?(it.name) }
        return unless ::Hardware::CPU.arm64?'

_PROBE_FIX='        self["HOMEBREW_OPTIMIZATION_LEVEL"] = "O2"
        self["HOMEBREW_DYNAMIC_LINKER"] = determine_dynamic_linker_path
        self["HOMEBREW_RPATH_PATHS"] = determine_rpath_paths(formula)
        m4_path_deps = ["libtool", "bison"]
        self["M4"] = "#{HOMEBREW_PREFIX}/opt/m4/bin/m4" if deps.any? { m4_path_deps.include?(it.name) }

        # Pre-set the autoconf cache variable for the broken gnulib
        # AC_C_UNDECLARED_BUILTIN_OPTIONS probe. In Homebrew'"'"'s build
        # environment, GCC treats memcpy/strchr as compiler builtins so the
        # probe compiles silently regardless of flags, and configure aborts with
        # "cannot make gcc-NN report undeclared builtins". Many packages bundle
        # gnulib (m4, pkgconf, libx11, attr, etc.) and hit this. Pre-setting the
        # autoconf cache variable skips the probe entirely for all of them.
        self["ac_cv_c_undeclared_builtin_options"] = \
          "-Wimplicit-function-declaration -Werror=implicit-function-declaration"

        return unless ::Hardware::CPU.arm64?'

_probe_result=$(python3 -c "
import sys
path, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
txt = open(path).read()
if new in txt:    print('already')
elif old in txt:  open(path,'w').write(txt.replace(old, new, 1)); print('patched')
else:             print('notfound')
" "$SUPERENV_RB" "$_PROBE_SEARCH" "$_PROBE_FIX")
case "$_probe_result" in
    already)  log_okay "superenv gnulib probe bypass patch already applied" ;;
    patched)  log_okay "Patched: ac_cv_c_undeclared_builtin_options pre-set in superenv" ;;
    notfound) log_warn "superenv probe patch target not found — super.rb may have changed; check manually" ;;
esac
unset _PROBE_SEARCH _PROBE_FIX _probe_result

# ── Patch 3: llvm_clang++ shim — add -L for glibc alongside -rpath-link ──────
# The shim adds -Wl,-rpath-link=/brew/opt/glibc/lib for DT_NEEDED resolution,
# but binutils' ld cannot resolve versioned symbols (GLIBC_2.33+) from a library
# found only via -rpath-link. Adding -L makes glibc's libc.so.6 a full symbol
# search path entry, so the linker resolves fstat@GLIBC_2.33 etc. correctly.
# Affects both plain glibc and glibc@X (versioned) builds.

if [[ -f "$SUPERENV_SHIM" ]]; then
    # Versioned glibc branch
    _SHIM_V_ORIG='      args << "#{wl}-rpath-link=#{@opt}/#{versioned_glibc_dep}/lib"
    else
      args << "#{wl}-rpath-link=#{@opt}/glibc/lib"'
    _SHIM_V_FIX='      args << "#{wl}-rpath-link=#{@opt}/#{versioned_glibc_dep}/lib"
      # Also add -L so versioned GLIBC symbols (e.g. GLIBC_2.33+) are resolved
      # from brew glibc rather than the system glibc 2.31. -rpath-link alone only
      # helps binutils find the .so file; symbol lookup still falls back to system.
      args << "-L#{@opt}/#{versioned_glibc_dep}/lib"
    else
      args << "#{wl}-rpath-link=#{@opt}/glibc/lib"
      args << "-L#{@opt}/glibc/lib"'
    _shim_result=$(python3 -c "
import sys
path, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
txt = open(path).read()
if new in txt:    print('already')
elif old in txt:  open(path,'w').write(txt.replace(old, new, 1)); print('patched')
else:             print('notfound')
" "$SUPERENV_SHIM" "$_SHIM_V_ORIG" "$_SHIM_V_FIX")
    case "$_shim_result" in
        already)  log_okay "superenv shim glibc -L patch already applied" ;;
        patched)  log_okay "Patched: -L/brew/opt/glibc/lib added to llvm_clang++ shim ldflags_linux" ;;
        notfound) log_warn "shim glibc -L patch target not found — llvm_clang++ may have changed; check manually" ;;
    esac
    unset _SHIM_V_ORIG _SHIM_V_FIX _shim_result
else
    log_warn "llvm_clang++ shim not found at $SUPERENV_SHIM — skipping shim patch"
fi

log_okay "superenv patches done"
