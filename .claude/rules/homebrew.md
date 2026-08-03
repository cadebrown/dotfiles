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
| `patch-homebrew-mesa.sh` | pyyaml binary wheel (Cython SIGILL in superenv) + bindgen `--gcc-install-dir` (rusticl bindings can't find `<cassert>`) |
| `patch-homebrew-fastfetch.sh` | Disable WSL GPU detection — directx-headers shim fails at custom prefix |
| `patch-homebrew-fish.sh` | Disable sphinx man pages — headless nodes lack configured locale for Python/sphinx |
| `patch-homebrew-rpm.sh` | LUA_MATH_LIBRARY cmake fix — FindLua can't find libm; glibc is keg-only |
| `patch-homebrew-systemd.sh` | lxml binary wheel (Cython SIGILL in superenv) |
| `patch-homebrew-netpbm.sh` | GCC 15 C23 + incompatible-pointer fix |
| `patch-homebrew-optflags.sh` | `HOMEBREW_OPTFLAGS_PLAT` overrides Linux's hardcoded `-march=native` — glibc is the one formula every machine builds from source |

## Gotchas

- **Homebrew upgrades are off by default on Linux** (`DF_BREW_UPGRADE=0`) because glibc
  upgrades can break every installed binary. Use `bootstrap.sh upgrade` deliberately.
- **The glibc keg must track the formula, or new bottles stop loading.** Linux bottles
  carry the glibc floor of homebrew-core's builder image, and a builder move comes with
  a formula bump (Ubuntu 22.04 → 24.04, glibc 2.35 → 2.39, Jul 2026). glibc is installed
  by `linux-packages.sh`, not the Brewfile, so `brew bundle` never upgrades it — a keg
  left behind means every formula poured afterwards dies with ``version `GLIBC_2.38' not
  found``, naming the binary instead of the cause (Aug 2026: binutils, gcc@15, texlab,
  tinymist, cadical, harper, juliaup, all from one bundle run). `linux-packages.sh` now
  reconciles the keg before the bundle and scans kegs installed since the last run
  against what the keg provides. Three asymmetries to remember: an upgrade is safe
  (backward compatible — older kegs keep working); `brew reinstall glibc` is not
  possible at all, because it unlinks the keg before building and every brew binary,
  compiler included, loses its loader mid-flight; and a bare `brew upgrade glibc`
  continues into `upgrade_dependents` after the 3-minute keg build, source-rebuilding
  most of the Cellar for hours while holding formula locks that fail every other brew
  command. `brew_glibc_build` sets `HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK=1`; by hand,
  pass it too.
- **libclang picks a GCC with no libstdc++ headers.** Ubuntu 24.04 ships gcc-14's runtime
  bits while `/usr/include/c++/` stops at 13, and clang selects the highest-numbered dir
  under `/usr/lib/gcc/<triple>/` regardless — so anything driving libclang (bindgen, IDE
  tooling, standalone clang) dies on `fatal error: '<cassert>' file not found` for a
  perfectly ordinary C++ header. clang even warns that it *would* pick 13 in a future
  release and then doesn't. Fix is `--gcc-install-dir=<newest GCC that has
  /usr/include/c++/N>`; Homebrew's own GCC does **not** work as a substitute (its Cellar
  layout isn't what `--gcc-install-dir` expects). Currently hits mesa's rusticl frontend
  (`patch-homebrew-mesa.sh` patch 2). Reproduce in one line:
  `echo '#include <llvm/ADT/DenseMapInfo.h>' | clang++ -fsyntax-only -I "$(brew --prefix llvm)/include" -x c++ -`
- **An interrupted dependents rebuild leaves dangling sonames.** `brew upgrade <x>` moves
  a dependency and then rebuilds its dependents; kill it in between and the dependents
  keep an RPATH into `opt/<dep>/lib` where the old soname no longer exists — e.g. node
  25.8.1 after llhttp went 9.3.1 → 9.4.3: `node: error while loading shared libraries:
  libllhttp.so.9.3`. The old keg is usually still in the Cellar, so it looks installed.
  Fix is to rebuild the dependent (`brew upgrade node`), not to relink the old keg.
- **"A `brew install X` process has already locked …" means contention, not corruption.**
  Homebrew takes an flock per formula under `var/homebrew/locks`; a long-running brew
  elsewhere (a dependents rebuild, another terminal) makes every other install fail one
  formula at a time, and `brew bundle` surfaces it as a plain install failure. The locks
  are released when the holder exits — `flock -n <lockfile> true` tells you whether one
  is genuinely held. Deleting lock files is not the fix and races the holder;
  `linux-packages.sh` warns up front when it sees a live brew on the prefix.
- **Homebrew's Linux ENV ignores `HOMEBREW_OPTFLAGS` and always builds `-march=native`.**
  `determine_optflags` hardcodes `:native` for Intel and ARM alike, and `glibc.rb` feeds
  it straight into cflags — so the one library every binary in the prefix loads gets the
  build host's exact ISA baked in, and dies with SIGILL or `Fatal glibc error: CPU does
  not support x86-64-v4` on any older CPU sharing the home. `patch-homebrew-optflags.sh`
  makes `HOMEBREW_OPTFLAGS_PLAT` win; `brew_glibc_build` in `linux-packages.sh` sets it
  to the arch baseline. glibc picks its tuned memcpy/strlen through IFUNC at load time,
  so the baseline build keeps the fast paths. Kegs built before this patch existed stay
  native-tuned until the next formula bump rebuilds them.
- **A renamed or deprecated cask blocks the greedy sweep forever.** `brew upgrade
  --cask --greedy` reverts and re-fails every run with `It seems there is already an App
  at '/Applications/X.app'` when the artifact name changed under a self-updating cask, or
  when a stray binary/symlink from an earlier install sits where the cask wants to link.
  Both hit at once in Aug 2026: OpenAI folded the Codex desktop app into ChatGPT
  (`Codex.app` → `ChatGPT.app`, same `com.openai.codex` bundle ID, `codex-app` cask
  deprecated in favour of `chatgpt`), and a leftover `/opt/homebrew/bin/dnx` symlink
  blocked `dotnet-sdk`. Homebrew's auto-migration also leaves an orphan
  `Caskroom/<old-cask>/` behind, so `brew list --cask` shows a cask `brew info` calls
  "Not installed". Fix is `brew install --cask <name> --force` plus deleting the orphan
  directory and stray links; then update the Brewfile to the replacement name. Two
  `/Applications` bundles with the same `CFBundleIdentifier` means a rename, not two
  products.
- **`brew bundle` skips `auto_updates: true` casks** — Cursor, VS Code, iTerm2, etc.
  self-update in place, so `brew bundle install --upgrade` leaves their cask metadata
  stale. `homebrew.sh` runs `brew upgrade --cask --greedy` after the bundle when
  `DF_BREW_UPGRADE=1` to keep the records in sync with the running apps.
- **Python@3.14 formula is patched on Linux** — `install/patch-homebrew-python.sh` fixes uuid
  and test_datetime build issues. `HOMEBREW_NO_AUTO_UPDATE=1` stops brew refreshing the tap
  mid-command and reverting patches. Formulas depending on python@3.14 (vim, imagemagick,
  graphviz, ffmpeg, glances) now build successfully with these patches.
- **The Linux tap needs an EXPLICIT refresh — `NO_AUTO_UPDATE` freezes it forever.**
  With auto-update off and `HOMEBREW_NO_INSTALL_FROM_API=1` forcing every lookup through
  the local clone, homebrew-core stays pinned at its clone date no matter how often
  bootstrap runs (one machine: 4.5 months stale, 193/336 formulae behind; glab stuck at
  1.89 so `glab skills` didn't exist yet). `linux-packages.sh` therefore runs
  `git checkout -- Formula/` → `brew update` → patch block, in that order. Discarding
  first is the load-bearing part: `brew update` stashes dirty formulae and pops them
  afterwards, so an upstream edit to a patched line leaves the tap mid-conflict.
  Refreshing definitions is NOT upgrading — `DF_BREW_UPGRADE` still gates installed kegs.
- **Patch anchors rot; a stale anchor fails SILENTLY.** Every `patch-homebrew-*.sh`
  matches an exact source block and only `log_warn`s when it misses, so a formula that
  moved upstream leaves the build unpatched while the script still exits 0. The first
  real refresh broke two: `pkgconf` (2.5.1 → 3.0.4 rewrote `def install` for meson) and
  the `llvm_clang++` shim (Homebrew moved Linux super shims into `shims/linux/super/bin/`).
  Anchor on the narrowest stable line (`  def install`) with a separate idempotency
  marker rather than whole-block matching. After any tap refresh, verify with:
  `for f in install/patch-homebrew-*.sh; do bash "$f" 2>&1 | grep '^\[warn\]'; done`
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
