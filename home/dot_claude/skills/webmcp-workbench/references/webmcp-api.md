# WebMCP API notes

WebMCP is a proposed web standard. The current specification presents an
imperative, document-scoped API: `document.modelContext.registerTool()`. A tool
has a name, description, JSON Schema input, optional annotations, and an
execution callback. Registrations are removed by aborting the signal supplied
in the registration options; there is no general `unregisterTool()` method.

Use `document.modelContext` directly. Older material may use
`navigator.modelContext`; that location is deprecated in current Chromium
material. Feature detection must make a missing implementation a no-op, and a
rejected registration must leave the ordinary UI working.

Chrome's WebMCP material also describes a broader declarative form direction.
This workbench uses only the current top-level imperative path because it is
appropriate for stateful application actions. Do not infer declarative support,
cross-origin exposure, or browser-agent discovery from a successful local mock.

ChatGPT desktop site tools are a separate product surface. OpenAI documents
that availability depends on the account, selected model, and page-provided
tools, and that they currently work in the desktop app's built-in browser. It
does not establish availability for GPT-6 Astra.

Primary references:

- [WebMCP specification](https://webmachinelearning.github.io/webmcp/)
- [Chrome: WebMCP](https://developer.chrome.com/docs/ai/webmcp)
- [OpenAI: WebMCP](https://learn.chatgpt.com/docs/webmcp)
