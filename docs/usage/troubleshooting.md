# Troubleshooting

Quick reference for when things go wrong. Check here before digging into scripts.

---

## Tool not found after bootstrap

```sh
echo "$_PLAT"                         # confirm which platform the shell resolved
ls ~/.local/$_PLAT/bin/               # chezmoi, uv, claude should be here
ls ~/.local/$_PLAT/cargo/bin/         # fd, sd, zoxide, etc.
which fd                              # should point into ~/.local/$_PLAT/
```

If `$_PLAT` is empty or wrong, `.zprofile` wasn't sourced. Open a new login shell (`zsh -l`) or source it:

```sh
source ~/.zprofile
```

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

Expected priority (highest to lowest):

```
~/.local/$PLAT/venv/bin      Python venv
~/.local/$PLAT/cargo/bin     Rust tools (fd, sd, zoxide, etc.)
~/.local/$PLAT/nvm/.../bin   Node.js
~/.local/$PLAT/bin           chezmoi, uv, claude (Linux)
~/.local/bin                 arch-neutral scripts
/opt/homebrew/bin            Homebrew (macOS)
/usr/bin                     system
```

Diagnose with:

```sh
which <tool>                  # where it's resolving from
type -a <tool>                # all locations on PATH
echo $PATH | tr ':' '\n'      # full PATH in order
```

If a Homebrew tool is shadowing a cargo tool, check `packages/cargo.txt` and `packages/Brewfile` for duplicates — remove the one you don't want.

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

This is fixed in current versions. Both `.zprofile` (zsh) and `.bash_profile` (bash) now resolve `~/.local` symlinks before setting `_LOCAL_PLAT`, ensuring all PATH entries use consistent physical paths.

If you installed before this fix was added:

```sh
# Apply updated shell profiles
chezmoi apply ~/.zprofile ~/.bash_profile

# Open a new shell
exec zsh -l   # or: exec bash -l

# Verify only one PLAT appears
echo "$_PLAT"                           # should show only the detected PLAT
echo "$PATH" | tr ':' '\n' | grep plat  # all paths should have the same PLAT prefix
```

On a shared NFS home with scratch space, `~/.local` is a symlink to `/scratch/$USER/.paths/.local`. The shell profiles now resolve this symlink so Homebrew, cargo, nvm, and other tools all add the same physical path to PATH (no duplicates).

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
