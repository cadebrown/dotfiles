"""Private, host-scoped metadata for native Codex sessions; never a task runner."""

import argparse
import fcntl
import hashlib
import json
import os
import re
import shlex
import socket
import stat
import subprocess
import sys
import tempfile
import time
from contextlib import contextmanager
from datetime import UTC, datetime
from pathlib import Path

EVENTS = {"SessionStart", "UserPromptSubmit", "PreCompact", "Stop", "Interrupt", "SessionEnd"}


def timestamp():
    return datetime.now(UTC).isoformat(timespec="milliseconds")


def state_root():
    machine = Path("/etc/machine-id")
    identity = machine.read_text().strip() if machine.is_file() else socket.gethostname()
    host = hashlib.sha256(identity.encode()).hexdigest()[:16]
    base = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state"))
    return Path(os.environ.get("DF_TASK_STATE_DIR", base / "dotfiles/tasks" / host))


def private_directory(path):
    path.mkdir(parents=True, exist_ok=True, mode=0o700)
    metadata = path.lstat()
    if not stat.S_ISDIR(metadata.st_mode) or metadata.st_uid != os.getuid():
        raise ValueError("task state must be an owned directory, not a symlink")
    path.chmod(0o700)


def session_path(session):
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]{0,127}", session):
        raise ValueError("invalid native session ID")
    return state_root() / (session + ".json")


def read_record(path):
    if not path.exists():
        return None
    metadata = path.lstat()
    if not stat.S_ISREG(metadata.st_mode) or metadata.st_uid != os.getuid():
        raise ValueError("task record must be an owned regular file")
    if metadata.st_size > 262144:
        raise ValueError("task record exceeds 256 KiB")
    data = json.loads(path.read_text())
    if not isinstance(data, dict) or data.get("version") != 1:
        raise ValueError("unsupported task record")
    return data


@contextmanager
def transaction(session, create=True):
    path = session_path(session)
    if not create and not path.exists():
        yield None
        return
    private_directory(path.parent)
    descriptor = os.open(path.with_suffix(".lock"), os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    try:
        if os.fstat(descriptor).st_uid != os.getuid():
            raise ValueError("task lock belongs to another user")
        deadline = time.monotonic() + 0.2
        while True:
            try:
                fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.monotonic() >= deadline:
                    raise TimeoutError("task checkpoint is busy; retry the command")
                time.sleep(0.005)
        record = read_record(path)
        if record is None:
            if not create:
                yield None
                return
            record = {
                "version": 1, "session_id": session, "created_at": timestamp(),
                "jobs": {}, "artifacts": [], "logs": [], "events": [],
            }
        yield record
        record["updated_at"] = timestamp()
        serialized = json.dumps(record, indent=2) + "\n"
        if len(serialized.encode()) > 262144:
            raise ValueError("task record exceeds 256 KiB")
        with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, prefix=".checkpoint-", delete=False) as output:
            temporary = Path(output.name)
            try:
                output.write(serialized)
                output.flush()
                os.fsync(output.fileno())
                os.replace(temporary, path)
            finally:
                temporary.unlink(missing_ok=True)
    finally:
        os.close(descriptor)


def repository(cwd):
    try:
        result = subprocess.run(
            ["git", "-C", cwd, "rev-parse", "--show-toplevel", "--git-common-dir"],
            capture_output=True, text=True, timeout=0.5, check=False,
        )
        lines = result.stdout.splitlines()
        if result.returncode == 0 and len(lines) == 2:
            common = Path(lines[1])
            return {"worktree": lines[0], "git_common_dir": str(common if common.is_absolute() else Path(cwd) / common)}
    except (OSError, subprocess.TimeoutExpired):
        return {}
    return {}


def hook(payload):
    event = payload.get("hook_event_name")
    if event not in EVENTS:
        return
    session = payload.get("session_id", "")
    cwd = payload.get("cwd")
    if not isinstance(cwd, str) or not Path(cwd).is_absolute():
        raise ValueError("hook requires an absolute cwd")
    details = repository(cwd) if event == "SessionStart" else {}
    with transaction(session, create=event != "SessionEnd") as record:
        if record is None:
            return
        record.update(details)
        record["cwd"] = cwd
        entry = {"event": event, "at": timestamp()}
        for field in ("turn_id", "source", "model"):
            value = payload.get(field)
            if isinstance(value, str):
                entry[field] = value[:256]
                record[field] = value[:256]
        record["events"] = (record["events"] + [entry])[-32:]
        if event == "SessionStart":
            if payload.get("source") != "compact":
                record["observed_state"] = "session-opened"
        elif event == "UserPromptSubmit":
            record["observed_state"] = "prompt-submitted"
        elif event == "Interrupt":
            record["observed_state"] = "interrupted"
            record["last_interrupt"] = entry
        elif event == "Stop":
            if record.get("last_interrupt", {}).get("turn_id") != payload.get("turn_id") or not payload.get("turn_id"):
                record["observed_state"] = "turn-stopped"
        elif event == "SessionEnd" and record.get("observed_state") != "interrupted":
            record["observed_state"] = "session-ended"


def absolute_path(value, cwd):
    path = Path(value).expanduser()
    return str(path.absolute() if path.is_absolute() else (Path(cwd) / path).absolute())


