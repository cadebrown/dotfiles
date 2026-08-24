# Scientific review

`scientific-review` is the shared-skill workflow for an auditable literature
review, manuscript check, or public peer-review analysis. Its source is
`home/dot_claude/skills/scientific-review/`;
chezmoi applies it to the shared agent-skill tree.

Use it when the answer needs an explicit claim-evidence matrix, source records,
reproduction status, or the distinction between a formal proof and weaker
evidence. It complements `research` for web-grounded investigation and
`math-lookup` for exact mathematical databases.

## Research record

Each conclusion-changing source records a canonical identifier, query,
retrieval date, version, license/access status, and either the raw response or
its checksum. Use DOI/arXiv/PMID/PMCID/OpenReview/dataset DOI identifiers rather
than URLs alone. `references/evidence-record.md` in the skill defines the review
matrix.

## Tool boundaries

- Asta and arXiv handle discovery and source retrieval; Crossref, OpenAlex, and
  DataCite resolve authoritative metadata; OpenReview v2 exposes venue records;
  Zotero’s local API stays on the machine.
- Lean establishes an exact formal statement only after the project proof gate.
  Wolfram or other CAS output remains recorded computation, not proof.
- Public review records can still carry anonymity and venue-policy obligations.
  Never infer concealed identities or send private manuscripts to external
  services.

Scite is an opt-in remote profile because queries and account-scoped library
context leave the machine. Enable it during agent configuration with
`DF_MCP_PROFILES=research-scite ~/dotfiles/bootstrap.sh update`; omit the
profile to keep the default Asta/arXiv research stack local/keyless where
possible. `biomed` and `publish` are reserved opt-in profiles; publication
tools still require explicit confirmation for writes.

## Reproducibility and publication

Record the command, inputs, seed, environment/toolchain, output, and checksums
for a rerun. DOI/repository operations remain project-scoped: inspect or create
a draft, validate metadata and checksums, then require an explicit instruction
before publishing. The skill neither stores secrets nor automates manuscript
uploads.
