# Docs and hosting

The documentation site at [dotfiles.cade.io](https://dotfiles.cade.io) is built with [mdBook](https://rust-lang.github.io/mdBook/) and deployed automatically on every push to `main`.

## How it works

```
push to main
  → Cloudflare Pages detects the push
  → runs infra/cloudflare/build.sh
    → downloads pinned mdbook + mdbook-mermaid binaries
    → runs `mdbook build docs`
  → deploys docs/book/ to dotfiles.cade.io
```

The entire pipeline is defined in two files:

- **`infra/cloudflare/main.tf`** -- OpenTofu config that creates the Cloudflare Pages project, binds the custom domain (`dotfiles.cade.io`), and sets up the CNAME DNS record
- **`infra/cloudflare/build.sh`** -- build script that downloads pinned prebuilt binaries directly from GitHub Releases, then builds

## Local development

```sh
mdbook serve docs/ --open    # live reload at localhost:3000
```

Changes to any `.md` file under `docs/` are reflected instantly in the browser.

## Doc structure

```
docs/
├── book.toml        # mdBook config (title, theme, repo link)
├── SUMMARY.md       # Table of contents / sidebar nav
├── intro.md         # Homepage
├── setup/
│   ├── bootstrap.md # Bootstrap instructions per platform
│   ├── chezmoi.md   # Dotfile management with chezmoi
│   └── packages.md  # Package layers (cargo, npm, pip, brew)
├── usage/
│   ├── updates.md   # Day-to-day workflow
│   └── troubleshooting.md
└── infra/
    └── docs-and-hosting.md   # This page
```

## Infrastructure management

The Cloudflare Pages project is managed with OpenTofu (open-source Terraform):

```sh
cd infra/cloudflare
export CLOUDFLARE_API_TOKEN=...
tofu plan -out=tfplan  # write a reviewable plan
tofu show tfplan       # inspect the exact saved plan
tofu apply tfplan      # apply only that reviewed plan
```

`terraform.tfvars` holds `account_id` and `github_owner` -- gitignored, copy from `terraform.tfvars.example` on each machine.

### What OpenTofu creates

| Resource | Purpose |
| --- | --- |
| `cloudflare_pages_project` | Pages project linked to GitHub, runs `build.sh` on push |
| `cloudflare_pages_domain` | Binds `dotfiles.cade.io` to the project |
| `cloudflare_dns_record` | CNAME `dotfiles.cade.io` → `<project>.pages.dev` (proxied) |

### Cloudflare provider v5 migration

Commit `f8a35b6` is the latest-v4 checkpoint required by Cloudflare's v5 migration path. Before the first v5 plan against an existing deployment, back up the remote state, check out that commit, run `tofu init -upgrade` and a refresh-only plan, then return to the v5 configuration and review a saved plan. CI validates configuration only; it never plans or applies Cloudflare changes.

This same pattern (OpenTofu + Cloudflare Pages + mdBook) is used across other projects at `cade.io`.
