#!/usr/bin/env bash
# ~/.claude/statusline.sh — custom Claude Code statusline.
#
# Shape (single line, compact, ANSI-colored, segments joined with " │ "):
#   <project> [› <subpath>] │ Δ <branch> [+A -D *S ?U !N x↑↓] │ λ <model> (<effort>, <ctx%>) │
#     <age>/<T>t/<C>c · <In>/<Out> (<cache>% cached) · $<cost> (+$<last>) · <tags>
#
# Each segment renders independently — if any piece errors, the others still
# show. ccline is no longer in the chain; transcript parsing is jq-direct.
#
# Reads JSON via stdin (Claude Code's contract):
#   .workspace.current_dir     string  cwd of the agent
#   .model.display_name        string  pretty name (e.g. "Claude Opus 4.7")
#   .model.id                  string  slug (e.g. "claude-opus-4-7[1m]")
#   .model.effort              string|{level: string}  effort tier
#   .transcript_path           string  path to JSONL transcript for this session
#   (additional fields tolerated but ignored)
#
# Performance: typical 100-130ms cold (bash + jq + 3 git calls). Pathological
# huge-diff cases bounded at ~610ms via 500ms cap on `git diff --shortstat`
# (placeholder `+>100k -<huge>` rendered on timeout). Skipped entirely on clean
# repos. See the bench harness at: tests/bench-statusline.sh (TODO).
#
# DEBUG=1 dumps the parsed input + intermediate values to stderr.
#
# FUTURE: a Rust rewrite using `gix` (gitoxide) would drop typical to ~10-20ms
# (5-10x faster) by avoiding 3 git CLI process startups + jq fork. Would also
# enable real parallelism (bash fork overhead negates parallel git in shell —
# verified by benchmarks). Not worth doing until/unless this version feels slow.

set -uo pipefail

# ─── colors (8-bit, no nerd-font assumptions) ────────────────────────────
_R=$'\e[0m'
_DIM=$'\e[2m'
# Base palette (8-color ANSI for backgrounds, 256-color for the warm tones
# we actually want — terminals on macOS/Linux have universally supported
# 256-color since at least 2015, so this is safe).
# Git counter colors (mostly bright 256-color)
_GREEN=$'\e[32m'           # +N lines added, branch name
_RED=$'\e[31m'             # -N lines removed
_BLUE=$'\e[38;5;39m'       # 256-color #39  — DeepSkyBlue1, *N staged
_ORANGE=$'\e[38;5;208m'    # 256-color #208 — DarkOrange, ?N unstaged + ctx warning tier
_YEL_VIVID=$'\e[38;5;226m' # 256-color #226 — Yellow1, !N untracked
_PINK=$'\e[38;5;175m'      # 256-color #175 — Pink3, ↑N ahead
_ORCHID=$'\e[38;5;213m'    # 256-color #213 — Orchid1, ↓N behind
_BOLDRED=$'\e[1;31m'       # xN merge conflicts (alert)
# Identity colors (per-segment chromatic anchor)
_STEEL=$'\e[38;5;75m'         # 256-color #75  — SteelBlue3, project subpath
_STEELBOLD=$'\e[1;38;5;75m'   # bold project anchor
_SKY=$'\e[38;5;87m'           # 256-color #87  — DeepSkyBlue1, git icon + branch
_PURPLE_MED=$'\e[1;38;5;135m' # 256-color #135 — MediumPurple2, model identity
_PINK_DUSTY=$'\e[1;38;5;175m' # 256-color #175 — Pink3, effort tag
# Semantic aliases
_DIR="$_STEEL"        # directory subpath / non-repo paths
_DIRTOP="$_STEELBOLD" # the "project" anchor (repo name or absolute root)
_GIT="$_SKY"          # git icon + branch name — bright cyan, distinct from project blue
_MODEL="$_PURPLE_MED" # model icon + name — MediumPurple2, distinct cool identity
_EFFORT="$_PINK_DUSTY" # effort tag — Pink3 dusty muted, sits inside the (effort, ctx%) parens
_SESS=$'\e[38;5;247m' # session segment — uniform mid-grey for everything except cache tier
_SEP=$' \e[2;38;5;240m│\e[0m '  # dim grey pipe between segments
_PSEP=$' \e[2m›\e[0m '          # dim chevron between project and subpath

