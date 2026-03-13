#!/bin/sh
# plat_Darwin_arm64 — Apple Silicon (M1/M2/M3/M4+)
[ "$(uname -s)" = "Darwin" ] || exit 1
[ "$(uname -m)" = "arm64" ] || exit 1
exit 0
