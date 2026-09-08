---
title: Cade's Dotfiles
description: Set up a macOS or Linux machine, change managed configuration, and use the included development tools and agents.
---

My macOS and Linux development environment: shells, languages, editors, and agents. [Package lists](https://github.com/cadebrown/dotfiles/tree/main/packages) select the tools; [configuration templates](https://github.com/cadebrown/dotfiles/tree/main/home) set them up.

<nav class="quick-links" aria-label="Quick start tasks">
<a href="#set-up-a-machine">Install</a>
<a href="#change-a-setting">Configure</a>
<a href="#use-an-agent">Use an agent</a>
<a href="#find-tools-and-guides">Find a tool</a>
<a href="#update-or-troubleshoot">Update & fix</a>
</nav>

<figure class="setup-flow" aria-label="Two paths from repository sources to installed tools and configuration">
<div class="flow-lane">
<a class="flow-node" data-stage="source" href="/setup/packages/"><span class="flow-label">Package lists</span><code>packages/*</code><span>Homebrew, Cargo, npm, uv</span></a>
<svg class="flow-arrow" viewBox="0 0 24 24" aria-hidden="true"><path d="M2 12h18m-6-6 6 6-6 6" /></svg>
<a class="flow-node" data-stage="apply" href="/setup/bootstrap/"><span class="flow-label">Install and check</span><code>bootstrap.sh</code><span>Runs the installers</span></a>
<svg class="flow-arrow" viewBox="0 0 24 24" aria-hidden="true"><path d="M2 12h18m-6-6 6 6-6 6" /></svg>
<a class="flow-node" data-stage="result" href="/architecture/runtime-paths/"><span class="flow-label">On your machine</span><strong>Tools and runtimes</strong><span>Homebrew and local prefixes</span></a>
</div>
<div class="flow-lane">
<a class="flow-node" data-stage="source" href="/reference/managed-configuration/"><span class="flow-label">Configuration source</span><code>home/*</code><span>Shells, editors, agents</span></a>
<svg class="flow-arrow" viewBox="0 0 24 24" aria-hidden="true"><path d="M2 12h18m-6-6 6 6-6 6" /></svg>
<a class="flow-node" data-stage="apply" href="/setup/chezmoi/"><span class="flow-label">Render and apply</span><code>chezmoi apply</code><span>Uses this machine's settings</span></a>
<svg class="flow-arrow" viewBox="0 0 24 24" aria-hidden="true"><path d="M2 12h18m-6-6 6 6-6 6" /></svg>
<a class="flow-node" data-stage="result" href="/reference/managed-configuration/"><span class="flow-label">In your home directory</span><code>~/.zshrc, ~/.config/</code><span>Plus each agent's config</span></a>
</div>
<figcaption>Bootstrap runs both paths. After setup, you can apply configuration changes separately.</figcaption>
</figure>

## Set up a machine

From an interactive terminal:

```sh title="Install from a checkout"
git clone https://github.com/cadebrown/dotfiles ~/dotfiles
~/dotfiles/bootstrap.sh
```

Expect name/email prompts, installer progress, then a tool check. Linux runs without sudo; initial macOS Homebrew setup may request administrator authentication.

- [Choose a setup](/setup/choose-your-setup/) — Full is the default. Core narrows Python/Cargo tools; both use the same Homebrew list.
- [Shared home?](/setup/plat/) Configure PLAT isolation before installing.
- [Installation steps](/setup/bootstrap/) · [Sign in to services](/setup/auth/)

## Change a setting

Edit [the zsh source](https://github.com/cadebrown/dotfiles/blob/main/home/dot_zshrc.tmpl), inspect the diff, then apply:

```sh title="Edit → inspect → apply"
"${EDITOR:-vi}" ~/dotfiles/home/dot_zshrc.tmpl
chezmoi diff ~/.zshrc
chezmoi apply ~/.zshrc
exec zsh -l
```

The new shell loads the result. Edit sources under `home/` to retain changes across applies. Find other files in the [configuration map](/reference/managed-configuration/) or follow a [configuration recipe](/workflows/configuration-recipes/).

## Use an agent

With Codex installed and signed in:

```sh title="Start a review session"
cd ~/dotfiles
codex -p review
```

```text title="Example prompt"
Trace how DF_USE_PLAT changes the Node executable path.
Show the source files and line references, then give me a command
to inspect the result in my current shell. Do not change files.
```

The `review` profile is read-only. Expect source locations and an inspection command to run on the target machine.

[Choose an agent](/agents/) · [Codex profiles](/agents/codex/) · [Instructions](/agents/instructions/) · [Workflow examples](/agents/domain-workflows/)

## Find tools and guides

| I need to… | Start here |
| --- | --- |
| Find a tool or connection | [Packages](/reference/packages/) · [Skills](/reference/skills/) · [MCP servers](/reference/mcp/) |
| Understand how it fits together | [Architecture](/architecture/overview/) · [Paths](/architecture/runtime-paths/) |
| Configure my workspace | [Shell & editors](/workflows/shell-editor-terminal/) · [Environment variables](/reference/env-vars/) |
| Use local models or resume work | [Local AI](/usage/local-llm/) · [Durable tasks](/agents/durable-work/) |
| Add a feature | [Write the guide](/contributing/documentation/) · [Show it working](/contributing/demonstrations/) |

## Update or troubleshoot

| Command | Effect |
| --- | --- |
| `~/dotfiles/bootstrap.sh update` | Pull repository changes and install missing tools |
| `~/dotfiles/bootstrap.sh upgrade` | Update the repository and request package upgrades |
| `bash ~/dotfiles/install/verify-path.sh` | Check executable locations and PATH ordering |
| `bash ~/dotfiles/install/codex.sh check` | Check the managed Codex setup |

Search an error message or open [Troubleshooting](/troubleshooting/). See [Daily maintenance](/usage/updates/) for package and configuration updates.
