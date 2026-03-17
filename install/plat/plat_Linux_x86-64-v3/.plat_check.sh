#!/bin/sh
# plat_Linux_x86-64-v3 — x86-64 microarchitecture level 3
# Requires: all of v2 + AVX/AVX2/BMI2/FMA (but NOT AVX-512)
# Typical CPUs: Intel Haswell+ (2013+), AMD Zen 2+ (2019+)
# If this check fails, the next lower level (v2) will be tried.
[ "$(uname -s)" = "Linux" ] || exit 1
[ "$(uname -m)" = "x86_64" ] || exit 1
for flag in avx avx2 bmi1 bmi2 f16c fma movbe xsave \
            cx16 popcnt sse4_1 sse4_2 ssse3; do
    grep -qw "$flag" /proc/cpuinfo 2>/dev/null || exit 1
done
# lzcnt is reported as "lzcnt" on Intel and "abm" on AMD — accept either
{ grep -qw "lzcnt" /proc/cpuinfo 2>/dev/null || grep -qw "abm" /proc/cpuinfo 2>/dev/null; } || exit 1
exit 0
