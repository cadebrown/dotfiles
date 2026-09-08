# From a demonstration to a reusable workflow

Record & Replay requires macOS and enabled Computer Use. In the desktop app, select Codex (or ChatGPT with Work), open Plugins → + → Record a skill, and submit the recording prompt. The user approves recording when ready, demonstrates the task, and stops through the menu bar, overlay, or chat. The app then drafts a skill. Replay it in a new task with the inputs that should change. If the feature is absent, check Computer Use availability and managed requirements rather than inventing a shell toggle. [Official Record & Replay documentation](https://learn.chatgpt.com/docs/extend/record-and-replay), checked 2026-09-07.

No recording is needed to use the existing workbenches. Start capture only when the user wants to demonstrate a workflow. Keep the capture focused on that operation and stop at its result.

## Refine the captured pattern

Use [workflow-template.md](../assets/workflow-template.md) in the project before promoting a workflow into a skill. This also works for a user-written procedure or an agent-produced example; retain the actual provenance.

1. Identify the outcome and any preference actually demonstrated or stated. Separate those from incidental cursor paths, window positions, wait times, and filenames.
2. Name the variable inputs and the intended project boundary. A selected sequence, export preset, destination, or date range should not silently carry over from the demonstration.
3. Express actions through app objects, menu labels, accessible controls, browser roles, or a supported API. Preserve visual inspection for choices that depend on appearance. Use the current tool documentation and fresh UI state on each run.
4. Add recovery at the places that actually varied: a document already open, an unsaved edit, a missing asset, an export in progress, or an unexpected modal. Inspect state before retrying a mutation; don't repeat an export or submission blindly.
5. Reopen and inspect the result. Then replay from a fresh app/task state with changed safe inputs, so success does not depend on leftover selections or cached identifiers. Record which replay was exercised and what remains untested.

Keep a project-specific workflow with its project. Extend a relevant existing workbench when the method is broadly useful. Create a separate skill only for a distinct recurring workflow that needs its own trigger. Review the saved instructions with the user when the demonstration leaves a consequential preference ambiguous; continue independent preparation within the existing request.

## A ready example without a recording

The media workbench includes an [agent-produced Kdenlive export/reopen example](../../media-workbench/references/kdenlive-replay.md), based on the previously exercised local media project. It shows parameter and recovery choices without claiming the user demonstrated them. A user recording could refine their preferred sequence selection, review gestures, naming, and export settings later.
