---
paths:
  - "install/cmake.sh"
  - "install/cmake/**"
  - "install/plat/**"
  - "home/dot_profile.tmpl"
---

# CMake toolchains, CUDA, compiler caching

## CMake toolchains

`install/cmake.sh` deploys `install/cmake/toolchains/{llvm,gcc}.cmake` to
`$LOCAL_PLAT/cmake/toolchains/`. `~/.profile` sets `CMAKE_TOOLCHAIN_FILE` to
the LLVM file when Homebrew LLVM is present. Switch with:

```sh
CMAKE_TOOLCHAIN_FILE="$_LOCAL_PLAT/cmake/toolchains/gcc.cmake" cmake -B build
```

Source files live in `install/cmake/toolchains/` — edit them there, not in the
deployed copies.

Per-session switching: the `tc` function in `.zshrc` — `tc gcc-13`, `tc gcc-15`,
`tc llvm-22`, `tc llvm-21`, `tc list`, `tc` (show current). GCC variants set
CC/CXX/AR/RANLIB/NM; LLVM variants only set CMAKE_TOOLCHAIN_FILE.

## CUDA convention

CUDA is **not** managed by bootstrap. It must be installed separately (system package,
NVIDIA runfile, or sysadmin-provided module). To integrate it with the PLAT layout:

```sh
# Point the per-PLAT symlink at whichever toolkit this machine uses
ln -sfn /usr/local/cuda              "$_LOCAL_PLAT/.cuda"   # system default
ln -sfn /opt/nvidia/cuda/12.6        "$_LOCAL_PLAT/.cuda"   # versioned
ln -sfn "$(which nvcc | xargs dirname)/../" "$_LOCAL_PLAT/.cuda"  # from PATH
```

`~/.profile` resolves `$_LOCAL_PLAT/.cuda` via `realpath` and exports:
- `CUDA_PATH` — used by many build systems and NVCC itself
- `CUDAToolkit_ROOT` — the canonical CMake variable for `find_package(CUDAToolkit)`
- Prepends `$CUDA_PATH/bin` to `PATH` so `nvcc` is available

Both CMake toolchain files (`llvm.cmake`, `gcc.cmake`) check for
`$_LOCAL_PLAT/.cuda/bin/nvcc` and set `CMAKE_CUDA_COMPILER` when found.
`CMAKE_CUDA_HOST_COMPILER` is always set to the toolchain's C++ compiler.

Different machines on a shared NFS home can point `$LOCAL_PLAT/.cuda` at
different toolkit versions — no conflicts.

## Compiler caching

`~/.profile` auto-configures ccache and sccache when installed. Key settings:
- `CCACHE_BASEDIR` = scratch root (enables cross-directory cache sharing)
- `CCACHE_COMPILERCHECK=content` (survives brew reinstalls)
- `CCACHE_SLOPPINESS=file_stat_matches,time_macros` (higher hit rate)
- `CCACHE_HARDLINK=1` (zero-copy cache hits on same partition)
- `RUSTC_WRAPPER=sccache` for Rust builds

## Gotchas

- **mold/lld need `--disable-new-dtags` on Linux** — these linkers default to DT_RUNPATH,
  which is searched after ld.so.cache, so the system's older libstdc++ wins over Homebrew's.
  All four CMake toolchain files add `-Wl,--disable-new-dtags` when selecting mold or lld.
  `~/.profile` also sets `LDFLAGS` with the same flag for non-CMake builds.
- **sccache is wired at ALL three layers** — so every cargo build hits the shared cache:
  1. shell profiles (`~/.profile`) → `RUSTC_WRAPPER` for login/interactive shells;
  2. `install/_lib.sh` → exports `RUSTC_WRAPPER` (guarded on `command -v sccache`) so
     bootstrap's non-login install scripts (`rust.sh`, the cass build) get it;
  3. `$CARGO_HOME/config.toml` `[build] rustc-wrapper` (written by `rust.sh`, guarded on
     `has sccache`) → read by cargo itself, so even bare cron/CI/non-login `cargo build`
     is covered.
  Layer 3 is safe here ONLY because `CARGO_HOME` is on **per-machine scratch**, not the
  shared NFS home — a config referencing sccache can't break a sibling machine, and
  `rust.sh` never clobbers a hand-written config. Caveat: if you uninstall sccache, drop
  the `rustc-wrapper` line too or cargo errors on every build. sccache passes incremental
  (dev) builds straight through — it only caches clean/release/`cargo install` builds.
