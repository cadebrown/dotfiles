#!/usr/bin/env bash
# ~/.codex/rtk-rewrite.sh — Codex PreToolUse hook: rewrite shell commands
# through rtk for token compression. The Codex sibling of
# dot_claude/rtk-rewrite.sh (Claude) and the opencode/pi TS plugins; all
# rewrite logic lives in `rtk rewrite` (the Rust registry) — this is a thin
# protocol adapter.
#
# Codex hook protocol (learn.chatgpt.com/docs/hooks, codex >= 0.135):
#   stdin:  {"hook_event_name":"PreToolUse","tool_name":"Bash",
#            "tool_input":{"command":"..."}, ...}
#   stdout: {"hookSpecificOutput":{"hookEventName":"PreToolUse",
#            "permissionDecision":"allow","updatedInput":{"command":"..."}}}
#   empty stdout + exit 0 = continue unchanged.
#
# rtk rewrite exit contract: 0 rewrite+allow, 1 passthrough, 2 deny,
# 3 rewrite-but-ask. Codex PreToolUse cannot express "rewrite AND ask", so
# 2/3 pass through UNREWRITTEN. The default full-auto policy runs the original;
# an explicitly interactive session can still apply rules/dotfiles.rules.
# `permissionDecision: allow` fires only for commands rtk actively rewrote,
# i.e. noisy read-only commands — never the destructive ones rtk skips.
set -uo pipefail

# Dock/GUI-launched Codex misses the login-shell PATH.
export PATH="$HOME/.local/bin:$HOME/.local/cargo/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

command -v rtk >/dev/null 2>&1 || exit 0
command -v jq  >/dev/null 2>&1 || exit 0
[[ "${RTK_DISABLED:-0}" == "1" ]] && exit 0

_input="$(cat)"
_cmd="$(printf '%s' "$_input" | jq -r '.tool_input.command // empty' 2>/dev/null)"
[[ -z "$_cmd" ]] && exit 0
case "$_cmd" in rtk\ *) exit 0 ;; esac

_rewritten="$(rtk rewrite "$_cmd" 2>/dev/null)"
_rc=$?
if [[ $_rc -eq 0 && -n "$_rewritten" && "$_rewritten" != "$_cmd" ]]; then
    jq -nc --arg cmd "$_rewritten" \
        '{hookSpecificOutput:{hookEventName:"PreToolUse",
          permissionDecision:"allow", updatedInput:{command:$cmd}}}'
fi
exit 0
