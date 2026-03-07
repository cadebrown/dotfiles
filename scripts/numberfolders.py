#!/usr/bin/env python3
# numberfolders.py - prefix folders with sequential numbers for ordering
# Usage: numberfolders.py [directory]

import os
import sys

def number_folders(directory='.'):
    entries = sorted(
        e for e in os.listdir(directory)
        if os.path.isdir(os.path.join(directory, e))
        and not e.startswith('.')
    )

    for i, name in enumerate(entries):
        # Strip existing numeric prefix if present
        stripped = name.lstrip('0123456789').lstrip('_- ')
        new_name = f"{i+1:02d}_{stripped}"
        if new_name != name:
            src = os.path.join(directory, name)
            dst = os.path.join(directory, new_name)
            print(f"  {name} → {new_name}")
            os.rename(src, dst)

if __name__ == '__main__':
    target = sys.argv[1] if len(sys.argv) > 1 else '.'
    number_folders(target)
