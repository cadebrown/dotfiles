# Package management

Every package layer has a declarative text file and an idempotent install script. All scripts skip already-installed items — safe to re-run at any time.

## The layers

| Layer | File | Install script | Platform |
|---|---|---|---|
| System packages | `packages/Brewfile` | `install/homebrew.sh` / `install/linux-packages.sh` | macOS (bottles) / Linux (manylinux container) |
| Rust tools | `packages/cargo.txt` | `install/rust.sh` | All |
| Python packages | `packages/pip.txt` | `install/python.sh` | All |
| Global npm | `packages/npm.txt` | `install/npm.sh` | All |
| Claude plugins | `packages/claude-plugins.txt` | `install/claude.sh` | All |
| Claude MCP servers | `packages/claude-mcp.txt` | `install/claude.sh` | All |

---

## Adding a package — priority order

Choose the first layer that applies:

### 1. cargo — Rust crates

```sh
# packages/cargo.txt
ripgrep
fd-find
```

Re-run: `bash ~/dotfiles/install/rust.sh`

### 2. Homebrew — everything else

```ruby
# packages/Brewfile
brew "tool-name"

# macOS-only (casks, GUI apps, macOS services)
if OS.mac?
  cask "some-app"
end
```

Re-run: `brew bundle --file=~/dotfiles/packages/Brewfile`

### 3. pip — Python packages

```sh
# packages/pip.txt
requests
black
```

Re-run: `bash ~/dotfiles/install/python.sh`

### 4. npm — npm-specific tools

```sh
# packages/npm.txt
@scope/package-name
```

Re-run: `bash ~/dotfiles/install/npm.sh`

### 5. Custom install script

Look at an existing `install/` script for patterns, follow them, and add an `INSTALL_*` flag to `bootstrap.sh`.

---

## Why cargo over Homebrew for some tools

`fd`, `sd`, and `zoxide` are in `cargo.txt` instead of `Brewfile` because:

- `$CARGO_HOME/bin` is already under `$LOCAL_PLAT/` — PLAT isolation is automatic
- Rust crates compile cleanly from source on any platform
- The Homebrew formula for these often just calls `cargo install` anyway

**Do not install the same tool in both places.** PLAT paths win on PATH — the Homebrew copy would install but never be used.

---

## Why Homebrew for Linux

Homebrew on Linux installs inside a `manylinux_2_28` container (AlmaLinux 8, glibc 2.28) so the compiled binaries work on any Linux host since ~2018. Most packages pour as precompiled bottles — no compilation needed. Homebrew bundles its own glibc 2.35, so the binaries are self-contained regardless of the host's glibc version.

The same `Brewfile` works on macOS and Linux. `if OS.mac?` blocks (casks, GUI apps) are silently skipped on Linux.

---

## Updating all packages

```sh
# Homebrew (macOS)
brew bundle --file=~/dotfiles/packages/Brewfile

# Homebrew (Linux) — re-run in container
bash ~/dotfiles/install/linux-packages.sh

# Cargo tools
bash ~/dotfiles/install/rust.sh

# Python venv
bash ~/dotfiles/install/python.sh

# Claude plugins + MCP servers
bash ~/dotfiles/install/claude.sh
```
