---
title: Skill workflows
description: Discover, select, author, and validate task-specific procedures.
---

## Select a skill because the task needs its procedure

A `SKILL.md` procedure may include scripts, references, templates, and assets. It does not install software, authenticate a service, or widen task authority.

| Need | Route | Evidence |
| --- | --- | --- |
| unfamiliar repository/runtime | `env-reconciler` | checked environment plan |
| browser UI | `browser-workbench` or Playwright | screenshots, trace, console/network evidence |
| native macOS app | `desktop-workbench` | live observation and reopened result |
| sustained/remote work | `long-running-work` + `df-task` | checkpoint, logs, artifacts |
| game/asset | `router`, then engine workflow | play slice and imported/rendered evidence |
| current APIs/libraries | `research` or `researcher` | dated primary sources and marked inference |

Read the selected skill fully. Keep project conventions in project instructions and reusable procedure detail in skills.

## Discover before duplicating

Use `find-skills` when asking whether a capability exists. If the name/source is known, inspect it with:

```bash
rg --files ~/.claude/skills ~/dotfiles/home/dot_claude/skills
```

Do not create a broadly named skill for a one-off selector or project-local source list. A reusable skill needs a stable input/output contract.

## Author at the correct ownership layer

Use `skill-creator` for a new Codex skill. Decide ownership first:

```text
Repository-controlled reusable procedure -> home/dot_claude/skills/<name>/SKILL.md
Upstream/community installed procedure    -> packages/agent-skills.txt
```

Never assign both. Keep unique project methods in a project `AGENTS.md`, script, or README.

## Write a procedure that can be checked

Include trigger, initial observation, source of truth, steps, prerequisite diagnostics, and evidence boundary:

```md
## Before editing
Read the schema and identify the owned fixture directory.
## Procedure
Run the repository normalizer, then validate every changed fixture.
## Evidence boundary
Parsing confirms schema conformance; it does not prove remote acceptance.
```

Do not embed credentials, uncontrolled recursive deletion, or unverified product claims.

## Validate behavior, not prose alone

Run representative isolated tasks with fixed inputs, model, effort, and tools; retain artifacts plus an independent check. Use [`writing-skills`](../../home/dot_claude/skills/writing-skills/SKILL.md) when a baseline comparison is warranted. Parsing Markdown proves shape only. For Codex capability assumptions, consult [official skills documentation](https://developers.openai.com/codex/skills/) and test the local client after installation.
