#!/usr/bin/env bash
# plat_Darwin_arm64 — compile flags for Apple Silicon (M1/M2/M3/M4+)
# -march=armv8.5-a matches the M1 baseline; Homebrew uses -march=native on macOS.
# Pin deployment target to avoid cc-rs querying a pre-release SDK version
# (on macOS 16 pre-release, the SDK version comes back as 26.x which breaks
# vendored C++ sources that include standard headers like <cwctype>).
export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-15.0}"
# On macOS 26 pre-release the CLT's c++/v1/ is incomplete — add the SDK's
# C++ headers explicitly so vendored C++ builds (e.g. difftastic) can find
# standard headers like <cwctype>.
_plat_sdk="$(xcrun --show-sdk-path 2>/dev/null)"
export CFLAGS="${CFLAGS:--march=armv8.5-a -O2}"
export CXXFLAGS="${CXXFLAGS:--march=armv8.5-a -O2${_plat_sdk:+ -I${_plat_sdk}/usr/include/c++/v1}}"
unset _plat_sdk
export RUSTFLAGS="${RUSTFLAGS:--C target-cpu=apple-m1}"
# HOMEBREW_OPTFLAGS is not used on macOS (bottles are pre-built for arm64)
export CMAKE_C_FLAGS="${CMAKE_C_FLAGS:--march=armv8.5-a -O2}"
export CMAKE_CXX_FLAGS="${CMAKE_CXX_FLAGS:--march=armv8.5-a -O2}"
