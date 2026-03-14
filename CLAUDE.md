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
   runs directly on the host (no root, no container). Docker/Podman is not required.

2. **PLAT isolation.** Every compiled binary lives under `~/.local/$PLAT/` where
   `PLAT` is detected from `install/plat/` check scripts (e.g. `plat_Linux_x86-64-v4`,
   `plat_Linux_x86-64-v3`, `plat_Darwin_arm64`). Detection picks the highest CPU level
   the machine supports. Two machines sharing a home directory install into separate PLAT
   subdirs — an AVX-512 machine and an AVX2-only machine each get their own binaries.
   Text configs (chezmoi-managed dotfiles) are shared freely.

3. **Idempotent.** Every script is safe to re-run. Check before installing; skip if already done.

4. **glibc portability.** Homebrew bundles its own glibc 2.35 — binaries are self-contained
   and independent of the host system glibc. Most packages pour as precompiled bottles;
   glibc itself builds from source (~2 min) using the native CPU march on first install.

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
│   ├── .chezmoiignore         # Skip platform-specific files (e.g. aerospace on Linux)
│   ├── dot_zshrc.tmpl         # ZSH interactive config (chezmoi template)
│   ├── dot_zprofile.tmpl      # ZSH login shell: PATH, env vars, tool activation
│   ├── dot_bashrc.tmpl        # Bash interactive config (aliases, prompt, completions)
│   ├── dot_bash_profile.tmpl  # Bash login shell: mirrors .zprofile for bash users
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
│   ├── npm.txt                # Global npm packages (read by install/node.sh)
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
│   ├── brew-shell.sh          # Debug helper: interactive Homebrew shell in manylinux container (optional)
│   ├── chezmoi.sh             # Install chezmoi binary → $ARCH_BIN
│   ├── homebrew.sh            # macOS: install Homebrew + brew bundle
│   ├── linux-packages.sh      # Linux: install Homebrew + glibc + brew bundle (no container, no sudo)
│   ├── patch-homebrew-python.sh # Linux: patch python@3.14 formula (uuid, test_datetime fixes)
│   ├── zsh.sh                 # oh-my-zsh + plugins (pure, autosuggestions, fsh, completions)
│   ├── services.sh            # macOS: colima login service + iTerm2 prefs
│   ├── node.sh                # nvm + Node.js → $LOCAL_PLAT/nvm/
│   ├── rust.sh                # rustup + cargo-binstall + cargo tools from cargo.txt
│   ├── python.sh              # uv + venv + pip installs from packages/pip.txt
│   ├── claude.sh              # Claude Code: native binary + plugins (all platforms)
│   ├── codex.sh               # Codex CLI: native binary from GitHub releases
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

### Helper functions

