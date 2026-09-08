"""Aggregate received event payloads without changing them."""


def count_by_job(events):
    counts = {}
    for event in events:
        task_id = event["task_id"]
        counts[task_id] = counts.get(task_id, 0) + 1
    return counts
