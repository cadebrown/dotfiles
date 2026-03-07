# Editors

## vim

Default `$EDITOR`. Used for git commit messages, quick edits, and anything invoked from the shell.

Config is minimal — vim's defaults are fine for quick edits. No plugins managed via dotfiles.

## Cursor / VS Code

Used for larger projects where LSP, debugging, and extensions matter. No settings tracked in dotfiles — rely on Settings Sync.

## Claude Code

Used alongside editors for AI-assisted development. Config tracked in dotfiles:

- `~/.claude/CLAUDE.md` — persistent instructions loaded every session
- `~/.claude/settings.json` — permissions and enabled plugins

See `packages/claude-plugins.txt` for installed plugins (LSPs for Rust, C++, Python, TypeScript, plus `claude-md-management`).
