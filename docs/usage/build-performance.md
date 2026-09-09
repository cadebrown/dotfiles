# Fast local builds

Use the cache and incremental system that matches the work being repeated. This
checkout makes a conservative local `sccache` policy available for eligible
C-family and Rust compilation, but the quickest edit/rebuild loop still depends
on the project, compiler, linker, generated code, and whether the changed work
is a translation unit, a dependency, or the final link. There is no universal
fastest configuration.

Start by naming the slow phase. A build usually has three independent layers:

1. **Incremental build planning**: Ninja, Cargo, Gradle, and similar tools avoid
   targets whose declared inputs have not changed.
2. **Compiler-result caching**: `sccache` can restore an eligible compiler
   result even when the build tool asks for the compile again.
3. **Linking and packaging**: the linker combines objects, and package/image
   steps assemble the deliverable. A compiler cache does not make this phase a
   hit.

Keep the first layer enabled for the normal edit loop. A clean build, a changed
header, a dependency update, and a final executable relink exercise different
layers, so measure each before changing a project profile. `sccache --show-stats`
reports cacheable requests, hits, misses, and reasons for bypassing the cache;
the underlying compile command remains the source of truth.

## What this checkout defaults

After a fresh login, `sccache` is the default CMake launcher for C, C++, CUDA,
HIP, Objective-C, and Objective-C++, and Cargo uses it as `rustc-wrapper` when
the managed Cargo configuration can be created. The four managed CMake
toolchains also include the same launcher policy, so a non-login CMake configure
can find `sccache`. An explicit launcher or wrapper value, including an empty
one, is a project/process override. See [compiler caching](./compiler-caching.md)
for the complete integration and shared-home storage rule.

The deployed native TOML configuration gives the local disk cache a **250 GiB
maximum** at `~/.cache/sccache`; it does not reserve 250 GiB. It keeps the
conservative direct-cache settings: preprocessor/direct mode is enabled,
`file_stat_matches` and time-macro ignoring are disabled, system headers are
included, and the working directory is hashed. The server remains local
(`client_side_mode = false`) and uses compression level 3. This favors correct cache
keys over avoidable hits. A changed cache limit applies after a quiet-boundary
server restart, not to a server already running.

```sh
sccache --show-stats
# At a quiet boundary only:
sccache --stop-server && sccache --start-server
```

The client-mode experiment in [`compiler-cache-tuning.json`](../_data/compiler-cache-tuning.json)
recorded 47.0 ms versus 18.5 ms for the fixed C fixture and 70.1 ms versus
21.5 ms for its C++ fixture (client versus server). It supports retaining the
server default on that host; it is not a general performance result.

The profile also selects Ninja and sets `CMAKE_BUILD_PARALLEL_LEVEL` to the
logical-core count only when the caller has not set it. Platform architecture
flags remain, but the profile no longer forces global C/C++ `-O2`; optimization
and debug/release choices belong to the project. Python now writes reusable bytecode under
`~/.cache/python/pycache` through `PYTHONPYCACHEPREFIX`; it does not suppress
bytecode. Gradle's user properties enable the daemon, parallel work, and build
caching. Configuration-cache compatibility remains a project decision.

## C and C++: keep the configured tree, then cache compiles

For a CMake project, configure once with Ninja and build the same directory.
The launcher is captured in its CMake cache, so reconfigure an existing tree
when changing its launcher rather than deleting it.

```sh
cmake -S . -B build -G Ninja \
  -DCMAKE_C_COMPILER_LAUNCHER=sccache \
  -DCMAKE_CXX_COMPILER_LAUNCHER=sccache
cmake --build build
cmake --build build --verbose
sccache --show-stats
```

