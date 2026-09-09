#!/usr/bin/env bats

setup() {
    REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    CACHE_HELPER="$REPO/home/.chezmoitemplates/compiler-cache.sh"
    CACHE_HOME="$BATS_TEST_TMPDIR/home"
    CACHE_BIN="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$CACHE_HOME/.cache" "$CACHE_BIN"
    printf '#!/bin/sh\nexit 0\n' > "$CACHE_BIN/sccache"
    chmod +x "$CACHE_BIN/"*
}

@test "one compiler-cache default covers C C++ CUDA and Rust under strict installer flags" {
    run env -i HOME="$CACHE_HOME" PATH="$CACHE_BIN:/usr/bin:/bin" \
        /bin/bash -euo pipefail -c '. "$1"; printf "%s\n" "$CMAKE_C_COMPILER_LAUNCHER|$CMAKE_CXX_COMPILER_LAUNCHER|$CMAKE_CUDA_COMPILER_LAUNCHER|$RUSTC_WRAPPER|$SCCACHE_DIR|$SCCACHE_CACHE_SIZE"; env | sort' _ "$CACHE_HELPER"
    [ "$status" -eq 0 ]
    [[ "$output" == "sccache|sccache|sccache|sccache|$CACHE_HOME/.cache/sccache|250G"* ]]
    [[ "$output" == *"CMAKE_HIP_COMPILER_LAUNCHER=sccache"* ]]
    [[ "$output" == *"CMAKE_OBJC_COMPILER_LAUNCHER=sccache"* ]]
    [[ "$output" == *"CMAKE_OBJCXX_COMPILER_LAUNCHER=sccache"* ]]
    [[ "$output" != *"CCACHE_SLOPPINESS="* && "$output" != *"USE_CCACHE="* ]]
    [[ "$output" != *"CARGO_INCREMENTAL="* ]]
}

@test "compiler cache preserves explicit launchers empty bypasses and machine storage settings" {
    run env -i HOME="$CACHE_HOME" PATH="$CACHE_BIN:/usr/bin:/bin" \
        CMAKE_C_COMPILER_LAUNCHER=custom CMAKE_CXX_COMPILER_LAUNCHER= \
        RUSTC_WRAPPER= SCCACHE_DIR="$CACHE_HOME/local disk/cache" SCCACHE_CACHE_SIZE=37G \
        /bin/bash -euo pipefail -c '. "$1"; . "$1"; printf "%s\n" "$CMAKE_C_COMPILER_LAUNCHER|$CMAKE_CXX_COMPILER_LAUNCHER|$RUSTC_WRAPPER|$SCCACHE_DIR|$SCCACHE_CACHE_SIZE"' _ "$CACHE_HELPER"
    [ "$status" -eq 0 ]
    [ "$output" = "custom|||$CACHE_HOME/local disk/cache|37G" ]
}

@test "native cache configuration owns storage without conflicting environment defaults" {
    mkdir -p "$CACHE_HOME/.config/sccache"
    printf '[cache.disk]\nsize = 268435456000\n' > "$CACHE_HOME/.config/sccache/config"
    run env -i HOME="$CACHE_HOME" PATH="$CACHE_BIN:/usr/bin:/bin" \
        /bin/bash -euo pipefail -c '. "$1"; printf "%s" "$SCCACHE_CONF|${SCCACHE_CACHE_SIZE-unset}|${SCCACHE_DIR-unset}"' _ "$CACHE_HELPER"
    [ "$status" -eq 0 ]
    [ "$output" = "$CACHE_HOME/.config/sccache/config|unset|unset" ]

    run env -i HOME="$CACHE_HOME" PATH="$CACHE_BIN:/usr/bin:/bin" SCCACHE_CONF=/custom/config SCCACHE_CACHE_SIZE=32G \
        /bin/bash -euo pipefail -c '. "$1"; printf "%s" "$SCCACHE_CONF|$SCCACHE_CACHE_SIZE|${SCCACHE_DIR-unset}"' _ "$CACHE_HELPER"
    [ "$status" -eq 0 ]
    [ "$output" = '/custom/config|32G|unset' ]
}

@test "missing sccache leaves a clean environment usable without adding broken wrappers" {
    run env -i HOME="$CACHE_HOME" PATH=/nonexistent \
        /bin/bash -euo pipefail -c '. "$1"; printf "%s" "${RUSTC_WRAPPER-unset}|${CMAKE_C_COMPILER_LAUNCHER-unset}|${SCCACHE_DIR-unset}"' _ "$CACHE_HELPER"
    [ "$status" -eq 0 ]
    [ "$output" = 'unset|unset|unset' ]
}

@test "rendered shared profile exports sccache in Bash and Zsh without legacy ccache policy" {
    local shell_bin
    chezmoi --source "$REPO/home" execute-template --file "$REPO/home/dot_profile.tmpl" > "$CACHE_HOME/.profile"
    for shell_bin in /bin/bash "$(command -v zsh)"; do
        run env -i HOME="$CACHE_HOME" PATH="$CACHE_BIN:/usr/bin:/bin" \
            "$shell_bin" -c '. "$HOME/.profile"; printf "%s" "$CMAKE_CXX_COMPILER_LAUNCHER|$RUSTC_WRAPPER|${CCACHE_HARDLINK-unset}|${USE_CCACHE-unset}"'
        [ "$status" -eq 0 ]
        [ "$output" = 'sccache|sccache|unset|unset' ]
    done
}

@test "installer library shares defaults and preserves an explicit Rust cache bypass" {
    run env -i HOME="$CACHE_HOME" PATH="$CACHE_BIN:/usr/bin:/bin" DF_USE_PLAT=0 RUSTC_WRAPPER= \
        /bin/bash -c '. "$1/install/_lib.sh"; printf "%s" "$CMAKE_CXX_COMPILER_LAUNCHER|$RUSTC_WRAPPER|$SCCACHE_CACHE_SIZE"' _ "$REPO"
    [ "$status" -eq 0 ]
    [ "$output" = 'sccache||250G' ]
}

@test "inherited legacy profile guard cannot retain disabled Python or old compiler caches" {
    chezmoi --source "$REPO/home" execute-template --file "$REPO/home/dot_profile.tmpl" > "$CACHE_HOME/.profile"
    run env -i HOME="$CACHE_HOME" PATH="$CACHE_BIN:/usr/bin:/bin" _PROFILE_SOURCED=1 \
        CCACHE_SLOPPINESS=file_stat_matches,time_macros CCACHE_HARDLINK=1 USE_CCACHE=ON \
        CMAKE_C_COMPILER_LAUNCHER=ccache CMAKE_CXX_COMPILER_LAUNCHER=ccache \
        CMAKE_CUDA_COMPILER_LAUNCHER=ccache SCCACHE_CACHE_SIZE=74G PYTHONDONTWRITEBYTECODE=1 \
        /bin/bash -c '. "$HOME/.profile"; printf "%s" "$CMAKE_C_COMPILER_LAUNCHER|$CMAKE_CXX_COMPILER_LAUNCHER|$SCCACHE_CACHE_SIZE|${CCACHE_HARDLINK-unset}|${USE_CCACHE-unset}|${PYTHONDONTWRITEBYTECODE-unset}|$PYTHONPYCACHEPREFIX"'
    [ "$status" -eq 0 ]
    [ "$output" = "sccache|sccache|250G|unset|unset|unset|$CACHE_HOME/.cache/python/pycache" ]
}
