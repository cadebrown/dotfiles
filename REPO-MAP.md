# Repo Map

## Core Flow

- [bootstrap.sh](/Users/cade/dotfiles/bootstrap.sh): top-level orchestrator for `install`, `update`, and `upgrade`
- [install/_lib.sh](/Users/cade/dotfiles/install/_lib.sh): central contract for path variables, PLAT detection, logging, and shared helpers

## Main Subsystems

- [home/](/Users/cade/dotfiles/home): chezmoi-managed dotfile sources that render into `~/`
- [install/](/Users/cade/dotfiles/install): idempotent installers and machine setup scripts
- [packages/](/Users/cade/dotfiles/packages): declarative package ownership across Brew, Cargo, npm, pip, and Claude-related lists
- [tests/](/Users/cade/dotfiles/tests): Docker-based bats suite for bootstrap validation
- [docs/](/Users/cade/dotfiles/docs): mdBook source for the docs site
- [infra/cloudflare/](/Users/cade/dotfiles/infra/cloudflare): OpenTofu for docs hosting

## Authoritative Files

- [install/_lib.sh](/Users/cade/dotfiles/install/_lib.sh): path and helper definitions
- [home/dot_zprofile.tmpl](/Users/cade/dotfiles/home/dot_zprofile.tmpl): zsh login environment
- [home/dot_bash_profile.tmpl](/Users/cade/dotfiles/home/dot_bash_profile.tmpl): bash login environment
- [packages/Brewfile](/Users/cade/dotfiles/packages/Brewfile): Homebrew package ownership
- [packages/cargo.txt](/Users/cade/dotfiles/packages/cargo.txt): Rust tool ownership
- [bootstrap.sh](/Users/cade/dotfiles/bootstrap.sh): bootstrap step order and `DF_DO_*` flags

## Common Task Entry Points

- Add or change installer behavior: [install/](/Users/cade/dotfiles/install) plus [bootstrap.sh](/Users/cade/dotfiles/bootstrap.sh)
- Add or move a package: [packages/](/Users/cade/dotfiles/packages)
- Change deployed shell behavior: [home/](/Users/cade/dotfiles/home)
- Change docs: [docs/](/Users/cade/dotfiles/docs), not `docs/book/`
- Validate setup changes: [tests/run.sh](/Users/cade/dotfiles/tests/run.sh)

## Frequent Mistakes To Avoid

- Editing generated files in `docs/book/`
- Editing deployed dotfiles in `~/` instead of sources in `home/`
- Duplicating a tool across multiple package layers
- Hardcoding machine-specific paths in chezmoi templates
- Changing install paths without understanding `PLAT` isolation
