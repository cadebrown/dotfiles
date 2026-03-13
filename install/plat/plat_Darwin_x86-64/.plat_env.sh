#!/usr/bin/env bash
# plat_Darwin_x86-64 — compile flags for Intel Mac
# x86-64-v3 covers all Haswell-era and later Intel Macs (2013+)
export CFLAGS="-march=x86-64-v3 -O2"
export CXXFLAGS="-march=x86-64-v3 -O2"
export RUSTFLAGS="-C target-cpu=x86-64-v3"
export CMAKE_C_FLAGS="-march=x86-64-v3 -O2"
export CMAKE_CXX_FLAGS="-march=x86-64-v3 -O2"