# ─── helpers ─────────────────────────────────────────────────────────────

# Pretty-print a token count: 1234 → "1.2k", 2345678 → "2.3M"
_humanize_tokens() {
    local n="$1"
    if   (( n >= 1000000 )); then printf '%.1fM' "$(echo "$n / 1000000" | bc -l)"
    elif (( n >=    1000 )); then printf '%.1fk' "$(echo "$n / 1000"    | bc -l)"
    else                          printf '%d' "$n"
    fi
}

# Pretty-print a duration in seconds: 42 → "42s", 245 → "4m", 7320 → "2h2m", 90061 → "1d1h"
_humanize_secs() {
    local s="$1"
    if   (( s <    60 )); then printf '%ds' "$s"
    elif (( s <  3600 )); then printf '%dm' $(( s / 60 ))
    elif (( s < 86400 )); then
        local h=$(( s / 3600 ))
        local m=$(( (s % 3600) / 60 ))
        if (( m > 0 )); then printf '%dh%dm' "$h" "$m"
        else                 printf '%dh' "$h"
        fi
    else
        local d=$(( s / 86400 ))
        local h=$(( (s % 86400) / 3600 ))
        if (( h > 0 )); then printf '%dd%dh' "$d" "$h"
        else                 printf '%dd' "$d"
        fi
    fi
}

# Per-model pricing table for cost estimates. $/MTok for {in, out, cache_read, cache_write_5m, cache_write_1h}.
# Keep in sync with https://www.anthropic.com/pricing#api when models are added.
_pricing() {
    case "$1" in
        claude-opus-4*|*opus-4*)         echo "15 75 1.50 18.75 30.00" ;;
        claude-sonnet-4*|*sonnet-4*)     echo "3 15 0.30 3.75 6.00"   ;;
        claude-haiku-4*|*haiku-4*)       echo "1 5 0.10 1.25 2.00"    ;;
        *)                                echo ""                       ;;
    esac
}

_cost_usd() {
    # Args: model_id in_tok out_tok cache_read_tok cache_write_5m_tok cache_write_1h_tok
    local price; price="$(_pricing "$1")"
    [[ -z "$price" ]] && { printf ''; return; }
    read -r p_in p_out p_cr p_cw5 p_cw1 <<<"$price"
    echo "scale=2; ($2*$p_in + $3*$p_out + $4*$p_cr + $5*$p_cw5 + $6*$p_cw1) / 1000000" | bc -l
}

# Bash-native timeout. Runs $@ with a wall-clock cap of $1 seconds (fractional
# ok). Returns 124 on timeout, else command's exit code. Stdout passes through.
# macOS doesn't ship `timeout`, so we roll our own — no coreutils dep.
#
# IMPORTANT: the watcher's stdio is redirected to /dev/null so it doesn't keep
# the parent $() capture pipe open. Without this, $() would block waiting for
# the watcher's sleep to finish, defeating the whole point of the timeout.
_timed() {
    local timeout_s="$1"; shift
    "$@" &
    local pid=$!
    { sleep "$timeout_s" && kill -KILL "$pid" 2>/dev/null; } >/dev/null 2>&1 &
    local watcher=$!
    wait "$pid" 2>/dev/null
    local rc=$?
    kill -TERM "$watcher" 2>/dev/null
    [[ $rc -ge 128 ]] && return 124
    return $rc
}

# Color a cache-hit % — high cache is GOOD, so green at top:
#   ≥90  DarkSeaGreen3 (115) — healthy, cache working
#   ≥70  Gold1         (220) — notice, leaking some
#   ≥40  DarkOrange    (208) — warning, cache eroding
#   <40  Red1          (196) — broken, cost spiking
_cache_color() {
    local pct="$1"
    [[ -z "$pct" ]] && { printf '%s' "$_DIM"; return; }
    local pct_int="${pct%.*}"
    if   (( pct_int >= 90 )); then printf '\e[38;5;115m'
    elif (( pct_int >= 70 )); then printf '\e[38;5;220m'
    elif (( pct_int >= 40 )); then printf '\e[38;5;208m'
    else                            printf '\e[38;5;196m'
    fi
}

