# PLAT isolation

PLAT (PLATform) is the per-architecture directory namespacing scheme this repo uses to make a single `$HOME` work across machines with **different CPU architectures**. It's **off by default** because most users have one machine.

## The decision in 30 seconds

```text
Do you share $HOME across machines with different CPUs (NFS, etc.)?
├── No  →  leave DF_USE_PLAT=0 (default).  Done.
└── Yes →  set DF_USE_PLAT=1 on every machine that shares the home.
           Each machine installs into ~/.local/$PLAT/ instead of ~/.local/.
           One home, many machines, no clobbering.
```

| | `DF_USE_PLAT=0` (default) | `DF_USE_PLAT=1` |
|---|---|---|
| **Layout** | flat `~/.local/{bin,brew,cargo,nvm,…}` | per-PLAT `~/.local/$PLAT/{bin,brew,cargo,nvm,…}` |
| **`$LOCAL_PLAT`** | `$HOME/.local` | `$HOME/.local/$PLAT` |
| **Capability flags** | still applied (CPU-tuned `-march`, `RUSTFLAGS`, `HOMEBREW_OPTFLAGS`) | same |
| **PATH entries** | `~/.local/bin` first | `~/.local/$PLAT/bin` first, then `~/.local/bin` |
| **Disk per machine** | one tree (~few GB) | one tree per PLAT (~few GB × N) |
| **Right for** | single laptop, workstation, VM | NFS-shared `$HOME` across heterogeneous CPUs (HPC, lab racks) |

## Layouts side-by-side

```text
DF_USE_PLAT=0  (default, flat)        DF_USE_PLAT=1  (NFS-shared homes)
─────────────────────────────         ────────────────────────────────────
~/.local/                             ~/.local/
├── bin/                              ├── plat_Darwin_arm64/
│   ├── chezmoi                       │   ├── bin/{chezmoi,uv,claude}
│   ├── uv                            │   ├── brew/        (Apple Silicon)
│   └── claude                        │   ├── cargo/bin/   (arm64 binaries)
├── brew/        (one prefix)         │   └── nvm/         (arm64 node)
├── cargo/bin/   (host arch)          ├── plat_Linux_x86-64-v3/
└── nvm/                              │   ├── brew/        (AVX2 glibc)
                                      │   └── ...
$_LOCAL_PLAT = ~/.local                └── plat_Linux_x86-64-v4/   (AVX-512)
                                          └── ...

                                      $_LOCAL_PLAT = ~/.local/$_PLAT
                                      (set per-shell from CPU detection)
```

Even with PLAT off, `.plat_env.sh` still sources at shell start so the host CPU gets `-march=x86-64-v3`, `RUSTFLAGS=-C target-cpu=apple-m1`, etc. Capability detection is independent of directory layout — only `LOCAL_PLAT` changes.

## What PLAT directories look like

`PLAT` is a string of the form `plat_{OS}_{cpu-target}`. Examples:

```text
plat_Darwin_arm64        # Apple Silicon
plat_Darwin_x86-64       # Intel Mac
plat_Linux_aarch64       # ARM Linux (Graviton, Ampere)
plat_Linux_x86-64-v4     # AVX-512 (Ice Lake+, Zen 4+)
plat_Linux_x86-64-v3     # AVX2    (Haswell+, Zen 2+)
plat_Linux_x86-64-v2     # SSE4.2  (Nehalem+)
```

Detection: shell startup scans `~/dotfiles/install/plat/plat_${OS}_*/` (highest level first), runs each spec's `.plat_check.sh`, picks the first that exits 0, then sources `.plat_env.sh` for compiler flags.

## Enabling PLAT isolation

**Per-machine, persistent** (recommended):

```sh
# Edit chezmoi data
chezmoi edit ~/.config/chezmoi/chezmoi.toml
# Set:
#     use_plat = true
chezmoi apply
exec zsh -l    # reload shell so $_LOCAL_PLAT picks up the new path
```

**One-shot via env var:**

```sh
DF_USE_PLAT=1 ~/dotfiles/bootstrap.sh
```

The env var is normalized — `1`, `true`, `yes`, `on` (case-insensitive) all enable.

## Disabling / migrating off PLAT

When you switch a machine from `DF_USE_PLAT=1` back to flat, the old `~/.local/$PLAT/` tree becomes orphaned (multi-GB of cargo registry, nvm node versions, uv tools, etc., all stranded). One-shot cleanup:

```sh
# 1. Set DF_USE_PLAT=0 (or remove use_plat=true from chezmoi data)
# 2. Reload shell so the running session sees the flat layout
# 3. Run the decommission script:
bash ~/dotfiles/install/plat-decommission.sh
```

The script is **standalone** — never invoked by `bootstrap.sh` (including upgrade mode), to prevent accidental data loss. Safety guarantees:

- **Refuses to run** if `DF_USE_PLAT=1` is currently set in the environment (won't nuke the active install)
- **Asks for confirmation** before deleting (skip with `DF_FORCE=1`)
- **Idempotent** — running with no `~/.local/plat_*/` dirs is a no-op
- After cleanup, re-run `~/dotfiles/bootstrap.sh` to repopulate the flat layout

## Failure modes PLAT exists to prevent

If you skip PLAT but actually share `$HOME` across architectures, you get one of these:

- **Wrong-arch binary on PATH** — Linux machine sees Apple Silicon `~/.local/bin/uv`; runs and immediately segfaults with `Bad CPU type` or `cannot execute binary file`.
- **Cargo registry corruption** — two machines share `~/.local/cargo/registry/` and race-update the index Git repo. Eventually one machine's `cargo build` fails with "object file is broken."
- **nvm node-version collisions** — one machine's `node v25.9.0` is x86_64 ELF; another machine sees the same path containing arm64. `node --version` segfaults.
- **Brew prefix incompatibility** — Brew's bottle relocation embeds the prefix path in binaries. Running `brew install foo` on machine A then trying to use `foo` on machine B without re-installing fails because the embedded RPATH is for A's libgcc.

PLAT is the heavy hammer that solves all of these by giving each architecture its own tree. The cost is disk space (a few GB × number of machines) and one extra path segment in `$_LOCAL_PLAT`.

## Why opt-in by default

Most people have one machine. The per-PLAT directory adds a layer of indirection, breaks tools that hard-code their own install location (`uv self update` was the canonical bug), and makes default tutorials more confusing. The mainstream answer to "what about binaries on shared `$HOME`?" in the broader ecosystem is **don't share that part of `$HOME`** (move `~/.local` to local disk per host). PLAT exists for the cases where that's not an option — typically HPC NFS where you can't.

See `install/_lib.sh` (the `### PLATFORM ###` block) for the implementation.
