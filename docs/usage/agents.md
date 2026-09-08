# Agent guidance

Four different AI coding tools (Claude Code, Codex, opencode, pi) each
expect their own AGENTS.md / CLAUDE.md file. Most of the
content is the same — user background, communication style, engineering
principles, tool preferences. The differences are the per-tool addenda
(skill systems, MCP usage, tool-call quirks, etc.).

## The shared partial

`home/.chezmoitemplates/agents-common.md` holds the common content. Each
tool's `.tmpl` file pulls it in with one line:

```gotmpl
{{ template "agents-common.md" . }}
```

A typical wrapper looks like:

```gotmpl
# AGENTS.md

Working preferences for <tool>. Shared guidance lives in the partial;
<tool>-specific exceptions follow.

{{ template "agents-common.md" . }}

## <Tool>-specific

- ...tool quirks, MCP setup, edit modes, etc...
```

### voice-common.md

`home/.chezmoitemplates/voice-common.md` holds tone/communication and
estimate conventions — deliberately split out of `agents-common.md` so it can
load at different levels per tool: Claude gets it via the `cade` output style
(system-prompt level), while the Codex/opencode/pi wrappers include it
directly next to `agents-common.md`. Keeping it out of `agents-common.md`
means Claude never loads the voice guidance twice.

### math-common.md

`home/.chezmoitemplates/math-common.md` keeps evidence distinctions and routes
formal certification to `scientific-review`. The exact Lean gate remains in
that skill's focused reference: intended statement, no `sorry`, `lake build`,
axiom audit, and `lean4checker --fresh`. Ordinary mathematical discussion does
not require starting a prover. The [math guide](math.md) documents tool routing.

## Where each file lives

| Tool | Source (chezmoi) | Deployed to |
|---|---|---|
| Claude Code | `home/dot_claude/CLAUDE.md.tmpl` | `~/.claude/CLAUDE.md` |
| Codex | `home/dot_codex/AGENTS.md.tmpl` | `~/.codex/AGENTS.md` |
| opencode | `home/dot_config/opencode/AGENTS.md.tmpl` | `~/.config/opencode/AGENTS.md` |
| pi | `home/dot_pi/agent/AGENTS.md.tmpl` | `~/.pi/agent/AGENTS.md` |

All four render through the same partial — edit `agents-common.md` once and
`chezmoi apply` propagates everywhere.

## Adding a new tool

1. Drop `home/<tool-config-path>/AGENTS.md.tmpl` (or whatever the tool calls
   it) with the wrapper shown above.
2. Add a `## <Tool>-specific` section at the bottom for anything the partial
   doesn't cover.
3. `chezmoi apply` deploys it.

No bootstrap.sh changes needed — `chezmoi apply` is step 2 of every bootstrap.

## Editing the shared content

Edit `home/.chezmoitemplates/agents-common.md` directly. The change takes
effect on every tool the next time they read their config (most pick up
file changes on session start; some are eager).

Global defaults express durable judgment, authorization, quality, and evidence
preferences. They preserve first-principles reasoning, substantive pushback,
the requested phase, selected model/effort, direct application work, and
editable creative outputs. They do not require history searches for
self-contained tasks or fixed counts of files, tests, or abstraction examples.
Detailed procedures stay in relevant skills; provider and package facts stay
in configuration and these docs.

Evaluate meaningful changes with the `writing-skills` workflow on realistic
isolated tasks using the same model and reasoning effort for both versions.
Record the loaded instruction fingerprints, produced artifacts, verifier
results, and observed usage. Prompt size is one measurement; a small sample
does not establish a universal quality improvement. The app's own instructions,
tool schemas, and skill catalog are separate context layers.

### Contextual tool preferences

These are useful when their task arises; they do not need to enter every
session's global prompt. Prefer `sd` for simple replacements, `bat` for human
file reading, and `zoxide` for familiar-directory jumps. Use `xh` for quick HTTP
requests, `hexyl` for binary inspection, `numbat` for units, and `samply record`
for CPU profiles. `typos` provides a source spelling pass. For symbolic math,
use the Wolfram skill and [math guide](math.md), which cover engine and API
alternatives without embedding credentials or changing quota claims globally.

## Project-level overrides

Most of these tools also walk up from the current working directory looking
for a project-local AGENTS.md / CLAUDE.md. Those override or augment the
global file — write project-specific guidance there, not in the partial.

