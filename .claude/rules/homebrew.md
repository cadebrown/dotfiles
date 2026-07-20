---
paths:
  - "packages/Brewfile"
  - "install/homebrew.sh"
  - "install/linux-packages.sh"
  - "install/patch-homebrew-*.sh"
---

# Homebrew — macOS and Linux custom prefix

Homebrew-on-Linux runs sudo-free at a user-owned prefix with its own glibc. That
custom prefix is the source of most build lore below.

## Formula patch catalog (Linux)

| Script | Fixes |
|---|---|
| `patch-homebrew-python.sh` | python@3.14: uuid detection + test_datetime PGO hang. Applied automatically during linux-packages.sh |
| `patch-homebrew-superenv.sh` | Linux superenv: linux-headers isystem, gnulib probe, glibc -L — three endemic build failures on custom prefix |
| `patch-homebrew-stdenv.sh` | Companion for rare stdenv builds (linux-headers isystem); stdenv builds skip the superenv shim |
| `patch-homebrew-ncurses.sh` | linux-headers CPPFLAGS — configure cascade failure from missing asm/ioctls.h + linux/limits.h |
| `patch-homebrew-m4.sh` | Bypass gnulib undeclared-builtin probe (GCC builtins make it silently succeed, configure aborts) |
| `patch-homebrew-pkgconf.sh` | Same gnulib probe as m4; pkgconf is a critical dep (openssh, podman, fish) |
| `patch-homebrew-cc65.sh` | linux-headers CPATH — Makefile uses $(CC) $(CFLAGS) without $(CPPFLAGS) |
| `patch-homebrew-mesa.sh` | pyyaml binary wheel (Cython SIGILL in superenv) |
| `patch-homebrew-fastfetch.sh` | Disable WSL GPU detection — directx-headers shim fails at custom prefix |
| `patch-homebrew-fish.sh` | Disable sphinx man pages — headless nodes lack configured locale for Python/sphinx |
| `patch-homebrew-rpm.sh` | LUA_MATH_LIBRARY cmake fix — FindLua can't find libm; glibc is keg-only |
| `patch-homebrew-systemd.sh` | lxml binary wheel (Cython SIGILL in superenv) |
| `patch-homebrew-netpbm.sh` | GCC 15 C23 + incompatible-pointer fix |

## Gotchas

- **Homebrew upgrades are off by default on Linux** (`DF_BREW_UPGRADE=0`) because glibc
  upgrades can break every installed binary. Use `bootstrap.sh upgrade` deliberately.
- **`brew bundle` skips `auto_updates: true` casks** — Cursor, VS Code, iTerm2, etc.
  self-update in place, so `brew bundle install --upgrade` leaves their cask metadata
  stale. `homebrew.sh` runs `brew upgrade --cask --greedy` after the bundle when
  `DF_BREW_UPGRADE=1` to keep the records in sync with the running apps.
- **Python@3.14 formula is patched on Linux** — `install/patch-homebrew-python.sh` fixes uuid
  and test_datetime build issues. `HOMEBREW_NO_AUTO_UPDATE=1` prevents Homebrew from
  overwriting patches. Formulas depending on python@3.14 (vim, imagemagick, graphviz, ffmpeg,
  glances) now build successfully with these patches.
- **Python dev headers come from Homebrew** — python@3.14 provides `Python.h` and
  `libpython3.14.so` at `$(brew --prefix)/opt/python@3.14/include/python3.14/`.
  CMake's `FindPython3` discovers these automatically via `brew shellenv` paths.
  There is no user-level venv — CLI tools use `uv tool install` (isolated venvs),
  and library work uses per-project `uv init` / `uv sync`.
- **Several formulas need linux-headers@6.8 CPPFLAGS on custom prefix** — Homebrew glibc's
  headers chain to kernel headers (`asm/ioctls.h`, `linux/limits.h`, `linux/errno.h`) that are
  NOT in the default include path. Any formula that doesn't declare `linux-headers@6.8` as a
  build dep will fail. Current patches: `ncurses` (all configure checks cascade-fail when
  `<stdio.h>` can't include `linux/limits.h`), `cc65` (Makefile doesn't propagate CPPFLAGS).
- **gcc formula is unversioned and tracks latest GCC** — as of GCC 15, implicit function
  declarations are errors by default, breaking configure scripts in m4 1.4.21 and ncurses 6.6.
  `linux-packages.sh` pre-installs gcc@13 and sets `HOMEBREW_CC=gcc-13` for all source builds.
  The m4 formula is additionally patched to bypass a gnulib probe that fails even with gcc-13.
