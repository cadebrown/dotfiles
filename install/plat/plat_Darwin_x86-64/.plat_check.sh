#!/bin/sh
# plat_Darwin_x86-64 — Intel Mac
[ "$(uname -s)" = "Darwin" ] || exit 1
[ "$(uname -m)" = "x86_64" ] || exit 1
exit 0
