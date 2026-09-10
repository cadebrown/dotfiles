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

`browser`, `creative`, `desktop`, `research`, `math`, `cloud`, and `workspace` come from the MCP registry; choose one only for its needed tool surface. `tools-all` intentionally exposes every declared server. See [AI workbench profiles](../usage/ai-workbench.md).

```bash
DF_MCP_PROFILES=research:math bash ~/dotfiles/install/codex.sh sync-config
bash ~/dotfiles/install/codex.sh check
```

Expected result: generated configuration passes its check for future sessions. Run sync without `DF_MCP_PROFILES` to restore core activation, then restart the harness after changing a pin, environment, or profile.

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
temporary storage. Bash and Zsh `codex` functions resolve host policy at launch,
including in non-login shells, and preserve an explicit `CODEX_HOME`. Existing
terminals retain their already-loaded functions: start a new shell or run
`exec zsh -l` (or `exec bash -l`) once after deploying a launcher change.
Already-exported runtime values take precedence over host-file edits; changing
the state root requires a fresh SSH login, not just replacing the current shell
and inheriting its environment. Direct
services and vendor-binary launches bypassing these functions must still receive
`CODEX_HOME` explicitly. Do not overwrite npm's Codex binary to change its home.

Sources: [`install/codex-runtime.sh`](../../install/codex-runtime.sh),
[`install/codex.sh`](../../install/codex.sh),
[`install/codex-history.py`](../../install/codex-history.py),
[`install/codex-backup.py`](../../install/codex-backup.py),
[`Codex shell launcher`](../../home/.chezmoitemplates/codex-launch.sh),
[Codex environment variables](https://learn.chatgpt.com/docs/config-file/environment-variables),
[remote connections](https://learn.chatgpt.com/docs/remote-connections), and
[SQLite WAL](https://sqlite.org/wal.html).

## Official reference

The role design follows [Codex subagents documentation](https://developers.openai.com/codex/subagents/). Verify active-client model and role support before relying on a local manifest in another Codex surface.
