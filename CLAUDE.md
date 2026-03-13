# CLAUDE.md — dotfiles repo

Personal dotfiles for macOS and Linux. Managed with [chezmoi](https://chezmoi.io),
bootstrapped with a single `curl | bash`, and designed for shared NFS home directories
across different CPU architectures without requiring sudo on Linux.

---

## Rules for agents

### Adding a tool to this config

1. Read `install/_lib.sh` first — it defines all path variables.
2. Check `packages/cargo.txt`, `packages/Brewfile`, and `packages/npm.txt`
   for duplicates. Never install the same tool in two layers.
3. Follow the priority in "Adding a program" below. Rust CLI tools go in
   `cargo.txt` (binstall pre-built binaries, no Linux container needed),
   not Brewfile.
4. New install scripts: source `_lib.sh`, use its variables and helpers,
   guard with idempotency checks, add an `INSTALL_*` flag to `bootstrap.sh`,
   add tests to `tests/`.

### Editing dotfiles

Edit chezmoi sources in `home/` (e.g. `home/dot_zshrc.tmpl`), never the
deployed files directly. Binary files like `dot_iterm2/*.plist` are not
templates — no `.tmpl` extension.

### Hard constraints

- No `sudo` in any script (Linux runs without root).
- No compiled binaries in `~/.local/bin/` (arch-neutral scripts only).
- No hardcoded paths — use `$LOCAL_PLAT`, `$CARGO_HOME`, etc. from `_lib.sh`.

---

## Core invariants

These must never be broken:

1. **No sudo on Linux.** Every install script runs as the current user. Homebrew on Linux
   runs inside a rootless container (Docker or Podman).

2. **PLAT isolation.** Every compiled binary lives under `~/.local/$PLAT/` where
   `PLAT` is detected from `install/plat/` check scripts (e.g. `plat_Linux_x86-64-v4`,
   `plat_Linux_x86-64-v3`, `plat_Darwin_arm64`). Detection picks the highest CPU level
   the machine supports. Two machines sharing a home directory install into separate PLAT
   subdirs — an AVX-512 machine and an AVX2-only machine each get their own binaries.
   Text configs (chezmoi-managed dotfiles) are shared freely.

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
│   ├── dot_iterm2/            # iTerm2 preferences → ~/.iterm2/
│   │   └── com.googlecode.iterm2.plist  # Binary plist — not a template
│   └── dot_config/            # App configs: nvim, ghostty, git, linearmouse, etc.
│
├── packages/
│   ├── Brewfile               # Homebrew packages — macOS (bottles) + Linux (compiled)
│   ├── cargo.txt              # Rust tools (read by install/rust.sh via cargo-binstall)
│   ├── pip.txt                # Python packages for $LOCAL_PLAT/venv (read by install/python.sh)
│   ├── claude-plugins.txt     # Claude Code plugins (read by install/claude.sh)
│   ├── claude-mcp.txt         # Claude Code MCP servers (read by install/claude.sh)
│   └── nix/                   # Nix home-manager config (optional, for Nix users)
│       ├── flake.nix
│       └── home.nix
│
├── install/
│   ├── _lib.sh                # SOURCE OF TRUTH for all PLAT paths and env vars
│   ├── plat/                  # Per-PLAT capability check + compile-flag scripts
│   │   ├── plat_Linux_x86-64-v4/
│   │   │   ├── .plat_check.sh # CPU feature check (AVX-512) — exits 0 if supported
│   │   │   └── .plat_env.sh   # Sets CFLAGS, RUSTFLAGS, HOMEBREW_OPTFLAGS, etc.
│   │   ├── plat_Linux_x86-64-v3/  # AVX2/FMA/BMI2 (Haswell+, Zen2+)
│   │   ├── plat_Linux_x86-64-v2/  # SSE4.2/POPCNT baseline
│   │   ├── plat_Linux_aarch64/    # 64-bit ARM Linux
│   │   ├── plat_Darwin_arm64/     # Apple Silicon
│   │   └── plat_Darwin_x86-64/    # Intel Mac
│   ├── migrate-plat.sh        # One-time: rename old x86_64-Linux dir to plat_Linux_* format
│   ├── brew-shell.sh          # Debug helper: interactive Homebrew shell in manylinux container
│   ├── chezmoi.sh             # Install chezmoi binary → $ARCH_BIN
│   ├── homebrew.sh            # macOS: install Homebrew + brew bundle
│   ├── linux-packages.sh      # Linux: brew bundle inside manylinux_2_28 container
│   ├── zsh.sh                 # oh-my-zsh + plugins (pure, autosuggestions, fsh, completions)
│   ├── services.sh            # macOS: colima login service + iTerm2 prefs
│   ├── node.sh                # nvm + Node.js → $LOCAL_PLAT/nvm/
│   ├── rust.sh                # rustup + cargo-binstall + cargo tools from cargo.txt
│   ├── python.sh              # uv + venv + pip installs from packages/pip.txt
│   ├── npm.sh                 # Global npm packages from packages/npm.txt
│   ├── claude.sh              # Claude Code: Linux native binary + plugins (macOS: Homebrew cask)
│   ├── scratch.sh             # Symlink large dirs to scratch space (NFS quota relief)
│   ├── verify-path.sh         # Diagnostic: check PATH binaries for arch/lib/symlink issues
│   └── nix.sh                 # Optional: Nix + home-manager (NOT called by bootstrap.sh)
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
    ├── paths.bats             # Test: compiled tools in correct PLAT dirs
    └── verify.bats            # Test: verify-path.sh diagnostic passes
```

---

## install/_lib.sh — the central contract

Every install script sources `_lib.sh` first. It defines all PLAT paths as variables:

| Variable | Value | Purpose |
|---|---|---|
| `PLAT` | detected from `install/plat/` (e.g. `plat_Linux_x86-64-v4`) | Platform + CPU-level identifier |
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
| `SCRATCH` | `$DOTFILES_SCRATCH_PATH` or resolved `~/scratch` | Scratch space root (empty if none) |
| `PATHS` | `$SCRATCH/.paths` | Symlink targets for ~/.local, ~/.cache, etc. (empty if no scratch) |

`_lib.sh` also sets `GIT_CONFIG_GLOBAL=/dev/null` to prevent `url.insteadOf` SSH
rewrites from breaking curl-based installers (oh-my-zsh, nvm, etc.) on machines
without SSH keys configured.

**If you add a new tool with compiled binaries, its install path must be under
`$LOCAL_PLAT/` and the variable must be defined in `_lib.sh`.**

---

## PLAT specs — install/plat/

Each subdirectory of `install/plat/` defines one platform target.
`_lib.sh` scans them (sorted reverse — highest first), runs `.plat_check.sh`,
and sources `.plat_env.sh` from the first one that exits 0.

### Current specs

| PLAT | OS | CPU requirement | Typical hardware |
|---|---|---|---|
| `plat_Linux_x86-64-v4` | Linux | AVX-512 (avx512f/bw/cd/dq/vl) | Intel Skylake-X/Ice Lake+, AMD Zen 4+ |
| `plat_Linux_x86-64-v3` | Linux | AVX2/FMA/BMI2 | Intel Haswell+ (2013+), AMD Zen 2+ (2019+) |
| `plat_Linux_x86-64-v2` | Linux | SSE4.2/POPCNT | Intel Nehalem+ (2008+), AMD K10+ |
| `plat_Linux_aarch64` | Linux | any AArch64 | Graviton, Ampere, etc. |
| `plat_Darwin_arm64` | macOS | any Apple Silicon | M1/M2/M3/M4+ |
| `plat_Darwin_x86-64` | macOS | any Intel | Intel Mac (all models) |

Detection order (highest to lowest):
```
v4 checked first → v3 → v2 → fallback
```
The fallback (no matching spec) uses the old `uname-m-uname-s` format for
backwards compatibility.

### .plat_check.sh — capability detection

POSIX sh (invoked with `/bin/sh`). Exit 0 if this machine supports this PLAT.

```sh
#!/bin/sh
# plat_Linux_x86-64-v3/.plat_check.sh
[ "$(uname -s)" = "Linux" ] || exit 1
[ "$(uname -m)" = "x86_64" ] || exit 1
for flag in avx avx2 bmi1 bmi2 f16c fma movbe xsave cx16 popcnt sse4_1 sse4_2 ssse3; do
    grep -qw "$flag" /proc/cpuinfo 2>/dev/null || exit 1
done
exit 0
```

macOS doesn't have `/proc/cpuinfo` — just check `uname -s` + `uname -m`.
Linux x86-64 feature flags come from `/proc/cpuinfo` — `grep -qw` does word-boundary matching.

### .plat_env.sh — compile flags

Bash. Sourced after detection to set compile-time flags for that PLAT.
Also sourced by `.zprofile` at login so interactive `cargo build`, `cmake`, etc. use them.

```bash
#!/usr/bin/env bash
# plat_Linux_x86-64-v3/.plat_env.sh
export CFLAGS="-march=x86-64-v3 -O2"
export CXXFLAGS="-march=x86-64-v3 -O2"
export RUSTFLAGS="-C target-cpu=x86-64-v3"
export HOMEBREW_OPTFLAGS="-march=x86-64-v3 -O2"   # controls glibc build in manylinux
export CMAKE_C_FLAGS="-march=x86-64-v3 -O2"
export CMAKE_CXX_FLAGS="-march=x86-64-v3 -O2"
```

### Adding a new PLAT

1. Create `install/plat/plat_{OS}_{name}/`
2. Write `.plat_check.sh` — exit 0 if supported, exit 1 if not
3. Write `.plat_env.sh` — set flags for this target
4. The name determines sort order — use a name that sorts correctly relative to siblings
   (e.g. `plat_Linux_x86-64-v4` sorts after `plat_Linux_x86-64-v3`)
5. Test with: `for d in install/plat/plat_Linux_*/; do /bin/sh "$d/.plat_check.sh" && echo "PASS $(basename $d)" || echo "fail $(basename $d)"; done`

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

## macOS vs Linux — Rust toolchain

`install/rust.sh` handles each platform differently:

**macOS:** Uses Homebrew's `rustup` (`brew "rustup"` is in `Brewfile` under `if OS.mac?`).
Homebrew's build is code-signed, which is required on macOS Sequoia+ where the linker
enforces `com.apple.provenance` on object files. The upstream `sh.rustup.rs` binary is
not code-signed and will fail with "Operation not permitted" when `ld` tries to open
compiled `.o`/`.rlib` files in sandboxed contexts.

**Linux:** Downloads `rustup-init` directly from `sh.rustup.rs`. No Homebrew needed or wanted.

Both platforms install `cargo-binstall` first (via its own pre-built binary installer).
For each tool in `cargo.txt`, binstall tries to download a pre-built binary from GitHub
releases; if none is available, it falls back to `cargo install` (source compilation).

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
source _lib.sh      → detect PLAT from install/plat/ (or fallback), set paths
0.   scratch        → create ~/scratch → DOTFILES_SCRATCH_PATH; symlink ~/.local, ~/.cache
                      re-resolve LOCAL_PLAT after ~/.local is symlinked to scratch
0.5  dotfiles repo  → clone if not present; ~/dotfiles → DOTFILES_PATH
0.3  PLAT detect    → re-detect PLAT from real repo's install/plat/; migrate old dir
                      sources .plat_env.sh for CFLAGS/RUSTFLAGS/HOMEBREW_OPTFLAGS
2.7  path sanity    → check PLAT paths are writable and not stale symlinks
1.   chezmoi        → install binary to $ARCH_BIN, run chezmoi apply
2.   dotfiles       → chezmoi apply (prompts name/email on first run)
3.   ZSH            → oh-my-zsh + plugins via install/zsh.sh
4.   packages       → macOS: homebrew.sh | Linux: linux-packages.sh
5.   services       → macOS: colima autostart + iTerm2 prefs (install/services.sh)
6.   runtimes       → node.sh, rust.sh, python.sh, claude.sh
```

Each step has an `INSTALL_*=0` env var to skip it. The Linux packages step
starts a `manylinux_2_28` container and runs `brew bundle` inside it; most
packages pour as precompiled bottles — first bootstrap takes ~10 min.

Pre-seed name/email to avoid interactive prompts:
```sh
CHEZMOI_NAME="Your Name" CHEZMOI_EMAIL="you@example.com" ~/dotfiles/bootstrap.sh
```

---

## Scratch space (NFS homes)

On Linux machines with shared NFS home directories and small quotas,
`~/.local/$PLAT` (2-5 GB), `~/.cache`, and oh-my-zsh can exhaust the quota.

**Setup:** Create `~/scratch` as a symlink to large local storage (e.g. `/scratch/$USER`),
or set `DOTFILES_SCRATCH_PATH=/path/to/storage`. Then run bootstrap — `install/scratch.sh`
(step 0, before any tool installs) will symlink these directories to scratch:

| Home path | Scratch target |
|---|---|
| `~/.local` | `$SCRATCH/.paths/.local` |
| `~/.cache` | `$SCRATCH/.paths/.cache` |

Override with `DOTFILES_LINKS_PATHS` (colon-separated). `~/.config` is intentionally excluded — chezmoi manages files inside it as a real directory and will replace a symlink. `~/.oh-my-zsh` is excluded too — `install/zsh.sh` installs fresh.

The `$PATHS` variable in `_lib.sh` points to `$SCRATCH/.paths` and is the
single source of truth for where symlink targets live.

No-op when no scratch space is detected — existing setups are unaffected.

**For agents:** The symlinks are transparent. `$LOCAL_PLAT` still resolves to
`~/.local/$PLAT` — tools install there as usual, the OS follows the symlink.
Don't add scratch-specific logic to install scripts; just use the standard
`_lib.sh` variables.

---

## Common tasks

### Adding a program

Follow this priority order — native installers first, Homebrew as fallback:

1. **cargo** — add to `packages/cargo.txt` if it's a Rust crate.
   `cargo-binstall` downloads pre-built binaries (fast, no container needed on Linux).
2. **npm** — add to `packages/npm.txt` if it's an npm package
3. **pip/uv** — add to `packages/pip.txt` if it's a Python package
4. **Homebrew** — add `brew "name"` to `packages/Brewfile` for non-language-specific
   tools, C libraries, and things without native installers
5. **Custom script** — look at an existing `install/` script for patterns and follow them;
   add an `INSTALL_*` flag to `bootstrap.sh`
6. **Ask** — if none of the above fits, ask before inventing a new mechanism

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

Add the crate name to `packages/cargo.txt`. `install/rust.sh` will:
1. Try `cargo binstall` — downloads a pre-built binary from GitHub releases if available
2. Fall back to `cargo install` — compiles from source otherwise

Run `bash ~/dotfiles/install/rust.sh` to apply. On macOS, source compilation requires
running from a normal terminal (the signed Homebrew rustup handles the Sequoia linker
requirements automatically).

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
mdbook serve docs/ --open

# Build static output only
mdbook build docs/        # output → docs/book/
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

### Verify PATH health

```sh
verify-path              # alias — runs all checks
bash ~/dotfiles/install/verify-path.sh --arch        # architecture match only
bash ~/dotfiles/install/verify-path.sh --libs        # shared library check (Linux)
bash ~/dotfiles/install/verify-path.sh --duplicates  # find shadowed binaries
bash ~/dotfiles/install/verify-path.sh --symlinks    # broken symlinks
bash ~/dotfiles/install/verify-path.sh --full        # check entire PATH, not just PLAT dirs
```

Not called by bootstrap — run manually after install or when debugging path issues.

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

- **macOS Sequoia: use Homebrew's rustup, not sh.rustup.rs.** The Homebrew
  `rustup` formula is code-signed. On macOS Sequoia+, the linker enforces
  `com.apple.provenance` on object files and will reject unsigned builds.
  `install/rust.sh` handles this automatically; `brew "rustup"` is in
  `Brewfile` under `if OS.mac?`.

- **`dot_iterm2/` is a binary plist, not a template.** Do not add `.tmpl`
  extension. If you need to update it, copy the new `com.googlecode.iterm2.plist`
  from `~/.iterm2/` into `home/dot_iterm2/` and run `chezmoi apply`.
