# Day-to-day workflow

Use the normal bootstrap for updates; edit managed sources for configuration changes.

| Task | Jump to |
| --- | --- |
| Refresh tools | [Update and upgrade](#update-and-upgrade) |
| Install something new | [Add a package](#add-a-package) |
| Change configuration | [Edit a dotfile](#edit-a-dotfile) · [Agent instructions](#update-ai-agent-instructions) |
| Change this site | [Work on the docs](#work-on-the-docs) |

## Update and upgrade

```sh
~/dotfiles/bootstrap.sh update    # pull latest + refresh tools (no brew upgrade)
~/dotfiles/bootstrap.sh upgrade   # update + brew upgrade + cargo upgrade
~/dotfiles/bootstrap.sh           # full install (same as first run, idempotent)
```

`update` pulls the repo, applies chezmoi, refreshes zsh plugins, and reconciles missing tools while holding existing Homebrew and Go packages. `upgrade` also refreshes Homebrew, Go, Rust/Cargo, Node/npm, uv tools, Julia, TeX, and extensions, then runs the strict JSON toolchain audit.

Run the read-only audit independently with:

```sh
bash ~/dotfiles/install/audit-versions.sh | jq .
```

---

## Add a package

See [Package management](../setup/packages.md) for the priority order. Quick reference:

```sh
# Rust tool → packages/cargo.txt, then:
bash ~/dotfiles/install/rust.sh

# Homebrew formula/cask → packages/Brewfile, then:
brew bundle --file=~/dotfiles/packages/Brewfile

# Plain Python libraries → packages/python.txt
# Python CLI tools → packages/pip.txt; optional full tools → packages/pip-full.txt
bash ~/dotfiles/install/python.sh
```

---

## Edit a dotfile

```sh
chezmoi edit ~/.zshrc          # edit the managed source
chezmoi diff ~/.zshrc          # inspect the pending change
chezmoi apply ~/.zshrc         # apply this target
exec zsh -l                    # load it in a new login shell
```

Find other targets in the [configuration map](../reference/managed-configuration.md). Plain `chezmoi edit` edits source only; `--apply` applies after editing and `--watch` applies on save.

---

## Sync dotfiles from the repo

```sh
chezmoi update                 # git pull + chezmoi apply
```

---

## AeroSpace config (v2)

Window-management docs are now in [AeroSpace window management](aerospace.md).

---

## Update AI agent instructions

Change shared guidance once; keep harness-specific behavior in its wrapper.

| Change | Authoritative source / guide |
| --- | --- |
| Shared preferences and tone | [Instruction architecture](../agents/instructions.md) |
| Codex profiles, roles, rules, or themes | [Codex guide](../agents/codex.md) · [managed sources](../../home/dot_codex/) |
| Claude hooks and status line | [Claude guide](../agents/claude.md) · [status-line source](../../home/dot_claude/executable_statusline.sh) |
| A skill | [Skill ownership and sync](../agents/skills.md) |

For a Codex configuration change:

```sh
"${EDITOR:-vi}" ~/dotfiles/home/dot_codex/create_private_config.toml
bash ~/dotfiles/install/codex.sh sync-config
bash ~/dotfiles/install/codex.sh check
```

Sync preserves runtime trust sections. Start a new session to load changed profiles or tool inventories. For the complete command and permission reference, use [agent guidance](agents.md#codex-workbench).

---

## Add an env var or PATH entry

Keep [zsh](../../home/dot_zprofile.tmpl) and [bash](../../home/dot_bash_profile.tmpl) login behavior aligned. Use `$_LOCAL_PLAT` for architecture-specific shell state:

```sh
export MY_TOOL_HOME="$_LOCAL_PLAT/my-tool"
export PATH="$MY_TOOL_HOME/bin:$PATH"
```

Also add the variable to `install/_lib.sh` so install scripts can reference the same path.

---

## Work on the docs

```sh
cd ~/dotfiles
npm --prefix site ci --ignore-scripts
npx --prefix site --no-install playwright install chromium
npm --prefix site run dev
./tests/ci.sh docs
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
