---
name: research-reader
description: Perform source-grounded technical reading before making implementation decisions. Use when a user asks for architecture understanding, design tradeoffs, external documentation research, or a summary that must be anchored in primary sources.
---

# Research Reader

Use this skill when reading quality matters more than immediate editing.

## Goals

- Gather evidence from primary sources first
- Distinguish observed facts from inference
- Compress findings into implementation-relevant conclusions

## Workflow

1. Prefer primary sources.
   Use official docs, local source, standards, schemas, and upstream repos before secondary commentary.

2. Read enough to answer the real decision.
   Do not over-collect. Stop when the implementation choice is constrained.

3. Separate facts from inference.
   State which claims come directly from sources and which are your synthesis.

4. Translate research into action.
   End with implications for configuration, implementation, testing, or risk.

## Output Contract

Return:
- the key facts
- the relevant source locations
- the practical implication for the current task

Avoid long background summaries that do not change the next step.
