"""Regenerate the synthetic log and its oracle; no model or network involved."""

from datetime import datetime, timedelta, timezone
import hashlib
import json
from pathlib import Path
import random


ROOT = Path(__file__).parent
randomizer = random.Random(20260908)
positions = randomizer.sample(range(1, 2401), 73)
scheduled = dict(zip(positions, ["E_COMPILE"] * 31 + ["E_FETCH"] * 23 + ["E_LINK"] * 19))
details = {
    "E_COMPILE": ("compiler", "module dependency did not resolve"),
    "E_FETCH": ("packages", "registry mirror request timed out"),
    "E_LINK": ("linker", "duplicate symbol in synthetic object"),
}
groups = {}
lines = []
start = datetime(2026, 8, 7, 10, 0, tzinfo=timezone.utc)
for number in range(1, 2401):
    timestamp = (start + timedelta(milliseconds=number * 125)).isoformat()
    if number in scheduled:
        code = scheduled[number]
        component, message = details[code]
        line = f'{timestamp} level=ERROR component={component} code={code} message="{message}; unit={number % 127}"'
        group = groups.setdefault(code, {"code": code, "count": 0, "first_line": number,
                                         "last_line": number, "example": line})
        group["count"] += 1
        group["last_line"] = number
    elif number % 29 == 0:
        line = f'{timestamp} level=INFO component=fixtures code=OK message="literal level=ERROR code=E_FETCH is expected test input"'
    elif number % 17 == 0:
        line = f'{timestamp} level=WARN component=cache code=E_COMPILE message="ERROR-like diagnostic was recovered; cache miss unit={number % 127}"'
    elif number % 41 == 0:
        line = f'    at synthetic_stack_frame_{number}: ERROR text in a continuation, not an ERROR-level record'
    else:
        line = f'{timestamp} level=INFO component=builder code=OK message="compiled unit={number % 127} artifact=target/object-{number:04d}.o cache=hit"'
    lines.append(line)
log = ROOT / "input" / "logs" / "build-output.txt"
log.parent.mkdir(exist_ok=True)
log.write_text("\n".join(lines) + "\n")
(ROOT / "expected-log.json").write_text(json.dumps({
    "total_lines": len(lines), "error_count": len(scheduled),
    "groups": [groups[code] for code in sorted(groups)],
}, indent=2) + "\n")
preserved = ("logs/build-output.txt", "check.py", "user-notes.txt", "events/__init__.py")
(ROOT / "preserved-inputs.json").write_text(json.dumps({
    name: hashlib.sha256((ROOT / "input" / name).read_bytes()).hexdigest() for name in preserved
}, indent=2) + "\n")
