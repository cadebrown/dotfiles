# Creative brief

**Purpose:** Demonstrate an editable local motion-graphics and video workflow.
**Audience/viewing context:** Example desktop playback; replace for the actual project.
**Delivery:** 24 seconds, 1920×1080, 30 fps, H.264/AAC; Remotion source and Kdenlive assembly remain editable.
**Direction status:** Agent-produced example. No user aesthetic approval is recorded.

| Reference | Provenance | Aspect shown | Status |
|---|---|---|---|
| `out/frame-100.png` after rendering | agent produced | Opening composition, orbital drawing, type hierarchy | example; not user-approved |
| `out/frame-340.png` after rendering | agent produced | Middle chapter and animated labels | example; not user-approved |
| `out/frame-580.png` after rendering | agent produced | Closing composition | example; not user-approved |
| `public/score.wav` after rendering | agent produced | Instrumental bed and chapter timing | example; not user-approved |

For real work, add user-supplied or researched references here with a URL/path, frame/timecode, and the precise aspect to follow. Mark each as candidate, approved, rejected, or superseded; approval needs actual user feedback and a scope. The example's dark background, green accents, orbital motif, and quiet score are replaceable proposals.

**Story/feeling to communicate:** [Project-specific outcome]
**Reference-led change:** [Composition, typography, pacing, color, motion, or audio]
**User feedback and chosen version:** [Record actual feedback; unknown until provided]

**Editable controls:** `src/index.jsx` owns content/layout/motion; `scripts/score.mjs` owns generated audio; `out/creative-system.kdenlive` owns the assembled cuts and separate audio track.
**Preview/rebuild:** `npm run studio` / `npm run render`.
**Handoff:** Keep the whole source project, lockfile, source media, and Kdenlive file together. The NLE edits rendered chapter footage; change the React source to alter typography or motion layers. Existing NLE timeline edits are preserved on rerender.
