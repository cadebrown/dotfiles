"""Exercise the shared edit guard against real, isolated chezmoi state."""

import json
import os
import shutil
import statistics
import subprocess
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GUARD = ROOT / "home/dot_local/bin/executable_df-chezmoi-guard"
CHEZMOI = shutil.which("chezmoi")
assert CHEZMOI, "chezmoi must be installed for ownership validation"


with tempfile.TemporaryDirectory(prefix="guard-test-") as temporary:
    root = Path(temporary).resolve()
    destination = root / "home"
    source = root / "source"
    binary = root / "bin"
    for directory in (destination, source, binary):
        directory.mkdir()
    log = root / "chezmoi-calls"
    wrapper = binary / "chezmoi"
    wrapper.write_text(
        '#!/bin/bash\nprintf "%s\\n" "$*" >> "$GUARD_CALL_LOG"\n'
        'exec "$GUARD_REAL_CHEZMOI" --config /dev/null --config-format toml --source "$GUARD_SOURCE" '
        '--destination "$HOME" "$@"\n'
    )
    wrapper.chmod(0o755)
    environment = {
        **os.environ, "HOME": str(destination), "GUARD_SOURCE": str(source),
        "GUARD_REAL_CHEZMOI": CHEZMOI, "GUARD_CALL_LOG": str(log),
        "PATH": str(binary) + os.pathsep + os.environ["PATH"],
    }
    (source / "dot_managed").write_text("managed\n")
    (destination / ".managed").write_text("managed\n")
    (source / "dot_nested").mkdir()
    (source / "dot_nested" / "missing").mkdir()
    (source / "dot_nested" / "missing" / "file").write_text("not deployed\n")
    (source / "dot_space name").write_text("space\n")
    (source / "dot_line\nbreak").write_text("newline\n")
    (source / "dot_trailing\n").write_text("trailing newline\n")
    (source / "symlink_dot_link").write_text(str(root / "outside"))
    (destination / ".link").symlink_to(root / "outside")
    (root / "alias").symlink_to(destination, target_is_directory=True)
    (root / "file-alias").symlink_to(destination / ".managed")
    (root / "relative-alias").symlink_to("home/.managed")
    (root / "loop-a").symlink_to("loop-b")
    (root / "loop-b").symlink_to("loop-a")
    (destination / "subdir").mkdir()

    checks = 0

    def check(tool_input, blocked, *, cwd=destination, env=environment, calls=1):
        global checks
        log.write_text("")
        result = subprocess.run(
            ["/bin/bash", str(GUARD)], input=json.dumps({"cwd": str(cwd), "tool_input": tool_input}),
            text=True, capture_output=True, env=env, timeout=5, check=False,
        )
        assert result.returncode == (2 if blocked else 0), (tool_input, result)
        assert not result.stdout, result
        if blocked:
            assert "Edit the source:" in result.stderr, result
        else:
            assert not result.stderr, result
        assert len(log.read_text().splitlines()) == calls, log.read_text()
        checks += 1
        return result

    for key in ("file_path", "filePath", "path"):
        check({key: "~/.managed"}, True)
    for target in (
        ".managed", "subdir/../.managed", root / "alias" / ".managed",
        root / "file-alias", root / "relative-alias", ".nested/missing/file",
        ".nested/missing/../missing/file", ".space name", ".line\nbreak", ".link",
        ".trailing\n", "~",
    ):
        check({"file_path": str(target)}, True)
    check({"file_path": str(source / "dot_managed")}, False)
    check({"file_path": "unmanaged"}, False)
    check({"file_path": str(root / "loop-a")}, False)
    for verb in ("Add", "Update", "Delete"):
        check({"command": f"*** Begin Patch\n*** {verb} File: ~/.managed\n*** End Patch"}, True)
    check({"command": "*** Update File: harmless\n*** Move to: ~/.managed"}, True)
    check({"command": "*** Update File: ~/.managed\n*** Move to: harmless"}, True)
    check({"command": "*** Update File: harmless\n*** Update File: ~/.managed"}, True)
    check({"command": "*** Update File: ~/.managed\n*** Update File: ~/.managed"}, True)
    # Keep the configured HOME/destination lexical: resolving this alias in the
    # fixture would hide the ownership-map vs physical-candidate mismatch.
    alias_environment = {**environment, "HOME": str(root / "alias")}
    for target in ("~/.managed", ".managed", str(destination / ".managed"),
                   str(root / "file-alias"), "~/.link", "~/.nested/missing/file", "~"):
        check({"file_path": target}, True, env=alias_environment, cwd=root / "alias")
    check({"file_path": "unmanaged"}, False, env=alias_environment, cwd=root / "alias")
    # No tool file means no ownership query, including irrelevant command tools.
    check({}, False, calls=0)
    check({"command": "echo hello"}, False, calls=0)
    # Ownership is re-read on every invocation; no stale allow result survives.
    check({"file_path": ".newly-managed"}, False)
    (source / "dot_newly-managed").write_text("new source\n")
    check({"file_path": ".newly-managed"}, True)
    # Preserve the existing optional-dependency/failing-chezmoi behavior.
    absent = root / "absent-bin"
    absent.mkdir()
    check({"file_path": ".managed"}, False, env={**environment, "PATH": str(absent)}, calls=0)
    (absent / "jq").symlink_to(shutil.which("jq"))
    check({"file_path": ".managed"}, False, env={**environment, "PATH": str(absent)}, calls=0)
    failing = absent / "chezmoi"
    failing.write_text("#!/bin/bash\nexit 1\n")
    failing.chmod(0o755)
    check({"file_path": ".managed"}, False, env={**environment, "PATH": str(absent)}, calls=0)

    # Large mixed patches must block even if an unmanaged file appears first;
    # one fresh ownership query serves every candidate.
    for count in (1, 10, 50):
        command = "\n".join(f"*** Update File: untracked-{i}" for i in range(count - 1))
        command += "\n*** Update File: ~/.managed"
        timings = []
        for _ in range(7):
            start = time.perf_counter()
            check({"command": command}, True)
            timings.append((time.perf_counter() - start) * 1000)
        print(f"guard {count} file(s): median {statistics.median(timings):.1f} ms; one chezmoi query")
    print(f"Passed {checks} real-chezmoi guard checks")
