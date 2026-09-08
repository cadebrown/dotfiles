import json
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(sys.argv[1]).resolve()
original = {p.name: p.read_bytes() for p in (root / 'data').glob('*.txt')}
with tempfile.TemporaryDirectory() as directory:
    result = subprocess.run(['zsh', str(root / 'audit.zsh')], cwd=directory,
                            capture_output=True, text=True, timeout=15)
    assert result.returncode == 0, result.stderr
expected = {'alpha.txt': 3, 'file with spaces.txt': 0, 'last.txt': 1}
rows = [line.rsplit('\t', 1) for line in (root / 'report.tsv').read_text().splitlines()]
actual = {Path(name).name: int(count) for name, count in rows}
assert actual == expected, actual
assert [name for name, _ in rows] == sorted(name for name, _ in rows)
assert len(rows) == len(expected)
assert original == {p.name: p.read_bytes() for p in (root / 'data').glob('*.txt')}
print(json.dumps({'checks': ['literal occurrence counts, zero counts, spaces, final unterminated line',
                             'different cwd, deterministic sort, input preservation'], 'passed': True}))
