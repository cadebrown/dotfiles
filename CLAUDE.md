# CLAUDE.md — dotfiles repo

Personal dotfiles for macOS and Linux, managed with [chezmoi](https://chezmoi.io).
Bootstrapped with `curl | bash`, designed for shared NFS home directories across
CPU architectures. Full docs at [dotfiles.cade.io](https://dotfiles.cade.io).

## Design constraints

These are non-negotiable and shape every decision in the repo:

1. **Cross-platform.** Everything works on both macOS and Linux, on both ARM and x86.
2. **Optional PLAT isolation (off by default).** When `DF_USE_PLAT=1` (or
   `use_plat=true` in chezmoi data), compiled binaries live under `~/.local/$PLAT/`
   where `PLAT` encodes OS + CPU level (e.g. `plat_Linux_x86-64-v3`, `plat_Darwin_arm64`),
   so two machines sharing an NFS home install into separate dirs without conflict.
   Default is `DF_USE_PLAT=0` — flat `~/.local/` layout. PLAT *detection* still runs
   in flat mode so `.plat_env.sh` capability flags (CFLAGS/RUSTFLAGS/HOMEBREW_OPTFLAGS)
   are tuned for the host CPU.
3. **No sudo on Linux.** Homebrew installs to a user-owned prefix with its own glibc.
4. **Idempotent.** Every script is safe to re-run. Check before installing, skip if done.
5. **Single source of truth.** One `Brewfile` for both platforms (`if OS.mac?` for differences).
   One `_lib.sh` for all path variables. One pair of shell profile templates for zsh and bash.

## Where things live

| What | Where | Notes |
|---|---|---|
| Dotfile sources | `home/` | chezmoi templates → applied to `~/` |
| Package lists | `packages/` | `Brewfile`, `cargo.txt`, `pip.txt`, `npm.txt`, `go.txt`, `mlx-models.txt`, `mcp-servers.txt`, `agent-skills.txt`, `claude-*.txt` |
| Agent skills | `home/dot_claude/skills/` | Single source → `~/.claude/skills`; `~/.agents/skills` symlinks there (read by Codex/opencode/pi) |
| Shared template partials | `home/.chezmoitemplates/` | `agents-common.md` (engineering norms) + `voice-common.md` (tone/estimates), shared by Claude/Codex/opencode/pi guidance files |
| Install scripts | `install/` | Each sources `_lib.sh`, each is idempotent |
| Path vars + helpers | `install/_lib.sh` | **Read this first** — defines `PLAT`, `LOCAL_PLAT`, all tool paths, logging |
| PLAT detection | `install/plat/` | `.plat_check.sh` (capability test) + `.plat_env.sh` (compiler flags) per target |
| Shell profiles | `home/dot_zprofile.tmpl`, `home/dot_bash_profile.tmpl` | Identical — runtime PLAT detection + PATH setup |
| chezmoi config | `home/.chezmoi.toml.tmpl` | Prompts for `DF_NAME`/`DF_EMAIL` on first init |
| Bootstrap entry | `bootstrap.sh` | Orchestrates everything; supports `install`/`update`/`upgrade` modes |
| Docs | `docs/` | mdBook → auto-deployed to dotfiles.cade.io |
| Infra | `infra/cloudflare/` | OpenTofu for Cloudflare Pages hosting |
| Tests | `tests/` | Docker-based bats suite |
| Overlays | `dotfiles-*/` | Private repos that extend the parent (e.g. `dotfiles-nvidia/`) |

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

## Install scripts

Each script sources `_lib.sh`, is idempotent, and has a `DF_DO_*` flag in `bootstrap.sh`:

| Script | What it does | Key details |
|---|---|---|
| `chezmoi.sh` | chezmoi binary → `$ARCH_BIN` | Official installer with checksum |
| `plat-decommission.sh` | Removes leftover `~/.local/plat_*/` dirs after switching to flat layout | Standalone only — never invoked by `bootstrap.sh` (including upgrade). Refuses if `DF_USE_PLAT=1`. |
| `zsh.sh` | oh-my-zsh + plugins (pure, autosuggestions, fsh, completions) | Clones or updates via git |
| `homebrew.sh` | macOS: Homebrew + `brew bundle` from Brewfile | Upgrades enabled by default |
| `linux-packages.sh` | Linux: Homebrew + glibc + `brew bundle` | Custom prefix, compiler symlinks, upgrades off by default |
| `macos-services.sh` | Colima + Ollama login services (rootless Docker + local LLM server) | macOS only, skips on Linux |
| `macos-settings.sh` | System prefs via `defaults write` (Dock, Finder, keyboard, trackpad, Safari, iTerm2) | macOS only |
| `macos-quick-actions.sh` | Deploys `*.workflow` bundles to `~/Library/Services/` (right-click Finder → "Open in Cursor") | macOS only; source bundles under `install/macos-quick-actions/`; flushes `pbs -flush` after changes |
| `node.sh` | nvm + Node.js + global npm packages from `npm.txt` | Lazy-loaded in zsh for fast startup |
| `rust.sh` | rustup + cargo-binstall + tools from `cargo.txt` | macOS: Homebrew rustup (code-signed); Linux: sh.rustup.rs |
| `go.sh` | `go install` CLI tools from `packages/go.txt` | Go itself via Brewfile (`brew "go"`). `GOBIN=$ARCH_BIN` so binaries land alongside cargo/uv ones. Respects `# linux-only` / `# macos-only` markers (same as `pip.txt`). |
| `python.sh` | uv + CLI tools from `pip.txt` via `uv tool install` | Each tool gets isolated venv under `$LOCAL_PLAT/uv/tools/`; no monolithic venv |
| `claude.sh` | Claude Code binary + plugins + MCP servers + overlay skills + `~/AGENTS.md` symlink | Downloads from Anthropic's GCS bucket; overlay discovery via `DF_OVERLAYS`. MCP servers reconcile declaratively (URL/command drift re-registers). `auth=gh` uses a connection-time headersHelper (`~/.claude/gh-mcp-headers.sh`); `auth=gcloud` uses `~/.claude/gcloud-mcp-headers.sh` (mints an ADC access token + `x-goog-user-project` per connection — powers Google's official remote MCP servers); `auth=context7` reads `~/.context7.env` (optional). |
| `codex.sh` | Manages `~/.codex/config.toml` (incl. generated `[mcp_servers.*]` from `packages/mcp-servers.txt`), hooks, and chezmoi guard | Codex binary via npm — PINNED in `npm.txt` so binary and config move in lockstep (0.134 redesigned profiles). Profiles are delta files `~/.codex/<name>.config.toml` (chezmoi-managed). `auth=gh` emits `bearer_token_env_var = "GH_TOKEN"`, filled by the `codex()` shell wrapper at launch; `auth=gcloud` emits `bearer_token_env_var = "GOOGLE_MCP_TOKEN"` + `env_http_headers` for `x-goog-user-project`, both filled by the same wrapper (ADC token via `gcloud auth application-default print-access-token`). Rules live in `~/.codex/rules/dotfiles.rules` (managed); `default.rules` is left to Codex's own TUI appends. |
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
| `patch-homebrew-python.sh` | Patches python@3.14 formula for Linux (uuid, test_datetime) | Applied automatically during linux-packages.sh |
| `patch-homebrew-superenv.sh` | Patches Linux superenv (linux-headers isystem, gnulib probe, glibc -L) | Three endemic build failures on custom prefix; see script for details |
| `patch-homebrew-stdenv.sh` | Patches Linux stdenv for rare stdenv builds (linux-headers isystem) | Companion to superenv patch; stdenv builds skip the shim |
| `patch-homebrew-ncurses.sh` | Patches ncurses formula for Linux (linux-headers CPPFLAGS) | Fixes configure cascade failure from missing asm/ioctls.h + linux/limits.h |
| `patch-homebrew-m4.sh` | Patches m4 formula for Linux (bypass gnulib undeclared-builtin probe) | GCC builtins cause probe to silently succeed, configure aborts |
| `patch-homebrew-pkgconf.sh` | Patches pkgconf formula for Linux (same gnulib probe as m4) | pkgconf is a critical dep (openssh, podman, fish); same fix as m4 |
| `patch-homebrew-cc65.sh` | Patches cc65 formula for Linux (linux-headers CPATH) | cc65 Makefile uses $(CC) $(CFLAGS) without $(CPPFLAGS); CPATH is reliable |
| `patch-homebrew-mesa.sh` | Patches mesa formula for Linux (pyyaml binary wheel) | Cython SIGILL in superenv: pyyaml source build crashes; use binary wheel |
| `patch-homebrew-fastfetch.sh` | Patches fastfetch formula for Linux (disable WSL GPU detection) | directx-headers shim fails at custom prefix |
| `patch-homebrew-fish.sh` | Patches fish formula for Linux (disable sphinx man pages) | Headless nodes lack configured locale for Python/sphinx |
| `patch-homebrew-rpm.sh` | Patches rpm formula for Linux (LUA_MATH_LIBRARY cmake fix) | cmake's FindLua can't find libm via find_library; glibc is keg-only |
| `patch-homebrew-systemd.sh` | Patches systemd formula for Linux (lxml binary wheel) | Cython SIGILL in superenv: lxml source build crashes; use binary wheel |
| `patch-homebrew-netpbm.sh` | Patches netpbm formula for Linux (GCC 15 C23 + incompatible-pointer fix) | GCC 15 defaults to C23 (bool typedef fails) and promotes -Wincompatible-pointer-types to error |

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

## PATH priority

Shell profiles prepend tool paths on top of Homebrew. Highest priority first.
`$_LOCAL_PLAT` resolves to either `$HOME/.local/$_PLAT` (when `use_plat=true`)
or `$HOME/.local` (default).

```
$_LOCAL_PLAT/cargo/bin        Rust tools (fd, sd, zoxide, etc.)
$_LOCAL_PLAT/nvm/.../bin      Node.js via nvm
$_LOCAL_PLAT/bin              chezmoi, uv, claude, plus go-installed binaries (GOBIN=here)
~/.local/bin                  arch-neutral scripts only (collapses to $_LOCAL_PLAT/bin in flat mode — deduped via typeset -U)
/opt/homebrew/bin             Homebrew (macOS)
/usr/bin                      system
```

Go env: `GOPATH=$LOCAL_PLAT/go` (module cache + workspace), `GOBIN=$ARCH_BIN`
(binary install target — same dir as cargo/uv outputs, so no second PATH entry),
`GOCACHE=$LOCAL_PLAT/go-build` (build cache, parallel to `CARGO_TARGET_DIR`).

Note: `$LOCAL_PLAT/venv/bin` was removed — Python CLI tools now use `uv tool install`
(isolated venvs under `$LOCAL_PLAT/uv/tools/`).

**Never install the same tool in two layers** — installed-location paths win,
but duplicates waste time and break `*-self-update` flows that compare argv[0]
against a recorded install dir (uv was the canonical example of this footgun).

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

## CMake toolchains

`install/cmake.sh` deploys `install/cmake/toolchains/{llvm,gcc}.cmake` to
`$LOCAL_PLAT/cmake/toolchains/`. `~/.profile` sets `CMAKE_TOOLCHAIN_FILE` to
the LLVM file when Homebrew LLVM is present. Switch with:

```sh
CMAKE_TOOLCHAIN_FILE="$_LOCAL_PLAT/cmake/toolchains/gcc.cmake" cmake -B build
```

Source files live in `install/cmake/toolchains/` — edit them there, not in the deployed copies.

## CUDA convention

CUDA is **not** managed by bootstrap. It must be installed separately (system package,
NVIDIA runfile, or sysadmin-provided module). To integrate it with the PLAT layout:

```sh
# Point the per-PLAT symlink at whichever toolkit this machine uses
ln -sfn /usr/local/cuda              "$_LOCAL_PLAT/.cuda"   # system default
ln -sfn /opt/nvidia/cuda/12.6        "$_LOCAL_PLAT/.cuda"   # versioned
ln -sfn "$(which nvcc | xargs dirname)/../" "$_LOCAL_PLAT/.cuda"  # from PATH
```

`~/.profile` resolves `$_LOCAL_PLAT/.cuda` via `realpath` and exports:
- `CUDA_PATH` — used by many build systems and NVCC itself
- `CUDAToolkit_ROOT` — the canonical CMake variable for `find_package(CUDAToolkit)`
- Prepends `$CUDA_PATH/bin` to `PATH` so `nvcc` is available

Both CMake toolchain files (`llvm.cmake`, `gcc.cmake`) check for
`$_LOCAL_PLAT/.cuda/bin/nvcc` and set `CMAKE_CUDA_COMPILER` when found.
`CMAKE_CUDA_HOST_COMPILER` is always set to the toolchain's C++ compiler.

Different machines on a shared NFS home can point `$LOCAL_PLAT/.cuda` at
different toolkit versions — no conflicts.

## chezmoi template rules

Templates in `home/*.tmpl` render on `chezmoi apply`. On shared NFS homes, **templates
must render identically on every machine** — otherwise machines overwrite each other.

- **Use `{{ .chezmoi.os }}`** (darwin/linux) for platform branching — this is stable across shared homes
- **Never use `{{ .chezmoi.arch }}`** or per-machine values in templates — use shell runtime detection instead
- Template variables: `{{ .name }}`, `{{ .email }}` (from chezmoi data), `{{ .chezmoi.os }}`, `{{ .chezmoi.homeDir }}`

### Shared partials

`home/.chezmoitemplates/` holds reusable template fragments:

- `agents-common.md` — engineering norms (how-I-work, no-shortcut-fixes, tool
  preferences, git) shared across all four tools' guidance files.
- `voice-common.md` — tone/communication + estimate conventions. Single source
  for "how output should read". Claude loads it via the `cade` output style
  (`home/dot_claude/output-styles/cade.md.tmpl`, system-prompt level); Codex,
  opencode, and pi include it directly in their always-on file. It is
  deliberately **not** in `agents-common.md`, so Claude doesn't load voice twice.

Reference either from a `.tmpl` with:

```gotmpl
{{ template "agents-common.md" . }}
{{ template "voice-common.md" . }}
```

Edit a partial once and every consuming tool updates on the next `chezmoi apply`.
See [docs/usage/agents.md](docs/usage/agents.md).

## Rules for agents

### Before making changes

- **Read `install/_lib.sh`** — it defines every path variable, logging function, and helper.
  All install scripts source it. Don't guess paths; use the variables it exports.
- **Check for duplicates** across `packages/cargo.txt`, `packages/Brewfile`, and `packages/npm.txt`
  before adding a tool. Never install the same thing in two layers.
- **Read the relevant install script** before modifying it. Understand the idempotency guard.

### Adding a tool

Priority order — native installer first, Homebrew as fallback:

1. `packages/cargo.txt` — Rust crates (cargo-binstall downloads pre-built binaries)
2. `packages/npm.txt` — npm packages
3. `packages/pip.txt` — Python packages (installed via `uv tool install`)
   - `# macos-only` — skip on Linux (e.g. `mlx-lm` requires Apple Metal)
   - `# python=X.Y` — pin to a specific Python version (e.g. `mlx-openai-server` needs 3.12 because outlines-core has no cp313/cp314 wheels)
4. `packages/go.txt` — Go CLI tools (installed via `go install`)
   - `# linux-only` / `# macos-only` — same parser shape as `pip.txt`. Useful when macOS gets the tool via a Brewfile cask/formula and only Linux needs the source build (e.g. `entire`).
5. `packages/Brewfile` — everything else (C libraries, GUI apps, tools without native installers)
6. New `install/*.sh` script — source `_lib.sh`, add `DF_DO_*` flag to `bootstrap.sh`, add tests

macOS-only things go in `if OS.mac?` blocks in the Brewfile.

### Adding an install script

1. Source `_lib.sh` at the top
2. Guard with `has tool && { log_okay "already installed"; exit 0; }`
3. Install under `$LOCAL_PLAT/` (never `~/.local/bin/` for compiled binaries)
4. Add a `DF_DO_*` flag to `bootstrap.sh`

### Editing dotfiles

- Edit sources in `home/` (e.g. `home/dot_zshrc.tmpl`), never the deployed files
- Binary files like `dot_iterm2/*.plist` are not templates — no `.tmpl` extension
- Shell profiles (`dot_zprofile.tmpl`, `dot_bash_profile.tmpl`) must stay in sync

### Env var naming

All user-facing env vars use the `DF_` prefix:

- Config: `DF_NAME`, `DF_EMAIL`, `DF_REPO`, `DF_PATH`, `DF_SCRATCH`, `DF_LINKS`, `DF_DIRS`, etc.
- Flags: `DF_DO_PACKAGES`, `DF_DO_RUST`, `DF_DO_AUTH`, etc. (set to `0` to skip, `1` to enable)
- Behavior: `DF_USE_PLAT=1` opts in to per-PLAT directory isolation (default 0, flat layout)
- Debug: `DF_DEBUG=1` for verbose output with timing

Internal vars: `DF_ROOT` (repo root), `DF_PACKAGES` (packages dir), `DF_INSTALL_DIR` (install dir).
Tool-standard vars (`PLAT`, `LOCAL_PLAT`, `RUSTUP_HOME`, `CARGO_HOME`, `NVM_DIR`, etc.) keep
their conventional names.

## Git hooks

A global pre-push hook scans commits for secrets using [gitleaks](https://github.com/gitleaks/gitleaks).

- Installed via `brew "gitleaks"` in `packages/Brewfile`
- Hook lives at `home/dot_config/git/hooks/executable_pre-push` (deployed by chezmoi)
- `~/.gitconfig` sets `core.hooksPath = ~/.config/git/hooks` — applies to **every repo**, not just dotfiles
- Scans only the commits being pushed (not full history) for speed
- Gracefully skips if gitleaks is not yet installed
- Emergency bypass: `git push --no-verify`

To run a full history scan manually: `gitleaks git --no-banner` from the repo root.

## Toolchain switching

The `tc` function in `.zshrc` switches CMake toolchains per-session:
`tc gcc-13`, `tc gcc-15`, `tc llvm-22`, `tc llvm-21`, `tc list`, `tc` (show current).
GCC variants set CC/CXX/AR/RANLIB/NM; LLVM variants only set CMAKE_TOOLCHAIN_FILE.

## Compiler caching

`~/.profile` auto-configures ccache and sccache when installed. Key settings:
- `CCACHE_BASEDIR` = scratch root (enables cross-directory cache sharing)
- `CCACHE_COMPILERCHECK=content` (survives brew reinstalls)
- `CCACHE_SLOPPINESS=file_stat_matches,time_macros` (higher hit rate)
- `CCACHE_HARDLINK=1` (zero-copy cache hits on same partition)
- `RUSTC_WRAPPER=sccache` for Rust builds

## Gotchas

These are non-obvious things that have caused real bugs:

- **gitleaks pre-push hook will block commits with secrets** — `core.hooksPath` applies globally.
  If a push is blocked unexpectedly, run `gitleaks git --no-banner` to review the finding.
  Emergency bypass: `git push --no-verify`. Don't disable the hook permanently.
- **`sourceDir` in chezmoi.toml must be a top-level key** — not inside `[data]`. Misplacing
  it silently breaks `chezmoi diff` and `chezmoi update`.
- **`GIT_CONFIG_GLOBAL=/dev/null`** is set by `_lib.sh` intentionally — prevents SSH URL
  rewrites from breaking curl-based installers on machines without SSH keys.
- **macOS Sequoia requires code-signed rustup** — the Homebrew `rustup` formula is signed;
  upstream `sh.rustup.rs` is not and will fail with linker provenance errors. `install/rust.sh`
  handles this, but don't change the macOS Rust install path without understanding why.
- **Don't use legacy paths** (`~/.nvm`, `~/.rustup`, `~/.cargo`) — everything is under `$LOCAL_PLAT/`.
- **Don't run install scripts without sourcing `_lib.sh`** — PLAT paths won't be set.
- **Brew zsh needs its own locale data on Linux.** Homebrew's glibc has no `lib/locale/`
  archive, so `setlocale()` falls back to C/ASCII and `wcwidth()` counts bytes instead of
  display columns — ZLE completion leaves remnant characters. Fix: `linux-packages.sh`
  generates `en_US.UTF-8` into `$LOCAL_PLAT/locale/` via brew's `localedef`; shell profiles
  export `LOCPATH` pointing there. Test: `bash tests/test-locale.sh`.
- **Homebrew upgrades are off by default on Linux** (`DF_BREW_UPGRADE=0`) because glibc
  upgrades can break every installed binary. Use `bootstrap.sh upgrade` deliberately.
- **`brew bundle` skips `auto_updates: true` casks** — Cursor, VS Code, iTerm2, etc.
  self-update in place, so `brew bundle install --upgrade` leaves their cask metadata
  stale. `homebrew.sh` runs `brew upgrade --cask --greedy` after the bundle when
  `DF_BREW_UPGRADE=1` to keep the records in sync with the running apps.
- **Python@3.14 formula is patched on Linux** — `install/patch-homebrew-python.sh` fixes uuid
  and test_datetime build issues. `HOMEBREW_NO_AUTO_UPDATE=1` prevents Homebrew from
  overwriting patches. Formulas depending on python@3.14 (vim, imagemagick, graphviz, ffmpeg,
  glances) now build successfully with these patches.
- **Python dev headers come from Homebrew** — python@3.14 provides `Python.h` and
  `libpython3.14.so` at `$(brew --prefix)/opt/python@3.14/include/python3.14/`.
  CMake's `FindPython3` discovers these automatically via `brew shellenv` paths.
  There is no user-level venv — CLI tools use `uv tool install` (isolated venvs),
  and library work uses per-project `uv init` / `uv sync`.
- **Several formulas need linux-headers@6.8 CPPFLAGS on custom prefix** — Homebrew glibc's
  headers chain to kernel headers (`asm/ioctls.h`, `linux/limits.h`, `linux/errno.h`) that are
  NOT in the default include path. Any formula that doesn't declare `linux-headers@6.8` as a
  build dep will fail. Current patches: `ncurses` (all configure checks cascade-fail when
  `<stdio.h>` can't include `linux/limits.h`), `cc65` (Makefile doesn't propagate CPPFLAGS).
- **gcc formula is unversioned and tracks latest GCC** — as of GCC 15, implicit function
  declarations are errors by default, breaking configure scripts in m4 1.4.21 and ncurses 6.6.
  `linux-packages.sh` pre-installs gcc@13 and sets `HOMEBREW_CC=gcc-13` for all source builds.
  The m4 formula is additionally patched to bypass a gnulib probe that fails even with gcc-13.
- **mold/lld need `--disable-new-dtags` on Linux** — these linkers default to DT_RUNPATH,
  which is searched after ld.so.cache, so the system's older libstdc++ wins over Homebrew's.
  All four CMake toolchain files add `-Wl,--disable-new-dtags` when selecting mold or lld.
  `~/.profile` also sets `LDFLAGS` with the same flag for non-CMake builds.
- **openssh is in Brewfile cross-platform** — on Linux, the system ssh may link against a
  different OpenSSL than Homebrew's, causing `git push` failures. Brew's openssh uses
  Homebrew's OpenSSL consistently.
- **Cython packages SIGILL in superenv (pip --no-binary)** — Homebrew's `venv.pip_install`
  always passes `--no-binary=:all:`, forcing source builds. Packages that use Cython
  (lxml, pyyaml) fail with exit -4 (SIGILL) in the superenv context. Fix: install these
  packages with `--prefer-binary` instead. Currently patched: `systemd` (lxml), `mesa`
  (pyyaml). See the respective `patch-homebrew-*.sh` for details.
- **cmake's FindLua can't find glibc's libm on Linux** — glibc is keg-only, so its lib
  dir is not in cmake's `find_library()` search path. FindLua requires LUA_MATH_LIBRARY
  (libm) to link liblua. The `rpm` formula is patched to pass
  `-DLUA_MATH_LIBRARY=$(Formula["glibc"].opt_lib/"libm.so")` explicitly.
- **glibc -L missing from HOMEBREW_LIBRARY_PATHS (root cause unclear)** — despite glibc
  being a keg-only transitive dep of many packages, its opt_lib is not added to the
  linker's `-L` path. The superenv shim adds `-Wl,-rpath-link` for glibc but this is
  insufficient for versioned symbol resolution (GLIBC_2.33+ in libstdc++.so). Fixed by
  `patch-homebrew-superenv.sh` Patch 3: adds `-L/brew/opt/glibc/lib` alongside
  `-rpath-link` in the shim's `ldflags_linux`.
- **GCC 15 is stricter: C23 default + new errors** — GCC 15 changed the default C
  standard from C17 to C23 (breaks `typedef unsigned char bool` in netpbm), and promotes
  `-Wincompatible-pointer-types` and `-Wimplicit-function-declaration` from warnings to
  errors. Per-formula patches (`netpbm`, etc.) add `-std=gnu17` and the relevant `-Wno-*`
  flags on Linux.
- **rtk: install from the official tap, not homebrew-core** — homebrew-core lags badly
  (shipped 0.29 when upstream stable was 0.42+). 0.29 sits in the window where rtk had
  *removed* the `rtk hook <harness>` subcommand in favor of `rtk rewrite` scripts, so the
  old `rtk hook claude` hook command made rtk try to exec a binary named `hook` and failed
  every PreToolUse with "No such file or directory". `packages/Brewfile` uses
  `brew "rtk-ai/tap/rtk"` (prebuilt, all 4 platforms, Linux x86_64 is musl = no glibc
  dependency). 0.42+ re-introduced `rtk hook claude|cursor|gemini|copilot` as the canonical
  built-in; our hooks are thin wrappers (`dot_claude/rtk-rewrite.sh`,
  `dot_cursor/hooks/rtk-rewrite.sh`) that PATH-harden + `command -v rtk || exit 0` then
  delegate to it. opencode/pi use in-process TS plugins calling `rtk rewrite` (no built-in
  hook exists for those). Codex is instruction-only — it has no command-rewrite hook.
- **rtk needs an allow-rule or it defaults to "ask"** — rtk reads deny/ask/allow from the
  host's own permission config and defaults unmatched commands to *ask* (least-privilege).
  For Claude that means the rewrite applies but without an explicit allow (fine under
  `bypassPermissions`); for Cursor an *ask* verdict yields **no rewrite at all** (Cursor's
  protocol can't rewrite-and-prompt). So `dot_claude/settings.json` has
  `permissions.allow: ["Bash(*)"]` and `dot_cursor/cli-config.json` has
  `permissions.allow: ["Shell(*)"]` — these make every rewrite auto-allow, fully transparent.
- **GitHub MCP can't use OAuth** — `api.githubcopilot.com/mcp` advertises OAuth, but
  GitHub's IdP doesn't implement Dynamic Client Registration (RFC 7591), so Claude
  Code's `/mcp` Authenticate flow fails with "Incompatible auth server" (tracked in
  anthropics/claude-code#3433). GitHub's own install guide just recommends a static PAT,
  so `mcp-servers.txt` uses `auth=gh`: Claude resolves the token at connection time via
  `~/.claude/gh-mcp-headers.sh` (headersHelper), Codex via `bearer_token_env_var =
  "GH_TOKEN"` filled by the `codex()` shell wrapper. **Token source is `$GITHUB_TOKEN`
  (the PAT in `~/.github.env`) first, `gh auth token` keyring as fallback** — one value,
  sourced into every shell, shared across the NFS fleet, no token in any MCP config.
- **Google MCP is split: Cloud = official ADC, Workspace = community server** —
  two different mechanisms for two different reasons.
  **Cloud** (`cloud-run`/`cloud-resmgr`/`cloud-storage`/`bigquery`): Google's
  official remote MCP endpoints (`*.googleapis.com/mcp`), authenticated by
  Application Default Credentials. `cloud-platform` is not a sensitive scope, so
  `bash install/auth.sh google` works with gcloud's built-in OAuth client and
  zero setup; the `auth=gcloud` helpers mint a short-lived token per connection.
  **Workspace** (`google-workspace` = Gmail/Calendar/Drive): the community
  `uvx workspace-mcp` (taylorwilsdon) server, full read+WRITE, OAuth client creds
  in `~/.google.env` (`bash install/auth.sh workspace`). We did NOT use Google's
  official Workspace MCP because (a) it's Developer Preview + read-mostly (Gmail
  drafts-only/no send, Calendar read-only, Drive no edit/delete), and (b) its
  scopes are *restricted* — Google blocks gcloud's generic client ("This app is
  blocked"), so it needs a self-made OAuth client anyway. At equal client-setup
  cost, full write beats read-only. The community server uses the STANDARD
  Gmail/Calendar/Drive APIs (no Preview Program). The `auth=gcloud` helpers
  mint a short-lived access token at connection time
  (Claude: `~/.claude/gcloud-mcp-headers.sh`; Codex: `GOOGLE_MCP_TOKEN` via the
  `codex()` wrapper) — nothing at rest, like `auth=gh`. Three gotchas: (1) ADC
  access tokens expire ~hourly and the helper runs at *connect*, so an MCP
  session held open >1h needs a `/mcp` reconnect to re-mint. (2) User-credential
  calls need a quota project via `x-goog-user-project` — `auth.sh google` sets it
  with `gcloud auth application-default set-quota-project`; without it some Cloud
  APIs 403 "user project required". (3) The Workspace servers are **Developer
  Preview and read-mostly** (Gmail = drafts only, no send; Calendar = read-only;
  Drive = create/read, no edit/delete) and need Workspace Developer Preview
  Program enrollment + `gcloud services enable <product>mcp.googleapis.com`. For
  full Workspace *write* today you'd swap to a community server (e.g.
  taylorwilsdon/google_workspace_mcp); we chose official+ADC for cleanliness.
- **A stale `GITHUB_TOKEN` silently shadows the gh keyring** — `gh auth token` returns
  `$GH_TOKEN`/`$GITHUB_TOKEN` ahead of its stored credential when either is set, by design
  (cli/cli#8347), and `gh auth login` even refuses to run while the env var is non-empty.
  So an expired PAT in `~/.github.env` poisons both the MCP helper and `gh` itself, and
  the only symptom is a cryptic MCP 401. The headersHelper now reads `$GITHUB_TOKEN`
  directly (env-first is explicit, not accidental), and `auth.sh status` pings the API to
  print a `github-mcp: live / EXPIRED` line so expiry is visible. Rotate with
  `bash install/auth.sh github`; to switch a machine to the keyring instead, clear
  `GITHUB_TOKEN` then `gh auth login`. After rotating, relaunch Claude Code — the running
  process caches the old env token at launch.
- **Codex profiles are per-file since 0.134** — `[profiles.*]` tables in config.toml
  are silently ignored; profiles are delta-only `~/.codex/<name>.config.toml` files
  with top-level keys. `@openai/codex` is version-pinned in `packages/npm.txt` so the
  binary can't drift ahead of the config — bump the pin and run
  `bash install/codex.sh check` together.
- **Codex `approval_policy` uses the granular form** — a plain `"never"` silently
  suppresses every `decision=prompt` rule in `rules/dotfiles.rules` (rm, git reset
  --hard, git push). `{ granular = { rules = true, ... } }` keeps those prompts live
  while everything else stays autonomous. Watch openai/codex#25312.
- **Test `~/.homebrew/bin/brew`, never `-e ~/.homebrew`** — Homebrew stores tap-trust
  state at `~/.homebrew/trust.json` on macOS, so a bare directory test misroutes the
  shell profiles onto the Linux user-prefix branch (bit us June 2026; both profile
  templates now guard on the binary).
- **Third-party taps must be trusted before `brew bundle`** — recent Homebrew refuses
  to load formulae/casks from non-core taps until trusted (gated by
  `HOMEBREW_REQUIRE_TAP_TRUST`), so an untrusted tap fails its package with "Refusing
  to load formula … from untrusted tap". `trust_brewfile_taps()` in `_lib.sh` derives
  the tap list from the Brewfile (explicit `tap` lines + `owner/repo` prefix of
  three-part `brew`/`cask` refs) and runs `brew trust --tap` for each before the bundle
  in both `homebrew.sh` and `linux-packages.sh`. The Brewfile stays the single source
  of truth — no separate trust list. Adding a tapped formula is enough; trust follows.
- **cass Linux prebuilts need host glibc >= 2.38** — they link system glibc, not the
  Homebrew one. install/memory.sh falls back to `cargo install --git` on older hosts.
  Its brew tap is NOT used (formula sha lagged a release-asset re-upload, June 2026).
- **qmd needs Homebrew sqlite on macOS** — the system libsqlite3 blocks loadable
  extensions, killing qmd's vector index. `brew "sqlite"` is in the Brewfile.
- **Memory indexes are per-machine** — qmd (~/.cache/qmd) and cass (~/.cache/cass)
  rebuild locally; only ~/kb (git) and dotfiles sync across machines.
- **`~/.claude` must not be in scratch links** — chezmoi manages `home/dot_claude/` as a
  real directory. If `scratch.sh` symlinks `~/.claude` to scratch, `chezmoi apply` replaces
  the symlink with a directory containing only managed files, orphaning all conversation
  history, sessions, and file-history on scratch.
- **docker-completion collides with the docker formula** — the `docker` formula now ships
  its own shell completions, but older machines carry `docker-completion` as a leftover
  dependency. Both want `etc/.../completions/docker`, so `brew bundle` aborts linking
  `docker` ("Could not symlink … belonging to docker-completion"). Upstream deprecated
  docker-completion (disables 2027-05-31, replacement `docker`), so `homebrew.sh` removes
  the orphan keg before the bundle. It's not in the Brewfile — fresh machines never hit
  this. Manual fix if needed: `brew uninstall --ignore-dependencies docker-completion`.

## Reference

For detailed documentation on any topic, see the docs site or source files:

- **Bootstrap flow and skip flags:** `bootstrap.sh` header comments, [docs/setup/bootstrap.md](docs/setup/bootstrap.md)
- **Package management:** [docs/setup/packages.md](docs/setup/packages.md)
- **Chezmoi workflow:** [docs/setup/chezmoi.md](docs/setup/chezmoi.md)
- **Troubleshooting:** [docs/usage/troubleshooting.md](docs/usage/troubleshooting.md)
- **PLAT specs and compiler flags:** `install/plat/` directories
- **verify-path.sh flags:** `bash install/verify-path.sh --help`
- **nvm lazy loading design:** `home/dot_zprofile.tmpl` (PATH entry) + `home/dot_zshrc.tmpl` (oh-my-zsh plugin)
- **Homebrew on Linux internals:** `install/linux-packages.sh` comments
- **Infra/hosting:** [docs/infra/docs-and-hosting.md](docs/infra/docs-and-hosting.md)
