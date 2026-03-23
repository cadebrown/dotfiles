#!/bin/bash
# BSP tiling: new windows split horizontally beside the focused window
# instead of being appended to the root container (e.g., as another accordion entry).
# Uses polling since `aerospace subscribe` is not available in v0.20.x.
prev=$(aerospace list-windows --workspace focused --count 2>/dev/null || echo 0)
while true; do
    curr=$(aerospace list-windows --workspace focused --count 2>/dev/null || echo 0)
    if [ "$curr" -gt "$prev" ]; then
        aerospace split horizontal
    fi
    prev=$curr
    sleep 0.1
done
