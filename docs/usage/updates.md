# Day-to-day workflow

---

## Update and upgrade

```sh
~/dotfiles/bootstrap.sh update    # pull latest + refresh tools (no brew upgrade)
~/dotfiles/bootstrap.sh upgrade   # update + brew upgrade + cargo upgrade
~/dotfiles/bootstrap.sh           # full install (same as first run, idempotent)
```

`update` pulls the repo, applies chezmoi, refreshes zsh plugins, and re-runs all install scripts (which skip already-installed tools). `upgrade` does the same but also enables Homebrew upgrades and forces cargo-binstall to re-check for newer binaries.

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
chezmoi edit ~/.zprofile       # zsh login shell
chezmoi edit ~/.bash_profile   # bash login shell
chezmoi edit ~/.gitconfig
```

Or edit the source directly and apply:

```sh
$EDITOR ~/dotfiles/home/dot_zshrc.tmpl
$EDITOR ~/dotfiles/home/dot_zprofile.tmpl
$EDITOR ~/dotfiles/home/dot_bash_profile.tmpl
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

Claude and Codex now diverge intentionally:

```sh
chezmoi edit ~/.claude/CLAUDE.md
chezmoi edit ~/.codex/AGENTS.md
```

Use `~/.claude/CLAUDE.md` for Claude-specific memory and `~/.codex/AGENTS.md` for Codex-specific guidance. Keep only genuinely shared preferences aligned.

Claude Code's status line is powered by [CCometixLine](https://github.com/Haleclipse/CCometixLine) (`@cometix/ccline` in `npm.txt`). To pick a theme: `ccline --config`.

Codex also has global skills and rules:

```sh
chezmoi edit ~/.codex/config.toml
chezmoi edit ~/.codex/rules/default.rules
```

Skills live under `home/dot_codex/skills/` in the repo and apply to `~/.codex/skills/`.

Useful Codex commands after updating:

```sh
codex --profile fast
codex --profile review
codex execpolicy check --pretty --rules ~/.codex/rules/default.rules -- git status
codex '$project-bootstrapper Map this repository and propose the first validation step.'
```

---

## Add an env var or PATH entry

Edit both `home/dot_zprofile.tmpl` and `home/dot_bash_profile.tmpl` (they should stay identical). For anything arch-specific use `$_LOCAL_PLAT` (set at shell startup):

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
