#!/bin/sh
# plat_Linux_aarch64 — 64-bit ARM on Linux
# Covers all AArch64 CPUs (Graviton, Apple Silicon via Rosetta, Ampere, etc.)
[ "$(uname -s)" = "Linux" ] || exit 1
[ "$(uname -m)" = "aarch64" ] || exit 1
exit 0
