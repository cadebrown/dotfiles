#!/usr/bin/env bash
# plat_Linux_x86-64-v3 — compile flags for x86-64-v3 (AVX2/FMA/BMI2)
# Intel Haswell+ (2013+), AMD Zen 2+ (2019+)
export CFLAGS="${CFLAGS:--march=x86-64-v3 -O2}"
export CXXFLAGS="${CXXFLAGS:--march=x86-64-v3 -O2}"
export RUSTFLAGS="${RUSTFLAGS:--C target-cpu=x86-64-v3}"
export HOMEBREW_OPTFLAGS="${HOMEBREW_OPTFLAGS:--march=x86-64-v3 -O2}"
export CMAKE_C_FLAGS="${CMAKE_C_FLAGS:--march=x86-64-v3 -O2}"
export CMAKE_CXX_FLAGS="${CMAKE_CXX_FLAGS:--march=x86-64-v3 -O2}"
