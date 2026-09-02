# Troubleshooting

Quick reference for when things go wrong. Check here before digging into scripts.

---

## Tool not found after bootstrap

```sh
echo "$_PLAT" "$_LOCAL_PLAT"          # capability + install root
ls "$_LOCAL_PLAT/bin/"                # chezmoi, uv, claude should be here
ls "$_LOCAL_PLAT/cargo/bin/"          # fd, sd, zoxide, etc.
which fd                              # should point under $_LOCAL_PLAT
```

`$_LOCAL_PLAT` is `$HOME/.local` by default (flat layout) or `$HOME/.local/$_PLAT` when [PLAT isolation](../setup/plat.md) is enabled. If `$_PLAT` or `$_LOCAL_PLAT` is empty, `.zprofile` wasn't sourced. Open a new login shell (`zsh -l`) or source it:

```sh
source ~/.zprofile
```

---

## Codex install fails with `marketplace unavailable: openai-bundled`

Symptom: `install/codex.sh` reports that `openai-bundled` is unavailable even
though `codex login status` says the user is authenticated.

Root cause: `openai-bundled` is a local marketplace owned and registered by
Codex Desktop. Authentication does not expose it to the standalone CLI, whose
built-in marketplace is `openai-curated`. The CLI-managed
`packages/codex-plugins.txt` must therefore contain only plugins from
marketplaces reported by `codex plugin marketplace list`.

Confirm:

```sh
codex login status
codex plugin marketplace list --json
```

**Fix:** update the dotfiles checkout and rerun `bootstrap.sh`. Bundled plugins
remain owned by Codex Desktop; do not register the app's internal plugin path
manually because that can conflict with the app's marketplace reconciliation.

---

## Codex plugin fails: `plugin X was not found in marketplace openai-curated`

Symptom: `install/codex.sh` (Codex Plugins step) logs a `[warn]` like
`Error: plugin openai-developers was not found in marketplace openai-curated`,
and on an older checkout the healthcheck then died with
`Missing or disabled Codex plugin: <plugin>@openai-curated`.

Root cause: `openai-curated` is a snapshot **bundled with codex-cli**, and codex
is unpinned (`packages/npm.txt`), so its curated plugin set changes across
versions. A selector in `packages/codex-plugins.txt` that a newer codex-cli no
longer ships can't install — the entry is stale. (`openai-developers` and
`build-web-data-visualization` were temporarily absent in codex-cli 0.144.6 and
returned in 0.147.0.)

Confirm — list what the installed codex actually offers:

```sh
codex plugin list --json | jq -r '.available[].pluginId'
```

**Fix:** prune (or re-point) the missing selectors in
`packages/codex-plugins.txt` to match that list, then rerun `bootstrap.sh`. The
healthcheck now **warns** (`dropped upstream: … — prune packages/codex-plugins.txt`)
instead of failing when a declared plugin is gone from the snapshot, so this no
longer blocks bootstrap — the warning is your cue to prune. A plugin still
offered by the snapshot but not installed/enabled stays a hard failure.

The `WARNING: failed to clean up stale arg0 temp dirs: Directory not empty` line
from codex-cli is unrelated NFS noise (`.nfs*` files in its temp dir) — harmless.

---

## Claude plugin fails: `Plugin "X" not found in any configured marketplace`

Symptom: `install/claude.sh` logs `[warn]  fail  <plugin>: … ✘ Failed to
install plugin "<plugin>": Plugin "<plugin>" not found in any configured
marketplace`, but the plugin visibly exists in the marketplace's GitHub repo.

Root cause: plugin installs resolve against the **local marketplace clones**
under `~/.claude/plugins/marketplaces/`, and with `DISABLE_AUTOUPDATER=1` those
never refresh themselves. A plugin added upstream after the clone date is
invisible (the `claude-plugins-official` clone once sat 4 months stale while
`math-olympiad` existed upstream). `claude.sh` used to refresh catalogs only in
upgrade mode — and even that call was broken, passing a nonexistent `--all` flag
whose error was silenced by `>/dev/null || true`, so no mode ever refreshed.
It now refreshes (with the correct no-name form) in every mode.

Confirm — compare the clone date against upstream:

```sh
git -C ~/.claude/plugins/marketplaces/<marketplace> log -1 --format=%cd
jq -r '.plugins[].name' \
  ~/.claude/plugins/marketplaces/<marketplace>/.claude-plugin/marketplace.json | grep <plugin>
```

**Fix:** update the checkout and rerun `bootstrap.sh` (or `install/claude.sh`).
Manual one-off:

```sh
claude plugin marketplace update <marketplace>
claude plugin install <plugin>@<marketplace>
```

---

## The same VS Code / Cursor extensions report `fail` on every upgrade run

Symptom: `bootstrap.sh upgrade` logs `fail <ext-id>` for a fixed set of
extensions, run after run — yet the extensions are installed and working in the
editor. Install mode never reports them.

Root cause: upgrade mode used to reinstall each declared extension with
`--install-extension <id> --force`, which re-resolves the ID against the
editor's marketplace. Two categories can never satisfy that:

- **Extensions the editor now bundles.** VS Code ships `github.copilot-chat`
  built in (0.59.0); the marketplace copy is older (0.48.1) and the CLI refuses
  the downgrade outright: `is a built-in extension … and cannot be downgraded`.
- **IDs the marketplace doesn't carry.** Cursor resolves against Open VSX, so
  Microsoft-proprietary IDs fail with `Extension '<id>' not found` even when the
  extension is installed — Cursor imported it from VS Code on first run, a path
  the CLI can't reproduce. `nvidia.nsight-vscode-edition` is refused explicitly:
  `not available in Cursor for the Mac Silicon`.

Confirm — run the install by hand to reproduce the marketplace error reported
by the now-failing bootstrap step:

```sh
code --install-extension <id> --force      # or: cursor --install-extension …
```

**Fix:** update the checkout and rerun. `vscode.sh` / `cursor.sh` now upgrade
with a single `--update-extensions` bulk pass instead of per-extension
`--force`, which only touches what the editor can actually resolve. Drop
bundled extensions from `packages/vscode-extensions.txt`, and keep IDs Open VSX
can't serve out of `packages/cursor-extensions.txt` (that file's header lists
the known-unavailable set and the Anysphere forks to use instead).

---

## Cursor reports `ENOENT` for `User/settings.json` and ignores user settings

Symptom: Cursor logs or displays an error such as:

```text
ENOENT: no such file or directory, open '.../Cursor/User/settings.json'
```

The native file is still a symlink, but its managed target is missing or empty:

```sh
ls -l "$HOME/Library/Application Support/Cursor/User/settings.json"
jq -e 'type == "object"' ~/.config/cursor/settings.json
git diff -- home/dot_config/cursor/settings.json
```

Root cause: Cursor writes the symlinked settings file non-atomically. The Cursor
agent hook could run after the file was truncated but before the replacement
contents arrived, and `chezmoi add` then copied the empty file into the repo.
The hook's `jq` cleanup also accepted empty input as success, preserving the
damage. A later failed rewrite can leave the native symlink dangling.

**Fix:** update the checkout. The hook now accepts only a complete settings
object or keybindings array, then validates the chezmoi source after import and
restores its previous contents if the file changed during the copy. To recover
an already-empty source after confirming the diff contains no wanted edits:

```sh
git restore --source=HEAD -- home/dot_config/cursor/settings.json
chezmoi apply ~/.config/cursor/settings.json ~/.cursor/hooks/sync-dotfiles-cursor.sh
```

If an open window still shows defaults after the native symlink resolves, run
`Developer: Reload Window` from Cursor's command palette.

---

## Brew bundle fails: `No available formula … This command requires the tap`

Symptom: `brew bundle` errors with `No available formula with the name
"owner/tap/formula". This command requires the tap owner/tap. If you trust this
tap, tap it explicitly and then try again: brew tap owner/tap` — even though the
Brewfile has the `tap "owner/tap"` line and the tap is already trusted.

Root cause: two separate Homebrew gates protect third-party taps — trust
(`HOMEBREW_REQUIRE_TAP_TRUST`) and the tap actually being cloned. Homebrew no
longer auto-taps from a fully-qualified formula name, and `brew bundle` can hit
formula resolution **before** executing the Brewfile's own `tap` directive — in
particular the upgrade check for a formula already installed under the same name
from homebrew/core (seen with `rtk`: core keg installed, `rtk-ai/tap/rtk` in the
Brewfile, tap trusted but never tapped → resolution error every run).

Confirm:

```sh
brew tap                      # tap missing from the list
jq . ~/.homebrew/trust.json   # …while already trusted here
```

**Fix:** update the checkout and rerun — `ensure_brewfile_taps()` (`_lib.sh`)
now trusts **and taps** every tap referenced by the Brewfile before the bundle.
Manual one-off: `brew tap owner/tap`, then rerun `install/homebrew.sh`.

---

## Brew bundle reports `Upgrading X has failed!` after installing X

