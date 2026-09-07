"""Behavioral coverage for preserving live Codex integrations during config sync."""

import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import tomlkit

SCRIPT = Path(__file__).resolve().parents[1] / "install/codex-config.py"
SPEC = importlib.util.spec_from_file_location("codex_config", SCRIPT)
SYNC = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SYNC)


class CodexConfigTests(unittest.TestCase):
    def test_semantic_merge_preserves_runtime_across_interleaved_tables(self):
        managed = tomlkit.parse("""model = "gpt-6-astra"
review_model = "gpt-6-astra"
model_reasoning_effort = "xhigh"
[features]
memories = true
[agents]
max_concurrent_threads_per_session = 6
[mcp_servers.github]
url = "https://new.example/mcp"
[mcp_servers.blender]
enabled = false
command = "new-blender"
""")
        current = tomlkit.parse("""model = "my-model-choice"
review_model = "old-review-model"
model_reasoning_effort = "max"
notify = ["desktop-client", "turn-ended"]
sandbox_mode = "danger-full-access"
[projects."/tmp/project.with.dots"]
trust_level = "trusted"
[features]
memories = false
node_repl = true
[features.context_management]
experimental_mode = true
[mcp_servers.github]
url = "https://old.example/mcp"
[mcp_servers.github.oauth]
client_id = "retired-managed-client"
[plugins."desktop@example"]
enabled = true
[mcp_servers.node_repl]
command = "desktop-node"
[mcp_servers.node_repl.env]
NODE_REPL_NODE_PATH = "/Applications/Desktop.app/node"
[mcp_servers.blender]
command = "old-blender"
[mcp_servers.retired]
command = "old-registry-server"
[hooks.state."/tmp/hooks.json:pre_tool_use:0:0"]
enabled = true
trusted_hash = "sha256:example"
[agents]
max_threads = 2
[skills]
max_context_tokens = 8000
[[skills.config]]
path = "/tmp/other-skill/SKILL.md"
enabled = false
[profiles.old]
model = "retired-profile"
""")
        merged = SYNC.merge_config(managed, current, {"github", "blender", "retired"})
        parsed = tomlkit.parse(tomlkit.dumps(merged))
        self.assertEqual(parsed["model"], "my-model-choice")
        self.assertEqual(parsed["model_reasoning_effort"], "max")
        self.assertEqual(parsed["review_model"], "gpt-6-astra")
        self.assertTrue(parsed["features"]["memories"])
        self.assertTrue(parsed["features"]["node_repl"])
        self.assertTrue(parsed["features"]["context_management"]["experimental_mode"])
        self.assertEqual(parsed["notify"], current["notify"])
        for key in ("projects", "plugins", "hooks", "skills"):
            self.assertEqual(parsed[key], current[key])
        self.assertEqual(
            parsed["mcp_servers"]["node_repl"], current["mcp_servers"]["node_repl"]
        )
        self.assertEqual(
            parsed["mcp_servers"]["github"], managed["mcp_servers"]["github"]
        )
        self.assertFalse(parsed["mcp_servers"]["blender"]["enabled"])
        self.assertNotIn("retired", parsed["mcp_servers"])
        self.assertNotIn("max_threads", parsed["agents"])
        self.assertNotIn("sandbox_mode", parsed)
        self.assertNotIn("profiles", parsed)
        self.assertEqual(
            SYNC.merge_config(managed, parsed, {"github", "blender", "retired"}), parsed
        )

    def test_skill_disable_preserves_other_choices_and_resolves_symlinks(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            actual = base / "shared/SKILL.md"
            actual.parent.mkdir()
            actual.write_text("name: skill-creator\n")
            alias = base / "agent-skill"
            alias.symlink_to(actual.parent, target_is_directory=True)
            config = tomlkit.parse("""[[skills.config]]
path = "/other/SKILL.md"
enabled = false
""")
            SYNC.disable_skills(config, [alias / "SKILL.md"])
            SYNC.disable_skills(config, [alias / "SKILL.md"])
            entries = config["skills"]["config"]
            self.assertEqual(len(entries), 3)
            self.assertEqual(
                {row["path"] for row in entries},
                {"/other/SKILL.md", str(actual.resolve()), str(alias / "SKILL.md")},
            )
            self.assertTrue(all(not row["enabled"] for row in entries))

    def test_atomic_cli_sync_and_domain_profiles(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            managed, current = base / "managed.toml", base / "config.toml"
            registry, ownership = base / "registry.jsonl", base / "ownership.json"
            managed.write_text(
                'model = "gpt-6-astra"\n[mcp_servers.blender]\nenabled = false\ncommand = "blender-mcp"\n'
            )
            current.write_text(
                '[mcp_servers.retired]\ncommand = "remove-me"\n[mcp_servers.custom]\ncommand = "keep-me"\n'
            )
            ownership.write_text('["retired"]')
            registry.write_text(
                json.dumps({"name": "blender", "profile": "creative"}) + "\n"
            )
            command = [
                sys.executable,
                str(SCRIPT),
                "--managed",
                str(managed),
                "--current",
                str(current),
                "--output",
                str(current),
                "--registry",
                str(registry),
                "--ownership",
                str(ownership),
                "--profiles-dir",
                str(base),
            ]
            subprocess.run(command, check=True, capture_output=True)
            first = current.read_bytes()
            subprocess.run(command, check=True, capture_output=True)
            self.assertEqual(current.read_bytes(), first)
            self.assertEqual(current.stat().st_mode & 0o777, 0o600)
            self.assertEqual(json.loads(ownership.read_text()), ["blender"])
            self.assertEqual(
                set(tomlkit.parse(current.read_text())["mcp_servers"]),
                {"blender", "custom"},
            )
            for profile in ("creative", "tools-all"):
                value = tomlkit.parse((base / f"{profile}.config.toml").read_text())
                self.assertTrue(value["mcp_servers"]["blender"]["enabled"])
            managed.write_text("this is not valid TOML")
            result = subprocess.run(command, capture_output=True, check=False)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(current.read_bytes(), first)

    def test_retired_profiles_remove_managed_servers_and_preserve_custom_content(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            records = [
                {"name": "blender", "profile": "creative"},
                {"name": "lean", "profile": "math"},
            ]
            SYNC.sync_profiles(base, records, {"blender", "lean"})
            creative = base / "creative.config.toml"
            creative.write_text(
                'model = "user-model"\n'
                + creative.read_text()
                + '\n[mcp_servers.custom]\ncommand = "custom-tool"\n'
            )
            custom = base / "custom.config.toml"
            custom.write_text("[mcp_servers.blender]\nenabled = true\n")
            SYNC.sync_profiles(base, [], {"blender", "lean"})
            self.assertFalse((base / "math.config.toml").exists())
            preserved = tomlkit.parse(creative.read_text())
            self.assertEqual(preserved["model"], "user-model")
            self.assertEqual(set(preserved["mcp_servers"]), {"custom"})
            self.assertEqual(
                custom.read_text(), "[mcp_servers.blender]\nenabled = true\n"
            )
            first = creative.read_bytes()
            SYNC.sync_profiles(base, [], set())
            self.assertEqual(creative.read_bytes(), first)

    def test_legacy_generated_profiles_migrate_without_claiming_custom_servers(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            creative = base / "creative.config.toml"
            creative.write_text(
                SYNC.PROFILE_HEADER
                + "[mcp_servers.blender]\nenabled = true\n"
                + '[mcp_servers.custom]\ncommand = "custom-tool"\n'
            )
            math = base / "math.config.toml"
            math.write_text(
                SYNC.PROFILE_HEADER + "[mcp_servers.lean]\nenabled = true\n"
            )
            SYNC.sync_profiles(base, [], {"blender", "lean"})
            self.assertFalse(math.exists())
            self.assertEqual(
                set(tomlkit.parse(creative.read_text())["mcp_servers"]), {"custom"}
            )


if __name__ == "__main__":
    unittest.main()
