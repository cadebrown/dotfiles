---
name: google-workspace-flow
description: Edit shared native Google Docs, Sheets, and Slides with templates, comments, and visual verification. Use for collaborative Google-file authoring and review through an available plugin, Workspace MCP, or gws CLI.
---

# Shared Google Workspace authoring

Keep the native Google file as the shared source once review begins. Preserve
its URL, permissions, and colleagues' changes. Follow the user's requested task
and existing authorization; setup does not authorize unrelated file changes.

## Choose the available route

- Use the OpenAI Google Drive plugin when connected and its native operations
  fit the task. Follow its document-specific skills.
- In other harnesses use the managed `google-workspace` MCP. Docs/Slides must
  actually be selected; Slides comments require the `complete` tool tier in
  Workspace MCP 1.26.2. Use the connected Google account, never infer its email.
- For missing wrapper features, `gws` 0.22.5 provides direct API commands from
  the shell. It has separate OAuth storage. `gws mcp` was removed; don't suggest
  it. Inspect `gws schema SERVICE.RESOURCE.METHOD` before forming a request.
- A search connector such as MaaS-GDrive can find files; that does not establish
  native editing or comment access. Pass the exact file URL to the authoring route.

Read the actual tool schemas and an accessible file to verify the route. Report
configured, authenticated, tools exposed, read, and write states separately.
For managed setup see `~/dotfiles/docs/usage/google-workspace.md` and
`~/dotfiles/docs/usage/google-ai.md`; use supported setup commands and private
credential storage. Preserve other integrations. Local stdio and remote HTTPS
connectors have different authentication and reachability requirements.

## Author and review

Read the target's native structure before editing. Start new work from a
provided native template when available; retain masters, layouts, typography,
and editable text, shapes, and tables. Use the installed presentation/document
authoring workflow for local artifacts and inspect the native conversion.
Don't flatten a deck into screenshots when editable primitives are requested.

For technical material preserve evidence, source links, units, measured versus
estimated values, and uncertainty. Match the user's audience and slide/page
budget. Re-read the final count if a limit was specified.

For comment review, fetch all comment pages and retain replies, resolution
state, IDs, and quoted text. Workspace MCP 1.26.2's shared comment reader defaults
to 100 and doesn't report truncation. A result of 100 is not proof of completeness.
Use the Drive API through gws when exhaustive review requires visible page tokens.
Include `nextPageToken` in requested fields; even `--page-all` has a default
10-page cap, so inspect the final token and continue as needed.

Anchor discussion with an exact quote and slide number, section, or sheet/range.
Drive-created comments may be unanchored in the editor. New native Docs/Slides
comment APIs are Developer Preview and are not exposed by every wrapper.
Don't manufacture anchor identifiers. Reply or resolve only when the task
calls for it; use IDs from a fresh read of the target comment thread.

For concurrent work, divide files or edit regions and coordinate writers.
Workspace MCP 1.26.2's Slides batch tool lacks top-level `writeControl`.
Re-reading alone does not remove the race. When conflict protection matters,
use native batchUpdate with `writeControl.requiredRevisionId` through a capable
route and handle a stale-revision error by re-reading and reconciling changes.
Never retry a stale full-document overwrite blindly.

After edits, read back the affected content and actually view rendered native
slides/pages using thumbnails, browser inspection, or a supported render/export.
A returned thumbnail URL or successful export is not visual inspection. Check
clipping, font substitution, diagrams, and tables. Export only when requested,
and distinguish successful conversion from verified layout fidelity.

Return the exact Google file link, concise changes, and what was verified.
Keep a small reproducible example or test file when it helps the user's setup;
label it clearly and don't change sharing just to make a test pass.

References: [Workspace MCP](https://github.com/taylorwilsdon/google_workspace_mcp),
[gws](https://github.com/googleworkspace/cli),
[Drive comments](https://developers.google.com/workspace/drive/api/guides/manage-comments),
[Slides revision control](https://developers.google.com/workspace/slides/api/reference/rest/v1/presentations/batchUpdate#WriteControl).
