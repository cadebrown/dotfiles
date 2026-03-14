#!/usr/bin/env bash
# install/patch-homebrew-fish.sh - patch the fish formula for Linux
#
# Problem: fish 4.x builds man pages via sphinx-doc using a Rust build script
# (crates/build-man-pages). On servers without a proper locale configured,
# sphinx-build fails with "locale.Error: unsupported locale setting".
#
# Fix: pass -DWITH_DOCS=OFF on Linux to skip sphinx man page generation entirely.
# The fish binary is fully functional without man pages.
#
# Safe to re-run: idempotent (checks before applying).
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

[[ "$OS" == "linux" ]] || { log_okay "Not on Linux — skipping fish patch"; exit 0; }

FISH_RB="$LOCAL_PLAT/brew/Homebrew/Library/Taps/homebrew/homebrew-core/Formula/f/fish.rb"

[[ -f "$FISH_RB" ]] || { log_warn "fish.rb not found at $FISH_RB — skipping"; exit 0; }

log_section "Patching fish formula for Linux (disable sphinx man pages)"

# Replace -DWITH_DOCS=ON with a Ruby ternary that disables docs on Linux.
# Single quotes inside the interpolation to avoid Ruby string nesting errors.
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
    patched)  log_okay "Patched: -DWITH_DOCS=OFF on Linux (skips sphinx man pages)" ;;
    notfound) log_warn "fish patch target not found — formula may have changed" ;;
esac
unset _PATCH _FIX _result

log_okay "fish.rb patched successfully"
