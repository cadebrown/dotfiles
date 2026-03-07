# Terminal (Ghostty)

[Ghostty](https://ghostty.org) is the primary terminal. Config lives at `~/.config/ghostty/config`.

## Notable settings

- **Font:** JetBrains Mono, 13pt
- **Theme:** GruvboxDark (dark) / GruvboxLight (light), follows system
- **Padding:** 8px on all sides
- **Scrollback:** 100,000 lines
- **Cursor:** bar style, no blink
- **`macos-option-as-alt = true`** — makes `opt` work as `alt` for shell keybindings (e.g. word-jump with `alt-←/→`)
- **Shell integration:** zsh, with cursor, sudo prompt, and title tracking

## Shell integration

Ghostty's zsh integration provides:

- Cursor shape changes between insert/normal mode
- Semantic zones (prompt, command, output) for navigation
- Window title set to current command/directory
