import importlib.util
import json
from pathlib import Path
import random
import sys

root = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("candidate", root / "merge_ranges.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
merge = module.merge_ranges
checks = []


def check(name, condition):
    checks.append({"name": name, "passed": bool(condition)})


check("nested, touching, empty and unordered intervals",
      merge([(8, 9), (3, 3), (2, 4), (1, 7), (7, 8)]) == [(1, 9)])
check("empty input", merge([]) == [])
large = 2 ** 130
check("arbitrary precision endpoints", merge([(large, large + 2), (large + 2, large + 3)]) == [(large, large + 3)])
try:
    merge([(1, 4), (3, 2)])
except ValueError:
    check("reversed interval rejected", True)
else:
    check("reversed interval rejected", False)
rng = random.Random(741)
for _ in range(200):
    original = [tuple(sorted((rng.randrange(-10, 11), rng.randrange(-10, 11)))) for _ in range(rng.randrange(12))]
    values = original.copy()
    result = merge(values)
    covered = {x for start, end in original for x in range(start, end)}
    actual = {x for start, end in result for x in range(start, end)}
    assert actual == covered, (original, result)
    assert all(start < end for start, end in result), result
    assert all(left[1] < right[0] for left, right in zip(result, result[1:])), result
    assert values == original, (values, original)
    assert merge(result.copy()) == result, result
check("200 independent coverage, nonmutation and canonical-form checks", True)
print(json.dumps({"checks": checks, "manual_review": ["Review whether tests expose the original defects and whether the change stays scoped."]}, indent=2))
sys.exit(not all(c["passed"] for c in checks))
