#!/usr/bin/env python3
# /// script
# requires-python = ">=3.9"
# dependencies = []
# ///
"""Change-aware Cursor import; standard library only for the installed runtime."""

import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time


def warn(message):
    print(f"[df-cursor-hook] {message}", file=sys.stderr)


def describe_error(error):
    detail = getattr(error, "stderr", None)
    if isinstance(detail, bytes):
        detail = detail.decode(errors="replace")
    return str(error) + (": " + detail.strip()[:400] if detail else "")


def digest(data):
    return hashlib.sha256(data).hexdigest()


def atomic_write(destination, data, mode=0o600):
    destination.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=f".{destination.name}.", dir=destination.parent)
    try:
        with os.fdopen(fd, "wb") as stream:
            os.fchmod(stream.fileno(), mode)
            stream.write(data)
        os.replace(temporary, destination)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


# Strings are matched before comments/commas so URLs and quoted punctuation survive.
JSONC_COMMENTS = re.compile(r'("(?:\\.|[^"\\])*")|//[^\r\n]*|/\*[\s\S]*?\*/')
JSONC_COMMAS = re.compile(r'("(?:\\.|[^"\\])*")|,\s*(?=[}\]])')


def parse_jsonc(data, expected_type):
    text = data.decode("utf-8-sig")
    text = JSONC_COMMENTS.sub(lambda m: m.group(1) or " ", text)
    text = JSONC_COMMAS.sub(lambda m: m.group(1) or "", text)

    def invalid_constant(value):
        raise ValueError(f"invalid JSON constant {value}")

    parsed = json.loads(text, parse_constant=invalid_constant)
    if not isinstance(parsed, expected_type):
        raise ValueError(f"expected {expected_type.__name__}")
    return parsed


def read_optional(location):
    try:
        return location.read_bytes()
    except FileNotFoundError:
        return None


def sync_file(live, source, previous):
    data = read_optional(live)
    if data is None:
        return None
    old_source = read_optional(source)
    fingerprint = {"live": digest(data), "source": digest(old_source) if old_source is not None else None}
    if previous == fingerprint:
        return previous

    expected = dict if live.name == "settings.json" else list
    parsed = parse_jsonc(data, expected)
    source_mode = source.stat().st_mode & 0o777 if old_source is not None else 0o644
    try:
        subprocess.run(["chezmoi", "add", str(live)], check=True, capture_output=True, timeout=5)
        imported = source.read_bytes()
        # Cursor may truncate/rewrite between validation and chezmoi's read.
        # Never certify a snapshot different from the one we validated.
        if imported != data or live.read_bytes() != data:
            raise ValueError("settings changed during import; retrying on the next event")
        parse_jsonc(imported, expected)
        if expected is dict and "remote.SSH.remotePlatform" in parsed:
            parsed.pop("remote.SSH.remotePlatform", None)
            imported = (json.dumps(parsed, indent=2, ensure_ascii=False) + "\n").encode()
            if imported != source.read_bytes():
                atomic_write(source, imported, source_mode)
        return {"live": digest(data), "source": digest(imported)}
    except BaseException:
        if old_source is None:
            source.unlink(missing_ok=True)
        else:
            atomic_write(source, old_source, source_mode)
        raise


def run_locked(root, state_dir):
    cache_path = state_dir / "fingerprints.json"
    try:
        state = json.loads(cache_path.read_text())
        if not isinstance(state, dict):
            raise ValueError("expected an object")
    except FileNotFoundError:
        state = {}
    except (ValueError, OSError) as error:
        warn(f"rebuilding unreadable fingerprint cache: {error}")
        state = {}
    updated = dict(state)
    for filename in ("settings.json", "keybindings.json"):
        try:
            result = sync_file(
                Path.home() / ".config/cursor" / filename,
                root / "home/dot_config/cursor" / filename,
                state.get(filename),
            )
            if result is None:
                updated.pop(filename, None)
            else:
                updated[filename] = result
        except (OSError, ValueError, subprocess.SubprocessError) as error:
            updated.pop(filename, None)
            warn(f"could not sync {filename}: {describe_error(error)}; will retry on the next event")
    if updated != state:
        atomic_write(cache_path, (json.dumps(updated) + "\n").encode())


def sync_extensions(root, state_dir):
    # Do not hold the settings lock during CLI startup: a concurrent prompt must
    # still be able to check/import settings while session-end inventory runs.
    if not ({"--session-end", "--sync-extensions"} & set(sys.argv)):
        return
    if os.environ.get("DF_CURSOR_HOOK_SYNC_EXTENSIONS", "1") != "1":
        return
    with (state_dir / "extensions.lock").open("a") as lock:
        os.chmod(state_dir / "extensions.lock", 0o600)
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            warn("extension sync already running in another session")
            return
        try:
            subprocess.run(["bash", str(root / "install/cursor.sh"), "sync-extensions"],
                           check=True, capture_output=True, timeout=15)
        except (OSError, subprocess.SubprocessError) as error:
            warn(f"extension sync failed: {describe_error(error)}; retry with install/cursor.sh sync-extensions")


def main():
    root = Path(os.environ["DF_ROOT"]).resolve()
    # Hashes only, never duplicate settings content (which may contain secrets).
    cache_root = Path(os.environ.get("XDG_CACHE_HOME", str(Path.home() / ".cache")))
    identity = digest((str(root) + "\0" + str(Path.home())).encode())[:24]
    state_dir = cache_root / "dotfiles/cursor-hook" / identity
    state_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.chmod(state_dir, 0o700)
    with (state_dir / "sync.lock").open("a") as lock:
        os.chmod(state_dir / "sync.lock", 0o600)
        deadline = time.monotonic() + 2
        while True:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.monotonic() >= deadline:
                    warn("another sync is busy; retrying settings on the next event")
                    return
                time.sleep(0.02)
        run_locked(root, state_dir)
    sync_extensions(root, state_dir)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError) as error:
        warn(f"sync unavailable: {error}; will retry on the next event")
    finally:
        print('{"continue":true}' if "--before-submit" in sys.argv else '{}')
