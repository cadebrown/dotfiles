"""Run disposable local-browser persistence, isolation, auth and artifact checks."""

import argparse
import functools
import json
import os
import shutil
import struct
import subprocess
import sys
import tempfile
import threading
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

HELPER = Path(__file__).resolve().parents[1] / "home/dot_local/bin/executable_df-browser"
PAGE = """<!doctype html><html lang="en"><meta charset="utf-8">
<title>Browser workspace validation</title><style>
body{font:20px system-ui;background:#112033;color:#e9effa;padding:5rem;max-width:50rem}
button,input{font:inherit;padding:.7rem 1rem;margin:.4rem 0}small{color:#a4b9d5}
</style><h1>Persistent browser workspace</h1><p id="status"></p>
<section id="member" hidden><h2>Signed in to the local fixture</h2>
<p>Cookie and local storage survived the browser restart.</p></section>
<section id="login"><label>Password <input type="password" autocomplete="current-password"></label>
<button id="signin">Sign in to fixture</button></section><small>No external account is used.</small>
<script>
function render(){ const ready=document.cookie.includes('df_fixture=fixture-only')&&localStorage.getItem('theme')==='midnight';
 document.querySelector('#member').hidden=!ready;document.querySelector('#login').hidden=ready;
 document.querySelector('#status').textContent=ready?'Session restored':'Sign in to begin'; }
document.querySelector('#signin').onclick=()=>{document.cookie='df_fixture=fixture-only; Max-Age=3600; SameSite=Lax; path=/';localStorage.setItem('theme','midnight');render()};render();
</script></html>"""


class QuietHandler(SimpleHTTPRequestHandler):
    def log_message(self, *_args):
        pass


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--artifacts", type=Path, help="Parent directory for the evidence folder")
    args = parser.parse_args()
    if args.artifacts:
        args.artifacts.mkdir(parents=True, exist_ok=True)
    root = Path(tempfile.mkdtemp(prefix="browser-sessions-", dir=args.artifacts)).resolve()
    root.chmod(0o700)
    project = root / "project"
    project.mkdir()
    (project / "index.html").write_text(PAGE)
    server = ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(QuietHandler, directory=str(project)))
    threading.Thread(target=server.serve_forever, daemon=True).start()
    url = f"http://127.0.0.1:{server.server_port}"
    environment = dict(os.environ, XDG_STATE_HOME=str(root / "state"))
    commands = []

    def run(*arguments):
        result = subprocess.run([sys.executable, str(HELPER), "--project", str(project), *arguments],
                                capture_output=True, text=True, env=environment, timeout=150, check=False)
        if result.returncode:
            raise AssertionError(f"{arguments[0]} failed: {result.stdout}{result.stderr}")
        response = json.loads(result.stdout)
        commands.append({"command": arguments[0], "service": arguments[1], "result": response})
        return response

    names = []
    try:
        for service in ("primary", "isolated"):
            opened = run("open", service, url, *(["--headed"] if service == "primary" else []))
            assert opened["headed"] == (service == "primary")
            names.append(service)
        initial = run("check", "primary", "--selector", "#member")
        assert initial["status"] == "needs-login", initial
        run("run", "primary", "run-code", "async page => { await page.locator('#signin').click(); }")
        assert run("check", "primary")["status"] == "signed-in"
        before = run("status", "primary")
        run("close", "primary")
        after = run("open", "primary")
        assert after["headed"] is False
        assert before["session"] == after["session"] and before["profile"] == after["profile"]
        restored = run("check", "primary")
        assert restored["status"] == "signed-in" and restored["cookie_count"] == 1, restored
        assert restored["earliest_cookie_expiry"], restored
        isolated = run("check", "isolated", "--selector", "#member")
        assert isolated["status"] == "needs-login" and isolated["cookie_count"] == 0, isolated
        assert run("status", "isolated")["profile"] != after["profile"]
        exported = Path(run("export-auth", "primary", "fixture")["auth_file"])
        assert exported.stat().st_mode & 0o777 == 0o600
        run("import-auth", "isolated", str(exported))
        run("run", "isolated", "reload")
        assert run("check", "isolated")["status"] == "signed-in"
        run("trace", "primary", "start")
        run("run", "primary", "reload")
        screenshot = Path(run("screenshot", "primary", "restored")["screenshot"])
        width, height = struct.unpack(">II", screenshot.read_bytes()[16:24])
        assert width >= 800 and height >= 600, (width, height)
        traces = Path(run("trace", "primary", "stop")["directory"])
        assert list(traces.glob("*.trace")) and list(traces.glob("*.network")), traces
        evidence = root / "evidence"
        evidence.mkdir(mode=0o700)
        shutil.copy2(screenshot, evidence / "restored.png")
        shutil.copytree(traces, evidence / "traces")
        assert "fixture-only" not in json.dumps(commands), "Authentication value leaked into command output"
        result = {"passed": True, "checks": ["persistent cookie and localStorage survive restart", "service profile isolation",
                  "signed-in and needs-login observations", "private explicit auth export/import", "screenshot dimensions",
                  "trace and network artifact paths", "owned-session close/remove cleanup"],
                  "browser": "Chrome", "playwright_cli": subprocess.check_output(["playwright-cli", "--version"], text=True).strip(),
                  "screenshot": str(evidence / "restored.png"), "traces": str(evidence / "traces")}
    finally:
        for service in names:
            run("close", service)
            run("remove", service)
        server.shutdown()
        server.server_close()
    (root / "results.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