Symptom: `bootstrap.sh upgrade` pours and links a formula successfully, then
reports `Upgrading <formula> has failed!`. Nearby errors name a vanished file in
`~/.cache/Homebrew/downloads/`, such as `No such file or directory @
dir_s_rmdir - ...bottle_manifest.json`. Several unrelated formulae can fail this
way in one run.

Root cause: Homebrew Bundle defaults to as many as four package workers. Those
workers launch separate `brew install` or `brew upgrade` processes that share
one download cache and run install cleanup against it. One worker can remove a
cache entry after another has inspected it, turning successful installs into
nonzero exits. Homebrew tracks the broader parallel-worker race as
[Homebrew/brew#23328](https://github.com/Homebrew/brew/issues/23328); the
[Homebrew manpage](https://docs.brew.sh/Manpage) documents the `auto` job
default and the sequential override.

Confirm after the original bootstrap process has exited:

```sh
formula=tree
brew list --versions "$formula"
brew outdated --formula "$formula"
brew linkage --test "$formula"
```

If the new version is listed, `brew outdated` prints nothing, and linkage
passes, the install succeeded and only its cleanup path failed.

Graphviz has a second version of this symptom. Netpbm fetches its source and
manual from Subversion. Bundle can queue those SVN fetches before it finishes
installing Graphviz's Subversion dependency, record `You must: brew install
svn`, then install Subversion, retry both checkouts, and successfully build
Netpbm and Graphviz. The early fetch result still makes Bundle print `Upgrading
graphviz has failed!` after the successful install.

**Fix:** update the checkout and rerun `bootstrap.sh upgrade`. The shared
installer environment now disables Bundle package jobs; downloads and each
source build can still run concurrently, but package installs and cleanup are
serialized. On Linux it also installs a working Subversion before a Brewfile
containing Graphviz, then runs `brew bundle check` after any nonzero Bundle exit.
If that check passes, it retries Bundle once and reports recovery only when the
clean retry exits zero. Manual one-off:

```sh
brew bundle install --jobs=1 --file="$HOME/dotfiles/packages/Brewfile"
```

Do not start the retry while the first bootstrap is still running.

---

## Brew cleanup fails with `Device or resource busy .../.nfs...`

Symptom: an upgrade prints a formula's beer-mug success line, then fails while
cleanup removes an unrelated old keg:

```text
Error: Device or resource busy @ apply2files - .../Cellar/expat/<version>/lib/.nfs...
```

Root cause: NFS renames an unlinked-but-open file to `.nfs*` and keeps it until
the last process closes it. Any Homebrew executable or shared library can be a
holder: this first appeared with the Bash running bootstrap, then with dozens of
long-lived `dbus-daemon` processes mapping an old `libexpat.so`. Homebrew runs
formula cleanup after installs and, every 30 days, a full cleanup. That cleanup
exception changes the command's exit status after the package succeeds, so
Bundle misleadingly reports `Upgrading <formula> has failed!` for each later
package too.

Confirm which processes still hold the file:

```sh
lsof /path/from/the/error/.nfs...
```

**Fix:** wait for the original bootstrap to exit, update the checkout, and retry.
On an NFS Homebrew prefix, `linux-packages.sh` sets the documented
[`HOMEBREW_NO_INSTALL_CLEANUP`](https://docs.brew.sh/Manpage#environment)
switch for the run. Installs and upgrades still happen, but cleanup cannot turn
their success into failure. The switch does not disable an explicit cleanup;
after every process shown by `lsof` has exited, reclaim the retired keg with:

```sh
brew cleanup expat
```

Old kegs consume some disk until that maintenance succeeds. Do not delete the
`.nfs*` file manually or terminate unrelated holders just to make cleanup pass.

---

## Ruby upgrade writes outside its new keg during `make install`

Symptom: upgrading `vim`, `ccache`, or another Ruby dependent builds Ruby and
then fails under the global Homebrew Ruby directory:

```text
Dir.mkdir: Permission denied @ dir_s_mkdir - .../brew/lib/ruby
```

The same contamination can later surface as `Errno::ENOENT` under
`.../brew/lib/ruby/gems/...` during RubyGems setup.

Root cause: the formula adds the versioned `ruby@X.Y` path as a compatibility
fallback. `runruby` supplies the build directory through `LD_LIBRARY_PATH`, but
Homebrew's GCC emits `DT_RPATH`, which the dynamic loader searches first. During
`make install`, the new Cellar lib directory is not populated yet, so the build
executable falls through to the previous keg's `libruby`. The source `RUBYLIB`
also lacks RubyGems' optional `defaults/operating_system.rb`; its `require` can
therefore find the previous keg's file. Those old Homebrew defaults redirect
`Gem.default_dir` and `Gem.ruby` outside the new keg. The Linux filesystem
sandbox correctly rejects that write; the prefix permissions are not broken.

**Fix:** `install/patch-homebrew-ruby.sh` patches the local formula before Brew
Bundle runs. It enables new ELF dtags so `DT_RUNPATH` yields to the build-tree
library path, retains the new keg before the versioned fallback after install,
and adds a build-local empty RubyGems packager-default file so the previous
keg's override cannot leak in. The formula replaces that empty file with the
current Homebrew configuration after installation.

This formula-local `DT_RUNPATH` is a deliberate exception to the prefix's usual
`DT_RPATH` policy: the build runner must let its temporary `LD_LIBRARY_PATH`
select the new build-tree `libruby`.

Do not `chmod` the prefix or disable Homebrew's Linux sandbox. Wait for any
active Homebrew process to exit, then rerun `~/dotfiles/bootstrap.sh upgrade` so
the formula refresh and patch happen in the intended order.

---

## apache-serf cannot find `asm/socket.h`

Symptom: a source build of `apache-serf` invokes a brewed GCC directly and
fails through Homebrew's glibc headers:

```text
glibc/include/bits/socket.h: fatal error: asm/socket.h: No such file or directory
```

Root cause: Homebrew's standard build environment already puts the installed
`linux-headers@6.8` include directory in `CPATH`. Serf's `SConstruct` creates a
new SCons child environment that does not inherit that variable, so the direct
GCC command loses the kernel-header path. Adding the path to superenv or CPATH
again does not cross this second environment boundary.

**Fix:** `install/patch-homebrew-apache-serf.sh` adds a direct Linux dependency
on `linux-headers@6.8` and passes its stable `opt_include` path through Serf's
supported `CPPFLAGS` SCons variable. The patch fails closed if the formula
structure changes instead of silently starting another known-broken source
build.

A trailing Clang warning about which GCC installation it may prefer is separate
from this GCC compile failure. Wait for any active Homebrew process to exit,
then rerun `~/dotfiles/bootstrap.sh upgrade` so the refreshed formula is patched
before Bundle starts.

---

## Gecode patch reports that its configure target moved

Symptom: bootstrap records this degradation even though MiniZinc may still
finish installing:

```text
gecode configure patch target not found — formula may have changed
```

Root cause: Homebrew changed the Gecode formula from Autotools flags such as
`--enable-qt` to CMake settings such as `GECODE_ENABLE_GIST`. The dependency
guard could still apply while the old configure anchor no longer existed,
leaving a partial formula edit and a misleading successful patch status.

**Fix:** `install/patch-homebrew-gecode.sh` recognizes both formula shapes,
forbids the upstream bottle on Linux, and sets Gist and Qt off while retaining
the macOS bottle and GUI. The bottle gate matters because build flags cannot
change a bottle that already contains `libgecodegist` and Qt dependencies. The
installer rebuilds an existing Gist-bearing keg from source and requires both
`brew linkage --test gecode` and the absence of `libgecodegist.so`; a moved
anchor stops source builds instead of leaving a partial formula edit.

---

## Clang cannot load `libz3` during an in-progress upgrade

Symptom: a formula failure ends with a separate loader error such as:

```text
clang: error while loading shared libraries: libz3.so.4.15: cannot open shared object file
```

Root cause: Bundle upgraded Z3 before unversioned LLVM. The installed LLVM still
needs Z3's previous major SONAME, while `opt/z3` already selects the new keg.
This is independent of a formula that was compiled with GCC and usually repairs
itself when the same Bundle run reaches LLVM.

The Linux installer reconciles this pair before Bundle: it upgrades an outdated
LLVM in upgrade mode, reinstalls a current keg whose linkage is broken, and
checks both `brew linkage` and the unversioned Clang executable again after
Bundle.

Do not point the old SONAME at the new major library or repoint `opt/z3` during
the active transaction. After all Homebrew processes exit, rerun
`~/dotfiles/bootstrap.sh upgrade`. For a manual check, run:

```sh
"$(brew --prefix)/bin/clang" --version
```

If it still reports the old Z3 SONAME, upgrade an outdated LLVM or reinstall a
current but broken keg, then verify its linkage:

```sh
if [[ -n "$(brew outdated --formula llvm)" ]]; then
    brew upgrade llvm
else
    brew reinstall llvm
fi
brew linkage --test llvm
"$(brew --prefix)/bin/clang" --version
```

---

## OpenSSH upgrade fails with `inreplace failed ... sshd_config`

Symptom: OpenSSH finishes `make install`, then Homebrew aborts while replacing
its Cellar prefix in the persistent configuration:

```text
Error: inreplace failed
.../brew/etc/ssh/sshd_config:
  expected replacement of ".../Cellar/openssh/<version>" with ".../opt/openssh"
```

Root cause: Homebrew preserves files under `etc` across upgrades. After the
first install, `sshd_config` already contains `opt/openssh`; a later install has
no Cellar path left to replace, but the formula treats that valid no-op as an
error.

**Fix:** `install/patch-homebrew-openssh.sh` guards the replacement with a
content check. It leaves an already-normalized configuration untouched, while
the formula's test still rejects any Cellar path that remains.

---

## Brew has the current keg but still uses an older version

Symptom: `brew list --versions glib` or another formula lists the current
version, and `brew outdated` prints nothing, but `opt/<formula>`, `bin/<tool>`,
or `pkg-config` still resolves an older keg. This can follow an interrupted or
failed upgrade.

Inspect both the selected keg and the current keg's receipt:

```sh
formula=glib
prefix=$(brew --prefix)
brew info --json=v2 "$formula" | jq '.formulae[0] | {linked_keg, installed}'
readlink -f "$prefix/opt/$formula"
ls "$prefix/Cellar/$formula"/*/INSTALL_RECEIPT.json
```

If the current keg has an install receipt, its direct executable works, and
`brew linkage --test "$formula"` passes, preview and repair only the links:

```sh
brew link --overwrite --dry-run "$formula"
brew link --overwrite "$formula"
```

If its receipt is absent or `brew info --json=v2` reports a null install time,
the keg is incomplete. Do not force-link it; rebuild it:

```sh
HOMEBREW_NO_INSTALL_CLEANUP=1 brew reinstall --build-from-source "$formula"
```

This run found both forms: Fish 4.8.1 was complete but its `bin/fish` symlink
still named 4.5.0, while GLib 2.88.3 lacked a receipt and had to be rebuilt.

---

## Brew Bundle reports a circular `libtiff, webp` dependency

Symptom: `brew bundle check` refuses to sort its graph even though both current
formulae are installed:

```text
Formulae dependency graph sorting found a circular dependency:
  libtiff, webp
```

Root cause: the installed WebP receipt can retain an old `libtiff` dependency,
while the current libtiff formula depends on WebP. Generated keg receipts are
installation records; do not hand-edit them. Reinstalling WebP regenerates its
receipt from the current one-way dependency graph:

```sh
HOMEBREW_NO_INSTALL_CLEANUP=1 brew reinstall --build-from-source webp
brew bundle check --file="$HOME/dotfiles/packages/Brewfile"
```

---

## Rust fails after Homebrew says its packages are satisfied

Symptom: `install/rust.sh` reports `Homebrew rustup not found` even though
`brew list rustup` and `brew --prefix rustup` succeed.

Root cause: Homebrew's keg-only `rustup` formula removed `rustup-init`. Older
bootstrap runs left `~/.local/cargo/bin/rustup` pointing at the removed
`/opt/homebrew/bin/rustup-init`, and `rust.sh` incorrectly required that removed
binary before accepting the installed formula.

Confirm:

```sh
brew info rustup | grep -E 'keg-only|no longer provides'
readlink ~/.local/cargo/bin/rustup
ls "$(brew --prefix rustup)/bin/rustup"
```

**Fix:** update the checkout and run `bash ~/dotfiles/install/rust.sh`. The
installer now links Homebrew's individual keg wrappers into the managed Cargo
bin directory and initializes stable with `rustup toolchain install`; it does
not depend on `rustup-init`.

---

## Cask upgrade fails: `It seems there is already an App at '/Applications/X.app'`

Symptom: `bootstrap.sh upgrade` reports `Some greedy cask upgrades failed`, and
`brew upgrade --cask --greedy` ends with `Error: Problems with multiple casks:`
naming an app (or a binary, e.g. `already a Binary at '/opt/homebrew/bin/dnx'`).
Homebrew reverts the upgrade, so the same failure repeats every run.

Root cause: Homebrew refuses to overwrite an artifact it doesn't have a receipt
for. Two ways an auto-updating cask gets there:

- **Upstream renames the app bundle.** The cask's `app` stanza changes name, the
  self-updater has already written the new bundle, and brew's receipt still
  points at the old one — so brew tries to *create* a file that exists. This is
  what `codex-app` did: OpenAI folded the Codex desktop app into ChatGPT and
  renamed `Codex.app` → `ChatGPT.app` (same `com.openai.codex` bundle ID). The
  `codex-app` cask is deprecated with `chatgpt` as its replacement, and the
  auto-migration leaves an orphan `Caskroom/codex-app/` directory behind, so
  `brew list --cask` still shows it while `brew info` says "Not installed".
- **A leftover symlink from a previous install.** `dnx` pointing into
  `/usr/local/share/dotnet/` blocked every `dotnet-sdk` upgrade.

Confirm:

```sh
brew outdated --cask --greedy               # which casks are stuck
ls /opt/homebrew/Caskroom/<cask>            # receipt version vs the running app
/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" /Applications/X.app
```

Two apps printing the *same* bundle ID means one is a stale copy under the old
name, not a second product.

**Fix:** `brew install --cask <name> --force` — it overwrites the unmanaged
artifact, removes the old-named bundle, and re-establishes the receipt at the
current version. Delete any orphan `Caskroom/<old-cask>/` directory (it holds
only a symlink and metadata; `rm -rf` on it does not follow the symlink) and
remove stray binaries before retrying. For a renamed cask, also update
`packages/Brewfile` to the replacement name.

---

## A Homebrew package is months behind upstream (Linux)

Symptom: a formula installs at a version far older than upstream stable, and
re-running bootstrap never moves it. Seen with `glab`, which stuck at 1.89.0
while upstream was 1.109.0 — old enough that `glab skills install --global`
failed with `Unknown command "skills"`, so `install/skills-sync.sh` reported
`fail glab` / `missing declared skill: glab` on every run.

Root cause: `install/linux-packages.sh` sets `HOMEBREW_NO_AUTO_UPDATE=1` (so an
implicit refresh can't revert the in-place formula patches) and, until now, never
ran an explicit `brew update`. The homebrew-core clone therefore froze at
whatever date it was first cloned, and `HOMEBREW_NO_INSTALL_FROM_API=1` forces
every lookup through that frozen clone. One machine sat 4.5 months stale with
193 of 336 installed formulae behind upstream.

Confirm:

```sh
git -C "$(brew --repo homebrew/core)" log -1 --format=%ci   # tap's age
brew info <formula> | head -1                               # frozen version
```

**Fix:** rerun `install/linux-packages.sh` — it now discards the formula patches,
runs `brew update`, and re-applies each patch against the fresh formula. This
refreshes *definitions* only; `DF_BREW_UPGRADE` still governs whether installed
kegs move, so a plain run leaves working binaries alone.

Upgrade a single package without touching the tap:

```sh
env -u HOMEBREW_NO_INSTALL_FROM_API -u HOMEBREW_NO_AUTO_UPDATE brew upgrade <formula>
```

Expect patch anchors to rot across a long refresh — see the patch-anchor gotcha
in `.claude/rules/homebrew.md`.

---

## `GLIBC_x.y not found` from a Homebrew binary (Linux)

Symptom: a brew-installed binary refuses to start, blaming Homebrew's own libc:

```
.../opt/binutils/bin/as: .../opt/glibc/lib/libc.so.6: version `GLIBC_2.38' not found
```

Only *some* binaries are affected — the recently installed ones — and the error
names whichever binary you happened to run, so it reads like a problem with that
package. `ldd` disagrees and shows the system libc, because it resolves through
the system loader while the binary itself runs under `brew/lib/ld.so`.

Root cause: the glibc keg is older than the bottles. Homebrew's Linux bottles
carry the glibc floor of the CI image that built them, and when homebrew-core
moves that image it bumps the `glibc` formula in the same breath (Ubuntu 22.04 →
24.04, glibc 2.35 → 2.39, July 2026). Nothing upgrades an installed glibc keg on
its own — it isn't in the Brewfile — so every formula poured after the move lands
with a floor the keg can't meet. Aug 2026: seven kegs (`binutils`, `gcc@15`,
`texlab`, `tinymist`, `cadical`, `harper`, `juliaup`) broke at once, all poured
by one `brew bundle` run days after the builder moved.

Confirm:

```sh
brew outdated --formula --verbose glibc      # glibc (2.35_2) < 2.39_1
ldd --version | head -1                      # host glibc
jq -r '.built_on.os_version' "$(brew --cellar)"/<formula>/*/INSTALL_RECEIPT.json
```

**Fix:** rerun `install/linux-packages.sh`. It reconciles the keg against the
formula before the bundle, and checks every keg installed since the last run
against what the keg provides. The broken kegs need no reinstall — they were
fine all along; only the loader under them was too old.

Upgrading by hand needs one guard:

```sh
HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK=1 brew upgrade glibc
```

A bare `brew upgrade glibc` moves the keg in ~3 minutes and then spends hours
source-rebuilding every dependent whose linkage it considers stale, holding a
formula lock the whole time so every other brew command fails with "has already
locked". The rebuild buys nothing: glibc is backward compatible, and the kegs
built against the old one keep running.

Homebrew refuses to build a glibc newer than the host's, so a host older than the
formula can't be fixed this way. That combination has no in-place remedy: either
the host glibc moves, or the keg goes and every formula is reinstalled against
the host loader. The script warns rather than pretending.

Related: `brew reinstall glibc` fails with `Errno::ENOENT ... gcc-13`. Reinstall
unlinks the keg before building, which leaves `brew/lib/ld.so` dangling, and no
brew binary — including the compiler — can start. Upgrades build the new keg
first and are safe; a keg can only be rebuilt at the same version by rebuilding
the prefix.

---

## `NODE_MODULE_VERSION` mismatch / `ERR_DLOPEN_FAILED` from an npm tool

Symptom: an npm-installed CLI dies loading a native addon, usually mid-script:

```
Error: The module '.../node_modules/better-sqlite3/build/Release/better_sqlite3.node'
was compiled against a different Node.js version using NODE_MODULE_VERSION 141.
This version of Node.js requires NODE_MODULE_VERSION 147.
```

Root cause: the package was installed under one Node major and is being run by
another. Native addons are ABI-locked per major, and the bin shebang is
`#!/usr/bin/env node` — so whichever Node is first on PATH wins. Two ways in:

- **Two Node layers.** Globals installed under Homebrew's node keg *and* under nvm.
  List them: `npm ls -g --depth=0 --prefix "$(brew --prefix)"` should show only `npm`.
  Remove strays with `npm uninstall -g --prefix "$(brew --prefix)" <pkg>` — nvm is the
  layer that owns npm globals.
- **PATH order.** `brew shellenv` puts brew's bin ahead of nvm's; `install/_lib.sh`
  restores nvm-first for install scripts, but an ad-hoc shell can still invert it.

It hides well: only subcommands that actually load the addon fail. `qmd collection
show` works while `qmd update` aborts, which reads like a broken index rather than a
broken interpreter.

**Fix:** run it under the Node that installed it (`command -v node` should be under
`$NVM_DIR`), or reinstall the package under the current Node (`npm install -g <pkg>`).

---

## nvm rejects `prefix` or `globalconfig` in `~/.npmrc`

Symptom: `install/node.sh` stops during `nvm use` or after installing a Node
version:

```text
Your user’s .npmrc file (${HOME}/.npmrc)
has a `globalconfig` and/or a `prefix` setting, which are incompatible with nvm.
```

Root cause: a legacy `prefix=~/.npm` sends every global package to one shared
tree. nvm instead gives each Node version its own global prefix under `$NVM_DIR`;
mixing the two makes package binaries and native addons run under the wrong Node
ABI. `globalconfig` can redirect npm to another file containing the same
conflict.

**Fix:** rerun `install/node.sh`. Before loading nvm it atomically removes an
active `prefix` from the user `.npmrc`, preserves the remaining npm policy, and
keeps the file private. If `.npmrc` sets `globalconfig`, the installer leaves it
unchanged and stops: copy any needed registry/auth/policy from the referenced
file into `~/.npmrc`, remove the `globalconfig` line, then rerun. nvm owns the
Node/npm prefix; `packages/npm.txt` owns the global CLI set. Do not export
`NPM_CONFIG_PREFIX` or add another npm `prefix` for this setup.

Verify the selected runtime and global tree agree:

```sh
source "$NVM_DIR/nvm.sh"
nvm use default --silent
command -v node
npm prefix -g
dirname "$(dirname "$(nvm which default)")"
```

The last two paths must match.

---

## A Homebrew binary can't find `libX.so.N` after an upgrade

Symptom: one program stops starting, naming a library version that used to exist:

```
node: error while loading shared libraries: libllhttp.so.9.3: cannot open shared object file
```

Root cause: `brew upgrade <formula>` doesn't stop at the formula — it then rebuilds every
dependent whose linkage the upgrade invalidated. Interrupt it in between (Ctrl-C, a
killed terminal, a timeout) and you're left with the new dependency and the old
dependent: the dependent's RPATH points at `opt/<dep>/lib`, which now holds only the new
soname. Both kegs are usually still in the Cellar, so `brew list` looks healthy.

Confirm:

```sh
brew list --versions <dep>                      # e.g. llhttp 9.3.1 9.4.3
readelf -d "$(brew --prefix)/opt/<formula>/bin/<prog>" | grep RPATH
```

**Fix:** rebuild the dependent — `brew upgrade <formula>` (or `reinstall`). Don't relink
the old dependency keg; that just moves the breakage to whatever wanted the new one.

Prevention: pass `HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK=1` when you upgrade something
with many dependents, so nothing half-finishes in the first place.

---

## `nvm` or `node` not available in a script

`nvm.sh` is lazy-loaded in interactive shells only. Login profiles put the bin
directory selected by nvm's `default` alias on PATH. A standalone
non-interactive script should activate that same alias explicitly:

```sh
source "$NVM_DIR/nvm.sh"
nvm use default --silent
```

---

## chezmoi keeps prompting for name/email

The cached values live in `~/.config/chezmoi/chezmoi.toml`. To reset:

```sh
chezmoi init --data=false
```

To pre-seed without prompting:

```sh
DF_NAME="Your Name" DF_EMAIL="you@example.com" chezmoi init
```

---

## chezmoi diff shows unexpected changes

Another program modified a managed file. Common culprits:

- **`uv`** auto-adds source lines to `.zshrc`/`.bashrc` for its `bin/env` files
- **Claude Code** updates `~/.claude/settings.json` when plugins are installed
- **Other tools** may modify shell configs without asking

Options:

```sh
chezmoi diff                          # see what changed
chezmoi apply --force                 # overwrite with repo version (safe for shell configs)
chezmoi add ~/.claude/settings.json   # pull the live version into the repo (for config files)
```

For shell configs (`.zshrc`, `.zprofile`, `.bash_profile`), always use `chezmoi apply --force` to restore the clean template. These files should never be manually edited.

---

## PATH order is wrong — wrong binary is resolving

Expected priority (highest to lowest). `$_LOCAL_PLAT` collapses to `$HOME/.local` in flat-mode (default).

```
$_LOCAL_PLAT/cargo/bin       Rust tools (fd, sd, zoxide, bat, rg, etc.)
$_LOCAL_PLAT/nvm/.../bin     Node.js (highest installed version)
$_LOCAL_PLAT/bin             chezmoi, uv, claude, codex, uv-tool entrypoints
~/.local/bin                 arch-neutral scripts (collapses to $_LOCAL_PLAT/bin in flat mode — deduped via typeset -U)
/opt/homebrew/bin            Homebrew (macOS) — also where rustup lives
/opt/homebrew/sbin           Homebrew sbin
/usr/bin                     system
```

Diagnose with:

```sh
which <tool>                  # where it's resolving from
type -a <tool>                # all locations on PATH
echo $PATH | tr ':' '\n'      # full PATH in order
```

If a Homebrew tool is shadowing a cargo tool, check `packages/cargo.txt` and `packages/Brewfile` for duplicates — remove the one you don't want.

The other classic shadowing footgun: legacy binaries at `~/.local/bin/<tool>` from before a layout migration. The `[[ -x "$ARCH_BIN/<tool>" ]]` install checks in current scripts catch most of these, but if `<tool> --version` shows an unexpectedly old version, check `ls ~/.local/bin/<tool>*` for backups (`*.preplat-bak.*` or stale binaries) and delete them.

---

## `nsys` / `ncu` resolve to the CUDA toolkit copy, not the standalone install

**Symptom.** You added a newer Nsight Systems / Nsight Compute to
`dotfiles-nvidia/packages/{nsys,ncu}-versions.txt`, the installer reports `ok`,
`nsys_list` / `ncu_list` show it — but `nsys --version` still prints the older
version, and `which nsys` points at `$_LOCAL_PLAT/.cuda/bin/nsys`.

**Root cause chain.** The CUDA toolkit bundles its own `nsys` and `ncu`. In the
shell profiles the `### CUDA ###` block runs *before* the Nsight blocks, and
`cuda_use` prepends `$CUDA_HOME/bin` to PATH. The Nsight auto-activation used to
be guarded on `! command -v nsys` ("activate only if not already in PATH") — by
that point the toolkit had *always* put one there, so the guard never fired and
the standalone install was permanently shadowed.

A second, independent trap: Nsight Compute ships `ncu` at the **root** of its
tree, not under `bin/` (Nsight Systems does use `bin/`). So even when `ncu_use`
did run, prepending `$NCU_HOME/bin` added a nonexistent directory.

**Confirm.**

```sh
which nsys ncu                       # .cuda/bin/... means it's shadowed
ls "$_LOCAL_PLAT/.ncu"               # ncu at top level, no bin/
readlink "$_LOCAL_PLAT/.nsys"        # which standalone version is active
```

**Fix.** Both are fixed in the profile templates: activation is now
unconditional whenever `$_LOCAL_PLAT/.nsys` / `.ncu` exists (the standalone
prepends *after* `cuda_use`, so it wins), and `ncu_use` falls back to
`$NCU_HOME` when there is no `bin/`. Run `chezmoi apply` and start a new login
shell. If it still resolves wrong, the version symlink is the likely culprit —
`cuda.sh`/`nsys.sh`/`ncu.sh` deliberately never overwrite an existing `.nsys` /
`.ncu` / `.cuda`, so a new install does not become active on its own:

```sh
nsys_switch tarball_nsys_2026.1.3.425
ncu_switch  tarball_ncu_2026.2.1.5
```

---

## Cloudflare Pages build failing

Check the build log via the API:

```sh
ACCOUNT="YOUR_CLOUDFLARE_ACCOUNT_ID"
TOKEN="..."
# List recent deployments
curl -s "https://api.cloudflare.com/client/v4/accounts/$ACCOUNT/pages/projects/dotfiles/deployments" \
  -H "Authorization: Bearer $TOKEN" | python3 -m json.tool | grep -E '"id"|"status"'

# Get logs for a specific deployment
DEPLOY_ID="..."
curl -s "https://api.cloudflare.com/client/v4/accounts/$ACCOUNT/pages/projects/dotfiles/deployments/$DEPLOY_ID/history/logs" \
  -H "Authorization: Bearer $TOKEN" | python3 -c "
import sys, json
for e in json.load(sys.stdin)['result']['data']: print(e['line'])
"
```

Common causes:
- **`cargo-binstall: command not found`** — `/opt/buildhome/.cargo/bin` not on PATH; check `infra/cloudflare/build.sh`
- **`mdbook: command not found`** — binstall failed; check network or fall back to `cargo install mdbook --locked`
- **Build output not found** — confirm `destination_dir = "docs/book"` in `infra/cloudflare/main.tf`

---

## Two machines fighting over dotfiles on a shared home

This happens when a template renders differently on each machine (e.g. using `{{ .chezmoi.arch }}`). The rule: **templates must be arch-neutral**. Arch-specific logic belongs in shell runtime code, not templates.

Check which template is causing the conflict:

```sh
chezmoi diff        # shows what chezmoi wants to change vs what's on disk
```

The fix is almost always to replace a template variable with a shell runtime expression. See [Managing dotfiles → Shared home safety](../setup/chezmoi.md#shared-home-directory-safety).

---

## A symlinked `~/.codex` or `~/.claude` turned back into a real directory

Symptom: you hand-symlinked `~/.codex` (or `~/.claude`) to scratch, and some time
later it is a plain directory again holding only the managed config — while the
scratch copy sits frozen at the date the link died. Nothing logged an error.

Root cause: chezmoi manages files *inside* both directories (`config.toml`,
`AGENTS.md`, `hooks.json`, profiles, `rules/`, `themes/`, `agents/` for Codex;
`settings.json`, `skills/`, hook scripts for Claude). A source *directory* means
chezmoi's target state for that path is "directory" — so on the next `chezmoi apply`
it removes whatever is there, symlink included, and recreates a real directory with
just the managed files. Everything else is orphaned wherever the link pointed.

Confirm — a stale target next to a fresh `$HOME` copy is the tell:

```sh
chezmoi managed | grep -x '.codex'          # non-empty ⇒ chezmoi owns this path
stat -c '%n %y' ~/.codex ~/scratch/.codex   # scratch frozen, home current
```

**Fix:** don't symlink the directory. Run `bash install/scratch.sh`, which redirects
the heavy *unmanaged* entries one level down (`sessions`, `cache`, `plugins`,
`*.sqlite`, …) where chezmoi never looks. See
[Scratch space](../setup/scratch.md#codex-specifics).

Then reconcile the orphaned copy by hand — the script won't touch it, because it
cannot tell your stale data from a deliberate second install:

```sh
du -sh ~/scratch/.codex                     # what was orphaned
rm -rf ~/scratch/.codex                     # once you've confirmed nothing is wanted
```

Setting `CODEX_HOME` instead does not help here, and makes things worse — see
[Why not CODEX_HOME?](../setup/scratch.md#why-not-codex_home).

---

## Duplicate PLAT paths in PATH (both v3 and v4 showing up)

Only relevant with `DF_USE_PLAT=1`. Fixed in current versions — `.zprofile`/`.bash_profile` resolve `~/.local` symlinks before setting `_LOCAL_PLAT` so PATH entries use the same physical path.

If you upgraded from before that fix:

```sh
chezmoi apply ~/.zprofile ~/.bash_profile
exec zsh -l                                # or: exec bash -l
echo "$PATH" | tr ':' '\n' | grep plat     # all entries should share the same PLAT prefix
```

In flat mode (`DF_USE_PLAT=0`, the default), this failure mode doesn't apply — there's no `$PLAT` segment in `$_LOCAL_PLAT`.

---

## Lost shell history

Zsh history lives at `~/.zsh_history` (the conventional default; survives any `~/.local` cleanup). Bash history at `~/.bash_history`. The bash sidecar command log (richer: timestamps, exit codes, cwd) at `~/.bash_log` — search via `bash_log_search <pattern>`.

If you have history under the old location (`~/.local/state/{zsh,bash}/`), one-time migrate:

```sh
[ -f ~/.local/state/zsh/history  ] && mv ~/.local/state/zsh/history  ~/.zsh_history
[ -f ~/.local/state/bash/history ] && mv ~/.local/state/bash/history ~/.bash_history
[ -f ~/.local/state/bash/log     ] && mv ~/.local/state/bash/log     ~/.bash_log
```

---

## Migrating off PLAT isolation

If you set up with `DF_USE_PLAT=1` and want to switch to flat (or vice-versa), the layout in `~/.local/` is stable as long as one mode is active — but switching strands GBs in the unused tree. Decommission tool:

```sh
# After setting DF_USE_PLAT=0 (or removing use_plat=true from chezmoi data):
bash ~/dotfiles/install/plat-decommission.sh
```

Refuses to run if `DF_USE_PLAT=1` is currently set (won't nuke the active install). See [PLAT isolation](../setup/plat.md) for the full migration story.

---

## Brew zsh tab completion leaves remnant characters (Linux)

Symptom: after pressing Tab, stale characters remain on the line instead of being erased.

Root cause chain:
1. Brew zsh's RUNPATH loads Homebrew's own glibc (`brew/opt/glibc/lib/libc.so.6`)
2. Homebrew's glibc ships no `lib/locale/` data → `setlocale()` silently falls back to `C/ASCII`
3. In the C locale, `wcwidth()` returns byte counts instead of display columns
4. Every cursor-position calculation in ZLE/completion is off → artifacts

Confirm by checking the codeset inside brew zsh:

```sh
zsh --no-rcs -c 'zmodload zsh/langinfo; echo $langinfo[CODESET]'
# broken:  ANSI_X3.4-1968
# working: UTF-8
```

**Fix:** `linux-packages.sh` generates `en_US.UTF-8` locale data for brew's glibc into
`$LOCAL_PLAT/locale/` using brew's own `localedef`. The shell profiles export `LOCPATH`
pointing there so brew zsh picks it up at startup.

If you installed before this fix:

```sh
# Regenerate locale data
bash ~/dotfiles/install/linux-packages.sh

# Apply updated shell profiles (adds LOCPATH export)
chezmoi apply ~/.zprofile ~/.bash_profile

# Open a new login shell and verify
exec zsh -l
zsh --no-rcs -c 'zmodload zsh/langinfo; echo $langinfo[CODESET]'  # UTF-8
```

Test suite: `bash ~/dotfiles/tests/test-locale.sh`

---

## Copy/paste from a remote SSH session pastes as mojibake (`â€™`, `Â`, `Ã©`)

Symptom: text copied out of a remote Linux session pastes with latin-1 garbage
where punctuation, accents, or spaces should be: `’` becomes `â€™`, `é` becomes
`Ã©`, non-breaking spaces surface as `Â `. Two common shapes:

- **plain ssh + tmux** — the display itself is garbled, and copies carry it
- **VS Code/Cursor Remote-SSH embedded terminal** — display may look fine, but
  copying agent TUI output (Claude Code renders with padding/NBSP characters)
  pastes with stray `Â` accent characters; no tmux involved

The terminal emulator (iTerm2, xterm.js) is innocent: the bytes are already
mangled before they reach it.

Root cause chain:

1. On macOS, `.zprofile` exports `LC_ALL=en_US.UTF-8`
2. macOS ships `SendEnv LANG LC_*` in `/etc/ssh/ssh_config`, and Linux sshd
   accepts `LC_*` by default — the Mac's `LC_ALL` lands in the remote
   environment. This covers Remote-SSH too: the VS Code/Cursor server is
   started over that same ssh connection, and every embedded terminal inherits
   its environment
3. `LC_ALL` overrides `LANG`, defeating the deliberate LANG-only locale setup in
   the Linux shell profiles (see the entry above). Embedded terminals are hit
   hardest: they spawn *non-login* shells, so a profile-only guard never even
   runs there
4. On hosts whose *system* glibc has no `en_US.UTF-8` compiled (minimal server
   images — the brew-glibc `LOCPATH` data doesn't help system binaries),
   `setlocale()` falls back to C/ASCII
5. Anything in that C locale that re-encodes the byte stream (system tmux is
   the classic offender) treats each UTF-8 byte as a separate latin-1
   character — the display, and therefore anything selected and copied from
   it, is mojibake

Confirm on the remote, inside the garbling session:

```sh
locale; echo "LC_ALL=$LC_ALL"; locale -a 2>/dev/null | grep -iE 'en_US|utf'
printf 'caf\xc3\xa9 \xe2\x80\x94 \xe2\x80\x9cok\xe2\x80\x9d\n'   # should render: café — “ok”
```

Broken looks like: a "cannot change locale" warning or `LC_CTYPE="C"` in the
`locale` output, and the printf line rendering as `cafÃ© â€” â€œokâ€`.

**Fix:** the locale guard (`unset LC_ALL` before exporting `LANG`, from the
`locale-env.sh` shared partial) runs in the Linux shell profiles AND the
interactive rc files — the rc copy is what protects non-login embedded
terminals. Then:

```sh
chezmoi apply ~/.zprofile ~/.bash_profile ~/.zshrc ~/.bashrc
tmux kill-server        # the tmux server caches the locale it started with
exec zsh -l             # or reconnect / open a fresh embedded terminal
```

Note the fix cleans the *encoding*; agent TUIs like Claude Code still put
invisible layout characters (padding spaces, hard wraps) into the scrollback,
so terminal-selection copies of long output stay imperfect. For clean text use
`/export` or copy from the paired web/mobile session instead.

If it's still garbled, the host has no UTF-8 locale usable by system binaries at
all — check `locale -a`; `export LANG=C.UTF-8` (built into every modern glibc)
is the fallback.

Note the tempting client-side fix does NOT work: `SendEnv -LC_*` in
`~/.ssh/config` is a no-op here, because ssh reads the user config *before*
`/etc/ssh/ssh_config` and `-pattern` removals apply at parse time — the system
default adds the patterns after your removal runs.

---

## `python` is Python 2 or cannot import SymPy

**Symptom:** `python --version` reports 2.7, or `python -c 'import sympy'`
fails after bootstrap.

**Cause:** The interactive Python environment or its entrypoint symlink is
missing for the active PLAT. This commonly appears after moving between hosts
with different CPU capability levels: another PLAT may have Python packages,
but its binaries are intentionally not on this host's PATH.

**Fix:** Re-run the Python installer for the active platform:

```sh
bash ~/dotfiles/install/python.sh
hash -r
python -c 'import sys, sympy; print(sys.version, sympy.__version__)'
```

The installer owns `$LOCAL_PLAT/python` and exposes its interpreter as
`$LOCAL_PLAT/bin/python`; project-specific dependencies still belong in each
project's uv environment.

## Python@3.14 build fails on Linux (uuid or test_datetime errors)

Python 3.14 from Homebrew has build issues on some Linux systems:

1. **UUID module detection failure** - configure detects libuuid but the build fails
2. **test_datetime hangs during PGO** - Profile-guided optimization runs the test suite, but `test_datetime` hangs on some CPUs (timezone-related)

**Fix:** Patches are applied automatically by `install/patch-homebrew-python.sh` during bootstrap. If you need to re-apply manually:

```sh
bash ~/dotfiles/install/patch-homebrew-python.sh
brew reinstall --build-from-source python@3.14
```

The patches:
- Set `py_cv_module__uuid=n/a` to disable the uuid module
- Patch Makefile's `PROFILE_TASK` to skip `test_datetime` during PGO

Environment variables in `.zprofile`/`.bash_profile` prevent Homebrew from auto-updating and overwriting these patches:
- `HOMEBREW_NO_AUTO_UPDATE=1` - prevents tap updates
- `HOMEBREW_NO_INSTALL_FROM_API=1` - forces local formula usage

---

## cass source build fails with `rustc 1.94.0 is not supported` or `E0554`

On a host with glibc < 2.38 (e.g. Ubuntu 22.04) cass has no usable prebuilt, so
`memory.sh` builds it from source — and you see one of:

```
rustc 1.94.0 is not supported by the following packages: sysinfo@0.39.5 requires rustc 1.95 …
# or, on a newer stable:
error[E0554]: `#![feature]` may not be used on the stable release channel
```

Two root causes stacked:

1. **cass requires nightly.** A dependency gates `#![feature(try_trait_v2)]` and
   the repo pins `channel = "nightly"`. Stable can't build it — an old stable
   fails the MSRV check, a new stable fails `E0554`.
2. **A stray Homebrew `rust` shadows rustup.** A `rust` formula (a lingering
   *build* dependency — not in the Brewfile, nothing depends on it) puts
   `cargo`/`rustc` in `brew/bin` at an old version. In bootstrap's PATH that
   shadows rustup, so `cargo` resolved to brew's 1.94.0 even after `rust.sh`
   updated rustup's stable to 1.97.1.

Confirm:

```sh
which -a cargo          # a brew/bin/cargo at an old version is the smoking gun
rustup toolchain list   # is `nightly` installed?
```

**Fix** (already baked into current `memory.sh` — this is for older checkouts or
manual recovery):

```sh
brew uninstall rust     # remove the orphan shadow (safe: nothing depends on it)
rustup toolchain install nightly --profile minimal
$CARGO_HOME/bin/cargo +nightly install --git \
  https://github.com/Dicklesworthstone/coding_agent_session_search \
  coding-agent-search --bin cass --locked --root "$LOCAL_PLAT"
```

`_cass_build_from_source` now installs nightly on demand and calls
`$CARGO_HOME/bin/cargo +nightly` explicitly, so it no longer depends on PATH
resolution or the default toolchain.

---

## `cass search` misses sessions you know happened

Symptom: history you remember from Codex or Cursor never surfaces, even on exact
phrases, while Claude Code sessions from the same week come back fine.

Root cause: cass ingest is **append-only per conversation**. Once a conversation is
in the canonical DB it is never re-read, so every parser improvement since it was
first indexed only reaches *new* sessions. Old ones keep whatever subset the parser
of the day extracted. `cass index --full` does not fix this — it forces a full
*scan* and a lexical rebuild, then logs `skipping historical salvage because
canonical database is already populated`.

Confirm — compare the DB against a fresh parse of the same files:

```sh
sqlite3 -readonly ~/.cass/agent_search.db \
  "select a.name, count(m.id) from messages m
   join conversations c on c.id=m.conversation_id
   join agents a on a.id=c.agent_id group by 1 order by 2 desc;"
wc -l < ~/.codex/sessions/2026/*/*/rollout-*.jsonl   # rough upper bound per file
```

Measured 2026-08-01: codex held 15,037 messages where the same 88 rollouts parse to
85,488 today, and cursor 3,384 vs 6,949 — 82% and 51% of that history unsearchable.

**Fix**, one connector at a time. Every step matters:

```sh
# 0. verify each source file still exists — forget is only safe if it can come back
sqlite3 -readonly ~/.cass/agent_search.db \
  "select c.source_path from conversations c join agents a on a.id=c.agent_id
   where a.name='codex';" | while read -r p; do [ -f "$p" ] || echo "MISSING: $p"; done

# 1. back up via sqlite, NOT cp — a plain copy can tear a live WAL
sqlite3 ~/.cass/agent_search.db ".backup '$HOME/.cass/agent_search.db.bak'"

# 2. drop the stale rows (dry-run first: omit --apply)
cass forget --source-glob "$HOME/.codex/sessions/**" --apply

# 3. reset the connector watermark — --full still honours it, and rollouts dated
#    months ago never beat a watermark stamped today, so the scan finds nothing
sqlite3 ~/.cass/agent_search.db \
  "update meta set value='0' where key='last_scan_ts:connector:codex';"

# 4. re-ingest, then clean up after a cass bug: forget leaks tail-state rows keyed
#    by the deleted conversation_id, and that column is a plain rowid — SQLite
#    reuses freed ids, so a future conversation would inherit a stale
#    "ingested through idx N" marker and be silently truncated
cass index --full
sqlite3 ~/.cass/agent_search.db \
  "delete from conversation_tail_state
   where conversation_id not in (select id from conversations);"

# 5. rebuild vectors in bounded batches; repeat until the backlog is empty
bash ~/dotfiles/install/memory.sh semantic
```

Skipping step 3 is the usual failure — the run exits 0, having ingested nothing.

---

## `cass index` fails with `graph topology attestation failed`

```
build HNSW index failed: hnsw error: graph topology attestation failed:
parallel construction failed (search entry origin 6219 reaches only 92908/97513
points at the base layer); serial rebuild also failed
```

Transcripts contain thousands of byte-identical tool stubs — `[Tool: apply_patch]`
alone repeats 4,383 times — and identical text embeds to identical vectors. Under
`DistDot` those form zero-distance cliques larger than the layer-0 fanout
(`max_nb_connection 16` → ~32 links), so a clique fills every member's neighbour
list with its own duplicates and nothing outside ever links *in*. HNSW reachability
is directional, so the whole group is unreachable from the entry point and cass's
attestation rejects the graph.

It is deterministic: retrying fails identically, which is why the serial rebuild
also failed and why `retryable=true` in the error is misleading.

**Fix:** drop `--build-hnsw` (the manual `memory.sh semantic` mode does not use
it). HNSW only backs `--approximate`; exact search over ~100k vectors is
fast enough, and the flag has never once succeeded on this archive — every
`semantic_manifest.json` here records `"hnsw": null`. Restore it if cass starts
deduping identical vectors before insert.

---

## Every `cass` command fails: `unable to open database file` (but sqlite3 opens it fine)

```
opening frankensqlite db readonly at /Users/cade/.cass/agent_search.db:
unable to open database file: '/Users/cade/.cass/agent_search.db'
```

`cass doctor` reports `archive-db-unreadable`, `cass index --full` refuses to
run ("index refused to modify an unhealthy canonical archive"), and the
older cass-watch/cass-semantic LaunchAgents may crash-loop with exit 5 — yet
`sqlite3 -readonly ~/.cass/agent_search.db "pragma quick_check;"` says `ok`.

frankensqlite pins the database's file identity — device id + inode — in the
`agent_search.db-fsqlite-ns-use` sidecar (record: 8-byte `FSQLNS01` magic,
1-byte version, then tag/dev/ino big-endian). On macOS, APFS volume device ids
are assigned at mount time and can change across reboots. After the id shifts,
every read-only open compares recorded vs live identity and fails closed with
`SQLITE_CANTOPEN`. A read-write open would rewrite the record and self-heal,
but cass health-gates every mutating command behind a read-only open first, so
nothing ever reaches the heal path.

**Confirm.**

```sh
stat -f "dev=%d ino=%i" ~/.cass/agent_search.db   # live identity
hexyl -n 40 ~/.cass/agent_search.db-fsqlite-ns-use
# bytes 10..18 = recorded dev (BE), bytes 18..26 = recorded ino (BE)
```

Inode matches, device id doesn't → this bug. If the *inode* differs, the db
file was actually replaced — stop and investigate before touching anything.

**Fix.** Stop all cass processes, then patch the recorded dev to the live value
(here only the last byte differed, `0x10` → `0x0d` at offset 17):

```sh
printf '\x0d' | dd of="$HOME/.cass/agent_search.db-fsqlite-ns-use" \
  bs=1 seek=17 count=1 conv=notrunc
cass doctor        # database failure should be gone
bash ~/dotfiles/install/memory.sh index
bash ~/dotfiles/install/memory.sh semantic  # one bounded vector batch
```

Recurs whenever the Data volume mounts with a different device id. Do **not**
run `cass doctor --fix` for this: on 0.6.23 it enters unbounded recursion in
the reconstruct path (observed: 1.6 h at 100% CPU, ~50 GB RSS, no output) —
kill it if started; it only touches lock files before hanging.

---

## macOS keeps asking: "cass would like to access data from other apps"

The prompt returns every few minutes, and "Allow" doesn't make it stop.

Older dotfiles deployed a `dev.cade.cass-watch` LaunchAgent that ran `cass index`
every 300 s, and **the `aider`
connector crawls `$HOME`**. Aider histories are project-local
(`.aider.chat.history.md` in each repo), so discovery walks its root — and that root
defaults to `$HOME`. The walk enters `~/Pictures`, `~/Music`, `~/Documents`,
`~/Desktop`, `~/Downloads`, and `~/Library`, so it asks for Photos, MediaLibrary,
AddressBook, Calendar, AppData — and AllFiles.

It is tempting to blame the connectors that read `~/Library/Application Support`
(`cursor`, `chatgpt`, `copilot`) — don't. Measured 2026-08-05: a scan that opens 13
Cursor `state.vscdb` files raises **zero** TCC requests, because Cursor is a
non-sandboxed Electron app with no registered container, so its app-support dir isn't
protected. Excluding those connectors costs you cross-harness session coverage and
fixes nothing.

"Allow" doesn't make it stop because `cass` is ad-hoc signed (`codesign -dv` →
`Signature=adhoc`, no Team ID), so a grant is pinned to the binary's cdhash and is
voided at the next cass upgrade. There is also no System Settings pane for App Data
grants, so a stale one can't be repaired from the UI.

See exactly what cass is asking for — this is the diagnostic that matters, since the
cass logs only record paths it opens deliberately, not what a directory walk touches:

```bash
/usr/bin/log show --last 30m --predicate 'process == "tccd"' --info \
  | rg 'Sub:\{.*/\.local/bin/cass\}' | rg -o 'kTCCService[A-Za-z]+' | sort | uniq -c
```

(`/usr/bin/log` explicitly — `log` is a shell function in this repo's profiles.)

**Fix — bound the crawl. That's the whole fix; leave every connector enabled:**

```bash
export CASS_AIDER_DATA_ROOT="$HOME/dev"   # aider discovery root, not $HOME
```

Applied on macOS by the manual `install/memory.sh` index modes. Current dotfiles
remove the old scheduled LaunchAgents. Aider still indexes normally — just only
under the given root, so aider projects elsewhere go unindexed.
`CASS_AIDER_DATA_ROOT` takes a single path, so `$HOME` is the only "covers everything"
value and it is what causes the problem.

Verify with the `log show` command above: a scan should now produce no cass entries at
all. Check a scan really ran, or the empty result proves nothing —
`rg 'skipping disabled connectors' ~/.local/share/cass/stderr.log | tail -1`.

The alternative to all of this is granting `~/.local/bin/cass` Full Disk Access
(`kTCCServiceSystemPolicyAllFiles` is one of the things it asks for), which covers every
service at once — but it must be re-added after every cass upgrade, and it hands a
self-updating ad-hoc-signed binary read access to Mail, Messages, and Safari history.

---

## `git push` blocked by gitleaks ("secrets detected")

A global **pre-push** hook scans the commits being pushed for secrets with
[gitleaks](https://github.com/gitleaks/gitleaks) and refuses the push if it finds
any. This is the safety net that keeps tokens and private keys out of remote
history — see [Authentication → File security](../setup/auth.md#file-security).

How it's wired:

- `brew "gitleaks"` (in `packages/Brewfile`) installs the scanner.
- The hook lives at `home/dot_config/git/hooks/executable_pre-push`, deployed by
  chezmoi to `~/.config/git/hooks/pre-push`.
- `~/.gitconfig` sets `core.hooksPath = ~/.config/git/hooks`, so it applies to
  **every repo on the machine**, not just dotfiles.
- It scans only the commits being pushed (a new branch is scanned against
  `--remotes`), not the full history, so it stays fast.
- If gitleaks isn't installed yet, the hook prints a warning and exits cleanly
  rather than blocking you.

When a push is blocked, the hook prints the exact `--log-opts` range it flagged.
Review the finding:

```sh
# Re-run the scan the hook ran (range is printed in the failure message)
gitleaks git --log-opts="<remote_sha>..<local_sha>"

# Or scan the entire repo history
gitleaks git --no-banner
```

If it's a real secret: rotate it, then rewrite the offending commit(s) to remove
it before pushing (a `--no-verify` push would leak it to the remote). If it's a
confirmed false positive, add a [gitleaks allowlist][allowlist] entry rather than
disabling the hook.

**Emergency bypass** (use only when you're certain there's no secret):

```sh
git push --no-verify
```

Don't disable the hook permanently — `core.hooksPath` is global precisely so the
protection can't be forgotten on a per-repo basis.

---

## `npm install -g` fails with `EBUSY … unlink '.nfsXXXX'` (qmd upgrade)

`bootstrap.sh upgrade` (or `install/node.sh`) dies upgrading a global npm
package — almost always `@tobilu/qmd`:

```
npm error code EBUSY
npm error EBUSY: resource busy or locked, unlink
'.../@tobilu/qmd/node_modules/sqlite-vec-linux-x64/.nfs000000001f79d0f000015a88'
[fail]  node.sh failed
```

**Root cause: NFS "silly-rename".** The qmd MCP daemon
(`qmd mcp --http --port 8181`) keeps native addons (`sqlite-vec`,
`node-llama-cpp`, `better-sqlite3`) mmap'd. When npm deletes the old package
tree to swap in the new one, NFS can't remove a file the daemon still has open,
so it renames it to `.nfsXXXX` and keeps it until that fd closes. npm then can't
`unlink` the `.nfs*` file and aborts with `EBUSY`. Only happens on NFS homes
(the Linux clusters) — macOS local disks unlink open files fine, so this is
gated to Linux.

`node.sh` now stops the daemon around the qmd upgrade and restarts it (via the
`qmd_daemon_*` helpers in `_lib.sh`), so a normal upgrade no longer trips on it.
To recover a checkout that predates the fix, or if you hit it by hand:

```sh
pkill -f "qmd[^ ]* mcp --http"         # 1. stop the daemon → NFS reaps .nfs* files
npm install -g @tobilu/qmd@latest      # 2. re-run the upgrade (or: bash install/node.sh)
qmd mcp --http --daemon &              # 3. restart (a new shell also lazy-starts it)
```

A failed swap can also leave a **broken husk** — a `qmd/` dir with only an empty
`node_modules/` plus a dangling `bin/qmd` symlink — in a *different* npm prefix
than the one `which qmd` resolves to (nvm's). Delete the husk; the live copy is
the one on PATH.

[allowlist]: https://github.com/gitleaks/gitleaks#configuration

## `import sage.all` / cysignals dies with `TypeError: signal handler must be signal.SIG_IGN, signal.SIG_DFL, or a callable object`

**Symptom.** Importing `cysignals.pysignals` (directly, or transitively via
passagemath's `sage.all`) raises the TypeError above. Plain `import
cysignals.signals` (and cypari2) works fine.

**Root cause.** This macOS release (Darwin 25.x) pre-installs C-level fault
handlers (SIGILL, SIGABRT, SIGFPE, SIGBUS, SIGSEGV) in every process.
`signal.getsignal()` reports a handler Python didn't install as `None`, and
cysignals' pysignals init saves + re-installs existing handlers — re-setting
`None` is rejected by CPython. Not sandbox-, uv-, or Python-version-specific:
reproduced on uv's python-build-standalone 3.12/3.13 and Homebrew 3.14.

**Confirm.**
```bash
python3 -c "import signal; print(signal.getsignal(signal.SIGSEGV))"   # → None
```

**Fix.** Reset the fault handlers from Python before anything imports
`cysignals.pysignals` (`~/dev/math-lab/sagefix.py` does exactly this):
```python
import signal
for s in (signal.SIGILL, signal.SIGABRT, signal.SIGFPE, signal.SIGBUS, signal.SIGSEGV):
    signal.signal(s, signal.SIG_DFL)
```
Related trap: pinning `cysignals` older than what passagemath wheels were
built against fails later with `cysignals.signals does not export expected C
function _do_raise_exception` — keep the resolver's cysignals (1.12.x), fix
the handlers instead.

## `pdflatex: command not found` on macOS with MacTeX installed

**Symptom.** `brew list --cask` shows `mactex` and
`/Library/TeX/texbin/pdflatex` exists and is executable, but `pdflatex`,
`latexmk`, `chktex`, and `texcount` all report "command not found".

**Root cause.** MacTeX installs into `/Library/TeX/texbin`, which is on no
default PATH. Its installer drops a `/etc/paths.d/TeX` entry, but that only
reaches `path_helper`-processed shells, and these profiles rebuild PATH
themselves. `install/latex.sh` verified the binary by absolute path, so the
step reported `[okay]` while nothing was actually reachable.

**Confirm.**
```bash
ls /Library/TeX/texbin/pdflatex   # exists
command -v pdflatex               # nothing
```

**Fix.** Handled by both shell profiles:
```sh
[ -d /Library/TeX/texbin ] && path=($path /Library/TeX/texbin)   # zprofile
```
Appended, not prepended, so Linux's TinyTeX binaries (symlinked into
`$ARCH_BIN` by `latex.sh`) keep priority on a machine with both. Run
`chezmoi apply ~/.zprofile ~/.bash_profile` and start a new shell.

## `brew bundle` installs nothing new and exits 0

**Symptom.** `brew bundle install` prints only `Using <formula>` lines and
succeeds. Packages just added to the Brewfile never appear, and no error names
them.

**Root cause.** A cask-only package declared as `brew "..."` instead of
`cask "..."`. Homebrew resolves the whole dependency graph before installing
anything, so one unsatisfiable entry aborts the entire run — every other new
package is collateral, which is what makes this read as a no-op rather than a
failure. Hit Aug 2026 with `brew "quarto"`: homebrew-core has no quarto formula
at all, only a cask.

**Confirm.**
```bash
brew bundle check --file=packages/Brewfile --verbose
# → Formula quarto needs to be installed or updated.
brew info --formula quarto
# → Error: No available formula ... Found a cask named "quarto" instead.
```

**Fix.** Move it into the `if OS.mac?` block as `cask "quarto"`. Casks are
macOS-only, so a cask-only tool has no Homebrew route on Linux — install it
another way there rather than leaving a `brew` line that breaks every bundle
run. Check a new entry with `brew info --formula <name>` before committing.

## A GUI app's config is permanently dirty in `chezmoi status`

**Symptom.** `chezmoi status` shows `MM` on an app's config file every time you
look, even when you changed nothing. Running `chezmoi apply` "fixes" it, then it
comes back after the app runs. Worse, bootstrap (which runs `chezmoi apply
--force`) silently reverts real in-app settings changes along the way.

**Root cause.** Two writers on one file. The app owns and rewrites its config,
and a statically chezmoi-managed copy fights it. LinearMouse is the sharpest
case: it stamps `"$schema": "https://schema.linearmouse.app/<app version>"` into
the file, so the file goes dirty **on a timer** — every app update produces a
diff with no setting change behind it. That trains you to ignore the dirty
status, which is exactly when a real reverted setting slips past.

**Confirm.**
```bash
chezmoi diff ~/.config/linearmouse/linearmouse.json
# -  "$schema" : ".../0.11.3"      <- what the app wrote
# +  "$schema" : ".../0.11.2"      <- what apply would force back
```

**Fix.** Don't let chezmoi manage app-owned configs. Use the apply/sync split
(`install/linearmouse.sh`, `install/claude-desktop.sh`,
`install/codex-desktop.sh`): the tracked source lives under `install/<app>/`,
`apply` merges it into the live file live-first so app-owned keys survive, and
`sync` captures in-app changes back. For LinearMouse specifically the tracked
source omits `$schema` entirely, so only genuine setting changes ever diff.

```bash
bash install/linearmouse.sh sync    # capture in-app changes → repo
bash install/linearmouse.sh         # push repo settings → app (default: apply)
```

Adding a new app to this pattern means deleting its `home/` chezmoi source
(chezmoi then leaves the live file alone), adding the script, and wiring a
`DF_DO_*` flag in `bootstrap.sh`.

---

## Codex MCP OAuth fails: "Authorization server response missing required issuer"

**Symptom.** `codex mcp login <server>` (or first use of an OAuth MCP server in
Codex) opens the browser, auth succeeds there, then the CLI dies with
`failed to handle OAuth callback … Authorization server response missing
required issuer: expected <server url>`. The same server connects fine from
Claude Code.

**Root cause.** A Codex regression, not a server or config problem. Codex
0.143.0+ looks for an `iss` field in the token endpoint's JSON response body —
where RFC 6749 doesn't put one — instead of using the RFC 9207 `iss` callback
parameter it already validated. Spec-compliant authorization servers
(Cloudflare's among them) fail the check. Tracked in
[openai/codex#31573](https://github.com/openai/codex/issues/31573); introduced
via a modelcontextprotocol/rust-sdk change.

**Confirm.** `codex --version` ≥ 0.143.0, the issue above still open, and the
server works from another harness. For Cloudflare specifically, prove the
server itself is healthy with a direct handshake:

```bash
curl -s -X POST https://mcp.cloudflare.com/mcp \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"probe","version":"0.0.0"}}}'
# → {"result":{…"serverInfo":{"name":"cloudflare-api"…
```

**Fix.** Sidestep OAuth in Codex with a static bearer: the
`--codex-bearer <ENV_VAR>` annotation in `packages/mcp-servers.txt` makes
`install/codex.sh` emit `bearer_token_env_var = "<ENV_VAR>"` for that server
while every other harness keeps OAuth. Cloudflare rides
`--codex-bearer CLOUDFLARE_API_TOKEN` (from `~/.cloudflare.env`,
`bash install/auth.sh cloudflare`); mcp.cloudflare.com accepts API-token
bearers directly, verified with the handshake above. Caveat: the token's
scopes bound what the tools can do — OAuth carried your full user grant, so
mint a broader token if a tool call 403s. Remove the annotation once the
upstream fix ships.
