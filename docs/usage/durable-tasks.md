# Durable Codex tasks

`codex -p deep` keeps the host awake during active turns using Codex's
`features.prevent_idle_sleep` setting. It retains Astra and `xhigh` reasoning.
The sleep assertion ends with active work; it does not keep work alive after a
shutdown or override an explicit sleep. Native Codex still owns execution,
cancellation, and conversation history.

The `df-task` helper keeps a small, private checkpoint beside that native
session. Lifecycle hooks record session and turn IDs, the working directory,
Git worktree location, model, and recent lifecycle events. Hooks preserve
registered job handles, logs, artifacts, and explicit handoff notes through
interruption and compaction. They do not read transcripts, prompts, environment
credentials, or native Codex memory. A stopped turn is not evidence that the
task is complete.

## During a task

Inside a Codex shell, `CODEX_THREAD_ID` supplies the native session ID:

```bash
df-task start --title "Render the scene and verify the export"
df-task checkpoint --note "Scene saved; export needs visual review" \
  --next "Open the render and inspect the camera framing" \
  --artifact ./scene.blend --artifact ./renders/final.png --log ./render.log
df-task job render --pid 12345 --log ./render.log
df-task job build --handle exec:12345 --log ./build.log
df-task status
```

Register an existing process or native tool handle. `df-task` does not spawn,
detach, stop, or retry jobs. PID registration accepts only a live process owned
by the current user and records its start identity. Status rechecks that
identity so an exited job or reused PID is not mistaken for the original job.
Native tool handles are preserved but reported as unverified; inspect them
with the tool that owns them. Exit status and artifact correctness still need
the usual verification.

`start` labels the current session; it does not create another Codex task.
`checkpoint` stores the notes you supply. It does not infer what remains to do.
Use meaningful milestones; keep the project's existing work log for substantial
reasoning and evidence. The command accepts repeated `--artifact` and `--log`
paths, including expected outputs that do not exist yet. No artifact or log
contents are copied.

## After an interruption

```bash
df-task list
df-task resume --session <native-session-id>
df-task resume --session <native-session-id> --launch
```

The first resume command only prints the checkpoint, current process identities,
and a quoted native resume command. `--launch` opens `codex resume` in the saved
working directory, without submitting a prompt or restarting any jobs. Inspect
the saved state and current files before requesting continuation. No hook or
background watcher resumes a cancelled task automatically.

Pass `--session <id>` to any command when outside Codex or when the harness does
not export `CODEX_THREAD_ID`. A removed worktree must be restored before
`--launch`; the helper will not silently switch repositories.

## Storage and hook behavior

State lives under `$XDG_STATE_HOME/dotfiles/tasks/<host-id>` (default
`~/.local/state/dotfiles/tasks/<host-id>`), partitioned by the Linux machine ID
or macOS hostname so machines sharing a home directory do not share PID state.
The checkpoint directory is mode `0700`; records and locks are `0600`.
`DF_TASK_STATE_DIR` explicitly selects a different directory for isolated tests.
Keep that directory outside repositories and cloud-synced folders if your home
directory is synced. Paths and manually entered notes may be private.

Each session has one atomically replaced JSON record and a short-lived file
lock, with at most 32 recent lifecycle events, 64 registered jobs, and 128 each
of artifact and log paths. `list` returns the 20 most recent sessions. Temporary
files left by an abrupt process kill cannot replace a valid checkpoint; later
reads use only the named record. Checkpoint files persist until removed by the
user. They do not edit Codex's native history or memory.

The hooks run at session start, prompt submission, before compaction, turn
stop, interruption, and session end. They return no continuation decision and
add no prompt context. Lock contention and malformed payloads produce a compact
warning rather than blocking Codex. All hook timeouts are three seconds, matching
the native maximum for interruption and session end. CLI checkpoints report
errors with a nonzero exit status and can be retried explicitly.

Install or refresh the managed helper and hooks with
`bash install/codex.sh sync-config`, then apply the static profile with
`chezmoi apply ~/.codex/deep.config.toml`. Restart or open a new Codex session after
syncing. `deep` is selected explicitly with `codex -p deep`; other profiles retain
their existing sleep behavior.

References: [Codex hooks](https://learn.chatgpt.com/docs/hooks),
[configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference),
and [long-running work](https://learn.chatgpt.com/docs/long-running-work).
