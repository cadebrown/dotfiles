import json
import os
import queue
import shutil
import http.server
import subprocess
import sys
import tempfile
import threading
import time
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class FixtureProvider(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, format, *args):
        pass

    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0"))
        self.server.requests.append((self.path, json.loads(self.rfile.read(length))))
        response = {"id": "resp-hook-fixture", "object": "response", "status": "completed", "model": "hook-fixture",
                    "output": [{"id": "msg-hook-fixture", "type": "message", "status": "completed", "role": "assistant",
                                "content": [{"type": "output_text", "text": "fixture complete", "annotations": []}]}]}
        events = [
            ("response.created", {"type": "response.created", "response": {**response, "status": "in_progress", "output": []}}),
            ("response.completed", {"type": "response.completed", "response": response}),
        ]
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "close")
        self.end_headers()
        for name, payload in events:
            self.wfile.write(f"event: {name}\ndata: {json.dumps(payload)}\n\n".encode())
            self.wfile.flush()


provider = http.server.ThreadingHTTPServer(("127.0.0.1", 0), FixtureProvider)
provider.requests = []
provider_thread = threading.Thread(target=provider.serve_forever, daemon=True)
provider_thread.start()


def request(process, identifier, method, parameters):
    if not hasattr(process, "responses"):
        process.responses = queue.Queue()
        process.notifications = []

        def read_responses():
            for line in process.stdout:
                process.responses.put(json.loads(line))
            process.responses.put(None)

        threading.Thread(target=read_responses, daemon=True).start()
    process.stdin.write(json.dumps({"id": identifier, "method": method, "params": parameters}) + "\n")
    process.stdin.flush()
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        try:
            response = process.responses.get(timeout=max(.01, deadline - time.monotonic()))
        except queue.Empty:
            break
        assert response is not None, "native app-server exited before responding"
        if response.get("id") == identifier:
            assert "error" not in response, response
            return response["result"]
        process.notifications.append(response)
    raise AssertionError(f"native {method} timed out")


