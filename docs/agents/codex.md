---
title: Codex profiles and focused roles
description: Select generated session profiles and bounded child roles.
---

## Pick a session profile for the work

Profiles in [`home/dot_codex/`](../../home/dot_codex/) apply when a session starts; they do not retrofit its tool inventory.

| Command | Use | Limit |
| --- | --- | --- |
| `codex` | ordinary implementation | existing sessions retain their inventory |
| `codex -p deep` | demanding implementation or research | wake prevention needs active-client support |
| `codex -p review` | read-only exploration | it does not inspect remote state |
| `codex -p fast` | quick low-risk iteration | Luna serves the whole session |
| `codex -p context` | context-management experiment | support depends on client, account, and rollout |

Codex enables every managed MCP by default. `browser`, `creative`, `desktop`, `research`, `math`, `cloud`, and `workspace` come from the MCP registry and enable their domain on top of the configured baseline. `tools-all` enables every declared server when the baseline has been narrowed. See [AI workbench profiles](../usage/ai-workbench.md).

```bash
env -u DF_MCP_PROFILES bash ~/dotfiles/install/codex.sh sync-config
bash ~/dotfiles/install/codex.sh check
```

Expected result: every managed server is enabled in generated configuration, except entries whose required URL credentials are missing. Subsequent ordinary syncs retain that baseline. `DF_MCP_PROFILES=core` explicitly opts down to core; `DF_MCP_PROFILES=research:math` selects core plus those domains. Separately configured custom servers retain their own enabled state. Restart the harness after changing a pin, environment, or profile; enabling a server does not authenticate it or install its runtime.

## Delegate only an independent bounded unit

Role sources are [`home/dot_codex/agents/`](../../home/dot_codex/agents/); tool scope is [`packages/codex-agent-tools.json`](../../packages/codex-agent-tools.json). Roles are efficiency choices, not security boundaries.

| Role | Good fit |
| --- | --- |
| `extractor` | facts from specified inputs |
| `coder` | exact mapping in named files |
| `explorer` | bounded repository trace |
| `researcher` | current primary-source question |
| `patcher` | bounded behavior contract |
| `verifier` | prescribed checks and edges |
| `reviewer` | adversarial final review |

`extractor` and `coder` use Luna/low; `explorer`, `researcher`, `patcher`, and `verifier` use Terra/medium. `reviewer`, `default`, and `worker` inherit the parent. Those are local manifests, not permanent product guarantees.

## Write a brief the child can finish

```text
Use patcher. Cwd: /absolute/project. Own only src/config.ts and its existing
config tests. Add optional positive-integer timeoutMs, default 30000; reject
zero, negative, fractional, and nonnumeric values through the current API.
Preserve other defaults. Run the existing config tests, log to /tmp/config-check.log,
and return changed files, behavior, checks, artifact path, and unresolved items.
Do not commit or edit other files.
```

Supply scope, contract, acceptance checks, and artifact path. For extraction, give an output schema and reconciliation count; for `coder`, give the exact replacement and require it to report ambiguity. Use a direct command for a one-command transformation; the parent integrates and decides whether independent review is warranted.

## Install and upgrade the native CLI

`codex` links directly to the native executable from the standard platform bin directory
(`$LOCAL_PLAT/bin`, or `~/.local/bin` without platform isolation). The managed
installer owns it; Codex is no longer in the global npm package list.

```sh
bash ~/dotfiles/install/codex.sh install   # retain a working native installation
bash ~/dotfiles/install/codex.sh upgrade   # latest stable release, config and checks
CODEX_VERSION=rust-v0.154.0 bash ~/dotfiles/install/codex.sh install
codex --version
```

The installer selects the complete official `codex-package` archive for the OS
and architecture, verifies its published SHA-256 digest, manifest and executable
version, and checks the code-mode host and bundled resources. It installs the
whole runtime under `$LOCAL_PLAT/lib/codex/<release-tag>` and atomically changes
the bin symlink. Failed checks retain the active runtime. The executable and
`codex-code-mode-host` must stay together; a bare CLI download is insufficient.
An existing process keeps its current executable until restarted; upgrades do
not interrupt tasks. GitHub API access needs `GITHUB_TOKEN` on shared networks
where the anonymous rate limit is exhausted. Exact tags are optional; without
`CODEX_VERSION`, upgrade follows the latest stable release.

The managed bin directory may be on NFS. Atomic replacement avoids mutating an
npm package tree underneath active processes; an open old inode may remain as
an NFS temporary file until its process exits. Do not delete those files or
uninstall the old package tree while clients still use it. Check `type -a codex`
for a stale npm shim taking precedence. The installer replaces its own bin entry after validation and warns about
external npm shims; it does not remove active npm package trees.

