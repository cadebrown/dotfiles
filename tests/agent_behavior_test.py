import argparse
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch


SPEC = importlib.util.spec_from_file_location("agent_behavior", Path(__file__).with_name("agent_behavior.py"))
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class AgentBehaviorTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.addCleanup(self.temporary.cleanup)

    def test_verifier_rejects_original_bug_and_accepts_correct_implementation(self):
        fixture = MODULE.FIXTURES / "coding"
        workspace = self.root / "workspace"
        shutil.copytree(fixture / "input", workspace)
        command = ["uv", "run", "--no-project", "--offline", str(fixture / "verify.py"), str(workspace)]
        self.assertNotEqual(subprocess.run(command, capture_output=True).returncode, 0)
        (workspace / "merge_ranges.py").write_text(
            'def merge_ranges(ranges):\n'
            '    result = []\n'
            '    for start, end in sorted(ranges):\n'
            '        if start > end: raise ValueError("reversed")\n'
            '        if start == end: continue\n'
            '        if result and start <= result[-1][1]:\n'
            '            result[-1] = (result[-1][0], max(end, result[-1][1]))\n'
            '        else: result.append((start, end))\n'
            '    return result\n')
        result = subprocess.run(command, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue(all(c["passed"] for c in json.loads(result.stdout)["checks"]))

    def test_isolation_resume_evidence_and_auth_cleanup(self):
        fixture_root = self.root / "fixtures"
        fixture = fixture_root / "resume"
        (fixture / "input").mkdir(parents=True)
        (fixture / "input" / "user-note.txt").write_text("unchanged")
        (fixture / "task.txt").write_text("checkpoint")
        (fixture / "resume.txt").write_text("finish")
        (fixture / "verify.py").write_text('print("verified fixture")\n')
        baseline, candidate = self.root / "before.md", self.root / "after.md"
        baseline.write_text("Baseline instructions")
        candidate.write_text("Candidate instructions")
        agent_dir = self.root / "roles"
        agent_dir.mkdir()
        role_text = 'name = "extractor"\nmodel = "gpt-5.6-luna"\n'
        (agent_dir / "extractor.toml").write_text(role_text)
        auth = self.root / "auth.json"
        auth.write_text('{"fixture": "test-token"}')
        codex = self.root / "fake-codex"
        codex.write_text('''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
args = sys.argv[1:]
home = Path(os.environ.get("CODEX_HOME", "."))
if "--version" in args:
    print("codex fixture")
elif "debug" in args:
    print(json.dumps([{"role":"user","content":[{"type":"input_text","text":(home/"AGENTS.md").read_text()}]}]))
else:
    assert (home/"auth.json").stat().st_mode & 0o777 == 0o600
    assert Path(args[args.index("--cd")+1]).resolve() == Path.cwd()
    assert os.environ["HOME"] == str(home.parent)
    assert os.environ["UV_CACHE_DIR"] == str(Path(os.environ["TMPDIR"])/"uv-cache")
    assert "OPENAI_API_KEY" not in os.environ
    if os.environ.get("EVAL_TEST_FAIL"):
        sys.exit(2)
    prompt = sys.stdin.read()
    if "resume" in args:
        assert args[args.index("resume")+1] == "fixture-thread"
        assert Path("checkpoint.txt").read_text() == "checkpoint"
    else:
        Path("checkpoint.txt").write_text(prompt)
    Path(args[args.index("--output-last-message")+1]).write_text(prompt)
    print(json.dumps({"type":"thread.started","thread_id":"fixture-thread"}))
    print(json.dumps({"type":"turn.completed","usage":{"input_tokens":1,"output_tokens":1}}))
''')
        codex.chmod(0o755)
        output = self.root / "results"
        args = argparse.Namespace(output=output, baseline=baseline, candidate=candidate,
                                  cases=["resume"], model="gpt-6-astra", effort="xhigh", codex=str(codex),
                                  skill=[], agent_dir=agent_dir, browser_modules=None, sandbox="danger-full-access")
        physical_root = self.root / "runtime-physical"
        physical_root.mkdir()
        alias_root = self.root / "runtime-alias"
        alias_root.symlink_to(physical_root, target_is_directory=True)
        aliased_runtime = alias_root / "experiment"
        aliased_runtime.mkdir()
        with patch.object(MODULE, "FIXTURES", fixture_root), \
                patch.object(MODULE.tempfile, "mkdtemp", return_value=str(aliased_runtime)), \
                contextlib.redirect_stdout(io.StringIO()):
            MODULE.prepare(args)
        experiment = output / "experiment.json"
        manifest = json.loads(experiment.read_text())
        runtime = Path(manifest["runtime_root"])
        self.assertEqual(runtime, aliased_runtime.resolve())
        self.assertEqual(manifest["sandbox"], "danger-full-access")
        self.addCleanup(shutil.rmtree, runtime)
        self.assertNotEqual(manifest["variants"]["baseline"]["sha256"], manifest["variants"]["candidate"]["sha256"])
        self.assertEqual((output / "agents/extractor.toml").read_text(), role_text)
        self.assertEqual((output / "agents/extractor.toml").stat().st_mode & 0o777, 0o600)
        self.assertEqual(output.stat().st_mode & 0o777, 0o700)
        for variant in ("baseline", "candidate"):
            selected = manifest["runs"][f"{variant}/resume"]
            role = Path(selected["root"]) / "home/.codex/agents/extractor.toml"
            self.assertEqual(role.read_text(), role_text)
            self.assertEqual(role.stat().st_mode & 0o777, 0o600)
            self.assertEqual(selected["control"]["agents/extractor.toml"], MODULE.digest(role))
            config = (Path(selected["root"]) / "home/.codex/config.toml").read_text()
            self.assertIn("multi_agent_v2 = true", config)
            self.assertIn("max_concurrent_threads_per_session = 2", config)
        run_args = argparse.Namespace(experiment=experiment, variant="candidate", case="resume", auth_file=auth, timeout=30)
        with patch.dict("os.environ", {"OPENAI_API_KEY": "not-for-fixture"}), contextlib.redirect_stdout(io.StringIO()):
            MODULE.run(run_args)
        result = manifest["runs"]["candidate/resume"]
        run_root = Path(result["root"])
        self.assertIn('sandbox_mode = "danger-full-access"', (run_root / "home/.codex/config.toml").read_text())
        self.assertFalse((run_root / "home/.codex/auth.json").exists())
        evidence = json.loads((Path(result["artifacts"]) / "run.json").read_text())
        self.assertEqual([turn["thread_id"] for turn in evidence], ["fixture-thread", "fixture-thread"])
        self.assertTrue((Path(result["artifacts"]) / "turn-1-workspace/checkpoint.txt").is_file())
        self.assertEqual((run_root / "workspace/user-note.txt").read_text(), "unchanged")
        (run_root / "home/.codex/AGENTS.md").write_text("tampered")
        with self.assertRaisesRegex(ValueError, "Control changed"):
            MODULE.check_controls(result)
        run_args.variant = "baseline"
        with patch.dict("os.environ", {"EVAL_TEST_FAIL": "1"}), self.assertRaisesRegex(RuntimeError, "did not complete"):
            MODULE.run(run_args)
        failed_root = Path(manifest["runs"]["baseline/resume"]["root"])
        self.assertFalse((failed_root / "home/.codex/auth.json").exists())

    def test_empty_agent_directory_fails_before_preparation(self):
        args = argparse.Namespace(agent_dir=self.root, output=self.root / "output")
        with self.assertRaisesRegex(ValueError, "No custom agent TOML"):
            MODULE.prepare(args)
        self.assertFalse(args.output.exists())

    def test_native_usage_preserves_child_identity_without_exporting_content(self):
        sessions = self.root / "sessions"
        sessions.mkdir()
        events = [
            {"type": "session_meta", "payload": {"id": "child", "source": {"subagent": {
                "thread_spawn": {"parent_thread_id": "parent", "agent_role": "coder"}}}}},
            {"type": "session_meta", "payload": {"id": "parent", "source": "exec"}},
            {"type": "turn_context", "payload": {"model": "gpt-6-astra", "effort": "xhigh"}},
            {"type": "response_item", "payload": {"text": "private prompt or tool content"}},
            {"type": "turn_context", "payload": {"model": "gpt-5.6-luna", "effort": "low"}},
            {"type": "event_msg", "payload": {"type": "token_count", "info": {
                "total_token_usage": {"input_tokens": 100, "cached_input_tokens": 60, "output_tokens": 10}}}},
            {"type": "event_msg", "payload": {"type": "token_count", "info": None}},
            {"type": "event_msg", "payload": {"type": "token_count", "info": "unknown format"}},
            {"type": "turn_context", "payload": None},
            None,
        ]
        (sessions / "child.jsonl").write_text("\n".join(map(json.dumps, events)) + "\npartial line")
        (sessions / "empty.jsonl").write_text(json.dumps({"type": "session_meta", "payload": {"id": "empty"}}))
        report = MODULE.native_usage(self.root)
        child, empty = report["sessions"]
        self.assertEqual((child["thread_id"], child["parent_thread_id"], child["role"]), ("child", "parent", "coder"))
        self.assertEqual((child["model"], child["effort"]), ("gpt-5.6-luna", "low"))
        self.assertEqual(child["reported_usage"]["input_tokens"], 100)
        self.assertIsNone(empty["reported_usage"])
        self.assertNotIn("private prompt", json.dumps(report))

    def test_delegation_verifier_exercises_results_and_preservation(self):
        fixture = MODULE.FIXTURES / "delegation"
        workspace = self.root / "maintenance"
        shutil.copytree(fixture / "input", workspace)
        command = ["uv", "run", "--no-project", "--offline", str(fixture / "verify.py"), str(workspace)]
        self.assertNotEqual(subprocess.run(command, capture_output=True).returncode, 0)
        (workspace / "output").mkdir()
        shutil.copyfile(fixture / "expected-log.json", workspace / "output/log-summary.json")
        producer = workspace / "events/producer.py"
        producer.write_text(producer.read_text().replace("def make_event(task_id,", "def make_event(job_id,")
                            .replace('"task_id": task_id,', '"job_id": job_id,'))
        consumer = workspace / "events/consumer.py"
        consumer.write_text(consumer.read_text().replace("task_id", "job_id"))
        (workspace / "retry_queue.py").write_text('''class RetryQueue:
    def __init__(self, base_delay=2, max_delay=30):
        if type(base_delay) is not int or type(max_delay) is not int or base_delay <= 0 or max_delay < base_delay:
            raise ValueError("invalid delays")
        self.base_delay, self.max_delay = base_delay, max_delay
        self.next_delays = {}
    def failure(self, job_id):
        delay = self.next_delays.get(job_id, self.base_delay)
        self.next_delays[job_id] = min(delay * 2, self.max_delay)
        return delay
    def success(self, job_id):
        self.next_delays.pop(job_id, None)
''')
        result = subprocess.run(command, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(len(json.loads(result.stdout)["checks"]), 5)
        original_report = (workspace / "output/log-summary.json").read_text()
        report = json.loads(original_report)
        report["groups"][0]["first_line"] += 1
        (workspace / "output/log-summary.json").write_text(json.dumps(report))
        result = subprocess.run(command, text=True, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        checks = {c["name"]: c["passed"] for c in json.loads(result.stdout)["checks"]}
        self.assertFalse(checks["exact log summary and evidence"])
        (workspace / "output/log-summary.json").write_text(original_report)
        (workspace / "user-notes.txt").write_text("unintended rewrite")
        result = subprocess.run(command, text=True, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        checks = {c["name"]: c["passed"] for c in json.loads(result.stdout)["checks"]}
        self.assertFalse(checks["preserved source inputs"])


if __name__ == "__main__":
    unittest.main()