with tempfile.TemporaryDirectory() as temporary:
    home = Path(temporary).resolve()
    codex_home = home / ".codex"
    codex_home.mkdir()
    config = codex_home / "config.toml"
    # This local SSE provider completes one real native turn without an API key.
    config.write_text(f'''
model = "gpt-6-astra"
thread_unload_delay_secs = 0
model_provider = "hook-fixture"
[model_providers.hook-fixture]
name = "Hook fixture"
base_url = "http://127.0.0.1:{provider.server_port}/v1"
wire_api = "responses"
request_max_retries = 0
stream_max_retries = 0
[features]
plugins = false
apps = false
''')
    environment = {**os.environ, "HOME": str(home), "CODEX_HOME": str(codex_home), "REPO": str(ROOT),
                   "DF_DOTFILES_REPO": str(ROOT), "DF_USE_PLAT": "0", "DF_STATE_ROOT": str(home / "state"),
                   "DF_TASK_STATE_DIR": str(home / "checkpoints"),
                   "PYTHON_ENV": str(home / ".local/python")}
    command = ["/bin/bash", "-c", 'source "$REPO/install/codex.sh"; _sync_hooks']
    subprocess.run(command, env=environment, check=True, capture_output=True, text=True)
    first = config.read_text()
    subprocess.run(command, env=environment, check=True, capture_output=True, text=True)
    assert config.read_text() == first, "hook sync changed an already synced config"
    assert (home / ".local/bin/df-task").is_file()
    assert (home / ".local/lib/dotfiles/df_task.py").is_file()
    python_bin = home / ".local/python/bin"
    python_bin.mkdir(parents=True)
    (python_bin / "python").symlink_to(sys.executable)
    installed = home / ".local/bin/df-task"
    payload = {"session_id": "installed-helper", "hook_event_name": "Interrupt", "cwd": str(home), "turn_id": "turn-1"}
    hook_environment = {**environment, "DF_DOTFILES_REPO": str(home / "unavailable-repository")}
    bash_startup = home / "forbidden-bash-startup"
    bash_startup.write_text("printf 'unexpected Bash startup\\n' >&2; exit 88\n")
    result = subprocess.run([str(installed), "hook"], input=json.dumps(payload),
                            env={**hook_environment, "BASH_ENV": str(bash_startup)},
                            capture_output=True, text=True, check=True, timeout=3)
    assert json.loads(result.stdout) == {} and not result.stderr, result
    assert json.loads((home / "checkpoints/installed-helper.json").read_text())["observed_state"] == "interrupted"
    stub_directory = home / "stub-bin"
    stub_directory.mkdir()
    capture = home / "resume-environment.json"
    stub = stub_directory / "codex"
    stub.write_text(
        f"#!{sys.executable}\nimport json, os, sys\nfrom pathlib import Path\n"
        f"Path({str(capture)!r}).write_text(json.dumps({{"
        "'git_config': os.environ.get('GIT_CONFIG_GLOBAL'), "
        "'cargo_target': os.environ.get('CARGO_TARGET_DIR'), 'arguments': sys.argv[1:]}))\n"
    )
    stub.chmod(0o755)
    for git_config in (None, "", str(home / "custom gitconfig")):
        caller = {**environment, "PATH": str(stub_directory) + os.pathsep + environment["PATH"], "CARGO_TARGET_DIR": "caller-target"}
        caller.pop("GIT_CONFIG_GLOBAL", None)
        if git_config is not None:
            caller["GIT_CONFIG_GLOBAL"] = git_config
        launched = subprocess.run([str(installed), "resume", "--session", "installed-helper", "--launch"],
                                 env=caller, capture_output=True, text=True, timeout=3, check=False)
        assert launched.returncode == 0, launched.stderr
        resumed = json.loads(capture.read_text())
        assert resumed == {"git_config": git_config, "cargo_target": "caller-target",
                           "arguments": ["--cd", str(home), "resume", "installed-helper"]}, resumed
    executable = shutil.which("codex")
    assert executable, "native Codex must be installed for hook trust validation"
    native_environment = hook_environment
    process = subprocess.Popen([executable, "app-server", "--listen", "stdio://"], env=native_environment,
                               stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, cwd=home)
    try:
        request(process, 1, "initialize", {"clientInfo": {"name": "dotfiles-hook-test", "version": "1"},
                                           "capabilities": {"experimentalApi": True}})
        response = request(process, 2, "hooks/list", {"cwds": [str(home)]})
        actual = response["data"][0]
        assert not actual["errors"] and not actual["warnings"], actual
        assert len(actual["hooks"]) == 8, actual
        trust = tomllib.loads(config.read_text())["hooks"]["state"]
        for hook in actual["hooks"]:
            assert hook["trustStatus"] == "trusted", hook
            assert hook["enabled"], hook
            assert trust[hook["key"]]["trusted_hash"] == hook["currentHash"], hook
            if hook["eventName"] != "preToolUse":
                assert hook["timeoutSec"] == 3, hook
        started = request(process, 3, "thread/start", {"cwd": str(home), "ephemeral": True})
        native_id = started["thread"]["id"]
        request(process, 4, "turn/start", {"threadId": native_id, "input": [{"type": "text", "text": "Hook regression fixture", "text_elements": []}]})
        native_checkpoint = home / "checkpoints" / f"{native_id}.json"
        deadline = time.monotonic() + 5
        while not native_checkpoint.exists() and time.monotonic() < deadline:
            try:
                process.notifications.append(process.responses.get(timeout=.02))
            except queue.Empty:
                pass
        assert native_checkpoint.exists(), f"native SessionStart hook did not finish: {process.notifications}"
        native_record = json.loads(native_checkpoint.read_text())
        assert any(event["event"] == "SessionStart" for event in native_record["events"]), native_record
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            native_record = json.loads(native_checkpoint.read_text())
            if any(event["event"] == "Stop" for event in native_record["events"]):
                break
            time.sleep(.02)
        else:
            raise AssertionError(f"native Stop hook did not finish: {native_record}; notifications={process.notifications}")
        # Check the native completion, not just a file written before exit.
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            completed = [event["params"]["run"] for event in process.notifications
                         if event and event.get("method") == "hook/completed"
                         and event["params"]["run"]["eventName"] == "stop"]
            if completed:
                assert completed[-1]["status"] == "completed", completed[-1]
                break
            try:
                process.notifications.append(process.responses.get(timeout=.02))
            except queue.Empty:
                pass
        else:
            raise AssertionError(f"no native Stop completion: {process.notifications}")
        assert provider.requests and provider.requests[0][0].endswith("/responses"), provider.requests
        request(process, 5, "thread/unsubscribe", {"threadId": native_id})
        # Unload runs SessionEnd asynchronously. Let it finish before removing
        # HOME so its atomic checkpoint cannot race TemporaryDirectory cleanup.
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            native_record = json.loads(native_checkpoint.read_text())
            if any(event["event"] == "SessionEnd" for event in native_record["events"]):
                break
            time.sleep(.02)
        else:
            raise AssertionError(f"native SessionEnd did not finish: {native_record}")
    finally:
        process.terminate()
        process.wait(timeout=5)
    profile = tomllib.loads((ROOT / "home/dot_codex/deep.config.toml").read_text())
    assert profile["features"]["prevent_idle_sleep"] is True
    assert profile["model"] == "gpt-6-astra" and profile["model_reasoning_effort"] == "xhigh"
    print("Native Codex verified all 8 hook trust hashes, idempotent sync, installed helper, genuine SessionStart/Stop/SessionEnd hooks, and deep defaults")
provider.shutdown()
provider.server_close()
provider_thread.join(timeout=5)
