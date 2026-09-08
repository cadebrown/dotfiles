---
name: long-running-work
description: Carry sustained research and implementation across interruptions, context windows, parallel agents, and remote sessions with resumable project state and verified artifacts.
---

# Long-running research and implementation

Keep the outcome and definition of done visible while using the strongest
available project tools. Work through research, implementation, and verification
until the requested result exists. Preserve user steering in the same task.

Use existing project planning/state files. When sustained work needs a durable
handoff and none exists, create a small `WORKLOG.md` with the objective,
constraints, current state, decisions, artifact paths, successful verification,
and next action. Update it at meaningful checkpoints and before an interruption;
do not turn every command into paperwork. Keep secrets and private source content
out of public project artifacts.

For research, save stable source URLs/identifiers, access date, and the particular
claims supported. Keep inference, numerical evidence, reproduction, and proof
distinct. Use the available literature/search/CAS/prover integrations rather
than substituting an unsourced narrative. Research should inform a concrete
experiment or implementation when that is part of the request.

For coding, render/export, or data work, choose restartable operations. Persist
the meaningful state before advancing: source revision, inputs, output paths,
and completed units. After resume, inspect current files and processes before
rerunning work; a session summary may be stale. Confirm completion by opening
the artifact or exercising its consumer, not by checking that a process exited.

Delegate bounded independent research, implementation, or review when authorized
and useful. Give each worker explicit ownership and collect every result before
claiming completion. Keep overlapping edits together. An independent review
should test the result against the original request, not repeat the author's
completion claim.

Use the host's actual persistence capabilities:

- Codex Goal mode when the user explicitly requests a goal; define its real
  completion criteria and budget only when requested. A long task alone is not
  permission to create a goal or recurring automation.
- Codex task steering/resume for continuing the same work. For scripted work,
  `codex exec --json -o last-message.md` captures events, and
  `codex exec resume <session-id>` continues the recorded session. Save the
  session ID from the emitted `thread.started` event with project state. Run
  resume from the project directory (or set `codex exec --cd <project> resume`):
  the caller's working directory can determine writable sandbox roots even
  when the saved conversation concerns a different project.
- Native scheduled tasks when the user asks to monitor, repeat, or return later.
  Notify for meaningful changes, failure, completion, or required decisions.
- SSH with `tmux` on a persistent Linux host for builds, experiments, and renders;
  use the available `tmux` skill for session control. Local app/Goal execution
  still needs its host available. Do not promise work continues after shutdown.

These are separate mechanisms: detached processes keep running; checkpoints
recover state; schedulers start later runs; Goal mode pursues an explicit
objective. Pick what the task needs and verify the actual mechanism is active.

On this dotfiles setup, `df-task checkpoint --note "..." --next "..."` records
an explicit handoff, and `df-task job render --pid <pid> --log <path>` records an
existing job. Both use `CODEX_THREAD_ID`, or an explicit `--session <id>`.
`df-task resume --session <id>` inspects the checkpoint and current job identities.
Lifecycle hooks record interruptions and compaction, not semantic progress;
they never restart work. See `~/dotfiles/docs/usage/durable-tasks.md` for details.

Current references: [long-running work](https://learn.chatgpt.com/docs/long-running-work)
and [non-interactive Codex](https://learn.chatgpt.com/docs/non-interactive-mode).
