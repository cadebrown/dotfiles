# Reusable workflow: [observable outcome]

**Provenance:** user recording / user description / agent-produced example
**Basis:** [Recording/task/artifact reference and date; “no recording” when applicable]
**Readiness:** draft / exercised on example / exercised with changed inputs
**Use when:** [Specific recurring task]
**Application and control path:** [App/version; native GUI, browser, API, or CLI]

| Parameter | Meaning and selection rule |
|---|---|
| input_project | [Explicit project path or user-selected document] |
| input_item | [Named sequence, collection, record, or selection; omit if irrelevant] |
| output_path | [Explicit destination and overwrite rule for this task] |
| variable_settings | [Only settings intended to vary; defaults need provenance] |

**Starting state:** [How to identify the intended app, window, project, and item from fresh observations]
**Existing work:** [How the workflow preserves unsaved changes or resumes an already-started operation]

| Intent | Semantic target/action | Observable result | Recovery from a different state |
|---|---|---|---|
| [Open the intended project] | [File → Open; explicit input path] | [Project identity visible] | [Observe a dialog or missing-media state before proceeding] |
| [Apply the requested change] | [Named object/track/field; parameter value] | [Actual changed property] | [Inspect current value before retrying] |
| [Save/export] | [Named destination and settings] | [File or completed job] | [Inspect queue and output before starting a duplicate] |

**Verify the result:** [Reopen the saved artifact; check the visible/content changes and requested output properties]
**Fresh-state replay:** [Close only this workflow's windows/session as appropriate; repeat with a different safe input or output; observe new identifiers]
**Uncertainty that needs a decision:** [A real ambiguity the workflow cannot resolve from project state]
**Evidence:** [Inputs, changed settings, artifact paths, observed result; do not substitute a successful click for the outcome]

Replace recorded coordinates, transient node IDs, account values, and one-off filenames with observations or parameters. Keep a fixed value only when its meaning is part of the task. The demonstration describes a method; it does not grant new authorization to publish, send, purchase, or change unrelated projects.
