---
title: Shell, terminal, and editor workflow
description: Operate managed shell, terminal, Neovim, VS Code, and Cursor configuration without confusing source, applied state, and active runtime behavior.
---

## Establish the shell environment first

Chezmoi renders the login environment from [dot_zprofile.tmpl](../../home/dot_zprofile.tmpl) and [dot_bash_profile.tmpl](../../home/dot_bash_profile.tmpl). They select the flat or PLAT-isolated local root, activate Homebrew, then source [dot_profile.tmpl](../../home/dot_profile.tmpl). Interactive [Zsh](../../home/dot_zshrc.tmpl) and [Bash](../../home/dot_bashrc.tmpl) rc files add the prompt, completion, history, and command helpers; they repeat locale setup because editor terminals commonly use a non-login shell.

```sh
# Rendered configuration is current only after an explicit apply.
chezmoi diff

# In a new terminal, establish the managed login environment and inspect it.
exec zsh -l
printf '%s\n' "$PATH" | tr : '\n' | sed -n '1,12p'
command -v git rg fzf node python
```

The expected observation is a resolved executable for each installed command and one selected local bin directory in the leading path entries. It does not prove every bootstrap package is installed. chezmoi diff proves the source would change targets; it does not apply it.

EDITOR=vim, PAGER=less, and RIPGREP_CONFIG_PATH=$HOME/.config/ripgrep/ripgreprc come from the common profile. Ripgrep searches hidden files and follows symlinks by default, then excludes .git, node_modules, virtual environments, build targets, and caches:

```text
--smart-case
--hidden
--glob=!.git/
--glob=!node_modules/
```

Use rg --debug --files 2>&1 | sed -n '1,40p' when a file is unexpectedly absent. Its output explains glob decisions without changing files; project .ignore or .rgignore still changes results.

## Use interactive search deliberately

Zsh loads direnv, while Bash runs direnv hook bash; entering a directory can therefore export values from that directory's .envrc. Review an unfamiliar .envrc before approving it. fzf uses fd --type f --hidden --follow --exclude .git where fd exists, so Ctrl-T and rg --files have deliberately different scopes. Atuin initializes after fzf because both provide Ctrl-R; a working Atuin replaces fzf's history binding.

Readline clients such as Bash, Python's REPL, and GDB share [dot_inputrc](../../home/dot_inputrc). It enables bracketed paste and makes up/down arrows search history using the typed prefix. This is not a Zsh keymap.

| Need | Managed behavior | Observation |
| --- | --- | --- |
| Find a source file | fzf uses fd when available | Ctrl-T excludes .git but can include hidden files. |
| Search exact content | rg applies the managed rc file | rg --debug pattern path reports active glob filtering. |
| Load per-project variables | direnv hook evaluates approved .envrc | direnv status reports directory state. |
| Recall Bash/Python input | readline prefix search and bracketed paste | Type git then Up; inspect rather than execute recalled input. |

## Carry clipboard data through SSH and tmux

[Ghostty configuration](../../home/dot_config/ghostty/config) renders to $HOME/.config/ghostty/config; [dot_tmux.conf](../../home/dot_tmux.conf) renders to $HOME/.tmux.conf. Ghostty advertises xterm-ghostty over SSH and permits OSC 52 writes while asking before clipboard reads. tmux enables clipboard escape passthrough for that terminal type.

```text
# Ghostty
shell-integration-features = cursor,sudo,title,path,ssh-env,ssh-terminfo
clipboard-write = allow
clipboard-read = ask

# tmux
set -s set-clipboard on
set -as terminal-features ',xterm-ghostty:clipboard'
```

```mermaid
flowchart LR
  R[remote program] --> O[OSC 52 sequence]
  O --> T[tmux passthrough]
  T --> G[Ghostty]
  G --> C[local clipboard]
```

