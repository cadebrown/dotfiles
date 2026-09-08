# AI workbench

The default setup is a small Codex tool surface with GPT-6 Astra at extra-high
reasoning. Add a domain profile when the task needs a specialist integration;
use skills and project CLIs for the normal work loop. This keeps long-running
coding and research sessions focused without discarding the capable local stack.

## Start a task

```bash
codex                         # Astra, core tools
codex -p deep                 # demanding implementation or research
codex -p review               # Astra, read-only exploration
codex -p fast                 # quick Luna iteration
codex -p context              # eligible Plus/Pro accounts only
```

`context` enables an experimental Astra context-management feature. It requires
a supported client and ChatGPT Plus or Pro sign-in; API, Business, and Enterprise
access does not enable it. Treat it as an opt-in experiment and keep durable
project state outside the chat.

Use one `-p` profile in a session. The profile inherits the core tool set, then
adds a single domain. The current generated domain profiles are `browser`,
`creative`, `desktop`, `research`, `math`, `cloud`, `workspace`, and `tools-all`.
`tools-all` is for intentional broad work, not a normal startup choice.

To change the persistent baseline for a host, select registry profiles while
regenerating configuration:

```bash
DF_MCP_PROFILES=research:math bash ~/dotfiles/install/codex.sh sync-config
bash ~/dotfiles/install/codex.sh check
```

That change applies to the generated harness configuration. Keep it scoped to a
real project need and rerun without `DF_MCP_PROFILES` to restore the core-only
baseline for new activation. Claude Code, OpenCode, and Cursor retain optional
registry MCPs already activated there; profile selection controls which new
ones a sync adds. The registry is
[`packages/mcp-servers.txt`](../../packages/mcp-servers.txt).

After changing an MCP pin, environment, or activation, start a new task (and
restart the harness when it owns the MCP subprocess). A running task keeps its
initial tool inventory and may retain an older subprocess environment.

## Delegate a focused task

