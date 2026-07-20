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
`build-web-data-visualization` were dropped as of codex-cli 0.144.6.)

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

## `nvm` or `node` not available in a script

`nvm.sh` is lazy-loaded in interactive shells only. Non-interactive shells get `node`/`npm` via the PATH entry `.zprofile`/`.bash_profile` adds from the highest installed version. If `node` is missing in a script, either:

```sh
# Option 1: source profile at the top of your script (zsh)
source ~/.zprofile

# Option 1b: source profile at the top of your script (bash)
source ~/.bash_profile

# Option 2: use the full path
NODE="$NVM_DIR/versions/node/$(ls $NVM_DIR/versions/node | sort -V | tail -1)/bin/node"
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

## Copy/paste from a remote SSH session pastes as mojibake (`â€™`, `Ã©`)

Symptom: text copied out of a remote Linux session — usually inside tmux — pastes
on the Mac with latin-1 garbage where punctuation or accents should be: `’`
becomes `â€™`, `é` becomes `Ã©`. The terminal (iTerm2, Cursor) is innocent: the
bytes are already mangled before they reach it.

Root cause chain:

1. On macOS, `.zprofile` exports `LC_ALL=en_US.UTF-8`
2. macOS ships `SendEnv LANG LC_*` in `/etc/ssh/ssh_config`, and Linux sshd
   accepts `LC_*` by default — the Mac's `LC_ALL` lands in the remote environment
3. `LC_ALL` overrides `LANG`, defeating the deliberate LANG-only locale setup in
   the Linux shell profiles (see the entry above)
4. On hosts whose *system* glibc has no `en_US.UTF-8` compiled (minimal server
   images — the brew-glibc `LOCPATH` data doesn't help system binaries),
   `setlocale()` falls back to C/ASCII
5. System tmux in a C locale treats each UTF-8 byte as a separate latin-1
   character and re-emits it as multibyte UTF-8 — the display, and therefore
   anything selected and copied from it, is mojibake

Confirm on the remote, inside the garbling session:

```sh
locale; echo "LC_ALL=$LC_ALL"; locale -a 2>/dev/null | grep -iE 'en_US|utf'
printf 'caf\xc3\xa9 \xe2\x80\x94 \xe2\x80\x9cok\xe2\x80\x9d\n'   # should render: café — “ok”
```

Broken looks like: a "cannot change locale" warning or `LC_CTYPE="C"` in the
`locale` output, and the printf line rendering as `cafÃ© â€” â€œokâ€`.

**Fix:** the Linux shell profiles `unset LC_ALL` before exporting `LANG`. Then:

```sh
chezmoi apply ~/.zprofile ~/.bash_profile
tmux kill-server        # the tmux server caches the locale it started with
exec zsh -l             # or reconnect
```

If it's still garbled, the host has no UTF-8 locale usable by system binaries at
all — check `locale -a`; `export LANG=C.UTF-8` (built into every modern glibc)
is the fallback.

Note the tempting client-side fix does NOT work: `SendEnv -LC_*` in
`~/.ssh/config` is a no-op here, because ssh reads the user config *before*
`/etc/ssh/ssh_config` and `-pattern` removals apply at parse time — the system
default adds the patterns after your removal runs.

---

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
