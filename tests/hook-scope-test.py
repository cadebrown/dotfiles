#!/usr/bin/env python3
"""Exercise negative gates, relevant delegation, and plugin-update reconciliation."""
import copy
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
DISPATCHER = ROOT / "home/dot_claude/executable_hook-scope.sh"
spec = importlib.util.spec_from_file_location("scope", ROOT / "install/claude-hook-scope.py")
scope = importlib.util.module_from_spec(spec)
spec.loader.exec_module(scope)


class HookScopeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="hook scope ")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.project = self.root / "project with spaces"
        self.project.mkdir()

    def dispatch(self, mode, data, cwd=None):
        payload = json.dumps(data) if not isinstance(data, str) else data
        # cat proves the original receives intact JSON, exit 2 proves blocking
        # results are propagated rather than swallowed by a wrapper.
        return subprocess.run(["/bin/bash", str(DISPATCHER), mode, "/bin/bash", "-c", "cat; exit 2"],
                              input=payload, text=True, capture_output=True, cwd=cwd or self.project)

    def test_hookify_rules_added_and_removed_take_effect_immediately(self):
        self.assertEqual(self.dispatch("hookify", {}).returncode, 0)
        rules = self.project / ".claude"
        rules.mkdir()
        rule = rules / "hookify.new rule.local.md"
        rule.write_text("test")
        result = self.dispatch("hookify", {"tool_name": "Bash"})
        self.assertEqual(result.returncode, 2)
        self.assertEqual(json.loads(result.stdout), {"tool_name": "Bash"})
        rule.unlink()
        self.assertEqual(self.dispatch("hookify", {}).returncode, 0)

    def test_hookify_matches_upstream_process_cwd(self):
        rules = self.project / ".claude"
        rules.mkdir()
        (rules / "hookify.x.local.md").write_text("test")
        self.assertEqual(self.dispatch("hookify", {"cwd": str(self.root)}).returncode, 2)

    def test_lean_prompt_uses_invocation_not_project_presence(self):
        for prompt in ("hello", "review code", ""):
            self.assertEqual(self.dispatch("lean-prompt", {"prompt": prompt}).returncode, 0)
        for prompt in ("/lean4:prove X", "\u2003/lean4:formalize X", "/lean4:future-command"):
            result = self.dispatch("lean-prompt", {"prompt": prompt})
            self.assertEqual(result.returncode, 2)
            self.assertEqual(json.loads(result.stdout)["prompt"], prompt)
        self.assertEqual(self.dispatch("lean-prompt", '{"prompt":"\\u002flean4:prove X"}').returncode, 2)

    def test_lean_ancestor_markers_and_payload_cwd_precedence(self):
        deep = self.project / "nested" / "directory"
        deep.mkdir(parents=True)
        data = {"cwd": str(deep), "tool_input": {"command": "git reset --hard"}}
        self.assertEqual(self.dispatch("lean-guard", data, self.root).returncode, 0)
        for marker_name in ("lean-toolchain", "lakefile.lean", "lakefile.toml"):
            marker = self.project / marker_name
            marker.touch()
            result = self.dispatch("lean-guard", data, self.root)
            self.assertEqual(result.returncode, 2)
            self.assertEqual(json.loads(result.stdout), data)
            # Explicit unrelated cwd takes precedence over tool workdir.
            self.assertEqual(self.dispatch("lean-guard", {"cwd": str(self.root), "tool_input": {"workdir": str(deep)}}).returncode, 0)
            self.assertEqual(self.dispatch("lean-guard", {"tool_input": {"workdir": str(deep)}}).returncode, 2)
            marker.unlink()
        self.assertEqual(self.dispatch("lean-guard", data, self.root).returncode, 0)

    def test_invalid_payload_delegates_upstream_policy(self):
        for mode in ("lean-prompt", "lean-guard"):
            self.assertEqual(self.dispatch(mode, "broken json").returncode, 2)

    def test_force_and_symlinked_project_preserve_guard(self):
        with patch.dict(os.environ, {"LEAN4_GUARDRAILS_FORCE": "1"}):
            self.assertEqual(self.dispatch("lean-guard", {"cwd": str(self.root)}).returncode, 2)
        (self.project / "lean-toolchain").touch()
        nested = self.project / "nested"
        nested.mkdir()
        link = self.root / "link into project"
        link.symlink_to(nested, target_is_directory=True)
        self.assertEqual(self.dispatch("lean-guard", {"cwd": str(link)}).returncode, 2)

    def test_slow_stream_preserves_complete_payload(self):
        import time
        process = subprocess.Popen(["/bin/bash", str(DISPATCHER), "lean-prompt", "cat"],
                                   stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                   text=True, cwd=self.project)
        process.stdin.write('{"prompt": ')
        process.stdin.flush()
        time.sleep(1.1)
        stdout, stderr = process.communicate('"/lean4:prove X"}', timeout=5)
        self.assertEqual(process.returncode, 0, stderr)
        self.assertEqual(json.loads(stdout), {"prompt": "/lean4:prove X"})

    def test_guard_held_open_pipe_still_reaches_blocking_handler(self):
        import time
        (self.project / "lean-toolchain").touch()
        data = {"cwd": str(self.project), "tool_input": {"command": "git reset --hard"}}
        process = subprocess.Popen(["/bin/bash", str(DISPATCHER), "lean-guard", "/bin/bash", "-c", "cat; exit 2"],
                                   stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                   text=True, cwd=self.root)
        start = time.monotonic()
        process.stdin.write(json.dumps(data))
        process.stdin.flush()
        process.wait(timeout=3)
        self.assertEqual(process.returncode, 2)
        self.assertLess(time.monotonic() - start, 3)
        self.assertEqual(json.loads(process.stdout.read()), data)
        process.stdin.close()
        process.stdout.close()
        process.stderr.close()

    def fixture(self, plugin):
        result = {"description": "preserve me", "hooks": {}}
        for event, script in (scope.HOOKIFY if plugin == "hookify" else scope.LEAN).items():
            command = "${CLAUDE_PLUGIN_ROOT}/hooks/" + script
            if plugin == "hookify":
                command = f'python3 "{command}"'
            group = {"hooks": [{"type": "command", "command": command, "timeout": 10}]}
            if event == "SessionStart":
                group["matcher"] = "startup"
            if plugin == "lean4" and event == "PreToolUse":
                group["matcher"] = "Bash"
            result["hooks"][event] = [group]
        return result

    def test_transform_idempotence_and_loud_drift(self):
        for plugin in ("hookify", "lean4"):
            original = self.fixture(plugin)
            once = scope.transform(copy.deepcopy(original), plugin)
            self.assertEqual(once, scope.transform(copy.deepcopy(once), plugin))
            self.assertEqual(once["description"], original["description"])
            changed = copy.deepcopy(original)
            event = next(iter(changed["hooks"]))
            changed["hooks"][event][0]["hooks"][0]["command"] += " --new-behavior"
            with self.assertRaises(ValueError):
                scope.transform(changed, plugin)

    def test_reconcile_after_update_and_drift_restores_full_hooks(self):
        fixture_body = b"upstream gate contract fixture"
        checksums = {plugin: {"gate-source": hashlib.sha256(fixture_body).hexdigest()} for plugin in ("hookify", "lean4")}
        patcher = patch.object(scope, "GATE_SOURCES", checksums)
        patcher.start()
        self.addCleanup(patcher.stop)
        plugins = {}
        targets = []
        for plugin, key in (("hookify", "hookify@claude-plugins-official"), ("lean4", "lean4@lean4-skills")):
            install = self.root / plugin
            target = install / "hooks/hooks.json"
            target.parent.mkdir(parents=True)
            (install / "gate-source").write_bytes(fixture_body)
            target.write_text(json.dumps(self.fixture(plugin)))
            plugins[key] = [{"installPath": str(install)}]
            targets.append(target)
        registry = self.root / "plugins/installed_plugins.json"
        registry.parent.mkdir()
        registry.write_text(json.dumps({"plugins": plugins}))
        scope.reconcile(self.root)
        once = [p.read_text() for p in targets]
        scope.reconcile(self.root)
        self.assertEqual(once, [p.read_text() for p in targets])
        targets[0].write_text(json.dumps(self.fixture("hookify")))
        scope.reconcile(self.root)
        self.assertEqual(once, [p.read_text() for p in targets])
        targets[0].write_text(json.dumps(self.fixture("hookify")))
        broken = self.fixture("lean4")
        broken["hooks"]["NewEvent"] = []
        targets[1].write_text(json.dumps(broken))
        scope.reconcile(self.root)
        self.assertEqual(json.loads(targets[1].read_text()), broken)
        receipt = json.loads((self.root / "hook-scope-state.json").read_text())
        self.assertEqual(receipt["plugins"][1]["status"], "unscoped")
        targets[1].write_text(json.dumps(self.fixture("lean4")))
        scope.reconcile(self.root)
        (self.root / "lean4/gate-source").write_text("upstream starts applying new behavior")
        scope.reconcile(self.root)
        self.assertEqual(json.loads(targets[1].read_text()), self.fixture("lean4"))
        receipt = json.loads((self.root / "hook-scope-state.json").read_text())
        self.assertIn("gate source changed", receipt["plugins"][1]["reason"])
        self.assertEqual(receipt["plugins"][0]["status"], "scoped")
        # Execute the restored registration: even an irrelevant cwd must run
        # the full upstream hook after its applicability contract changes.
        handler = self.root / "lean4/hooks/guardrails.sh"
        handler.write_text('#!/bin/sh\nprintf "full upstream check"\nexit 2\n')
        handler.chmod(0o755)
        command = json.loads(targets[1].read_text())["hooks"]["PreToolUse"][0]["hooks"][0]["command"]
        result = subprocess.run(["/bin/bash", "-c", command], cwd=self.root,
                                env=dict(os.environ, CLAUDE_PLUGIN_ROOT="lean4"),
                                text=True, capture_output=True, input="{}")
        self.assertEqual(result.returncode, 2)
        self.assertEqual(result.stdout, "full upstream check")


if __name__ == "__main__":
    unittest.main()
