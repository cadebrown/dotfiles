# CLAUDE.md — dotfiles repo

Personal dotfiles for macOS and Linux, managed with [chezmoi](https://chezmoi.io).
Bootstrapped with `curl | bash`, designed for shared NFS home directories across
CPU architectures. Full docs at [dotfiles.cade.io](https://dotfiles.cade.io).

## Design constraints

These are non-negotiable and shape every decision in the repo:

1. **Cross-platform.** Everything works on both macOS and Linux, on both ARM and x86.
2. **PLAT isolation.** Compiled binaries live under `~/.local/$PLAT/` where `PLAT` encodes
   OS + CPU level (e.g. `plat_Linux_x86-64-v3`, `plat_Darwin_arm64`). Two machines sharing
   an NFS home install into separate PLAT dirs — no conflicts. Text configs are shared.
3. **No sudo on Linux.** Homebrew installs to a user-owned prefix with its own glibc.
4. **Idempotent.** Every script is safe to re-run. Check before installing, skip if done.
5. **Single source of truth.** One `Brewfile` for both platforms (`if OS.mac?` for differences).
   One `_lib.sh` for all path variables. One pair of shell profile templates for zsh and bash.

## Where things live

| What | Where | Notes |
|---|---|---|
| Dotfile sources | `home/` | chezmoi templates → applied to `~/` |
| Package lists | `packages/` | `Brewfile`, `cargo.txt`, `pip.txt`, `npm.txt`, `claude-*.txt` |
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

- `packages/` — package list files mirroring the parent format (e.g. `claude-mcp.txt`,
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
done < <(overlay_package_files "claude-mcp.txt")
```

Currently used by: `install/claude.sh` (MCP servers + plugins). Overlay skills use
`DF_OVERLAYS` directly to scan `home/dot_claude/skills/` in each overlay.

### Chezmoi integration

`run_onchange_*.sh.tmpl` scripts use `{{ glob (joinPath .chezmoi.workingTree "dotfiles-*/packages/...") }}`
to hash overlay files. When an overlay file changes, chezmoi detects the hash change and
re-runs the install script.

## Install scripts

Each script sources `_lib.sh`, is idempotent, and has a `DF_DO_*` flag in `bootstrap.sh`:

| Script | What it does | Key details |
|---|---|---|
| `chezmoi.sh` | chezmoi binary → `$ARCH_BIN` | Official installer with checksum |
| `zsh.sh` | oh-my-zsh + plugins (pure, autosuggestions, fsh, completions) | Clones or updates via git |
| `homebrew.sh` | macOS: Homebrew + `brew bundle` from Brewfile | Upgrades enabled by default |
| `linux-packages.sh` | Linux: Homebrew + glibc + `brew bundle` | Custom prefix, compiler symlinks, upgrades off by default |
| `macos-services.sh` | Colima + Ollama login services (rootless Docker + local LLM server) | macOS only, skips on Linux |
| `macos-settings.sh` | System prefs via `defaults write` (Dock, Finder, keyboard, trackpad, Safari, iTerm2) | macOS only |
| `macos-quick-actions.sh` | Deploys `*.workflow` bundles to `~/Library/Services/` (right-click Finder → "Open in Cursor") | macOS only; source bundles under `install/macos-quick-actions/`; flushes `pbs -flush` after changes |
| `node.sh` | nvm + Node.js + global npm packages from `npm.txt` | Lazy-loaded in zsh for fast startup |
| `rust.sh` | rustup + cargo-binstall + tools from `cargo.txt` | macOS: Homebrew rustup (code-signed); Linux: sh.rustup.rs |
| `python.sh` | uv + CLI tools from `pip.txt` via `uv tool install` | Each tool gets isolated venv under `$LOCAL_PLAT/uv/tools/`; no monolithic venv |
| `claude.sh` | Claude Code binary + plugins + MCP servers + overlay skills | Downloads from Anthropic's GCS bucket; overlay discovery via `DF_OVERLAYS` |
| `codex.sh` | Codex CLI binary from GitHub releases | Platform detection + checksum |
| `cursor.sh` | Cursor settings symlinks + extension install; `sync-extensions` subcommand captures new extensions back | Union-only (never removes); app updated via Brewfile cask |
| `vscode.sh` | VS Code extension install; `sync-extensions` subcommand captures new extensions back | Extensions only — settings.json NOT tracked (contains embedded credentials) |
| `local-llm.sh` | Creates PLAT-isolated HuggingFace cache dir, verifies ollama/mlx-lm/aider binaries | Warns but does not fail if tools are absent |
| `opencode.sh` | Creates Ollama context-boosted model aliases via Modelfile | Skips if source model not installed; omits gpt-oss:120b (confirmed hang bug) |
| `local-llm.sh` | Creates PLAT-isolated dirs for Ollama + HuggingFace model storage; verifies mlx-lm and aider binaries | macOS primary; dirs also created on Linux |
| `opencode.sh` | Creates context-boosted Ollama model aliases for OpenCode (256K for qwen3-coder, 128K for others) | Requires ollama server running; skips missing source models |
| `auth.sh` | Interactive API token setup (GitHub, Anthropic, OpenAI) | Creates `~/.{service}.env` files, chmod 600 |
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

Shell profiles prepend PLAT paths on top of Homebrew. Highest priority first:

```
$LOCAL_PLAT/cargo/bin         Rust tools (fd, sd, zoxide, etc.)
$LOCAL_PLAT/nvm/.../bin       Node.js via nvm
$LOCAL_PLAT/bin               chezmoi, uv, claude
~/.local/bin                  arch-neutral scripts only
/opt/homebrew/bin             Homebrew (macOS)
/usr/bin                      system
```

Note: `$LOCAL_PLAT/venv/bin` was removed — Python CLI tools now use `uv tool install`
(isolated venvs under `$LOCAL_PLAT/uv/tools/`).

**Never install the same tool in two layers** — PLAT paths win, but duplicates waste time.

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
6.   runtimes         DF_DO_NODE, DF_DO_RUST, DF_DO_PYTHON, DF_DO_CLAUDE, DF_DO_CODEX, DF_DO_CURSOR, DF_DO_VSCODE, DF_DO_CMAKE
6.5  local LLM        DF_DO_LOCAL_LLM (local-llm.sh + opencode.sh)
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
   - `# python=X.Y` — pin to a specific Python version (e.g. `aider-chat` needs 3.12 because scipy has no wheels for 3.14+)
4. `packages/Brewfile` — everything else (C libraries, GUI apps, tools without native installers)
5. New `install/*.sh` script — source `_lib.sh`, add `DF_DO_*` flag to `bootstrap.sh`, add tests

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
- **`~/.claude` must not be in scratch links** — chezmoi manages `home/dot_claude/` as a
  real directory. If `scratch.sh` symlinks `~/.claude` to scratch, `chezmoi apply` replaces
  the symlink with a directory containing only managed files, orphaning all conversation
  history, sessions, and file-history on scratch.

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
