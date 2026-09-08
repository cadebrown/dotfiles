---
title: Runtime paths and platform isolation
description: The LOCAL_PLAT contract for flat machines, shared homes, scratch storage, and tool paths.
---

## One path contract

Every installer sources `install/_lib.sh`, which derives runtime paths from
`LOCAL_PLAT`. In the ordinary flat layout that is `~/.local`; with
`DF_USE_PLAT=1`, it is `~/.local/$PLAT`. The latter is for one NFS-shared home
used from machines with incompatible architectures, not a general performance
setting.

| Variable | Purpose |
|---|---|
| `ARCH_BIN` | executable destination: `$LOCAL_PLAT/bin` |
| `CARGO_HOME`, `RUSTUP_HOME` | Rust tools and toolchains |
| `NVM_DIR` | Node versions and global npm package tree |
| `UV_TOOL_DIR`, `PYTHON_ENV` | uv tool environments and managed Python |
| `ELAN_HOME` | Lean toolchains and shims |
| `GOPATH`, `GOCACHE`, `GOBIN` | Go source/cache and executable destination |

The exact derivations are in
[`_lib.sh`](https://github.com/cadebrown/dotfiles/blob/main/install/_lib.sh#L150).
Platform detection chooses the highest matching `install/plat/` specification;
the lightweight runtime helper resolves `~/.local` through a scratch symlink
before adding the optional platform directory
([source](https://github.com/cadebrown/dotfiles/blob/main/install/_runtime-paths.sh#L12)).

```bash
# Normal single-machine layout
./bootstrap.sh

# Only for an NFS-shared HOME across architectures
DF_USE_PLAT=1 ./bootstrap.sh
```

In PLAT mode, failure to find a matching platform specification is fatal. In
flat mode, detection still supplies capability flags when available but no
matching specification is acceptable
([source](https://github.com/cadebrown/dotfiles/blob/main/install/_lib.sh#L142)).

## Shell and scratch convergence

Generated login profiles use the same layout: they put the selected runtime bin
ahead of Homebrew and export the language-specific homes
([zprofile source](https://github.com/cadebrown/dotfiles/blob/main/home/dot_zprofile.tmpl#L105)).
Confirm what the current shell actually resolves before diagnosing a tool:

```bash
printf '%s\n' "$DF_USE_PLAT" "${_LOCAL_PLAT:-unset}"
command -v cargo node python lean
bash ~/dotfiles/install/verify-path.sh
```

`DF_SCRATCH` can redirect large writable directories to local storage. The
scratch installer copies, verifies entries, and only then replaces a real
directory with a symlink
([source](https://github.com/cadebrown/dotfiles/blob/main/install/scratch.sh#L128)).
It intentionally keeps managed `~/.claude` and `~/.codex` directories real and
moves selected unmanaged subdirectories instead
([source](https://github.com/cadebrown/dotfiles/blob/main/install/scratch.sh#L38)).
See [PLAT setup](/setup/plat/) and [scratch setup](/setup/scratch/) before
enabling either feature on a populated home.
