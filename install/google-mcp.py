# /// script
# requires-python = ">=3.11"
# dependencies = ["mcp==2.2.0", "google-auth[requests]==2.57.1", "httpx2==2.12.0"]
# ///
"""Relay Google Cloud MCP through stdio with refreshable ADC credentials."""

import argparse
import logging
import os
import shutil
import subprocess
import sys
from contextlib import asynccontextmanager
from urllib.parse import urlsplit

import anyio
import google.auth
import httpx2
import requests
from google.auth.exceptions import GoogleAuthError
from google.auth.transport.requests import Request
from mcp.client.streamable_http import streamable_http_client
from mcp.server.stdio import stdio_server

ENDPOINTS = frozenset({
    "https://run.googleapis.com/mcp",
    "https://cloudresourcemanager.googleapis.com/mcp",
    "https://storage.googleapis.com/storage/mcp",
    "https://bigquery.googleapis.com/mcp",
})
SCOPES = ["https://www.googleapis.com/auth/cloud-platform"]


class AuthenticationError(RuntimeError):
    """A credential operation failed; its private response must not be logged."""


def validate_endpoint(value):
    parsed = urlsplit(value)
    if (value.rstrip("/") not in ENDPOINTS or parsed.query or parsed.fragment
            or parsed.username or parsed.password):
        raise ValueError("use a registered HTTPS Google Cloud MCP endpoint")
    return value


def gcloud_project():
    executable = shutil.which("gcloud")
    if not executable:
        return None
    try:
        result = subprocess.run(
            [executable, "config", "get-value", "project"],
            capture_output=True, text=True, timeout=10, check=False,
            env={**os.environ, "CLOUDSDK_CORE_DISABLE_PROMPTS": "1"},
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    project = result.stdout.strip()
    return project if result.returncode == 0 and project and project != "(unset)" else None


def quota_project(credentials, fallback=gcloud_project):
    return (os.environ.get("GOOGLE_CLOUD_QUOTA_PROJECT")
            or os.environ.get("GOOGLE_CLOUD_PROJECT")
            or getattr(credentials, "quota_project_id", None)
            or fallback())


def load_credentials(request):
    try:
        credentials, _ = google.auth.default(scopes=SCOPES, request=request)
        project = quota_project(credentials)
        if project and hasattr(credentials, "with_quota_project"):
            credentials = credentials.with_quota_project(project)
        return credentials, project
    except (GoogleAuthError, requests.RequestException, OSError, ValueError):
        raise AuthenticationError(
            "cannot load Application Default Credentials; inspect your existing ADC login"
        ) from None


class BoundedRequest(Request):
    def __call__(self, *args, **kwargs):
        kwargs["timeout"] = min(kwargs.get("timeout") or 30, 30)
        return super().__call__(*args, **kwargs)


class CredentialAuth(httpx2.Auth):
    def __init__(self, credentials, request, endpoint, project=None):
        self.credentials = credentials
        self.request = request
        self.endpoint = endpoint.rstrip("/")
        self.project = project
        self.lock = anyio.Lock()
        self.refresh_required = False

    def validate_request(self, request):
        if str(request.url).rstrip("/") != self.endpoint:
            raise AuthenticationError("refusing to send Google credentials outside the MCP endpoint")

    def prepare(self, request):
        headers = {}
        try:
            if self.refresh_required:
                self.credentials.refresh(self.request)
                self.refresh_required = False
            self.credentials.before_request(self.request, request.method, str(request.url), headers)
        except (GoogleAuthError, requests.RequestException, OSError, ValueError):
            raise AuthenticationError(
                "Google ADC refresh failed; inspect your existing ADC login before reconnecting"
            ) from None
        if self.project:
            headers["x-goog-user-project"] = self.project
        request.headers.update(headers)

    async def async_auth_flow(self, request):
        self.validate_request(request)
        async with self.lock:
            await anyio.to_thread.run_sync(self.prepare, request)
        response = yield request
        if response.status_code == 401:
            async with self.lock:
                self.refresh_required = True
            logging.getLogger(__name__).warning(
                "Google MCP rejected credentials (401); the request was not replayed"
            )


async def copy_messages(source, destination, cancel_scope):
    async for message in source:
        if isinstance(message, Exception):
            raise message
        await destination.send(message)
    cancel_scope.cancel()


async def relay(endpoint, http_client, stdio=stdio_server):
    async with (
        stdio() as (local_read, local_write),
        local_read,
        local_write,
        streamable_http_client(endpoint, http_client=http_client) as (remote_read, remote_write),
        anyio.create_task_group() as group,
    ):
        group.start_soon(copy_messages, local_read, remote_write, group.cancel_scope)
        group.start_soon(copy_messages, remote_read, local_write, group.cancel_scope)


@asynccontextmanager
async def authenticated_client(endpoint):
    with requests.Session() as session:
        request = BoundedRequest(session=session)
        credentials, project = await anyio.to_thread.run_sync(load_credentials, request)
        auth = CredentialAuth(credentials, request, endpoint, project)
        async with httpx2.AsyncClient(
            auth=auth,
            timeout=httpx2.Timeout(30, read=300),
            follow_redirects=False,
            event_hooks={"request": [auth_guard(auth)]},
        ) as client:
            yield client


def auth_guard(auth):
    async def check(request):
        auth.validate_request(request)
    return check


async def run(endpoint):
    async with authenticated_client(endpoint) as client:
        await relay(endpoint, client)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("endpoint", nargs="?")
    parser.add_argument("--check-runtime", action="store_true", help="check locked dependencies without credentials or network")
    args = parser.parse_args()
    if args.endpoint:
        try:
            validate_endpoint(args.endpoint)
        except ValueError as error:
            parser.error(str(error))
    if args.check_runtime:
        print("Google MCP runtime ready")
        return 0
    if not args.endpoint:
        parser.error("a Google Cloud MCP endpoint is required")
    logging.basicConfig(level=logging.WARNING, format="df-google-mcp: %(message)s")
    try:
        anyio.run(run, args.endpoint)
    except KeyboardInterrupt:
        return 130
    except (ExceptionGroup, AuthenticationError, httpx2.HTTPError, OSError, ValueError):
        # Credential provider exceptions can contain private OAuth response bodies.
        print("df-google-mcp: connection failed; check ADC credentials, project access, and connectivity", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
