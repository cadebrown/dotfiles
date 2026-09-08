---
title: Durable tasks and remote boundaries
description: Preserve checkpoints and evidence across interruptions without inventing recovery.
---

## Checkpoint work that must survive a session

`df-task` records native-session checkpoints plus job, log, and artifact registrations. It does not spawn, detach, stop, retry, or infer continuing work.

Run inside a Codex session with `CODEX_THREAD_ID` set, or add `--session ID` using the native session ID. Register paths from your actual run.

```bash
df-task start --title "Validate the import flow" --next "Run the focused browser fixture" \
  --artifact ./artifacts/import.png --log ./artifacts/import.log
df-task checkpoint --note "Fixture reaches confirmation; export needs reopen check" \
  --next "Open the export in the consumer" --artifact ./out/export.glb
df-task status
```

Expected result: the checkpoint lists your next step, logs, and artifacts. To track an existing process, use `df-task job build --pid PID --log ./build.log` with its real PID. PID rechecking distinguishes the original process from a reused PID.

## Resume conservatively

```bash
df-task list
df-task resume --session <native-session-id>
df-task resume --session <native-session-id> --launch
```

The first two commands show saved state and its native resume command. `--launch` opens that command in its recorded directory; it does not submit a prompt or restart a job. Restore a missing worktree explicitly. See [Durable Codex tasks](../usage/durable-tasks.md).

## Separate task, process, and remote host

```mermaid
flowchart TB
  T[Task: intent] --> C[Checkpoint]
  J[Process: PID or handle] --> C
  A[Artifacts and logs] --> C
  R[Remote host or tmux] --> J
  C --> N[Next session: inspect then continue]
```

Record host, command, input revision, output path, last passing check, and inspection command. An agent task, OS process, remote host, SSH connection, `tmux` server, browser, and cloud job are separate stateful systems.

## Keep remote claims narrow

SSH proves the command ran on that host; it does not prove a GUI, durable credentials, propagation, or hardware execution. A cloud MCP profile similarly configures a route, not OAuth, IAM, enabled APIs, or an external write. Restart after MCP or secret changes, and pair claims with current observations. See [Google Cloud MCP credentials](../usage/google-cloud-mcp.md).

## Hooks are checkpoint signals, not an autonomous scheduler

Managed Codex hooks call `df-task hook` at lifecycle events with short timeouts. They record state; they do not decide continuation, restart cancelled jobs, or resume work. Use `long-running-work` with the checkpoint record for a sustained plan.
