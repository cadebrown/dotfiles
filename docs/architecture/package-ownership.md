---
title: Package ownership and convergence
description: Which manifest owns each class of tool and how installers converge safely.
---

## One owner per executable

Package lists are declarations, not a list of commands to run manually. A
package should have one manager owner so upgrades and PATH selection stay
predictable.

| Owner | Manifest | Intended contents |
|---|---|---|
| Homebrew | `packages/Brewfile` | system tools, formulae, casks, development SDKs |
| cargo-binstall | `packages/cargo.txt` | release-binary Rust CLIs |
| npm under nvm | `packages/npm.txt` | Node CLI tools, Codex, browser CLIs |
| uv tool | `packages/pip.txt` | isolated Python CLI environments |
| Go | `packages/go.txt` | Go command-line tools |
| agent config | package lists beside installers | plugins, extensions, MCP endpoints, skills |

The Cargo manifest states why it excludes tools without release binaries
([source](https://github.com/cadebrown/dotfiles/blob/main/packages/cargo.txt#L1)).
The npm manifest similarly makes Codex npm-owned while `install/codex.sh` owns
its configuration and health check
([source](https://github.com/cadebrown/dotfiles/blob/main/packages/npm.txt#L14)).

## How convergence works

Bootstrap installs Homebrew before language runtimes, then invokes Python,
Node, Rust, Go, Julia, Lean, and TeX in a fixed order
([source](https://github.com/cadebrown/dotfiles/blob/main/bootstrap.sh#L535)).
The Node installer keeps nvm's selected binary ahead of a Homebrew Node, because
native npm add-ons are tied to the Node ABI
([source](https://github.com/cadebrown/dotfiles/blob/main/install/node.sh#L200)).
The Python installer puts each CLI tool in its own uv environment, while the
managed `python` wrapper uses one interactive environment
([source](https://github.com/cadebrown/dotfiles/blob/main/install/python.sh#L76)).

When adding a tool, identify the executable, the owner, the supported platform,
and a meaningful health check before changing a list. Do not install the same
CLI with both Homebrew and npm, pip and uv, or Cargo and a tap merely because
both work. Use [package setup](/setup/packages/) for current commands and
[updates](/usage/updates/) for routine reconciliation.

```bash
# Inspect declared ownership before changing it.
rg -n '(^|/)tool-name([ @#]|$)' packages install home
./tests/ci.sh full
```
