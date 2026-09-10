# PLAT isolation

PLAT gives each incompatible machine using one shared home a distinct runtime
tree. It is off by default because a single machine needs the simpler flat
layout.

## The decision in 30 seconds

```text
Shared HOME across different CPU architectures?
├── no  → use DF_USE_PLAT=0 (default)
└── yes → use DF_USE_PLAT=1 on every participating host
          each host installs under ~/.local/$PLAT/
```

| | Flat default | PLAT isolation |
| --- | --- | --- |
| local root | `~/.local` | `~/.local/$PLAT` |
| executable path | `~/.local/bin` | `~/.local/$PLAT/bin` first |
| suitable for | one laptop, VM, workstation | heterogeneous NFS/GPFS home |
| cost | one runtime tree | disk per platform |

Capability flags are detected in both layouts; PLAT changes directory isolation,
not CPU tuning.

## Layouts side-by-side

```text
flat                         PLAT-isolated shared home
~/.local/bin                ~/.local/plat_Darwin_arm64/bin
~/.local/cargo              ~/.local/plat_Linux_x86-64-v3/cargo
~/.local/nvm                ~/.local/plat_Linux_aarch64/nvm
```

`LOCAL_PLAT` is the installer root selected by [`install/_lib.sh`](../../install/_lib.sh).
Managed login profiles export the same path as `$_LOCAL_PLAT` for interactive
inspection and project commands.

## What PLAT directories look like

Names are `plat_{OS}_{cpu-target}`, for example `plat_Darwin_arm64`,
`plat_Linux_aarch64`, `plat_Linux_x86-64-v3`, and `plat_Linux_x86-64-v4`.
Detection selects the highest matching `install/plat/` specification and sources
its environment. PLAT-on fails if no matching spec exists; flat mode can run
without one.

## Enabling PLAT isolation

```sh
# persistent per-host setting: choose PLAT isolation in guided setup
bash ~/dotfiles/install/host.sh configure
bash ~/dotfiles/install/host.sh show
exec zsh -l

# or one bootstrap invocation
DF_USE_PLAT=1 ~/dotfiles/bootstrap.sh
```

The environment parser accepts `1`, `true`, `yes`, or `on`.

PLAT is resolved at startup, not rendered from shared chezmoi data. See
[host configuration](chezmoi.md#host-configuration) for private overlay presets,
local overrides, and an explicit tools root. PLAT distinguishes compatible
binary targets, not hosts: same-PLAT machines still need separate local
SQLite databases and runtime sockets.

## Disabling / migrating off PLAT

Disable the setting, open a fresh login shell, then run the explicit cleanup:

```sh
bash ~/dotfiles/install/plat-decommission.sh
~/dotfiles/bootstrap.sh
```

The cleanup is never part of bootstrap. It refuses an active PLAT environment,
asks before removal (unless explicitly forced), and is a no-op when no old trees
remain. Inspect its target before confirming.

## Failure modes PLAT exists to prevent

Without isolation, shared hosts can resolve a wrong-architecture executable or
share nonportable Cargo, nvm, and Homebrew state. Typical symptoms are an
unexecutable binary, cache corruption, or a relocated-prefix failure. PLAT keeps
those compiled trees apart while still sharing text configuration.

## Why opt-in by default

The extra path segment costs disk and complicates tools that hard-code their
installation root. Prefer the flat layout unless a shared heterogeneous home
actually creates the collision risk. [Runtime paths](/architecture/runtime-paths/)
and [scratch space](/setup/scratch/) cover the related layout decisions.
