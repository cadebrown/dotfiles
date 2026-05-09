#!/usr/bin/env bash
# ~/.claude/statusline.sh — wraps ccline to rewrite the context segment text.
#
# ccline 1.1.2 hardcodes the context_window format as "{percent}% · {tokens}k
# tokens" with no config option (see src/core/segments/context_window.rs).
# We don't need the absolute token count — the percentage is what matters
# for "am I about to hit the wall". Substitute on the rendered output.
#
# Examples:
#   "12.3% · 45.6k tokens"  →  "12.3% used"
#   "0% · 999 tokens"       →  "0% used"
#   "- · - tokens"          →  unchanged (no transcript yet — early in session)
ccline | sed -E 's/([0-9.]+%) · [0-9.]+k? tokens/\1 used/g'
