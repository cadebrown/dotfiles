#!/usr/bin/env bash
# tests/test-locale.sh — verify brew glibc locale fix
#
# Run directly: bash tests/test-locale.sh
# Does NOT require a login shell — sets LOCPATH from _lib.sh variables.

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../install/_lib.sh"

ZSH="$LOCAL_PLAT/brew/bin/zsh"
LOCALE_DIR="$LOCAL_PLAT/locale"

pass() { printf "[pass] %s\n" "$1"; }
fail() { printf "[FAIL] %s\n" "$1"; FAILURES=$((FAILURES + 1)); }
FAILURES=0

echo "=== locale fix tests ==="
echo "LOCPATH:     $LOCALE_DIR"
echo "brew zsh:    $ZSH"
echo ""

# 1. locale dir exists
if [[ -d "$LOCALE_DIR/en_US.UTF-8" ]]; then
    pass "locale dir exists: $LOCALE_DIR/en_US.UTF-8"
else
    fail "locale dir missing: $LOCALE_DIR/en_US.UTF-8 (run linux-packages.sh)"
fi

# 2. LC_CTYPE generated
if [[ -f "$LOCALE_DIR/en_US.UTF-8/LC_CTYPE" ]]; then
    pass "LC_CTYPE present"
else
    fail "LC_CTYPE missing — localedef may have failed"
fi

# 3. brew zsh exists
if [[ -x "$ZSH" ]]; then
    pass "brew zsh found"
else
    fail "brew zsh not found at $ZSH"
    echo "Cannot run remaining tests without brew zsh."
    exit 1
fi

# 4. without LOCPATH → should be ASCII (confirms we're testing the right thing)
CODESET_NO_LOC=$(LOCPATH="" LANG=en_US.UTF-8 "$ZSH" --no-rcs -c \
    'zmodload zsh/langinfo; printf "%s" $langinfo[CODESET]' 2>/dev/null)
if [[ "$CODESET_NO_LOC" != "UTF-8" ]]; then
    pass "without LOCPATH codeset is '$CODESET_NO_LOC' (not UTF-8 — expected)"
else
    # Some systems have locale data elsewhere; not a hard failure
    printf "[warn] without LOCPATH codeset is already UTF-8 — LOCPATH may not be needed on this machine\n"
fi

# 5. with LOCPATH → must be UTF-8
CODESET=$(LOCPATH="$LOCALE_DIR" LANG=en_US.UTF-8 "$ZSH" --no-rcs -c \
    'zmodload zsh/langinfo; printf "%s" $langinfo[CODESET]' 2>/dev/null)
if [[ "$CODESET" == "UTF-8" ]]; then
    pass "CODESET with LOCPATH: UTF-8"
else
    fail "CODESET with LOCPATH: '$CODESET' (expected UTF-8)"
fi

# 6. wcwidth(❯) == 1
WCWIDTH=$(LOCPATH="$LOCALE_DIR" LANG=en_US.UTF-8 "$ZSH" --no-rcs -c \
    'printf "%d" ${(m)#:-❯}' 2>/dev/null)
if [[ "$WCWIDTH" == "1" ]]; then
    pass "wcwidth(❯) == 1"
else
    fail "wcwidth(❯) == '$WCWIDTH' (expected 1 — cursor math will be off)"
fi

# 7. LOCPATH exported in deployed ~/.zprofile
if grep -q 'export LOCPATH' "$HOME/.zprofile" 2>/dev/null; then
    pass "LOCPATH exported in ~/.zprofile"
else
    fail "LOCPATH not in ~/.zprofile (run: chezmoi apply)"
fi

# 8. LOCPATH exported in deployed ~/.bash_profile
if grep -q 'export LOCPATH' "$HOME/.bash_profile" 2>/dev/null; then
    pass "LOCPATH exported in ~/.bash_profile"
else
    fail "LOCPATH not in ~/.bash_profile (run: chezmoi apply)"
fi

echo ""
if [[ "$FAILURES" -eq 0 ]]; then
    echo "All tests passed."
else
    echo "$FAILURES test(s) failed."
    exit 1
fi
