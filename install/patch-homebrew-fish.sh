#!/usr/bin/env bash
# install/patch-homebrew-fish.sh — patch fish.rb for Linux custom-prefix builds
#
# ─── WHY THIS EXISTS ────────────────────────────────────────────────────────────
#
# fish 4.x rewrote its build system in Rust. Man page generation is now handled
# by a Rust build script (crates/build-man-pages/build.rs) that invokes sphinx-
# build from Homebrew's sphinx-doc package. The build.rs script runs sphinx-build
# as a subprocess and panics if it exits non-zero:
#
#   thread 'main' panicked at crates/build-man-pages/build.rs:95:13:
#   sphinx-build failed to build the man pages.
#
# sphinx-build fails because Python's locale module raises an exception when the
# system locale is not configured. On headless cluster nodes, the standard locale
# environment variables (LANG, LC_ALL, LC_CTYPE) are typically unset or set to
# values like "C" or "POSIX" that Python 3's locale module rejects:
#
#   locale.Error: unsupported locale setting
#
# The fish formula passes -DWITH_DOCS=ON unconditionally, which triggers this
# Rust/sphinx build path. This flag controls both man pages and HTML docs.
#
# Note: this is not a fish bug or a Homebrew formula bug in isolation — it's the
# combination of (a) fish using Rust to drive sphinx, (b) Rust build scripts
# running in the Homebrew build sandbox without locale env set, and (c) the
# cluster having no locale infrastructure installed (no locale-gen, no
# /usr/share/locale populated). On a desktop Ubuntu system with locales
# configured, this would likely succeed.
#
# ─── WHAT THE PATCH DOES ────────────────────────────────────────────────────────
#
# Changes the cmake -DWITH_DOCS= flag from a hardcoded ON to a Ruby ternary:
#   "-DWITH_DOCS=ON"
#   → "-DWITH_DOCS=#{OS.linux? ? 'OFF' : 'ON'}"
#
# On macOS the formula is unaffected (still builds docs). On Linux, docs are
# skipped entirely — no sphinx invocation, no man pages, no HTML docs.
#
# Note on the Ruby string: single quotes inside #{} are required because the
# outer string is double-quoted. Using double quotes inside the interpolation
# would prematurely terminate the outer string literal and cause a Ruby parse
# error (we hit this the first time and had to fix it).
#
# ─── SIDE EFFECTS ───────────────────────────────────────────────────────────────
#
# - 'man fish' will not work (no man pages installed).
# - fish --help and all interactive features are fully functional.
# - fish's web-based config UI (fish_config) is still installed.
# - On a server cluster, man pages are rarely consulted; the online docs at
#   https://fishshell.com/docs/ serve the same purpose.
#
# ─── WHEN TO REMOVE ─────────────────────────────────────────────────────────────
#
# When either:
# a) Locales are properly configured on the cluster (run: locale -a | grep en_US),
#    in which case setting LANG=en_US.UTF-8 before the build may be enough, OR
# b) fish's build system stops using Python/sphinx for man pages (unlikely — this
#    is an intentional switch to Sphinx for richer documentation), OR
# c) The upstream formula already handles locale setup or sets DOCS=OFF on Linux.
#    Check: grep -i 'WITH_DOCS\|sphinx\|locale' fish.rb
#
# ─── SKIP FLAG ──────────────────────────────────────────────────────────────────
#
# Set DF_PATCH_BREW_FISH=0 to skip:
#   DF_PATCH_BREW_FISH=0 bash install/linux-packages.sh
#
# ────────────────────────────────────────────────────────────────────────────────
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

[[ "$OS" == "linux" ]] || { log_okay "Not on Linux — skipping fish patch"; exit 0; }

# Allow opting out via DF_PATCH_BREW_FISH=0
if [[ "${DF_PATCH_BREW_FISH:-1}" == "0" ]]; then
    log_info "DF_PATCH_BREW_FISH=0 — skipping fish formula patch"
    exit 0
fi

FISH_RB="$LOCAL_PLAT/brew/Homebrew/Library/Taps/homebrew/homebrew-core/Formula/f/fish.rb"

[[ -f "$FISH_RB" ]] || { log_warn "fish.rb not found at $FISH_RB — skipping"; exit 0; }

log_section "Patching fish formula for Linux (disable sphinx man pages)"

# Replace -DWITH_DOCS=ON with a Ruby ternary.
# IMPORTANT: single quotes inside #{} are mandatory here — the outer string is
# double-quoted, so inner double quotes would end the string and cause a Ruby
# syntax error. Using _FIX as a shell variable with double-quoted assignment
# lets us embed the single quotes cleanly without extra escaping.
_PATCH='                    "-DWITH_DOCS=ON",'
_FIX="                    \"-DWITH_DOCS=\#{OS.linux? ? 'OFF' : 'ON'}\","
_result=$(python3 -c "
import sys
path, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
txt = open(path).read()
if new in txt:    print('already')
elif old in txt:  open(path,'w').write(txt.replace(old, new, 1)); print('patched')
else:             print('notfound')
" "$FISH_RB" "$_PATCH" "$_FIX")
case "$_result" in
    already)  log_okay "fish WITH_DOCS patch already applied" ;;
    patched)  log_okay "Patched: -DWITH_DOCS=OFF on Linux (skips sphinx/Rust man page build)" ;;
    notfound) log_warn "fish patch target not found — formula may have changed; check fish.rb" ;;
esac
unset _PATCH _FIX _result

log_okay "fish.rb patches done"
