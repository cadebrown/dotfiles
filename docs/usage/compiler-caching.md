# Compiler caching with sccache

Managed login shells and bootstrap install scripts use [sccache](https://github.com/mozilla/sccache/blob/v0.17.0/README.md) as the compiler launcher when it is available (0.17.0 on the audited Mac). It is the sole managed compiler-cache package in the [Brewfile](../../packages/Brewfile): CMake C, C++, Objective-C, Objective-C++, CUDA, and HIP launchers and Cargo's `RUSTC_WRAPPER` default to `sccache`. The local cache limit is **250 GiB**.

This is a local, machine policy. It does not configure remote storage, distributed compilation, or any project outside this repository. A cache hit can avoid an eligible compiler invocation; it does not validate compiler correctness, linking, tests, ABI compatibility, or deployment behavior.

Read [build performance by language](build-performance.md) for incremental builds, optimization levels, linker choices, and the languages that use their own caches. Sccache has known limitations and does not support every compiler.

## Managed configuration

The shared [`compiler-cache.sh`](../../home/.chezmoitemplates/compiler-cache.sh) snippet is included by the login profile and sourced by [`install/_lib.sh`](../../install/_lib.sh). It selects the managed [native sccache configuration](../../home/dot_config/sccache/config.tmpl). Linux reads `~/.config/sccache/config`; macOS's native `~/Library/Application Support/Mozilla.sccache/config` is a symlink to the same file. Non-login Cargo and other direct sccache callers therefore get the same disk policy without inheriting shell variables. All four installed GCC/LLVM CMake toolchains also include the [launcher defaults](../../install/cmake/toolchains/_cache.cmake).

The piped bootstrap defers this configuration until it has cloned the repository; its earlier directory setup does no compilation. Before chezmoi deploys the native configuration, the helper supplies the same local path and `250G` size through environment variables. An already-running shell retains its old environment until it sources the updated profile or starts a new shell.

When `sccache` is on `PATH`, the snippet supplies these defaults:

| Variable | Default | Purpose |
| --- | --- | --- |
| `CMAKE_C_COMPILER_LAUNCHER` | `sccache` | C launcher recorded when CMake configures a build tree |
| `CMAKE_CXX_COMPILER_LAUNCHER` | `sccache` | C++ launcher recorded when CMake configures a build tree |
| `CMAKE_CUDA_COMPILER_LAUNCHER` | `sccache` | CUDA launcher recorded when CMake configures a build tree |
| `CMAKE_HIP_COMPILER_LAUNCHER` | `sccache` | HIP launcher; runtime GPU validation is host-specific |
| `CMAKE_OBJC_COMPILER_LAUNCHER`, `CMAKE_OBJCXX_COMPILER_LAUNCHER` | `sccache` | Objective-C and Objective-C++ |
| `RUSTC_WRAPPER` | `sccache` | Cargo compiler wrapper; the existing Cargo configuration remains in place for non-login Cargo invocations |
| Native `[cache.disk].dir` | `~/.cache/sccache` | Local cache directory; `SCCACHE_DIR` overrides it |
| Native `[cache.disk].size` | `268435456000` bytes (250 GiB) | Maximum cache size; `SCCACHE_CACHE_SIZE` overrides it |
| Native `client_side_mode` | `false` | Keep the server mode that performed better in the local probes |

The launcher and wrapper use `${VAR-sccache}`, so an inherited value, including an explicitly empty one, wins. An explicit `SCCACHE_CONF` selects a different configuration; `SCCACHE_DIR` and `SCCACHE_CACHE_SIZE` override file settings. The helper does not inject conflicting storage variables when a configuration is selected. Set machine overrides in the process that launches the shell or build command, before profile startup. For example:

```sh
SCCACHE_DIR=/Volumes/build-cache/sccache SCCACHE_CACHE_SIZE=40G zsh -l
```

The profile recognizes the former dotfiles policy by its paired
`CCACHE_SLOPPINESS=file_stat_matches,time_macros` and `CCACHE_HARDLINK=1` settings.
Once per inherited environment, it removes that policy's cache variables and
replaces `ccache` launchers with the new defaults, even if `_PROFILE_SOURCED`
was already set. Source it to update an existing Bash or Zsh session:

```sh
. ~/.profile
```

For Fish, start a new Fish shell. Its bridge imports both changed values and
explicit removals, so stale flags do not survive merely because Bash unset them.
This also enables Python bytecode caching by clearing
`PYTHONDONTWRITEBYTECODE`. Unrelated explicit compiler overrides remain intact.
During the one-time legacy migration, reapply any intentional cache storage
override after startup; it replaces the former environment-derived cache size
with the native file policy. Existing CMake build trees still need reconfiguration.

Or apply it to one configure/build sequence:

```sh
SCCACHE_CACHE_SIZE=40G cmake -S . -B build -G Ninja
SCCACHE_CACHE_SIZE=40G cmake --build build
```

An empty wrapper is a supported bypass for a Cargo command, even though the managed Cargo configuration names `sccache`:

```sh
RUSTC_WRAPPER= cargo build
```

The 250 GiB maximum is a cache limit, not a reservation or a combined budget with other derived data. On the audited Mac, the cache filesystem had approximately 1.2 TiB free before applying it. The limit is intentionally large and no longer scales from total capacity; set a smaller machine override on disks with less space. See sccache's pinned [configuration reference](https://github.com/mozilla/sccache/blob/v0.17.0/docs/Configuration.md) and [local storage reference](https://github.com/mozilla/sccache/blob/v0.17.0/docs/Local.md).

The native policy enables direct/preprocessor caching while hashing header contents, tracking system headers and the working directory, and respecting time macros. `file_stat_matches=false`, `ignore_time_macros=false`, `skip_system_headers=false`, and `hash_working_directory=true` preserve those choices explicitly. Compression stays at the upstream zstd level 3. No global base-directory rewriting, remote cache, or distributed-build service is configured. Direct mode still has an upstream-documented conditional-header limitation: a previously absent optional header appearing can require `SCCACHE_DIRECT=false` or invalidation for that project.

Storage settings take effect when the local sccache server starts. Changing an environment variable does not reconfigure an already-running server. At a quiet build boundary, run `sccache --stop-server` and then `sccache --start-server` from the environment with the intended settings. Confirm the actual location and capacity with `sccache --show-stats`. Do not stop a server while other builds are using it.

Restart old IDE/agent processes as well: a direct child that skips shell startup
can still inherit their former `SCCACHE_CACHE_SIZE` and restart the daemon with
that smaller limit. The final sweep reproduced a return to 74 GiB and restored
250 GiB at an idle boundary. The native configuration cannot override an explicit
environment value held by an already-running parent process.

## CMake and CUDA

CMake captures compiler launchers while it configures a build directory. Reconfigure an existing build tree to adopt sccache; deleting the tree is unnecessary:

```sh
cmake -S . -B build -G Ninja \
  -DCMAKE_C_COMPILER_LAUNCHER=sccache \
  -DCMAKE_CXX_COMPILER_LAUNCHER=sccache \
  -DCMAKE_CUDA_COMPILER_LAUNCHER=sccache \
  -DCMAKE_HIP_COMPILER_LAUNCHER=sccache \
  -DCMAKE_OBJC_COMPILER_LAUNCHER=sccache \
  -DCMAKE_OBJCXX_COMPILER_LAUNCHER=sccache
cmake --build build --verbose
```

Use a project preset or scoped `-D` values when a project needs a different launcher. `CMAKE_<LANG>_COMPILER_LAUNCHER` is CMake's documented interface for this integration. It does not change the compiler selected by `CC`, `CXX`, or a toolchain file. See [CMake's launcher variable reference](https://cmake.org/cmake/help/latest/variable/CMAKE_LANG_COMPILER_LAUNCHER.html).

This launcher integration applies to Ninja and Makefile generators. Meson 1.12 independently prefers sccache when it auto-detects compilers, verified locally; explicit `CC`/`CXX` can suppress that behavior and need a cache prefix or machine file. Raw Make/Autotools and native extensions need their own compiler-wrapper setting. Xcode uses its native compilation cache. The [language guide](build-performance.md) gives concrete recipes and boundaries. Never wrap one cache inside the other.

The policy applies CUDA and HIP launchers but does not establish GPU-platform coverage or a performance result. Confirm the emitted compiler command and sccache statistics on each CUDA/HIP project and host before relying on it for a particular workflow.

## Local storage on shared-home Linux machines

`~/.cache/sccache` is appropriate only when `~/.cache` resolves to machine-local scratch storage. On a Linux machine whose home directory is NFS, configure the cache path before opening the login shell if the managed scratch layout is absent:

```sh
SCCACHE_DIR=/var/tmp/$USER/sccache zsh -l
```

Verify the resolved location and filesystem before compiling:

```sh
mkdir -p "$SCCACHE_DIR"
cache_path="$(cd "$SCCACHE_DIR" && pwd -P)"
printf '%s\n' "$cache_path"
df -Pk "$cache_path"
```

The reported path and filesystem must be local to that machine, not the NFS-mounted home. Do not point multiple machines at the same local-cache directory, and do not infer remote-cache support from this policy.

## Installation and limits

Fresh bootstrap installs resolve `sccache` through rootless Homebrew from the managed Brewfile. The migration removes the managed `ccache` package request and global `CCACHE_*` settings, but it does not uninstall an already-installed `ccache` binary or delete its old cache directory. Those are user-owned local state.

Cargo incremental compilation remains enabled by Cargo's normal defaults; this policy does not set `CARGO_INCREMENTAL=0`. Sccache only caches eligible invocations, and some Rust crate types or incremental invocations are uncacheable. For the version-specific constraints, see the pinned [Rust caveats](https://github.com/mozilla/sccache/blob/v0.17.0/docs/Rust.md) and [Cargo wrapper configuration](https://doc.rust-lang.org/cargo/reference/config.html#buildrustc-wrapper).

Sccache 0.17.0 rejects an explicit `CARGO_INCREMENTAL=1` or `CARGO_BUILD_INCREMENTAL=1` before compiling. This differs from an ordinary Cargo development build whose incremental rustc invocation is passed through. For explicitly forced incremental builds use `RUSTC_WRAPPER= CARGO_INCREMENTAL=1 cargo build`. An empty wrapper bypasses both the environment default and Cargo's configured wrapper; unsetting it alone can expose the Cargo configuration again. See the pinned [command preflight](https://github.com/mozilla/sccache/blob/v0.17.0/src/commands.rs#L889-L909).

Cacheable development dependencies can benefit too; sccache is not exclusively a release-build tool. Rust linking and procedural macros have additional limitations. The earlier isolated metadata-only rlib probe also produced a hit on 0.17.0, despite the pinned Rust prose claiming that link output is mandatory; that observation does not establish that every `cargo check` invocation is cacheable.

## Migration verification

The [latest tuning evidence](../_data/compiler-cache-tuning.json) adds native configuration discovery without storage environment variables, successful C/C++/Objective-C/Objective-C++ cached rebuilds, Meson auto-detection and explicit-compiler behavior, a scoped Make cache hit, a Python bytecode-cache check, and server/client-side comparisons. The live Mac's daemon was restarted at a quiet build boundary and read back with a **268435456000-byte maximum**. Existing cache objects were retained. Client-side mode passed the functional tests but was slower on the tiny fixture, so it remains disabled; the fixed-order samples do not establish universal performance rankings.

The [migration evidence](../_data/compiler-cache-migration-check.json) records isolated probes on macOS arm64 on 2026-09-08 local time (2026-09-09 UTC), using sccache 0.17.0, ccache 4.14, Homebrew Clang 23.1.0, and Rust 1.98.1. These probes did not alter the existing user cache or stop its server.

- A CMake/Ninja executable with C and C++ translation units built successfully. Removing its objects and rebuilding produced two cache hits and the same result. Editing their shared header changed the executable result from `21` to `33`.
- A dependency-free Cargo release library rebuilt successfully after removing only its isolated target directory. The second build added one Rust cache hit, with no additional Rust misses. An earlier direct-rustc probe had malformed cache-parser arguments; the actual Cargo build resolves that diagnostic.
- Three alternating C++ fixture rounds used fresh cache directories and one warm recompile each. Median cold/warm times were **0.411 / 0.0176 seconds for ccache** and **0.446 / 0.0206 seconds for sccache**. Both avoided most compilation work; ccache was about 3 ms faster on the warm fixture. This is a small local microbenchmark, not a representative full-project comparison or evidence that sccache is universally fastest.

The choice of a unified sccache default accepts that small observed fixture overhead for one implementation spanning the managed languages. A substantial regression in a real project would justify an explicit exception. Linux and CUDA were not exercised on this Mac. The Docker bootstrap gate failed while building its Ubuntu image with package-signature errors; Colima's Docker filesystem was confirmed full. Native shell, cache-policy, and handbook checks do not establish that missing platform result.

## Before-migration audit

The [2026-09-08 audit evidence](../_data/compiler-cache-audit.json) is retained as a historical record of the earlier ccache/sccache split, local counters, and isolated probes. It is not the current configuration and is not a matched performance benchmark.

The removed ccache configuration relaxed correctness globally: `time_macros` allowed an object to retain an earlier `__TIME__` value, reproduced by the audit; `file_stat_matches` substituted file metadata checks for include-content checks; and hardlink mode shared object storage and prevented compression of those entries. These were custom settings, not evidence that ccache's conservative defaults are unsafe. See the [ccache 4.14 manual](https://ccache.dev/manual/4.14.html).

## Why one cache, and where exceptions belong

Sccache covers this repository's Rust and C-family integrations with one service, cache directory, and storage budget. That is the reason for the default. Compiler caches restore eligible compilation results; Ninja's unchanged-file detection and rustc's incremental compilation solve different parts of the build loop. Increasing the cache-hit count by disabling useful incremental compilation can make actual development slower.

| Question | ccache 4.14 | sccache 0.17.0 |
| --- | --- | --- |
| C/C++ and CUDA | Supported | Supported |
| Rust | Unsupported | Eligible invocations supported |
| Remote storage | Supported | Supported, with multiple backends and hierarchical caching |
| Distributed compilation | Separate tools/integration | Optional separate sccache distributed-build system |
| Standard C++20 modules | Unsupported | Partial Clang named-module support; restrictions remain |
| Fastest local rebuilds | Workload-dependent | Workload-dependent |

The broader feature set does not make sccache universally faster. A project with a reproducible compatibility problem or substantial measured slowdown can override its launcher. Establish that exception with the actual compiler, build flags, clean rebuilds, header edits, and development loop. Keep debug-path remapping and relaxed cache semantics project-specific and verify their effect on diagnostics and dependency tracking. Upstream references: [ccache](https://ccache.dev/), [sccache overview and modules](https://github.com/mozilla/sccache/blob/v0.17.0/README.md), and [distributed-build requirements](https://github.com/mozilla/sccache/blob/v0.17.0/docs/DistributedQuickstart.md).
