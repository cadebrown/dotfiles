#!/usr/bin/env bash
# install/verify-path.sh - diagnostic tool to verify PATH binaries
#
# Checks that all binaries in PLAT-managed directories are compatible
# with the current machine. Not called by bootstrap — run manually
# or via the `verify-path` shell alias.
#
# Usage:
#   bash ~/dotfiles/install/verify-path.sh [--arch] [--libs] [--duplicates] [--symlinks] [--all] [--full]
#
# Flags:
#   --arch       Check ELF/Mach-O architecture matches current machine
#   --libs       Check shared library availability (Linux only, ldd)
#   --duplicates Find binaries appearing in multiple PATH directories
#   --symlinks   Find broken symlinks in PATH directories
#   --all        Run all checks (default)
#   --full       Check entire PATH, not just PLAT dirs

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

# Parse flags
CHECK_ARCH=0
CHECK_LIBS=0
CHECK_DUPES=0
CHECK_SYMLINKS=0
FULL_PATH=0

if [[ $# -eq 0 ]]; then
    CHECK_ARCH=1 CHECK_LIBS=1 CHECK_DUPES=1 CHECK_SYMLINKS=1
fi

for arg in "$@"; do
    case "$arg" in
        --arch)       CHECK_ARCH=1 ;;
        --libs)       CHECK_LIBS=1 ;;
        --duplicates) CHECK_DUPES=1 ;;
        --symlinks)   CHECK_SYMLINKS=1 ;;
        --all)        CHECK_ARCH=1; CHECK_LIBS=1; CHECK_DUPES=1; CHECK_SYMLINKS=1 ;;
        --full)       FULL_PATH=1 ;;
        --help|-h)
            echo "Usage: verify-path.sh [--arch] [--libs] [--duplicates] [--symlinks] [--all] [--full]"
            exit 0
            ;;
        *)
            log_error "Unknown flag: $arg"
            exit 1
            ;;
    esac
done

# Directories to check
PLAT_DIRS=(
    "$LOCAL_PLAT/bin"
    "$LOCAL_PLAT/cargo/bin"
    "$HOME/.local/bin"
)
[[ -d "$LOCAL_PLAT/venv/bin" ]] && PLAT_DIRS+=("$LOCAL_PLAT/venv/bin")

# If nvm has a default node, include it
if [[ -d "$NVM_DIR/versions/node" ]]; then
    _nvm_bin="$NVM_DIR/versions/node/$(ls "$NVM_DIR/versions/node/" 2>/dev/null | sort -V | tail -1)/bin"
    [[ -d "$_nvm_bin" ]] && PLAT_DIRS+=("$_nvm_bin")
fi

if [[ "$FULL_PATH" == "1" ]]; then
    IFS=: read -ra PLAT_DIRS <<< "$PATH"
fi

ERRORS=0
WARNINGS=0

# Expected architecture patterns for `file` output
case "$ARCH" in
    aarch64) ARCH_PATTERN="aarch64\|ARM aarch64\|arm64" ;;
    x86_64)  ARCH_PATTERN="x86-64\|x86_64\|AMD64" ;;
    *)       ARCH_PATTERN="$ARCH" ;;
esac

# --- Architecture check ---
if [[ "$CHECK_ARCH" == "1" ]]; then
    log_section "Architecture check (expecting $ARCH)"
    count=0
    for dir in "${PLAT_DIRS[@]}"; do
        [[ -d "$dir" ]] || continue
        for bin in "$dir"/*; do
            [[ -f "$bin" && -x "$bin" ]] || continue
            [[ -L "$bin" ]] && continue  # skip symlinks, check targets separately
            file_out="$(file -b "$bin" 2>/dev/null)" || continue
            # Only check ELF and Mach-O binaries
            case "$file_out" in
                ELF*|Mach-O*)
                    if ! echo "$file_out" | grep -qi "$ARCH_PATTERN"; then
                        log_error "Wrong arch: $bin ($file_out)"
                        ((ERRORS++)) || true
                    else
                        ((count++)) || true
                    fi
                    ;;
            esac
        done
    done
    log_ok "$count binaries match $ARCH"
fi

# --- Shared library check (Linux only) ---
if [[ "$CHECK_LIBS" == "1" && "$OS" == "linux" ]]; then
    log_section "Shared library check"
    count=0
    missing=0
    for dir in "${PLAT_DIRS[@]}"; do
        [[ -d "$dir" ]] || continue
        # Skip Homebrew dirs — they bundle their own glibc
        [[ "$dir" == *"/brew/"* ]] && continue
        for bin in "$dir"/*; do
            [[ -f "$bin" && -x "$bin" ]] || continue
            file_out="$(file -b "$bin" 2>/dev/null)" || continue
            case "$file_out" in
                ELF*)
                    ldd_out="$(ldd "$bin" 2>/dev/null)" || continue
                    if echo "$ldd_out" | grep -q "not found"; then
                        not_found="$(echo "$ldd_out" | grep "not found" | awk '{print $1}' | tr '\n' ', ')"
                        log_warn "Missing libs for $bin: $not_found"
                        ((missing++)) || true
                    else
                        ((count++)) || true
                    fi
                    ;;
            esac
        done
    done
    if [[ "$missing" -gt 0 ]]; then
        log_warn "$missing binaries with missing libraries"
        ((WARNINGS += missing))
    fi
    log_ok "$count binaries have all shared libraries"
fi

# --- Duplicate detection ---
if [[ "$CHECK_DUPES" == "1" ]]; then
    log_section "Duplicate detection"
    declare -A seen_bins
    dupes=0
    for dir in "${PLAT_DIRS[@]}"; do
        [[ -d "$dir" ]] || continue
        for bin in "$dir"/*; do
            [[ -f "$bin" || -L "$bin" ]] || continue
            name="$(basename "$bin")"
            if [[ -n "${seen_bins[$name]:-}" ]]; then
                log_warn "Duplicate: $name (${seen_bins[$name]} wins over $bin)"
                ((dupes++)) || true
            else
                seen_bins[$name]="$bin"
            fi
        done
    done
    if [[ "$dupes" -gt 0 ]]; then
        log_warn "$dupes duplicates found"
        ((WARNINGS += dupes))
    else
        log_ok "No duplicates"
    fi
fi

# --- Stale symlinks ---
if [[ "$CHECK_SYMLINKS" == "1" ]]; then
    log_section "Stale symlink check"
    stale=0
    for dir in "${PLAT_DIRS[@]}"; do
        [[ -d "$dir" ]] || continue
        for bin in "$dir"/*; do
            if [[ -L "$bin" && ! -e "$bin" ]]; then
                log_error "Broken symlink: $bin → $(readlink "$bin")"
                ((stale++)) || true
            fi
        done
    done
    if [[ "$stale" -gt 0 ]]; then
        log_error "$stale broken symlinks"
        ((ERRORS += stale))
    else
        log_ok "No broken symlinks"
    fi
fi

# --- Summary ---
log_section "Summary"
if [[ "$ERRORS" -gt 0 ]]; then
    log_error "$ERRORS errors, $WARNINGS warnings"
    exit 1
elif [[ "$WARNINGS" -gt 0 ]]; then
    log_warn "0 errors, $WARNINGS warnings"
    exit 0
else
    log_ok "All checks passed"
    exit 0
fi