| Function | Purpose |
|---|---|
| `has cmd` | Check if a command exists on PATH |
| `log_ok msg` | Print green `[ ok ]` status line |
| `log_info msg` | Print blue `[info]` status line |
| `log_warn msg` | Print yellow `[warn]` status line |
| `log_error msg` | Print red `[err ]` to stderr |
| `log_section msg` | Print bold `=== section ===` header |
| `die msg` | Print error and exit 1 |
| `run_logged cmd...` | Run command with output indented 4 spaces |
| `ensure_dir path` | `mkdir -p` if directory doesn't exist |
| `download url dest` | Download via curl or wget |
| `_re_derive_plat_vars` | Re-derive all PLAT variables from current `LOCAL_PLAT` (call after `LOCAL_PLAT` changes) |
| `_read_package_list file` | Read a package list file, skip blanks/comments, output one package name per line |

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
export CFLAGS="${CFLAGS:--march=x86-64-v3 -O2}"
export CXXFLAGS="${CXXFLAGS:--march=x86-64-v3 -O2}"
export RUSTFLAGS="${RUSTFLAGS:--C target-cpu=x86-64-v3}"
export HOMEBREW_OPTFLAGS="${HOMEBREW_OPTFLAGS:--march=x86-64-v3 -O2}"
export CMAKE_C_FLAGS="${CMAKE_C_FLAGS:--march=x86-64-v3 -O2}"
export CMAKE_CXX_FLAGS="${CMAKE_CXX_FLAGS:--march=x86-64-v3 -O2}"
```

`HOMEBREW_OPTFLAGS` is sourced from `.plat_env.sh` but is **not** passed into Homebrew
in the default (no-container) mode — Homebrew's native march detection runs on the host
CPU, which is exactly what we want (v3 machine → `-march=znver2`, v4 → `-march=native` for
that host). Only glibc builds from source; all user tools pour as precompiled bottles.

`brew-shell.sh` (debug tool) still supports container mode for cross-arch testing.
If you need to build on a high-end machine for older hardware, `brew-shell.sh` accepts
`HOMEBREW_OPTFLAGS_PLAT` to override native detection; it translates `x86-64-v{n}` →
`x86-64` for bootstrap gcc (GCC 9, which predates that syntax).

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

## Shell profiles (zsh and bash)

**Login profiles:** Both `.zprofile` (zsh) and `.bash_profile` (bash) are maintained as
identical templates that provide the same functionality:

- PLAT detection from `install/plat/` check scripts (picks the highest CPU level the machine supports)
- Symlink resolution for `~/.local` → ensures all PLAT paths use consistent physical paths
- Homebrew shellenv sourcing
- PATH setup (PLAT paths prepended before Homebrew)
- Tool-specific env vars (Rust, Node, Python, Nix)
- Platform-specific config (CUDA on Linux, Colima on macOS)

**Interactive configs:** `.zshrc` uses oh-my-zsh with plugins (pure prompt, autosuggestions,
fast-syntax-highlighting, completions, nvm lazy loading). `.bashrc` is minimal: basic prompt
with git branch, shared aliases (same as `.zshrc`), zoxide, and fzf completions.

**PATH deduplication:** On shared NFS homes with scratch space, `~/.local` is a symlink to
`/scratch/$USER/.paths/.local`. Without resolution, some tools (Homebrew, Python venv)
resolve the symlink and add the physical path to PATH, while others (cargo, nvm) use
the literal `~/.local/$PLAT` path. This creates duplicate PATH entries for the same PLAT.
Both shell profiles resolve the symlink using `readlink -f` before setting `_LOCAL_PLAT`,
ensuring all tools add the same physical path.

## nvm lazy loading

nvm.sh is ~6000 lines of bash. Sourcing it at login adds ~400ms to shell startup.
Instead, we use a two-layer approach:

1. **`.zprofile`/`.bash_profile`** — adds the latest installed node binary dir to PATH directly
   (`ls $NVM_DIR/versions/node/ | sort -V | tail -1`). This makes `node`/`npm`
   available in non-interactive shells (scripts, CI) with zero nvm overhead.

2. **`.zshrc`** (zsh only) — enables the oh-my-zsh `nvm` plugin with `lazy yes`. This creates
   stub functions for `nvm`/`node`/`npm`/`npx` that source the real `nvm.sh` on
   first use. In interactive zsh shells, the stub overrides the PATH-based node, so
   `nvm use` works correctly.

Bash interactive shells get node via the PATH entry from step 1 — no nvm lazy loading,
but `nvm use` is not available without manually sourcing `$NVM_DIR/nvm.sh`.

Result: **~0.14s** zsh shell startup (down from ~1.1s with eager nvm loading).

---

## bootstrap.sh flow

```
source _lib.sh   → detect PLAT from install/plat/ check scripts, set all path vars
1.  scratch      → create ~/scratch → DOTFILES_SCRATCH_PATH; symlink ~/.local, ~/.cache
                   re-resolve LOCAL_PLAT now that ~/.local may point to scratch
2.  repo         → clone dotfiles if not present; create ~/dotfiles symlink
                   re-detect PLAT from real repo's install/plat/; source .plat_env.sh
