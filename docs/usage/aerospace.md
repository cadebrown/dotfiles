# AeroSpace (v2)

This is the canonical reference for macOS window management in this dotfiles repo.

---

## Source of truth

```sh
$EDITOR ~/dotfiles/home/dot_aerospace.toml
chezmoi apply ~/.aerospace.toml
aerospace reload-config
```

---

## Design principles

- Direct hotkeys for primary actions (no leader-mode dependency)
- No hardcoded workspace-to-monitor assignment
- No automatic app-to-workspace routing
- Tight grid (zero gaps) with predictable normalization

---

## Main keymap

- `alt + ←/↓/↑/→`: focus window
- `alt + shift + ←/↓/↑/→`: move window
- `cmd + alt + ←/↓/↑/→`: join-with direction
- `alt + -` / `alt + =`: resize smart `-50` / `+50`
- `alt + /`: cycle `layout tiles horizontal vertical`
- `alt + ,`: cycle `layout accordion horizontal vertical`
- `alt + f`: AeroSpace fullscreen
- `alt + shift + f`: macOS native fullscreen
- `alt + tab`: workspace back-and-forth
- `alt + 1..9`: switch workspace
- `alt + shift + 1..9`: move node to workspace and follow
- `cmd + alt + 1..9`: move node to workspace without following
- `alt + pageUp/pageDown`: focus monitor next/prev (wrap)
- `alt + shift + pageUp/pageDown`: move workspace to monitor next/prev (wrap)

---

## Service mode

- Enter: `alt + shift + ;`
- `esc`: reload config + return to main
- `r`: flatten workspace tree + return to main
- `f`: toggle floating/tiling + return to main
- `backspace`: close all windows but current + return to main
