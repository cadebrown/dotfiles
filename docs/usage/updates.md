# Day-to-day workflow

---

## Upgrade all packages

```sh
~/dotfiles/bootstrap.sh
```

That's it. Every install script is idempotent — it upgrades what's installed, installs what's missing, and skips what's already current. Re-running bootstrap is safe at any time and is the same command whether you're on a fresh machine or updating an existing one.

---

## Add a package

See [Package management](../setup/packages.md) for the priority order. Quick reference:

```sh
# Rust tool → packages/cargo.txt, then:
bash ~/dotfiles/install/rust.sh

# Homebrew formula/cask → packages/Brewfile, then:
brew bundle --file=~/dotfiles/packages/Brewfile

# Python package → packages/pip.txt, then:
bash ~/dotfiles/install/python.sh
```

---

## Edit a dotfile

```sh
chezmoi edit ~/.zshrc          # opens in $EDITOR, applies on save
chezmoi edit ~/.zprofile
chezmoi edit ~/.gitconfig
```

Or edit the source directly and apply:

```sh
$EDITOR ~/dotfiles/home/dot_zshrc.tmpl
chezmoi apply
```

Preview before applying: `chezmoi diff`

---

## Sync dotfiles from the repo

```sh
chezmoi update                 # git pull + chezmoi apply
```

---

## Update AI agent instructions

Claude (`~/.claude/CLAUDE.md`) and Codex (`~/.codex/AGENTS.md`) mirror each other — edit both:

```sh
chezmoi edit ~/.claude/CLAUDE.md
chezmoi edit ~/.codex/AGENTS.md
```

---

## Add an env var or PATH entry

Edit `home/dot_zprofile.tmpl`. For anything arch-specific use `$_LOCAL_PLAT` (set at shell startup):

```sh
export MY_TOOL_HOME="$_LOCAL_PLAT/my-tool"
export PATH="$MY_TOOL_HOME/bin:$PATH"
```

Also add the variable to `install/_lib.sh` so install scripts can reference the same path.

---

## Work on the docs

```sh
cd ~/dotfiles/docs && mdbook serve --open   # live reload at localhost:3000
```

Every push to `main` auto-deploys to [dotfiles.cade.io](https://dotfiles.cade.io) via Cloudflare Pages.

---

## Deploy infrastructure changes

```sh
cd ~/dotfiles/infra/cloudflare
export CLOUDFLARE_API_TOKEN=...
tofu plan     # preview
tofu apply    # apply
```

`terraform.tfvars` is gitignored — it holds `account_id` and stays local.

---

## Commit and push

```sh
cd ~/dotfiles
git add -p                    # stage selectively
git commit -m "description"
git push
```

Natural commit points: one commit per feature, config change, or coherent set of package additions.
