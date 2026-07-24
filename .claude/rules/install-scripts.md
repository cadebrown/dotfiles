---
paths:
  - "install/**"
  - "bootstrap.sh"
  - "tests/**"
---

# Install scripts

Each script sources `_lib.sh`, is idempotent, and has a `DF_DO_*` flag in `bootstrap.sh`:

| Script | What it does | Key details |
|---|---|---|
| `chezmoi.sh` | chezmoi binary → `$ARCH_BIN` | Official installer with checksum |
| `plat-decommission.sh` | Removes leftover `~/.local/plat_*/` dirs after switching to flat layout | Standalone only — never invoked by `bootstrap.sh` (including upgrade). Refuses if `DF_USE_PLAT=1`. |
| `zsh.sh` | oh-my-zsh + plugins (pure, autosuggestions, fsh, completions) | Clones or updates via git |
| `homebrew.sh` | macOS: Homebrew + `brew bundle` from Brewfile | Upgrades enabled by default |
| `linux-packages.sh` | Linux: Homebrew + glibc + `brew bundle` | Custom prefix, compiler symlinks, upgrades off by default |
| `macos-services.sh` | Colima + Ollama + mlxserve auto-start (rootless Docker + local LLM servers) — **gated off by default** — plus docker CLI-plugin symlinks (always run) | macOS only, skips on Linux. Auto-start is opt-in via `DF_START_LOCAL_SERVICES=1` (default 0); mlxserve alone held ~34GB RAM at login. Manual control unaffected: `colima start` / `ollama serve` / `mlxserve`. |
| `macos-settings.sh` | System prefs via `defaults write` (Dock, Finder, keyboard, trackpad, Safari, iTerm2) + sudo QoL: Touch ID (`/etc/pam.d/sudo_local`, pam_reattach for tmux) and a global 60-min sudo ticket (`/etc/sudoers.d/df-ticket`) | macOS only |
| `macos-quick-actions.sh` | Deploys `*.workflow` bundles to `~/Library/Services/` (right-click Finder → "Open in Cursor") | macOS only; source bundles under `install/macos-quick-actions/`; flushes `pbs -flush` after changes |
| `node.sh` | nvm + Node.js + global npm packages from `npm.txt` | Lazy-loaded in zsh for fast startup |
| `rust.sh` | rustup + cargo-binstall + tools from `cargo.txt` | macOS: Homebrew rustup (code-signed); Linux: sh.rustup.rs. Linux binstall prefers musl targets and smoke-tests each crate's bins for glibc loader failures (refetch → source-build fallback) |
| `go.sh` | `go install` CLI tools from `packages/go.txt` | Go itself via Brewfile (`brew "go"`). `GOBIN=$ARCH_BIN` so binaries land alongside cargo/uv ones. Respects `# linux-only` / `# macos-only` markers (same as `pip.txt`). |
| `python.sh` | uv + CLI tools from `pip.txt` via `uv tool install` | Each tool gets isolated venv under `$LOCAL_PLAT/uv/tools/`; no monolithic venv |
| `claude.sh` | Claude Code binary + plugins + MCP servers + overlay skills + `~/AGENTS.md` symlink | Downloads from Anthropic's GCS bucket; overlay discovery via `DF_OVERLAYS`. MCP servers reconcile declaratively (URL/command drift re-registers). Auth details: see `.claude/rules/agent-tooling.md`. |
| `codex.sh` | Manages `~/.codex/config.toml` (incl. generated `[mcp_servers.*]` from `packages/mcp-servers.txt`), hooks, and chezmoi guard | Codex binary via npm — UNPINNED in `npm.txt`; `codex.sh` reconciles the managed config right after upgrades, so format drift surfaces in its healthcheck. Profiles are delta files `~/.codex/<name>.config.toml` (chezmoi-managed). Auth details: see `.claude/rules/agent-tooling.md`. |
| `claude-desktop.sh` | Tracks Claude Desktop (macOS GUI app) preferences. `apply` (default) deep-merges tracked prefs into the app-owned config; `sync` captures in-app changes back, sanitized | macOS only (self-skips on Linux). App itself via Brewfile (`cask "claude"`). NOT chezmoi-managed — the app owns/rewrites the live config, so a static managed file would clobber + churn. Tracked source: `install/claude-desktop/claude_desktop_config.json`. `sync` strips a blocklist (`*ByAccount`, `remoteToolsDeviceName`, `coworkOnboardingResumeStep`, `epitaxyPrefs`) so account UUIDs / device name / transient UI never reach the public repo; new prefs are captured automatically. Distinct from `claude.sh` (the CLI). |
| `codex-desktop.sh` | Tracks the Codex desktop app (macOS GUI) GUI prefs. `apply` (default) deep-merges tracked prefs into the app-owned state; `sync` extracts in-app changes back | macOS only (self-skips on Linux). App via Brewfile (`cask "codex-app"`, NOT `codex` = CLI). Live state `~/.codex/.codex-global-state.json` also holds prompt history + cloud/account data, so this uses an **allowlist** (the inverse of `claude-desktop.sh`'s blocklist): only named keys (theme, `open-in-target-preferences`, `composer-personality`, `diff-filter`, `skip-full-access-confirm`, `agent-mode-by-host-id`) are emitted — never whole objects. Tracked source: `install/codex-desktop/codex-global-state.json`. Substantive Codex config (config.toml, profiles, rules, themes) is separate, via `codex.sh` + chezmoi. |
| `cursor.sh` | Cursor settings symlinks + extension install; `sync-extensions` subcommand captures new extensions back | Union-only (never removes); app updated via Brewfile cask |
| `vscode.sh` | VS Code extension install; `sync-extensions` subcommand captures new extensions back | Extensions only — settings.json NOT tracked (contains embedded credentials) |
| `local-llm.sh` | Verifies ollama/mlx-lm/mlx-openai-server binaries; creates HF cache dir; `pull-models` subcommand pre-pulls MLX models from `packages/mlx-models.txt` | Warns (does not fail) if tools missing. MLX is the primary local backend (started via `mlxserve`); Ollama remains as fallback. |
| `opencode.sh` | OpenCode binary check (config is pure chezmoi; primary backend is MLX in `opencode.json`) | The old Ollama context-boost alias machinery was removed — nothing consumed it |
| `blender-mcp.sh` | Installs the `blender-mcp` Blender addon (`addon.py` from github.com/ahujasid/blender-mcp) and enables it via headless Blender | MCP server side is separate — see `packages/mcp-servers.txt`. Skips if Blender not installed. |
| `skills-sync.sh` | Installs official agent skills for installed CLIs from `packages/agent-skills.txt` (ast-grep, nushell, jj, qmd self-install) into the shared `~/.claude/skills` tree | Engine: `npx skills add` (vercel-labs; lockfile at `~/.agents/.skill-lock.json`). Installer-managed dirs — never add chezmoi sources for them (one writer per skill dir). |
| `memory.sh` | Agent memory stack: cass binary (GitHub release, checksum-verified) + session-history index, ~/kb knowledge repo, qmd collections + embeddings, memory daemons | qmd MCP daemon on localhost:8181 (LaunchAgent dev.cade.qmd on macOS, lazy-start on Linux); cass watch daemon likewise. `reindex` mode forces re-embedding. Indexes under ~/.cache (scratch), never synced; ~/kb is git-synced. |
| `auth.sh` | Guided API token setup with service registry | Creates `~/.{service}.env` files (chmod 600). Built-in token services: GitHub, Anthropic, OpenAI, Cloudflare, HuggingFace, Tavily, Exa, Firecrawl, Context7, WolframAlpha. Interactive logins (not env files): `gh auth login`, `gcloud auth login`, and `google` (= `gcloud auth application-default login` with the union of MCP scopes + optional `gcloud services enable` of the MCP-backing APIs — authenticates Google's official remote MCP servers). Run `bash auth.sh status` for state, `bash auth.sh <service>` for a single one. Add a token service by appending to `_SERVICE_DEFS`; an interactive login gets its own function + dispatch case. |
| `dirs.sh` | Creates `~/dev`, `~/bones`, `~/misc` | Symlinks to scratch when available |
| `scratch.sh` | Symlinks `~/.local`, `~/.cache`, etc. to scratch space | NFS quota relief |
| `verify-path.sh` | Diagnostic: arch check, library check, duplicates, stale symlinks | Not called by bootstrap |
| `patch-homebrew-*.sh` | Per-formula/toolchain patches for Homebrew on Linux | See `.claude/rules/homebrew.md` for the full patch catalog and the underlying build failures |

## Logging functions

Defined in `_lib.sh`. Use these in install scripts — 4-char label symmetry:

| Function | Label | When to use |
|---|---|---|
| `log_info msg` | `[info]` | Status updates, what's happening |
| `log_okay msg` | `[okay]` | Success, already done, skipping |
| `log_warn msg` | `[warn]` | Non-fatal issues, degraded state |
| `log_fail msg` | `[fail]` | Errors (prints to stderr) |
| `log_debug msg` | `[dbug]` | Verbose trace (only when `DF_DEBUG=1`) |
| `log_section msg` | `=== msg ===` | Major step headers |
| `die msg` | | `log_fail` + `exit 1` |
| `run_logged cmd` | | Run with indented output, shows command + timing in debug mode |

## Bootstrap step order

```
0.   scratch          DF_DO_SCRATCH
0.1  dirs             DF_DO_DIRS
0.5  repo clone       (always)
0.3  PLAT re-detect   (always)
1.   chezmoi install   (always)
2.   chezmoi apply     (always)
2.7  path sanity       (always)
3.   zsh              DF_DO_ZSH
4.   packages         DF_DO_PACKAGES
5.   macOS services   DF_DO_MACOS_SERVICES
5.5  macOS settings   DF_DO_MACOS_SETTINGS
5.6  Quick Actions    DF_DO_MACOS_QUICK_ACTIONS
6.   runtimes         DF_DO_NODE, DF_DO_RUST, DF_DO_GO, DF_DO_PYTHON, DF_DO_CLAUDE, DF_DO_CODEX, DF_DO_CLAUDE_DESKTOP, DF_DO_CODEX_DESKTOP, DF_DO_CURSOR, DF_DO_VSCODE, DF_DO_CMAKE
6.5  local LLM        DF_DO_LOCAL_LLM (local-llm.sh + opencode.sh)
6.6  agent memory     DF_DO_MEMORY (memory.sh — cass + qmd + ~/kb + daemons)
6.65 agent skills     DF_DO_SKILLS (skills-sync.sh — agent-skills.txt)
6.7  blender-mcp      DF_DO_BLENDER_MCP (skips if Blender not installed)
7.   auth             DF_DO_AUTH (off by default)
```

## Overlays

Overlays are private repos at `$DF_ROOT/dotfiles-*/` that extend the public dotfiles
without modifying them. Each overlay can provide:

- `packages/` — package list files mirroring the parent format (e.g. `mcp-servers.txt`,
  `claude-plugins.txt`). Install scripts discover these via `overlay_package_files()`.
- `home/dot_claude/CLAUDE.md` — appended to `~/.claude/CLAUDE.md` via chezmoi template.
- `home/dot_claude/skills/` — deployed to `~/.claude/skills/` by `install/claude.sh`.
- `install/` — install scripts sourcing the parent `_lib.sh`.
- `bootstrap.sh` — run automatically by the parent bootstrap (step 8).

### How overlay package files work

`_lib.sh` defines `DF_OVERLAYS` (array of overlay root paths) and `overlay_package_files()`.
Install scripts call `overlay_package_files "filename.txt"` to get a list of all copies
of that file — base first, then each overlay in sorted order:

```bash
while IFS= read -r _file; do
    _process_entries_from "$_file"
done < <(overlay_package_files "mcp-servers.txt")
```

Currently used by: `install/claude.sh` (MCP servers + plugins) and `install/codex.sh`
(MCP servers). Overlay skills use `DF_OVERLAYS` directly to scan
`home/dot_claude/skills/` in each overlay.

### Chezmoi integration

`run_onchange_*.sh.tmpl` scripts use `{{ glob (joinPath .chezmoi.workingTree "dotfiles-*/packages/...") }}`
to hash overlay files. When an overlay file changes, chezmoi detects the hash change and
re-runs the install script.

## Adding an install script

1. Source `_lib.sh` at the top
2. Guard with `has tool && { log_okay "already installed"; exit 0; }`
3. Install under `$LOCAL_PLAT/` (never `~/.local/bin/` for compiled binaries)
4. Add a `DF_DO_*` flag to `bootstrap.sh`

## Gotchas

- **Don't run install scripts without sourcing `_lib.sh`** — PLAT paths won't be set.
- **`GIT_CONFIG_GLOBAL=/dev/null`** is set by `_lib.sh` intentionally — prevents SSH URL
  rewrites from breaking curl-based installers on machines without SSH keys.
- **macOS Sequoia requires code-signed rustup** — the Homebrew `rustup` formula is signed;
  upstream `sh.rustup.rs` is not and will fail with linker provenance errors. `install/rust.sh`
  handles this, but don't change the macOS Rust install path without understanding why.
- **cargo-binstall gnu prebuilts can outrun the host glibc** — GitHub's ubuntu-latest
  runners moved to 24.04 (glibc 2.39), so upstream gnu release binaries refuse to load
  on older hosts (Ubuntu 22.04 = 2.35 broke atuin/xan/yazi, July 2026). Homebrew's
  keg-only glibc can't help: external prebuilts hardcode the system loader path, and
  brew only patches its own bottles. `rust.sh` therefore passes musl-first `--targets`
  on Linux (static, no glibc dep — same reason the rtk tap ships musl) and smoke-tests
  each crate's bins after install (`_glibc_broken_bins`): loader failure → force
  refetch (musl may now win) → `cargo install` source fallback. The shell profiles
  guard `atuin init` on success, so a broken binary degrades to fzf's ^R instead of
  erroring on every shell.
