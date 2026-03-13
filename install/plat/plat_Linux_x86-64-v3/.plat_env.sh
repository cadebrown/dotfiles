#!/usr/bin/env bash
# plat_Linux_x86-64-v3 — compile flags for x86-64-v3 (AVX2/FMA/BMI2)
# Intel Haswell+ (2013+), AMD Zen 2+ (2019+)
export CFLAGS="-march=x86-64-v3 -O2"
export CXXFLAGS="-march=x86-64-v3 -O2"
export RUSTFLAGS="-C target-cpu=x86-64-v3"
export HOMEBREW_OPTFLAGS="-march=x86-64-v3 -O2"
export CMAKE_C_FLAGS="-march=x86-64-v3 -O2"
export CMAKE_CXX_FLAGS="-march=x86-64-v3 -O2"
