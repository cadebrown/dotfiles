# Creative references and demonstrated workflows

Use a project brief to preserve visual intent, and an executable project to
preserve the ability to change it. The workbench examples demonstrate working
tools; their visual choices are proposals, not evidence of personal taste.

## Work from annotated references

Keep a short `CREATIVE-BRIEF.md` beside the project. The workbenches provide
starting templates:

| Work | Template or entrypoint | Editable handoff |
|---|---|---|
| Browser UI | `desktop-workbench/assets/creative-brief.md`, then `browser-workbench` | App source, assets/design tokens, run command, interaction tests, and viewport screenshots |
| Blender scene or game asset | `blender-workbench/assets/creative-brief.md` | `.blend`, project scripts, textures/fonts, named asset collection, and requested engine export |
| Motion graphics and video | `media-workbench` scaffold includes `CREATIVE-BRIEF.md` | React/SVG composition, source audio, lockfile, `.kdenlive` timeline, and rendered output |

These paths are under `~/.claude/skills/`, with shared harness links managed by
the existing skill setup. To start a browser/design brief without copying an
entire demo:

```bash
cp ~/.claude/skills/desktop-workbench/assets/creative-brief.md ./CREATIVE-BRIEF.md
```

For every useful reference, identify its source, a view or timecode, the
specific aspect it should guide, and its status. A user-supplied image is a
reference; it becomes an approved direction only when feedback establishes
that scope. Approval of its lighting does not imply approval of its geometry
or palette. Mark agent-found references and generated alternatives as
candidates. Keep rejected and superseded directions annotated when that
prevents repeating a failed choice.

Resolve consequential visual uncertainty with something inspectable: a viewport
comparison, a material/camera preview, a short animated passage, or a working
interaction. Preserve the selected version and the user's actual feedback in
the brief. Do not require a formal brief or approval meeting for an ordinary
small edit; use the context already provided.

## Concrete examples

For Blender, the orbital-compute example under
`~/Documents/Codex/2026-09-07/ai-setup-upgrade/blender/orbital-compute` contains
native scenes, renders, animation samples, and a GLB. Its validation record
covers native save/reopen, imported geometry/materials/animation, and resumed
frames. A real brief could retain the asset-collection/export structure while
replacing the orbital subject, orthographic camera, or materials. Those choices
were agent-produced, not recorded user preferences.

For video, the Creative System example under
`~/Documents/Codex/2026-09-07/ai-setup-upgrade/media/film` keeps motion typography
in `src/index.jsx`, generated sound in `scripts/score.mjs`, and assembly edits in
`out/creative-system.kdenlive`. It has a verified MP4 and a separate MLT export.
Native playback and a saved/reopened project-note edit were exercised. The
dark palette and instrumental score are replaceable examples. Changing text
inside React is different from trimming the rendered chapter in Kdenlive;
the handoff explains which source owns each change.

For browser UI, use the browser workbench's `assets/interaction-lab` for an
editable create/complete/filter/reopen interaction and screenshots across
browser engines. A design reference might govern the form hierarchy while
the interaction test preserves behavior. Keep screenshots of the selected
layout and the actual working source together. A passing browser test does not
approve the visual direction.

## Teach a workflow by demonstration

Record & Replay can turn a user demonstration into skill instructions. The
desktop workbench's
[`record-and-replay.md`](../../home/dot_claude/skills/desktop-workbench/references/record-and-replay.md)
contains the current macOS entrypoint and refinement procedure, sourced from
[OpenAI's documentation](https://learn.chatgpt.com/docs/extend/record-and-replay).
Recording is optional; no demonstration was captured during this setup work.

Use `desktop-workbench/assets/workflow-template.md` to name the recurring
outcome, changing inputs, fresh starting observations, semantic actions, and
result checks. Keep the provenance: user recording, user description, or
agent-produced example. Refinement should remove accidental coordinates and
one-off filenames while preserving meaningful user choices. Replay must
observe the current project and controls, recover from an already-open file or
in-progress export, and reopen the result before calling the task complete.

The media workbench includes
[`kdenlive-replay.md`](../../home/dot_claude/skills/media-workbench/references/kdenlive-replay.md),
an agent-produced review/save/export/reopen example based on the exercised
project. It is usable now with explicit project and output paths. A later user
demonstration can teach preferred review gestures, naming, or export decisions
without making recording a prerequisite for productive work.

Keep a project-specific procedure with that project. Extend an existing skill
when it learns a broadly useful method. A distinct recurring workflow may earn
its own skill after replay with changed inputs shows that it works beyond the
original demonstration.
