#!/usr/bin/env bash
# Patches Homebrew's python@3.14 formula for Linux x86-64 compatibility
#
# Fixes:
#   1. Disables uuid module (build fails on some systems)
#   2. Skips test_datetime during PGO (hangs on AVX-512 CPUs)
#
# Idempotent - safe to run multiple times

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_lib.sh"

# Only patch on Linux
[[ "$OS" != "linux" ]] && { log_ok "Python patches only needed on Linux"; exit 0; }

# Find Homebrew prefix
if [[ -z "${HOMEBREW_PREFIX:-}" ]]; then
    if [[ -d "$LOCAL_PLAT/brew" ]]; then
        export HOMEBREW_PREFIX="$LOCAL_PLAT/brew"
    else
        log_error "Homebrew not found"
        exit 1
    fi
fi

FORMULA="$HOMEBREW_PREFIX/Homebrew/Library/Taps/homebrew/homebrew-core/Formula/p/python@3.14.rb"

if [[ ! -f "$FORMULA" ]]; then
    log_info "Python@3.14 formula not found (homebrew-core not tapped yet)"
    exit 0
fi

log_info "Patching python@3.14 formula for Linux compatibility..."

# Patch 1: Disable uuid module
if ! grep -q "py_cv_module__uuid=n/a" "$FORMULA"; then
    log_info "Adding uuid disable patch..."
    # Insert after py_cv_module__tkinter line
    sed -i '/py_cv_module__tkinter=n\/a/a\      py_cv_module__uuid=n/a' "$FORMULA"
else
    log_ok "UUID disable patch already present"
fi

# Patch 2: Skip test_datetime in PROFILE_TASK
if ! grep -q "test_datetime" "$FORMULA"; then
    log_info "Adding test_datetime skip patch..."
    # Insert inreplace block after system "./configure"
    sed -i '/system "\.\/configure", \*args/a\
\
    # Patch Makefile to skip test_datetime in PROFILE_TASK\
    inreplace "Makefile" do |s|\
      s.gsub!(/^PROFILE_TASK=.*$/, "PROFILE_TASK=\\t-m test --pgo -x test_datetime --timeout=$(TESTTIMEOUT)")\
    end' "$FORMULA"
else
    log_ok "PROFILE_TASK patch already present"
fi

log_ok "Python@3.14 formula patched successfully"