In a remote tmux pane, printf '\033]52;c;dGVzdA==\a' is a controlled write test: the expected result is local clipboard text test. It proves only that terminal path. Remote reads still require Ghostty approval, and an embedded VS Code/Cursor terminal is not Ghostty. See [Ghostty shell integration](https://ghostty.org/docs/features/shell-integration) and [tmux clipboard options](https://man.openbsd.org/tmux#set-clipboard).

## Operate Neovim as configuration plus plugin state

[init.lua](../../home/dot_config/nvim/init.lua) deploys to $HOME/.config/nvim/init.lua. It bootstraps lazy.nvim into Neovim's data directory on first startup, then declares Telescope with leader-s-f (files), leader-s-g (live grep), leader-s-d (diagnostics), and leader-leader (buffers). Ctrl-h/j/k/l changes splits; Esc Esc exits terminal mode.

The LSP section uses Mason, nvim-lspconfig, Blink completion, and a lua_ls server declaration; mason-tool-installer ensures lua_ls and stylua. Conform formats before writes with LSP fallback, except C/C++ are excluded from format-on-save. Treesitter installs declared core parsers automatically.

```lua
vim.keymap.set('n', '<leader>sg', builtin.live_grep)
map('grd', require('telescope.builtin').lsp_definitions, 'Goto Definition')
require('conform').format { async = true, lsp_format = 'fallback' }
```

When lazy.nvim already exists, nvim --headless '+checkhealth' +qa checks observed runtime health and can report missing external tools. The first Neovim startup clones lazy.nvim, so it is not a read-only first-run test. :Lazy, :Mason, and :checkhealth establish plugin or server state, separate from applied Lua source. See [Neovim documentation](https://neovim.io/doc/) and [lazy.nvim](https://lazy.folke.io/) before changing plugin APIs.

## Keep editor configuration and editor state apart

[VS Code settings](../../home/dot_config/vscode/settings.json) and [Cursor settings](../../home/dot_config/cursor/settings.json) deploy first to $HOME/.config/vscode/ and $HOME/.config/cursor/. Their installers then link JSON into platform-native User directories and reconcile separate extension manifests. [Cursor hooks](../../home/dot_cursor/hooks.json) deploy to $HOME/.cursor/hooks.json; session hooks use the managed helper to import changed JSON source edits, and the pre-tool hook delegates command rewriting to RTK.

```sh
# Read-only source syntax checks and native-link evidence when configured.
jq . $HOME/dotfiles/home/dot_config/vscode/settings.json >/dev/null
jq . $HOME/dotfiles/home/dot_config/cursor/settings.json >/dev/null
ls -l "$HOME/Library/Application Support/Cursor/User/settings.json"  # macOS
```

Settings choose CMake behavior, language defaults, terminal integration, and themes. They do not install a language server, grant an agent permission, or prove that a GUI reloaded a file. cursor --list-extensions and code --list-extensions inspect application inventories only when their CLIs exist. Use [troubleshooting](../usage/troubleshooting.md#cursor-reports-enoent-for-usersettingsjson-and-ignores-user-settings) for the known Cursor non-atomic settings-write failure, and [VS Code settings](https://code.visualstudio.com/docs/configure/settings) for schema behavior.

## Treat Git and SSH settings as defaults, not credentials

The [Git template](../../home/dot_gitconfig.tmpl) sets delta, histogram diffs, zdiff3, pull rebase with fast-forward-only, rerere, submodule recursion, worktree defaults, and GitHub SSH URL rewriting. [SSH configuration](../../home/dot_ssh/config.tmpl) includes private $HOME/.ssh/config.d blocks before a Host * policy that multiplexes through /tmp, accepts new host keys, hashes known hosts, and forwards the agent by default.

```sh
git config --global --show-origin --get core.pager
ssh -G github.com | rg '^(controlpath|forwardagent|stricthostkeychecking) '
```

These commands show the effective Git/SSH client view without connecting. They cannot prove a key is loaded, forwarding is server-permitted, or a first connection's host key is trustworthy. See [Git configuration](https://git-scm.com/docs/git-config) and [OpenSSH ssh_config](https://man.openbsd.org/ssh_config).
