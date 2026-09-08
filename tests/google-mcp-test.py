"""Google transport integration tests; every credential in this file is synthetic."""

import asyncio
import importlib.util
import logging
import os
import socket
import subprocess
import sys
import unittest
from contextlib import asynccontextmanager
from datetime import UTC, datetime, timedelta
from pathlib import Path
from unittest.mock import patch

import anyio
import httpx2
import uvicorn
from google.auth.credentials import Credentials
from google.auth.exceptions import RefreshError
from mcp import Client, StdioServerParameters
from mcp.server import MCPServer
from mcp.server.mcpserver import Context
from starlette.responses import Response

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("google_mcp", ROOT / "install/google-mcp.py")
relay = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(relay)


def utcnow():
    return datetime.now(UTC).replace(tzinfo=None)


class FixtureCredentials(Credentials):
    def __init__(self, expire_again=False, fail=False):
        super().__init__()
        self.expiry = utcnow() - timedelta(hours=1)
        self.refreshes = 0
        self.requests = 0
        self.expire_again = expire_again
        self.fail = fail

    def refresh(self, request):
        if self.fail:
            raise RefreshError("private-refresh-token-do-not-log")
        self.refreshes += 1
        self.token = f"fixture-token-{self.refreshes}"
        self.expiry = utcnow() + timedelta(hours=1)

    def before_request(self, request, method, url, headers):
        self.requests += 1
        if self.expire_again and self.requests == 5:
            self.expiry = utcnow() - timedelta(hours=1)
        super().before_request(request, method, url, headers)


@asynccontextmanager
async def fixture_server():
    server = MCPServer("refresh-fixture")
    observed = []
    state = {"started": False, "cancelled": False}

    @server.tool()
    async def add(left: int, right: int, ctx: Context) -> int:
        await ctx.report_progress(1, 1, "added")
        return left + right

    @server.tool()
    async def wait_forever() -> str:
        state["started"] = True
        try:
            await anyio.sleep_forever()
        finally:
            state["cancelled"] = True

    @server.resource("fixture://status")
    def status() -> str:
        return "ready"

    @server.prompt()
    def welcome(name: str) -> str:
        return f"Hello {name}"

    app = server.streamable_http_app()

    async def record(scope, receive, send):
        if scope["type"] == "http":
            headers = dict(scope["headers"])
            observed.append((scope["method"], headers))
            if not headers.get(b"authorization", b"").startswith(b"Bearer fixture-token-"):
                await Response(status_code=401)(scope, receive, send)
                return
        await app(scope, receive, send)

    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        listener.listen()
        port = listener.getsockname()[1]
        running = uvicorn.Server(uvicorn.Config(record, log_level="error", access_log=False))
        task = asyncio.create_task(running.serve(sockets=[listener]))
        try:
            with anyio.fail_after(5):
                while not running.started:
                    await anyio.sleep(0.01)
            yield f"http://127.0.0.1:{port}/mcp", observed, state
        finally:
            running.should_exit = True
            with anyio.fail_after(5):
                await task


async def fixture_relay(endpoint):
    credentials = FixtureCredentials(expire_again=True)
    auth = relay.CredentialAuth(credentials, None, endpoint, "fixture-quota")
    async with httpx2.AsyncClient(auth=auth, timeout=httpx2.Timeout(5, read=30)) as client:
        await relay.relay(endpoint, client)


