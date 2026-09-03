#!/usr/bin/env bash
# install/audit-versions.sh — read-only toolchain version report.
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

# Fresh bootstraps run this before a new login shell. Resolve managed binaries
# from their authoritative roots rather than whatever the caller happened to
# have on PATH.
PATH="$CARGO_HOME/bin:$ELAN_HOME/bin:$ARCH_BIN:$PATH"
export PATH

usage() {
    printf 'Usage: %s [--strict]\n' "${0##*/}"
    printf 'Print a JSON array. --strict exits 1 when a required version is missing or stale.\n'
}

strict=0
case "${1:-}" in
    "") ;;
    --strict) strict=1 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
esac

has jq || { printf '%s\n' 'audit-versions.sh requires jq' >&2; exit 2; }

rows=()
failed=0

normalize_version() {
    printf '%s\n' "$1" | sed -E 's/^[^0-9]*//; s/[^0-9.].*$//'
}

version_at_least() {
    local actual expected a1 a2 a3 e1 e2 e3
    actual="$(normalize_version "$1")"
    expected="$(normalize_version "$2")"
    IFS=. read -r a1 a2 a3 <<< "$actual"
    IFS=. read -r e1 e2 e3 <<< "$expected"
    a1="${a1:-0}"; a2="${a2:-0}"; a3="${a3:-0}"
    e1="${e1:-0}"; e2="${e2:-0}"; e3="${e3:-0}"
    (( 10#$a1 > 10#$e1 )) && return 0
    (( 10#$a1 < 10#$e1 )) && return 1
    (( 10#$a2 > 10#$e2 )) && return 0
    (( 10#$a2 < 10#$e2 )) && return 1
    (( 10#$a3 >= 10#$e3 ))
}

record() {
    local tool expected mode manager source installed status
    tool="$1"; expected="$2"; mode="$3"; manager="$4"; source="$5"; installed="$6"
    if [[ -z "$installed" ]]; then
        status="missing"
    elif [[ "$mode" == "major" ]] && [[ "$(normalize_version "$installed")" == "$expected".* ]]; then
        status="current"
    elif [[ "$mode" == "exact" ]] && [[ "$(normalize_version "$installed")" == "$expected" ]]; then
        status="current"
    elif [[ "$mode" == "minimum" ]] && version_at_least "$installed" "$expected"; then
        status="current"
    else
        status="outdated"
    fi
    [[ "$status" == "current" ]] || failed=1
    rows+=("$(jq -cn --arg tool "$tool" --arg manager "$manager" \
        --arg expected "$expected" --arg policy "$mode" --arg installed "$installed" \
        --arg status "$status" --arg source "$source" --arg platform "$OS/$ARCH" \
        '{tool:$tool, manager:$manager, expected:$expected, policy:$policy,
          installed:$installed, status:$status, source:$source, platform:$platform}')")
}

command_version() {
    local command="$1" pattern="$2" output
    has "$command" || return 0
    output="$("$command" --version 2>/dev/null | head -1 || true)"
    printf '%s\n' "$output" | sed -nE "$pattern"
}

record rustup 1.29.1 minimum rustup repo-baseline "$(command_version rustup 's/^rustup ([0-9.]+).*/\1/p')"
record rustc 1.98.0 minimum rustup stable "$(command_version rustc 's/^rustc ([0-9.]+).*/\1/p')"
record node 24 major nvm lts "$(command_version node 's/^v?([0-9.]+).*/\1/p')"
record nvm 0.40.7 exact nvm repo-pin "$(bash -c 'NVM_DIR="$1"; [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh" >/dev/null 2>&1 && nvm --version' _ "$NVM_DIR" 2>/dev/null || true)"
record npm 12 minimum npm configured-major "$(command_version npm 's/^v?([0-9.]+).*/\1/p')"
record python 3.14 major homebrew python@3.14 "$(command_version python3 's/^Python ([0-9.]+).*/\1/p')"
record uv 0.12 major uv self-update "$(command_version uv 's/^uv ([0-9.]+).*/\1/p')"
record go 1.27 minimum homebrew go "$(go version 2>/dev/null | sed -nE 's/^go version go([0-9.]+).*/\1/p' || true)"
record zig 0.16.0 exact homebrew zig "$(zig version 2>/dev/null | sed -nE 's/^([0-9.]+).*/\1/p' || true)"
record juliaup 1.22.3 minimum homebrew juliaup "$(command_version juliaup 's/^Juliaup ([0-9.]+).*/\1/p')"
record julia 1.12.7 minimum juliaup release "$(command_version julia 's/^julia version ([0-9.]+).*/\1/p')"
record lean 4.33.1 exact elan mathlib-paired-pin "$(command_version lean 's/^Lean \(version ([0-9.]+).*/\1/p')"
record llvm@22 22.1.8 exact homebrew llvm@22 "$(brew list --versions llvm@22 2>/dev/null | awk '{print $2}' || true)"
record cmake 4.4.2 minimum homebrew cmake "$(command_version cmake 's/^cmake version ([0-9.]+).*/\1/p')"
record ninja 1.13.2 minimum homebrew ninja "$(command_version ninja 's/^([0-9.]+).*/\1/p')"
record quarto 1.10.18 exact quarto release-archive "$(command_version quarto 's/^([0-9.]+).*/\1/p')"

printf '%s\n' "${rows[@]}" | jq -s .
if (( strict && failed )); then
    exit 1
fi