# ─── parse stdin ─────────────────────────────────────────────────────────
INPUT="$(cat)"

if ! command -v jq >/dev/null 2>&1; then
    printf '%s[jq missing — install via brew]%s' "$_DIM" "$_R"
    exit 0
fi

CWD="$(printf       '%s' "$INPUT" | jq -r '.workspace.current_dir // .cwd // "."')"
MODEL_NAME="$(printf '%s' "$INPUT" | jq -r '.model.display_name // ""')"
MODEL_ID="$(printf   '%s' "$INPUT" | jq -r '.model.id // ""')"
TRANSCRIPT="$(printf '%s' "$INPUT" | jq -r '.transcript_path // ""')"
#  Claude Code wraps effort as {"level":"max"} — extract .level if object, else use as-is.
EFFORT="$(printf     '%s' "$INPUT" | jq -r '
    (.model.effort // .effort // .effortLevel // "") as $e |
    if ($e | type) == "object" then ($e.level // "") else $e end
')"

if [[ "${DEBUG:-0}" == "1" ]]; then
    {
        echo "=== statusline.sh debug ==="
        echo "INPUT:";   printf '%s' "$INPUT" | jq . 2>&1 | head -30
        echo "parsed: cwd=$CWD model_name=$MODEL_NAME model_id=$MODEL_ID effort=$EFFORT transcript=$TRANSCRIPT"
    } >&2
fi

# ─── compute session stats (single jq pass, shared by model + session segs) ─
# Fields produced:
#   $turns  $ctx  $tin $tout $tcr $tcw5 $tcw1   (sums + last-turn ctx, as before)
#   $age    seconds between first and last assistant timestamps
#   $tools  count of `tool_use` blocks across all assistant turns
#   $lin $lout $lcr $lcw5 $lcw1   token breakdown of the LAST assistant turn (for Δ$)
TURNS=0 CTX=0 TIN=0 TOUT=0 TCR=0 TCW5=0 TCW1=0 AGE=0 TOOLS=0
LIN=0 LOUT=0 LCR=0 LCW5=0 LCW1=0
HAVE_STATS=0
PCT=""
if [[ -n "$TRANSCRIPT" && -r "$TRANSCRIPT" ]]; then
    _stats="$(jq -s -r '
        [ .[] | select(.type == "assistant") ] as $a |
        ($a | length) as $turns |
        ($a | last  // {}) as $last |
        ($a | first // {}) as $firstm |
        ($last.message.usage // {}) as $u |
        (($u.input_tokens // 0)
         + ($u.output_tokens // 0)
         + ($u.cache_read_input_tokens // 0)
         + ($u.cache_creation_input_tokens // 0)) as $ctx |
        ($a | map(.message.usage // {})) as $usages |
        ($usages | map(.input_tokens             // 0) | add // 0) as $tin |
        ($usages | map(.output_tokens            // 0) | add // 0) as $tout |
        ($usages | map(.cache_read_input_tokens  // 0) | add // 0) as $tcr |
        ($usages | map(.cache_creation.ephemeral_5m_input_tokens // 0) | add // 0) as $tcw5 |
        ($usages | map(.cache_creation.ephemeral_1h_input_tokens // 0) | add // 0) as $tcw1 |
        ($firstm.timestamp // "" | sub("\\.[0-9]+Z$"; "Z") | try fromdateiso8601 catch 0) as $first_s |
        ($last.timestamp   // "" | sub("\\.[0-9]+Z$"; "Z") | try fromdateiso8601 catch 0) as $last_s |
        (if ($last_s > 0 and $first_s > 0) then ($last_s - $first_s) else 0 end) as $age |
        ([ .[] | select(.type=="assistant") | (.message.content // [])[]?
          | select(.type == "tool_use") ] | length) as $tools |
        ($u.input_tokens                                 // 0) as $lin |
        ($u.output_tokens                                // 0) as $lout |
        ($u.cache_read_input_tokens                      // 0) as $lcr |
        ($u.cache_creation.ephemeral_5m_input_tokens     // 0) as $lcw5 |
        ($u.cache_creation.ephemeral_1h_input_tokens     // 0) as $lcw1 |
        "\($turns) \($ctx) \($tin) \($tout) \($tcr) \($tcw5) \($tcw1) \($age) \($tools) \($lin) \($lout) \($lcr) \($lcw5) \($lcw1)"
    ' "$TRANSCRIPT" 2>/dev/null)"
    if [[ -n "$_stats" ]]; then
        read -r TURNS CTX TIN TOUT TCR TCW5 TCW1 AGE TOOLS LIN LOUT LCR LCW5 LCW1 <<<"$_stats"
        HAVE_STATS=1
    fi
fi
# Context window: 1M for [1m] variants, otherwise 200k default.
CTX_MAX=200000
[[ "$MODEL_ID" == *"[1m]"* ]] && CTX_MAX=1000000
if (( CTX > 0 )); then
    PCT="$(echo "scale=1; $CTX * 100 / $CTX_MAX" | bc -l)"
fi

# ─── worktree + subagent detection (cheap; for session-segment tags) ────────
IN_WORKTREE=0
_wtmeta="$(git -C "$CWD" rev-parse --git-dir --git-common-dir 2>/dev/null)"
if [[ -n "$_wtmeta" ]]; then
    _gd="$(printf '%s\n' "$_wtmeta" | head -1)"
    _gcd="$(printf '%s\n' "$_wtmeta" | tail -1)"
    [[ -n "$_gd" && "$_gd" != "$_gcd" ]] && IN_WORKTREE=1
fi
# Subagent: best-effort. Claude Code may set `.agent`, `.agent_id`, or similar
# in the statusline JSON when rendering inside a sub-agent context. Field name
# isn't documented yet; we check a few likely candidates and degrade silently.
SUBAGENT="$(printf '%s' "$INPUT" | jq -r '
    if (.agent      // null) != null and (.agent      | tostring) != "" and (.agent      | tostring) != "null" then "1"
    elif (.agent_id // null) != null then "1"
    elif (.is_subagent // false) == true then "1"
    elif (.parent_session_id // null) != null then "1"
    else "" end' 2>/dev/null)"

# ─── segment: directory ──────────────────────────────────────────────────
# Three rendering modes, picked by where CWD sits:
#   1. inside a git repo  → "<project>" or "<project> › <subpath>"
#                           project bold sky-cyan, subpath regular sky-cyan
#   2. inside $HOME       → "~/path/to" (one segment, regular sky-cyan)
#   3. anywhere else      → "/abs/path" (one segment, regular sky-cyan)
_dir_segment() {
    local repo
    if repo="$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null)"; then
        local repo_name; repo_name="$(basename "$repo")"
        local rel="${CWD#"$repo"}"; rel="${rel#/}"
        if [[ -n "$rel" ]]; then
            printf '%s%s%s%s%s%s%s' "$_DIRTOP" "$repo_name" "$_R" "$_PSEP" "$_DIR" "$rel" "$_R"
        else
            printf '%s%s%s' "$_DIRTOP" "$repo_name" "$_R"
        fi
    elif [[ "$CWD" == "$HOME" || "$CWD" == "$HOME"/* ]]; then
        # Prefix-removal then prepend "~" — bash's ${var/#pat/repl} silently
        # fails when both var and pat start with "/", so don't use it here.
        local short="~${CWD#"$HOME"}"
        printf '%s%s%s' "$_DIR" "$short" "$_R"
    else
        printf '%s%s%s' "$_DIR" "$CWD" "$_R"
    fi
}

# ─── segment: git (branch + status counts + upstream + diff lines) ───────
# Examples (each suffix is independent — hidden when zero):
#   Δ main                              clean, in sync
#   Δ main *2                            2 staged
#   Δ main *2 ?1                         2 staged, 1 unstaged
#   Δ main *2 ?1 !1                      + 1 untracked
#   Δ main ?3 ↑2                         3 unstaged, 2 commits ahead
#   Δ main x2                            2 conflicted (merge in progress)
#   Δ main *2 ?1  +248 -9                file counts + line diff vs HEAD
#   Δ detached@a1b2c3d                   detached HEAD
#
# Symbol convention:
#   * = staged   (added to index, ready to commit)
#   ? = unstaged (modified, not yet staged)
#   ! = untracked (new file git doesn't know about)
#   x = conflict (merge in progress, needs resolution)
#   + = lines added vs HEAD
#   - = lines removed vs HEAD
#   ↑ = commits ahead of upstream
#   ↓ = commits behind upstream
#
# Color convention:
#   green:    branch name, *staged, +lines added
#   red:      ?unstaged, -lines removed
#   yellow:   !untracked, ↓behind
#   bold red: xconflicted
#   cyan:     ↑ahead
_git_segment() {
    local branch
    if ! branch="$(git -C "$CWD" symbolic-ref --short HEAD 2>/dev/null)"; then
        local sha; sha="$(git -C "$CWD" rev-parse --short HEAD 2>/dev/null)" || return
        printf '%sΔ detached@%s%s' "$_DIM" "$sha" "$_R"
        return
    fi

    # Single porcelain pass — captures branch tracking + every file's status code.
    local porc; porc="$(git -C "$CWD" status --porcelain=v1 --branch --untracked-files=normal 2>/dev/null)"

    # Parse upstream "## main...origin/main [ahead 2, behind 1]" header
    local ahead=0 behind=0 head_line
    head_line="$(printf '%s\n' "$porc" | head -1)"
    if [[ "$head_line" == *"[ahead "* ]]; then
        local tmp="${head_line#*[ahead }"
        ahead="${tmp%%,*}"; ahead="${ahead%]*}"
    fi
    if [[ "$head_line" == *"behind "* ]]; then
        local tmp="${head_line#*behind }"
        behind="${tmp%]*}"
    fi

    # Per-file counts. Conflict patterns from `git status` docs:
    #   DD AU UD UA DU AA UU
    local staged=0 unstaged=0 untracked=0 conflicts=0
    while IFS= read -r line; do
        [[ -z "$line" || "$line" == "##"* ]] && continue
        local xy="${line:0:2}"
        case "$xy" in
            "??") (( untracked++ )) ;;
            "DD"|"AU"|"UD"|"UA"|"DU"|"AA"|"UU") (( conflicts++ )) ;;
            *)
                local x="${line:0:1}" y="${line:1:1}"
                [[ "$x" != " " ]] && (( staged++ ))
                [[ "$y" != " " ]] && (( unstaged++ ))
                ;;
        esac
    done <<<"$porc"

    # Line-diff (vs HEAD): includes staged + unstaged TRACKED changes only.
    # Untracked files are not in HEAD, so `git diff HEAD` already ignores them.
    # - Skip entirely when no tracked changes (saves ~20ms on clean repos).
    # - Hard-cap at 500ms; on timeout, render `+>100k` placeholder so a huge
    #   uncommitted diff doesn't block the prompt.
    local diff_added=0 diff_removed=0 diff_huge=0 shortstat
    if (( staged > 0 || unstaged > 0 )); then
        shortstat="$(_timed 0.5 git -C "$CWD" diff --shortstat HEAD 2>/dev/null)"
        if [[ $? -eq 124 ]]; then
            diff_huge=1
        elif [[ -n "$shortstat" ]]; then
            diff_added="$(  printf '%s' "$shortstat" | grep -oE '[0-9]+ insertion' | grep -oE '[0-9]+' || echo 0)"
            diff_removed="$(printf '%s' "$shortstat" | grep -oE '[0-9]+ deletion'  | grep -oE '[0-9]+' || echo 0)"
            diff_added="${diff_added:-0}"
            diff_removed="${diff_removed:-0}"
        fi
    fi

    # Compose — order: branch → +/- diffs → file counts → conflicts → upstream
    local out="${_GIT}Δ ${branch}${_R}"
    if (( diff_huge )); then
        out+=" ${_GREEN}+>100k${_R} ${_RED}->100k${_R}"
    fi
    (( diff_added   > 0 )) && out+=" ${_GREEN}+${diff_added}${_R}"
    (( diff_removed > 0 )) && out+=" ${_RED}-${diff_removed}${_R}"
    (( staged    > 0 )) && out+=" ${_BLUE}*${staged}${_R}"
    (( unstaged  > 0 )) && out+=" ${_ORANGE}?${unstaged}${_R}"
    (( untracked > 0 )) && out+=" ${_YEL_VIVID}!${untracked}${_R}"
    (( conflicts > 0 )) && out+=" ${_BOLDRED}x${conflicts}${_R}"
    (( ahead     > 0 )) && out+=" ${_PINK}↑${ahead}${_R}"
    (( behind    > 0 )) && out+=" ${_ORCHID}↓${behind}${_R}"
    printf '%s' "$out"
}

# ─── segment: model + effort + context% ──────────────────────────────────
# Uses Anthropic's canonical naming. Drops "Claude" prefix (every Claude Code
# model is a Claude) and the bracketed variant tag (e.g. "[1m]") — context %
# already reflects the tier.
#
#   claude-opus-4-7              → Opus 4.7
#   claude-opus-4-7[1m]          → Opus 4.7      (1M variant inferred via ctx denominator)
#   claude-sonnet-4-6            → Sonnet 4.6
#   claude-haiku-4-5-20251001    → Haiku 4.5     (date suffix dropped)
#
# Suffix "(effort, ctx%)" is a single grouped piece of meta-info:
#   - effort intensity-colored (dim → cyan → yellow → orange → bold red)
#   - ctx% threshold-colored   (cyan <50 → yellow <80 → bold red ≥80)
#   - parens themselves dim so the values pop
_model_segment() {
    local id="$MODEL_ID"

    # Strip [..] variant suffix and "claude-" prefix
    [[ "$id" == *"["*"]"* ]] && id="${id%[*}"
    id="${id#claude-}"

    # Match family-X-Y[-extra] where -extra is typically a date stamp
    local pretty=""
    if [[ "$id" =~ ^([a-z]+)-([0-9]+)-([0-9]+) ]]; then
        local family="${BASH_REMATCH[1]}"
        local major="${BASH_REMATCH[2]}"
        local minor="${BASH_REMATCH[3]}"
        if [[ -n "${BASH_VERSION:-}" && "${BASH_VERSINFO[0]}" -ge 4 ]]; then
            family="${family^}"
        else
            family="$(printf '%s%s' "$(printf '%s' "${family:0:1}" | tr '[:lower:]' '[:upper:]')" "${family:1}")"
        fi
        pretty="${family} ${major}.${minor}"
    elif [[ -n "$MODEL_NAME" ]]; then
        pretty="${MODEL_NAME#Claude }"
    else
        pretty="$id"
    fi

    local out="${_MODEL}λ ${pretty}${_R}"

    # Build "(effort, ctx%)" suffix — only if at least one piece is present.
    # Effort keeps its pink color; ctx% is uniform grey (no tier coloring).
    if [[ -n "$EFFORT" || -n "$PCT" ]]; then
        local body=""
        if [[ -n "$EFFORT" ]]; then
            body+="${_EFFORT}${EFFORT}${_R}"
        fi
        if [[ -n "$PCT" ]]; then
            [[ -n "$body" ]] && body+="${_DIM}, ${_R}"
            body+="${_SESS}${PCT}%${_R}"
        fi
        out+=" ${_DIM}(${_R}${body}${_DIM})${_R}"
    fi

    printf '%s' "$out"
}

# ─── segment: session stats ──────────────────────────────────────────────
# Layout (groups joined by " · ", pieces joined by "/" or " "):
#   <age>/<turns>t/<tools>c  ·  <total_in>/<total_out> (<cache>% cached)  ·  $<cost> (+$<lastturn>)  [·  <tags>]
#
# All data text in uniform _SESS grey; bullets dim; no leading icon.
#
# Where:
#   age      = humanized first→last assistant timestamp diff (e.g. "2h10m")
#   turns    = # of assistant turns
#   tools    = # of tool_use blocks across all turns ("c" = calls)
#   total_in = TIN + TCR + TCW5 + TCW1 (everything model received, incl. cache)
#   total_out = TOUT (everything model produced)
#   cache%   = TCR / total_in × 100 — efficiency signal; drop = cost spike alarm
#   $cost    = total session cost in USD
#   $lastturn = last assistant turn's cost (only when > $0.01)
#   tags     = "wt" if in worktree, "sub" if in sub-agent (only when present)
_session_segment() {
    (( HAVE_STATS )) || return

    # Group 1: turns / tools (age) — work counters, age parenthetical
    local g1="${TURNS}t/${TOOLS}c ($(_humanize_secs "$AGE"))"

    # Group 2: tokens — total_in / total_out, cache% inside parens (tiered color)
    local total_in=$(( TIN + TCR + TCW5 + TCW1 ))
    local g2_pre="$(_humanize_tokens "$total_in")/$(_humanize_tokens "$TOUT")"
    local cache_pct=""
    if (( total_in > 0 )); then
        cache_pct="$(echo "scale=0; $TCR * 100 / $total_in" | bc -l)"
    fi

    # Group 3: cost + last-turn cost (warm tan). bc returns ".76" for sub-1
    # values, so pad with leading 0 to render "$0.76" instead of "$.76".
    local cost lastcost have_cost=0
    cost="$(_cost_usd "$MODEL_ID" "$TIN" "$TOUT" "$TCR" "$TCW5" "$TCW1")"
    if [[ -n "$cost" ]]; then
        [[ "$cost" == .* ]] && cost="0$cost"
        have_cost=1
        lastcost="$(_cost_usd "$MODEL_ID" "$LIN" "$LOUT" "$LCR" "$LCW5" "$LCW1")"
        if [[ -n "$lastcost" ]] && (( $(echo "$lastcost > 0.01" | bc -l) )); then
            [[ "$lastcost" == .* ]] && lastcost="0$lastcost"
        else
            lastcost=""
        fi
    fi

    # Group 4: tags (worktree, subagent) — only shown when at least one is set
    local tags=""
    (( IN_WORKTREE )) && tags+="wt"
    [[ -n "$SUBAGENT" ]] && { [[ -n "$tags" ]] && tags+=" "; tags+="sub"; }

    # Assemble — bullet-separated groups, suppress empties.
    # Colors: activity grey, cache% tiered, cost warm tan, tags grey.
    local sep="${_DIM} · ${_R}"
    local out="${_SESS}${g1}${_R}"

    # Group 2: tokens with optional tiered cache%
    out+="${sep}${_SESS}${g2_pre}"
    if [[ -n "$cache_pct" ]]; then
        out+=" ${_DIM}(${_R}$(_cache_color "$cache_pct")${cache_pct}%${_R}${_DIM})${_R}"
    else
        out+="${_R}"
    fi

    # Group 3: cost + last-turn cost (grey, no warm emphasis)
    if (( have_cost )); then
        out+="${sep}${_SESS}\$${cost}${_R}"
        [[ -n "$lastcost" ]] && out+=" ${_DIM}(+${_R}${_SESS}\$${lastcost}${_R}${_DIM})${_R}"
    fi

    # Group 4: tags
    [[ -n "$tags" ]] && out+="${sep}${_SESS}${tags}${_R}"

    printf '%s' "$out"
}

# ─── compose ─────────────────────────────────────────────────────────────
DIR_SEG="$(_dir_segment)"
GIT_SEG="$(_git_segment)"
MODEL_SEG="$(_model_segment)"
SESS_SEG="$(_session_segment)"

out=""
for seg in "$DIR_SEG" "$GIT_SEG" "$MODEL_SEG" "$SESS_SEG"; do
    [[ -z "$seg" ]] && continue
    [[ -n "$out" ]] && out+="$_SEP"
    out+="$seg"
done

printf '%s' "$out"
