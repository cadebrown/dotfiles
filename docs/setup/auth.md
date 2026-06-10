# Auth (API tokens)

`install/auth.sh` is a guided helper for the API tokens this repo's tools need. It maintains `~/.<service>.env` files (chmod 600) — sourced automatically by `install/_lib.sh` on every install run and by your login shell.

## Quick reference

```sh
bash ~/dotfiles/install/auth.sh                  # walk every service interactively
bash ~/dotfiles/install/auth.sh status           # current state, no prompts
bash ~/dotfiles/install/auth.sh huggingface      # set/update one
bash ~/dotfiles/install/auth.sh gh               # `gh auth login` (browser)
bash ~/dotfiles/install/auth.sh help             # service list

# Or as part of bootstrap:
DF_DO_AUTH=1 ~/dotfiles/bootstrap.sh
```

## Service registry

| Service | Env var | File | Used for | Skip if |
|---|---|---|---|---|
| **github** | `GITHUB_TOKEN` | `~/.github.env` | `cargo-binstall` rate limits, Homebrew rate limits, gh CLI fallback | you don't bulk-binstall from GitHub releases (or use the gh-derive trick below) |
| **anthropic** | `ANTHROPIC_API_KEY` | `~/.anthropic.env` | Anthropic SDK, agents using `api.anthropic.com` directly | you only use Claude via Pro / Claude Code OAuth |
| **openai** | `OPENAI_API_KEY` | `~/.openai.env` | OpenAI SDK, Codex CLI in API mode | you only use Codex via ChatGPT login |
| **cloudflare** | `CLOUDFLARE_API_TOKEN` | `~/.cloudflare.env` | OpenTofu in `infra/`, Cloudflare MCP via API, R2/Pages | you don't deploy infra/ via OpenTofu (the Cloudflare MCP can use OAuth) |
| **huggingface** | `HF_TOKEN` | `~/.huggingface.env` | mlx-lm gated models, transformers | you don't pull gated models or private repos |

Plus `gh auth login` (browser flow) — required for the **GitHub MCP server** consumed by both Claude and Codex (`auth=gh` in `mcp-servers.txt`). gh stores its token in macOS keychain / Linux secret service, not in an env file.

## How tokens get loaded

```text
   Walk auth.sh         ─writes─►   ~/.<service>.env  (chmod 600)
                                          │
                                          │ sourced on every install run
                                          ▼
   install/_lib.sh  ◄─sources─  for f in ~/.*.env; do . "$f"; done
                                          │
                                          │ exported into the shell environment
                                          ▼
   install scripts see GITHUB_TOKEN, HF_TOKEN, etc. as env vars.

   Same files are also sourced by your shell profile so interactive
   sessions inherit them — no need to `source` manually after setup.
```

After setting a token, **open a new shell** (or `source ~/.<svc>.env`) to use it in your current session.

## Per-prompt UX

Each service prompt shows status, create-URL, scope hint, file path, and a "skip if" note. Then either `[k]eep / [u]pdate / [d]elete` (when set) or "Enter token / Enter to skip" (when empty). Tokens are masked everywhere — only the last 4 characters appear (e.g. `...mqTO`). Input is hidden via `stty -echo`.

```text
github (GITHUB_TOKEN)
  GitHub PAT (cargo-binstall, Homebrew rate limits, gh fallback)
  create:  https://github.com/settings/tokens
  scopes:  fine-grained no-permission (rate limits only) OR repo (private clones)
  skip if: you don't bulk-binstall from GitHub releases — or press G to derive from `gh auth token`
  file:    /Users/cade/.github.env
  status:  empty
  Enter GITHUB_TOKEN, [G] to derive from `gh auth token`, or Enter to skip:
```

After a `walk`, you get a tally:

```text
Summary
  set:      2
  updated:  0
  kept:     1
  deleted:  0
  skipped:  2
```

## The `gh`-derive trick (GITHUB_TOKEN)

`gh auth login` already stores a token in your OS keychain. Rather than maintain a second token, point `~/.github.env` at the keychain dynamically:

```sh
# ~/.github.env
export GITHUB_TOKEN="$(gh auth token 2>/dev/null)"
```

Now `cargo-binstall` etc. always see the current keychain token, and `gh auth refresh` automatically picks up everywhere.

The auth.sh prompt offers this with `[G]` when github is empty and `gh auth status` succeeds. Selecting it writes exactly that one-liner.

## Adding a new service

The registry is one constant in `install/auth.sh`. Add a row with:

```text
name|ENV_VAR|.env_file_basename|short description|create_url|scopes hint|skip-if hint
```

Example for adding OpenRouter:

```text
"openrouter|OPENROUTER_API_KEY|.openrouter.env|OpenRouter token (openrouter/ models)|https://openrouter.ai/keys|—|you don't use OpenRouter-routed models"
```

Now `bash auth.sh status`, `bash auth.sh openrouter`, and the walk all include it. No code changes needed.

## File security

- All env files are **chmod 600** (owner-only).
- Tokens are **never echoed** in plaintext — only masked tails.
- The bash glob `for _envfile in "$HOME"/.*.env` in `_lib.sh` errors silently if no files match (no leakage).
- A pre-push gitleaks hook (`home/dot_config/git/hooks/pre-push`) scans new commits for accidental token leakage before pushing — see [Troubleshooting](../usage/troubleshooting.md) if it ever blocks a push.
