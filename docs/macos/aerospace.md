# Window Management (AeroSpace)

[AeroSpace](https://nikitabobko.github.io/AeroSpace/guide) is a tiling window manager for macOS. Config lives at `~/.aerospace.toml`.

## Layout

Uses a tiling layout by default (`tiles`). Windows are organized into numbered workspaces (1–14), accessible with `alt-N`.

## Key bindings

| Binding | Action |
|---|---|
| `alt-1` through `alt-9` | Switch to workspace 1–9 |
| `alt-shift-1` through `alt-shift-5` | Switch to workspace 10–14 |
| `alt-tab` | Toggle between last two workspaces |
| `alt-shift-tab` | Move workspace to next monitor |
| `alt-←/↓/↑/→` | Focus window in direction |
| `alt-shift-←/↓/↑/→` | Move window in direction |
| `alt-f` | Fullscreen (AeroSpace) |
| `alt-shift-f` | Native macOS fullscreen |
| `alt-minus` / `alt-equal` | Resize window smart -50/+50 |
| `alt-/` | Toggle tiles (horizontal/vertical) |
| `alt-,` | Toggle accordion layout |
| `alt-shift-;` | Enter service mode |

## Service mode

`alt-shift-;` enters service mode for less common actions:

| Binding | Action |
|---|---|
| `esc` | Reload config, exit service mode |
| `r` | Flatten workspace tree (reset layout) |
| `f` | Toggle floating/tiling |
| `backspace` | Close all windows but current |
| `↑` / `↓` | Volume up/down |
| `shift-↓` | Mute |
