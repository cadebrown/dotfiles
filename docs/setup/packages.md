# Package management

Every package layer has a declarative text file and an idempotent install script. All scripts skip already-installed items — safe to re-run at any time.

## The layers

| Layer | File | Install script | Platform |
|---|---|---|---|
| System packages | `packages/Brewfile` | `install/homebrew.sh` / `install/linux-packages.sh` | macOS (bottles) / Linux (native, no container) |
| Rust tools | `packages/cargo.txt` | `install/rust.sh` | All |
| Python packages | `packages/pip.txt` | `install/python.sh` | All |
| Global npm | `packages/npm.txt` | `install/node.sh` | All |
| Claude plugins | `packages/claude-plugins.txt` | `install/claude.sh` | All |
| Claude MCP servers | `packages/claude-mcp.txt` | `install/claude.sh` | All |

---

## Adding a package — priority order

Choose the first layer that applies. Native installers first, Homebrew as fallback:

### 1. cargo — Rust crates

```sh
# Add to packages/cargo.txt
fd-find
ripgrep
bat
my-new-tool
```

Re-run: `bash ~/dotfiles/install/rust.sh`

`install/rust.sh` uses [cargo-binstall](https://github.com/cargo-bins/cargo-binstall): it tries to
download a pre-built binary from GitHub releases first (fast, no compilation), and falls back to
`cargo install` (source compilation) if no binary is available.

On Linux, cargo-binstall avoids the manylinux container round-trip entirely. On macOS, it downloads
the same pre-built binary that Homebrew bottles provide — same quality, faster install.

> **macOS note:** Source compilation requires running from a normal terminal. The macOS Sequoia
> linker enforces `com.apple.provenance` on object files and will block compilation in sandboxed
> contexts (e.g., certain CI environments). This isn't an issue for day-to-day use.

### 2. npm — npm-specific tools

```sh
# packages/npm.txt
@cometix/ccline
```

Re-run: `bash ~/dotfiles/install/node.sh`

Currently ships [`@cometix/ccline`](https://github.com/Haleclipse/CCometixLine) — a Rust-based status line for Claude Code with themes and TUI config (`ccline --config`).

### 3. pip — Python packages

```sh
# packages/pip.txt
requests
black
numpy
```

Re-run: `bash ~/dotfiles/install/python.sh`

Installs into `$LOCAL_PLAT/venv` via `uv`. The venv is activated in `.zprofile`.

### 4. Homebrew — non-language-specific tools and C libraries

```ruby
# packages/Brewfile
brew "tool-name"

# macOS-only (casks, GUI apps, macOS-specific services)
if OS.mac?
  cask "some-app"
  brew "macos-only-tool"
end
```

Re-run: `brew bundle --file=~/dotfiles/packages/Brewfile`

`if OS.mac?` blocks are silently skipped on Linux. Everything outside those blocks runs on both platforms.

Prefer Homebrew for tools that aren't available via cargo/npm/pip, have complex C dependencies, or are
macOS-specific (casks, GUI apps).

### 5. Custom install script

Look at an existing `install/` script for patterns and follow them. Add a `DF_DO_*` flag to `bootstrap.sh`.

---

## Don't duplicate across layers

**Do not install the same tool in both cargo.txt and Brewfile.** PLAT paths (`~/.local/$PLAT/`) come first on PATH — the Homebrew copy would install but never be used. If a tool is in `cargo.txt`, it must not be in `Brewfile`, and vice versa.

---

## Why cargo over Homebrew for Rust tools

Tools like `fd`, `sd`, `bat`, `ripgrep`, `git-delta`, `difftastic`, `procs`, `bottom`,
`ast-grep`, `zoxide`, and `hyperfine` live in `cargo.txt` because:

- `$CARGO_HOME/bin/` is already under `$LOCAL_PLAT/` — PLAT isolation is free
- `cargo-binstall` downloads pre-built GitHub release binaries — fast, no compilation

Tools that have no pre-built binary and are painful to compile (or only make sense on macOS) go in
`Brewfile` under `if OS.mac?`.

---

## Why Homebrew for Linux

Homebrew on Linux installs natively on the host (no container, no sudo). It bundles its own
glibc 2.35, making binaries fully self-contained regardless of the host's glibc version.

**Custom prefix tradeoff:** Installing to `~/.local/$PLAT/brew/` instead of the standard
`/home/linuxbrew/.linuxbrew` enables per-CPU isolation on shared NFS homes, but bottles
built for the standard prefix can't always be relocated:

- **Relocatable packages** (jq, CLI tools with simple dependencies) pour as bottles — patchelf
  rewrites RPATH and they work fine
- **Deep path embedding** (Python, Perl, git, vim, ffmpeg, imagemagick) build from source
  on first install. Homebrew uses all available CPU cores (auto-detects `nproc`), so builds
  are fast on modern hardware.

Once built, packages are cached. Subsequent runs and upgrades are bottle-only.

**Compilers:** `gcc` and `llvm` are keg-only (Homebrew doesn't create unversioned `gcc`/`clang`
symlinks to avoid shadowing system compilers). `linux-packages.sh` creates symlinks in
`$LOCAL_PLAT/bin/` so `gcc` → `gcc-15` and `clang` → `llvm@21/bin/clang`.

See [Compiler toolchains](#compiler-toolchains) below for CMake integration.

**Python@3.14 patches:** On Linux, `install/patch-homebrew-python.sh` automatically patches
the python@3.14 formula to fix build issues (uuid module detection, test_datetime PGO hangs).
Patches are applied during bootstrap and protected by `HOMEBREW_NO_AUTO_UPDATE=1`.

The same `Brewfile` works on macOS and Linux. `if OS.mac?` blocks are silently skipped on Linux.

---

---

## Compiler toolchains

CMake compiler selection is handled by toolchain files deployed per-PLAT, not by raw
`CC`/`CXX` env vars. `install/cmake.sh` copies them from `install/cmake/toolchains/`
to `$LOCAL_PLAT/cmake/toolchains/` on every bootstrap run (always overwrites, so they
stay in sync with the repo).

### Default: LLVM (Homebrew clang)

When Homebrew LLVM is present, `~/.profile` automatically sets:

```sh
export CMAKE_TOOLCHAIN_FILE="$_LOCAL_PLAT/cmake/toolchains/llvm.cmake"
```

The toolchain configures:

| CMake variable | Value |
|---|---|
| `CMAKE_C_COMPILER` | `$LOCAL_PLAT/brew/opt/llvm/bin/clang` |
| `CMAKE_CXX_COMPILER` | `$LOCAL_PLAT/brew/opt/llvm/bin/clang++` |
| `CMAKE_AR` / `RANLIB` / `NM` | `llvm-ar`, `llvm-ranlib`, `llvm-nm` |
| `CMAKE_LINKER_TYPE` | `LLD` (Linux only; macOS requires Apple ld) |
| `CMAKE_CUDA_HOST_COMPILER` | `clang++` |

### Switching to GCC 15

Per-invocation:

```sh
CMAKE_TOOLCHAIN_FILE="$_LOCAL_PLAT/cmake/toolchains/gcc.cmake" cmake -B build
```

Per-session:

```sh
export CMAKE_TOOLCHAIN_FILE="$_LOCAL_PLAT/cmake/toolchains/gcc.cmake"
```

Per-project (`CMakePresets.json`):

```json
{ "cacheVariables": { "CMAKE_TOOLCHAIN_FILE": "/absolute/path/to/gcc.cmake" } }
```

The GCC toolchain uses versioned binaries (`gcc-15`, `g++-15`, etc.) because Homebrew
does not create unversioned `gcc` symlinks on macOS. Linker priority: mold → lld → gold → system ld.

### Disabling the toolchain

```sh
unset CMAKE_TOOLCHAIN_FILE   # let CMake auto-detect compilers
```

### CUDA

CUDA is not managed by bootstrap — install the toolkit separately (system package, NVIDIA
runfile, or a module system on HPC). Then point the per-PLAT symlink at it:

```sh
ln -sfn /usr/local/cuda "$_LOCAL_PLAT/.cuda"        # system default
ln -sfn /opt/nvidia/cuda/12.6 "$_LOCAL_PLAT/.cuda"  # versioned install
```

`~/.profile` resolves the symlink at login and exports:

- `CUDA_PATH` and `CUDAToolkit_ROOT` — picked up by CMake's `find_package(CUDAToolkit)`
  and most other build systems
- Prepends `$CUDA_PATH/bin` to `PATH` so `nvcc` is on the path

Both toolchain files also set `CMAKE_CUDA_COMPILER` to `$LOCAL_PLAT/.cuda/bin/nvcc` when the
symlink exists, so `enable_language(CUDA)` works without any project-level configuration.

Different machines on a shared NFS home can point their `$LOCAL_PLAT/.cuda` symlinks at
different toolkit versions — no conflicts.

### Source files

Toolchain source files live in `install/cmake/toolchains/` — edit them there, not in the
deployed copies under `$LOCAL_PLAT/`. Re-deploy with:

```sh
bash ~/dotfiles/install/cmake.sh
```

Then wipe the CMake cache (`rm -rf build/CMakeCache.txt build/CMakeFiles`) for the changes
to take effect in an existing build directory.

---

## Updating all packages

```sh
~/dotfiles/bootstrap.sh update    # pull + refresh (install missing, skip current)
~/dotfiles/bootstrap.sh upgrade   # update + brew upgrade + cargo upgrade
```

`update` refreshes tools without upgrading existing versions. `upgrade` additionally enables Homebrew upgrades and forces cargo-binstall to re-check for newer binaries. Both are idempotent — safe to run at any time.
