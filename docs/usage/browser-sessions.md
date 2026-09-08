# Browser workspaces

`df-browser` wraps the installed Playwright CLI with a stable browser workspace
for each **project + service + host**. An owned workspace has its own persistent
profile, screenshots, traces, and optional private authentication exports. It
does not reuse your normal Chrome profile. This is useful for logged-in services
and local development across agent sessions, including headless Linux work.

## Open, use, and resume

```bash
# The git root is the project binding; outside a repo, the current directory is.
df-browser open dashboard https://example.com --headed
df-browser run dashboard snapshot
df-browser run dashboard click e12
df-browser screenshot dashboard desktop
df-browser close dashboard

# Reuses the same profile and original service URL, headless by default.
df-browser open dashboard
df-browser check dashboard --selector '[data-testid="account-menu"]'
```

Use the service's real signed-in marker for `--selector`. The marker is remembered
for subsequent `check` calls. Ordinary manual login, SSO and MFA work in the
headed profile; closing the browser preserves its cookie database, local storage,
and other persistent browser data. Session-only cookies and sessionStorage follow
the browser's normal lifetime rules and are not guaranteed to survive restart.

Use `--project` before the command to bind the same workspace from any directory:

```bash
df-browser --project ~/dev/my-app open dashboard
df-browser --project ~/dev/my-app status dashboard
df-browser --project ~/dev/my-app list
```

Service names use lowercase letters, digits, underscores and hyphens. A different
project or service gets a different profile. The host component uses Linux's
machine ID or the macOS hardware UUID, falling back to the hostname when
unavailable. Set `DF_BROWSER_HOST_ID` to a stable, unique value on hosts without
either identifier. It also scopes the native CLI session, preventing machines
sharing an NFS home from launching one profile concurrently. Moving or renaming
a project changes its binding; explicitly transfer auth state if needed.

The browser is Chrome by default. Select an installed runtime with
`open ... --browser=firefox`, `--browser=webkit`, or `--browser=msedge` on first use.
The helper does not install browser engines implicitly. A workspace's browser and
ownership mode are fixed; use another service name for a different one.

## Existing authenticated tabs

Use native Codex browser control when working with a user-selected tab in the
app. For terminal agents, install the official
[Playwright Extension](https://playwright.dev/agent-cli/commands/attach#browser-extension)
in the intended Chrome or Edge browser, then explicitly attach:

```bash
df-browser attach account-tab --extension=chrome
df-browser run account-tab snapshot
df-browser run account-tab tab-list
df-browser close account-tab
```

The extension retains its normal browser selection and consent flow. The helper
does not autoattach on startup, launch remote debugging, read a normal browser's
profile directory, or transfer attached account state into an owned profile.
`close` **detaches** an attached workspace and leaves the external browser open.
Use `attach ... --extension` again to reconnect. No global `close-all` or
`kill-all` operation is used.

## Login and expiry observations

`check` returns compact JSON with a timestamp, origin, cookie count and earliest
persistent-cookie expiry, without cookie values. Its status is:

| Status | Observation |
| --- | --- |
| `signed-in` | The configured signed-in marker is visible. |
| `needs-login` | The configured marker is absent, or a password form is visible. |
| `unknown` | Neither condition establishes the account's state. |

A missing marker can also mean navigation is still loading or the selector needs
updating. Cookie expiry cannot prove server-side session validity: services may
revoke sessions sooner or refresh them. `status` shows the **last** observation;
run `check` to refresh it. No credentials are refreshed or entered automatically.

## Private auth transfer

Profiles persist automatically. Storage-state exports happen only when requested,
and only for owned profiles:

```bash
df-browser export-auth dashboard before-migration
# Prints the private JSON file's path, never its contents.
df-browser import-auth another-owned-service /absolute/private/auth.json
df-browser run another-owned-service reload
df-browser check another-owned-service --selector '[data-testid="account-menu"]'
```

Exports are private `0600` files in the workspace's `auth/` directory, outside the
project. Import accepts an existing Playwright storage-state file owned by you
with no group/world permissions; symlinks are refused. Labels cannot overwrite an
existing export. Storage-state transfer follows Playwright's cookie/local-storage
format; it is not a complete browser-profile backup and does not include ordinary
sessionStorage. Do not put these files in Git or include them in task attachments.

## Screenshots, traces, and cleanup

```bash
df-browser trace dashboard start
df-browser run dashboard reload
df-browser screenshot dashboard after-reload
df-browser trace dashboard stop
df-browser view dashboard
df-browser close dashboard
```

`view` opens the Playwright dashboard for interactive observation. To switch an
owned browser between headless and headed modes, close and reopen it with or
without `--headed`. Screenshots require a new label for each capture. Trace
recording is explicit; closing a traced workspace stops the trace first.

State lives under
`${XDG_STATE_HOME:-~/.local/state}/df-browser/<host-hash>/<project-hash>/<service>/`:

| Path | Contents |
| --- | --- |
| `profile/` | Owned browser profile; absent for extension attachment. |
| `artifacts/screenshots/<label>.png` | Named captures. |
| `artifacts/traces/` | Playwright action/network logs and trace resources. |
| `auth/<label>.json` | Explicit storage-state exports. |
| `workspace.json` | Binding, ownership and last auth observation. |

The workspace has mode `0700`. Artifacts remain private because screenshots and
traces can contain authenticated page content and network data. Share only the
specific reviewed artifact. The helper is a lifecycle wrapper, not a sandbox for
arbitrary JavaScript passed to `run ... eval` or `run ... run-code`.

`df-browser remove <service>` deletes that workspace's profile, auth exports and
artifacts. It requires the workspace to be closed first and checks ownership;
sibling sessions and the external attached browser are preserved. Normal `close`
does not delete data.

### Playwright CLI shutdown compatibility

Playwright CLI 0.1.19 has a reproduced shutdown defect on this Mac: its daemon's
context-close handler starts a second shutdown while the first is still closing
Chrome. The second call force-kills Chrome before persistent cookies reach disk.
The profile path and local storage survive, so checking the profile directory
alone misses the lost login.

For an owned session, `close` removes only that source-identified daemon listener
before invoking the normal CLI close command. Playwright's own completion
listeners remain intact. This is a compatibility workaround against the installed
CLI implementation; an unrecognized handler causes a clear error and leaves the
profile open, rather than risking a forced shutdown. Attached browsers only
detach and never use this workaround. Rerun the real-browser fixture after a
Playwright upgrade and remove this adapter once native close preserves cookies.

## Validation

`tests/browser-sessions.bats` checks ownership, scope, private transfer, attachment
and cleanup contracts without requiring a desktop. A disposable real Chrome
fixture validates cookie/local-storage persistence, auth observations, isolation,
explicit transfer, screenshots and traces:

```bash
uv run --no-project python tests/browser-sessions-live.py --artifacts /tmp/browser-evidence
```

It contacts only a temporary localhost server and removes the profiles it owns.
The retained screenshot, trace and JSON result are evidence from synthetic data.
Real extension attachment still requires the user's installed extension and its
native consent flow.

Validated against Playwright CLI 0.1.19. References:
[sessions](https://playwright.dev/agent-cli/sessions),
[attachment](https://playwright.dev/agent-cli/commands/attach), and
[CLI configuration](https://github.com/microsoft/playwright-cli#configuration).
