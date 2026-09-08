---
name: writing-skills
description: Improve skill discovery and behavior using realistic tasks in the target harness and model. Use when a skill misroutes, a workflow needs validation, or instruction revisions need comparison.
---

# Improve skills through actual use

Use the current harness's skill-creation guidance for packaging. In Codex,
prefer its system `skill-creator`; other harnesses may expose their own authoring
skill. This workflow has no required superpowers dependencies.

Start from a real task and the decision the skill should improve. Preserve
the user's product, scope, and authorization. Keep the entrypoint focused on
non-obvious capability routing and constraints; put optional details in linked
references. Remove prescribed output templates when the task's artifact already
communicates the result.

Make discovery precise before expanding the body. Describe the operation the
skill enables and when it helps; broad subject names can attract unrelated
tasks. Check a representative request and a nearby request that should route
elsewhere. Where skills overlap, distinguish their operations or outputs while
preserving useful capabilities. A specialist debugging skill should not load
merely because an ordinary build runs a binary.

Inspect the target harness's actual discovered catalogue, not just source
frontmatter. In Codex, `codex -C /project debug prompt-input 'request'` shows
the model-visible instructions and skill descriptions without running a model.
This can reveal duplicate names, truncated descriptions, stale paths, or an
instruction file that never loaded. It does not prove correct skill selection;
that requires observing a real task run.

Choose evaluation proportional to the change. Frontmatter and link validation
catch packaging defects. A meaningful workflow change needs a realistic task
run with the intended model, tools, and representative input. A small wording
fix does not need an elaborate benchmark.

The installed `plugin-eval` CLI supports native Codex execution:

```bash
plugin-eval analyze /absolute/path/to/skill --format json --output /tmp/skill-analysis.json
plugin-eval init-benchmark /absolute/path/to/skill --model gpt-6-astra --output /tmp/benchmark.json
```

Edit the generated config before running it: use a small isolated input
workspace, concrete user requests, actual output paths, and verifiers that
exercise the result. Keep run artifacts outside the skill source. Then run:

```bash
plugin-eval benchmark /absolute/path/to/skill --config /tmp/benchmark.json --model gpt-6-astra
```

Benchmark commands invoke a real model and consume account usage. A static
analysis score is not a behavioral result. Record the model, reasoning settings,
skill revision, raw logs, observed usage, and artifact/verifier results. Comparing
revisions requires the same task and model; a Claude run does not establish
Astra behavior. Before interpreting a failed score, distinguish tool/environment
failure from skill behavior.

For paired global-instruction comparisons, the dotfiles checkout includes
`tests/agent_behavior.py` and `tests/fixtures/agent-behavior/README.md`.
The helper snapshots both instruction variants, verifies actual loading in
isolated Codex homes, holds the model and settings fixed, and preserves native
resume sessions and output evidence. Start with a small representative pair;
repeat only when the observed difference warrants it. Treat artifact checks,
manual factual or visual review, and tool failures as separate findings.

For complex skills, a fresh independent agent can forward-test the skill in an
isolated workspace alongside useful local work. Give it the task and inputs,
not the intended answer. Check the produced artifact, including visual inspection
when appropriate. Keep fixes tied to observed failures; avoid accumulating rules
for hypothetical edge cases. Commit or publish only when the user requests it.
