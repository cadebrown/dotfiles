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

This is the global memory for <tool>. Common guidance lives in the shared
partial; <tool>-specific notes follow.

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

`home/.chezmoitemplates/math-common.md` holds the research-mathematics norms,
included by all four guidance files. Three things it fixes in place:

- **The proof gate.** A claim counts as proved only when the exact intended
  statement compiles in Lean with no `sorry`, survives `lake build`, passes an
  axiom audit, and certifies under `lean4checker --fresh`. Misformalization —
  proving the wrong statement — is the classic failure, not bad tactics, so
  formalized statements get unit-tested against known examples first.
- **Evidence tiers.** CAS output, notebook experiments, and numerical sweeps are
  *evidence*, never proof, and have to be labeled as such. Literature claims
  carry a source.
- **Tool routing**, so agents reach for the verifying tool instead of guessing:
  Lean state and search → the `lean-lsp` MCP; literature → `asta` and `arxiv`;
  CAS checks → `wolframscript`; sequences → OEIS; constants → PSLQ via
  `mathlas`. Registered for every harness from `packages/mcp-servers.txt`.

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

Codex and Claude each have `researcher` and `reviewer` specialists under their
managed `agents/` directories. Global instructions authorize bounded parallel
research, log analysis, tests, and final review while keeping overlapping edits
in one agent. Codex is capped at six direct children and one level of nesting.

`install/agent-tools.sh` deploys `df-agent-doctor` into `$ARCH_BIN` on every
platform. The command checks the declared tool surface, skill registry, Codex
plugins/config, qmd, cass, the managed Python/SymPy environment, and the live qmd
LaunchAgent on macOS. When `dotfiles-nvidia` is present, it also runs the
overlay's final runtime verifier, including ComputeLab and internal MCP tools.

## Model and safety defaults

- Codex defaults to GPT-5.6 Sol at high reasoning. `deep` raises reasoning to
  extra-high, `fast` uses GPT-5.6 Luna at low reasoning, and `review` is read-only.
- Codex defaults to the built-in `:danger-full-access` profile with approval policy
  `never`. All MCP and connector tools, including destructive and open-world tools,
  run without prompts.
- Claude Code defaults to Claude Fable 5 with extra-high effort,
  `bypassPermissions`, and its OS sandbox disabled.
- OpenCode uses Fable for planning, local Qwen3.6 for builds on macOS, and a
  read-only Sonnet 5 review subagent. Plan/build agents and all MCP tools use the
  global `allow` policy; its shell wrapper also passes `--auto`. Review rejects
  unmatched shell commands without asking.
- Cursor CLI permits every shell command, Cursor's Claude extension starts in
  bypass mode, Claude Desktop permits all browser actions, and Codex Desktop skips
  its full-access confirmation.

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

Run `bash install/memory.sh index` for a lexical refresh. Run
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
