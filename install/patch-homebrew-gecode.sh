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
# Three edits, all guarded so macOS keeps its upstream bottle and Gist:
#
#   Linux bottle              →  source build (the bottle already contains Gist)
#   depends_on "qtbase"        →  depends_on "qtbase" if OS.mac?
#   GIST=ON / QT=ON            →  ON on macOS, OFF on Linux
#
# The patch also recognizes the older Autotools formula and converts its
# --enable-qt flag to --disable-gist/--disable-qt on Linux.
#
# Both the bottle policy and dependency edit are load-bearing. Configure flags
# cannot change an already-built bottle, and Homebrew installs every declared
# dependency regardless of those flags.
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

if [[ ! -f "$GECODE_RB" ]]; then
    log_warn "gecode.rb not found at $GECODE_RB — refusing to start source builds"
    exit 1
fi

log_section "Patching gecode formula for Linux (no Gist, no Qt)"

_DEP_ANCHOR='  depends_on "qtbase"'

_POUR_FIX='  pour_bottle? do
    reason "Linux bottle contains Gist and requires Qt"
    satisfy { OS.mac? }
  end'

_DEP_FIX='  # Gist (Gecode'"'"'s graphical search-tree explorer) is the only thing here that
  # wants Qt, and qtbase does not link on a custom Linux prefix: it compiles
  # against the system ICU headers and links Homebrew'"'"'s keg-only icu4c, so
  # libQt6Core dies on `undefined reference to ucol_setAttribute_74`. Headless
  # nodes have no use for Gist; minizinc drives gecode from the command line.
  depends_on "qtbase" if OS.mac?'

_CMAKE_ANCHOR='    args = %w[
      -DGECODE_ENABLE_EXAMPLES=OFF
      -DGECODE_ENABLE_GIST=ON
      -DGECODE_ENABLE_MPFR=OFF
      -DGECODE_ENABLE_QT=ON
    ]'

_CMAKE_FIX='    args = %W[
      -DGECODE_ENABLE_EXAMPLES=OFF
      -DGECODE_ENABLE_GIST=#{OS.mac? ? "ON" : "OFF"}
      -DGECODE_ENABLE_MPFR=OFF
      -DGECODE_ENABLE_QT=#{OS.mac? ? "ON" : "OFF"}
    ]'

_AUTOTOOLS_ANCHOR='      --disable-mpfr
      --enable-qt
    ]'

_AUTOTOOLS_FIX='      --disable-mpfr
    ]
    args += OS.mac? ? %w[--enable-qt] : %w[--disable-gist --disable-qt]'

_result=$(python3 -c '
import sys

path, pour_fix, dep_anchor, dep_fix, cmake_anchor, cmake_fix, autotools_anchor, autotools_fix = sys.argv[1:]
text = open(path).read()
original = text
missing = []

if pour_fix not in text:
    dependency = "\n  depends_on "
    if "\n  pour_bottle?" in text:
        missing.append("Linux bottle policy")
    elif dependency in text:
        text = text.replace(dependency, "\n" + pour_fix + "\n" + dependency, 1)
    else:
        missing.append("formula dependency anchor")

if dep_fix not in text:
    lines = text.splitlines()
    guarded_dependency = dep_anchor + " if OS.mac?"
    if dep_anchor in lines:
        text = text.replace("\n" + dep_anchor + "\n", "\n" + dep_fix + "\n", 1)
    elif guarded_dependency in lines:
        pass
    else:
        missing.append("Qt dependency")

if cmake_fix not in text and autotools_fix not in text:
    if cmake_anchor in text:
        text = text.replace(cmake_anchor, cmake_fix, 1)
    elif autotools_anchor in text:
        text = text.replace(autotools_anchor, autotools_fix, 1)
    else:
        missing.append("Gist/Qt build flags")

if missing:
    print("notfound:" + ",".join(missing))
elif text == original:
    print("already")
else:
    open(path, "w").write(text)
    print("patched")
' "$GECODE_RB" "$_POUR_FIX" "$_DEP_ANCHOR" "$_DEP_FIX" "$_CMAKE_ANCHOR" "$_CMAKE_FIX" "$_AUTOTOOLS_ANCHOR" "$_AUTOTOOLS_FIX")

case "$_result" in
    already) log_okay "gecode no-Gist/no-Qt Linux patch already applied" ;;
    patched) log_okay "Patched: gecode builds from source without Qt or Gist on Linux" ;;
    notfound:*)
        log_warn "gecode patch target not found (${_result#notfound:}) — refusing to start source builds"
        exit 1
        ;;
esac

unset _POUR_FIX _DEP_ANCHOR _DEP_FIX _CMAKE_ANCHOR _CMAKE_FIX _AUTOTOOLS_ANCHOR _AUTOTOOLS_FIX _result

log_okay "gecode.rb patch done"