Sources: [official Codex CLI documentation](https://learn.chatgpt.com/docs/codex/cli)
and [`install/codex.sh`](../../install/codex.sh).

## Linux descriptor capacity

Linux login and interactive shell startup raise the soft open-file limit to
65,536, capped by the existing hard limit. Higher soft limits remain unchanged;
macOS is unchanged. This applies before SSH-launched app servers start, without
a Codex shell wrapper. Hundreds of active MCP helpers can consume several
parent descriptors each for pipes and process handles; a 1,024 limit can fail
while opening session metadata, CA files, or tool runners.

```sh
ulimit -Sn
ulimit -Hn
```

A fresh SSH login should report a soft limit of 65,536 or the hard cap. Existing
daemons retain their old limits until explicitly adjusted or restarted. Verify
the actual daemon's `/proc/<pid>/limits`, not only the interactive shell. This
provides descriptor capacity; it does not establish that helper growth is bounded.
Source: [`resource-limits.sh`](../../home/.chezmoitemplates/resource-limits.sh).

## MCP credentials on remote Linux hosts

Run `bash ~/dotfiles/install/codex.sh sync-config` on each host after updating
these sources. Linux sync sets the top-level `mcp_oauth_credentials_store =
"file"`; macOS retains its configured storage choice. Login and runtime refresh
then use the private `.credentials.json` in the active `CODEX_HOME`, avoiding an
unavailable or locked desktop keyring. Keep the file mode `0600` and the
host-local runtime directory `0700`. Existing keyring-only logins need a fresh
`codex mcp login <server>`; sync does not copy or delete credentials.

GitHub uses `~/.claude/gh-mcp-headers.sh` at connection time in both Codex and
Claude. It reads explicit `GH_TOKEN`, then `GITHUB_TOKEN`, then `~/.github.env`,
then `gh auth token`. App-server launches therefore do not depend on a shell
function exporting `GH_TOKEN`. No token is embedded in MCP configuration.
The helper fails explicitly when no credential is available.

Restart an affected remote client when it is idle, then verify both `/mcp`
initialization and a read-only tool operation. Saved OAuth metadata or a passing
config parser alone does not establish working access. Missing optional API
keys, Google ADC, or a local server executable still require their own setup.
Increasing `startup_timeout_sec` does not fix these failures.

See [repeated remote MCP warnings](../usage/troubleshooting.md#remote-codex-repeatedly-warns-about-mcp-authentication)
and the [Codex configuration reference](https://developers.openai.com/codex/config-reference/).

## MCP login from SSH

When Codex runs in an SSH shell and the sign-in browser runs on your laptop,
forward the MCP OAuth callback to the workstation. Opening the authorization
link alone does not create that tunnel. SSH agent forwarding (`ForwardAgent`)
is separate from TCP port forwarding.

For a one-off login, use the same unprivileged port on both machines:

```sh
# Laptop: open the SSH shell with its callback tunnel.
ssh -o ExitOnForwardFailure=yes -L 127.0.0.1:45231:127.0.0.1:45231 workstation
# Workstation: start the login, then open its printed URL on the laptop.
codex -c mcp_oauth_callback_port=45231 mcp login cloudflare
```

The browser callback should finish at the workstation's listener, and the CLI
should print `Successfully logged in to MCP server`. Some providers display a
**Finish OAuth** button after sign-in; click it while the CLI is still waiting.

For remote OAuth logins, set
`DF_CODEX_MCP_CALLBACK_PORT=45231` in that workstation's hostname-specific
[host policy](../setup/chezmoi.md#host-configuration), then run
`bash ~/dotfiles/install/codex.sh sync-config` there. Add the matching forward
to the laptop's private SSH overlay or `~/.ssh/config.d/`:

```text
Host workstation-oauth
    HostName workstation
    LocalForward 127.0.0.1:45231 127.0.0.1:45231
    ControlPath /tmp/ssh-codex-oauth-%C
    ExitOnForwardFailure yes
```

Use `ssh workstation-oauth` for login. Keep callback forwards off the ordinary
workstation alias used by the desktop app: separate app-managed SSH connections
can otherwise compete for the same local port during reconnect or restart.
The dedicated control path keeps the OAuth tunnel separate from app transport.

Use a different port for each workstation that can be connected concurrently.
The host setting accepts decimal ports from 1024 through 65535. Without it,
sync preserves an existing callback setting; Codex's default is an OS-selected
port. A server-specific OAuth callback port takes precedence over the global
setting and must match its tunnel too. A fixed port permits one pending login
at a time on that workstation. Reconnect after changing configuration; an
existing multiplexed SSH connection can also receive the configured forward
with `ssh -O forward workstation-oauth`. Do not use `ClearAllForwardings=yes` for the
interactive connection that needs this callback.

The tunnel follows the SSH connection's lifetime. Verify its configured route
with `ssh -G workstation-oauth`, and check the actual local listener with `lsof` or
`ss`. A port already owned by another workstation must not be reused: end that
forward or choose another matching pair. A logged-in status establishes stored
authentication, not access to every tool or permission scope.

Sources: [Codex MCP configuration](https://learn.chatgpt.com/docs/extend/mcp),
[OpenSSH LocalForward](https://man.openbsd.org/ssh_config#LocalForward).

## Host-local state

On a local-home laptop, Codex keeps its normal `~/.codex` layout. On a
shared-home workstation, configure a persistent local `DF_STATE_ROOT` through
[host configuration](../setup/chezmoi.md#host-configuration), then run:

```sh
bash ~/dotfiles/install/host.sh show
bash ~/dotfiles/install/codex.sh sync-runtime
```

The runtime lives at `$DF_STATE_ROOT/codex`. The installer checks ownership,
permissions, and filesystem locality, seeds existing configuration/authentication
without overwriting local choices, and syncs managed instructions, profiles,
roles, rules, themes, and trusted hooks. It does not upgrade packages or delete
the old shared tree. Open a fresh login shell and reconnect the remote desktop
connection after changing its state root.

Plugin caches are separate from task history. Preserve any installed local
marketplace snapshots and their plugin payloads when moving an existing
runtime; restore only those artifact directories into absent destinations,
not the old home wholesale. The desktop can restore account-backed plugins.
Run `bash ~/dotfiles/install/codex.sh check` to verify the declared inventory
as well as configuration. Generated runtime files remain protected by the
dotfiles edit guard; authentication and task data remain writable.

```text
shared configuration + compatible binaries
                 ├─ host A → local CODEX_HOME → local SQLite + socket
                 └─ host B → local CODEX_HOME → local SQLite + socket
```

Moving the home directory does not automatically move live tasks. Before any
migration, stop Codex writers on every host sharing the old root. Make a full
backup to a new directory outside both the source and its symlink targets:

```sh
# Replace these example absolute paths with your chosen backup location.
bash ~/dotfiles/install/codex.sh backup "$HOME/.codex" /backup/codex-before-migration
# If the destination already has data, back it up too before importing.
bash ~/dotfiles/install/codex.sh backup "$CODEX_HOME" /backup/codex-local-before-migration

# Only after each backup reports complete; keep the destination stopped.
bash ~/dotfiles/install/codex.sh import-history /backup/codex-before-migration/sources/codex/tree
```

The backup includes all regular files, including history, configuration,
authentication, attachments, plugin artifacts, and raw SQLite/WAL/SHM bytes.
Files reached through symlinks are copied, not merely linked; a separate
topology inventory preserves the original link targets and file metadata.
Every copy is SHA-256 checked, and a final inventory scan rejects changed
sources. Only `manifest.json` with `status: complete` marks success; an
`INCOMPLETE.json` is not a recoverable snapshot guarantee. Backups are private
(`0700` directories, `0600` files) and contain credentials: never commit or
share them. Original executable modes are recorded in the manifest for restore.
Sockets/FIFOs and dangling links are recorded, not copied as live resources.
This is a file backup of quiescent sources, not a filesystem snapshot or SQLite
repair; even an invalid database is retained byte-for-byte. Network storage is
acceptable for an inert backup, not for the running database.

The importer copies `sessions`, `archived_sessions`, the session index and
prompt history, plus attachments, generated images, and visualizations. It
checks the copied bytes and source stability, and never overwrites an existing
destination file. It does not copy databases, queues, or runnable goals. Keep
the original tree until the imported history has been verified. Re-running is
safe for locally continued transcripts, but is not a synchronization operation.

Do not copy live SQLite databases or share writable session files between
concurrent hosts. Use the app's Handoff workflow for ongoing work across matching saved
projects; it is a transfer, not concurrent multi-host task synchronization.
Database-only metadata may not be recoverable from a transcript alone.

Unknown machines with local homes need no preset. Codex setup on network
storage fails with a configuration action instead of silently using NFS or
temporary storage. Bash and Zsh resolve host policy when the shell starts,
including interactive non-login terminals; `codex` is the native executable,
with no shell-function wrapper. Explicit `CODEX_HOME` overrides remain supported.
After deploying the shell change, start a fresh SSH login. In an existing shell,
`unset -f codex _codex_with_host_env` removes the old loaded functions.
Already-exported runtime values take precedence over host-file edits; changing
the state root requires a fresh SSH login. Direct services must receive
`CODEX_HOME` explicitly because they do not read interactive shell startup files.

Sources: [`install/codex-runtime.sh`](../../install/codex-runtime.sh),
[`install/codex.sh`](../../install/codex.sh),
[`install/codex-history.py`](../../install/codex-history.py),
[`install/codex-backup.py`](../../install/codex-backup.py),
[`Host policy resolver`](../../install/_host-config.sh),
[Codex environment variables](https://learn.chatgpt.com/docs/config-file/environment-variables),
[remote connections](https://learn.chatgpt.com/docs/remote-connections), and
[SQLite WAL](https://sqlite.org/wal.html).

## Official reference

The role design follows [Codex subagents documentation](https://developers.openai.com/codex/subagents/). Verify active-client model and role support before relying on a local manifest in another Codex surface.
