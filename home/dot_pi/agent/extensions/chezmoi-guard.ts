// Chezmoi-guard Pi extension — blocks edits to chezmoi-managed deployed
// dotfiles (e.g. ~/.zshrc), pointing the agent at the source under
// ~/dotfiles/home/ instead. The pi sibling of the Claude/Codex PreToolUse
// hook; ALL detection logic lives in ~/.local/bin/df-chezmoi-guard
// (exit 2 = blocked) — this is a thin protocol adapter.

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent"
import { isToolCallEventType } from "@earendil-works/pi-coding-agent"

const GUARD_TIMEOUT_MS = 3_000

export default async function (pi: ExtensionAPI) {
  // Probe once at load; extension is inert when the guard isn't deployed.
  const probe = await pi.exec("bash", ["-c", "command -v df-chezmoi-guard"], {
    timeout: GUARD_TIMEOUT_MS,
  })
  if (probe.code !== 0) {
    console.warn("[chezmoi-guard] df-chezmoi-guard not on PATH — extension disabled")
    return
  }

  pi.on("tool_call", async (event, ctx) => {
    try {
      const isEdit = isToolCallEventType("edit", event)
      const isWrite = isToolCallEventType("write", event)
      if (!isEdit && !isWrite) return

      const path = (event.input as { path?: unknown }).path
      if (typeof path !== "string" || path.trim() === "") return

      // The guard accepts `path` in tool_input and resolves ~ / relative
      // against cwd — same payload shape Claude and Codex hooks send.
      const payload = JSON.stringify({ tool_input: { path }, cwd: process.cwd() })
      const result = await pi.exec(
        "bash",
        ["-c", 'df-chezmoi-guard <<< "$1"', "_", payload],
        { timeout: GUARD_TIMEOUT_MS, signal: ctx.signal },
      )
      if (result.code === 2) {
        const reason =
          result.stderr.trim() ||
          "Blocked: chezmoi-managed path — edit the source under ~/dotfiles/home/ and run 'chezmoi apply'"
        return { block: true, reason }
      }
    } catch (err) {
      // Fail open: never break editing on a guard malfunction.
      console.warn("[chezmoi-guard] unexpected error; allowing tool call", err)
      return
    }
  })
}
