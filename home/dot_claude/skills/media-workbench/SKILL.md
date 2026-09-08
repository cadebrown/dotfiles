---
name: media-workbench
description: Create motion graphics, explainers, and editable video projects with Remotion, Kdenlive, and FFmpeg. Use for video authoring, timeline editing, media automation, and rendered delivery.
---

# Media workbench

Use Kdenlive for timeline editing, Remotion for code-authored motion graphics, and FFmpeg for media transforms and delivery. Follow an explicitly chosen editor or project.

Keep the intended story, viewing context, references, and feedback in the project. New scaffolds include [CREATIVE-BRIEF.md](assets/remotion-template/CREATIVE-BRIEF.md); the starter's look and score are marked as agent-produced proposals. Annotate a reference by frame/timecode and the aspect it should guide. Do not infer approval of a palette, pacing, or sound from a supplied example or a technically successful render.

For a new Remotion project, run `node scripts/scaffold.mjs /absolute/output/project` from this skill directory. The scaffold includes pinned dependencies, a working animated composition, generated original audio, preview, render, editable Kdenlive assembly, and a render manifest. Run `npm ci`, then `npm run render` inside the project. `npm run studio` opens the editable composition. Read [Remotion workflow](references/remotion.md) when changing the composition or rendering.

For Kdenlive work, read [Kdenlive integration](references/kdenlive.md). Open the generated `out/creative-system.kdenlive` to edit three video chapters with a separate stereo music track. The generator preserves an existing timeline on rerender. Edit a saved copy when changing an existing project programmatically; Kdenlive's MLT XML contains both render structure and editor metadata.

For a repeatable edit/export/reopen operation, adapt [kdenlive-replay.md](references/kdenlive-replay.md). It is an agent-produced example, not a recorded user demonstration. The desktop workbench's [Record & Replay guidance](../desktop-workbench/references/record-and-replay.md) explains how an optional user demonstration can refine such a workflow.

Judge a video by playback, representative frames, pacing, legible type, and sound. FFprobe establishes encoding properties; it does not establish creative quality. Reopen the project or rendered output through the chosen application. Report host integration that could not be exercised separately from successful rendering.

Deliver the editable project with its assets and reopening command. In this scaffold, typography and motion are editable in React/SVG, sound in `score.mjs` or the replacement source audio, and assembly cuts/audio tracks in `.kdenlive`. A rendered MP4 is not a substitute for those sources. Note any baked layers and attach the latest project feedback to the handoff.
