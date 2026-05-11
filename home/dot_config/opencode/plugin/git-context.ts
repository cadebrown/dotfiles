// git-context.ts — opencode plugin: surface git context at session start.
//
// Fires on `session.created`. Pulls `git status -sb` + last 5 commits and
// shows them as a TUI toast (visible) AND writes to the structured log
// (re-readable via `opencode logs`). $ is Bun shell, no extra deps.
//
// Plugin discovery: opencode auto-loads any *.ts/*.js in ~/.config/opencode/plugin/
// (and project-local .opencode/plugin/). No registration needed.

import type { Plugin } from "@opencode-ai/plugin"

export const GitContext: Plugin = async ({ $, client, directory }) => {
  return {
    "session.created": async () => {
      try {
        const status = (await $`git -C ${directory} status -sb`.text()).trim()
        const log = (await $`git -C ${directory} log --oneline -5`.text()).trim()

        const body =
          `git status:\n${status || "(clean)"}\n\n` +
          `recent commits:\n${log || "(no commits)"}`

        await client.tui.showToast({
          body: { message: body, variant: "info" },
        })
        await client.app.log({
          body: { service: "git-context", level: "info", message: body },
        })
      } catch {
        // Not a git repo — silent. Most non-repo dirs don't want noise here.
      }
    },
  }
}
