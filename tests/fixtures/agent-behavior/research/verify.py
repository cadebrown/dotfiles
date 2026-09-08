import json
from pathlib import Path
import sys

root = Path(sys.argv[1])
path = root / "decision.md"
text = path.read_text() if path.is_file() else ""
checks = [
    {"name": "decision artifact exists", "passed": bool(text.strip())},
    {"name": "recommendation stays within requested length", "passed": 0 < len(text.split()) <= 700},
    {"name": "cites WAL primary source", "passed": "https://www.sqlite.org/wal.html" in text},
    {"name": "cites backup primary source", "passed": "https://www.sqlite.org/backup.html" in text},
]
print(json.dumps({"checks": checks, "manual_review": [
    "Correctly rejects many simultaneous writers while preserving reader/writer concurrency.",
    "Explains why a raw main-file copy may omit committed WAL state and recommends a consistent backup method.",
    "Handles multi-host NFS explicitly; distinguishes SQLite facts from the chosen single-writer/local-service design.",
    "Proposes a useful contention or backup measurement and does not invent measured performance or version safety."
]}, indent=2))
sys.exit(not all(c["passed"] for c in checks))
