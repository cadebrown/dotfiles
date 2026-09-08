"""Contract tests for profile ownership and private authentication transfers."""

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HELPER = Path(__file__).resolve().parents[1] / "home/dot_local/bin/executable_df-browser"
FAKE_CLI = r'''#!/usr/bin/env python3
import json, os
from pathlib import Path
import sys
args = sys.argv[1:]
session = args.pop(0).removeprefix('-s=')
command = args.pop(0)
state_file = Path('.test-browser.json')
state = json.loads(state_file.read_text()) if state_file.exists() else None
with open(os.environ['BROWSER_TEST_LOG'], 'a') as log:
    log.write(json.dumps({'session':session, 'command':command, 'args':args,
        'env':{k:v for k,v in os.environ.items() if k.startswith('PLAYWRIGHT_MCP_') or k == 'PLAYWRIGHT_CLI_SESSION'}}) + '\n')
if command == 'list':
    result = {'browsers':[state] if state else []}
elif command in ('open', 'attach'):
    state = {'name':session, 'status':'open', 'attached':command == 'attach',
        'userDataDir':next((a.split('=',1)[1] for a in args if a.startswith('--profile=')), None),
        'headed':'--headed' in args}
    state_file.write_text(json.dumps(state))
    result = {'session':session, 'status':'open'}
elif command in ('close', 'detach'):
    state_file.unlink(missing_ok=True)
    result = {'status':'closed'}
elif command == 'state-save':
    Path(args[0]).write_text(json.dumps({'cookies':[], 'origins':[]}))
    result = {'result':'Saved'}
else:
    result = {'result':'Done'}
print(json.dumps(result))
'''


class BrowserSessions(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.project = self.root / "project"
        self.project.mkdir()
        self.bin = self.root / "bin"
        self.bin.mkdir()
        cli = self.bin / "playwright-cli"
        cli.write_text(FAKE_CLI.replace("#!/usr/bin/env python3", "#!" + sys.executable))
        cli.chmod(0o700)
        self.log = self.root / "calls.jsonl"
        self.environment = dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ["PATH"],
                                XDG_STATE_HOME=str(self.root / "state"), BROWSER_TEST_LOG=str(self.log),
                                PLAYWRIGHT_MCP_USER_DATA_DIR="/someone-elses-profile", PLAYWRIGHT_MCP_EXTENSION="chrome",
                                PLAYWRIGHT_CLI_SESSION="unrelated")

    def call(self, *arguments, project=None, success=True):
        result = subprocess.run([sys.executable, str(HELPER), "--project", str(project or self.project), *arguments],
                                capture_output=True, text=True, env=self.environment, check=False)
        if success:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            return json.loads(result.stdout)
        self.assertNotEqual(result.returncode, 0, result.stdout)
        return result.stderr

    def calls(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()]

    def test_project_service_isolation_and_same_workspace_restart(self):
        first = self.call("open", "service", "https://example.com")
        other = self.call("open", "another", "https://example.com")
        project = self.root / "project-two"
        project.mkdir()
        second = self.call("open", "service", project=project)
        self.assertEqual(len({first["profile"], other["profile"], second["profile"]}), 3)
        self.call("close", "service")
        again = self.call("open", "service")
        self.assertEqual(again["profile"], first["profile"])
        self.assertEqual(again["session"], first["session"])
        launches = [call for call in self.calls() if call["command"] == "open"]
        self.assertEqual(launches[-1]["args"][0], "https://example.com")
        self.assertTrue(all(not call["env"] for call in self.calls()))
        self.assertEqual(Path(first["profile"]).stat().st_mode & 0o777, 0o700)

    def test_attached_session_only_detaches_and_cannot_export_auth(self):
        attached = self.call("attach", "account", "--extension=chrome")
        self.assertEqual(attached["mode"], "extension")
        self.assertIsNone(attached["profile"])
        self.assertIn("only supported for owned", self.call("export-auth", "account", success=False))
        self.assertIn("mode cannot change", self.call("open", "account", success=False))
        self.call("close", "account")
        actions = [call["command"] for call in self.calls()]
        self.assertIn("detach", actions)
        self.assertNotIn("close", actions)
        self.assertNotIn("state-save", actions)
        self.assertIn("--extension=chrome", next(call["args"] for call in self.calls() if call["command"] == "attach"))

    def test_shared_home_hosts_have_distinct_native_sessions_and_profiles(self):
        self.environment["DF_BROWSER_HOST_ID"] = "machine-one"
        first = self.call("open", "service")
        self.environment["DF_BROWSER_HOST_ID"] = "machine-two"
        second = self.call("open", "service")
        self.assertNotEqual(first["session"], second["session"])
        self.assertNotEqual(first["profile"], second["profile"])
        self.assertTrue((Path(first["profile"]).parent / ".playwright").is_dir())
        self.assertTrue((Path(second["profile"]).parent / ".playwright").is_dir())
        self.environment["DF_BROWSER_HOST_ID"] = "machine-one"
        self.assertEqual(self.call("status", "service")["session"], first["session"])

    def test_auth_transfer_is_private_explicit_and_does_not_overwrite_exports(self):
        opened = self.call("open", "service")
        workspace = Path(opened["profile"]).parent
        self.assertFalse((workspace / "auth").exists())
        exported = Path(self.call("export-auth", "service")["auth_file"])
        self.assertEqual(exported.stat().st_mode & 0o777, 0o600)
        self.assertNotIn(str(self.project), str(exported))
        self.assertIn("label already exists", self.call("export-auth", "service", success=False))
        self.assertTrue(self.call("import-auth", "service", str(exported))["imported"])
        exported.chmod(0o644)
        self.assertIn("private", self.call("import-auth", "service", str(exported), success=False))
        exported.chmod(0o600)
        linked = self.root / "link.json"
        linked.symlink_to(exported)
        self.assertIn("not a symlink", self.call("import-auth", "service", str(linked), success=False))

    def test_remove_requires_closed_owned_workspace_and_preserves_siblings(self):
        first = self.call("open", "first")
        other = self.call("open", "other")
        self.assertIn("Close this workspace", self.call("remove", "first", success=False))
        self.call("close", "first")
        self.call("remove", "first")
        self.assertFalse(Path(first["profile"]).parent.exists())
        self.assertTrue(Path(other["profile"]).exists())
        self.assertTrue(self.call("status", "other")["running"])

    def test_session_override_and_changed_ownership_are_rejected(self):
        opened = self.call("open", "service")
        self.assertIn("Cannot override", self.call("run", "service", "snapshot", "-s=unrelated", success=False))
        self.assertIn("managed operations", self.call("run", "service", "kill-all", success=False))
        state_file = Path(opened["profile"]).parent / ".test-browser.json"
        state = json.loads(state_file.read_text())
        state["userDataDir"] = str(self.root / "unrelated-profile")
        state_file.write_text(json.dumps(state))
        self.assertIn("different profile", self.call("close", "service", success=False))
        self.assertTrue(state_file.exists())

    def test_traversal_and_symlink_workspaces_are_rejected(self):
        self.call("open", "../../escape", success=False)
        opened = self.call("open", "service")
        workspace = Path(opened["profile"]).parent
        sibling = workspace.parent / "linked"
        sibling.symlink_to(workspace)
        self.assertIn("symlink", self.call("open", "linked", success=False))


if __name__ == "__main__":
    unittest.main()
