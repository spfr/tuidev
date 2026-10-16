# shellcheck shell=bash
# lib/agents/statusline.sh — `agents statusline`: Claude Code's status line
# command, which records Claude's usage limits on the way.
#
# Claude Code runs its statusLine command after each assistant message
# (debounced), with the session's state as JSON on stdin; for Pro and Max
# plans, after the first API response, that holds rate_limits.five_hour and
# rate_limits.seven_day ({used_percentage, resets_at}, each may be absent):
# the only place Claude Code tells its limits without an API call. Shipped
# in ~/.claude/settings.json (configs/claude/settings.json) as
#   [ -x ~/.local/bin/agents ] && exec ~/.local/bin/agents statusline
# so a status line of your own is kept (the settings merge keeps your value),
# and AGENTS_STATUSLINE_CMD (agents.conf) runs yours behind this one.
#
# Uses: config.sh, util.sh (_agents_awk), limits.sh
#   (_agents_limits_put); awk/statusline.awk.
# Public: agents_statusline.

# Status line JSON is a few KiB; a command of yours gets at most this much
# (awk/statusline.awk reads a MiB too).
_AGENTS_STATUSLINE_MAX=1048576

# agents_statusline — read the status line JSON once; record Claude's limit
# windows into limits.tsv when a reading changed (or is 5 minutes old: the
# READ column of `agents limits`); then the status line itself: what
# AGENTS_STATUSLINE_CMD prints for the same JSON (its output and exit status
# untouched), else "Opus · ctx 42% · 5h 23% · wk 41%" (only the fields the
# JSON has). Never fails because of the recording; never prompts.
# One awk does the work (and reads the clock); the JSON is kept in a
# variable only for a command of yours: a status line runs on every message.
agents_statusline() {
    local in="" parsed rows now="" own=""
    if [[ -t 0 ]]; then
        echo "agents statusline: reads Claude Code's status line JSON on stdin (statusLine in ~/.claude/settings.json)" >&2
        return 2
    fi
    # Yours, unless this already runs inside it (a command of yours that
    # calls agents statusline again would loop).
    [[ -z "${AGENTS_STATUSLINE_CMD:-}" || -n "${_AGENTS_STATUSLINE_INNER:-}" ]] || own=1
    [[ -z "${AGENTS_TESTING:-}" ]] || now="${AGENTS_NOW:-}"
    if [[ -n "$own" ]]; then
        in="$(head -c "$_AGENTS_STATUSLINE_MAX" 2>/dev/null)" || in=""
        parsed="$(printf '%s\n' "$in" | _agents_statusline_awk "$now")" || parsed=""
    else
        parsed="$(_agents_statusline_awk "$now")" || parsed=""
    fi
    rows="${parsed#*$'\n'}"; [[ "$parsed" == *$'\n'* ]] || rows=""
    [[ -z "$rows" ]] || _agents_limits_put "" "$rows" 2>/dev/null || true
    if [[ -n "$own" ]]; then
        printf '%s\n' "$in" | _AGENTS_STATUSLINE_INNER=1 /bin/sh -c "$AGENTS_STATUSLINE_CMD"
        return
    fi
    printf '%s\n' "${parsed%%$'\n'*}"
    return 0
}

# _agents_statusline_awk NOW < JSON — awk/statusline.awk (NOW empty: its clock).
_agents_statusline_awk() {
    _agents_awk statusline -v lf="$AGENTS_DATA_DIR/limits.tsv" -v now="$1" -v hist="$AGENTS_HISTORY" 2>/dev/null
}
