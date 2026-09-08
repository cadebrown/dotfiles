# Package management

Manifests declare ownership; installers reconcile them idempotently. Find the
owner before adding a tool, then run its installer or the normal bootstrap.

## The layers

| Owner | Manifest | Installer | Use for |
| --- | --- | --- | --- |
| Homebrew | `packages/Brewfile` | `install/homebrew.sh` | system tools, libraries, casks |
| Cargo | `packages/cargo.txt` | `install/rust.sh` | Rust CLIs with suitable releases |
| uv | `packages/python.txt`, `pip*.txt` | `install/python.sh` | Python libraries and isolated CLIs |
| npm/nvm | `packages/npm*.txt` | `install/node.sh` | Node CLIs |
| Go | `packages/go.txt` | `install/go.sh` | Go CLIs |
| agents/editors | package lists plus `home/dot_*` | matching installer | plugins, skills, MCP, extensions, config |

Use one owner per executable. A duplicate Homebrew/npm, pip/uv, or Cargo/tap
install produces ambiguous upgrades and PATH behavior. See
[package ownership](/architecture/package-ownership/) for the contract.

## Adding a package — priority order

1. Prefer the language-native list when it owns the tool: Cargo, npm, uv, or Go.
2. Use Homebrew for system dependencies, GUI apps, SDKs, and tools without a
   suitable native path.
3. Add a focused installer only when neither list expresses its lifecycle.

Before editing, search all ownership sources and identify a probe:

```sh
cd ~/dotfiles
rg -n '(^|/)tool-name([ @#]|$)' packages install home
# edit the selected manifest, then run its installer
bash install/rust.sh                 # example for packages/cargo.txt
command -v tool-name && tool-name --version
```

The [source manifests](../../packages/) are the current inventory. Comments in
each list carry platform and exception rules.

### 1. cargo — Rust crates

Add a crate name to `packages/cargo.txt`. `install/rust.sh` uses cargo-binstall
when a compatible release binary exists, otherwise compiles from source. On
Linux it prefers musl candidates to avoid a too-new glibc; a failing binary is
retried from a compatible source path. A macOS source build needs a normal
terminal because Sequoia's linker provenance rules can reject sandboxed builds.

### 2. npm — npm-specific tools

Add global CLIs to `packages/npm.txt`. nvm owns Node and its global prefix under
`$NVM_DIR`; do not set npm `prefix` or `globalconfig` in `~/.npmrc`.
`packages/npm-allow-scripts.txt` is the reviewed lifecycle-script allowlist.
Codex's package is npm-owned while [`install/codex.sh`](../../install/codex.sh)
owns configuration and its health check.

### 3. uv — Python libraries and CLI tools

`packages/python.txt` feeds the managed interactive `python`; `pip.txt` and
`pip-full.txt` declare isolated CLI environments. Put project dependencies in
the project `pyproject.toml` and lockfile instead:

```sh
uv init example && cd example
uv add numpy
uv run python -c 'import numpy; print(numpy.__version__)'
```

### 4. Homebrew — non-language-specific tools and C libraries

Use `packages/Brewfile` for formulae, casks, SDKs, and shared libraries.
Bootstrap owns `brew bundle`; use the manifest rather than `brew install` for a
durable addition. Linux uses its rootless managed prefix, while macOS uses the
standard Homebrew prefix.

### 5. VS Code / Cursor extensions

Add marketplace identifiers to `packages/vscode-extensions.txt` or
`packages/cursor-extensions.txt`, then run the matching installer. Settings
live under `home/dot_config/`; extensions and settings are separate state. See
[shell, terminal, and editor workflow](/workflows/shell-editor-terminal/).

### 6. Custom install script

When a tool needs its own lifecycle, add an idempotent `install/<name>.sh`,
source `_lib.sh`, wire a documented bootstrap gate, and add a meaningful probe.
Changing managed behavior also requires the feature entry described in
[documentation guidance](/contributing/documentation/).

## Local AI tools

