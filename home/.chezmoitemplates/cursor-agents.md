{{/* Cursor wrapper: shared prefs plus Cursor-native routing. */ -}}
# Personal working preferences

{{ template "voice-common.md" . }}

{{ template "agents-common.md" . }}

## Cursor

Custom subagents live in `~/.cursor/agents/` and pin `composer-2.5`. Explore
defaults to the same model. Delegate
`researcher` for live primary-source questions, `reviewer` after
implementation, `verifier` to check claimed work, and `debugger` for a
failing reproduction. Built-in Explore, Bash, and Browser stay product-owned;
do not recreate them. A role description is not a permission boundary.

Computer use — pick one driver per task:

- In-editor web UI: the built-in Browser subagent, `cursor-ide-browser`,
  chrome-devtools MCP, or Design Mode in the Agents Window.
- Native macOS apps: `macos-automator` MCP and `desktop-workbench` / peekaboo.
- Isolated VM: Cloud Agent native computer use (demos and screenshots).
- This Mac as a Cloud worker: the My Machines worker started by
  `df-cursor-worker` (`agent worker --computer-use`). Clicks and screenshots
  go through **Cursor Computer Use** (`co.anysphere.cursor-computer-use`),
  which needs Accessibility and Screen Recording. Grant those to that helper
  app, not to Terminal or Cursor.app.
- Codex Desktop Computer Use is a different harness; do not run two GUI
  drivers on the same display for one task.

Cloud `/in-cloud` and `/autopilot` sessions use MCP from cursor.com/agents,
not `~/.cursor/mcp.json`. User hooks in `~/.cursor/hooks.json` do not run on
Cloud VMs. Cursor captures settings edits instead of blocking them with the
chezmoi guard.

`~/.cursor/skills` is a symlink to `~/.claude/skills`. Turn on Sync Skills for
Cloud Agents in Settings when a Cloud run needs that tree. Shell is
unrestricted (`Shell(*)`).
