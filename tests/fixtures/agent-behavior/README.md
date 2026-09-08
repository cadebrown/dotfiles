# Paired instruction behavior checks

Compare two global `AGENTS.md` revisions using the same Codex binary, GPT-6 Astra,
reasoning effort, fixtures, and tools. This is a small local experiment, not a
general model benchmark or a quality score. `prepare` performs no inference;
`run` consumes real model usage.

```bash
uv run --no-project tests/agent_behavior.py prepare \
  --baseline /absolute/baseline-AGENTS.md \
  --candidate /absolute/candidate-AGENTS.md \
  --output /absolute/new-experiment \
  --model gpt-6-astra --effort xhigh \
  --cases coding research resume

uv run --no-project tests/agent_behavior.py run /absolute/new-experiment/experiment.json baseline coding
uv run --no-project tests/agent_behavior.py run /absolute/new-experiment/experiment.json candidate coding
```

Use `research`, `browser`, or `resume` in place of `coding`. Alternate the order
of baseline and candidate in subsequent repeats; use a new experiment directory
each time. `--cases` selects a bounded subset. Optional `--skill /absolute/skill`
copies identical selected skills into both variants. The default comparison
includes only the system skills supplied by the pinned local Codex binary.
Optional `--agent-dir /absolute/rendered-agent-roles` snapshots that directory's
`*.toml` role files into the experiment and installs identical copies in both
isolated Codex homes. Use rendered agent TOML, not chezmoi templates. Their hashes
join the existing control inventory, so edits after preparation reject a run.
Supplying roles enables `multi_agent_v2` and caps concurrent children at two.
The ordinary default cases and no-role configuration remain unchanged.

For the browser case, pass `--browser-modules /project/node_modules` during
preparation, where `@playwright/test` is already installed. Set
`PLAYWRIGHT_BROWSERS_PATH=/absolute/browser-cache` on both run commands if the
browser binaries normally live under your real home. On this macOS setup the
cache is `~/Library/Caches/ms-playwright`. The helper records that explicit path.
It does not install browsers or packages. A missing executable is an environment
failure, not a skill-quality result.

Each variant/case gets a fresh workspace, `HOME`, `CODEX_HOME`, and XDG paths
outside the dotfiles tree. Runtime paths are canonicalized so macOS `/var` and
`/private/var` aliases cannot disagree with the sandbox's writable roots.
Ancestor instruction/config files cause preparation
to fail. No user config, MCP, plugins, hooks, memory, or third-party skills are
copied automatically. Explicitly supplied skills and agent role files are the
exceptions; role files can themselves configure MCP servers or other tools and
contain credentials. Supplied roles are copied verbatim with mode `0600`, and
new result directories use mode `0700`; inspect and sanitize configs before
sharing artifacts. The chosen global instructions and a minimal explicit configuration
are installed in the isolated home. `codex debug prompt-input` must show the
complete chosen instruction text before a run is allowed. Prompt snapshots,
config hashes, input hashes, and instruction hashes remain in the experiment.

Runs default to workspace-write with network access and approval policy `never`.
Use `prepare --sandbox danger-full-access` when deliberately comparing under
that host configuration. Both variants receive the same selected policy, which
is recorded in the manifest and native prompt snapshots. On macOS,
workspace-write can block Chromium's MachPort rendezvous during startup; that
is an environment failure even when the browser binaries are installed.
The normal PATH and machine binaries remain available; this is configuration
isolation, not a hermetic machine or a security container. The instruction
text itself may intentionally reference outside tools or documents. Raw events
show whether a model uses them. Browser runs exercise Playwright in the CLI;
they do not measure native Desktop computer-use or connected app behavior.

The default auth source is the calling `CODEX_HOME/auth.json`, overridable with
`--auth-file`. It is copied with mode 0600 only while the run is active and
removed on completion or failure. That authentication file is not copied to
result artifacts; explicitly supplied role files can still contain secrets.
The temporary runtime root is recorded in `experiment.json`; it contains the
native sessions needed for resume. Keep it while inspecting results, then remove
that exact recorded directory when the experiment is no longer needed.

The helper saves each turn's raw JSONL, stderr, final message, workspace snapshot,
usage, elapsed time, exit code, and native task ID. It also writes
`native-usage.json` with parent/child identities, selected models and efforts,
and the last reported cumulative counters per native session. It exports no
prompt or tool-argument content into that summary. The native format can change;
missing counters remain unavailable, and these are not billing receipts. Do not
add cached input or reasoning output twice, or sum repeated cumulative snapshots.
Resume uses the same task with an explicit
workspace on both turns. It tests a planned checkpoint followed by a requirement
change; it does not simulate a crash, offline work, or a scheduler wakeup.

