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

# _agents_claude_account — limits.tsv's cli and label for this Claude Code
# (REPLY_CLI, REPLY_LABEL): CLAUDE_CONFIG_DIR unset, empty or $HOME/.claude is
# the plain account ("claude", "-"); any other directory is "claude:NAME",
# label NAME: its basename without leading dots and a "claude-" prefix,
# lowercased, [a-z0-9._-] only, at most 24 characters. A basename that says
# no more than "claude" (~/.config/claude, /work/.claude) is named by its
# parent directory the same way, cut to 18 characters, and the first 5 hex
# digits of the path's checksum ("config-1a2b3", "work-4c5d6"), so it never
# shares a row with a directory named so itself (~/.claude-work is "work");
# one directly in $HOME, or with no usable parent name, by "c" and the
# checksum. Only directory names: never an email, a credential file or the
# Keychain, nor your user name.
_agents_claude_account() {
    local d="${CLAUDE_CONFIG_DIR:-}" n p sum
    while [[ "$d" == */ && "$d" != / ]]; do d="${d%/}"; done
    REPLY_CLI=claude REPLY_LABEL=-
    [[ -n "$d" && "$d" != "$HOME/.claude" ]] || return 0
    n="$(_agents_claude_acct_name "${d##*/}")"
    if [[ -z "$n" || "$n" == claude ]]; then
        p="${d%/*}"; n=""
        sum="$(printf '%s' "$d" | cksum | cut -d' ' -f1)"
        [[ "$d" == */* && -n "$p" && "$p" != "$HOME" && "$p" != "${HOME%/}" ]] && n="$(_agents_claude_acct_name "${p##*/}")"
        if [[ -n "$n" && "$n" != claude ]]; then
            printf -v sum '%08x' "$sum"; n="${n:0:18}-${sum:0:5}"
        else
            n="c$sum"
        fi
    fi
    REPLY_CLI="claude:$n" REPLY_LABEL="$n"
}

# _agents_claude_acct_name NAME — a directory name as an account label
# (_agents_claude_account), "" when nothing is left.
_agents_claude_acct_name() {
    printf '%s' "$1" | LC_ALL=C tr '[:upper:]' '[:lower:]' | LC_ALL=C sed -e 's/[^a-z0-9._-]/-/g' -e 's/^[^a-z0-9]*//' -e 's/^claude-//' -e 's/^[^a-z0-9]*//' | cut -c1-24
}

# _agents_statusline_awk NOW < JSON — awk/statusline.awk (NOW empty: its clock).
_agents_statusline_awk() {
    local REPLY_CLI REPLY_LABEL
    _agents_claude_account
    _agents_awk statusline -v lf="$AGENTS_DATA_DIR/limits.tsv" -v now="$1" -v hist="$AGENTS_HISTORY" \
        -v acct="$REPLY_CLI" -v label="$REPLY_LABEL" 2>/dev/null
}
