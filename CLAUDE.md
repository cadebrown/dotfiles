# CLAUDE.md — dotfiles repo

Personal dotfiles for macOS and Linux. Managed with [chezmoi](https://chezmoi.io),
bootstrapped with a single `curl | bash`, and designed for shared NFS home directories
across different CPU architectures without requiring sudo on Linux.

---

## Core invariants

These must never be broken:

1. **No sudo on Linux.** Every install script runs as the current user. Homebrew on Linux
   runs inside a rootless container (Docker or Podman).

2. **PLAT isolation.** Every compiled binary lives under `~/.local/$PLAT/` where
   `PLAT = $(uname -m)-$(uname -s)` (e.g. `aarch64-Linux`, `x86_64-Linux`, `arm64-Darwin`).
   Two machines sharing a home directory compile and install independently into separate PLAT
   subdirs. Text configs (chezmoi-managed dotfiles) are shared freely.

3. **Idempotent.** Every script is safe to re-run. Check before installing; skip if already done.

4. **glibc portability.** Linux packages install inside a `manylinux_2_28` container
   (AlmaLinux 8, glibc 2.28). Most packages pour as precompiled bottles; Homebrew
   bundles its own glibc 2.35 so binaries are self-contained.

5. **Same Brewfile everywhere.** `packages/Brewfile` is the single source of truth for packages
   on both macOS and Linux. `if OS.mac?` blocks handle casks and macOS-specific tools.
   Homebrew skips those blocks on Linux automatically.

---

## Repo structure

```
dotfiles/
├── bootstrap.sh               # Entry point — run this on any new machine
├── CLAUDE.md                  # This file
├── README.md
│
├── home/                      # Dotfiles managed by chezmoi → applied to ~/
│   ├── dot_zshrc.tmpl         # ZSH config (chezmoi template)
│   ├── dot_zprofile.tmpl      # Login shell: PATH, env vars, tool activation
│   ├── dot_gitconfig.tmpl     # Git config (name/email from chezmoi data)
│   ├── dot_ssh/config.tmpl    # SSH config
│   ├── dot_claude/CLAUDE.md   # Global Claude Code instructions → ~/.claude/CLAUDE.md
│   ├── dot_codex/             # OpenAI Codex CLI config → ~/.codex/
│   │   ├── AGENTS.md          # Global Codex instructions (mirrors dot_claude/CLAUDE.md)
│   │   ├── create_config.toml # Base settings (create_ prefix: written once, never overwritten)
│   │   └── rules/default.rules # Auto-allowed shell commands
│   └── dot_config/            # App configs: nvim, ghostty, git, linearmouse, etc.
│
├── packages/
│   ├── Brewfile               # Homebrew packages — macOS (bottles) + Linux (compiled)
│   ├── cargo.txt              # `cargo install` list (read by install/rust.sh)
│   ├── pip.txt                # Python packages for ~/.venv (read by install/python.sh)
│   ├── claude-plugins.txt     # Claude Code plugins (read by install/claude.sh)
│   ├── claude-mcp.txt         # Claude Code MCP servers (read by install/claude.sh)
│   └── nix/                   # Nix home-manager config (optional, for Nix users)
│       ├── flake.nix
│       └── home.nix
│
├── install/
│   ├── _lib.sh                # SOURCE OF TRUTH for all PLAT paths and env vars
│   ├── chezmoi.sh             # Install chezmoi binary → $ARCH_BIN
│   ├── homebrew.sh            # macOS: install Homebrew + brew bundle
│   ├── linux-packages.sh      # Linux: brew bundle inside manylinux_2_28 container
│   ├── zsh.sh                 # oh-my-zsh + plugins (pure, autosuggestions, fsh, completions)
│   ├── services.sh            # macOS: register colima as login service
│   ├── node.sh                # nvm + Node.js → $LOCAL_PLAT/nvm/
│   ├── rust.sh                # rustup + cargo installs from packages/cargo.txt
│   ├── python.sh              # uv + venv + pip installs from packages/pip.txt
│   ├── npm.sh                 # Global npm packages from packages/npm.txt
│   ├── claude.sh              # Claude Code: Linux native binary + plugins (macOS: Homebrew cask)
│   └── nix.sh                 # Optional: Nix + home-manager (NOT called by bootstrap.sh — run manually)
│
├── docs/                      # mdBook documentation (served at dotfiles.cade.io)
│   ├── book.toml              # mdBook config: theme, repo URL, search
│   ├── SUMMARY.md             # Table of contents / nav structure
│   ├── intro.md
│   └── setup/
│       ├── bootstrap.md       # System requirements + install instructions per platform
│       ├── chezmoi.md
│       └── packages.md
│
├── infra/
│   └── cloudflare/            # OpenTofu config for Cloudflare Pages
│       ├── main.tf            # Pages project + custom domain + DNS record
│       ├── build.sh           # Build script: installs mdbook, runs `mdbook build docs`
│       ├── terraform.tfvars.example
│       └── .terraform.lock.hcl
│
└── tests/
    ├── Dockerfile             # Ubuntu 24.04 + bats-core test image
    ├── run.sh                 # Build image and run test suite
    ├── entrypoint.sh          # Runs inside container: bootstrap + bats
    ├── bootstrap.bats         # Test: dotfiles applied, plugins installed, chezmoi idempotent
    ├── shell.bats             # Test: ~/.zprofile sources cleanly, env vars correct
    └── paths.bats             # Test: compiled tools in correct PLAT dirs
```

---

## install/_lib.sh — the central contract

Every install script sources `_lib.sh` first. It defines all PLAT paths as variables:

| Variable | Value | Purpose |
|---|---|---|
| `PLAT` | `$(uname -m)-$(uname -s)` | Platform identifier |
| `LOCAL_PLAT` | `$HOME/.local/$PLAT` | Root for all compiled tools |
| `ARCH_BIN` | `$LOCAL_PLAT/bin` | chezmoi, uv, uvx |
| `RUSTUP_HOME` | `$LOCAL_PLAT/rustup` | Rust toolchain |
| `CARGO_HOME` | `$LOCAL_PLAT/cargo` | Cargo (bins at `cargo/bin/`) |
| `NVM_DIR` | `$LOCAL_PLAT/nvm` | nvm + Node.js versions |
| `VENV` | `$LOCAL_PLAT/venv` | Python virtualenv |
| `NIX_PROFILE` | `$LOCAL_PLAT/nix-profile` | Nix profile (if used) |
| `UV_TOOL_BIN_DIR` | `$LOCAL_PLAT/bin` | uv tool binaries |
| `UV_TOOL_DIR` | `$LOCAL_PLAT/uv/tools` | uv tool metadata |
| `UV_PYTHON_INSTALL_DIR` | `$LOCAL_PLAT/uv/python` | uv managed Pythons |
| `OS` | `darwin` or `linux` | Normalised OS |
| `ARCH` | `aarch64` or `x86_64` | Normalised arch (arm64 → aarch64) |

`_lib.sh` also sets `GIT_CONFIG_GLOBAL=/dev/null` to prevent `url.insteadOf` SSH
rewrites from breaking curl-based installers (oh-my-zsh, nvm, etc.) on machines
without SSH keys configured.

**If you add a new tool with compiled binaries, its install path must be under
`$LOCAL_PLAT/` and the variable must be defined in `_lib.sh`.**

---

## PATH priority

`.zprofile` sources Homebrew first, then prepends PLAT paths on top. The resulting
order ensures PLAT-installed tools always win over Homebrew equivalents:

```
$LOCAL_PLAT/venv/bin          ← Python venv (highest priority)
$LOCAL_PLAT/cargo/bin         ← Rust cargo tools (fd, sd, zoxide, etc.)
$LOCAL_PLAT/nvm/.../bin       ← Node.js via nvm
$LOCAL_PLAT/bin               ← chezmoi, uv, uvx
~/.local/bin                  ← arch-neutral scripts
/opt/homebrew/bin             ← Homebrew (macOS)
/usr/bin                      ← system
```

**Do not install the same tool via both Homebrew and cargo/npm.** If a tool is in
`packages/cargo.txt`, remove it from `packages/Brewfile` (and vice versa). PLAT
paths win on PATH, but duplicates waste install time and disk.

---

## nvm lazy loading

nvm.sh is ~6000 lines of bash. Sourcing it at login adds ~400ms to shell startup.
Instead, we use a two-layer approach:

1. **`.zprofile`** — adds the latest installed node binary dir to PATH directly
   (`ls $NVM_DIR/versions/node/ | sort -V | tail -1`). This makes `node`/`npm`
   available in non-interactive shells (scripts, CI) with zero nvm overhead.

2. **`.zshrc`** — enables the oh-my-zsh `nvm` plugin with `lazy yes`. This creates
   stub functions for `nvm`/`node`/`npm`/`npx` that source the real `nvm.sh` on
   first use. In interactive shells, the stub overrides the PATH-based node, so
   `nvm use` works correctly.

Result: **~0.14s** shell startup (down from ~1.1s with eager nvm loading).

---

## bootstrap.sh flow

```
1. chezmoi      → install binary to $ARCH_BIN, run chezmoi apply
2. dotfiles     → chezmoi apply (prompts name/email on first run)
3. ZSH          → oh-my-zsh + plugins via install/zsh.sh
4. packages     → macOS: homebrew.sh | Linux: linux-packages.sh
5. services     → macOS: colima autostart via brew services
6. runtimes     → node.sh, rust.sh, python.sh, claude.sh
```

Each step has an `INSTALL_*=0` env var to skip it. The Linux packages step
starts a `manylinux_2_28` container and runs `brew bundle` inside it; most
packages pour as precompiled bottles — first bootstrap takes ~10 min.

---

## Common tasks

### Adding a program

Follow this priority order:

1. **npm** — add to `packages/npm.txt` if it's an npm package
2. **cargo** — add to `packages/cargo.txt` if it's a Rust crate
3. **Homebrew** — add `brew "name"` to `packages/Brewfile` if it's in Homebrew
   (works on macOS via bottles, compiles from source on Linux)
4. **Special script** — look at an existing `install/` script for patterns and follow them;
   add an `INSTALL_*` flag to `bootstrap.sh`
5. **Ask** — if none of the above fits, ask before inventing a new mechanism

For macOS-only things (casks, GUI apps, macOS services), wrap in `if OS.mac?`:

```ruby
if OS.mac?
  cask "some-app"
  brew "macos-only-tool"
end
```

### Add a Python package

Add to `packages/pip.txt`. Installed into `$LOCAL_PLAT/venv` via uv.

### Add a Rust tool

Add to `packages/cargo.txt`. Installed via `cargo install` into `$CARGO_HOME`.

### Edit a dotfile

```sh
chezmoi edit ~/.zshrc      # opens in $EDITOR, applies on save
chezmoi edit ~/.zprofile
```

Or edit `home/dot_*.tmpl` directly and run `chezmoi apply`.

### Apply dotfile changes

```sh
chezmoi apply              # apply pending changes
chezmoi diff               # preview what would change
chezmoi update             # git pull + apply
```

### Update AI agent instructions (Claude / Codex)

Edit both files — they mirror each other:

```sh
chezmoi edit ~/.claude/CLAUDE.md    # or edit home/dot_claude/CLAUDE.md
chezmoi edit ~/.codex/AGENTS.md     # or edit home/dot_codex/AGENTS.md
```

### Add a Codex auto-allowed command

Edit `home/dot_codex/rules/default.rules`:

```
prefix_rule(pattern=["my-cmd", "arg"], decision="allow")
```

### Add a new env var or PATH entry

Edit `home/dot_zprofile.tmpl`. For anything arch-specific, use `$_LOCAL_PLAT`:

```sh
export MY_TOOL_HOME="$_LOCAL_PLAT/my-tool"
export PATH="$MY_TOOL_HOME/bin:$PATH"
```

Also add the corresponding variable to `install/_lib.sh` so install scripts
can reference the same path.

### Add a new install script

1. Create `install/my-thing.sh`, source `_lib.sh` at the top
2. Guard with `has my-thing && { log_ok ...; exit 0; }` for idempotency
3. Add a step to `bootstrap.sh` with an `INSTALL_MY_THING` flag
4. Add tests to `tests/paths.bats` or `tests/bootstrap.bats`

### Work on docs

```sh
# Serve locally with live reload (opens browser automatically)
cd docs && mdbook serve --open

# Build static output only
cd docs && mdbook build        # output → docs/book/
```

Docs are hosted at https://dotfiles.cade.io via Cloudflare Pages.
Every push to `main` triggers a rebuild automatically.

### Deploy infrastructure changes

```sh
cd infra/cloudflare
export CLOUDFLARE_API_TOKEN=...
tofu plan    # preview
tofu apply   # create/update Pages project + DNS
```

`terraform.tfvars` (contains account_id) is gitignored — copy from
`terraform.tfvars.example` and fill in on each machine.

### Run tests

```sh
# Full Docker-based test (requires Docker or Podman)
./tests/run.sh

# Just the shell env tests locally
bats tests/shell.bats
```

Tests run in an Ubuntu 24.04 container. Bootstrap runs with
`INSTALL_NIX=0 INSTALL_PACKAGES=0` (Nix and Linux packages need
privileges/container-in-container that aren't available in test).

---

## chezmoi template variables

Available in `home/**/*.tmpl`:

| Variable | Example |
|---|---|
| `{{ .chezmoi.os }}` | `darwin`, `linux` |
| `{{ .chezmoi.arch }}` | `arm64`, `amd64` |
| `{{ .chezmoi.homeDir }}` | `/Users/cade` |
| `{{ .name }}` | from `chezmoi.toml` data |
| `{{ .email }}` | from `chezmoi.toml` data |

The `.chezmoi.toml.tmpl` prompts for `name` and `email` on first init via
`promptStringOnce`. Values are cached in `~/.config/chezmoi/chezmoi.toml`.

---

## Pitfalls

- **Don't put compiled binaries in `~/.local/bin/`** — that dir is for
  arch-neutral shell scripts only. Compiled tools go under `$LOCAL_PLAT/`.

- **Don't use `~/.nvm`, `~/.rustup`, `~/.cargo` paths** — all legacy paths.
  Everything is under `$LOCAL_PLAT/`.

- **Don't install the same tool via both Homebrew and cargo/npm.** PLAT paths
  win on PATH, but duplicates waste install time. If it's in `cargo.txt`,
  remove it from `Brewfile`.

- **Don't modify `.zshrc` or `.zprofile` directly** — chezmoi manages them.
  Run `chezmoi edit ~/.zshrc` or edit `home/dot_zshrc.tmpl`.

- **Don't run install scripts without sourcing `_lib.sh`** — the PLAT paths
  won't be set and tools will land in wrong locations.

- **Homebrew on Linux runs in a container** — `linux-packages.sh` requires
  Docker or Podman available on the host. Without it, the script exits with
  a clear error message pointing to the docs.

- **`sourceDir` in chezmoi.toml must be a top-level TOML key** — it goes
  before the `[data]` section, not inside it. Misplacing it silently breaks
  `chezmoi diff` and `chezmoi update`.

- **`GIT_CONFIG_GLOBAL=/dev/null`** is set by `_lib.sh` for all install scripts.
  This is intentional — it prevents `url.insteadOf` SSH rewrites from breaking
  curl-based installers on machines without SSH keys.
