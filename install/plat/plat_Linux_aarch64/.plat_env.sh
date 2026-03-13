#!/usr/bin/env bash
# plat_Linux_aarch64 — compile flags for AArch64 Linux
# Generic armv8-a baseline — works on all 64-bit ARM CPUs.
# Add FEAT_SVE / FEAT_SVE2 flags here if targeting specific hardware.
export CFLAGS="${CFLAGS:--march=armv8-a -O2}"
export CXXFLAGS="${CXXFLAGS:--march=armv8-a -O2}"
export RUSTFLAGS="${RUSTFLAGS:--C target-cpu=generic}"
export HOMEBREW_OPTFLAGS="${HOMEBREW_OPTFLAGS:--march=armv8-a -O2}"
export CMAKE_C_FLAGS="${CMAKE_C_FLAGS:--march=armv8-a -O2}"
export CMAKE_CXX_FLAGS="${CMAKE_CXX_FLAGS:--march=armv8-a -O2}"
