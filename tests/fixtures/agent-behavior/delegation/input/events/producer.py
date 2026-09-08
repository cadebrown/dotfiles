"""Create the payload sent to the job event consumer."""

LEGACY_LABEL = "task_id"


def make_event(task_id, occurred_at, description):
    return {
        "task_id": task_id,
        "occurred_at": occurred_at.isoformat(),
        "description": description,
    }
