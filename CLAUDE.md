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
| Overlays | `dotfiles-*/` | Private repos that extend the parent (e.g. `dotfiles-nvidia/`); see `.claude/rules/install-scripts.md` |

## Scoped rules

Area detail lives in `.claude/rules/*.md` and loads automatically when you read
matching files (`paths:` frontmatter). Working on one of these areas without
opening its files first? Read the rule directly:

| Rule | Scope | Contents |
|---|---|---|
| `install-scripts.md` | `install/**`, `bootstrap.sh`, `tests/**` | per-script reference table, logging helpers, overlay mechanics, bootstrap step order |
| `homebrew.md` | Brewfile, homebrew/linux-packages/patch-homebrew scripts | Homebrew-on-Linux build lore: formula patch catalog, glibc/GCC 15 traps, tap trust |
| `chezmoi-home.md` | `home/**` | template rules, shared partials, shell-profile invariants, locale/LC_ALL handling |
| `agent-tooling.md` | claude/codex/skills/memory scripts + package lists | MCP auth patterns, rtk hooks, chezmoi-guard, harness full-auto config, plugin three-places rule |
| `toolchains.md` | `install/cmake/**`, `install/plat/**` | CMake toolchains, CUDA convention, ccache/sccache, `tc` switching |

## PATH priority

Shell profiles prepend tool paths on top of Homebrew. Highest priority first.
`$_LOCAL_PLAT` resolves to either `$HOME/.local/$_PLAT` (when `use_plat=true`)
or `$HOME/.local` (default).

```
$_LOCAL_PLAT/cargo/bin        Rust tools (fd, sd, zoxide, etc.)
$_LOCAL_PLAT/nvm/.../bin      Node.js via nvm
$_LOCAL_PLAT/bin              chezmoi, uv, claude, plus go-installed binaries (GOBIN=here)
~/.local/bin                  arch-neutral scripts only (collapses to $_LOCAL_PLAT/bin in flat mode)
/opt/homebrew/bin             Homebrew (macOS)
/usr/bin                      system
```

**Never install the same tool in two layers** — installed-location paths win,
but duplicates waste time and break `*-self-update` flows that compare argv[0]
against a recorded install dir (uv was the canonical example of this footgun).

## Rules for agents

### Before making changes

- **Read `install/_lib.sh`** — it defines every path variable, logging function, and helper.
  All install scripts source it. Don't guess paths; use the variables it exports.
- **Check for duplicates** across `packages/cargo.txt`, `packages/Brewfile`, and `packages/npm.txt`
  before adding a tool. Never install the same thing in two layers.
- **Read the relevant install script** before modifying it. Understand the idempotency guard.

### Debugging & common issues

- `docs/usage/troubleshooting.md` is the FAQ — symptom → root-cause chain → confirm → fix.
  Check it (and the scoped-rule gotcha lists) before re-deriving a diagnosis.
- When you root-cause a new real-world issue, add an entry there in the same format, and
  add a gotcha bullet to the matching `.claude/rules/` file if it's likely to bite
  future agent work in this repo.

### Adding a tool

Priority order — native installer first, Homebrew as fallback:

1. `packages/cargo.txt` — Rust crates (cargo-binstall downloads pre-built binaries)
2. `packages/npm.txt` — npm packages
3. `packages/pip.txt` — Python packages (installed via `uv tool install`)
   - `# macos-only` — skip on Linux; `# python=X.Y` — pin a Python version
4. `packages/go.txt` — Go CLI tools (`go install`); `# linux-only` / `# macos-only` markers
5. `packages/Brewfile` — everything else (C libraries, GUI apps, tools without native installers);
   macOS-only things go in `if OS.mac?` blocks
6. New `install/*.sh` script — source `_lib.sh`, add `DF_DO_*` flag to `bootstrap.sh`, add tests

### Editing dotfiles

- Edit sources in `home/` (e.g. `home/dot_zshrc.tmpl`), never the deployed files
- Shell profiles (`dot_zprofile.tmpl`, `dot_bash_profile.tmpl`) must stay in sync
- Templates must render identically on every machine (shared NFS homes) — see
  `.claude/rules/chezmoi-home.md`

### Env var naming

All user-facing env vars use the `DF_` prefix: config (`DF_NAME`, `DF_REPO`, …),
flags (`DF_DO_*`, `0` skips / `1` enables), behavior (`DF_USE_PLAT`), debug
(`DF_DEBUG=1`). Internal: `DF_ROOT`, `DF_PACKAGES`, `DF_INSTALL_DIR`.
Tool-standard vars (`PLAT`, `LOCAL_PLAT`, `RUSTUP_HOME`, `CARGO_HOME`, `NVM_DIR`, …)
keep their conventional names.

## Git hooks

A global pre-push hook scans pushed commits for secrets with gitleaks —
`core.hooksPath = ~/.config/git/hooks` applies to **every repo**, not just dotfiles.
If a push is blocked, run `gitleaks git --no-banner` to review; emergency bypass
`git push --no-verify` (only when certain there's no secret). Don't disable the hook.

## Cross-cutting gotchas

Area-specific gotchas live in the scoped rules; only repo-wide traps here:

- **Don't use legacy paths** (`~/.nvm`, `~/.rustup`, `~/.cargo`) — everything is under `$LOCAL_PLAT/`.
- **Don't run install scripts without sourcing `_lib.sh`** — PLAT paths won't be set.

## Reference

- **Bootstrap flow and skip flags:** `bootstrap.sh` header comments, [docs/setup/bootstrap.md](docs/setup/bootstrap.md)
- **Package management:** [docs/setup/packages.md](docs/setup/packages.md)
- **Chezmoi workflow:** [docs/setup/chezmoi.md](docs/setup/chezmoi.md)
- **Troubleshooting / FAQ:** [docs/usage/troubleshooting.md](docs/usage/troubleshooting.md)
- **PLAT specs and compiler flags:** `install/plat/` directories
- **verify-path.sh flags:** `bash install/verify-path.sh --help`
- **Homebrew on Linux internals:** `install/linux-packages.sh` comments
- **Infra/hosting:** [docs/infra/docs-and-hosting.md](docs/infra/docs-and-hosting.md)
