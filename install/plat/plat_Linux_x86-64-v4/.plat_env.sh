#!/usr/bin/env bash
# plat_Linux_x86-64-v4 — compile flags for x86-64-v4 (AVX-512)
# Intel Skylake-X / Ice Lake+, some AMD Zen 4+
export CFLAGS="${CFLAGS:--march=x86-64-v4 -O2}"
export CXXFLAGS="${CXXFLAGS:--march=x86-64-v4 -O2}"
export RUSTFLAGS="${RUSTFLAGS:--C target-cpu=x86-64-v4}"
export HOMEBREW_OPTFLAGS="${HOMEBREW_OPTFLAGS:--march=x86-64-v4 -O2}"
export CMAKE_C_FLAGS="${CMAKE_C_FLAGS:--march=x86-64-v4 -O2}"
export CMAKE_CXX_FLAGS="${CMAKE_CXX_FLAGS:--march=x86-64-v4 -O2}"
