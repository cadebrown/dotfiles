"""Exercise observable maintenance contracts independently of model-written tests."""

from collections import Counter
import copy
from datetime import datetime, timedelta, timezone
import hashlib
import importlib.util
import json
from pathlib import Path
import random
import subprocess
import sys


FIXTURE = Path(__file__).parent
WORKSPACE = Path(sys.argv[1]).resolve()
CHECKS = []


def check(name, function):
    try:
        function()
        CHECKS.append({"name": name, "passed": True})
    except Exception as error:
        CHECKS.append({"name": name, "passed": False,
                       "detail": f"{type(error).__name__}: {error}"})


def load(name, relative):
    spec = importlib.util.spec_from_file_location(name, WORKSPACE / relative)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def preserved_inputs():
    expected = json.loads((FIXTURE / "preserved-inputs.json").read_text())
    for relative, sha256 in expected.items():
        assert hashlib.sha256((WORKSPACE / relative).read_bytes()).hexdigest() == sha256, relative


def log_summary():
    actual = json.loads((WORKSPACE / "output" / "log-summary.json").read_text())
    expected = json.loads((FIXTURE / "expected-log.json").read_text())
    assert actual == expected, "Summary differs from the generated event schedule"
    assert type(actual["total_lines"]) is int and type(actual["error_count"]) is int
    for group in actual["groups"]:
        assert all(type(group[key]) is int for key in ("count", "first_line", "last_line"))


def event_contract():
    producer = load("fixture_producer", "events/producer.py")
    consumer = load("fixture_consumer", "events/consumer.py")
    assert producer.LEGACY_LABEL == "task_id", "Historical label changed"
    randomizer = random.Random(941)
    for repetition in range(80):
        events = []
        ids = []
        for index in range(randomizer.randrange(0, 40)):
            identifier = randomizer.choice(["", "a b", "task_id", "job_id", "λ", str(index % 5)])
            stamp = datetime(2026, 1, 2, tzinfo=timezone(timedelta(hours=-4))) + timedelta(seconds=index)
            description = {"text": "literal task_id and job_id", "sequence": [repetition, index]}
            original = copy.deepcopy(description)
            event = producer.make_event(job_id=identifier, occurred_at=stamp, description=description)
            assert event == {"job_id": identifier, "occurred_at": stamp.isoformat(), "description": original}
            assert description == original, "Producer mutated description"
            events.append(event)
            ids.append(identifier)
        before = copy.deepcopy(events)
        assert consumer.count_by_job(events) == dict(Counter(ids)), "Incorrect event counts"
        assert events == before, "Consumer mutated input"
    try:
        producer.make_event(task_id="old-key", occurred_at=datetime.now(), description="legacy")
    except TypeError:
        pass
    else:
        raise AssertionError("Legacy producer keyword still accepted")
    try:
        consumer.count_by_job([{"task_id": "old-key"}])
    except KeyError:
        pass
    else:
        raise AssertionError("Legacy consumer payload still accepted")


def retry_contract():
    queue_type = load("fixture_retry_queue", "retry_queue.py").RetryQueue
    default = queue_type()
    assert [default.failure("default") for _ in range(7)] == [2, 4, 8, 16, 30, 30, 30]
    invalid = [(0, 30), (-1, 30), (2, 0), (3, 2), (True, 30), (2, True), (2.0, 30), (2, 30.0), ("2", 30)]
    for base, cap in invalid:
        try:
            queue_type(base_delay=base, max_delay=cap)
        except ValueError:
            pass
        else:
            raise AssertionError(f"Invalid constructor accepted: {(base, cap)!r}")
    randomizer = random.Random(7211)
    for base, cap in [(1, 1), (1, 3), (2, 30), (7, 51), (10, 10)]:
        queues = [queue_type(base_delay=base, max_delay=cap) for _ in range(2)]
        failures = [Counter(), Counter()]
        for _ in range(350):
            number = randomizer.randrange(2)
            key = randomizer.choice(["a", "b", "", "has spaces", "λ"])
            if randomizer.randrange(4) == 0:
                queues[number].success(key)
                failures[number][key] = 0
            else:
                occurrence = failures[number][key]
                expected = min(cap, base * 2 ** occurrence)
                assert queues[number].failure(key) == expected, (base, cap, number, key, occurrence)
                failures[number][key] += 1
        capped = queue_type(base_delay=base, max_delay=cap)
        for index in range(2048):
            actual = capped.failure("persistent")
            if index >= 10:
                assert actual == cap, "Repeated failure did not remain capped"


def public_check():
    result = subprocess.run([sys.executable, str(WORKSPACE / "check.py")], cwd=WORKSPACE,
                            capture_output=True, text=True, timeout=20)
    assert result.returncode == 0, result.stdout + result.stderr


for label, function in [("preserved source inputs", preserved_inputs),
                        ("exact log summary and evidence", log_summary),
                        ("event field migration on generated payloads", event_contract),
                        ("independent capped retry state", retry_contract),
                        ("unchanged public starting check", public_check)]:
    check(label, function)
print(json.dumps({"checks": CHECKS, "manual_review": [
    "Inspect raw events/native child sessions for actual delegation, model, effort, tools, and compact handoffs.",
    "Review retry state to ensure capped failures do not create ever-growing integers.",
    "Parent usage alone may exclude child usage; do not claim total savings from it.",
    "This fixture uses local synthetic logs; it does not measure live web scraping or general model quality."
]}, indent=2))
sys.exit(0 if all(item["passed"] for item in CHECKS) else 1)