| Tool | Owner | Operational boundary |
| --- | --- | --- |
| Ollama | Brewfile | installation does not start or query its server |
| mlx-lm / mlx-openai-server | `pip-full.txt` | Apple Silicon-oriented optional workflow |
| OpenCode | [`npm.txt`](../../packages/npm.txt) (`opencode-ai`) plus `install/opencode.sh` | npm owns the binary; the installer reconciles configuration |
| local-model tooling | `install/local-llm.sh` | validate model, license, and task separately |

Use [AI workbench](/usage/ai-workbench/) for an end-to-end workflow; executable
checks do not establish model quality or a running service.

## Research mathematics

| Tool family | Owner | Project proof/result boundary |
| --- | --- | --- |
| Lean | `install/lean.sh` / elan | project `lean-toolchain`, `lake build` |
| TeX and Quarto | installer plus Brewfile/TinyTeX | source and render command |
| Julia | Brewfile plus `install/julia.sh` | project `Pkg` environment |
| solvers and research CLIs | Brewfile, Cargo, or uv lists | project lockfiles and evidence |

Read [research tooling](/workflows/research-tooling/) for concrete project
commands and [math workflows](/usage/math/) for proof claims.

## Don't duplicate across layers

Search before adding, retain one owner, and remove a duplicate only through its
own manager after checking what currently resolves on PATH. This repository does
not use a universal package lock because each manager has different platform and
binary semantics.

## Why cargo over Homebrew for Rust tools

Cargo-binstall can use upstream release artifacts and falls back to source,
while keeping Rust CLIs in the Rust manifest. Prefer Homebrew where the package
is a library, system dependency, or macOS application rather than a standalone
Rust CLI.

## Why Homebrew for Linux

The managed Linux prefix provides current formulae without sudo and keeps them
inside the same runtime-root contract as other compiled state. It is not a
replacement for a project's pinned dependencies.

## Compiler toolchains

### Default: LLVM (Homebrew clang)

Managed CMake toolchain files are copied to the installer runtime root; in a
managed login shell that is `$_LOCAL_PLAT/cmake/toolchains`.
The [login profile](../../home/dot_profile.tmpl) selects `llvm-22.cmake` on
macOS when Homebrew LLVM is available; Linux prefers `gcc-13.cmake`. Each falls
back to the other if its preferred compiler is unavailable. An existing
`CMAKE_TOOLCHAIN_FILE` takes precedence. To choose LLVM explicitly:

```sh
ls "${_LOCAL_PLAT:?open a managed login shell first}/cmake/toolchains"
cmake -S . -B build -DCMAKE_TOOLCHAIN_FILE="$_LOCAL_PLAT/cmake/toolchains/llvm-22.cmake"
cmake --build build
```

### Switching toolchains

Set `CMAKE_TOOLCHAIN_FILE` per project or configure preset; do not rely on a
global default for a reproducible project build. The profile defaults to
`gcc-13.cmake` on Linux where available and `llvm-22.cmake` on macOS where
available; an already-set `CMAKE_TOOLCHAIN_FILE` wins.

### Disabling the toolchain

Clear the profile default for a command that needs its own compiler selection:

```sh
env -u CMAKE_TOOLCHAIN_FILE cmake -S . -B build-system
```

Or set the project file explicitly. Confirm `cmake -LAH` reports the expected
compiler.

### CUDA

CUDA is overlay-specific. Enable the overlay and select its documented CMake
toolchain only on a host with the required NVIDIA driver and toolkit.

### Compiler caching (ccache / sccache)

The profiles configure cache directories and size bounds under the local/scratch
layout. Caches improve rebuilds but are disposable derived state; a cache hit
does not validate compiler correctness.

### openssh from Homebrew

Use the managed OpenSSH only when its path precedes the system client, then
check `ssh -V` and `ssh -G host`. See [shell workflow](/workflows/shell-editor-terminal/)
for the managed SSH policy.

### Source files

The authoritative compiler inputs are [`install/cmake.sh`](../../install/cmake.sh),
[`home/dot_profile.tmpl`](../../home/dot_profile.tmpl), and the files in
[`install/cmake/toolchains/`](../../install/cmake/toolchains/).

## Updating all packages

```sh
~/dotfiles/bootstrap.sh update
~/dotfiles/bootstrap.sh upgrade  # accepts managed upgrades
```

Keep the degradation summary and use [updates](/usage/updates/) when a selected
tool fails to reconcile.