| Case | Independent checks | Human review |
| --- | --- | --- |
| Execution (opt-in) | Generated zsh script, literal counts, spaces, zero matches, alternate cwd, unchanged inputs | Shell-variable safety and output discipline |
| Delegation (opt-in) | Exact grouped log counts and evidence, unchanged sources, generated producer/consumer payloads, interleaved capped retry behavior | Actual child models/tools, launch decisions, compact handoffs, bounded retry state |
| Coding | Interval coverage on 200 reproducible generated inputs, edge cases, nonmutation, invalid inputs | Scope and usefulness of model-written tests |
| Research | Output exists, length bound, primary-source citations | Factual accuracy, inference boundaries, recommendation usefulness |
| Browser | Real Chromium keyboard/toggle/reset/slider interactions, viewport overflow, runtime errors, screenshots | Design, readability, motion, honest visual inspection |
| Resume | CLI output on independent data, inclusive boundary, duplicate validation, preserved user notes | First-turn stop point, same native task ID, checkpoint quality |

Research uses a fixed, paraphrased primary-source packet to separate instruction
behavior from changing search results. It measures synthesis and judgment, not
live source discovery. Browser aesthetics and research correctness are not
inferred from keyword matches. Inspect the manual-review items printed by each
verifier and review the actual artifacts, preferably without variant labels.

## Delegation sample

The [2026-09-08 sample result](delegation/sample-result.md) records actual native
model routing, independent checks, usage, and the limits of that first pair.

The opt-in `delegation` case supplies three independent maintenance jobs to the
same Astra parent: extract actual errors from a 2,400-line synthetic log, rename
one event payload field while preserving historical literals, and fix independent
per-job exponential retry state. The request permits delegation without naming
roles or models, so native events can show whether the proposed instructions
actually route the work. It requires no network or extra dependencies.

```bash
uv run --no-project tests/agent_behavior.py prepare \
  --baseline /absolute/baseline-AGENTS.md \
  --candidate /absolute/candidate-AGENTS.md \
  --agent-dir /absolute/rendered-agent-roles \
  --output /absolute/new-delegation-experiment \
  --model gpt-6-astra --effort xhigh --cases delegation

uv run --no-project tests/agent_behavior.py run \
  /absolute/new-delegation-experiment/experiment.json candidate delegation
uv run --no-project tests/agent_behavior.py run \
  /absolute/new-delegation-experiment/experiment.json baseline delegation
```

Both variants have the same available roles. Their instruction policy is the
controlled difference; this does not compare agent availability against having
no agents. Use fresh experiment directories for repeats. `prepare` verifies
instruction loading without a model call. `run` consumes the parent model's
usage plus whatever child models it actually launches. Luna/low roles target
cheap extraction and mechanical edits; Terra/medium targets bounded changes.
Names and intended prices do not prove actual routing or savings. Consult the
[current official pricing](https://learn.chatgpt.com/docs/pricing) for rates at
the time of a run, and record parent and child model/effort, usage, elapsed time,
checks, and parent rework before comparing cost. Parent `turn.completed` usage
alone must not be treated as the sum of all child usage.

The expected report contains 2,400 total lines and 73 actual ERROR-level records:
31 `E_COMPILE`, 23 `E_FETCH`, and 19 `E_LINK`. Its first/last line references and
exact examples are independently checked against the fixture's generated event
schedule. The verifier also checks preserved input hashes, 80 generated payload
batches, legacy-key rejection, invalid constructor arguments, 1,750 interleaved
retry operations across separate instances, and repeated cap behavior. The
fixture includes misleading error text in INFO, WARN, and continuation lines.
Regenerate its deterministic log/oracle with
`uv run --no-project tests/fixtures/agent-behavior/delegation/generate.py` only
when intentionally changing the fixture; ordinary prepare/run does not regenerate
the oracle. `uv run --no-project tests/agent_behavior_test.py` checks that the
verifier rejects the original defects and accepts a correct independent result.

Review raw parent events and the native sessions under the recorded runtime
`CODEX_HOME` for actual child launches and tool access. Passing artifact checks
does not establish that delegation occurred or that it saved tokens. This local
log fixture does not validate live web discovery, page extraction, browser tools,
hosted ChatGPT Work routing, or general model quality. The verifier is external
to the copied workspace, but this is not an adversarially sealed benchmark.

Re-run only an independent verifier with:

```bash
uv run --no-project tests/agent_behavior.py verify /absolute/new-experiment/experiment.json candidate coding
```

Report observed outcomes, material behavior differences, actual usage, and
limitations. One successful pair is evidence for those tasks. Shorter prompts,
lower token usage, or a static plugin-eval score do not establish better work.
