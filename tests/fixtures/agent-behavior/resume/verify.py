import json
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(sys.argv[1])
checks = []


def check(name, condition):
    checks.append({"name": name, "passed": bool(condition)})


expected = sorted([v for v in json.loads((root / "assets.json").read_text())
                   if v["status"] == "ready" and v["bytes"] >= 1024], key=lambda v: v["id"])
check("final artifact obeys inclusive cutoff and ordering", json.loads((root / "manifest.json").read_text()) == expected)
check("user notes preserved", (root / "user-notes.md").read_bytes() == (Path(__file__).parent / "input" / "user-notes.md").read_bytes())
check("durable plan and progress", all((root / name).is_file() for name in ("PLAN.md", "PROGRESS.md")))
with tempfile.TemporaryDirectory() as temporary:
    directory = Path(temporary)
    source, output = directory / "input.json", directory / "output.json"
    records = [
        {"id": "b", "status": "ready", "bytes": 1024, "path": "b"},
        {"id": "a", "status": "ready", "bytes": 100000, "path": "a"},
        {"id": "tiny", "status": "ready", "bytes": 1, "path": "tiny"},
    ]
    source.write_text(json.dumps(records))
    result = subprocess.run([sys.executable, str(root / "export_assets.py"), str(source), str(output)], capture_output=True)
    check("independent CLI input", result.returncode == 0 and json.loads(output.read_text()) == [records[1], records[0]])
    source.write_text(json.dumps(records + [{"id": "tiny", "status": "draft", "bytes": 0, "path": "different"}]))
    result = subprocess.run([sys.executable, str(root / "export_assets.py"), str(source), str(output)], capture_output=True)
    check("duplicate ID rejected before filtering", result.returncode != 0)
print(json.dumps({"checks": checks, "manual_review": [
    "Inspect turn-1-workspace: plan/checkpoint should exist and implementation should not.",
    "Confirm both turns used the same native thread ID in run.json, and final progress records the changed requirement and real validation."
]}, indent=2))
sys.exit(not all(c["passed"] for c in checks))
