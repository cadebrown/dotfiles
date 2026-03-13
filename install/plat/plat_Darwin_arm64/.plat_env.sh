#!/usr/bin/env bash
# plat_Darwin_arm64 — compile flags for Apple Silicon (M1/M2/M3/M4+)
# -march=armv8.5-a matches the M1 baseline; Homebrew uses -march=native on macOS.
export CFLAGS="${CFLAGS:--march=armv8.5-a -O2}"
export CXXFLAGS="${CXXFLAGS:--march=armv8.5-a -O2}"
export RUSTFLAGS="${RUSTFLAGS:--C target-cpu=apple-m1}"
# HOMEBREW_OPTFLAGS is not used on macOS (bottles are pre-built for arm64)
export CMAKE_C_FLAGS="${CMAKE_C_FLAGS:--march=armv8.5-a -O2}"
export CMAKE_CXX_FLAGS="${CMAKE_CXX_FLAGS:--march=armv8.5-a -O2}"
