---
title: New-machine workflows
description: Practical bring-up paths for macOS, rootless Linux, and NFS-shared homes.
---

## A normal macOS or Linux machine

Clone the repository to the intended durable location and use the local script.
This makes it easy to inspect the revision, preserve a working tree, and retry
from the same source.

```bash
git clone https://github.com/cadebrown/dotfiles "$HOME/dotfiles"
cd "$HOME/dotfiles"
DF_NAME='Your Name' DF_EMAIL='you@example.com' ./bootstrap.sh
```

The local script records the repository as chezmoi’s source directory after
applying its managed files
([source](https://github.com/cadebrown/dotfiles/blob/main/bootstrap.sh#L390)).
Linux installation is designed to be rootless; OS packages that require sudo
are outside this lifecycle. On macOS, Homebrew casks may still trigger their
own platform prompts.

After completion, open a fresh login shell and exercise only what was selected:

```bash
exec zsh -l
bash ~/dotfiles/install/verify-tools.sh
chezmoi diff
```

## NFS home with local scratch

Use platform isolation only when the same home is mounted by machines with
different CPU architectures. Put the large runtime state on a stable local disk
before bootstrap, then ask the installer to resolve `~/.local` through it:

```bash
mkdir -p "/local/$USER"
DF_SCRATCH="/local/$USER" DF_USE_PLAT=1 ./bootstrap.sh
```

Scratch redirection is intentionally conservative: it verifies copied entries
before replacing the source directory
([source](https://github.com/cadebrown/dotfiles/blob/main/install/scratch.sh#L154)).
Do not point it at ephemeral `tmpfs` storage unless loss after reboot is
acceptable; the script warns when it detects that filesystem type
([source](https://github.com/cadebrown/dotfiles/blob/main/install/scratch.sh#L86)).

## Update routine

Use `update` for the normal reconciliation path and `upgrade` when deliberately
accepting managed runtime upgrades. `upgrade` can surface version or upstream
configuration changes, so keep its output and resolve its final audit rather
than treating it as a background refresh. See [updates](/usage/updates/) and
[platform isolation](../architecture/runtime-paths.md) for the detailed limits.
