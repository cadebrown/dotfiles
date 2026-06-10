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

## Memory layers

Three layers, set up by `install/memory.sh` (bootstrap step 6.6, `DF_DO_MEMORY`):

| Layer | Store | Search | Synced? |
|---|---|---|---|
| L1 auto-memory | `~/.claude/projects/<proj>/memory/` (markdown) | loaded each session; also indexed by qmd | no (per-machine) |
| L2 knowledge base | `~/kb` git repo (markdown) | qmd — hybrid BM25 + local GGUF embeddings + rerank, MCP daemon on `localhost:8181` | yes (git remote) |
| L3 session history | every agent's transcripts (Claude Code, Codex, opencode, pi) | cass — hybrid BM25 + local ONNX embeddings (`nomic-embed`), CLI/`history-search` skill | no (per-machine) |

Search indexes always rebuild locally (`~/.cache/qmd`, `~/.cache/cass` — on
scratch when configured); only `~/kb` and the dotfiles repo sync across
machines. Daemons: LaunchAgents `dev.cade.qmd` / `dev.cade.cass-watch` on
macOS, lazy-start from the shell profiles on Linux.

Re-index after bulk changes: `bash install/memory.sh reindex` (forces qmd
re-embed and a full cass rebuild). Agent-facing usage rules live in the
`## Memory layers` section of `agents-common.md`.
