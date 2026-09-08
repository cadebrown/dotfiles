# /// script
# requires-python = ">=3.9"
# dependencies = []
# ///
"""Isolated warm hook benchmark: uv run tests/cursor-hook-benchmark.py --baseline REV.

Extension inventory is disabled in both runs. The fake chezmoi copies the actual
managed fixture files; no live settings or package manifests are modified.
"""
import argparse
import json
import os
from pathlib import Path
import shlex
import shutil
import statistics
import subprocess
import sys
import tempfile
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", required=True, help="Git revision of the old shell hook")
    parser.add_argument("--repetitions", type=int, default=20)
    args = parser.parse_args()
    if args.repetitions < 1:
        parser.error("repetitions must be positive")
    repo = Path(__file__).resolve().parent.parent
    relative = "home/dot_cursor/hooks/executable_sync-dotfiles-cursor.sh.tmpl"
    old = subprocess.check_output(["git", "-C", str(repo), "show", f"{args.baseline}:{relative}"], text=True)
    new = (repo / relative).read_text()
    with tempfile.TemporaryDirectory(prefix="cursor-perf-") as temporary:
        base = Path(temporary)
        home, root, binaries = base / "home", base / "repo with spaces", base / "bin"
        for directory in (home / ".config/cursor", root / "home/dot_config/cursor", binaries):
            directory.mkdir(parents=True)
        for filename in ("settings.json", "keybindings.json"):
            shutil.copy(repo / "home/dot_config/cursor" / filename, home / ".config/cursor" / filename)
        mock = binaries / "chezmoi"
        mock.write_text('#!/bin/bash\ncp "$2" "$DF_ROOT/home/dot_config/cursor/${2##*/}"\n')
        mock.chmod(0o755)
        (binaries / "python3").symlink_to(sys.executable)
        shutil.copy(repo / "home/dot_cursor/hooks/sync_dotfiles_cursor.py", base)
        env = dict(os.environ, HOME=str(home), DF_ROOT=str(root), TMPDIR=temporary,
                   XDG_CACHE_HOME=str(home / ".cache"), DF_CURSOR_HOOK_SYNC_EXTENSIONS="0",
                   DF_CURSOR_HOOK_DEBOUNCE_SECS="0", PATH=str(binaries) + ":" + os.environ["PATH"])
        results = {"baseline": args.baseline, "repetitions": args.repetitions,
                   "fixture": "Copied managed settings, mock chezmoi file copy; extensions disabled in both runs."}
        for name, script in (("before", old), ("after", new)):
            # Old hooks prepend Homebrew, overriding PATH mocks; direct only
            # their import command into the fixture without changing other work.
            script = script.replace("{{ .chezmoi.workingTree }}", str(root))
            script = script.replace('chezmoi add "$f"', shlex.quote(str(mock)) + ' add "$f"')
            target = base / (name + ".sh")
            target.write_text(script)
            command = ["/bin/bash", str(target), "--before-submit"]
            for _ in range(2):
                subprocess.run(command, env=env, check=True, capture_output=True)
            samples = []
            for _ in range(args.repetitions):
                start = time.perf_counter()
                subprocess.run(command, env=env, check=True, capture_output=True)
                samples.append((time.perf_counter() - start) * 1000)
            results[name] = {"median_ms": round(statistics.median(samples), 2),
                             "min_ms": round(min(samples), 2), "max_ms": round(max(samples), 2)}
        print(json.dumps(results, indent=2))


if __name__ == "__main__":
    main()
