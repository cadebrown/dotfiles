---
title: Compiler and research tooling
description: Managed language toolchains and the project-level boundaries for reproducible research work.
---

## Toolchains supply projects; projects supply proofs and results

The global setup provides launchers, compilers, debuggers, and selected command
line tools. A project still owns its lockfiles, dependencies, build directory,
and evidence. This distinction matters for Rust, CMake, Python, Lean, Julia,
TeX, and formal research: a working global executable does not validate a
specific project.

| Work | Global provision | Project-level action |
|---|---|---|
| Rust | rustup, Cargo tools, LLVM/CMake helpers | `cargo` manifest and test suite |
| Python | uv and a managed interactive interpreter | `uv init`, lockfile, `uv sync` |
| Lean | elan and a pinned default | project `lean-toolchain`, `lake build` |
| Julia | juliaup and isolated depot | `Pkg` environment per project |
| Typesetting | MacTeX or TinyTeX and Quarto | document source and render command |

Lean is installed under `ELAN_HOME` with a deliberate default pin; projects can
override it through `lean-toolchain`
([source](https://github.com/cadebrown/dotfiles/blob/main/install/lean.sh#L8)).
For a fresh Mathlib project, use the installer’s documented creation sequence:

```bash
lake +leanprover-community/mathlib4:lean-toolchain new example math
cd example
lake exe cache get
lake build
```

The cache is a speed aid, not a proof check. For formal-result expectations and
the full proof gate, follow [math workflows](/usage/math/) and
[scientific review](/usage/scientific-review/).

## CMake and Python examples

CMake toolchain files are copied into `$_LOCAL_PLAT/cmake/toolchains`, preserving
the repository versions rather than inventing a host path
([source](https://github.com/cadebrown/dotfiles/blob/main/install/cmake.sh#L10)).
The managed Python command has libraries from `packages/python.txt`; isolated
CLI tools are verified through their declared entrypoints
([source](https://github.com/cadebrown/dotfiles/blob/main/install/python.sh#L123)).

```bash
uv init experiment
cd experiment
uv add numpy
uv run python -c 'import numpy; print(numpy.__version__)'

ls "${_LOCAL_PLAT:?open a managed login shell first}/cmake/toolchains"
cmake -S . -B build -DCMAKE_TOOLCHAIN_FILE="$_LOCAL_PLAT/cmake/toolchains/llvm-22.cmake"
cmake --build build
```

The CMake filename must exist in the installed toolchain directory; list it
before selecting it. Compiler package versions and specific toolchain files may
change with repository revisions.
