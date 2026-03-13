#!/bin/sh
# plat_Linux_x86-64-v2 — x86-64 microarchitecture level 2
# Requires: SSE4.2, POPCNT, CX16, LAHF_LM (the v2 baseline from glibc/psABI)
# Typical CPUs: Intel Nehalem+ (2008+), AMD K10+ (2010+)
# This is the lowest level we build — v1 (generic x86-64) is the OS fallback.
[ "$(uname -s)" = "Linux" ] || exit 1
[ "$(uname -m)" = "x86_64" ] || exit 1
for flag in cx16 lahf_lm popcnt sse4_1 sse4_2 ssse3; do
    grep -qw "$flag" /proc/cpuinfo 2>/dev/null || exit 1
done
exit 0
