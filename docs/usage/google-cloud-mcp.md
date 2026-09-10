# Google Cloud MCP credentials

`df-google-mcp` keeps the official Cloud Run, Resource Manager, Storage, and
BigQuery MCP servers authenticated throughout a long-running agent session. It
reads existing Application Default Credentials (ADC) and lets Google's auth
library refresh access tokens before HTTP requests. Tokens remain in process
memory; no bearer token is written into an agent configuration.

The shared MCP registry's `auth=gcloud` entries use this stdio launcher across
harnesses. The launcher bridges the official SDK's stdio and Streamable HTTP
transports, preserving upstream tools, resources, prompts, notifications, and
cancellation. The server still determines the tool inventory and permissions.
Google Workspace uses its separate integration and OAuth credentials.

## Use

Normal bootstrap installs the locked Python runtime. This command prepares or
checks it after checking out updated dotfiles:

```sh
df-google-mcp --check-runtime
```

The Python check does not read credentials or contact a Google API. uv may first
download missing locked dependencies; with a populated cache the check works
offline. The underlying bootstrap command (with `_lib.sh` loaded) is:

```sh
UV_CACHE_DIR="${UV_CACHE_DIR:-$LOCAL_PLAT/uv/cache}" \
  uv --quiet run --locked --script "$DF_ROOT/install/google-mcp.py" --check-runtime
```

Harness configuration supplies one endpoint argument:

```sh
df-google-mcp https://run.googleapis.com/mcp
```

The other accepted endpoints are
`https://cloudresourcemanager.googleapis.com/mcp`,
`https://storage.googleapis.com/storage/mcp`, and
`https://bigquery.googleapis.com/mcp`. Arbitrary origins, non-HTTPS URLs,
credentials embedded in URLs, query strings, and fragments are rejected before
ADC is read. The launcher supports flat and PLAT-isolated installations and does
not require a login shell. Its uv cache lives under `$LOCAL_PLAT/uv/cache` unless
`UV_CACHE_DIR` is explicitly set, so PLAT-isolated hosts do not share script
environments containing architecture-specific extensions.
The launcher resolves [per-host configuration](/setup/chezmoi/#host-configuration)
at startup, including private overlay presets and hostname-specific local
overrides. Explicit invocation values take precedence; an unconfigured machine
retains the flat default. This keeps GUI-launched agents on the same runtime
paths as login shells without sourcing interactive shell profiles.

ADC resolution follows `google.auth.default`, including an explicit
`GOOGLE_APPLICATION_CREDENTIALS` file when supplied. Existing ADC from
`gcloud auth application-default login` continues to work. The launcher never
opens a login flow, changes IAM, enables APIs, or changes the gcloud configuration.

The quota project sent in `x-goog-user-project` is chosen in this order:

1. `GOOGLE_CLOUD_QUOTA_PROJECT`.
2. `GOOGLE_CLOUD_PROJECT`.
3. The quota project recorded in ADC.
4. The current project reported by `gcloud config get-value project`, if gcloud
   is available.

If none is available, no quota-project header is invented. Google may reject
requests that require one. Set the appropriate environment variable in the
harness's server environment to select a different project explicitly.

## Failure behavior

Expired tokens are refreshed under a lock, so concurrent tool requests share one
refresh. A refresh failure produces a credential error with no private OAuth
response in the log. The HTTP connect/write timeout is 30 seconds and the read
timeout is 300 seconds; a tool can hold a stream open while working.

A 401 response marks the credentials for refresh before the next request. The
failed request is **not replayed automatically**: a tool may have performed a
mutation before its response was lost. Permission errors and revoked credentials
still require correcting the underlying access or login. A working session no
longer needs an hourly reconnect merely because its original access token expired.

When the harness closes stdin, the relay closes its streams and terminates the
upstream MCP session. Closing a session does not undo completed cloud actions.

## Validation and sources

`bats tests/google-mcp.bats` runs against the runtime's locked dependencies.
It exercises synthetic expired credentials, concurrent refresh, 401 behavior,
endpoint confinement, quota-project precedence, offline preflight, and a real
stdio-to-local-HTTP MCP session. The fixture checks tool calls, resources,
prompts, progress notifications, cancellation, token rotation within one session,
and cleanup after EOF. It never sends real Google credentials to localhost.

The implementation follows the official
[MCP Python transport interfaces](https://github.com/modelcontextprotocol/python-sdk/blob/main/docs/client/transports.md)
and Google's
[credential refresh interface](https://google-auth.readthedocs.io/en/latest/reference/google.auth.credentials.html)
with the standard
[requests transport](https://google-auth.readthedocs.io/en/latest/reference/google.auth.transport.requests.html).
