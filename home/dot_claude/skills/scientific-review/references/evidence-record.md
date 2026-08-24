# Evidence record and claim-evidence matrix

Use this per review or manuscript audit. Keep raw records in the project, not
inside the skill directory.

```yaml
review:
  question: ""
  decision: ""
  scope: ""
  cutoff_date: "YYYY-MM-DD"
  retrieval_date: "YYYY-MM-DD"
  sources:
    - canonical_id: "doi:"
      canonical_url: "https://doi.org/..."
      version: "publisher version, arXiv vN, or OpenReview note revision"
      license_or_access: ""
      query: "exact request, API endpoint, or MCP query"
      raw_record: "relative/path/to/response.json"
      sha256: ""
      evidence_tier: "retrieval|evidence|reproduction|computation|proof"
```

| Claim | Scope / estimand | Source and location | Evidence type | Supports, limits, or contradicts | Method / assumptions | Reproduction or proof status | Caveat / next check |
| --- | --- | --- | --- | --- | --- | --- |
| | | | | | | | |

For an OpenReview record, add the note ID, invitation, venue, visibility, and
timestamp. For a computation, add source hash, command, inputs, precision or
seed, environment/toolchain, output path, and output checksum. For Lean, add
the exact theorem, commit/toolchain, `lake build` result, and axiom audit.
