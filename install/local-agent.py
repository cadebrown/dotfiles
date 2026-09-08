"""Start an explicitly selected local agent without changing login services."""

import fcntl
import json
import os
from pathlib import Path
import plistlib
import shutil
import signal
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request


def read_json(path):
    return json.loads(path.read_text()) if path.is_file() else {}


def flag(args, *names):
    value = None
    for index, arg in enumerate(args):
        if arg == "--":
            break
        for name in names:
            if arg == name:
                if index + 1 == len(args):
                    raise ValueError(f"{name} needs a value")
                value = args[index + 1]
            elif arg.startswith(name + "="):
                value = arg.split("=", 1)[1]
    return value


def without_model_flags(args):
    result = []
    iterator = iter(args)
    for arg in iterator:
        if arg == "--":
            result.extend([arg, *iterator])
            break
        if arg in ("--provider", "--model", "-m"):
            next(iterator)
        elif not arg.startswith(("--provider=", "--model=", "-m=")):
            result.append(arg)
    return result


def client_arguments(client, args, forced):
    forwarded = without_model_flags(args)
    if client != "opencode":
        return [*forced, *forwarded]
    boundary = forwarded.index("--") if "--" in forwarded else len(forwarded)
    options, prompt = forwarded[:boundary], forwarded[boundary:]
    automatic = [] if any(arg in ("--auto", "--no-auto") or arg.startswith(("--auto=", "--no-auto="))
                          for arg in options) else ["--auto"]
    return [*options, *forced, *automatic, *prompt]


def agent_config(client, args, home, executable):
    if client == "pi":
        directory = Path(os.environ.get("PI_CODING_AGENT_DIR", home / ".pi/agent"))
        config = read_json(directory / "settings.json")
        config.update(read_json(Path.cwd() / ".pi/settings.json"))
        provider = flag(args, "--provider") or config.get("defaultProvider")
        model = flag(args, "--model", "-m") or config.get("defaultModel", "")
        if "/" in model:
            provider, model = model.split("/", 1)
        selection = model
        model = model.split(":", 1)[0]
        entry = read_json(directory / "models.json").get("providers", {}).get(provider, {})
        url = entry.get("baseUrl", "")
        if model not in [item["id"] for item in entry.get("models", [])]:
            raise ValueError("Pi needs an exact configured local model ID")
        forced = ["--provider", provider, "--model", selection]
    else:
        result = subprocess.run([executable, "debug", "config"], check=True,
                                capture_output=True, text=True, timeout=30)
        config = json.loads(result.stdout)
        agent = flag(args, "--agent") or config.get("default_agent", "build")
        selected = config.get("agent", {}).get(agent, {}).get("model")
        model = flag(args, "--model", "-m") or selected or config.get("model", "")
        provider, separator, model = model.partition("/")
        if not separator:
            raise ValueError("OpenCode needs a configured provider/model")
        url = config.get("provider", {}).get(provider, {}).get("options", {}).get("baseURL", "")
        forced = ["--model", f"{provider}/{model}"]
    if provider != "mlx":
        raise ValueError("local-agent requires the mlx provider; use the client directly for cloud models")
    endpoint = urllib.parse.urlparse(url)
    if (endpoint.scheme != "http" or endpoint.hostname not in ("127.0.0.1", "localhost", "::1")
            or endpoint.username or endpoint.password or endpoint.query or endpoint.fragment):
        raise ValueError("The configured MLX endpoint must be an HTTP loopback URL")
    return url.rstrip("/"), model, forced


def models(url):
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    try:
        with opener.open(url + "/models", timeout=2) as response:
            payload = json.load(response)
        return {item["id"] for item in payload["data"]}
    except (urllib.error.URLError, TimeoutError, OSError, ValueError, KeyError, TypeError):
        return None


def occupied(url):
    endpoint = urllib.parse.urlparse(url)
    try:
        with socket.create_connection((endpoint.hostname, endpoint.port or 80), timeout=1):
            return True
    except OSError:
        return False


def identity(pid):
    result = subprocess.run(["ps", "-ww", "-p", str(pid), "-o", "lstart=", "-o", "command="],
                            capture_output=True, text=True, check=False)
    return result.stdout.strip() if result.returncode == 0 else ""


def stop_owned(state):
    receipt = read_json(state / "process.json")
    pid = receipt.get("pid")
    if not pid:
        raise ValueError("No local-agent-owned server; existing services are left running")
    current = identity(pid)
    if not current:
        (state / "process.json").unlink()
        return
    if current != receipt.get("identity"):
        raise ValueError("Saved MLX PID belongs to another process; no signal sent")
    os.kill(pid, signal.SIGTERM)
    for _ in range(100):
        if identity(pid) != current:
            (state / "process.json").unlink()
            return
        time.sleep(0.1)
    raise ValueError("Owned MLX process did not stop after SIGTERM; no forced kill sent")


