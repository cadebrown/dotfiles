---
name: research
description: Current, source-grounded research for unfamiliar APIs, libraries, standards, tools, products, or domains. Use before implementation when local knowledge may be stale or incomplete.
---

# Research

Use this skill when correctness depends on external facts or current documentation.

## Source Order

1. Primary documentation, specifications, release notes, source repositories, or papers.
2. Maintainer-authored examples and official migration guides.
3. High-signal community reports only when primary sources are silent.

## Workflow

1. Define the decision.
   State what implementation choice or factual question the research must answer.

2. Search current sources.
   Prefer official docs and upstream repositories. For OpenAI products, use official OpenAI sources first.

3. Read enough to constrain the decision.
   Stop once the evidence determines the next implementation step.

4. Cross-reference local code.
   Check whether the repository already uses the API, pattern, or dependency.

5. Separate fact from inference.
   Label conclusions that are synthesized from sources rather than directly stated.

6. Cite sources.
   Include URLs for any external facts that influenced the recommendation or code.

## Output Contract

Return:
- decision-relevant facts
- source URLs
- local code implications
- uncertainty or conflicting evidence
