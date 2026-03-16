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

## Install scripts

Each script sources `_lib.sh`, is idempotent, and has a `DF_DO_*` flag in `bootstrap.sh`:

| Script | What it does | Key details |
|---|---|---|
| `chezmoi.sh` | chezmoi binary → `$ARCH_BIN` | Official installer with checksum |
| `zsh.sh` | oh-my-zsh + plugins (pure, autosuggestions, fsh, completions) | Clones or updates via git |
| `homebrew.sh` | macOS: Homebrew + `brew bundle` from Brewfile | Upgrades enabled by default |
| `linux-packages.sh` | Linux: Homebrew + glibc + `brew bundle` | Custom prefix, compiler symlinks, upgrades off by default |
| `macos-services.sh` | Colima login service (rootless Docker) | macOS only, skips on Linux |
| `macos-settings.sh` | System prefs via `defaults write` (Dock, Finder, keyboard, trackpad, Safari, iTerm2) | macOS only |
| `node.sh` | nvm + Node.js + global npm packages from `npm.txt` | Lazy-loaded in zsh for fast startup |
| `rust.sh` | rustup + cargo-binstall + tools from `cargo.txt` | macOS: Homebrew rustup (code-signed); Linux: sh.rustup.rs |
| `python.sh` | uv + venv + packages from `pip.txt` | Venv at `$LOCAL_PLAT/venv` with `--seed` |
| `claude.sh` | Claude Code binary + plugins + MCP servers | Downloads from Anthropic's GCS bucket |
| `codex.sh` | Codex CLI binary from GitHub releases | Platform detection + checksum |
| `auth.sh` | Interactive API token setup (GitHub, Anthropic, OpenAI) | Creates `~/.{service}.env` files, chmod 600 |
| `dirs.sh` | Creates `~/dev`, `~/bones`, `~/misc` | Symlinks to scratch when available |
| `scratch.sh` | Symlinks `~/.local`, `~/.cache`, etc. to scratch space | NFS quota relief |
| `verify-path.sh` | Diagnostic: arch check, library check, duplicates, stale symlinks | Not called by bootstrap |
| `patch-homebrew-python.sh` | Patches python@3.14 formula for Linux (uuid, test_datetime) | Applied automatically during linux-packages.sh |

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
$LOCAL_PLAT/venv/bin          Python venv
$LOCAL_PLAT/cargo/bin         Rust tools (fd, sd, zoxide, etc.)
$LOCAL_PLAT/nvm/.../bin       Node.js via nvm
$LOCAL_PLAT/bin               chezmoi, uv, claude
~/.local/bin                  arch-neutral scripts only
/opt/homebrew/bin             Homebrew (macOS)
/usr/bin                      system
```

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
6.   runtimes         DF_DO_NODE, DF_DO_RUST, DF_DO_PYTHON, DF_DO_CLAUDE, DF_DO_CODEX, DF_DO_CMAKE
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
3. `packages/pip.txt` — Python packages (installed into `$LOCAL_PLAT/venv` via uv)
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

## Gotchas

These are non-obvious things that have caused real bugs:

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
  overwriting patches.

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