class AuthTests(unittest.IsolatedAsyncioTestCase):
    async def test_expired_and_concurrent_credentials_refresh_once(self):
        credentials = FixtureCredentials()
        calls = []

        async def record(request):
            calls.append(request.headers["authorization"])
            return httpx2.Response(200)

        endpoint = "https://run.googleapis.com/mcp"
        auth = relay.CredentialAuth(credentials, None, endpoint)
        async with httpx2.AsyncClient(auth=auth, transport=httpx2.MockTransport(record)) as client:
            await asyncio.gather(*(client.post(endpoint, json={}) for _ in range(5)))
            self.assertEqual(credentials.refreshes, 1)
            credentials.expiry = utcnow() - timedelta(hours=1)
            await client.post(endpoint, json={})
        self.assertEqual(calls, ["Bearer fixture-token-1"] * 5 + ["Bearer fixture-token-2"])

    async def test_401_does_not_replay_mutation_and_next_request_refreshes(self):
        credentials = FixtureCredentials()
        calls = []

        async def reject(request):
            calls.append(request.headers["authorization"])
            return httpx2.Response(401)

        endpoint = "https://run.googleapis.com/mcp"
        auth = relay.CredentialAuth(credentials, None, endpoint)
        async with httpx2.AsyncClient(auth=auth, transport=httpx2.MockTransport(reject)) as client:
            response = await client.post(endpoint, json={"method": "tools/call"})
            self.assertEqual(response.status_code, 401)
            self.assertEqual(len(calls), 1)
            await client.post(endpoint, json={"method": "tools/list"})
        self.assertEqual(calls, ["Bearer fixture-token-1", "Bearer fixture-token-2"])

    async def test_auth_failure_has_no_credential_details_and_sends_nothing(self):
        sent = []
        endpoint = "https://run.googleapis.com/mcp"
        auth = relay.CredentialAuth(FixtureCredentials(fail=True), None, endpoint)

        async def record(request):
            sent.append(request)
            return httpx2.Response(200)

        async with httpx2.AsyncClient(auth=auth, transport=httpx2.MockTransport(record)) as client:
            with self.assertRaises(relay.AuthenticationError) as caught:
                await client.post(endpoint, json={})
        self.assertNotIn("private-refresh-token", str(caught.exception))
        self.assertEqual(sent, [])

    async def test_credentials_are_not_sent_to_other_paths_or_origins(self):
        endpoint = "https://run.googleapis.com/mcp"
        auth = relay.CredentialAuth(FixtureCredentials(), None, endpoint)
        async with httpx2.AsyncClient(auth=auth) as client:
            for url in ("http://run.googleapis.com/mcp", "https://example.com/mcp", endpoint + "?token=x", "https://run.googleapis.com/other"):
                with self.assertRaises(relay.AuthenticationError):
                    await client.post(url, json={})

    def test_production_endpoint_validation(self):
        for endpoint in relay.ENDPOINTS:
            self.assertEqual(relay.validate_endpoint(endpoint), endpoint)
        for endpoint in ("http://127.0.0.1/mcp", "https://run.googleapis.com.evil.test/mcp", "https://run.googleapis.com/mcp?x=1", "https://user:password@run.googleapis.com/mcp"):
            with self.assertRaises(ValueError):
                relay.validate_endpoint(endpoint)

    async def test_redirect_cannot_forward_auth_to_another_path(self):
        endpoint = "https://run.googleapis.com/mcp"
        auth = relay.CredentialAuth(FixtureCredentials(), None, endpoint)
        calls = []

        async def redirect(request):
            calls.append(str(request.url))
            return httpx2.Response(307, headers={"location": "/other"})

        async with httpx2.AsyncClient(
                auth=auth, transport=httpx2.MockTransport(redirect), follow_redirects=True,
                event_hooks={"request": [relay.auth_guard(auth)]}) as client:
            with self.assertRaises(relay.AuthenticationError):
                await client.post(endpoint, json={})
        self.assertEqual(calls, [endpoint])

    def test_quota_precedence_and_no_unnecessary_gcloud_process(self):
        class ADC:
            quota_project_id = "adc-project"

        def unexpected():
            self.fail("gcloud should not run when a quota project is known")

        with patch.dict(os.environ, {}, clear=True):
            self.assertEqual(relay.quota_project(ADC(), unexpected), "adc-project")
            with patch.dict(os.environ, {"GOOGLE_CLOUD_PROJECT": "explicit-project"}):
                self.assertEqual(relay.quota_project(ADC(), unexpected), "explicit-project")
                with patch.dict(os.environ, {"GOOGLE_CLOUD_QUOTA_PROJECT": "explicit-quota"}):
                    self.assertEqual(relay.quota_project(ADC(), unexpected), "explicit-quota")
            self.assertEqual(relay.quota_project(object(), lambda: "gcloud-project"), "gcloud-project")

    async def test_real_stdio_http_roundtrip_refresh_resources_prompts_and_eof(self):
        async with fixture_server() as (endpoint, observed, state):
            parameters = StdioServerParameters(
                command=sys.executable,
                args=[str(Path(__file__).resolve()), "--fixture", endpoint],
            )
            with anyio.fail_after(20):
                async with Client(parameters) as client:
                    tools = await client.list_tools()
                    self.assertEqual([tool.name for tool in tools.tools], ["add", "wait_forever"])
                    progress = []

                    async def record_progress(value, total, message):
                        progress.append((value, total, message))

                    for _ in range(2):
                        result = await client.call_tool("add", {"left": 2, "right": 3}, progress_callback=record_progress)
                        self.assertFalse(result.is_error)
                        self.assertIn("5", str(result))
                    resources = await client.list_resources()
                    self.assertEqual(str(resources.resources[0].uri), "fixture://status")
                    resource = await client.read_resource("fixture://status")
                    self.assertEqual(resource.contents[0].text, "ready")
                    prompts = await client.list_prompts()
                    self.assertEqual(prompts.prompts[0].name, "welcome")
                    prompt = await client.get_prompt("welcome", {"name": "Agent"})
                    self.assertEqual(prompt.messages[0].content.text, "Hello Agent")
                    self.assertEqual(progress, [(1, 1, "added"), (1, 1, "added")])
                    with anyio.move_on_after(0.2):
                        await client.call_tool("wait_forever", {})
                    while not state["cancelled"]:
                        await anyio.sleep(0.01)
                    self.assertTrue(state["started"])
            tokens = {headers[b"authorization"] for _, headers in observed}
            self.assertEqual(tokens, {b"Bearer fixture-token-1", b"Bearer fixture-token-2"})
            self.assertTrue(all(headers[b"x-goog-user-project"] == b"fixture-quota" for _, headers in observed))
            self.assertEqual(sum(method == "DELETE" for method, _ in observed), 1)
            sessions = {headers[b"mcp-session-id"] for _, headers in observed if b"mcp-session-id" in headers}
            self.assertEqual(len(sessions), 1)

    def test_cli_preflight_is_offline_and_invalid_endpoint_is_stderr_only(self):
        environment = {**os.environ, "GOOGLE_APPLICATION_CREDENTIALS": "/missing/fixture-adc.json"}
        ready = subprocess.run([sys.executable, str(ROOT / "install/google-mcp.py"), "--check-runtime"], capture_output=True, text=True, env=environment, timeout=10, check=False)
        self.assertEqual(ready.returncode, 0, ready.stderr)
        invalid = subprocess.run([sys.executable, str(ROOT / "install/google-mcp.py"), "http://localhost/mcp"], capture_output=True, text=True, env=environment, timeout=10, check=False)
        self.assertNotEqual(invalid.returncode, 0)
        self.assertEqual(invalid.stdout, "")
        private_url = subprocess.run([sys.executable, str(ROOT / "install/google-mcp.py"), "https://user:fixture-private-password@run.googleapis.com/mcp"], capture_output=True, text=True, env=environment, timeout=10, check=False)
        self.assertNotEqual(private_url.returncode, 0)
        self.assertNotIn("fixture-private-password", private_url.stdout + private_url.stderr)
        missing = subprocess.run([sys.executable, str(ROOT / "install/google-mcp.py"), "https://run.googleapis.com/mcp"], capture_output=True, text=True, env=environment, timeout=10, check=False)
        self.assertEqual(missing.returncode, 1)
        self.assertEqual(missing.stdout, "")
        self.assertNotIn("Traceback", missing.stderr)


if __name__ == "__main__":
    logging.basicConfig(level=logging.ERROR)
    if len(sys.argv) == 3 and sys.argv[1] == "--fixture":
        anyio.run(fixture_relay, sys.argv[2])
    else:
        unittest.main()
