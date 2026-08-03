#!/usr/bin/env bash
# install/patch-homebrew-gecode.sh — build gecode without Gist (and without Qt)
# on Linux
#
# ─── WHY THIS EXISTS ────────────────────────────────────────────────────────────
#
# gecode is the solver backend minizinc uses. The formula unconditionally builds
# Gist — Gecode's graphical search-tree explorer — which is what drags in
# `depends_on "qtbase"` and, with it, the whole Qt stack.
#
# qtbase does not build on a custom Linux prefix. libQt6Core fails to link:
#
#   ld: qcollator_icu.cpp:(.text+0x112): undefined reference to `ucol_setAttribute_74'
#   ld: qlocale_icu.cpp:(.text+0x13e): undefined reference to `u_strToLower_74'
#
# ICU exports version-suffixed symbols, and qtbase compiled against the system
# headers (/usr/include/unicode, ICU 74 on Ubuntu 24.04) while linking Homebrew's
# keg-only icu4c@78 — headers from one ICU, library from another. So minizinc
# fails on every bootstrap run, hours into a Qt build it never needed.
#
# Gist is a GUI. These are headless nodes. minizinc drives gecode through its
# command-line solver interface and never touches Gist.
#
# ─── WHAT THE PATCH DOES ────────────────────────────────────────────────────────
#
# Two edits, both guarded by OS.mac? so macOS keeps Gist:
#
#   depends_on "qtbase"        →  depends_on "qtbase" if OS.mac?
#   --enable-qt (in args)      →  --enable-qt on macOS, --disable-gist
#                                 --disable-qt on Linux
#
# Dropping the depends_on is the load-bearing half: Homebrew installs declared
# dependencies whatever the configure flags say, so leaving it would still build
# Qt.
#
# ─── SIDE EFFECTS ───────────────────────────────────────────────────────────────
#
# No libgecodegist on Linux. `brew test gecode` links -lgecodegist and queries
# pkgconf for Qt6Widgets, so it fails on Linux with this patch — `brew install`
# does not run tests, and the bundle is unaffected. Every non-GUI Gecode library
# (kernel, int, set, float, search, driver, minimodel) is built as before.
#
# ─── WHEN TO REMOVE ─────────────────────────────────────────────────────────────
#
# When qtbase builds on a custom prefix — i.e. when its ICU detection stops
# preferring /usr/include over the keg-only icu4c — or if Gist is ever wanted on
# a Linux box with a display.
#
# ─── SKIP FLAG ──────────────────────────────────────────────────────────────────
#
# Set DF_PATCH_BREW_GECODE=0 to skip:
#   DF_PATCH_BREW_GECODE=0 bash install/linux-packages.sh
#
# ────────────────────────────────────────────────────────────────────────────────
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

[[ "$OS" == "linux" ]] || { log_okay "Not on Linux — skipping gecode patch"; exit 0; }

if [[ "${DF_PATCH_BREW_GECODE:-1}" == "0" ]]; then
    log_info "DF_PATCH_BREW_GECODE=0 — skipping gecode formula patch"
    exit 0
fi

GECODE_RB="$LOCAL_PLAT/brew/Homebrew/Library/Taps/homebrew/homebrew-core/Formula/g/gecode.rb"

[[ -f "$GECODE_RB" ]] || { log_warn "gecode.rb not found at $GECODE_RB — skipping"; exit 0; }

log_section "Patching gecode formula for Linux (no Gist, no Qt)"

### Patch 1: drop the qtbase dependency on Linux ###

_ORIG='  depends_on "qtbase"'

_FIX='  # Gist (Gecode'"'"'s graphical search-tree explorer) is the only thing here that
  # wants Qt, and qtbase does not link on a custom Linux prefix: it compiles
  # against the system ICU headers and links Homebrew'"'"'s keg-only icu4c, so
  # libQt6Core dies on `undefined reference to ucol_setAttribute_74`. Headless
  # nodes have no use for Gist; minizinc drives gecode from the command line.
  depends_on "qtbase" if OS.mac?'

_result=$(python3 -c "
import sys
path, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
txt = open(path).read()
if new in txt:    print('already')
elif old in txt:  open(path,'w').write(txt.replace(old, new, 1)); print('patched')
else:             print('notfound')
" "$GECODE_RB" "$_ORIG" "$_FIX")
case "$_result" in
    already)  log_okay "gecode qtbase dependency already guarded" ;;
    patched)  log_okay "Patched: gecode drops the qtbase dependency on Linux" ;;
    notfound) log_warn "gecode depends_on patch target not found — formula may have changed" ;;
esac

### Patch 2: configure without Gist/Qt on Linux ###

_ORIG='      --disable-mpfr
      --enable-qt
    ]'

_FIX='      --disable-mpfr
    ]
    args += OS.mac? ? %w[--enable-qt] : %w[--disable-gist --disable-qt]'

_result=$(python3 -c "
import sys
path, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
txt = open(path).read()
if new in txt:    print('already')
elif old in txt:  open(path,'w').write(txt.replace(old, new, 1)); print('patched')
else:             print('notfound')
" "$GECODE_RB" "$_ORIG" "$_FIX")
case "$_result" in
    already)  log_okay "gecode configure flags already patched" ;;
    patched)  log_okay "Patched: gecode configures --disable-gist --disable-qt on Linux" ;;
    notfound) log_warn "gecode configure patch target not found — formula may have changed" ;;
esac
unset _ORIG _FIX _result

log_okay "gecode.rb patch done"
