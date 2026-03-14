# Docs and hosting

The documentation site at [dotfiles.cade.io](https://dotfiles.cade.io) is built with [mdBook](https://rust-lang.github.io/mdBook/) and deployed automatically on every push to `main`.

## How it works

```
push to main
  → Cloudflare Pages detects the push
  → runs infra/cloudflare/build.sh
    → installs cargo-binstall + mdbook
    → runs `mdbook build docs`
  → deploys docs/book/ to dotfiles.cade.io
```

The entire pipeline is defined in two files:

- **`infra/cloudflare/main.tf`** -- OpenTofu config that creates the Cloudflare Pages project, binds the custom domain (`dotfiles.cade.io`), and sets up the CNAME DNS record
- **`infra/cloudflare/build.sh`** -- build script that runs inside Cloudflare's build environment (installs mdbook via cargo-binstall, then builds)

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
tofu plan     # preview changes
tofu apply    # create/update Pages project + DNS
```

`terraform.tfvars` holds `account_id` and `github_owner` -- gitignored, copy from `terraform.tfvars.example` on each machine.

### What OpenTofu creates

| Resource | Purpose |
| --- | --- |
| `cloudflare_pages_project` | Pages project linked to GitHub, runs `build.sh` on push |
| `cloudflare_pages_domain` | Binds `dotfiles.cade.io` to the project |
| `cloudflare_record` | CNAME `dotfiles` → `<project>.pages.dev` (proxied) |

This same pattern (OpenTofu + Cloudflare Pages + mdBook) is used across other projects at `cade.io`.
