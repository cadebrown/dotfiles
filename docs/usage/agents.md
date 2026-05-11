# Agent guidance

Five different AI coding tools (Claude Code, Codex, aider, opencode, pi) each
expect their own AGENTS.md / CLAUDE.md / CONVENTIONS.md file. Most of the
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

## Where each file lives

| Tool | Source (chezmoi) | Deployed to |
|---|---|---|
| Claude Code | `home/dot_claude/CLAUDE.md.tmpl` | `~/.claude/CLAUDE.md` |
| Codex | `home/dot_codex/AGENTS.md.tmpl` | `~/.codex/AGENTS.md` |
| aider | `home/dot_config/aider/CONVENTIONS.md.tmpl` | `~/.config/aider/CONVENTIONS.md` |
| opencode | `home/dot_config/opencode/AGENTS.md.tmpl` | `~/.config/opencode/AGENTS.md` |
| pi | `home/dot_pi/agent/AGENTS.md.tmpl` | `~/.pi/agent/AGENTS.md` |

All five render through the same partial — edit `agents-common.md` once and
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
