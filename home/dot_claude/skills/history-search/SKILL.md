---
name: history-search
description: Search past coding-agent sessions (Claude Code, Codex, opencode, pi transcripts) with hybrid lexical+semantic search via cass. Use when the user references past work ("we did this before", "that bug from last month"), before re-debugging something that feels familiar, or to recover the reasoning behind an old decision.
allowed-tools: Bash, Read
argument-hint: "<what to look for in past sessions>"
---

Search past agent sessions for: $ARGUMENTS

## Tool

`cass` indexes session history from every agent on this machine (Claude Code,
Codex, opencode, pi) into one hybrid BM25+vector index. It is read-only over
transcripts; the index updates continuously via the `cass watch` daemon.

## Commands

```sh
# Hybrid search, machine-readable output (preferred for agents)
cass search "borrow checker workaround in the sim engine" --robot

# Token-budgeted, cited context bundle — best when you need the actual
# content, not just hits
cass pack "decision about chezmoi PLAT layout"

# Narrow by agent or recency when the query is ambiguous
cass search "MCP auth" --robot --agent claude-code
cass search "profile migration" --robot --days 30

# Read a specific hit in full (ids come from search output)
cass show <hit-id>

# If results look stale or empty
cass health --robot   # index status; daemon may still be backfilling embeddings
```

## Method

1. Start with `cass search "<query>" --robot` — scan titles/snippets.
2. For promising hits, `cass pack` or `cass show` to pull real content.
3. Cite what you use: mention the session date/agent so the user can locate it.
4. If nothing relevant: say so and move on — do not pad with weak matches.
5. Semantic results depend on the embedding backfill; if `fallback_mode` says
   "lexical", note that recall may be keyword-limited right now.

## Boundaries

- Read-only. Never write to transcript dirs or the cass index.
- Durable conclusions worth keeping go to `~/kb` (knowledge base) or
  auto-memory — not back into history.
