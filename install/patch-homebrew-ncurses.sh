#!/usr/bin/env bash
# install/patch-homebrew-ncurses.sh — patch ncurses.rb for Linux custom-prefix builds
#
# ─── WHY THIS EXISTS ────────────────────────────────────────────────────────────
#
# ncurses 6.6 requires Linux kernel headers (via Homebrew glibc's include chain)
# that it does not declare as a build dependency.
#
# Two distinct failures occur without this patch:
#
# 1. CONFIGURE: Homebrew glibc's headers chain to kernel headers:
#      glibc/include/limits.h → bits/local_lim.h → <linux/limits.h>   (kernel)
#      glibc/include/sys/ioctl.h → bits/ioctls.h → <asm/ioctls.h>     (kernel)
#    When any configure function test includes <stdio.h> or <limits.h>, the chain
#    reaches linux/limits.h, fails, and marks the function absent. This cascades
#    to every check, and configure aborts:
#      configure: error: getopt is required for building programs
#
# 2. COMPILE: Even if configure succeeds (or CPPFLAGS fixes the probes),
#    the actual ncurses source files include <errno.h>, which chains:
#      glibc/include/bits/errno.h → <linux/errno.h>   (kernel)
#    ncurses's Makefile subdirectories do NOT propagate $(CPPFLAGS) to compile
#    rules, so ENV.append "CPPFLAGS" fixes configure but not make. Result:
#      fatal error: linux/errno.h: No such file or directory
#
# Homebrew provides linux-headers@6.8 for exactly this purpose, but ncurses
# does not declare the dependency.
#
# ─── WHAT THE PATCH DOES ────────────────────────────────────────────────────────
#
# Prepends to the install def:
#   on_linux do
#     ENV.prepend_path "CPATH", Formula["linux-headers@6.8"].include.to_s
#   end
#
# ENV.prepend_path "CPATH" is used rather than ENV.append "CPPFLAGS" because
# ncurses's Makefile subdirectories use $(CC) without $(CPPFLAGS) in compile
# rules. GCC automatically picks up CPATH as an extra -I directory regardless
# of how the Makefile invokes the compiler — this fixes both configure tests
# and the actual compilation.
#
# ─── SIDE EFFECTS ───────────────────────────────────────────────────────────────
#
# None. ncurses builds and works correctly. This only adds an include path to
# linux-headers@6.8 which is already installed as part of the Brewfile.
#
# ─── WHEN TO REMOVE ─────────────────────────────────────────────────────────────
#
# When the upstream ncurses formula adds:
#   depends_on "linux-headers@6.8" => :build if OS.linux?
# or when Homebrew's glibc provides linux/limits.h and asm/ioctls.h directly.
# Check: grep linux-headers ncurses.rb
#
# ─── SKIP FLAG ──────────────────────────────────────────────────────────────────
#
# Set DF_PATCH_BREW_NCURSES=0 to skip:
#   DF_PATCH_BREW_NCURSES=0 bash install/linux-packages.sh
#
# ────────────────────────────────────────────────────────────────────────────────
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

[[ "$OS" == "linux" ]] || { log_okay "Not on Linux — skipping ncurses patch"; exit 0; }

if [[ "${DF_PATCH_BREW_NCURSES:-1}" == "0" ]]; then
    log_info "DF_PATCH_BREW_NCURSES=0 — skipping ncurses formula patch"
    exit 0
fi

NCURSES_RB="$LOCAL_PLAT/brew/Homebrew/Library/Taps/homebrew/homebrew-core/Formula/n/ncurses.rb"

[[ -f "$NCURSES_RB" ]] || { log_warn "ncurses.rb not found at $NCURSES_RB — skipping"; exit 0; }

log_section "Patching ncurses formula for Linux (add linux-headers include path)"

_ORIG='  def install
    ENV.delete("TERMINFO")

    args = ['

# CPPFLAGS version — old incorrect patch; ncurses subdirectory Makefiles use
# $(CC) $(CFLAGS) without $(CPPFLAGS), so ENV.append "CPPFLAGS" fixes configure
# tests but the actual compilation still fails with linux/errno.h not found.
_CPPFLAGS_FIX='  def install
    ENV.delete("TERMINFO")
    on_linux do
      # linux-headers@6.8 provides asm/ioctls.h and linux/limits.h, which
      # Homebrew glibc requires transitively via bits/ioctls.h and
      # bits/local_lim.h. Without this, configure function tests (snprintf,
      # getopt, etc.) all fail because basic headers like <stdio.h>/<limits.h>
      # cannot be fully included.
      ENV.append "CPPFLAGS", "-I#{Formula["linux-headers@6.8"].include}"
    end

    args = ['

# CPATH version — correct fix. GCC picks up CPATH automatically regardless of
# what the Makefile does, so this works for both configure tests and compilation
# even when $(CPPFLAGS) is not used in subdirectory Makefile compile rules.
_CPATH_FIX='  def install
    ENV.delete("TERMINFO")
    on_linux do
      # linux-headers@6.8 provides asm/ioctls.h, linux/limits.h, linux/errno.h,
      # etc. Homebrew glibc requires these kernel headers transitively, but ncurses
      # does not declare the dependency. Using CPATH (not CPPFLAGS) because ncurses
      # subdirectory Makefiles use $(CC) $(CFLAGS) without $(CPPFLAGS) — GCC always
      # checks CPATH regardless of the Makefile.
      ENV.prepend_path "CPATH", Formula["linux-headers@6.8"].include.to_s
    end

    args = ['

_result=$(python3 -c "
import sys
path = sys.argv[1]
orig, cppflags_fix, cpath_fix = sys.argv[2], sys.argv[3], sys.argv[4]
txt = open(path).read()
if cpath_fix in txt:
    print('already')
elif cppflags_fix in txt:
    open(path,'w').write(txt.replace(cppflags_fix, cpath_fix, 1))
    print('migrated')
elif orig in txt:
    open(path,'w').write(txt.replace(orig, cpath_fix, 1))
    print('patched')
else:
    print('notfound')
" "$NCURSES_RB" "$_ORIG" "$_CPPFLAGS_FIX" "$_CPATH_FIX")
case "$_result" in
    already)  log_okay "ncurses linux-headers CPATH patch already applied" ;;
    migrated) log_okay "Migrated: ncurses patch updated from CPPFLAGS to CPATH" ;;
    patched)  log_okay "Patched: linux-headers@6.8 CPATH added for Linux" ;;
    notfound) log_warn "ncurses patch target not found — formula may have changed; check ncurses.rb" ;;
esac
unset _ORIG _CPPFLAGS_FIX _CPATH_FIX _result

log_okay "ncurses.rb patches done"