def ensure_server(url, model, state, plist_path, timeout=180):
    state.mkdir(parents=True, exist_ok=True, mode=0o700)
    with (state / "startup.lock").open("a") as lock:
        deadline = time.monotonic() + timeout
        while True:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.monotonic() >= deadline:
                    raise ValueError("Another local-agent startup is still running")
                time.sleep(0.2)
        current = models(url)
        if current is not None:
            if model not in current:
                raise ValueError(f"The existing endpoint does not serve {model}; no process changed")
            return
        if occupied(url):
            raise ValueError("The configured port is occupied by an unverified server; no process changed")
        receipt = read_json(state / "process.json")
        if receipt.get("pid") and identity(receipt["pid"]) == receipt.get("identity"):
            raise ValueError("An owned MLX process is still starting or unhealthy; inspect its log before restarting")
        if sys.platform != "darwin":
            raise ValueError("MLX startup requires macOS; existing loopback endpoints can still be reused")
        with plist_path.open("rb") as source:
            config = plistlib.load(source)
        argv = config["ProgramArguments"]
        expected = flag(argv, "--served-model-name")
        port = flag(argv, "--port")
        host = flag(argv, "--host")
        endpoint = urllib.parse.urlparse(url)
        if expected != model or int(port or "0") != endpoint.port or host != "127.0.0.1":
            raise ValueError("Agent model/endpoint differs from the managed MLX plist; align them explicitly")
        executable = shutil.which("mlx-openai-server")
        if not executable:
            raise ValueError("mlx-openai-server is missing; install the full Python profile first")
        environment = dict(os.environ)
        environment.setdefault("HF_HOME", config.get("EnvironmentVariables", {}).get("HF_HOME", ""))
        environment.update(HF_HUB_OFFLINE="1", TRANSFORMERS_OFFLINE="1")
        log_path = state / "server.log"
        with log_path.open("ab") as log:
            process = subprocess.Popen([executable, *argv[1:]], stdin=subprocess.DEVNULL,
                                       stdout=log, stderr=log, start_new_session=True,
                                       env=environment, cwd=Path.home())
        for _ in range(20):
            started = identity(process.pid)
            if started:
                break
            time.sleep(0.05)
        receipt = {"pid": process.pid, "identity": started, "url": url, "model": model}
        (state / "process.json").write_text(json.dumps(receipt) + "\n")
        print(f"Starting local {model}; log: {log_path}", file=sys.stderr)
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if process.poll() is not None:
                (state / "process.json").unlink(missing_ok=True)
                raise ValueError(f"MLX exited; inspect {log_path}. Models must be pre-pulled explicitly")
            current = models(url)
            if current is not None and model in current:
                return process
            time.sleep(0.5)
        process.terminate()
        try:
            process.wait(timeout=10)
            (state / "process.json").unlink(missing_ok=True)
        except subprocess.TimeoutExpired:
            raise ValueError(f"MLX readiness timed out and its owned process is still running; inspect {log_path}")
        raise ValueError(f"MLX readiness timed out; inspect {log_path}; no agent was launched")


def main(args):
    if not args or args[0] not in ("pi", "opencode", "status", "stop"):
        raise ValueError("Usage: local-agent pi|opencode [client arguments] | status | stop")
    home = Path.home()
    state = Path(os.environ.get("LOCAL_PLAT", home / ".local")) / "share/mlxserve/on-demand"
    if args[0] == "stop":
        stop_owned(state)
        return
    if args[0] == "status":
        receipt = read_json(state / "process.json")
        print(json.dumps({"owned_process": bool(receipt.get("pid") and identity(receipt["pid"]) == receipt.get("identity")),
                          "endpoint": receipt.get("url"), "model": receipt.get("model")}))
        return
    client, arguments = args[0], args[1:]
    executable = shutil.which(client)
    if not executable:
        raise ValueError(f"{client} is missing; run install/node.sh")
    url, model, forced = agent_config(client, arguments, home, executable)
    process = ensure_server(url, model, state, home / "Library/LaunchAgents/dev.cade.mlxserve.plist",
                            float(os.environ.get("DF_MLX_START_TIMEOUT", "180")))
    if process is not None:
        print("MLX remains available; use local-agent stop when finished", file=sys.stderr)
    os.execv(executable, [executable, *client_arguments(client, arguments, forced)])


if __name__ == "__main__":
    try:
        main(sys.argv[1:])
    except (ValueError, OSError, KeyError, subprocess.SubprocessError) as error:
        print(f"local-agent: {error}", file=sys.stderr)
        sys.exit(1)
