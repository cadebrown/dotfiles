---
name: math-lookup
description: Look up mathematical reference data from authoritative sources — integer sequences (OEIS), L-functions/number fields (LMFDB), reviews (zbMATH Open), DOI→BibTeX, constant identification via PSLQ, and Lean/Mathlib theorem search (LeanSearch/Loogle). Use when identifying a sequence or constant, checking whether a result/object is known, fetching citations, or searching Mathlib from outside a Lean session.
allowed-tools: Bash, Read, WebFetch
argument-hint: "<sequence, constant, object, or theorem to look up>"
---

# math-lookup

Zero-install lookups against the canonical math databases. Prefer these over
web search — they are exact, citable, and JSON-native. `xh` and `jq` are
installed; `curl` works everywhere.

## OEIS — integer sequences

Always check OEIS before conjecturing about a sequence.

```bash
xh 'https://oeis.org/search' q==1,1,2,5,14,42 fmt==json | jq '.results[:3] | .[] | {number, name}'
# by A-number:
xh 'https://oeis.org/search' q==id:A000108 fmt==json | jq '.results[0] | {name, formula: .formula[:3], comment: .comment[:2]}'
```

The `mathlas` MCP's `identify_sequence` does exact OEIS matching too.

## LMFDB — L-functions, modular forms, number fields, elliptic curves

```bash
# REST API: JSON, 100 results/request. Browse schema at lmfdb.org/api
xh 'https://www.lmfdb.org/api/ec_curvedata/?rank=i2&_format=json&_max=5' | jq '.data[] | {label: .lmfdb_label, rank}'
```

## FindStat — combinatorial statistics

```bash
xh 'https://www.findstat.org/api/StatisticsDatabase/' fields==Identifier limit==10 | jq '.included.Statistics | keys[:10]'
```

## zbMATH Open — reviews/metadata (free REST)

```bash
xh 'https://api.zbmath.org/v1/document/_search' search_string=='an:1234.56789' | jq '.result[:2]'
# or by query: search_string=='ti:"perfectoid spaces" & py:2012'
```

## DOI / arXiv → BibTeX

```bash
curl -sLH "Accept: application/x-bibtex" "https://doi.org/10.1007/BF01231188"
# arXiv: use the arxiv MCP for search + LaTeX source; for a quick BibTeX:
xh 'https://arxiv.org/abs/2601.07421' | rg -o 'citation_[a-z]+" content="[^"]+"' | head -8
```

## Constant identification (inverse symbolic calculation)

Given a numeric constant, find a closed form. Two routes:

```bash
# mpmath PSLQ (works in any uv project with mpmath):
uv run --with mpmath python -c "
from mpmath import mp, pslq, mpf, pi, e, sqrt, log
mp.dps = 50
x = mpf('3.1462643699419723423291350657155704455124771291873')
print(pslq([x, 1, pi, e, sqrt(2), log(2)], tol=mp.mpf(10)**-40))"
```

The `mathlas` MCP's `identify_constant` runs PSLQ at 50 digits against a
constant library. PARI's `lindep` is the third option (`command gp` — bare
`gp` is aliased to git push).

## Lean/Mathlib search from outside a Lean session

Inside a Lean project, prefer the `lean-lsp` MCP tools. Otherwise:

```bash
# Loogle — type-pattern search:
xh 'https://loogle.lean-lang.org/json' q=='Real.sqrt (_ * _)' | jq '.hits[:5] | .[] | {name, module}'
# LeanSearch — natural language (web UI at leansearch.net; API shape may drift):
xh POST 'https://leansearch.net/api/search' query=='sum of first n odd numbers' num_results:=5 | jq '.[:3]'
```

## Prover escalation (pointers, not recipes)

Own tactics → `grind` → `/lean4:prove` / `/lean4:autoprove` (plugin cycle) →
external prover APIs: Aristotle (`aristotlelib`, key via `bash
install/auth.sh aristotle`) or Aleph (`alephprover`, `bash install/auth.sh
aleph`), both per-project pip installs. Apply the proof gate from
math-common.md to anything they return.
