---
name: scientific-review
description: Audit scientific claims, manuscripts, or peer-review records against traceable evidence, or certify completed Lean proofs. Use for literature reviews, review responses, claim-evidence matrices, and final formal certification; use lean4 for routine proof development.
---

# Scientific Review

Treat discovery, evidence, reproduction, and proof as different products. A
retrieved paper or a successful computation supports a claim; it does not prove
it. Preserve the boundary in both the investigation and the final wording.

For final certification of an AI-generated or exported Lean proof, read
[the formal certification gate](references/formal-certification.md). Apply that
gate directly when certification is the task; literature-review artifacts are
not required for a proof-only request.

## Start with the review target

State the claim, its scope and population, the decision it informs, and the
cutoff date. Decide whether the task needs (a) discovery, (b) source inspection,
(c) a reproducible computation, (d) a formal proof, or (e) review-record
analysis. Do not search private libraries, venue records, or manuscript files
unless the user put them in scope.

## Route to the authoritative layer

| Need | First route | Boundary |
| --- | --- | --- |
| Literature discovery, related work, citation graph | `asta` MCP, then arXiv | Search results and citation counts are retrieval evidence, not validation. |
| arXiv text, definitions, equations, appendices | `arxiv` MCP/source; confirm the paper version | Cite the arXiv identifier and version. |
| DOI metadata, authors, funders, license, retractions | Crossref content negotiation/REST | Preserve the DOI and the returned record. |
| Broad corpus, OA status, affiliations, funders, graph filters | OpenAlex REST | Record the query and retrieval date; API budgets and coverage change. |
| Dataset/software DOI and PID relationships | DataCite REST v2 | Use the public read API; repository credentials are only for an authorized project. |
| Public submission, review, rebuttal, decision | OpenReview API v2 | Respect venue permissions and anonymity; do not infer hidden identities. |
| Local bibliography, notes, attachment inventory | Zotero local API | Keep requests on `localhost`; never expose the library as a remote service. |
| Exact formal claim | `lean4`, `lean-lsp` MCP when available, and the project toolchain | Apply the [formal certification gate](references/formal-certification.md) before claiming final certification. |
| Symbolic/numeric check | Wolfram MCP or `wolframscript` | Save code, inputs, precision, and output; label the result as computation. |

Use primary publisher, repository, or official API records to resolve conflicts.
Treat an abstract or metadata-only record as insufficient for a claim about
methods, assumptions, statistics, or a theorem statement.
Read [the authoritative API routes](references/authoritative-apis.md) before
writing a direct request; API versions and authentication rules differ.

## Build an auditable evidence record

For every item that affects the conclusion, retain canonical IDs (DOI, arXiv,
PMID/PMCID, OpenReview note, dataset/software DOI), canonical URL, exact query,
retrieval date, version, license/access status, and either the raw response or
its path plus checksum. Keep a claim-evidence matrix rather than a pile of
links. Read [the evidence-record template](references/evidence-record.md) when
creating a review artifact.

Classify each row as one of: direct empirical evidence, method/assumption,
replication, counterevidence, metadata/provenance, computation, or formal proof.
State what would change the conclusion and distinguish an absent result from a
negative result.

## Peer review and manuscript work

Review the stated claim against its cited evidence, methods, scope, uncertainty,
and conflicts. Cite the source and location for each substantive finding. A
useful finding identifies the claim, evidence, consequence, and requested
revision; it does not merely restate a preference.

For OpenReview, preserve the note ID, invitation, venue, timestamp, visibility,
and the original review/rebuttal text or a checksum. Public availability does
not remove confidentiality, anonymity, or venue-policy obligations.

Do not upload manuscripts to similarity, AI-detection, or external review
services. Do not embed credentials in artifacts, prompts, scripts, or source
control.

## Reproduction and publication

Reproduction requires a runnable, versioned environment and observed output;
it is not established by prose, a download, or an agent summary. Record the
command, toolchain/dependency versions, inputs, seeds, environment, output, and
checksums. Never call it a replication unless it independently re-runs the
relevant method and compares the prespecified target.

Repository and DOI publication APIs are project-scoped. Create or inspect a
draft, validate metadata and checksums, present the exact immutable effect, and
publish only after an explicit user instruction in that project. Never make
publication a side effect of a literature or review request.

## Deliverable

Lead with the conclusion and confidence. Follow with a compact claim-evidence
matrix, provenance record, limitations/conflicts, and the exact evidence tier:
retrieval, evidence, reproduction, computation, or proof. Do not turn citations
or model/CAS output into stronger claims than they support.
