# Google Workspace

Use the managed `google-workspace` MCP for cross-harness Gmail, Calendar,
Drive, Docs, Slides, and Sheets work. It is an external-write integration:
creating, editing, sending, moving, or deleting Workspace data is controlled by
the selected tool and the Google account's permissions.

## Configure a Desktop OAuth client

Create a Desktop OAuth client in a Google Cloud project, add yourself to the
consent screen's test users when required, and enable only the Workspace APIs
you intend to use. Then save the client ID and secret in the owner-only
`~/.google.env` file:

```sh
bash ~/dotfiles/install/auth.sh workspace
```

The helper writes only `GOOGLE_OAUTH_CLIENT_ID` and
`GOOGLE_OAUTH_CLIENT_SECRET`; it preserves other exports in that file and never
prints either value. It does not use gcloud's generic OAuth client because
restricted Workspace scopes require your project's Desktop client.

## Choose a narrow CLI consent

Use the read command for the existing mail and scheduling workflow:

```sh
bash ~/dotfiles/install/auth.sh workspace-cli
```

Expected result: `gws` opens its own consent flow for read-only Drive, Gmail,
and Calendar scopes. For document editing, run the separate command:

```sh
bash ~/dotfiles/install/auth.sh workspace-cli-edit
```

Expected result: `gws` requests the selected Drive, Docs, Slides, and Sheets
scopes. Review the browser consent screen before completing it. The helper does
not run `gws auth setup`, which can create Cloud state and enable APIs. It also
does not replace `~/.google.env`; gws stores its credentials under
`~/.config/gws`, while Workspace MCP stores its credentials under
`~/.google_workspace_mcp/credentials`.

`workspace-cli-edit` writes gws's own grant and may replace its previous
selected-scope grant. Decide on the full gws scope set before consenting again;
preserving unrelated exports in `~/.google.env` does not preserve a prior gws
grant. The upstream CLI and MCP handle their normal pagination and revision
fallback behavior.

## Enable the MCP in each harness

The shared registry launches the managed `df-workspace-mcp` wrapper. It loads
the owner-only OAuth client environment for desktop-launched clients, while
preserving explicitly supplied client IDs, secrets, and client-secret-file
mechanisms. It resolves the managed `uvx`, then pins `workspace-mcp==1.26.2`,
selects Gmail, Calendar, Drive, Docs, Slides, and Sheets, and passes
`--tool-tier complete`. Sync the managed configuration after the OAuth client
exists:

```sh
bash ~/dotfiles/install/claude.sh sync-mcp
bash ~/dotfiles/install/codex.sh sync-config
bash ~/dotfiles/install/cursor.sh sync-mcp
bash ~/dotfiles/install/opencode.sh sync-config
```

Expected result: each configured harness has a `google-workspace` entry in its
workspace profile. This proves configuration only. Start a fresh client session
and make a harmless account-authorized operation before treating it as working.
The MCP is a community server; its behavior does not describe the availability
or write surface of Google's official Workspace MCP. The current configuration
and launcher do not prove that the OAuth client, gws grant, or Workspace API
permissions are present.

For native Docs, Sheets, and Slides authoring and review, follow the shared
[Google Workspace workflow skill](../../home/dot_claude/skills/google-workspace-flow/SKILL.md).

## Sources and validation

The source of truth is [the shared MCP registry](../../packages/mcp-servers.txt)
and [the auth helper](../../install/auth.sh). The wrapper source is
[df-workspace-mcp](../../home/dot_local/bin/executable_df-workspace-mcp). The CLI package is pinned in
[packages/npm.txt](../../packages/npm.txt); the authoring procedure is the
[shared workflow skill](../../home/dot_claude/skills/google-workspace-flow/SKILL.md). Run:

```sh
bats tests/google-auth.bats tests/workspace-mcp.bats
./tests/ci.sh docs
```

The auth fixture checks read and edit scope dispatch, no automatic `gws auth
setup`, preservation of unrelated `.google.env` exports, and no client secret
in output. It does not perform a browser OAuth flow or prove API permission.