The documented `CMAKE_<LANG>_COMPILER_LAUNCHER` interface accepts the same
pattern for CUDA, HIP, Objective-C, and Objective-C++. The latter three are
defaulted here only where the configured toolchain supports them; inspect the
actual command and statistics on the target host. sccache documents C/C++,
`nvcc`, and `hipcc` support, while CMake documents the launcher variable rather
than a specific cache implementation. [sccache's usage guide](https://github.com/mozilla/sccache/blob/v0.17.0/README.md#usage)
and [CMake's launcher reference](https://cmake.org/cmake/help/latest/variable/CMAKE_LANG_COMPILER_LAUNCHER.html)
are the relevant interfaces.

For Meson 1.12 or later, its environment configuration prefers `sccache` to
`ccache` when `CC` and `CXX` are unset. An explicit compiler needs a native
file command array or a prefix, so that sccache wraps the exact compiler rather
than a PATH alias:

```ini
# sccache-native.ini
[binaries]
c = ['sccache', '/opt/homebrew/opt/llvm/bin/clang']
cpp = ['sccache', '/opt/homebrew/opt/llvm/bin/clang++']
```

```sh
meson setup build --native-file sccache-native.ini
meson compile -C build
```

Meson's [machine-file documentation](https://mesonbuild.com/Machine-files.html)
defines these compiler-array semantics. For raw Make, Autotools, `cgo`,
setuptools, and node-gyp, use a command-scoped real compiler path, for example
`CC='sccache /absolute/path/to/clang' CXX='sccache /absolute/path/to/clang++'
make -j"$(sysctl -n hw.logicalcpu)"`. Do not set a global `CC` wrapper: nested
wrappers, compiler identity, and cross compilation are project-specific.

C++20 modules remain a coverage boundary. sccache has partial Clang named-module
support but bypasses header modules and implicit discovery; GCC and MSVC module
flows are unsupported. Conditional headers or generated inputs can similarly
invalidate or bypass a result. See sccache's [current caveats](https://github.com/mozilla/sccache/blob/v0.17.0/README.md#known-caveats).

## Rust: prioritize incremental development

Cargo's ordinary development profile stays incremental with its normal
`opt-level = 0`, full debug information, and 256 codegen units. That is
usually the fastest iteration path for workspace members and path dependencies.
The managed wrapper can still cache eligible non-incremental work, but sccache
does not cache the link for `bin`, `dylib`, `cdylib`, or `proc-macro` crates, and
incremental crate compilations are generally bypassed. Cargo's [profile
reference](https://doc.rust-lang.org/cargo/reference/profiles.html) and
sccache's [Rust caveats](https://github.com/mozilla/sccache/blob/v0.17.0/docs/Rust.md)
describe those separate controls.

Run the normal loop first:

```sh
cargo check                 # skips final code generation where possible
cargo test
cargo build
```

This sccache version has one important preflight rule: explicit
`CARGO_INCREMENTAL=1` is rejected. For a deliberately forced incremental
workflow, bypass the wrapper for that command:

```sh
RUSTC_WRAPPER= CARGO_INCREMENTAL=1 cargo build
```

For a clean, dependency-heavy CI/rebuild measurement, make non-incremental
compilation an explicit project/job choice and compare cold and warm runs:

```sh
CARGO_INCREMENTAL=0 RUSTC_WRAPPER=sccache cargo build --locked
sccache --show-stats
```

An isolated probe also observed a metadata-only Rust cache hit in this version.
That observation is useful but does not override the documented general rule or
prove `cargo check` coverage for another project. Proc macros, link products,
and compiler-version changes remain expected gaps.

If a repository needs a quick-to-compile optimized build for profiling or
acceptance tests, keep it local to that repository:

```toml
# Cargo.toml
[profile.fast-release]
inherits = "release"
opt-level = 3
debug = 0
lto = false
incremental = false
codegen-units = 128
```

More codegen units can reduce compile time and can make the generated program
slower. Shipping profiles should retain the project's own LTO, PGO, debug, and
codegen choices; PGO and LTO commonly add build work in exchange for runtime
optimization. For a debug-focused local profile, start from `dev` with
`debug = "line-tables-only"`, `incremental = true`, and `codegen-units = 256`.
It preserves useful locations while trading away some local-variable inspection.

## Language-native caches stay native

Python has two distinct caches: `.pyc` bytecode avoids recompiling imported
Python modules, while uv/pip cache downloads and built wheels. Both are enabled.
The shared profile clears the old `PYTHONDONTWRITEBYTECODE=1` default and sets
`PYTHONPYCACHEPREFIX` to `~/.cache/python/pycache`, preserving an explicit prefix.
An actual two-process import probe wrote and reused the same bytecode file.
This does not cache function results or make Python execution itself native code.
See [Python's bytecode settings](https://docs.python.org/3/using/cmdline.html#envvar-PYTHONPYCACHEPREFIX)
and [uv's cache guide](https://docs.astral.sh/uv/concepts/cache/).

Inspect the effective settings in a fresh shell:

```sh
uv run --offline python -c 'import sys; print(sys.dont_write_bytecode, sys.pycache_prefix)'
uv cache dir
pip3 cache dir            # when pip is installed
npm config get cache
go env GOCACHE GOMODCACHE
zig env
```

Python should report `False` followed by the configured prefix. The other
commands report their native cache directories. On the audited Mac, these were
`~/.cache/uv`, `~/Library/Caches/pip`, `~/.npm`, `~/.local/go-build`,
`~/.local/go/pkg/mod`, and `~/.cache/zig`. Paths vary by OS and PLAT layout;
shared-home machines must keep these caches on local storage. No cache-disabling
uv, pip, Go, CUDA, or PyTorch environment override was present after startup.
That is an environment audit, not a GPU or framework runtime test. Full selected
environment readbacks are in the [tuning evidence](../_data/compiler-cache-tuning.json).

Do not route unsupported compilers through sccache. Swift/Xcode 26's native
per-project compilation cache is enabled with
`COMPILATION_CACHE_ENABLE_CACHING=YES`; validate it in the Xcode project or
build settings, rather than wrapping `swiftc`; use the [Xcode 26 release
notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-26-release-notes)
for the matching Xcode version. Go already has its own
PLAT-specific `GOCACHE`; use scoped `CC`/`CXX` only for a tested cgo project.
Zig owns its build cache. Java uses Gradle's daemon, parallelism, and build
cache (or a Maven project cache choice); .NET uses its normal incremental build
and compiler server; TypeScript needs `tsc -b` or `incremental: true` in the
repository `tsconfig`; Julia uses package images and precompilation; Lean uses
Lake/Mathlib artifact caches. These systems have different input models, so
their project configuration is more reliable than a global compiler wrapper.

Gradle's user-level settings make its local build cache available, but they do
not assert that every task is cacheable or configuration-cache compatible. A
project can inspect that distinction without changing its defaults:

```sh
./gradlew build --build-cache --info
./gradlew help --configuration-cache
```

The [Gradle build-cache guide](https://docs.gradle.org/current/userguide/build_cache.html)
explains that task authors define cacheability and inputs. Treat a failing
configuration-cache run as a project integration issue, not a reason to force
the feature globally. Likewise, a TypeScript project should preserve its own
output directory and only enable `incremental` when its checked-in `tsconfig`
owns the generated `.tsbuildinfo` lifecycle.

## Measure the loop you care about

Use a fixed machine and toolchain for a before/after comparison. Run each case
at least once to populate tool startup state, then record wall time and cache
statistics for a clean build, an unchanged build, one local source edit, a
public-header/API edit, and the final test/package step. Compare the emitted
program or test result after the changed-input cases. This separates a true
compiler cache hit from Ninja/Cargo deciding no work was needed, and exposes a
link or code-generation bottleneck that cache tuning cannot solve.

For cross-checkout cache reuse, sccache normally includes absolute paths in its
key. `SCCACHE_BASEDIRS` can normalize intentionally chosen absolute worktree
roots, but it changes cache identity and should be set in a project or CI
environment only after checking debug paths and generated inputs. The
[sccache path-normalization reference](https://github.com/mozilla/sccache/blob/v0.17.0/README.md#normalizing-paths-with-sccache_basedirs)
documents the exact syntax.

For any optimization, record the exact command, toolchain, machine, cold/warm
state, and changed-input scenario. Faster compilation does not establish faster
runtime behavior, correct diagnostics, ABI compatibility, or a successful
deployment.
