# Review, save, export, and reopen a Kdenlive project

**Provenance:** Agent-produced example, not a user recording. Its basis is the local 2026-09-07 Creative System project: three video chapters, separate score track, full MLT export, native playback, a saved project-note edit, and successful reopening. New inputs still need their own verification.

**Use when:** A user wants a repeatable review/export of a specified local editing project.
**Inputs:** `input_project`, `review_sequence` when the project has several, `saved_copy`, `export_path`, requested range and encoding settings. Derive unspecified technical properties from the selected project; the example's 1080p30/24 seconds are not universal defaults.

| Intent | Action and observable outcome | Recovery |
|---|---|---|
| Open the chosen source | Inspect the actual app/window, then open `input_project`; confirm project and sequence identity. | Preserve an unsaved document before switching. If media is missing, use the project's known source paths; do not substitute unrelated files. |
| Review the meaningful moments | Scrub opening, transition, and ending; play a representative span with sound. Compare annotated references for the requested visual aspects. | Refresh UI state if controls moved. Do not treat an audio meter as confirmation of listening quality. |
| Save the requested edit | Apply the requested change only, then Save As `saved_copy`; verify the new path. | Inspect current values after an interrupted operation before repeating it. Use a new copy if preserving the previous version is part of the task. |
| Export the selected sequence | Choose the intended range/settings and `export_path`; wait for the completed export or use an explicit matching MLT render. | Check the job queue and output before retrying. A render started twice is not useful recovery. |
| Reopen and verify | Reopen `saved_copy` and confirm the edit persisted; play the export and inspect its streams/duration against the intended sequence. | If saving succeeded but verification failed, keep both artifacts and correct the actual mismatch. |

To exercise replay, begin a new task or reset only the app state owned by this workflow, choose a different safe output name, and observe project/window identifiers afresh. The workflow should work without the previous task's coordinates, node IDs, selected track, or open file dialog.

The tested project lives under `~/Documents/Codex/2026-09-07/ai-setup-upgrade/media/film`. Start a replay with its `out/creative-system.kdenlive` and new output paths. `npm run studio` edits the underlying motion design; Kdenlive edits assembled footage. The [Kdenlive reference](kdenlive.md) covers MLT execution and project-format boundaries.

If the user supplies a demonstration later, preserve its provenance and annotate their specific review gestures, naming choices, and preferred export settings. Do not turn this example into an assertion about their preferences.
