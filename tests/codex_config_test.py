"""Behavioral coverage for preserving live Codex integrations during config sync."""

import importlib.util
import json
import os
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
    def test_agent_scopes_keep_transports_and_exclude_runtime_integrations(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            sources = base / "sources"
            sources.mkdir()
            (sources / "coder.toml").write_text('''name = "coder"
description = "Exact changes"
model = "gpt-5.6-luna"
model_reasoning_effort = "low"
developer_instructions = "Only the assigned changes."
[agents]
enabled = false
''')
            (sources / "reviewer.toml").write_text('''name = "reviewer"
description = "Review"
developer_instructions = "Inspect correctness."
''')
            scopes = base / "scopes.json"
            scopes.write_text('{"coder": ["docs"]}')
            config = tomlkit.parse('''model = "gpt-6-astra"
[mcp_servers.docs]
url = "https://docs.example/mcp"
bearer_token_env_var = "DOCS_TOKEN"
[mcp_servers.runtime]
command = "runtime-tool"
required = true
[apps._default]
enabled = true
[apps.mail]
enabled = true
[plugins."runtime@example"]
enabled = true
''')
            original = tomlkit.dumps(config)
            output = SYNC.render_agents(sources, scopes, config)
            coder = tomlkit.parse(output["coder.toml"])
            self.assertEqual(coder["model"], "gpt-5.6-luna")
            self.assertEqual(coder["model_reasoning_effort"], "low")
            self.assertFalse(coder["agents"]["enabled"])
            self.assertTrue(coder["mcp_servers"]["docs"]["enabled"])
            self.assertEqual(coder["mcp_servers"]["docs"]["bearer_token_env_var"], "DOCS_TOKEN")
            self.assertFalse(coder["mcp_servers"]["runtime"]["enabled"])
            self.assertFalse(coder["mcp_servers"]["runtime"]["required"])
            self.assertEqual(coder["mcp_servers"]["runtime"]["command"], "runtime-tool")
            self.assertTrue(all(not value["enabled"] for value in coder["apps"].values()))
            self.assertFalse(coder["features"]["plugins"])
            self.assertNotIn("plugins", coder)
            reviewer = tomlkit.parse(output["reviewer.toml"])
            self.assertNotIn("model", reviewer)
            self.assertNotIn("mcp_servers", reviewer)
            self.assertEqual(tomlkit.dumps(config), original)
            self.assertEqual(SYNC.render_agents(sources, scopes, config), output)
            target = base / "coder.toml"
            SYNC.atomic_write(target, output["coder.toml"])
            target.chmod(0o644)
            SYNC.atomic_write(target, output["coder.toml"])
            self.assertEqual(target.stat().st_mode & 0o777, 0o600)
            scopes.write_text('{"coder": ["typo"]}')
            with self.assertRaisesRegex(ValueError, "Unknown MCP"):
                SYNC.render_agents(sources, scopes, config)
            scopes.write_text('{"missing_role": []}')
            with self.assertRaisesRegex(ValueError, "missing agent sources"):
                SYNC.render_agents(sources, scopes, config)

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
[apps.example]
default_tools_approval_mode = "writes"
[apps.example.tools.publish]
approval_mode = "writes"
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
            parsed["mcp_servers"]["node_repl"]["command"], "desktop-node"
        )
        self.assertEqual(
            parsed["mcp_servers"]["node_repl"]["env"],
            current["mcp_servers"]["node_repl"]["env"],
        )
        self.assertEqual(
            parsed["mcp_servers"]["node_repl"]["default_tools_approval_mode"],
            "approve",
        )
        self.assertEqual(
            parsed["apps"]["example"]["default_tools_approval_mode"], "approve"
        )
        self.assertEqual(
            parsed["apps"]["example"]["tools"]["publish"]["approval_mode"],
            "approve",
        )
        self.assertEqual(
            parsed["mcp_servers"]["github"]["url"], "https://new.example/mcp"
        )
        self.assertEqual(
            parsed["mcp_servers"]["github"]["default_tools_approval_mode"],
            "approve",
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
                '[apps.mail]\nenabled = true\n[apps.calendar]\nenabled = true\n'
            )
            sources = base / "sources"
            sources.mkdir()
            (sources / "coder.toml").write_text(
                'name = "coder"\ndescription = "Exact edits"\n'
                'developer_instructions = "Change only assigned files."\n'
            )
            scopes = base / "scopes.json"
            scopes.write_text('{"coder": []}')
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
                "--agent-sources", str(sources),
                "--agent-scopes", str(scopes),
                "--agents-dir", str(base / "agents"),
            ]
            subprocess.run(command, check=True, capture_output=True,
                           env={**os.environ, "PYTHONHASHSEED": "1"})
            first = current.read_bytes()
            agent_target = base / "agents/coder.toml"
            first_agent = agent_target.read_bytes()
            subprocess.run(command, check=True, capture_output=True,
                           env={**os.environ, "PYTHONHASHSEED": "2"})
            self.assertEqual(current.read_bytes(), first)
            self.assertEqual(agent_target.read_bytes(), first_agent)
            self.assertEqual(agent_target.stat().st_mode & 0o777, 0o600)
            self.assertEqual(current.stat().st_mode & 0o777, 0o600)
            self.assertEqual(json.loads(ownership.read_text()), ["blender"])
            self.assertEqual(
                set(tomlkit.parse(current.read_text())["mcp_servers"]),
                {"blender", "custom"},
            )
            self.assertEqual(
                tomlkit.parse(current.read_text())["mcp_servers"]["custom"][
                    "default_tools_approval_mode"
                ],
                "approve",
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
