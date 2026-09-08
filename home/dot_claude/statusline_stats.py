"""Incrementally reduce append-only Claude JSONL transcripts (stdlib only).

The cache is disposable. Atomic replacement permits concurrent refreshes without
locks: a slower writer may publish an older offset, which the next reader catches
up. File identity, timestamps, and bounded prefix/offset fingerprints invalidate
replacement, truncation, and ordinary in-place rewrites. Arbitrary edits in the
middle of an append-only transcript are outside this cache's contract.
"""

import copy
import datetime
import hashlib
import json
import os
from pathlib import Path
import sys
import tempfile

VERSION = 1
FIELDS = ("input_tokens", "output_tokens", "cache_read_input_tokens")


def initial():
    return {"turns": 0, "ctx": 0, "totals": [0] * 5, "tools": 0,
            "first": 0, "last": 0, "usage": [0] * 5}


def timestamp(value):
    try:
        return int(datetime.datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp())
    except (ValueError, AttributeError):
        return 0


def add(stats, record):
    if record.get("type") != "assistant":
        return
    message = record.get("message") or {}
    usage = message.get("usage") or {}
    creation = usage.get("cache_creation") or {}
    values = [usage.get(key) or 0 for key in FIELDS] + [
        creation.get("ephemeral_5m_input_tokens") or 0,
        creation.get("ephemeral_1h_input_tokens") or 0]
    moment = timestamp(record.get("timestamp", ""))
    if not stats["turns"]:
        stats["first"] = moment
    stats["turns"] += 1
    stats["last"] = moment
    stats["usage"] = values
    stats["ctx"] = sum(values[:3]) + (usage.get("cache_creation_input_tokens") or 0)
    stats["totals"] = [a + b for a, b in zip(stats["totals"], values)]
    stats["tools"] += sum(block.get("type") == "tool_use"
                          for block in (message.get("content") or []))


def fingerprint(stream, offset):
    # Both ranges remain fixed when the transcript grows.
    stream.seek(0)
    prefix = stream.read(min(offset, 4096))
    stream.seek(max(0, offset - 4096))
    suffix = stream.read(min(offset, 4096))
    return hashlib.sha256(prefix + suffix).hexdigest()


def cache_path(transcript, directory):
    key = hashlib.sha256(os.fsencode(os.path.abspath(transcript))).hexdigest()
    return Path(directory) / (key + ".json")


def validate(state):
    stats = state["stats"]
    return (state["version"] == VERSION and isinstance(state["offset"], int)
            and state["offset"] >= 0
            and all(isinstance(stats[k], int) for k in
                    ("turns", "ctx", "tools", "first", "last"))
            and all(isinstance(stats[k], list) and len(stats[k]) == 5
                    and all(isinstance(v, int) for v in stats[k])
                    for k in ("totals", "usage")))


def reduce(transcript, directory):
    cache = cache_path(transcript, directory)
    state = None
    try:
        state = json.loads(cache.read_text())
        if not validate(state):
            state = None
    except (OSError, ValueError, KeyError, TypeError):
        state = None
    with open(transcript, "rb") as stream:
        meta = os.fstat(stream.fileno())
        identity = [meta.st_dev, meta.st_ino]
        if state is not None:
            try:
                valid = (state["identity"] == identity and meta.st_size >= state["size"]
                         and (meta.st_size != state["size"] or
                              [meta.st_mtime_ns, meta.st_ctime_ns] == state["times"])
                         and fingerprint(stream, state["offset"]) == state["fingerprint"])
            except (KeyError, TypeError):
                valid = False
            if not valid:
                state = None
        stats = state["stats"] if state else initial()
        offset = state["offset"] if state else 0
        stream.seek(offset)
        # Bound this refresh to the size observed above, even if a writer appends.
        remaining = meta.st_size - offset
        pending = b""
        while remaining:
            line = stream.readline(remaining)
            if not line:
                break
            remaining -= len(line)
            if not line.endswith(b"\n"):
                pending = line
                break
            if line.strip():
                add(stats, json.loads(line))
            offset += len(line)
        result = copy.deepcopy(stats)
        if pending.strip():
            try:
                add(result, json.loads(pending))
            except (ValueError, UnicodeError):
                # A writer has not finished the last record yet. Never checkpoint it.
                pass
        updated = {"version": VERSION, "identity": identity, "size": meta.st_size,
                   "times": [meta.st_mtime_ns, meta.st_ctime_ns], "offset": offset,
                   "fingerprint": fingerprint(stream, offset), "stats": stats}
    if updated != state:
        temporary = None
        try:
            cache.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
            with tempfile.NamedTemporaryFile(mode="w", dir=cache.parent, delete=False) as out:
                temporary = out.name
                json.dump(updated, out, separators=(",", ":"))
            os.replace(temporary, cache)
        except OSError:
            # An unwritable cache only affects performance, never the result.
            pass
        finally:
            if temporary and os.path.exists(temporary):
                os.unlink(temporary)
    age = result["last"] - result["first"] if result["last"] > 0 and result["first"] > 0 else 0
    return [result["turns"], result["ctx"], *result["totals"], age,
            result["tools"], *result["usage"]]


if __name__ == "__main__":
    try:
        directory = os.environ.get("STATUSLINE_STATS_CACHE_DIR") or str(
            Path(os.environ.get("XDG_CACHE_HOME", str(Path.home() / ".cache"))) / "claude-statusline")
        print(*reduce(sys.argv[1], directory))
    except (OSError, ValueError, TypeError, AttributeError):
        # Statusline segments are independent; invalid transcripts omit stats.
        sys.exit(1)
