#!/usr/bin/env bash
# Patches Homebrew's python@3.14 formula for Linux x86-64 compatibility
#
# Fixes:
#   1. Disables uuid module (build fails on some systems)
#   2. Skips test_datetime during PGO (hangs on AVX-512 CPUs)
#
# Uses Python for reliable multi-line patching (matches the approach used
# by mesa, fish, and fastfetch formula patches). Falls back to sed if
# Python is unavailable.
#
# Idempotent - safe to run multiple times

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_lib.sh"

# Only patch on Linux
[[ "$OS" != "linux" ]] && { log_okay "Python patches only needed on Linux"; exit 0; }

# Find Homebrew prefix
if [[ -z "${HOMEBREW_PREFIX:-}" ]]; then
    if [[ -d "$LOCAL_PLAT/brew" ]]; then
        export HOMEBREW_PREFIX="$LOCAL_PLAT/brew"
    else
        log_fail "Homebrew not found"
        exit 1
    fi
fi

FORMULA="$HOMEBREW_PREFIX/Homebrew/Library/Taps/homebrew/homebrew-core/Formula/p/python@3.14.rb"

if [[ ! -f "$FORMULA" ]]; then
    log_info "Python@3.14 formula not found (homebrew-core not tapped yet)"
    exit 0
fi

log_info "Patching python@3.14 formula for Linux compatibility..."

# Use Python for reliable multi-line patching
_py=""
if command -v python3 &>/dev/null; then
    _py="python3"
elif command -v python &>/dev/null; then
    _py="python"
fi

if [[ -n "$_py" ]]; then
    "$_py" - "$FORMULA" <<'PYEOF'
import sys

formula_path = sys.argv[1]
with open(formula_path, "r") as f:
    content = f.read()

changed = False

# Patch 1: Disable uuid module — insert after py_cv_module__tkinter=n/a
uuid_marker = "py_cv_module__uuid=n/a"
tkinter_marker = "py_cv_module__tkinter=n/a"
if uuid_marker not in content and tkinter_marker in content:
    content = content.replace(
        tkinter_marker,
        tkinter_marker + "\n      " + uuid_marker,
    )
    changed = True
    print("[info]  Added uuid disable patch")
elif uuid_marker in content:
    print("[okay]  UUID disable patch already present")

# Patch 2: Skip test_datetime in PROFILE_TASK — insert inreplace after system "./configure"
datetime_marker = "test_datetime"
configure_marker = 'system "./configure", *args'
if datetime_marker not in content and configure_marker in content:
    patch_block = '''

    # Patch Makefile to skip test_datetime in PROFILE_TASK
    inreplace "Makefile" do |s|
      s.gsub!(/^PROFILE_TASK=.*$/, "PROFILE_TASK=\\t-m test --pgo -x test_datetime --timeout=$(TESTTIMEOUT)")
    end'''
    content = content.replace(
        configure_marker,
        configure_marker + patch_block,
    )
    changed = True
    print("[info]  Added test_datetime skip patch")
elif datetime_marker in content:
    print("[okay]  PROFILE_TASK patch already present")

if changed:
    with open(formula_path, "w") as f:
        f.write(content)

sys.exit(0)
PYEOF
else
    # Fallback: sed-based patching (less reliable for multi-line)
    log_warn "Python not available — falling back to sed"

    # Patch 1: Disable uuid module
    if ! grep -q "py_cv_module__uuid=n/a" "$FORMULA"; then
        log_info "Adding uuid disable patch..."
        sed -i '/py_cv_module__tkinter=n\/a/a\      py_cv_module__uuid=n/a' "$FORMULA"
    else
        log_okay "UUID disable patch already present"
    fi

    # Patch 2: Skip test_datetime in PROFILE_TASK
    if ! grep -q "test_datetime" "$FORMULA"; then
        log_info "Adding test_datetime skip patch..."
        sed -i '/system "\.\/configure", \*args/a\
\
    # Patch Makefile to skip test_datetime in PROFILE_TASK\
    inreplace "Makefile" do |s|\
      s.gsub!(/^PROFILE_TASK=.*$/, "PROFILE_TASK=\\t-m test --pgo -x test_datetime --timeout=$(TESTTIMEOUT)")\
    end' "$FORMULA"
    else
        log_okay "PROFILE_TASK patch already present"
    fi
fi

log_okay "Python@3.14 formula patched successfully"