def process_identity(pid):
    try:
        result = subprocess.run(["ps", "-p", str(pid), "-o", "uid=", "-o", "lstart="],
                                capture_output=True, text=True, timeout=0.5, check=False, env={**os.environ, "LC_ALL": "C"})
    except (OSError, subprocess.TimeoutExpired):
        return None
    parts = result.stdout.split(None, 1)
    return parts[1].strip() if result.returncode == 0 and len(parts) == 2 and parts[0] == str(os.getuid()) else None


def checkpoint(args):
    details = repository(str(Path.cwd()))
    with transaction(args.session) as record:
        record.setdefault("cwd", str(Path.cwd()))
        if record["cwd"] == str(Path.cwd()):
            record.update(details)
        for field in ("title", "note", "next"):
            value = getattr(args, field, None)
            if value is not None:
                if len(value) > 4096:
                    raise ValueError(f"{field} exceeds 4096 characters")
                record[field] = value
        for field in ("artifacts", "logs"):
            for value in getattr(args, field):
                path = absolute_path(value, str(Path.cwd()))
                if path not in record[field]:
                    record[field].append(path)
            if len(record[field]) > 128:
                raise ValueError(f"at most 128 {field} per session")
    print(session_path(args.session))


def track_job(args):
    if not 1 <= len(args.name) <= 128:
        raise ValueError("job name must be 1 to 128 characters")
    identity = process_identity(args.pid) if args.pid else None
    if args.pid and not identity:
        raise ValueError("PID is not a live process owned by the current user")
    if not args.pid and not args.handle:
        raise ValueError("provide --pid or --handle for an existing job")
    with transaction(args.session) as record:
        record.setdefault("cwd", str(Path.cwd()))
        record["jobs"][args.name] = {"pid": args.pid, "identity": identity, "handle": args.handle,
                                    "log": absolute_path(args.log, str(Path.cwd())) if args.log else None,
                                    "registered_at": timestamp()}
        if len(record["jobs"]) > 64:
            raise ValueError("at most 64 jobs per session")
    print(session_path(args.session))


def inspect_record(session):
    record = read_record(session_path(session))
    if record is None:
        raise ValueError("no checkpoint for that session")
    for job in record["jobs"].values():
        job["process_state"] = "unverified-handle"
        if job.get("pid"):
            job["process_state"] = "running" if process_identity(job["pid"]) == job["identity"] else "exited-or-replaced"
    record["resume_command"] = shlex.join(["codex", "--cd", record["cwd"], "resume", session])
    return record


def main():
    parser = argparse.ArgumentParser(prog="df-task", description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("hook", help="record native lifecycle metadata for Codex hooks")
    commands.add_parser("list", help="show the 20 most recently checkpointed sessions")
    for command in ("start", "checkpoint", "job", "status", "resume"):
        sub = commands.add_parser(command)
        sub.add_argument("--session", default=os.environ.get("CODEX_THREAD_ID"), help="native session ID; defaults to CODEX_THREAD_ID")
        if command in ("start", "checkpoint"):
            sub.add_argument("--title")
            sub.add_argument("--note")
            sub.add_argument("--next")
            sub.add_argument("--artifact", dest="artifacts", action="append", default=[])
            sub.add_argument("--log", dest="logs", action="append", default=[])
        if command == "job":
            sub.add_argument("name")
            sub.add_argument("--pid", type=int)
            sub.add_argument("--handle", help="existing native exec/tmux job handle; never launched by df-task")
            sub.add_argument("--log")
        if command == "resume":
            sub.add_argument("--launch", action="store_true", help="open native interactive resume; does not submit a prompt or restart jobs")
    args = parser.parse_args()
    try:
        if args.command == "hook":
            payload = sys.stdin.read(1048577)
            if len(payload) > 1048576:
                raise ValueError("hook payload exceeds 1 MiB")
            payload = json.loads(payload)
            if not isinstance(payload, dict):
                raise ValueError("hook requires a JSON object")
            hook(payload)
            print("{}")
        elif args.command == "list":
            paths = sorted(state_root().glob("*.json"), key=lambda path: path.stat().st_mtime, reverse=True)[:20]
            records = [read_record(path) for path in paths]
            print(json.dumps([{key: record.get(key) for key in ("session_id", "title", "cwd", "observed_state", "updated_at")} for record in records], indent=2))
        else:
            if not args.session:
                raise ValueError("pass --session with a native Codex session ID")
            if args.command in ("start", "checkpoint"):
                checkpoint(args)
            elif args.command == "job":
                track_job(args)
            else:
                record = inspect_record(args.session)
                if args.command == "resume" and args.launch:
                    if not Path(record["cwd"]).is_dir():
                        raise ValueError("saved working directory is missing; restore it before resuming")
                    os.chdir(record["cwd"])
                    os.execvp("codex", ["codex", "--cd", record["cwd"], "resume", args.session])
                print(json.dumps(record, indent=2))
    except (OSError, ValueError, TypeError, TimeoutError) as error:
        print(f"df-task: {error}", file=sys.stderr)
        if args.command == "hook":
            print("{}")
            return 0
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
