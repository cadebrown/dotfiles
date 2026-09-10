# Managing dotfiles

[chezmoi](https://chezmoi.io) renders `home/` into the home directory. Edit the
source, preview the rendered result, then apply; a rendered target is not the
durable source of truth.

## Data flow

```mermaid
flowchart LR
  S[home/dot_*.tmpl] --> C[chezmoi apply]
  D[chezmoi.toml data] --> C
  C --> H[managed files under HOME]
  H --> R[new login or app runtime]
```

Templates render at apply time. Name, email, and setup choices are cached in
`~/.config/chezmoi/chezmoi.toml`; bootstrap prompts only when required values
are missing.

## The quick version

```sh
chezmoi edit ~/.zshrc       # edit source only
chezmoi edit ~/.zshrc --apply  # edit source, then apply after editor exit
chezmoi diff                # inspect pending rendered changes
chezmoi apply               # deploy all pending changes
chezmoi update              # update source and apply
```

After a login-profile change, open a new login shell (`exec zsh -l`) before
judging runtime behavior.

## How files map

| Source | Target |
| --- | --- |
| `home/dot_zshrc.tmpl` | `~/.zshrc` |
| `home/dot_zprofile.tmpl` / `dot_bash_profile.tmpl` | login profiles |
| `home/dot_config/...` | `~/.config/...` |
| `home/dot_ssh/config.tmpl` | `~/.ssh/config` |
| `home/dot_claude/`, `home/dot_codex/` | agent configuration |

`dot_` maps to a leading dot and `.tmpl` means a Go template. Browse
[`home/`](../../home/) for the complete source tree.

## Template variables

| Variable | Meaning |
| --- | --- |
| `.name`, `.email` | first-bootstrap identity values |
| `.chezmoi.os` | stable operating-system branch |
| `.chezmoi.username`, `.chezmoi.homeDir` | observed local identity/path |

Use per-machine facts at shell runtime when the target file is shared. See
[PLAT isolation](/setup/plat/) for the layout contract.

## Editing dotfiles

```sh
# direct source workflow
${EDITOR:-vi} ~/dotfiles/home/dot_zshrc.tmpl
chezmoi diff
chezmoi apply
exec zsh -l
```

`chezmoi edit ~/.zshrc --apply` is the target-based equivalent of this
workflow; `--watch` applies each saved edit. Plain `chezmoi edit` changes only
the source. Do not edit
`~/.zshrc`, `.zprofile`, or `.bash_profile` directly: the next apply replaces
the change.

## Shared home directory safety

All machines sharing a home write the same target files. Do not render an
architecture-specific template value into those files; evaluate it when the
shell starts instead:

```sh
# stable template; runtime chooses the current machine
export PATH="$HOME/.local/$(uname -m)-$(uname -s)/bin:$PATH"

# unsafe in a shared target: each host rewrites a different value
# export PATH="$HOME/.local/{{ .chezmoi.arch }}/bin:$PATH"
```

Existing templates may branch by OS where that is an intentional deployment
boundary. Keep cross-host executable isolation in the runtime path helper.

## Host configuration

Store machine-dependent inputs separately from shared rendered files. Bootstrap,
login shells, Fish, and agent launchers use the same runtime resolver; applying
dotfiles on one machine must not select the platform for every shared-home host.

```text
defaults → dotfiles-*/hosts/<hostname>.env → local override → invocation env
                              │
                   resolve at process startup
                    ├─ DF_TOOLS_ROOT + PLAT → binaries
                    └─ DF_STATE_ROOT/codex → local Codex state
```

Run the guided configurator on the machine being configured:

```sh
bash ~/dotfiles/install/host.sh configure
bash ~/dotfiles/install/host.sh show
```

It stores local overrides in `~/.config/dotfiles/hosts/<hostname>.env`, using
the exact output of `hostname`, not an SSH alias. The format is data-only
`KEY=value`, not shell code. Use absolute paths without shell substitutions.
At the root-directory prompts, Enter keeps the displayed default and `-`
clears it. Unattended setup never waits for a prompt. To include the wizard in
an interactive first bootstrap, set `DF_HOST_CONFIGURE=1`; an existing local
host file is not replaced automatically.
After changing an existing host policy, start a fresh login (a new SSH connection
on a remote host). A nested shell inherits exported `DF_*` and `CODEX_HOME`
values, which intentionally take precedence over files.

| Input | Default | Meaning |
| --- | --- | --- |
| `DF_PROFILE` | `full` | `core` or `full` package selection |
| `DF_USE_PLAT` | `0` | architecture-separated tools |
| `DF_PLAT` | `auto` | compatible platform detection or explicit specification |
| `DF_TOOLS_ROOT` | `~/.local` | base directory before the optional PLAT suffix |
| `DF_STATE_ROOT` | unset | persistent host-local state; Codex uses its `codex` child |
| supported `DF_DO_*` flags | bootstrap defaults | optional installer selection |

An ordinary local-home machine needs no host file. Shared homes need an explicit
local state root for Codex; there is no automatic fallback to NFS or temporary
storage. `CODEX_HOME` remains an explicit launch override.

Keep internal presets in a private [overlay](overlays.md), under
`hosts/<hostname>.env`. Local overrides need not be committed. Neither file
should contain credentials. The public resolver has no employer-specific paths.
Use `DF_TOOLS_ROOT` directly rather than repointing a shared `~/.local` symlink.
`DF_SCRATCH` remains bulk storage and does not imply filesystem locality.

Sources: [`install/_host-config.sh`](../../install/_host-config.sh),
[`install/host.sh`](../../install/host.sh), and
[`install/_runtime-paths.sh`](../../install/_runtime-paths.sh). This complements
[chezmoi's per-machine setup](https://www.chezmoi.io/user-guide/setup/) with
runtime resolution for files shared by multiple machines.

## Multi-machine sync

```sh
# source machine: edit, preview, apply, then publish through normal Git workflow
chezmoi diff && chezmoi apply

# each other machine: refresh its own local target
chezmoi update
```

`chezmoi apply` affects only the machine where it runs. For a one-off render,
use `chezmoi execute-template < source.tmpl` and copy the result deliberately.

## Files that other tools also write

Treat these as managed/configuration boundaries: editor settings, agent config,
and shell profiles may be linked or updated by their matching installer after
chezmoi applies the source. Inspect `chezmoi diff` and the relevant installer
before resolving a conflict by hand. See [configuration recipes](/workflows/configuration-recipes/)
and [troubleshooting](/usage/troubleshooting/) for repeatable diagnosis.