## Skills (shared across tools)

Skills live in one place: `home/dot_claude/skills/` → deployed to
`~/.claude/skills`. A chezmoi-managed symlink `~/.agents/skills` →
`~/.claude/skills` exposes the same tree to Codex, opencode, and pi (all
three scan `~/.agents/skills`; opencode also reads `~/.claude/skills`
directly). One SKILL.md edit propagates to every tool on `chezmoi apply`.

Installer-managed skills are declared in `packages/agent-skills.txt`; Codex
plugins are declared separately in `packages/codex-plugins.txt`. Run
`bash install/skills-sync.sh check` for a read-only drift check. Do not use
`npx skills check` as an audit: current versions update installed skills.
Normal sync installs missing declarations and fails if any remain missing.
Upgrade compares each npx-managed tree with the mutable receipt from its last
install, so consecutive upgrades keep tracking upstream while real local edits
are preserved. Self-installed skills rerun their declared force installer.
The committed digest remains the review/audit baseline. Read-only `check`
continues to exit nonzero for drift from that baseline.

Claude has `researcher` and `reviewer` specialists under its managed `agents/`
directory. Codex has the focused roles below. Global instructions authorize
bounded delegation while keeping overlapping edits in one agent. Codex allows
up to six concurrent direct children; focused efficiency roles disable their
own agents. The configured `max_depth = 1` is a V1 fallback, not a V2 nesting
guarantee for other roles.

`install/agent-tools.sh` deploys `df-agent-doctor` into `$ARCH_BIN` on every
platform. The command checks the declared tool surface, skill registry, Codex
plugins/config, qmd, cass, the managed Python/SymPy environment, and the live qmd
LaunchAgent on macOS. When `dotfiles-nvidia` is present, it also runs the
overlay's final runtime verifier, including ComputeLab and internal MCP tools.

## Codex delegation

The Codex wrapper authorizes named focused roles on every parent model whenever
useful independent work appears, including partway through a task. This is an
instruction policy for choosing work, not a runtime rule that detects or changes
the parent model or reasoning effort. Explicit task, model, and user directions
remain authoritative.

Custom role sources live under `home/dot_codex/agents/`. After editing them, run
`bash install/codex.sh sync-config` to render `~/.codex/agents/` with mode `0600`.
The installer owns those generated outputs; chezmoi ignores the target directory
so it cannot overwrite the generated tool scopes. These roles set both model
and reasoning effort:

| Role | Model / effort | Context controls | Assignment |
|---|---|---|---|
| `extractor` | Luna / low | Output 2,000; skills 2,000; web disabled; no registry MCPs | Extract requested facts from specified logs, files, or pages; return evidence locations and missing values. |
| `coder` | Luna / low | Output 2,000; skills 2,000; web disabled; no registry MCPs | Apply explicit replacements, mappings, or schema transformations to named files, with observable checks. |
| `explorer` | Terra / medium | Output 4,000; skills 3,000; web disabled | Answer a focused repository question or trace a specific execution path. |
| `researcher` | Terra / medium | Output 4,000; skills 3,000; web medium | Discover primary sources, verify current claims, and separate evidence from inference. |
| `patcher` | Terra / medium | Output 4,000; skills 3,000; web disabled | Implement a bounded behavior change that needs coding judgment. |
| `verifier` | Terra / medium | Output 4,000; skills 3,000; web disabled; no registry MCPs | Run prescribed checks and edge cases, then report evidence for parent integration. |
| `reviewer` | Inherit parent | Inherit parent | Independently assess correctness, regressions, and missing validation when warranted. |

`default` and `worker` also retain parent inheritance. The focused roles use low
verbosity and disable child-agent spawning. `researcher` and `reviewer` retain
their read-only permission setting; the other focused roles inherit the session's
permissions and are constrained by their role instructions. Role sources do not
turn inherited permissions into a security boundary. The verifier therefore may
write its requested artifacts while its instructions prohibit application/source
edits. Role descriptions and model settings belong in these files, rather than
being copied into every skill.

The role manifests also set context controls: Luna `extractor` and `coder` start
with a 2,000-token tool-output limit and a 2,000-token skill-catalog budget;
Terra `explorer`, `researcher`, `patcher`, and `verifier` start with 4,000 and
3,000 respectively. `researcher` uses medium web-search context. These are
starting choices for bounded assignments, not hard execution or spend caps, and
they do not guarantee savings. Validate them with observed correctness, usage,
artifacts, and parent rework on representative tasks.

