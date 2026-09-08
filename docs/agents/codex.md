---
title: Codex profiles and focused roles
description: Select generated session profiles and bounded child roles.
---

## Pick a session profile for the work

Profiles in [`home/dot_codex/`](../../home/dot_codex/) apply when a session starts; they do not retrofit its tool inventory.

| Command | Use | Limit |
| --- | --- | --- |
| `codex` | ordinary implementation | existing sessions retain their inventory |
| `codex -p deep` | demanding implementation or research | wake prevention needs active-client support |
| `codex -p review` | read-only exploration | it does not inspect remote state |
| `codex -p fast` | quick low-risk iteration | Luna serves the whole session |
| `codex -p context` | context-management experiment | support depends on client, account, and rollout |

`browser`, `creative`, `desktop`, `research`, `math`, `cloud`, and `workspace` come from the MCP registry; choose one only for its needed tool surface. `tools-all` intentionally exposes every declared server. See [AI workbench profiles](../usage/ai-workbench.md).

```bash
DF_MCP_PROFILES=research:math bash ~/dotfiles/install/codex.sh sync-config
bash ~/dotfiles/install/codex.sh check
```

Expected result: generated configuration passes its check for future sessions. Run sync without `DF_MCP_PROFILES` to restore core activation, then restart the harness after changing a pin, environment, or profile.

## Delegate only an independent bounded unit

Role sources are [`home/dot_codex/agents/`](../../home/dot_codex/agents/); tool scope is [`packages/codex-agent-tools.json`](../../packages/codex-agent-tools.json). Roles are efficiency choices, not security boundaries.

| Role | Good fit |
| --- | --- |
| `extractor` | facts from specified inputs |
| `coder` | exact mapping in named files |
| `explorer` | bounded repository trace |
| `researcher` | current primary-source question |
| `patcher` | bounded behavior contract |
| `verifier` | prescribed checks and edges |
| `reviewer` | adversarial final review |

`extractor` and `coder` use Luna/low; `explorer`, `researcher`, `patcher`, and `verifier` use Terra/medium. `reviewer`, `default`, and `worker` inherit the parent. Those are local manifests, not permanent product guarantees.

## Write a brief the child can finish

```text
Use patcher. Cwd: /absolute/project. Own only src/config.ts and its existing
config tests. Add optional positive-integer timeoutMs, default 30000; reject
zero, negative, fractional, and nonnumeric values through the current API.
Preserve other defaults. Run the existing config tests, log to /tmp/config-check.log,
and return changed files, behavior, checks, artifact path, and unresolved items.
Do not commit or edit other files.
```

Supply scope, contract, acceptance checks, and artifact path. For extraction, give an output schema and reconciliation count; for `coder`, give the exact replacement and require it to report ambiguity. Use a direct command for a one-command transformation; the parent integrates and decides whether independent review is warranted.

## Official reference

The role design follows [Codex subagents documentation](https://developers.openai.com/codex/subagents/). Verify active-client model and role support before relying on a local manifest in another Codex surface.
