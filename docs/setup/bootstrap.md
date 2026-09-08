# Bootstrap a new machine

Bootstrap applies managed files, installs the selected runtimes, then runs
small selected-tool checks. Start from a checkout when you want an interactive
name/email prompt or an auditable revision.

## One-liner

```sh
curl -fsSL https://raw.githubusercontent.com/cadebrown/dotfiles/main/bootstrap.sh | \
  DF_NAME="Your Name" DF_EMAIL="you@example.com" bash
```

Piping consumes stdin, so provide `DF_NAME` and `DF_EMAIL`; chezmoi caches them
in `~/.config/chezmoi/chezmoi.toml` for later runs.

### Interactive (prompts for name + email)

```sh
git clone https://github.com/cadebrown/dotfiles ~/dotfiles
~/dotfiles/bootstrap.sh
```

Expected result: a final selected-tool verification and, if applicable, a
degradation summary to repair. It does not prove cloud credentials, GUI privacy
grants, or running local services.

## Modes

```sh
~/dotfiles/bootstrap.sh          # install
~/dotfiles/bootstrap.sh update   # refresh a clean checkout; skips scratch setup
~/dotfiles/bootstrap.sh upgrade  # update plus managed runtime upgrades
```

`upgrade` enables Homebrew upgrades; it does not update the operating system.
`update` refuses a non-fast-forward pull. See [the lifecycle](/architecture/bootstrap-lifecycle/)
for stage order and recovery behavior.

## macOS

### Requirements

| Requirement | How to satisfy it |
| --- | --- |
| macOS 13+ | Ventura or later |
| Xcode Command Line Tools | `xcode-select --install`, or Homebrew's prompt |
| Internet access | required for package sources |

Homebrew installation uses the system privilege flow.

### What gets installed

| Area | Managed result |
| --- | --- |
| Configuration | chezmoi applies `home/` templates and login profiles |
| Packages | Homebrew packages/casks, uv, nvm, Rust, Go, Lean, TeX, and selected CLIs |
| Agent tooling | Claude, Codex, MCP configuration, skills, optional memory and local-LLM tools |
| Desktop integration | macOS settings, services, Cursor/VS Code, and optional Blender MCP |

Installers call the root `LOCAL_PLAT`; a managed login shell exposes the same
root as `$_LOCAL_PLAT` (`~/.local` by default). Executables land in its `bin/`.
`DF_START_LOCAL_SERVICES=1` opts in to starting Colima, Ollama,
and mlxserve at login; otherwise start a needed service manually. See
[package ownership](/architecture/package-ownership/) and the
[macOS workflow](/workflows/macos-workstation/) for operational checks.

| macOS-specific choice | Effect |
| --- | --- |
| Homebrew Rustup | code-signed toolchain path for current macOS linker rules |
| `DF_PROFILE=core` | keeps Rustup/rust-analyzer but omits optional Cargo tools |
| service default | Colima/Ollama are left manual; mlxserve is stopped/disabled so a hand-start does not survive bootstrap |

## Linux

### Requirements

| Requirement | Notes |
| --- | --- |
| x86_64 or aarch64 | supported host architectures |
| `git`, `curl`, `python3` | normally preinstalled |
| Internet access | required for package sources |

No sudo is required. Homebrew installs under `$_LOCAL_PLAT/brew` in a managed
login shell; Linux setup
does not require Docker or Podman. An enabled NVIDIA overlay may have its own
container requirement.

### What gets installed

The same configuration, language, agent, and optional-workflow layers as macOS,
with rootless Linux Homebrew, TinyTeX, and Linux-specific package handling.
Cursor and VS Code default off on Linux; set their gates only where the CLI is
available. Inspect the exact owner in [package setup](/setup/packages/).

| Linux-specific choice | Effect |
| --- | --- |
| Homebrew | rootless native prefix; no container runtime required |
| TeX | TinyTeX under the runtime root; missing packages install through `tlmgr` |
| editors | Cursor/VS Code default off; selecting a missing CLI or extension fails bootstrap |

## Skipping steps

Pass `DF_DO_<AREA>=0` for an optional stage; `DF_DO_AUTH=1` opts into the token
walk. A skipped stage is not an uninstall, and final verification skips the
same selected check.

