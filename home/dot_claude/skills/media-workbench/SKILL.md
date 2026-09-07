---
name: media-workbench
description: Create motion graphics, explainers, and editable video projects with Remotion, Kdenlive, and FFmpeg. Use for video authoring, timeline editing, media automation, and rendered delivery.
---

# Media workbench

Use Kdenlive for timeline editing, Remotion for code-authored motion graphics, and FFmpeg for media transforms and delivery. Follow an explicitly chosen editor or project.

For a new Remotion project, run `node scripts/scaffold.mjs /absolute/output/project` from this skill directory. The scaffold includes pinned dependencies, a working animated composition, generated original audio, preview, render, editable Kdenlive assembly, and a render manifest. Run `npm ci`, then `npm run render` inside the project. `npm run studio` opens the editable composition. Read [Remotion workflow](references/remotion.md) when changing the composition or rendering.

For Kdenlive work, read [Kdenlive integration](references/kdenlive.md). Open the generated `out/creative-system.kdenlive` to edit three video chapters with a separate stereo music track. The generator preserves an existing timeline on rerender. Edit a saved copy when changing an existing project programmatically; Kdenlive's MLT XML contains both render structure and editor metadata.

Judge a video by playback, representative frames, pacing, legible type, and sound. FFprobe establishes encoding properties; it does not establish creative quality. Reopen the project or rendered output through the chosen application. Report host integration that could not be exercised separately from successful rendering.
