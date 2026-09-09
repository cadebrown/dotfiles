#!/usr/bin/env bats

setup() {
    REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    CMAKE_BIN="$(command -v cmake)"
    CACHE_BIN="$BATS_TEST_TMPDIR/cache-bin"
    CACHE_FIXTURE="$BATS_TEST_TMPDIR/cache-fixture.cmake"
    mkdir -p "$CACHE_BIN"
    printf '#!/bin/sh\nexit 0\n' > "$CACHE_BIN/sccache"
    chmod 755 "$CACHE_BIN/sccache"
    printf '%s\n' "include(\"$REPO/install/cmake/toolchains/_cache.cmake\")" \
        'foreach(language C CXX CUDA OBJC OBJCXX HIP)' \
        '  message("${language}=${CMAKE_${language}_COMPILER_LAUNCHER}")' \
        'endforeach()' > "$CACHE_FIXTURE"
}

@test "CMake cache defaults every supported compiler launcher to discovered sccache" {
    run env -i PATH="$CACHE_BIN" "$CMAKE_BIN" -P "$CACHE_FIXTURE"

    [ "$status" -eq 0 ]
    for language in C CXX CUDA OBJC OBJCXX HIP; do
        [[ "$output" == *"${language}=$CACHE_BIN/sccache"* ]]
    done
}

@test "CMake cache preserves existing launchers and explicit environment bypasses" {
    run env -i PATH="$CACHE_BIN" \
        CMAKE_CXX_COMPILER_LAUNCHER=from-environment \
        CMAKE_CUDA_COMPILER_LAUNCHER= \
        "$CMAKE_BIN" -DCMAKE_C_COMPILER_LAUNCHER=from-cache -P "$CACHE_FIXTURE"

    [ "$status" -eq 0 ]
    [[ "$output" == *"C=from-cache"* ]]
    [[ "$output" == *"CXX=from-environment"* ]]
    [[ "$output" == *"CUDA="* ]]
    for language in OBJC OBJCXX HIP; do
        [[ "$output" == *"${language}=$CACHE_BIN/sccache"* ]]
    done
}

@test "CMake cache leaves unset launchers alone when sccache is unavailable" {
    run env -i PATH=/nonexistent "$CMAKE_BIN" -P "$CACHE_FIXTURE"

    [ "$status" -eq 0 ]
    for language in C CXX CUDA OBJC OBJCXX HIP; do
        [[ "$output" == *"${language}="* ]]
    done
}

@test "every managed GCC and LLVM toolchain activates the shared cache policy" {
    local toolchain
    for toolchain in gcc-13 gcc-15 llvm-21 llvm-22; do
        printf '%s\n' "include(\"$REPO/install/cmake/toolchains/$toolchain.cmake\")" \
            'foreach(language C CXX CUDA OBJC OBJCXX HIP)' \
            '  message("${language}=${CMAKE_${language}_COMPILER_LAUNCHER}")' \
            'endforeach()' > "$CACHE_FIXTURE"
        run env -i PATH="$CACHE_BIN" "$CMAKE_BIN" -P "$CACHE_FIXTURE"
        [ "$status" -eq 0 ]
        for language in C CXX CUDA OBJC OBJCXX HIP; do
            [[ "$output" == *"${language}=$CACHE_BIN/sccache"* ]]
        done
    done
}

@test "platform defaults retain architecture settings without forcing optimization" {
    local platform expected result
    while IFS='|' read -r platform expected; do
        run env -i PATH="$PATH" /bin/bash -c \
            '. "$1"; printf "%s|%s|%s|%s" "$CFLAGS" "$CXXFLAGS" "$CMAKE_C_FLAGS" "$CMAKE_CXX_FLAGS"' \
            _ "$REPO/install/plat/$platform/.plat_env.sh"
        [ "$status" -eq 0 ]
        result="$output"
        [ "$result" = "${expected}|${expected}|${expected}|${expected}" ]
        [[ "$result" != *-O2* ]]
    done <<'PLATFORMS'
plat_Darwin_arm64|-march=armv8.5-a
plat_Darwin_x86-64|-march=x86-64-v3
plat_Linux_aarch64|-march=armv8-a
plat_Linux_x86-64-v2|-march=x86-64-v2
plat_Linux_x86-64-v3|-march=x86-64-v3
plat_Linux_x86-64-v4|-march=x86-64-v4
PLATFORMS
}

@test "platform environments preserve explicit C and CMake flags" {
    local platform
    for platform in "$REPO"/install/plat/*/.plat_env.sh; do
        run env -i PATH="$PATH" CFLAGS='-g -O0' CXXFLAGS='-stdlib=libc++' \
            CMAKE_C_FLAGS='-DCMAKE_TEST=one' CMAKE_CXX_FLAGS='-DCMAKE_TEST=two' \
            /bin/bash -c '. "$1"; printf "%s|%s|%s|%s" "$CFLAGS" "$CXXFLAGS" "$CMAKE_C_FLAGS" "$CMAKE_CXX_FLAGS"' \
            _ "$platform"
        [ "$status" -eq 0 ]
        [ "$output" = '-g -O0|-stdlib=libc++|-DCMAKE_TEST=one|-DCMAKE_TEST=two' ]
    done
}