| Gate | Default | Stage |
| --- | --- | --- |
| `DF_DO_SCRATCH`, `DF_DO_DIRS` | install: on; update/upgrade scratch: off | scratch links; home directories |
| `DF_DO_PACKAGES`, `DF_DO_LLDB`, `DF_DO_QUARTO` | on | Homebrew/package bundle; debugger; Quarto |
| `DF_DO_ZSH`, `DF_DO_NODE`, `DF_DO_RUST`, `DF_DO_PYTHON`, `DF_DO_GO` | on | shell plugins and language runtimes |
| `DF_DO_JULIA`, `DF_DO_LEAN`, `DF_DO_LATEX` | on | Julia, Lean, TeX |
| `DF_DO_CLAUDE`, `DF_DO_CODEX`, `DF_DO_OPENCODE` | on | coding-agent CLIs/configuration |
| `DF_DO_CLAUDE_DESKTOP`, `DF_DO_CODEX_DESKTOP`, `DF_DO_LINEARMOUSE` | on, macOS | tracked desktop preferences |
| `DF_DO_MACOS_SERVICES`, `DF_DO_MACOS_SETTINGS`, `DF_DO_MACOS_QUICK_ACTIONS` | on, macOS | services, system settings, Finder actions |
| `DF_START_LOCAL_SERVICES` | off | start Colima, Ollama, mlxserve at login |
| `DF_DO_CURSOR`, `DF_DO_VSCODE` | macOS: on; Linux: off | editor extension/settings integration |
| `DF_DO_CMAKE`, `DF_DO_LOCAL_LLM`, `DF_DO_MEMORY`, `DF_DO_SKILLS` | on (`LOCAL_LLM`: full profile) | toolchains, model tooling, qmd/cass, skills |
| `DF_DO_BLENDER_MCP` | macOS: on; Linux: off | Blender add-on |
| `DF_DO_AUTH`, `DF_DO_OVERLAYS` | auth: off; overlays: on | token walk; sibling overlays |
| `DF_USE_PLAT`, `DF_BREW_UPGRADE`, `DF_STRICT_UPGRADE` | off; brew off except upgrade; strict upgrade on | runtime layout and upgrade policy |
| `DF_BREW_UPGRADE_CASKS`, `DF_BREW_UPGRADE_MAS` | `auto` | permit GUI/MAS upgrades only with a cached sudo ticket |

```sh
# narrow command-line machine
DF_PROFILE=core DF_DO_AUTH=0 DF_DO_LOCAL_LLM=0 ./bootstrap.sh

# configuration without common language/agent runtimes
DF_DO_PACKAGES=0 DF_DO_ZSH=0 DF_DO_NODE=0 DF_DO_RUST=0 \
DF_DO_PYTHON=0 DF_DO_CLAUDE=0 ./bootstrap.sh
```

`DF_PROFILE` is `core` or `full`; `core` defaults local-LLM setup off and
`full` defaults it on. The complete, revision-matched comments are in [the
`bootstrap.sh` header](../../bootstrap.sh) and [the environment-variable
reference](/reference/env-vars/).

## Debug mode

```sh
DF_DEBUG=1 ~/dotfiles/bootstrap.sh
```

This adds command and elapsed-time diagnostics. Keep the complete output when
reporting a failed stage.

## Shared home directories (NFS/GPFS)

```sh
DF_USE_PLAT=1 ~/dotfiles/bootstrap.sh
```

Use this only when one home is shared across incompatible CPU architectures.
It places each machine's compiled state in `~/.local/$PLAT`; text configuration
remains shared. [PLAT isolation](/setup/plat/) explains the layouts and safe
decommissioning.

### Scratch space (large quota environments)

```sh
DF_SCRATCH=/scratch/$USER ~/dotfiles/bootstrap.sh
```

Bootstrap links selected heavy state into `$DF_SCRATCH/.paths` before installs.
`~/.claude` and `~/.codex` remain real chezmoi-managed directories; only their
unmanaged heavy children move. See [scratch space](/setup/scratch/) before
running it on an existing machine.

## Auth (API tokens)

```sh
bash ~/dotfiles/install/auth.sh status
DF_DO_AUTH=1 ~/dotfiles/bootstrap.sh
```

The guided registry stores opted-in values in owner-only env files. Read
[auth](/setup/auth/) for service selection and file handling.
