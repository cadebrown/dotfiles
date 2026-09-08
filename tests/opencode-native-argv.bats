#!/usr/bin/env bats

@test "installed OpenCode recognizes launcher and shell wrapper subcommands" {
    run uv run --no-project python - "$BATS_TEST_DIRNAME/.." <<'PY'
import importlib.util
import os
from pathlib import Path
import subprocess
import sys

root = Path(sys.argv[1]).resolve()
spec = importlib.util.spec_from_file_location("local_agent", root / "install/local-agent.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
arguments = module.client_arguments("opencode", ["run", "--help"], ["--model", "mlx/local-model"])
result = subprocess.run(["opencode", *arguments], capture_output=True, text=True, timeout=15)
output = result.stdout + result.stderr
assert result.returncode == 0 and output.startswith("opencode run [message..]") and "Commands:" not in output
environment = dict(os.environ, GH_TOKEN="fixture", GOOGLE_MCP_TOKEN="fixture", GOOGLE_CLOUD_PROJECT="fixture")
for shell in ("bash", "zsh"):
    for command in ("run", "models"):
        result = subprocess.run([shell, "-f", "-c", 'source "$1"; shift; _opencode_with_defaults "$@"', "_",
            str(root / "home/.chezmoitemplates/opencode-credentials.sh"), command, "--help"],
            capture_output=True, text=True, env=environment, timeout=15)
        output = result.stdout + result.stderr
        assert result.returncode == 0 and output.startswith("opencode " + command + " ") and "Commands:" not in output, (shell, command)
PY
    [ "$status" -eq 0 ]
}
