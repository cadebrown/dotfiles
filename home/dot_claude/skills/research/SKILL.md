---
name: research
description: Research a topic thoroughly using web search before answering. Use when encountering unfamiliar APIs, libraries, or domains.
disable-model-invocation: true
user-invocable: true
allowed-tools: WebSearch, WebFetch, Read, Grep, Glob
argument-hint: "<topic or question>"
---

Research the following topic thoroughly before providing an answer: $ARGUMENTS

Steps:
1. Search the web for current, authoritative sources (official docs, RFCs, papers)
2. Read the most relevant pages in full
3. If the topic relates to code in the current project, cross-reference with the codebase
4. Synthesize findings — lead with the answer, then supporting detail
5. Cite sources with URLs
6. Flag anything uncertain, conflicting, or rapidly changing
