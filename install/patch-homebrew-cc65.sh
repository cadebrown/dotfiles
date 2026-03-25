#!/usr/bin/env bash
# install/patch-homebrew-cc65.sh — patch cc65.rb for Linux custom-prefix builds
#
# ─── WHY THIS EXISTS ────────────────────────────────────────────────────────────
#
# cc65 is a 6502 C compiler. Its formula builds via a plain Makefile:
#   system "make", "PREFIX=#{prefix}"
# It does not declare linux-headers@6.8 as a build dependency and does not
# pass CFLAGS/CPPFLAGS to make.
#
# On Linux with a custom Homebrew prefix (not /home/linuxbrew/.linuxbrew),
# cc65 must be built from source (bottles are path-bound). The build uses
# Homebrew's own glibc, whose errno.h chain is:
#   brew/opt/glibc/include/errno.h
#     → brew/opt/glibc/include/bits/errno.h
#       → <linux/errno.h>   ← kernel header, not in glibc itself
#
# Homebrew provides linux-headers@6.8 for exactly this purpose, but because
# cc65 doesn't declare the dependency, the include path is never added, and
# the build fails with:
#   fatal error: linux/errno.h: No such file or directory
#
# ─── WHAT THE PATCH DOES ────────────────────────────────────────────────────────
#
# Changes the install def from:
#   system "make", "PREFIX=#{prefix}"
#   system "make", "install", "PREFIX=#{prefix}"
#
# to:
#   on_linux do
#     ENV.prepend_path "CPATH", Formula["linux-headers@6.8"].include.to_s
#   end
#   system "make", "PREFIX=#{prefix}"
#   system "make", "install", "PREFIX=#{prefix}"
#
# ENV.prepend_path "CPATH" is used rather than ENV.append "CPPFLAGS" because
# cc65's raw Makefile uses $(CC) $(CFLAGS) without $(CPPFLAGS) in compile rules.
# GCC automatically picks up CPATH as an extra -I directory regardless of how
# the Makefile invokes it, making this the most robust approach for raw Makefiles.
#
# ─── SIDE EFFECTS ───────────────────────────────────────────────────────────────
#
# None. cc65 builds and works normally. This only adds an include path that
# is already installed on the system as part of linux-headers@6.8.
#
# ─── WHEN TO REMOVE ─────────────────────────────────────────────────────────────
#
# When the upstream cc65 formula adds:
#   depends_on "linux-headers@6.8" => :build if OS.linux?
# or when Homebrew's glibc provides linux/errno.h directly.
# Check: grep linux-headers cc65.rb
#
# ─── SKIP FLAG ──────────────────────────────────────────────────────────────────
#
# Set DF_PATCH_BREW_CC65=0 to skip:
#   DF_PATCH_BREW_CC65=0 bash install/linux-packages.sh
#
# ────────────────────────────────────────────────────────────────────────────────
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

[[ "$OS" == "linux" ]] || { log_okay "Not on Linux — skipping cc65 patch"; exit 0; }

if [[ "${DF_PATCH_BREW_CC65:-1}" == "0" ]]; then
    log_info "DF_PATCH_BREW_CC65=0 — skipping cc65 formula patch"
    exit 0
fi

CC65_RB="$LOCAL_PLAT/brew/Homebrew/Library/Taps/homebrew/homebrew-core/Formula/c/cc65.rb"

[[ -f "$CC65_RB" ]] || { log_warn "cc65.rb not found at $CC65_RB — skipping"; exit 0; }

log_section "Patching cc65 formula for Linux (add linux-headers include path)"

_ORIG='  def install
    system "make", "PREFIX=#{prefix}"
    system "make", "install", "PREFIX=#{prefix}"
  end'

# CPPFLAGS version — old incorrect patch; cc65 Makefile uses $(CC) $(CFLAGS)
# without $(CPPFLAGS), so ENV.append "CPPFLAGS" is silently ignored.
_CPPFLAGS_FIX='  def install
    on_linux do
      # linux-headers@6.8 provides linux/errno.h, which Homebrew glibc requires
      # but cc65 does not declare as a dependency. Without this, the source build
      # fails with: fatal error: linux/errno.h: No such file or directory
      ENV.append "CPPFLAGS", "-I#{Formula["linux-headers@6.8"].include}"
    end
    system "make", "PREFIX=#{prefix}"
    system "make", "install", "PREFIX=#{prefix}"
  end'

# CPATH version — correct fix. GCC picks up CPATH automatically regardless of
# what the Makefile does, so this works even when $(CPPFLAGS) is not used.
_CPATH_FIX='  def install
    on_linux do
      # linux-headers@6.8 provides linux/errno.h, which Homebrew glibc requires
      # but cc65 does not declare as a dependency. Without this, the source build
      # fails with: fatal error: linux/errno.h: No such file or directory
      # Using CPATH (not CPPFLAGS) because the cc65 Makefile uses $(CC) $(CFLAGS)
      # without $(CPPFLAGS). GCC always checks CPATH regardless of the Makefile.
      ENV.prepend_path "CPATH", Formula["linux-headers@6.8"].include.to_s
    end
    system "make", "PREFIX=#{prefix}"
    system "make", "install", "PREFIX=#{prefix}"
  end'

_result=$(python3 -c "
import sys
path = sys.argv[1]
orig, cppflags_fix, cpath_fix = sys.argv[2], sys.argv[3], sys.argv[4]
txt = open(path).read()
if cpath_fix in txt:
    print('already')
elif cppflags_fix in txt:
    # Migrate from old CPPFLAGS patch to correct CPATH patch
    open(path,'w').write(txt.replace(cppflags_fix, cpath_fix, 1))
    print('migrated')
elif orig in txt:
    open(path,'w').write(txt.replace(orig, cpath_fix, 1))
    print('patched')
else:
    print('notfound')
" "$CC65_RB" "$_ORIG" "$_CPPFLAGS_FIX" "$_CPATH_FIX")
case "$_result" in
    already)  log_okay "cc65 linux-headers CPATH patch already applied" ;;
    migrated) log_okay "Migrated: cc65 patch updated from CPPFLAGS to CPATH" ;;
    patched)  log_okay "Patched: linux-headers@6.8 CPATH added for Linux" ;;
    notfound) log_warn "cc65 patch target not found — formula may have changed; check cc65.rb" ;;
esac
unset _ORIG _CPPFLAGS_FIX _CPATH_FIX _result

log_okay "cc65.rb patch done"
