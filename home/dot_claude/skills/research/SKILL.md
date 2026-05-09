---
name: research
description: Research a topic thoroughly using web search before answering. Use when encountering unfamiliar APIs, libraries, frameworks, or domains, or when training data may be stale.
disable-model-invocation: true
user-invocable: true
allowed-tools: WebSearch, WebFetch, Read, Grep, Glob
argument-hint: "<topic or question>"
---

Research the following topic thoroughly before providing an answer: $ARGUMENTS

## Process

1. **Search broadly first** — multiple queries with different phrasings. Identify candidate sources.
2. **Fetch the most authoritative pages in full.** Not summaries — the actual docs.
3. **Cross-reference with the codebase** if the topic relates to current work — what's already used? What conventions are in place?
4. **Synthesize** — lead with the answer, then supporting detail. Cite each non-obvious claim with a URL.
5. **Flag uncertainty** — anything that conflicts between sources, anything rapidly changing, anything I couldn't verify.

## Source quality (highest → lowest)

1. **Primary source** — official docs, RFCs, specs, source code, papers
2. **Vendor blog / changelog / GitHub release notes** — if recent and signed by maintainer
3. **High-trust secondary** — well-known author's blog, conference talk transcript, Wikipedia (for stable topics)
4. **Stack Overflow / Reddit** — accept only as a pointer; verify the underlying claim against (1) or (2)
5. **AI-generated content / SEO blogs** — ignore unless they cite primary sources you can verify

When sources disagree: prefer (1) and (2) over (3) and (4). When (1) is silent on something common practitioners do, say so.

## Recency

Note the date on every fetched page. APIs and best practices move fast — a 2022 blog post about a 2024 framework version is suspect. If the source is undated, treat it as suspect. Flag anything where recency matters and the source is old.

## Output format

- **Answer first** — the direct response to the question, in 1–3 sentences.
- **Evidence** — bullets with quote / paraphrase + URL for each non-obvious claim.
- **Caveats** — anything uncertain, conflicting, or out of date.
- **Suggested next step** — only if the user is mid-task and a concrete next action is obvious.

## Red flags — pause and re-research

- Multiple sources directly contradict and you can't tell which is right.
- The "answer" depends on a version, OS, or context the user hasn't specified.
- The most authoritative source is over 2 years old in a fast-moving area.
- You're tempted to say "I think" instead of citing.
