---
title: Claude Code configuration and hooks
description: Change managed Claude Code configuration, plugin hooks, and status evidence.
---

## Know which layer owns the behavior

Edit the owner. Changes in `~/.claude/plugins/` disappear at the next reconciliation.

| Concern | Source | Inspect |
| --- | --- | --- |
| Shared instructions | [`agents-common.md`](../../home/.chezmoitemplates/agents-common.md), [`CLAUDE.md.tmpl`](../../home/dot_claude/CLAUDE.md.tmpl) | `chezmoi diff` |
| Settings/status line | [`settings.json`](../../home/dot_claude/settings.json), [`executable_statusline.sh`](../../home/dot_claude/executable_statusline.sh) | `jq . ~/.claude/settings.json` |
| Interactive model default | [`claude-defaults.sh`](../../home/.chezmoitemplates/claude-defaults.sh), [`.zshrc`](../../home/dot_zshrc.tmpl), [`.bashrc`](../../home/dot_bashrc.tmpl) | `type claude` |
| Plugin declarations | [`claude-plugins.txt`](../../packages/claude-plugins.txt) | `claude plugin list --json` |
| Hook scopes | [`claude-hook-scope.py`](../../install/claude-hook-scope.py), [`hook-scope.sh`](../../home/dot_claude/executable_hook-scope.sh) | `jq . ~/.claude/hook-scope-state.json` |

The shared voice arrives through Claude’s `cade` output style. Project instructions still own project build, test, and deployment work.

The user setting selects `claude-opus-5[1m]` at medium effort. On NVIDIA hosts,
server-managed settings select Sonnet again at startup even though Opus remains
allowed. The interactive shell launcher therefore supplies `--model
claude-opus-5[1m] --effort medium` for session commands. Explicit model or
effort flags win independently; management commands such as `claude mcp`,
`claude auth`, `claude plugin`, `claude doctor`, and `claude update` bypass the
launcher defaults unchanged. Resumed sessions retain the model stored in their
transcript.

## Plugin and hook lifecycle

`install/claude.sh` installs the CLI, refreshes declared marketplaces, reconciles plugins, and regenerates narrow hook gates. After an intentional direct plugin update:

```bash
bash ~/dotfiles/install/claude.sh sync-hooks
jq . ~/.claude/hook-scope-state.json
```

Expected result: generated scope and drift state are printed. The generator narrows reviewed Hookify and Lean gates; upstream implementation drift restores the full upstream check and records a warning. Hookify still follows rule globs; Lean prompt checks remain for `/lean4:` and Bash checks use physical ancestor project markers.

## Observe overhead without inventing a speedup

The status line stores aggregate transcript statistics and offsets under `${XDG_CACHE_HOME:-~/.cache}/claude-statusline`, not transcript text. It incrementally handles appends; replacement, truncation, equal-size timestamp changes, and boundary-fingerprint changes invalidate cache state. This is not an end-to-end latency claim.

The shared chezmoi guard uses fresh ownership observation and resolves lexical/physical aliases. Third-party adapters fail open if its executable is unavailable; inspect the deployed helper before treating it as enforcement. Preserve inputs, cache state, versions, and focused test evidence. See [hook overhead](../usage/agent-overhead.md).

## Practical routes

- [`researcher`](../../home/dot_claude/agents/researcher.md): source-grounded, read-heavy work; no editor tools.
- [`reviewer`](../../home/dot_claude/agents/reviewer.md): adversarial review after implementation; no edits.
- [`df-agent-doctor`](../../home/dot_local/bin/executable_df-agent-doctor): post-bootstrap component check; not account, GUI, or running-session proof.

Before changing schemas, check current [hooks](https://code.claude.com/docs/en/hooks) and [plugins](https://code.claude.com/docs/en/plugins) documentation.
