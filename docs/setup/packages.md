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
@scope/package-name
```

Re-run: `bash ~/dotfiles/install/node.sh`

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

Look at an existing `install/` script for patterns and follow them. Add an `INSTALL_*` flag to `bootstrap.sh`.

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

The same `Brewfile` works on macOS and Linux. `if OS.mac?` blocks are silently skipped on Linux.

---

## Updating all packages

```sh
~/dotfiles/bootstrap.sh
```

Re-running bootstrap is the canonical way to upgrade. Every script is idempotent — it upgrades what's installed, installs what's missing, and skips what's already current. Works the same on macOS and Linux.
