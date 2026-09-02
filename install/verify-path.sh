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
            log_fail "Unknown flag: $arg"
            exit 1
            ;;
    esac
done

# Directories to check. Flat mode makes LOCAL_PLAT/bin and ~/.local/bin the
# same directory, so append uniquely or every binary becomes its own duplicate.
PLAT_DIRS=()
_append_unique_dir() {
    local candidate="$1" existing
    for existing in "${PLAT_DIRS[@]-}"; do
        [[ "$existing" == "$candidate" ]] && return 0
    done
    PLAT_DIRS+=("$candidate")
}

_append_unique_dir "$LOCAL_PLAT/bin"
_append_unique_dir "$LOCAL_PLAT/cargo/bin"
_append_unique_dir "$HOME/.local/bin"

# If nvm has a default node, include it
if [[ -d "$NVM_DIR/versions/node" ]]; then
    _nvm_bin="$NVM_DIR/versions/node/$(ls "$NVM_DIR/versions/node/" 2>/dev/null | sort -V | tail -1)/bin"
    [[ -d "$_nvm_bin" ]] && _append_unique_dir "$_nvm_bin"
fi

if [[ "$FULL_PATH" == "1" ]]; then
    PLAT_DIRS=()
    while IFS= read -r _path_dir; do
        [[ -n "$_path_dir" ]] && _append_unique_dir "$_path_dir"
    done < <(printf '%s' "$PATH" | tr ':' '\n')
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
                        log_fail "Wrong arch: $bin ($file_out)"
                        ((ERRORS++)) || true
                    else
                        ((count++)) || true
                    fi
                    ;;
            esac
        done
    done
    log_okay "$count binaries match $ARCH"

    # In PLAT mode ~/.local/bin is shared across machines and must stay
    # architecture-neutral. In flat mode it is the intended native binary dir.
    _local_bin="$HOME/.local/bin"
    if [[ "$DF_USE_PLAT" == "1" && -d "$_local_bin" ]]; then
        _compiled=0
        for bin in "$_local_bin"/*; do
            [[ -f "$bin" && -x "$bin" ]] || continue
            [[ -L "$bin" ]] && continue
            file_out="$(file -b "$bin" 2>/dev/null)" || continue
            case "$file_out" in
                ELF*|Mach-O*)
                    log_fail "Compiled binary in ~/.local/bin/: $(basename "$bin") — move to \$LOCAL_PLAT/bin/"
                    ((_compiled++)) || true
                    ;;
            esac
        done
        if [[ "$_compiled" -gt 0 ]]; then
            ((ERRORS += _compiled))
        else
            log_okay "$HOME/.local/bin/ has no compiled binaries (arch-neutral only)"
        fi

        _compiled_links=0
        for bin in "$_local_bin"/*; do
            [[ -L "$bin" && -e "$bin" ]] || continue
            file_out="$(file -bL "$bin" 2>/dev/null || true)"
            case "$file_out" in
                ELF*|Mach-O*)
                    log_fail "Compiled symlink in ~/.local/bin/: $(basename "$bin") → $(readlink "$bin")"
                    ((_compiled_links++)) || true
                    ;;
            esac
        done
        if (( _compiled_links > 0 )); then
            ((ERRORS += _compiled_links))
        else
            log_okay "$HOME/.local/bin/ has no compiled symlink targets"
        fi
    fi
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
    log_okay "$count binaries have all shared libraries"
fi

# --- Duplicate detection ---
if [[ "$CHECK_DUPES" == "1" ]]; then
    log_section "Duplicate detection"
    seen_names=()
    seen_paths=()
    seen_count=0
    dupes=0
    for dir in "${PLAT_DIRS[@]}"; do
        [[ -d "$dir" ]] || continue
        for bin in "$dir"/*; do
            [[ -f "$bin" || -L "$bin" ]] || continue
            name="$(basename "$bin")"
            previous=""
            index=0
            while [[ "$index" -lt "$seen_count" ]]; do
                if [[ "${seen_names[$index]}" == "$name" ]]; then
                    previous="${seen_paths[$index]}"
                    break
                fi
                ((index++)) || true
            done
            if [[ -n "$previous" ]]; then
                log_warn "Duplicate: $name ($previous wins over $bin)"
                ((dupes++)) || true
            else
                seen_names[$seen_count]="$name"
                seen_paths[$seen_count]="$bin"
                ((seen_count++)) || true
            fi
        done
    done
    if [[ "$dupes" -gt 0 ]]; then
        log_warn "$dupes duplicates found"
        ((WARNINGS += dupes))
    else
        log_okay "No duplicates"
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
                log_fail "Broken symlink: $bin → $(readlink "$bin")"
                ((stale++)) || true
            fi
        done
    done
    if [[ "$stale" -gt 0 ]]; then
        log_fail "$stale broken symlinks"
        ((ERRORS += stale))
    else
        log_okay "No broken symlinks"
    fi
fi

# --- Summary ---
log_section "Summary"
if [[ "$ERRORS" -gt 0 ]]; then
    log_fail "$ERRORS errors, $WARNINGS warnings"
    exit 1
elif [[ "$WARNINGS" -gt 0 ]]; then
    log_warn "0 errors, $WARNINGS warnings"
    exit 0
else
    log_okay "All checks passed"
    exit 0
fi
