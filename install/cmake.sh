#!/usr/bin/env bash
# install/cmake.sh — install CMake toolchain files to $LOCAL_PLAT/cmake/toolchains/
# Idempotent: copies source files from install/cmake/toolchains/ — safe to re-run.

set -euo pipefail
. "$(dirname "$0")/_lib.sh"

log_section "cmake toolchains"

_src="$DF_ROOT/install/cmake/toolchains"
_dst="$LOCAL_PLAT/cmake/toolchains"

if [ ! -d "$_src" ]; then
    die "toolchain sources not found: $_src"
fi

ensure_dir "$_dst"

for _f in "$_src"/*.cmake; do
    _name="$(basename "$_f")"
    cp "$_f" "$_dst/$_name"
    log_okay "installed $_name → $_dst/$_name"
done

unset _src _dst _f _name