The `coder` contract is deliberately narrower than `patcher`. "Replace these
three deprecated keys using this exact mapping in these named fixture files,
then run this verifier" fits `coder`. "Add an option with these semantics and
make its error handling consistent with the existing API" fits `patcher`.
Architecture, ambiguous requirements, difficult diagnosis, and final integration
remain with the parent. If a command can perform the whole task deterministically,
the parent should run that command directly instead of spawning a model.

Prefer direct CLI operations when one trivial deterministic command can complete
the work. Otherwise, batch related mechanical work in one assignment and give
each child the question, explicit cwd, absolute input paths or URLs, owned files
or modules, output artifact path or format, and acceptance checks. Prefer a
fresh brief (`fork_turns: "none"` when the available interface supports it) over
copying the whole conversation. Normally keep one or two useful children active.
Children report incomplete specifications, ownership conflicts, scope growth,
and failed checks to the parent; they do not build another delegation tree or
retry a failure without new evidence.

Have tools filter large material before a model reads it: use `rg`, `jq`, a
parser, or page extraction. Parsers write structured artifacts directly instead
of retyping generated data. Keep full logs and extracted datasets in artifacts;
return the answer, evidence locations, check results, artifacts, and unresolved
items.
The goal is to reduce expensive parent context and use cheaper models for
bounded interpretation. Delegation can increase total tokens, so model price
alone does not establish savings. Measure usage together with correctness and
parent rework on representative tasks.

