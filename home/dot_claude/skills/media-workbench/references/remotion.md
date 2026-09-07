# Remotion authoring

The bundled starter pins Remotion 4.0.522 and React 19.2.8, checked against their npm registries on 2026-09-07. It creates a 24-second 1080p/30 film. All visuals are local React/SVG, and the stereo score is generated locally without external assets or services.

```sh
node /path/to/media-workbench/scripts/scaffold.mjs /absolute/project
cd /absolute/project
npm ci
npm run render
npm run studio
```

The first render downloads Remotion's matching Chrome Headless Shell when absent. This browser is a rendering runtime. It does not connect to the user's signed-in browsing profile.

Change `src/index.jsx` for content, typography, scene structure, and animation; change `scripts/score.mjs` for sound. `npm run stills` makes three representative PNGs. `npm run render` produces MP4, stills, a source/output hash manifest, and an editable Kdenlive assembly. `npm run verify` decodes the whole MP4 and checks expected stream properties. If duration, dimensions, or frame rate changes, update the composition, score, timeline chapter boundaries, and verifier together.

Use frame-based motion (`useCurrentFrame`, `spring`, `interpolate`) rather than wall clocks or unseeded randomness. Asset readiness belongs inside Remotion's lifecycle when loading new fonts/images. Keep meaningful text clear at delivery size and inspect scene boundaries as well as settled frames.

The render uses PNG frames and explicit BT.709 conversion. Remotion 4's default color path can produce full-range YUV even when `pixelFormat: 'yuv420p'` is requested; setting `colorSpace: 'bt709'` performs the color conversion instead of merely retagging the output.

`out/creative-system.kdenlive` is created once and preserved on later renders. Rerender refreshes the referenced MP4 and WAV. Save timeline edits in Kdenlive; don't overwrite the editor file with a fresh scaffold. Keep the entire project directory when moving machines because the timeline references its media.

Sources: [renderMedia](https://www.remotion.dev/docs/renderer/render-media), [renderStill](https://www.remotion.dev/docs/renderer/render-still), [bundle](https://www.remotion.dev/docs/bundle), [licensing](https://www.remotion.dev/docs/license). Remotion's license is separate from the open-source editor; check the current terms if this personal workflow becomes a company/team product.
