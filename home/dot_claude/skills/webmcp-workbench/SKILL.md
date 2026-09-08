---
name: webmcp-workbench
description: Build and validate WebMCP site tools for an interactive web application when an agent should call page-native actions instead of guessing DOM controls.
---

# WebMCP workbench

Use WebMCP to expose a small, page-scoped contract around existing application
logic. Keep the ordinary UI fully usable: site tools are an additional agent
surface, not the application's only control path.

Use the current imperative API, `document.modelContext.registerTool()`, behind
feature detection. Register focused tools with JSON Schema inputs, accurate
read-only annotations, structured results, and an `AbortController` lifecycle.
Call the same action functions from the page UI and each tool. Keep mutations
local unless the user separately authorizes an external write.

Use a small read tool first, then only the narrow mutation that meets the
request. Return the new state or a structured validation error so an agent can
verify the result without reinterpreting the page. Abort registrations when the
route or page is torn down. Do not expose secrets, raw account tokens, broad
"run arbitrary action" tools, or instructions harvested from page content.

The API is still proposed and support is browser, account, model, page, and
permission-policy dependent. Do not promise site-tool discovery for a specific
model. Use the normal UI and browser automation when `document.modelContext` is
unavailable. Read [API notes](references/webmcp-api.md) before making protocol
or compatibility claims.

## Reusable demo

Scaffold the editable, local-only Mission Control dashboard:

```bash
node ~/.claude/skills/webmcp-workbench/scripts/scaffold.mjs /absolute/output/mission-control
cd /absolute/output/mission-control
npm ci
npm test
npm start
```

It exposes read, focus, simulation, work-item, and reset actions. The
Playwright tests install a feature-detection mock to exercise the real tool
definitions and the same action layer the UI uses. Use it as a compact starting
point, not a claim that a normal browser or any particular agent can discover
the tools.
