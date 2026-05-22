#!/usr/bin/env bash
# install/go.sh - install Go CLI tools from packages/go.txt
#
# Reads packages/go.txt (+ overlay copies via overlay_package_files), respects
# # linux-only / # macos-only markers, and runs `go install` per entry.
# Idempotent — Go's build cache short-circuits unchanged versions.
#
# Binaries land in $GOBIN (= $ARCH_BIN, $LOCAL_PLAT/bin) so they sit alongside
# cargo-binstall + uv-tool-installed CLIs without a second PATH entry.
#
# Prerequisite: `go` on PATH (installed via packages/Brewfile entry `brew "go"`).
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

log_section "Go CLI tools"

if ! has go; then
    log_warn "go not on PATH — install via Brewfile (\`brew install go\`) then re-run"
    exit 0
fi

log_okay "go: $(go version 2>&1 | head -1)"
ensure_dir "$GOBIN"
ensure_dir "$GOPATH"
ensure_dir "$GOCACHE"

_install_from() {
    local file="$1" _line _pkg _is_linux _is_macos
    log_info "Reading $file"
    while IFS= read -r _line; do
        # Skip blank lines and pure comments.
        [[ -z "${_line// }" || "$_line" == \#* ]] && continue

        # Same parser shape as install/python.sh's pip.txt loop.
        _is_linux="$(printf '%s' "$_line" | grep -c 'linux-only' || true)"
        _is_macos="$(printf '%s' "$_line" | grep -c 'macos-only' || true)"
        _pkg="$(printf '%s' "$_line" | sed 's/#.*//;s/^[[:space:]]*//;s/[[:space:]]*$//')"
        [[ -z "$_pkg" ]] && continue

        if (( _is_linux > 0 )) && [[ "$OS" != "linux" ]]; then
            log_debug "skip linux-only on $OS: $_pkg"
            (( _skip++ )) || true
            continue
        fi
        if (( _is_macos > 0 )) && [[ "$OS" != "darwin" ]]; then
            log_debug "skip macos-only on $OS: $_pkg"
            (( _skip++ )) || true
            continue
        fi

        log_info "  go install $_pkg"
        if run_logged go install "$_pkg"; then
            log_okay "  ok    $_pkg"
            (( _ok++ )) || true
        else
            log_warn "  fail  $_pkg"
            (( _fail++ )) || true
        fi
    done < "$file"
}

_ok=0 _skip=0 _fail=0

while IFS= read -r _file; do
    _install_from "$_file"
done < <(overlay_package_files "go.txt")

log_okay "Go tools: ${_ok} installed, ${_skip} skipped (platform), ${_fail} failed"