3.  chezmoi      → install binary to $ARCH_BIN; chezmoi apply (prompts name/email once)
4.  path check   → verify PLAT paths are writable and not stale symlinks
5.  ZSH          → oh-my-zsh + plugins via install/zsh.sh
6.  packages     → macOS: homebrew.sh | Linux: linux-packages.sh (glibc + brew bundle)
7.  services     → macOS: colima autostart + iTerm2 prefs (install/services.sh)
8.  runtimes     → node.sh, rust.sh, python.sh, claude.sh
```

Each step after scratch has an `INSTALL_*=0` env var to skip it. The Linux packages
step installs Homebrew's own glibc first, then runs `brew bundle` — no container, no
Docker required. Most packages pour as precompiled bottles; glibc builds from source
on first install (~2 min).

Pre-seed name/email to avoid interactive prompts:
```sh
CHEZMOI_NAME="Your Name" CHEZMOI_EMAIL="you@example.com" ~/dotfiles/bootstrap.sh
```

---

## Linux Homebrew — how it works

`linux-packages.sh` installs Homebrew natively on the host (no Docker, no container,
no sudo). Key design decisions:

**1. Custom prefix:** Homebrew installs to `~/.local/$PLAT/brew/` instead of the standard
`/home/linuxbrew/.linuxbrew`. This enables per-CPU-level isolation on shared NFS homes.

**2. glibc first:** The script runs `brew install glibc` explicitly before `brew bundle`.
Why? Homebrew's bottles are built for `/home/linuxbrew/.linuxbrew` with system glibc ≥ 2.35.
On a custom prefix:
- **Packages with relocatable binaries** (jq, ripgrep, etc.) pour as bottles — patchelf
  rewrites the RPATH and they work fine.
- **Packages that embed the prefix deeply** (Python, Perl, OpenSSL, ncurses, git, vim)
  can't be relocated and build from source. These use Homebrew's bundled glibc (~2 min
  one-time build) as their loader and libc, making them fully self-contained.

Installing glibc first ensures that even on systems where the host glibc is already ≥ 2.35,
binaries still use Homebrew's loader (`brew/lib/ld.so` → `opt/glibc/bin/ld.so`) instead
of silently depending on the host system glibc.

**3. Compiler symlinks:** `gcc` and `llvm` are keg-only (Homebrew policy: don't shadow
system compilers). The script creates unversioned symlinks in `$LOCAL_PLAT/bin/`:
- `gcc-15` → `gcc`
- `g++-15` → `g++`
- `llvm@21/bin/clang` → `clang`
- `llvm@21/bin/clang++` → `clang++`

This gives clean `gcc`/`clang` commands that resolve to Homebrew's versions. Re-run
`linux-packages.sh` after a compiler upgrade to refresh symlinks.

**4. Build parallelism:** Homebrew auto-detects `nproc` and sets `HOMEBREW_MAKE_JOBS`
accordingly (e.g. `make -j112` on 112-core machines). Source builds (glibc, Python,
Perl, git, vim) use all available cores.

### Python@3.14 build issues on Linux

Python 3.14 from Homebrew fails to build on some Linux systems due to:

1. **UUID module detection failure** - configure detects libuuid but build fails
   - **Fix:** Set `py_cv_module__uuid=n/a` to disable the module entirely

2. **test_datetime hangs during PGO** - Profile-guided optimization runs the test suite,
   but `test_datetime` hangs on AVX-512 CPUs (possibly timezone/locale related)
   - **Fix:** Patch Makefile's `PROFILE_TASK` to add `-x test_datetime`

**Patches are applied automatically** by `install/patch-homebrew-python.sh` during bootstrap.

**Manual re-application** (if Homebrew updates overwrite patches):
```bash
bash ~/dotfiles/install/patch-homebrew-python.sh
brew reinstall --build-from-source python@3.14
```

**Environment variables** to prevent formula updates:
- `HOMEBREW_NO_AUTO_UPDATE=1` - set in `.zprofile`, prevents tap updates
- `HOMEBREW_NO_INSTALL_FROM_API=1` - forces local formula usage

---

## Scratch space (NFS homes)

On Linux machines with shared NFS home directories and small quotas,
`~/.local/$PLAT` (2-5 GB), `~/.cache`, and oh-my-zsh can exhaust the quota.

**Setup:** Create `~/scratch` as a symlink to large local storage (e.g. `/scratch/$USER`),
or set `DOTFILES_SCRATCH_PATH=/path/to/storage`. Then run bootstrap — `install/scratch.sh`
(step 1, before any tool installs) will symlink these directories to scratch:

| Home path | Scratch target | Why |
|---|---|---|
| `~/.local` | `$SCRATCH/.paths/.local` | All PLAT binaries (2-5 GB per PLAT) |
| `~/.cache` | `$SCRATCH/.paths/.cache` | Homebrew downloads, uv cache, build artifacts |
| `~/.vscode` | `$SCRATCH/.paths/.vscode` | VSCode extensions and state |
| `~/.vscode-server` | `$SCRATCH/.paths/.vscode-server` | Remote SSH server binaries |
| `~/.cursor` | `$SCRATCH/.paths/.cursor` | Cursor extensions and state |
| `~/.cursor-server` | `$SCRATCH/.paths/.cursor-server` | Cursor Remote SSH binaries |

Override with `DOTFILES_LINKS_PATHS` (colon-separated). `~/.config` is intentionally excluded — chezmoi manages files inside it as a real directory and will replace a symlink.

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
   `cargo-binstall` downloads pre-built binaries from GitHub releases (fast).
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
`INSTALL_NIX=0 INSTALL_PACKAGES=0` (Nix and package installs are skipped
in the test environment to keep tests fast and hermetic).

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

- **Don't manually edit chezmoi-managed shell configs** — `.zshrc`, `.zprofile`,
  `.bashrc`, and `.bash_profile` are managed by chezmoi templates. Use `chezmoi edit` instead.
  Tools like `uv` may try to auto-add source lines to these files; if they do,
  run `chezmoi apply --force` to restore the clean template.

- **Don't put compiled binaries in `~/.local/bin/`** — that dir is for
  arch-neutral shell scripts only. Compiled tools go under `$LOCAL_PLAT/`.

- **Don't use `~/.nvm`, `~/.rustup`, `~/.cargo` paths** — all legacy paths.
  Everything is under `$LOCAL_PLAT/`.

- **Don't install the same tool via both Homebrew and cargo/npm.** PLAT paths
  win on PATH, but duplicates waste install time. If it's in `cargo.txt`,
  remove it from `Brewfile`.

- **Don't modify `.zshrc`, `.zprofile`, `.bashrc`, or `.bash_profile` directly** —
  chezmoi manages them. Run `chezmoi edit ~/.zshrc` or edit `home/dot_zshrc.tmpl`.

- **Don't run install scripts without sourcing `_lib.sh`** — the PLAT paths
  won't be set and tools will land in wrong locations.

- **Homebrew on Linux installs glibc first** — `linux-packages.sh` explicitly
  runs `brew install glibc` before `brew bundle` so all bottles link against
  Homebrew's own glibc (self-contained, not the host system glibc). Even on
  systems where the host glibc is already ≥ 2.35, forcing glibc install ensures
  binaries use `brew/lib/ld.so` → `opt/glibc/bin/ld.so` instead of the system
  loader, making installs portable across different Linux distributions.

- **Compilers are keg-only** — `gcc` and `llvm` formulas don't create unversioned
  `gcc`/`clang` symlinks in `brew/bin` (Homebrew policy to avoid shadowing system
  compilers). `linux-packages.sh` creates symlinks in `$LOCAL_PLAT/bin/` pointing
  to the latest installed versions (e.g. `gcc-15` → `gcc`, `llvm@21/bin/clang` →
  `clang`). Re-run `linux-packages.sh` after a compiler upgrade to refresh symlinks.

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

- **Python@3.14 patches on Linux** — `install/patch-homebrew-python.sh` patches
  the Homebrew formula to fix uuid module detection and test_datetime PGO hangs.
  `HOMEBREW_NO_AUTO_UPDATE=1` and `HOMEBREW_NO_INSTALL_FROM_API=1` (set in both
  shell profiles) prevent Homebrew from overwriting these patches.

- **`dot_iterm2/` is a binary plist, not a template.** Do not add `.tmpl`
  extension. If you need to update it, copy the new `com.googlecode.iterm2.plist`
  from `~/.iterm2/` into `home/dot_iterm2/` and run `chezmoi apply`.