The [Codex delegation guide](agents.md#codex-delegation) defines the roles and
launch policy. `codex -p fast` selects Luna for the entire session; assigning
the `coder` or `extractor` role uses Luna for just that child while the selected
parent model keeps coordinating the main task. Any parent model may launch a
suitable named role as work appears. This preserves the parent model and effort;
explicit task and model requirements take priority.

Use `extractor` for specified logs or pages, `coder` for exact mechanical code
edits, `explorer` for repository investigation, `researcher` for finding sources,
`patcher` for bounded implementation needing judgment, and `verifier` for
prescribed checks and edge cases. Here are sample
briefs to adapt with real inputs and project-native checks:

```text
Use extractor. Cwd: /absolute/project. Input: /tmp/build-output.log. Group compiler errors by diagnostic
code and report the count, first occurrence's line number, and exact message.
Filter before reading. Write the complete grouped data to /tmp/build-errors.json
and return a compact summary. Unknown codes stay unknown; do not infer causes.
Check that the group counts equal the number of matched error records.
```

```text
Use coder. Cwd: /absolute/project. You own only /absolute/project/fixtures/request-a.json
and /absolute/project/fixtures/request-b.json.
Replace the top-level key max_tokens with max_output_tokens in those files,
preserving its value and every other field. If both keys exist, report the
conflict without editing that file. Do not change application behavior.
Check that both files parse, the old key is absent, and all other values match
their originals. Return the changed files and check results.
```

```text
Use patcher. Cwd: /absolute/project. You own /absolute/project/src/config.ts and
its existing config tests. Add an optional
positive-integer timeoutMs setting, defaulting to 30000 when absent. Reject zero,
negative, fractional, and nonnumeric values through the current validation API.
Preserve other defaults. Run the existing config tests with cases covering those
inputs. Return the behavior change, checks, and unresolved questions.
```

Use direct CLI commands for trivial deterministic work; otherwise batch related
mechanical transformations in one focused assignment. Each child gets a compact
fresh brief, explicit cwd, absolute inputs, named ownership, an artifact path,
and acceptance checks. Keep full outputs in the requested artifacts and have the
parent read the focused result first. `extractor` writes parser-produced
structured data directly. `coder` and `patcher` fix ordinary in-scope mistakes,
then escalate missing contracts or scope growth. `verifier` writes test/build
artifacts but does not edit application/source checks or weaken them; the parent
judges integration from its exit statuses, evidence, and gaps. Escalate based on
new evidence rather than repeating generic retries. Exercise samples in an
isolated workspace before making claims about routing quality or savings; record
the actual model, reasoning effort, tools, usage, verifier result, and parent
rework. The role budgets are starting context choices, not hard execution or
spend caps, and observed validation determines whether they save work.

## Choose a domain path

| Work | Primary path | Evidence that matters |
|---|---|---|
| Browser UI | `browser-workbench`, Playwright CLI, then `codex -p browser` for DevTools evidence | Screenshots at relevant viewports, interaction result, console/network/trace when relevant |
| WebMCP app actions | `webmcp-workbench`, page-defined tools sharing the app's own state and permissions | Native tool discovery and invocation, visible state changes, persistence, and working ordinary controls |
| Native desktop | Codex Computer Use or `desktop-workbench`; `codex -p desktop` for scriptable apps | A fresh observation of the target application and the reopened export or changed state |
| Blender and game assets | `blender-workbench`; `codex -p creative` only for a live scene | Rendered frame, reopened `.blend`, and an imported engine export |
| Motion graphics and editing | `media-workbench`, Remotion, Kdenlive, FFmpeg | Playback, representative frames, legible type, and audible output |
| Research and formal math | `researcher`, `scientific-review`, `codex -p research` or `-p math` | Primary sources, exact retrieval dates, and Lean/CAS/reproduction evidence kept distinct |
| Sustained work | `long-running-work`, checkpoints, and `tmux` over SSH where needed | A current work log, restartable operation, and an artifact exercised by its consumer |

These paths are complementary. A browser session does not prove desktop access;
an installed desktop tool does not grant a screen-recording, accessibility, or
account permission; a headless Linux job does not establish remote GUI control.
Inspect the live capability before relying on it.

## Browser and UI/UX

Use [`df-browser`](browser-sessions.md) for persistent project/service browser
workspaces, private login state, and screenshots and traces kept outside the
repository. Existing signed-in browser tabs are available through explicit
extension attachment.

Use Playwright CLI for named, repeatable sessions and project-owned regression
tests. The `browser` profile enables the pinned Chrome DevTools MCP with its
usage and CrUX telemetry disabled. Use it for console, request, and performance
evidence rather than loading it into every coding task.

```bash
playwright-cli -s=ui open http://127.0.0.1:3000
playwright-cli -s=ui snapshot
playwright-cli -s=ui screenshot --filename=desktop.png
playwright-cli -s=ui close
```

Figma design context is provided by its official plugin when connected. Figma
account authorization, Desktop availability, and canvas-write access are
separate from this dotfiles setup; check the active Figma connection before
asking an agent to read or change a design.

Use the [WebMCP workbench](webmcp.md) when your application should expose
meaningful actions to agents in the same live page. Its reusable simulation lab
provides an editable example and checks the ordinary UI alongside the tool
interface. WebMCP is page-scoped; it does not require enabling another global
MCP server. Client support must be verified through the current browser.

## Desktop, 3D, and media

Use Computer Use for application work. On macOS, background and locked-mode
execution are available when their explicit task opt-ins are enabled. Peekaboo
can provide structured accessibility and screenshot automation outside a native
Computer Use harness. Start by checking actual permissions and app/window state;
use a semantic application API when repeatable edits need it.

Blender's batch helper keeps scene work reproducible, while the live bridge is
for an already-open editor. For media, Kdenlive owns editable timelines,
Remotion owns code-authored motion graphics, and FFmpeg/ffprobe handle delivery
and inspection. See [Game development](gamedev.md) for assets and
[`media-workbench`](../../home/dot_claude/skills/media-workbench/SKILL.md) for
the editing flow. The two reproducible entry points are:

```bash
uv run ~/.claude/skills/blender-workbench/scripts/blender_workbench.py --help
(cd ~/.claude/skills/media-workbench && node scripts/scaffold.mjs /absolute/output/project)
```

## Long-running and remote work

[`df-task`](durable-tasks.md) records lightweight native lifecycle checkpoints
and explicitly registered jobs, logs, and artifacts. `codex -p deep` also keeps
the host awake during active turns. Use `df-task list` and `df-task resume` to
inspect saved state and recover the native resume command after interruption.

The [Google Cloud MCP transport](google-cloud-mcp.md) refreshes ADC within a
running session across Codex, Claude Code, OpenCode, and Cursor. No launch-time
Google access token needs to be renewed by reopening the harness.

For repeatable creative work, start with the
[creative reference and demonstration workflow](creative-workflows.md).
Project briefs separate confirmed requirements, proposed direction, and
reference provenance. Record & Replay can teach a stable Mac workflow through
a demonstration; it is not a recording service enabled by bootstrap.

Use a task's native resume path for active Codex work. For a persistent Linux
build, experiment, render, or server, keep the process in `tmux` over SSH and
record its command, inputs, output path, and last successful verification in
the project. A process exiting successfully is not completion until its output
is opened, rendered, or otherwise exercised.

The three local memory layers have distinct jobs: native harness memory for the
current agent, qmd for the Markdown knowledge base, and cass for transcript
history. qmd is kept warm automatically. cass is an archive and its indexing is
manual, so refresh it deliberately:

```bash
bash ~/dotfiles/install/memory.sh index
bash ~/dotfiles/install/memory.sh semantic
```

Run `df-agent-doctor` after a bootstrap or toolchain update to check the
declared stack and the live qmd service. It does not prove account access,
hardware availability, or a third-party application's GUI state.
