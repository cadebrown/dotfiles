---
name: desktop-workbench
description: Use when operating or validating native desktop workflows across apps, including macOS background computer use, file dialogs, creative applications, and CLI-driven accessibility automation.
---

# Desktop workbench

Use the desktop to finish work inside the user's actual applications. Combine visual judgment with the application's structured interface when that makes the task more reliable.

## Choose the control surface

- In Codex Desktop, use its native Computer Use tools and their returned documentation. The browser extension operates the user's connected browser; the in-app browser has its own profile. Discover the current apps and tabs instead of guessing access from installation.
- Outside a harness with native Computer Use, macOS has `peekaboo` for accessibility, screenshots, windows, menus, and actions. Start with `peekaboo permissions status --json` and `peekaboo help <command>`; the installed version defines the interface. The optional `codex -p desktop` profile exposes scriptable-app automation as well.
- For Blender assets/renders use `blender-workbench`; for editing and motion graphics use `media-workbench`. Use the graphical application to inspect and refine the result.
- For an app with a scripting API, prefer semantic operations (objects, tracks, documents, menu commands) for repeated edits. Preserve access to the GUI for outcomes that need visual judgment.

## Work in the intended window

Observe first, bind actions to the identified app/window, and observe the resulting state. Refresh accessibility references after changes. When controls are not exposed to accessibility, inspect the screenshot and use the current documented visual control mechanism.

Distinguish the tool's capability from the task's authority. The user may already have authorized the operation; apply that authorization throughout the work. An installed tool does not establish its OS permission or access to a particular account. If a real permission or sign-in step needs the user, finish independent work and identify that exact remaining step.

For exported files, check the saved artifact and reopen it in the target application. An action returning successfully is not evidence that a dialog closed, an edit landed, or an export completed.

## References and demonstrated workflows

For creative work with meaningful design choices, keep a short project brief using [creative-brief.md](assets/creative-brief.md). Annotate what each reference contributes and whether that aspect is proposed or explicitly approved. A supplied reference, generated example, or successful tool run does not establish the user's taste. Carry feedback into that project's brief and editable sources.

When the user wants to teach a workflow by showing it, use [Record & Replay](references/record-and-replay.md) and [workflow-template.md](assets/workflow-template.md). Refine the demonstrated intent into parameters and observable outcomes. Recording is optional; do not start one merely to inspect an app or run an existing workflow.

## CLI session example (macOS)

When the chosen harness supports Peekaboo directly:

```bash
peekaboo permissions status --json
peekaboo window list --app Finder --json
peekaboo see --app Finder --json
```

Use the resulting window and fresh snapshot identifiers with semantic actions. Consult `peekaboo help click`, `peekaboo help type`, and `peekaboo help press` for exact selectors. A nonzero result marked unsafe to retry requires observation before another action.

## Long and remote work

Native Codex Computer Use currently supports macOS and Windows, with different background behavior. Linux workloads can use SSH, headless browsers, application CLIs, and render workers; a reachable shell does not establish remote GUI control. Keep task files and artifacts on the execution host and use the native remote connection to steer the same task. Locked macOS use is a separate opt-in OS integration, not a shell permission setting.

Sources: [Codex Computer Use](https://learn.chatgpt.com/docs/computer-use), [Peekaboo](https://github.com/openclaw/Peekaboo), [remote connections](https://learn.chatgpt.com/docs/remote-connections).
