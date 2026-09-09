import concurrent.futures
import importlib.util
import json
import os
import stat
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path
from unittest.mock import patch

SCRIPT = Path(__file__).parents[1] / "home/dot_local/lib/dotfiles/df_task.py"
SPEC = importlib.util.spec_from_file_location("df_task", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class DurableTaskTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name).resolve()
        self.state = self.root / "state"
        self.workspace = self.root / "project with spaces"
        self.workspace.mkdir()
        self.environment = {**os.environ, "DF_TASK_STATE_DIR": str(self.state), "CODEX_THREAD_ID": "session-123"}
        self.environment_patch = patch.dict(os.environ, self.environment)
        self.environment_patch.start()

    def tearDown(self):
        self.environment_patch.stop()
        self.temporary.cleanup()

    def command(self, *args, payload=None, expected=0, environment=None, retry_busy=False):
        deadline = time.monotonic() + 5
        while True:
            result = subprocess.run([sys.executable, str(SCRIPT), *args], cwd=self.workspace,
                                    env=environment or self.environment, input=json.dumps(payload) if payload is not None else None,
                                    capture_output=True, text=True, timeout=5, check=False)
            if (retry_busy and result.returncode == 1
                    and result.stderr.strip() == "df-task: task checkpoint is busy; retry the command"
                    and time.monotonic() < deadline):
                time.sleep(0.01)
                continue
            break
        self.assertEqual(result.returncode, expected, result.stderr)
        return result

    def event(self, event, **fields):
        result = self.command("hook", payload={"hook_event_name": event, "session_id": "session-123",
                                              "cwd": str(self.workspace), "turn_id": "turn-1", **fields})
        self.assertEqual(json.loads(result.stdout), {})
        self.assertEqual(result.stderr, "")

    def record(self):
        return json.loads(self.command("status").stdout)

    def test_interrupt_compact_and_resume_preserve_handoff_without_restarting(self):
        self.event("SessionStart", source="startup", model="gpt-6-astra")
        self.command("start", "--title", "Complete the export")
        self.command("checkpoint", "--note", "Scene saved", "--next", "Inspect output", "--artifact", "render.png", "--log", "build.log")
        self.event("UserPromptSubmit", prompt="must not be copied", transcript_path="/private/native-memory")
        self.event("Interrupt")
        self.event("PreCompact")
        self.event("SessionStart", source="compact")
        self.event("Stop")
        self.event("SessionEnd")
        result = self.record()
        self.assertEqual(result["observed_state"], "interrupted")
        self.assertEqual(result["next"], "Inspect output")
        self.assertEqual(result["artifacts"], [str(self.workspace / "render.png")])
        self.assertNotIn("must not be copied", json.dumps(result))
        self.assertNotIn("native-memory", json.dumps(result))
        before = (self.state / "session-123.json").read_bytes()
        resumed = json.loads(self.command("resume").stdout)
        self.assertEqual(resumed["observed_state"], "interrupted")
        self.assertEqual((self.state / "session-123.json").read_bytes(), before)
        self.event("SessionStart", source="resume")
        self.assertEqual(self.record()["observed_state"], "session-opened")
        self.event("UserPromptSubmit", turn_id="turn-2")
        self.event("Stop", turn_id="turn-2")
        self.assertEqual(self.record()["observed_state"], "turn-stopped")

    def test_native_resume_uses_saved_directory_and_no_continuation_prompt(self):
        self.event("SessionStart", source="startup")
        binary = self.root / "bin"
        binary.mkdir()
        capture = self.root / "resume.json"
        stub = binary / "codex"
        stub.write_text(f"#!{sys.executable}\nimport json, os, sys\nfrom pathlib import Path\nPath({str(capture)!r}).write_text(json.dumps([os.getcwd(), sys.argv[1:]]))\n")
        stub.chmod(0o755)
        self.command("resume", "--launch", environment={**self.environment, "PATH": str(binary) + os.pathsep + self.environment["PATH"]})
        self.assertEqual(json.loads(capture.read_text()), [str(self.workspace), ["--cd", str(self.workspace), "resume", "session-123"]])

    def test_native_job_identity_survives_interrupt_and_detects_exit_or_reuse(self):
        process = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(30)"])
        self.addCleanup(lambda: process.poll() is None and process.kill())
        self.command("job", "render", "--pid", str(process.pid), "--log", "render.log")
        self.command("job", "build", "--handle", "exec:517")
        self.event("Interrupt")
        result = self.record()
        self.assertEqual(result["jobs"]["render"]["process_state"], "running")
        self.assertEqual(result["jobs"]["build"]["process_state"], "unverified-handle")
        with MODULE.transaction("session-123") as record:
            record["jobs"]["render"]["identity"] = "a different process"
        self.assertEqual(self.record()["jobs"]["render"]["process_state"], "exited-or-replaced")
        self.assertIsNone(process.poll())
        process.terminate()
        process.wait(timeout=5)
        self.assertEqual(self.record()["jobs"]["render"]["process_state"], "exited-or-replaced")
        self.command("job", "exited", "--pid", str(process.pid), expected=1)

    def test_concurrent_checkpoints_keep_every_registered_artifact(self):
        def add_artifact(index):
            return self.command("checkpoint", "--artifact", f"result-{index}.txt", retry_busy=True)
        with concurrent.futures.ThreadPoolExecutor(max_workers=8) as executor:
            list(executor.map(add_artifact, range(16)))
        self.assertCountEqual(self.record()["artifacts"],
                              [str(self.workspace / f"result-{index}.txt") for index in range(16)])
        self.assertEqual(stat.S_IMODE(self.state.stat().st_mode), 0o700)
        self.assertEqual(stat.S_IMODE((self.state / "session-123.json").stat().st_mode), 0o600)

    def test_contended_cli_returns_busy_and_succeeds_after_lock_release(self):
        with MODULE.transaction("session-123"):
            result = self.command("checkpoint", "--artifact", "after-lock.txt", expected=1)
            self.assertEqual(result.stderr.strip(), "df-task: task checkpoint is busy; retry the command")
        self.command("checkpoint", "--artifact", "after-lock.txt")
        self.assertEqual(self.record()["artifacts"], [str(self.workspace / "after-lock.txt")])

    def test_failed_atomic_replace_preserves_previous_checkpoint(self):
        self.command("checkpoint", "--note", "last valid checkpoint")
        with (
            patch.object(MODULE.os, "replace", side_effect=OSError("simulated interrupted write")),
            self.assertRaises(OSError),
            MODULE.transaction("session-123") as record,
        ):
            record["note"] = "uncommitted change"
        self.assertEqual(self.record()["note"], "last valid checkpoint")
        self.assertEqual(list(self.state.glob(".checkpoint-*")), [])

    def test_state_and_pid_ownership_checks(self):
        target = self.root / "untouched.json"
        target.write_text("original")
        self.state.mkdir()
        (self.state / "session-123.json").symlink_to(target)
        self.command("checkpoint", "--note", "overwrite", expected=1)
        self.assertEqual(target.read_text(), "original")
        self.command("checkpoint", "--session", "../escape", expected=1)
        with patch.object(MODULE.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, "999999 Mon Sep  7 12:00:00 2026\n", "")):
            self.assertIsNone(MODULE.process_identity(123))

    def test_hook_errors_do_not_block_or_request_continuation(self):
        result = self.command("hook", payload={"hook_event_name": "Interrupt", "session_id": "../escape", "cwd": str(self.workspace)})
        self.assertEqual(json.loads(result.stdout), {})
        self.assertIn("invalid native session ID", result.stderr)
        self.assertFalse(self.state.exists())

    def test_orphan_session_end_leaves_no_state_but_existing_session_records_it(self):
        self.event("SessionEnd")
        self.assertFalse(self.state.exists())
        self.event("SessionStart", source="startup")
        self.event("SessionEnd")
        result = self.record()
        self.assertEqual(result["observed_state"], "session-ended")
        self.assertEqual([entry["event"] for entry in result["events"]], ["SessionStart", "SessionEnd"])

    def test_hook_contention_returns_within_interrupt_budget(self):
        self.command("checkpoint", "--note", "existing state")
        with MODULE.transaction("session-123"):
            start = time.monotonic()
            result = self.command("hook", payload={"hook_event_name": "Interrupt", "session_id": "session-123", "cwd": str(self.workspace)})
            self.assertLess(time.monotonic() - start, 2)
            self.assertIn("checkpoint is busy", result.stderr)
            self.assertEqual(json.loads(result.stdout), {})

    def test_worktree_identity_and_other_sessions_remain_separate(self):
        subprocess.run(["git", "init", "-q", str(self.workspace)], check=True)
        self.event("SessionStart", source="startup")
        self.command("checkpoint", "--session", "other-session", "--note", "other task")
        result = self.record()
        self.assertEqual(result["worktree"], str(self.workspace))
        self.assertEqual(Path(result["git_common_dir"]), self.workspace / ".git")
        self.assertNotIn("note", result)
        self.assertEqual(len(json.loads(self.command("list").stdout)), 2)


if __name__ == "__main__":
    unittest.main()
