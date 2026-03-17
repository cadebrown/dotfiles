#!/bin/sh
# plat_Linux_x86-64-v4 — x86-64 microarchitecture level 4
# Requires: all of v3 + AVX-512 (avx512f, avx512bw, avx512cd, avx512dq, avx512vl)
# Typical CPUs: Intel Skylake-X / Ice Lake+, some AMD Zen 4+
# If this check fails, the next lower level (v3) will be tried.
[ "$(uname -s)" = "Linux" ] || exit 1
[ "$(uname -m)" = "x86_64" ] || exit 1
for flag in avx512f avx512bw avx512cd avx512dq avx512vl \
            avx avx2 bmi1 bmi2 f16c fma lzcnt movbe xsave \
            cx16 popcnt sse4_1 sse4_2 ssse3; do
    grep -qw "$flag" /proc/cpuinfo 2>/dev/null || exit 1
done
exit 0
