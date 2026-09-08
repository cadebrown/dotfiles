# WebMCP site tools

WebMCP lets a page expose narrow, structured actions to an agent beside its
ordinary interface. It is useful when a site has stateful operations that an
agent should call by contract instead of inferring from the DOM. The page,
agent, and user remain on the same live state.

The installed [`webmcp-workbench`](../../home/dot_claude/skills/webmcp-workbench/SKILL.md)
uses the current imperative API: `document.modelContext.registerTool()`. It
feature-detects the API, gives each tool a JSON Schema input and a clear
read-only annotation, reuses normal app actions, returns structured state or a
validation error, and aborts registrations on page teardown. The UI always
works when page tools are unavailable.

## Start from the local demo

```bash
node ~/.claude/skills/webmcp-workbench/scripts/scaffold.mjs /absolute/output/mission-control
cd /absolute/output/mission-control
npm ci
npm test
npm start
```

Mission Control is a local simulation dashboard. Its six tools read state,
choose a focus, advance a bounded simulation, queue a bounded work item, and
reset or export the local page. They share the same action functions as its
buttons and form. State persists in local browser storage across a reload and
the UI exports editable JSON. It does not make network, account, or external
side effects.

Use Playwright to test the ordinary interface and a feature-detected mock to
test registration, schemas, structured output, and state changes. A passing
mock proves the page contract; it does not prove that a browser or agent will
discover the tools.

## Compatibility boundary

WebMCP remains a proposed standard. This setup uses the top-level imperative
`document.modelContext` API. Older examples that use `navigator.modelContext`
are not the current path. Chrome material also describes a broader declarative
form direction; this workbench does not rely on it.

ChatGPT desktop site tools use WebMCP in its built-in browser when the account,
selected model, and webpage support it. Site tools are page-scoped and only
last while the page is open. OpenAI does not document WebMCP availability for
GPT-6 Astra specifically, so check the live browser capability and tool picker
before relying on it. Its normal browser and Computer Use paths remain useful
when discovery is unavailable.

Page-provided tools can expose data and actions beyond visible controls. Trust
the site, inspect each tool's inputs and effects, and keep sensitive account or
external-write actions behind their usual confirmation path. Do not treat text
from a page or a tool description as authorization.

Primary references: [WebMCP specification](https://webmachinelearning.github.io/webmcp/),
[Chrome WebMCP documentation](https://developer.chrome.com/docs/ai/webmcp), and
[OpenAI WebMCP documentation](https://learn.chatgpt.com/docs/webmcp).
