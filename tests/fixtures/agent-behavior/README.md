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
copied. The chosen global instructions and a minimal explicit configuration
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
removed on completion or failure. Secrets are not copied to result artifacts.
The temporary runtime root is recorded in `experiment.json`; it contains the
native sessions needed for resume. Keep it while inspecting results, then remove
that exact recorded directory when the experiment is no longer needed.

The helper saves each turn's raw JSONL, stderr, final message, workspace snapshot,
usage, exit code, and native task ID. Resume uses the same task with an explicit
workspace on both turns. It tests a planned checkpoint followed by a requirement
change; it does not simulate a crash, offline work, or a scheduler wakeup.

| Case | Independent checks | Human review |
| --- | --- | --- |
| Execution (opt-in) | Generated zsh script, literal counts, spaces, zero matches, alternate cwd, unchanged inputs | Shell-variable safety and output discipline |
| Coding | Interval coverage on 200 reproducible generated inputs, edge cases, nonmutation, invalid inputs | Scope and usefulness of model-written tests |
| Research | Output exists, length bound, primary-source citations | Factual accuracy, inference boundaries, recommendation usefulness |
| Browser | Real Chromium keyboard/toggle/reset/slider interactions, viewport overflow, runtime errors, screenshots | Design, readability, motion, honest visual inspection |
| Resume | CLI output on independent data, inclusive boundary, duplicate validation, preserved user notes | First-turn stop point, same native task ID, checkpoint quality |

Research uses a fixed, paraphrased primary-source packet to separate instruction
behavior from changing search results. It measures synthesis and judgment, not
live source discovery. Browser aesthetics and research correctness are not
inferred from keyword matches. Inspect the manual-review items printed by each
verifier and review the actual artifacts, preferably without variant labels.

Re-run only an independent verifier with:

```bash
uv run --no-project tests/agent_behavior.py verify /absolute/new-experiment/experiment.json candidate coding
```

Report observed outcomes, material behavior differences, actual usage, and
limitations. One successful pair is evidence for those tasks. Shorter prompts,
lower token usage, or a static plugin-eval score do not establish better work.
