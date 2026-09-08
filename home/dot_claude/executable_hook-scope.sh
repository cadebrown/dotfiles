#!/bin/bash
# Cheap negative gates for installer-wrapped upstream plugin hooks. Never cache
# applicability: a rule/project added during a session must work on the next call.
set -u
mode="${1:-}"
shift
case "$mode" in
    hookify)
        # Upstream deliberately loads rules relative to the process cwd, not
        # payload.cwd or CLAUDE_PROJECT_DIR. Keep exactly that discovery scope.
        for rule_file in .claude/hookify.*.local.md; do
            [[ -e "$rule_file" || -L "$rule_file" ]] && exec "$@"
        done
        exit 0
        ;;
    lean-prompt|lean-guard) ;;
    *) printf 'Unknown hook scope: %s\n' "$mode" >&2; exit 1 ;;
esac

# An explicit upstream force override applies even outside Lean projects.
[[ "$mode" == lean-guard && "${LEAN4_GUARDRAILS_FORCE:-}" == 1 ]] && exec "$@"
# Preserve the upstream behavior if jq is unavailable. Bash 3.2 can discard
# partial input on read timeout; never use a timed read for the payload.
command -v jq >/dev/null 2>&1 || exec "$@"
[[ -t 0 ]] && exit 0
payload=''
if [[ "$mode" == lean-guard ]]; then
    # Match upstream's bounded cat: a complete payload in a held-open pipe
    # still reaches the guard, before the host's five-second deadline.
    payload="$(
        exec 3<&0
        cat <&3 & reader=$!
        ( sleep 1; kill "$reader" 2>/dev/null ) >/dev/null 2>&1 & timer=$!
        wait "$reader" 2>/dev/null || true
        kill "$timer" 2>/dev/null || true
        wait "$timer" 2>/dev/null || true
    )"
else
    IFS= read -r -d '' payload
fi

if [[ "$mode" == lean-prompt ]]; then
    # contains is conservative: it admits all prompts upstream's Unicode
    # lstrip/prefix test accepts, including JSON-escaped slash/letters.
    jq -e '(.prompt // "") | contains("/lean4:")' >/dev/null 2>&1 <<< "$payload"
    result=$?
    [[ "$result" == 1 ]] && exit 0
else
    project_dir="$(jq -er '(.cwd // .tool_input.cwd // .tool_input.workdir) // "" | strings' 2>/dev/null <<< "$payload")"
    result=$?
    # Invalid input goes to upstream's own parser/error policy.
    if [[ "$result" == 0 ]]; then
        project_dir="${project_dir:-$PWD}"
        [[ "$project_dir" == /* ]] || project_dir="$PWD/$project_dir"
        if [[ -d "$project_dir" ]]; then
            # A symlink into a project may hide its marker in lexical parents.
            project_dir="$(cd -- "$project_dir" && pwd -P)" || exec "$@" <<< "$payload"
            while :; do
                if [[ -f "$project_dir/lakefile.lean" || -f "$project_dir/lean-toolchain" || -f "$project_dir/lakefile.toml" ]]; then
                    exec "$@" <<< "$payload"
                fi
                [[ "$project_dir" == / ]] && break
                project_dir="${project_dir%/*}"
                project_dir="${project_dir:-/}"
            done
        fi
        exit 0
    fi
fi
exec "$@" <<< "$payload"
