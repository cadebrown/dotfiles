"""Small public starting check; the external verifier exercises broader inputs."""

from datetime import datetime, timezone
from events.producer import LEGACY_LABEL, make_event
from events.consumer import count_by_job
from retry_queue import RetryQueue

event = make_event(job_id="alpha", occurred_at=datetime(2026, 1, 2, tzinfo=timezone.utc),
                   description="example task_id text must survive")
assert event["job_id"] == "alpha"
assert "task_id" not in event
assert LEGACY_LABEL == "task_id"
assert count_by_job([event, event]) == {"alpha": 2}

queue = RetryQueue()
assert [queue.failure("alpha") for _ in range(5)] == [2, 4, 8, 16, 30]
assert queue.failure("beta") == 2
queue.success("alpha")
assert queue.failure("alpha") == 2
assert queue.failure("beta") == 4
print("Public maintenance checks passed")
