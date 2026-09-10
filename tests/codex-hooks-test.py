import json
import os
import selectors
import shutil
import subprocess
import sys
import tempfile
import time
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def request(process, identifier, method, parameters):
    process.stdin.write(json.dumps({"id": identifier, "method": method, "params": parameters}) + "\n")
    process.stdin.flush()
    deadline = time.monotonic() + 10
    with selectors.DefaultSelector() as selector:
        selector.register(process.stdout, selectors.EVENT_READ)
        while time.monotonic() < deadline:
            if not selector.select(max(0, deadline - time.monotonic())):
                break
            line = process.stdout.readline()
            if not line:
                raise AssertionError("native app-server exited before responding")
            response = json.loads(line)
            if response.get("id") == identifier:
                assert "error" not in response, response
                return response["result"]
    raise AssertionError(f"native {method} timed out")


with tempfile.TemporaryDirectory() as temporary:
    home = Path(temporary).resolve()
    codex_home = home / ".codex"
    codex_home.mkdir()
    config = codex_home / "config.toml"
    config.write_text('model = "gpt-6-astra"\n')
    environment = {**os.environ, "HOME": str(home), "CODEX_HOME": str(codex_home), "REPO": str(ROOT),
                   "DF_DOTFILES_REPO": str(ROOT), "DF_USE_PLAT": "0", "DF_STATE_ROOT": str(home / "state"),
                   "DF_TASK_STATE_DIR": str(home / "checkpoints")}
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
    result = subprocess.run([str(installed), "hook"], input=json.dumps(payload), env=environment,
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
    process = subprocess.Popen([executable, "app-server", "--listen", "stdio://"], env=environment,
                               stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
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
    finally:
        process.terminate()
        process.wait(timeout=5)
    profile = tomllib.loads((ROOT / "home/dot_codex/deep.config.toml").read_text())
    assert profile["features"]["prevent_idle_sleep"] is True
    assert profile["model"] == "gpt-6-astra" and profile["model_reasoning_effort"] == "xhigh"
    print("Native Codex verified all 8 hook trust hashes, idempotent sync, installed helper, and deep defaults")
