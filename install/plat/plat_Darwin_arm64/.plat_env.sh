#!/usr/bin/env bash
# plat_Darwin_arm64 — compile flags for Apple Silicon (M1/M2/M3/M4+)
# -march=armv8.5-a matches the M1 baseline; Homebrew uses -march=native on macOS.
# Pin deployment target to avoid cc-rs querying a pre-release SDK version
# (on macOS 16 pre-release, the SDK version comes back as 26.x which breaks
# vendored C++ sources that include standard headers like <cwctype>).
export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-15.0}"
export CFLAGS="${CFLAGS:--march=armv8.5-a -O2}"
# Don't inject Apple's SDK c++/v1 into CXXFLAGS — Apple's libc++ headers
# don't compose with Homebrew clang (FP_NORMAL/FP_SUBNORMAL come out
# undeclared via <math.h>). Homebrew clang has its own bundled libc++ at
# $(brew --prefix llvm)/include/c++/v1 in its default search path; AppleClang
# finds Apple's libc++ on its own via the SDK. Either way, no -I needed here.
export CXXFLAGS="${CXXFLAGS:--march=armv8.5-a -O2}"
export RUSTFLAGS="${RUSTFLAGS:--C target-cpu=apple-m1}"
# HOMEBREW_OPTFLAGS is not used on macOS (bottles are pre-built for arm64)
export CMAKE_C_FLAGS="${CMAKE_C_FLAGS:--march=armv8.5-a -O2}"
export CMAKE_CXX_FLAGS="${CMAKE_CXX_FLAGS:--march=armv8.5-a -O2}"
