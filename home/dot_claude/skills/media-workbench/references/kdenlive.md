# Kdenlive editing and automation

Kdenlive is the default NLE for this workflow. The generated starter project has three independently editable video cuts and a separate stereo score track. Motion typography remains editable in the Remotion source; Kdenlive edits the rendered chapter footage. It is not a native title-layer conversion.

Open `out/creative-system.kdenlive`, scrub all three chapters, play with audio, adjust a cut or track volume, and Save As a new project. Close and reopen that copy, then use Render → MP4 (H.264/AAC) → Render to File. Inspect the exported video with FFprobe and playback.

For repeatable existing-project edits, start from the saved `.kdenlive` file. It is MLT XML plus editor metadata. Keep the sequence UUID, bin IDs, track tractors, dual track playlists, and wrapper tractor consistent. XML well-formedness alone cannot establish that the editor will reopen it. The starter generator preserves existing `.kdenlive` files.

The starter omits an explicit XML `LC_NUMERIC` attribute. With this Mac's bundled MLT 7.39.0, the generated composition crashed during frame-cache cleanup when `LC_NUMERIC="C"` was present; the same composition completed null and encoded renders when that attribute was omitted. This is a verified local compatibility boundary, not a claim about every MLT build. Preserve editor-generated locale data in unrelated existing projects.

Use Kdenlive's Generate Script action for faithful repeat renders of projects containing editor effects or titles. Run the generated `.mlt` with the matching bundled `melt`; this keeps the application's media plugins and fonts aligned. On this Mac the binaries are inside `/Applications/Kdenlive.app/Contents/MacOS/`. Linux package paths vary. Run `melt -help` and `kdenlive_render --help` for the installed build instead of copying an older CLI signature.

For a simple MLT render with an explicit output:

```sh
/Applications/Kdenlive.app/Contents/MacOS/melt project.kdenlive \
  -consumer avformat:export.mp4 vcodec=libx264 crf=18 preset=medium \
  acodec=aac ab=192k pix_fmt=yuv420p movflags=+faststart
```

For a Linux render service, use the exported MLT script plus its media/assets. Qt effects may require a virtual display; ordinary Remotion/FFmpeg jobs have fewer editor runtime requirements. Do not claim that CLI installation proves title/font/plugin equivalence between Mac and Linux.

Sources checked 2026-09-07: [project file details](https://docs.kdenlive.org/en/project_and_asset_management/file_management/project_files.html), [official file-format reference](https://github.com/KDE/kdenlive/blob/master/dev-docs/fileformat.md), [rendering and command-line scripts](https://docs.kdenlive.org/en/exporting/render.html), [MLT XML](https://www.mltframework.org/docs/mltxml/).
