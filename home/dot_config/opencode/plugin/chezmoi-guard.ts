import type { Plugin } from "@opencode-ai/plugin"

// Chezmoi-guard OpenCode plugin — blocks edits to chezmoi-managed deployed
// dotfiles (e.g. ~/.zshrc), pointing the agent at the source under
// ~/dotfiles/home/ instead. The opencode sibling of the Claude/Codex
// PreToolUse hook; ALL detection logic lives in ~/.local/bin/df-chezmoi-guard
// (exit 2 = blocked) — this is a thin protocol adapter.

export const ChezmoiGuardPlugin: Plugin = async ({ $ }) => {
  try {
    await $`which df-chezmoi-guard`.quiet()
  } catch {
    // Guard not deployed (bootstrap not run) — plugin inert.
    return {}
  }

  return {
    "tool.execute.before": async (input, output) => {
      const tool = String(input?.tool ?? "").toLowerCase()
      if (tool !== "edit" && tool !== "write" && tool !== "apply_patch") return
      const args = output?.args as Record<string, unknown> | undefined
      if (!args) return

      // edit/write carry filePath; apply_patch carries patchText, which the
      // guard parses from the `command` field (same as Codex's payload).
      const tool_input: Record<string, unknown> = {}
      if (typeof args.filePath === "string") tool_input.filePath = args.filePath
      if (typeof args.patchText === "string") tool_input.command = args.patchText
      if (Object.keys(tool_input).length === 0) return

      const payload = JSON.stringify({ tool_input, cwd: process.cwd() })
      try {
        const result = await $`printf '%s' ${payload} | df-chezmoi-guard`
          .quiet()
          .nothrow()
        if (result.exitCode === 2) {
          const reason = String(result.stderr).trim()
          throw new Error(
            reason ||
              "Blocked: chezmoi-managed path — edit the source under ~/dotfiles/home/ and run 'chezmoi apply'",
          )
        }
      } catch (err) {
        if (err instanceof Error && err.message.startsWith("Blocked:")) throw err
        // Guard malfunction — fail open, never break editing.
      }
    },
  }
}
