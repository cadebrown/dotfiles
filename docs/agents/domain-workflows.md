---
title: Creative, game & research workflows
description: Choose a domain route, preserve editable work, and collect relevant evidence.
---

Choose [Creative](#creative-work), [Games](#games), or [Research](#research). Each workflow leaves editable sources and an output you can inspect.

<ol class="workflow-steps" aria-label="From task brief to reviewed output">
<li><strong>Brief</strong><span>Task + constraints</span></li>
<li><strong>Build</strong><span>Editable source</span></li>
<li><strong>Run</strong><span>Open or play it</span></li>
<li><strong>Review</strong><span>Compare the result</span></li>
</ol>

<div id="creative-work-preserve-intent-and-editability" class="legacy-fragment-anchor" aria-hidden="true"></div>

## Creative work

Record requirements, references, candidate directions, and feedback in `CREATIVE-BRIEF.md`. Compare layouts, camera views, or short previews before selecting a direction.

| Work | Keep | Finish with | Prompt example |
| --- | --- | --- | --- |
| Browser design | source, assets, tokens | viewport screenshots and interaction | “Implement the selected card layout; capture desktop and mobile states.” |
| Blender/game asset | `.blend`, scripts, textures, export settings | render, reopened scene, destination import | “Make the selected prop; render it and import the GLB into the project.” |
| Motion/video | composition, source audio, editable timeline | playback, frames, audible output, reopened project | “Animate the chosen transition; export a preview and reopen the timeline.” |

Use [creative workflows](../usage/creative-workflows.md) for templates, provenance, and evidence boundaries.

<div id="games-validate-the-playable-path" class="legacy-fragment-anchor" aria-hidden="true"></div>

## Games

Use [`router`](/reference/skills/#router) to find the engine's build and test commands:

```text
Use router. Own the dash mechanic and its existing tests. Run the project’s
documented narrow build, then play the dash path in its target runtime. Return
the changed files, test command, capture path, and any untested device boundary.
```

Run existing deterministic tests, then exercise the actual input-to-outcome path in the engine, browser, or emulator. A valid GLB does not establish material, scale, animation, timing, audio, input, or gameplay use. See [game development](../usage/gamedev.md).

<div id="research-separate-source-calculation-and-proof" class="legacy-fragment-anchor" aria-hidden="true"></div>

## Research

Use primary sources for drift-prone facts and label direct evidence separately from inference.

| Result | Establishes |
| --- | --- |
| Numerical/CAS result | Its stated inputs, assumptions, software, and precision |
| Literature source | The source’s claim, scope, and status |
| Lean build | The checked statement elaborates in that environment |
| Formal certification | The additional reviewed conditions for the repository claim |

Use [math routes](../usage/math.md) and [scientific review](../usage/scientific-review.md). A bounded computation or compiled formalization does not establish a different theorem.

## A concrete research brief

```text
Use researcher. Does current official API documentation support setting X in
client Y? Search official documentation only. Return the direct URL, retrieval
date, supported-client wording, and whether the conclusion is evidence or
inference. Do not edit files. Write excerpts to /tmp/api-setting-research.md.
```

The parent can use that artifact to decide whether local client-version verification or an implementation change is justified.