- **GCC 15 is stricter: C23 default + new errors** — GCC 15 changed the default C
  standard from C17 to C23 (breaks `typedef unsigned char bool` in netpbm), and promotes
  `-Wincompatible-pointer-types` and `-Wimplicit-function-declaration` from warnings to
  errors. Per-formula patches (`netpbm`, etc.) add `-std=gnu17` and the relevant `-Wno-*`
  flags on Linux.
- **Cython packages SIGILL in superenv (pip --no-binary)** — Homebrew's `venv.pip_install`
  always passes `--no-binary=:all:`, forcing source builds. Packages that use Cython
  (lxml, pyyaml) fail with exit -4 (SIGILL) in the superenv context. Fix: install these
  packages with `--prefer-binary` instead. Currently patched: `systemd` (lxml), `mesa`
  (pyyaml). See the respective `patch-homebrew-*.sh` for details.
- **cmake's FindLua can't find glibc's libm on Linux** — glibc is keg-only, so its lib
  dir is not in cmake's `find_library()` search path. FindLua requires LUA_MATH_LIBRARY
  (libm) to link liblua. The `rpm` formula is patched to pass
  `-DLUA_MATH_LIBRARY=$(Formula["glibc"].opt_lib/"libm.so")` explicitly.
- **glibc -L missing from HOMEBREW_LIBRARY_PATHS (root cause unclear)** — despite glibc
  being a keg-only transitive dep of many packages, its opt_lib is not added to the
  linker's `-L` path. The superenv shim adds `-Wl,-rpath-link` for glibc but this is
  insufficient for versioned symbol resolution (GLIBC_2.33+ in libstdc++.so). Fixed by
  `patch-homebrew-superenv.sh` Patch 3: adds `-L/brew/opt/glibc/lib` alongside
  `-rpath-link` in the shim's `ldflags_linux`.
- **openssh is in Brewfile cross-platform** — on Linux, the system ssh may link against a
  different OpenSSL than Homebrew's, causing `git push` failures. Brew's openssh uses
  Homebrew's OpenSSL consistently.
- **Brew zsh needs its own locale data on Linux.** Homebrew's glibc has no `lib/locale/`
  archive, so `setlocale()` falls back to C/ASCII and `wcwidth()` counts bytes instead of
  display columns — ZLE completion leaves remnant characters. Fix: `linux-packages.sh`
  generates `en_US.UTF-8` into `$LOCAL_PLAT/locale/` via brew's `localedef`; shell profiles
  export `LOCPATH` pointing there. Test: `bash tests/test-locale.sh`.
- **Third-party taps must be trusted AND tapped before `brew bundle`** — two distinct
  Homebrew refusals: untrusted taps fail with "Refusing to load formula … from
  untrusted tap" (gated by `HOMEBREW_REQUIRE_TAP_TRUST`), and untapped taps fail with
  "No available formula … This command requires the tap … tap it explicitly" because
  brew no longer auto-taps from a fully-qualified `owner/repo/formula` name. The
  Brewfile's own `tap` directive is NOT reliable protection against the second one:
  `brew bundle` can hit formula resolution before the directive runs (seen July 2026
  with `rtk-ai/tap/rtk` while a same-named `rtk` keg from homebrew/core triggered the
  upgrade check — trusted, tap line present, still failed). `ensure_brewfile_taps()`
  in `_lib.sh` derives the tap list from the Brewfile (explicit `tap` lines +
  `owner/repo` prefix of three-part `brew`/`cask` refs) and runs `brew trust --tap` +
  `brew tap` for each before the bundle in both `homebrew.sh` and
  `linux-packages.sh`. The Brewfile stays the single source of truth — adding a
  tapped formula is enough; trust and tap follow.
- **rtk: install from the official tap, not homebrew-core** — homebrew-core lags badly
  (shipped 0.29 when upstream stable was 0.42+; that version window broke every
  PreToolUse hook). `packages/Brewfile` uses `brew "rtk-ai/tap/rtk"` (prebuilt, all 4
  platforms, Linux x86_64 is musl = no glibc dependency). Full rtk hook wiring:
  see `.claude/rules/agent-tooling.md`.
- **docker-completion collides with the docker formula** — the `docker` formula now ships
  its own shell completions, but older machines carry `docker-completion` as a leftover
  dependency. Both want `etc/.../completions/docker`, so `brew bundle` aborts linking
  `docker` ("Could not symlink … belonging to docker-completion"). Upstream deprecated
  docker-completion (disables 2027-05-31, replacement `docker`), so `homebrew.sh` removes
  the orphan keg before the bundle. It's not in the Brewfile — fresh machines never hit
  this. Manual fix if needed: `brew uninstall --ignore-dependencies docker-completion`.
- **qmd needs Homebrew sqlite on macOS** — the system libsqlite3 blocks loadable
  extensions, killing qmd's vector index. `brew "sqlite"` is in the Brewfile.
