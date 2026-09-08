import importlib.util
import json
import os
from pathlib import Path
import plistlib
import socket
import sys
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("local_agent", Path(__file__).parents[1] / "install/local-agent.py")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class ModelServer(BaseHTTPRequestHandler):
    def do_GET(self):
        payload = json.dumps({"data": [{"id": "local-model"}]}).encode()
        self.send_response(200)
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, *args):
        return


class LocalAgentTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.root = Path(self.directory.name)
        self.state = self.root / "state"
        self.plist = self.root / "mlx.plist"

    def tearDown(self):
        receipt = MODULE.read_json(self.state / "process.json")
        if receipt.get("pid") and MODULE.identity(receipt["pid"]) == receipt.get("identity"):
            MODULE.stop_owned(self.state)
        self.directory.cleanup()

    def server(self):
        server = ThreadingHTTPServer(("127.0.0.1", 0), ModelServer)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(server.server_close)
        self.addCleanup(server.shutdown)
        return f"http://127.0.0.1:{server.server_port}/v1"

    def test_reuses_matching_existing_server_without_creating_receipt(self):
        url = self.server()
        MODULE.ensure_server(url, "local-model", self.state, self.plist)
        self.assertFalse((self.state / "process.json").exists())
        self.assertEqual(MODULE.models(url), {"local-model"})

    def test_wrong_model_leaves_existing_server_untouched(self):
        url = self.server()
        with self.assertRaisesRegex(ValueError, "existing endpoint does not serve"):
            MODULE.ensure_server(url, "other-model", self.state, self.plist)
        self.assertEqual(MODULE.models(url), {"local-model"})

    def test_non_http_listener_is_not_replaced(self):
        with socket.socket() as listener:
            listener.bind(("127.0.0.1", 0))
            listener.listen()
            url = f"http://127.0.0.1:{listener.getsockname()[1]}/v1"
            with self.assertRaisesRegex(ValueError, "occupied"):
                MODULE.ensure_server(url, "local-model", self.state, self.plist)

    def fake_runtime(self, body):
        with socket.socket() as listener:
            listener.bind(("127.0.0.1", 0))
            port = listener.getsockname()[1]
        with self.plist.open("wb") as output:
            plistlib.dump({"ProgramArguments": ["/old/unavailable/server", "launch",
                "--served-model-name", "local-model", "--host", "127.0.0.1", "--port", str(port)]}, output)
        executable = self.root / "mlx-openai-server"
        executable.write_text(f"#!{sys.executable}\n" + body)
        executable.chmod(0o755)
        return executable, f"http://127.0.0.1:{port}/v1"

    def test_owned_start_verifies_model_uses_current_path_and_stops_exact_process(self):
        executable, url = self.fake_runtime('''import json, os, sys
from http.server import BaseHTTPRequestHandler, HTTPServer
assert os.environ["HF_HUB_OFFLINE"] == "1"
class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b'{"data":[{"id":"local-model"}]}')
port = int(sys.argv[sys.argv.index("--port") + 1])
HTTPServer(("127.0.0.1", port), Handler).serve_forever()
''')
        with patch.object(MODULE.sys, "platform", "darwin"), patch.object(MODULE.shutil, "which", return_value=str(executable)):
            process = MODULE.ensure_server(url, "local-model", self.state, self.plist, timeout=5)
            self.addCleanup(process.wait, timeout=5)
        receipt = MODULE.read_json(self.state / "process.json")
        self.assertEqual(receipt["model"], "local-model")
        self.assertEqual(MODULE.models(url), {"local-model"})
        MODULE.stop_owned(self.state)
        process.wait(timeout=5)
        self.assertFalse((self.state / "process.json").exists())
        self.assertFalse(MODULE.occupied(url))

    def test_failed_start_does_not_claim_readiness(self):
        executable, url = self.fake_runtime("raise SystemExit(17)\n")
        with patch.object(MODULE.sys, "platform", "darwin"), patch.object(MODULE.shutil, "which", return_value=str(executable)):
            with self.assertRaisesRegex(ValueError, "MLX exited"):
                MODULE.ensure_server(url, "local-model", self.state, self.plist, timeout=5)
        self.assertFalse((self.state / "process.json").exists())

    def test_saved_pid_cannot_authorize_stopping_an_unrelated_process(self):
        self.state.mkdir()
        (self.state / "process.json").write_text(json.dumps({"pid": os.getpid(), "identity": "old unrelated process"}))
        with self.assertRaisesRegex(ValueError, "another process"):
            MODULE.stop_owned(self.state)

    def test_pi_reads_configured_model_and_rejects_cloud_fallback(self):
        directory = self.root / ".pi/agent"
        directory.mkdir(parents=True)
        (directory / "settings.json").write_text(json.dumps({"defaultProvider": "mlx", "defaultModel": "local-model"}))
        (directory / "models.json").write_text(json.dumps({"providers": {"mlx": {
            "baseUrl": "http://localhost:8080/v1", "models": [{"id": "local-model"}]}}}))
        with patch.dict(os.environ, {"PI_CODING_AGENT_DIR": str(directory)}):
            url, model, forced = MODULE.agent_config("pi", [], self.root, "pi")
            self.assertEqual((url, model), ("http://localhost:8080/v1", "local-model"))
            self.assertEqual(forced, ["--provider", "mlx", "--model", "local-model"])
            _, model, forced = MODULE.agent_config("pi", ["--model", "mlx/local-model:high"], self.root, "pi")
            self.assertEqual(model, "local-model")
            self.assertEqual(forced, ["--provider", "mlx", "--model", "local-model:high"])
            with self.assertRaises(ValueError):
                MODULE.agent_config("pi", ["--model", "openai/cloud-model"], self.root, "pi")

    def test_opencode_uses_effective_config_and_agent_selection(self):
        executable = self.root / "opencode"
        config = {"model": "mlx/local-model", "provider": {"mlx": {"options": {"baseURL": "http://localhost:8080/v1"}}},
                  "agent": {"plan": {"model": "anthropic/cloud-model"}}}
        executable.write_text(f"#!{sys.executable}\nimport sys\nassert sys.argv[1:] == ['debug', 'config']\nprint({json.dumps(config)!r})\n")
        executable.chmod(0o755)
        _, model, _ = MODULE.agent_config("opencode", [], self.root, str(executable))
        self.assertEqual(model, "local-model")
        with self.assertRaisesRegex(ValueError, "mlx provider"):
            MODULE.agent_config("opencode", ["--agent", "plan"], self.root, str(executable))

    def test_resolved_model_flags_replace_overrides_but_preserve_prompt_text(self):
        self.assertEqual(MODULE.without_model_flags(["--provider", "mlx", "--model=x", "run", "--", "--model", "as text"]),
                         ["run", "--", "--model", "as text"])

    def test_opencode_subcommand_precedes_generated_options_and_prompt_delimiter(self):
        forced = ["--model", "mlx/local-model"]
        self.assertEqual(MODULE.client_arguments("opencode", ["run", "--model=mlx/local-model", "--agent", "build", "--", "--model", "prompt"], forced),
                         ["run", "--agent", "build", "--model", "mlx/local-model", "--auto", "--", "--model", "prompt"])
        self.assertEqual(MODULE.client_arguments("opencode", ["run", "--no-auto", "prompt"], forced),
                         ["run", "--no-auto", "prompt", "--model", "mlx/local-model"])
        self.assertEqual(MODULE.client_arguments("pi", ["--provider", "mlx", "--model", "local-model:high", "--", "--model"],
                                               ["--provider", "mlx", "--model", "local-model:high"]),
                         ["--provider", "mlx", "--model", "local-model:high", "--", "--model"])


if __name__ == "__main__":
    unittest.main()
