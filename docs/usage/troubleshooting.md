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

`nvm.sh` is lazy-loaded in interactive shells only. Non-interactive shells get `node`/`npm` via the PATH entry `.zprofile` adds from the highest installed version. If `node` is missing in a script, either:

```sh
# Option 1: source zprofile at the top of your script
source ~/.zprofile

# Option 2: use the full path
NODE="$NVM_DIR/versions/node/$(ls $NVM_DIR/versions/node | sort -V | tail -1)/bin/node"
```

---

## Homebrew on Linux: Docker/Podman not found

`linux-packages.sh` requires a container runtime. Options:

```sh
# Rootless Docker
curl -fsSL https://get.docker.com/rootless | sh

# Podman (Debian/Ubuntu)
apt install podman

# Skip packages entirely and install manually
INSTALL_PACKAGES=0 ~/dotfiles/bootstrap.sh
```

See [Bootstrap → Linux](../setup/bootstrap.md#linux) for full setup instructions.

---

## chezmoi keeps prompting for name/email

The cached values live in `~/.config/chezmoi/chezmoi.toml`. To reset:

```sh
chezmoi init --data=false
```

To pre-seed without prompting:

```sh
CHEZMOI_NAME="Your Name" CHEZMOI_EMAIL="you@example.com" chezmoi init
```

---

## chezmoi diff shows unexpected changes

Another program modified a managed file (e.g. Claude Code updated `~/.claude/settings.json`). Options:

```sh
chezmoi diff                          # see what changed
chezmoi apply                         # overwrite with repo version
chezmoi add ~/.claude/settings.json   # pull the live version into the repo
```

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
ACCOUNT="5afb385ba43e1a082b138554dfdb141c"
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
