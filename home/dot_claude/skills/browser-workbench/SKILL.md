---
name: browser-workbench
description: Build, debug, and visually verify web interfaces with native browser control and repeatable Playwright flows. Use webmcp-workbench when adding or testing page-provided agent actions.
---

# Browser workbench

Use the browser throughout implementation: inspect the rendered experience, exercise the important interaction, then refine it. Preserve the user's chosen browser and any explicitly selected tab.

## Available paths

- **Codex Desktop:** native in-app browser for local development and shared visual feedback; connected browser extension for an existing account or selected tab. Follow the tools' live documentation. Do not assume cookies are shared across profiles.
- **Repeatable automation:** installed `playwright-cli` and the `playwright-cli` skill. Named sessions, traces, screenshots, video recording, persistent profiles, and browser engines are available. Use project-owned Playwright tests when a flow should become a regression check.
- **Portable alternative:** `agent-browser`; read its version-matched `agent-browser skills get core` guide before commands. Use a separately named session and explicit browser executable when comparing it with Playwright. Report observed behavior rather than assuming a smaller snapshot improves task quality.
- **Browser debugging:** `codex -p browser` enables Chrome DevTools MCP with pinned code and usage/CrUX telemetry disabled. Use console, network, and performance evidence when they answer the actual problem.
- **Design sources:** the official Figma plugin provides design context when connected. Its account connection is distinct from local plugin installation. Use the installed Figma skill for the requested operation.
- **Page-provided actions:** use `webmcp-workbench` to add or validate semantic tools in a web app. Discover tools from the current page through the browser's supported interface. Keep visual inspection in the loop; a tool response does not establish what the user sees.

## Work loop

Start the project's documented development server and verify the route. Inspect desktop and narrow-screen layouts, then exercise the main flow and relevant loading/error/empty states. Check console errors and failed requests when behavior is wrong. For visual work, read actual screenshots; DOM assertions alone do not establish layout quality.

Use the project's creative brief and annotated references when shaping a new
interface. Distinguish user-approved direction from suggested examples, and
respect an explicit request to discuss concepts before implementation. The
`desktop-workbench` creative-reference resources can seed a brief when useful.

Use stable roles, labels, and test IDs in reusable tests. Keep app/window identifiers and browser profiles explicit. Store screenshots, traces, and videos alongside the task artifacts, with the URL, viewport, browser version, and source revision needed to reproduce them. Do not export signed-in storage state unless the task needs it.

## A reusable interactive session

```bash
playwright-cli -s=design open http://127.0.0.1:3000
playwright-cli -s=design resize 1440 1000
playwright-cli -s=design snapshot
playwright-cli -s=design screenshot --filename=desktop.png
playwright-cli -s=design resize 390 844
playwright-cli -s=design screenshot --filename=mobile.png
playwright-cli -s=design close
```

For trace, video, and annotation workflows, load the corresponding references in the installed Playwright skill rather than inventing flags. Close only the sessions created for the task. Headless execution is useful on Linux and unattended workers; return a viewable artifact to the user when the result needs visual review.

## Runnable interaction lab

Copy [assets/interaction-lab](assets/interaction-lab) into a task workspace, run `npm install --ignore-scripts`, then `npm test`. The pinned Playwright suite creates/completes/filters/reopens a task in Chromium, Firefox, WebKit, and mobile WebKit, and writes screenshots plus JSON results. Install matching browser runtimes with `npx playwright install` if they are missing. `npm start` serves the same sample for native Computer Use, Peekaboo, or CLI browser experiments. Keep generated dependencies and evidence outside the installed skill tree.

Sources: [Playwright CLI](https://github.com/microsoft/playwright-cli), [Chrome DevTools MCP](https://github.com/ChromeDevTools/chrome-devtools-mcp), [agent-browser](https://github.com/vercel-labs/agent-browser).