The [executable delegation samples](../../tests/fixtures/agent-behavior/README.md#delegation-sample)
cover log extraction, an exact field rename, and a bounded retry repair. The
[first paired result](../../tests/fixtures/agent-behavior/delegation/sample-result.md)
confirmed Luna routing and passing outputs, but did not demonstrate fewer raw
tokens.

Tool activation is separate from role instructions and permission settings.
The [MCP registry](../../packages/mcp-servers.txt) remains the source of endpoints
and versions; [configuration generation](../../install/codex-config.py) combines
the [role selection manifest](../../packages/codex-agent-tools.json) with the managed configuration. Generated roles
include the resolved MCP definitions, disable unrelated servers, and scope apps
and plugins. Keep endpoint and credential declarations out of the role sources.
Run `bash install/codex.sh sync-config` after changing either role instructions
or tool selection, then inspect the actual spawned inventory in a new task.
A tool allowlist does not restrict what an unrestricted shell can access, and
a running task may retain its original tool inventory.

`extractor`, `coder`, and `verifier` load no registry MCPs; the extractor can
fetch supplied URLs with shell tools. `patcher` keeps Context7. `explorer` keeps Context7,
OpenAI developer docs, Rust docs, and crates.io. `researcher` keeps Context7 and
OpenAI developer docs plus live native web search with medium context. The other
efficiency roles disable native web search. Their generated configurations disable plugin
discovery and known apps as well as unwanted MCPs. New MCP integrations or
project overrides require another sync and inventory check; these are context
controls, not a security boundary.

These local files configure Codex clients that load them. They do not deploy
agent definitions, tools, or model routing into hosted ChatGPT Work. A matching
hosted project instruction can describe the workflow, but its available models
and delegation controls must be checked in that product. See OpenAI's
[subagent documentation](https://learn.chatgpt.com/docs/agent-configuration/subagents)
for the supported client behavior.

## Codex workbench

Codex defaults to GPT-6 Astra at extra-high reasoning. Use the base task for
normal work, then select one profile when its narrow purpose matches the job:

| Command | Intended use |
|---|---|
| `codex -p deep` | Astra with medium verbosity for a demanding implementation or research task. |
| `codex -p review` | Astra with read-only filesystem permissions for review and exploration. |
| `codex -p fast` | GPT-5.6 Luna at low reasoning for quick, low-risk iteration. |
| `codex -p context` | Astra with experimental context management. It requires a supported client and a ChatGPT Plus or Pro sign-in; it is not an API, Business, or Enterprise feature. |

The base configuration enables only the small, general MCP set: GitHub, OpenAI
developer docs, Context7, qmd, Rust docs, and crates.io. Domain profiles inherit
that base and add one task surface:

| Command | Adds |
|---|---|
| `codex -p browser` | Chrome DevTools MCP for browser debugging. |
| `codex -p creative` | The pinned Blender bridge. |
| `codex -p desktop` | Scriptable macOS-app automation. |
| `codex -p research` | Web and scholarly research sources. |
| `codex -p math` | Lean, theorem-search, and Wolfram tools. |
| `codex -p cloud` | Cloudflare and Google Cloud tools. |
| `codex -p workspace` | Google Workspace tools. |
| `codex -p tools-all` | Every declared MCP; use only when its added context and authority are intentional. |

Codex accepts one `-p` overlay per invocation. Treat it as a session choice:
browser work uses `browser`, Blender work uses `creative`, and so on. When a
project actually needs several domains at baseline, select the precise set with
`DF_MCP_PROFILES=browser:creative` while running
`bash ~/dotfiles/install/codex.sh sync-config`; rerun without that variable to
return Codex's base activation to the core set. Claude Code, OpenCode, and
Cursor preserve optional registry MCPs already activated there; profile
selection determines which new ones a sync adds. Start a new task after a
change to an MCP pin, environment, or activation, since an existing task keeps
its original tool inventory and may retain an old subprocess. The registry and
generated profiles live in
[`packages/mcp-servers.txt`](../../packages/mcp-servers.txt) and
[`install/codex-config.py`](../../install/codex-config.py).

Codex uses unrestricted local shell permissions with approval policy `never`.
Every managed or runtime-added MCP server and app connector uses Codex's
`approve` mode so read and write tools run without an interactive approval
prompt. Connector and account authorization remain separate from shell
permissions, and Codex may still enforce confirmation for tools marked
destructive by their provider.

## Other harnesses

- Claude Code defaults to Claude Fable 5 with extra-high effort,
  `bypassPermissions`, and its OS sandbox disabled.
- OpenCode uses Fable for planning, local Qwen3.6 for builds on macOS, and a
  read-only Sonnet 5 review subagent. Its generated MCP configuration follows the
  selected registry profiles; permissions are scoped per agent.
- Cursor CLI permits every shell command, Cursor's Claude extension starts in
  bypass mode, and Codex Desktop has its own app integrations and account gates.

The chezmoi source guard still blocks edits to rendered targets when an authoritative
source exists under `home/`. That is a correctness invariant, not an approval gate.

## Memory layers

Three layers, set up by `install/memory.sh` (bootstrap step 6.6, `DF_DO_MEMORY`):

| Layer | Store | Search | Synced? |
|---|---|---|---|
| L1 auto-memory | `~/.claude/projects/<proj>/memory/` (markdown) | loaded each session; also indexed by qmd | no (per-machine) |
| L2 knowledge base | `~/kb` git repo (markdown) | qmd — hybrid BM25 + local GGUF embeddings + rerank, MCP daemon on `localhost:8181` | yes (git remote) |
| L3 session history | every agent's transcripts (Claude Code, Codex, opencode, pi) | cass — hybrid BM25 + native MiniLM embeddings, CLI/`history-search` skill | no (per-machine) |

Both stores are local (`~/.cache/qmd`, `~/.cass` — on scratch when configured);
only `~/kb` and the dotfiles repo sync across machines. qmd's index is fully
rebuildable from `~/kb`; **cass is not** — it keeps transcripts the harnesses
later rotate away, so for those conversations it is the only remaining copy.
That is why it lives at `~/.cass` rather than under `~/.cache`. qmd keeps a
persistent MCP daemon, but cass indexing is manual on every platform so a large
session archive never blocks bootstrap or consumes resources on a schedule.

qmd stays warm as a query service. cass indexing is deliberately **manual**:
the shell profiles and installer do not schedule an archive scan. Run
`bash install/memory.sh index` for a lexical refresh. Run
`bash install/memory.sh semantic` for one resumable 64-conversation semantic
batch; repeat it when you want more history embedded. After bulk changes,
`bash install/memory.sh reindex` forces the qmd embedding and cass lexical
indexes to rebuild. Agent-facing usage rules live in the `## Memory layers`
section of `agents-common.md`.

## Remote clipboard

Ghostty copies selections to the local clipboard and permits remote OSC 52
writes. Its shell integration propagates environment and terminfo over SSH.
The managed tmux config enables clipboard escape passthrough, and Neovim forces
its OSC 52 provider whenever `SSH_TTY` or `SSH_CONNECTION` is set. Paste remains
local terminal input; remote clipboard reads still require Ghostty approval.
