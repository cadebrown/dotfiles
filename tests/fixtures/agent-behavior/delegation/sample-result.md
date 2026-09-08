# Delegation sample: 2026-09-08

One paired run with Codex CLI 0.153.4, an Astra/xhigh parent, the same synthetic
inputs, and the same available source role files. Both variants had isolated
configuration, no configured MCPs/plugins, web search disabled, and at most two
children. The candidate ran first. This is a routing and correctness sample,
not a controlled estimate of production savings.

| Observation | Existing instructions | New Codex routing instructions |
|---|---|---|
| Log extraction | Generic child, Astra/xhigh | `extractor`, Luna/low, fresh brief |
| Exact event-field rename | Generic child, Astra/xhigh | `coder`, Luna/low, fresh brief |
| Retry behavior repair | Parent Astra/xhigh | Parent Astra/xhigh |
| External checks | 5/5 passed | 5/5 passed |

Both runs produced the exact 2,400-line / 73-error summary, migrated generated
event payloads correctly, preserved protected inputs, and passed independent
retry-state checks. Inspection confirmed that both retry implementations store
capped per-job delays, avoiding unbounded integer growth after reaching the cap.
The Terra `patcher` role was available but not selected in this sample.

Native session counters reported the following cumulative usage. Input includes
cached input; output includes reasoning output, so neither subset should be
added again. These counters are not a ChatGPT billing receipt.

| Run / session | Model | Input | Cached input | Output |
|---|---|---:|---:|---:|
| Existing / parent | Astra | 123,776 | 103,424 | 3,593 |
| Existing / log child | Astra | 157,106 | 134,272 | 1,807 |
| Existing / code child | Astra | 113,637 | 106,752 | 1,271 |
| New / parent | Astra | 214,030 | 189,952 | 4,478 |
| New / log child | Luna | 207,120 | 165,376 | 1,711 |
| New / code child | Luna | 101,245 | 85,760 | 1,419 |

The new instructions selected the intended cheaper models, but this run did
not demonstrate fewer raw tokens. Its parent performed more verification calls,
including correcting a verification regex that initially rejected continuation
lines. The Luna extractor initially tried the wrong relative log path and used
several separate calls to construct its JSON artifact. Useful follow-up
experiments should supply an explicit working directory and exact paths, write
structured output directly from a parser, and measure representative larger
jobs. Do not infer a guaranteed improvement from the role names or one pair.
For trivial deterministic work, direct CLI filtering remains the preferred path.

The result establishes model selection and local artifact correctness. It does
not validate live web scraping, the later generated MCP/plugin scopes, hosted
ChatGPT Work, or Terra implementation quality. Those need separate exercises.

Native parent task IDs for provenance:

- Existing: `01a08228-8ff2-7720-905d-91ab81b2b0b0`
- New: `01a08224-3a24-7870-aa88-f155b46a06ba`

The experiment manifest records instruction, role, configuration, and input
hashes. Source role files were copied before the final explicit web-search and
plugin-discovery settings; the isolated test already disabled web search and
had no plugins. Reproduce with the commands in the parent fixture README,
review native child sessions as well as CLI JSON output, and consult the
[current Codex pricing](https://learn.chatgpt.com/docs/pricing) before translating
reported usage into a cost estimate.

## Follow-up defaults sample

A second pair used the final focused role settings with the previous Astra-only
routing instructions as the baseline and the new all-parent routing policy as
the candidate. Both variants had the same upgraded role snapshots, tool-output
and skill-catalog limits, model, inputs, and isolated tool configuration. This
pair therefore compares the instruction revisions; it does not isolate the
effect of the new role budgets. The candidate again ran first. Both selected
Luna/low `extractor` and `coder` children and passed all five external checks.

The harness now records elapsed time and native usage automatically. These sums
include each parent and its two children, with each session counted once:

| Variant | Input | Cached input (subset) | Output | Elapsed seconds |
|---|---:|---:|---:|---:|
| Previous routing | 439,861 | 369,280 | 8,356 | 196.274 |
| New routing | 516,213 | 450,816 | 8,084 | 174.827 |

The candidate finished sooner and used fewer uncached input and output tokens,
but more total tokens. One sequential pair cannot establish reliable latency or
cost savings. Billing depends on the model and treatment of cached tokens;
these are native usage counters, not billed costs.

Parent task IDs:

- Previous routing: `01a0824d-b671-7042-872b-ed79684cf6fe`
- New routing: `01a08247-8906-7bf0-b9f9-b0ef5d0f5527`

Live configuration readback confirmed Astra/xhigh remained the parent, all
seven generated role files were mode `0600`, the six efficiency roles disabled
further agents and plugin discovery, and their MCP selections matched the
manifest. This confirms generation and loading; it does not establish a shell
security boundary or behavior for every integration.

A separate live smoke explicitly selected `verifier` as Terra/medium with an
Astra/xhigh parent. It ran the prescribed existing check, wrote its report, and
preserved source and check files. The first attempt encountered an unwritable uv
cache; the same child retried successfully with a temporary cache and recorded
both attempts. The experiment harness now places uv's cache under its writable
temporary directory. All five external maintenance checks also passed after
the smoke. Parent task: `01a0824f-80e0-7431-8323-89bdb1008d0d`.
