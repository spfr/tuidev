#!/bin/bash

# ============================================================================
# notify.sh — one notification helper for agent hooks, on any host
# ============================================================================
# Called from Claude Code hooks (configs/claude/settings.json) and, opt-in,
# Codex's `notify` (configs/codex/config.toml). The channels:
#
#   1. herdr toast          inside a herdr pane (HERDR_ENV=1)
#   2. tmux status line     inside tmux ($TMUX)
#   3. macOS banner         terminal-notifier (clickable), else osascript
#   4. Linux desktop        notify-send, when installed
#   5. ntfy push            only when NTFY_URL is set (e.g. https://ntfy.sh/topic)
#   6. nothing              silent no-op
#
# The first of 1 and 2 that works shows it in the terminal. On a Mac the
# banner (3) shows it too, because a toast or a status line can't be seen
# from another app, unless the session is one you reach over ssh
# (is_remote) or, inside Herdr, you are at the Mac looking at the session's
# own pane (at_terminal: its terminal app in front, its pane Herdr's focused
# one): then the toast, with Herdr's own sound, is the one alert. tmux's
# status line is silent and brief, so tmux keeps the banner. Otherwise the
# first of 3 to 5 that works does. Pushing to a phone when nobody reacts is
# left to whatever escalates for you; ntfy (5) is for setups without one.
#
# Clicking the banner takes you to the session that asked. When this runs
# under a claude or codex process and the `agents` command is installed
# (the monitoring pack), `agents root-of` names that session as PID@START
# now (the hook is long gone by the click) and hands over the command a
# click runs, `agents jump PID@START`, built and quoted by agents itself:
# its Herdr pane, tmux pane, or Ghostty, iTerm or Terminal tab, refused if
# the pid has since been reused. The banner also brings that terminal app
# forward, and a newer notification from the same session replaces the
# older one. Without terminal-notifier the banner is osascript's, which a
# click can't take anywhere; without agents it is a plain banner.
#
# With the monitoring pack (its data directory, AGENTS_DATA_DIR, already
# exists; this never creates it), each notification is logged for `agents
# report --view waits`, one line appended to notify.tsv there:
#   epoch session project kind channels banner_skipped
# session: the agent session's PID@START, "-" when agents knows none;
# project: the session's directory as agents names it (CLAUDE_PROJECT_DIR,
# else the working directory); kind: the subtitle (Permission, Idle…) or
# "-"; channels: those that showed it (herdr, tmux, banner, osascript,
# notify-send, ntfy) or none; banner_skipped: present (you were at the Mac,
# in front of the session) or remote (a session reached over ssh), else "-".
# Never the message. AGENTS_HISTORY=0, in the environment or agents.conf,
# logs nothing; `agents sample` drops lines older than AGENTS_HISTORY_DAYS.
#
# It never prints and always exits 0: hook stdout is parsed by the calling CLI,
# and a failed notification must not surface as a hook error. Every outside
# command it waits for is bounded by a timeout, with every process it starts.
#
# Usage:
#   notify.sh <title> <message> [subtitle] [sound]
#
# Under a Claude Code hook (CLAUDE_PROJECT_DIR is set), the hook's JSON on
# stdin replaces <message> with its own "message" when jq can read one, so
# the banner says what the session is waiting for. Any other caller's stdin
# is left alone.
#
# Examples:
#   notify.sh "Claude Code" "Task completed"
#   notify.sh "Claude Code" "Needs your approval" "Permission"
#   notify.sh "Build" "Tests passed" "CI" "Glass"
#
# Sounds (macOS only): Basso, Blow, Bottle, Frog, Funk, Glass, Hero, Morse,
#   Ping, Pop, Purr, Sosumi, Submarine, Tink
#
# Environment: TUIDEV_TERMINAL_NOTIFIER names the terminal-notifier to use
# (empty: none); it is otherwise Homebrew's, then the one on PATH.
# TUIDEV_NOTIFY_PRESENT_IDLE (seconds, default 120) is how long since the
# last key or mouse move you still count as at the Mac; 0 or
# TUIDEV_NOTIFY_BANNER=always shows the banner inside Herdr whether you are
# there or not.
# ============================================================================

TITLE="${1:-}"
MESSAGE="${2:-}"
SUBTITLE="${3:-}"
SOUND="${4:-Glass}"

[[ -n "$TITLE" && -n "$MESSAGE" ]] || exit 0

have() { command -v "$1" >/dev/null 2>&1; }

# Message with the subtitle folded in, for channels that have no subtitle field.
BODY=""

# with_timeout SECS CMD... — CMD (stdin from /dev/null), killed after SECS
# seconds with every process it started: 124 then. Job control gives CMD
# and the watcher a process group each, so the kill reaches grandchildren
# (which would hold a $( ) open) and the watcher's sleep goes when CMD ends
# first. lib/agents/util.sh's _agents_timeout is the same; this script
# stands alone (it runs without the monitoring pack).
with_timeout() {
    local secs="$1"; shift
    (
        set +e -m
        "$@" </dev/null &
        pid=$!
        ( sleep "$secs"; kill -TERM -- "-$pid" ) >/dev/null 2>&1 &
        watcher=$!
        wait "$pid" 2>/dev/null; rc=$?
        kill -TERM -- "-$watcher" 2>/dev/null || [[ $rc -lt 128 ]] || rc=124
        exit "$rc"
    )
}

# hook_message — the "message" of a Claude Code hook's JSON on stdin, when
# there is one (read for at most 2 s) and jq can read it, cut to 200
# characters.
hook_message() {
    local input="" msg
    [[ -n "${CLAUDE_PROJECT_DIR:-}" && ! -t 0 ]] && have jq || return 0
    IFS= read -r -d '' -t 2 input || true
    [[ "$input" == *'"message"'* ]] || return 0
    # shellcheck disable=SC2016  # jq's own $in
    msg="$(with_timeout 2 jq -rn --arg in "$input" '$in | fromjson? | .message? | strings' 2>/dev/null)"
    [[ -n "$msg" ]] && printf '%s' "${msg:0:200}"
}

notify_herdr() {
    [[ "${HERDR_ENV:-}" == 1 ]] && have herdr || return 1
    with_timeout 3 herdr notification show "$TITLE" --body "$BODY"
}

notify_tmux() {
    [[ -n "${TMUX:-}" ]] && have tmux || return 1
    local text="[$TITLE] $BODY"
    # -l prints the text literally (tmux >= 3.4). Older tmux: escape `#` so a
    # message cannot expand formats such as #(command).
    with_timeout 2 tmux display-message -l "$text" || with_timeout 2 tmux display-message "${text//#/##}"
}

is_macos() { [[ "$(uname -s 2>/dev/null)" == Darwin ]]; }

# in_focused_pane — true when Herdr says the pane this session runs in
# (HERDR_PANE_ID, which Herdr sets in each pane and the hook inherits) is
# the focused one: `herdr pane get`, over its socket, bounded to a second
# (it takes 10-30 ms). Its "focused" is Herdr's own focus, one pane across
# every workspace and tab. False when the pane is unknown, Herdr can't
# answer or names another pane: the banner shows.
in_focused_pane() {
    local pane="${HERDR_PANE_ID:-}" out
    [[ "$pane" =~ ^[A-Za-z0-9:_-]+$ ]] || return 1
    out="$(with_timeout 1 herdr pane get "$pane" 2>/dev/null)" || return 1
    # JSON escapes every quote inside a string, so these match keys only.
    [[ "$out" =~ \"pane_id\"[[:space:]]*:[[:space:]]*\"$pane\" && "$out" =~ \"focused\"[[:space:]]*:[[:space:]]*true ]]
}

# at_terminal — true when you are at this Mac looking at the session's
# pane: the screen is unlocked, a key or the mouse moved within
# TUIDEV_NOTIFY_PRESENT_IDLE seconds, the app in front is the one that
# shows the session, as agents names it (a Herdr session no client shows,
# or one whose clients run in different apps, has none), and Herdr's
# focused pane is the session's (in_focused_pane): another pane or tab of
# the same Herdr is somewhere else. Asked once, at notify time, each probe
# bounded (they take about 10-30 ms): ioreg and lsappinfo need no
# permission prompt. A probe that fails or can't tell says no, so the
# banner shows as it always did.
at_terminal() {
    local idle="${TUIDEV_NOTIFY_PRESENT_IDLE:-120}" v front
    [[ "${TUIDEV_NOTIFY_BANNER:-}" != always && "$idle" =~ ^[0-9]+$ && $idle -gt 0 ]] || return 1
    have ioreg && have lsappinfo && session && [[ -n "$BUNDLE" && "$BUNDLE" != - ]] || return 1
    v="$(with_timeout 2 ioreg -n Root -d1 -k IOConsoleLocked | awk -F' = ' '/"IOConsoleLocked" = / { print $2; exit }')"
    [[ "$v" == No ]] || return 1
    v="$(with_timeout 2 ioreg -c IOHIDSystem -r -k HIDIdleTime | awk '/"HIDIdleTime" = / { print $NF; exit }')"
    [[ "$v" =~ ^[0-9]+$ ]] && (( v / 1000000000 < idle )) || return 1
    v="$(with_timeout 2 lsappinfo front)"
    [[ "$v" == ASN:* ]] || return 1
    front="$(with_timeout 2 lsappinfo info -only bundleid "$v" | sed -n 's/.*[bB]undle[iI][dD][a-zA-Z]*"*="\([^"]*\)".*/\1/p' | head -1)"
    [[ -n "$front" && "$front" == "$BUNDLE" ]] || return 1
    in_focused_pane
}

# terminal-notifier's path: Homebrew's before PATH's (an older Ruby gem of
# the same name can come first on PATH).
notifier() {
    local d
    if [[ -n "${TUIDEV_TERMINAL_NOTIFIER+set}" ]]; then
        [[ -x "$TUIDEV_TERMINAL_NOTIFIER" ]] && printf '%s\n' "$TUIDEV_TERMINAL_NOTIFIER"
        return 0
    fi
    for d in /opt/homebrew/bin /usr/local/bin; do
        [[ -x "$d/terminal-notifier" ]] && { printf '%s\n' "$d/terminal-notifier"; return 0; }
    done
    command -v terminal-notifier 2>/dev/null
    return 0
}

# The agents command (monitoring pack): on PATH, or where the pack puts it.
agents_cmd() {
    local a
    a="$(command -v agents 2>/dev/null)"
    [[ "$a" == /* ]] || a="$HOME/.local/bin/agents"
    [[ -x "$a" ]] && printf '%s\n' "$a"
}

# session — true when this runs under an agent session `agents root-of`
# knows (asked once): TOKEN is its PID@START, APP the terminal app that
# shows it, BUNDLE that app's id, CLICK the /bin/sh command a click runs to
# go there ("-" for any of the last three when unknown). agents builds and
# quotes CLICK (lib/agents/notify.sh): it is posted as is.
SESSION=""
session() {
    local agents out
    if [[ -z "$SESSION" ]]; then
        SESSION=none TOKEN="" APP="-" BUNDLE="-" CLICK="-"
        agents="$(agents_cmd)"
        if [[ -n "$agents" ]] && out="$(with_timeout 3 "$agents" root-of "$$" 2>/dev/null)"; then
            IFS=$'\t' read -r TOKEN APP BUNDLE CLICK <<<"$out"
            [[ -z "$TOKEN" ]] || SESSION=found
        fi
    fi
    [[ "$SESSION" == found ]]
}

# is_remote — true for a session reached over ssh, where the Mac's screen
# isn't the user's to look at. The environment says so first, but it can be
# stale: a tmux server started over ssh keeps SSH_CONNECTION in every pane
# after you attach to it at the Mac. So when agents finds the session in a
# terminal app here (itself, or its tmux or Herdr clients'), that live
# answer wins and the session is local.
is_remote() {
    [[ -n "${SSH_CONNECTION:-}${SSH_TTY:-}" ]] || return 1
    ! { session && [[ -n "$APP" && "$APP" != - ]]; }
}

# tn_text TEXT — TEXT as terminal-notifier shows it literally: it reads each
# option's value as a property list first, so one starting with [ ( { < or
# a quote gets a leading backslash (which it strips; its README, "Escaping"),
# and one starting with - a leading space (else it is read as an option).
# lib/agents/notify.sh's _agents_tn_text is the same.
tn_text() {
    case "$1" in
        \[*|\(*|\{*|\<*|\"*|\'*) printf '\\%s' "$1" ;;
        -*) printf ' %s' "$1" ;;
        *)  printf '%s' "$1" ;;
    esac
}

# A banner a click can act on, when agents knows the session: the click
# runs agents' own CLICK command, never a title or a message (those reach
# terminal-notifier as argv).
notify_terminal_notifier() {
    local tn args
    tn="$(notifier)"
    [[ -n "$tn" ]] || return 1
    args=(-title "$(tn_text "$TITLE")" -message "$(tn_text "$MESSAGE")" -sound "$SOUND")
    [[ -z "$SUBTITLE" ]] || args+=(-subtitle "$(tn_text "$SUBTITLE")")
    if session && [[ -n "$CLICK" && "$CLICK" != - ]]; then
        args+=(-group "agents-$TOKEN" -execute "$CLICK")
        [[ -z "$BUNDLE" || "$BUNDLE" == - ]] || args+=(-activate "$BUNDLE")
    fi
    with_timeout 5 "$tn" "${args[@]}"
}

notify_osascript() {
    have osascript || return 1
    with_timeout 5 osascript -e 'on run argv' \
        -e 'display notification (item 2 of argv) with title (item 1 of argv) subtitle (item 3 of argv) sound name (item 4 of argv)' \
        -e 'end run' "$TITLE" "$MESSAGE" "$SUBTITLE" "$SOUND"
}

# terminal-notifier's banner, else osascript's: only when terminal-notifier
# is missing or failed. Not when the timeout cut it off (124): it has most
# likely posted, or sat on macOS's first "allow notifications?" prompt, and
# osascript would show the same banner a second time.
notify_macos() {
    local rc=0
    notify_terminal_notifier || rc=$?
    if [[ $rc -eq 0 || $rc -eq 124 ]]; then used banner; return 0; fi
    notify_osascript && used osascript
}

notify_linux_desktop() {
    have notify-send || return 1
    with_timeout 5 notify-send --app-name="$TITLE" "$TITLE" "$BODY"
}

notify_ntfy() {
    [[ -n "${NTFY_URL:-}" ]] && have curl || return 1
    curl -fsS --max-time 5 -H "Title: $TITLE" --data-raw "$BODY" "$NTFY_URL"
}

# What main did, for the log: the channels that showed it (comma list) and
# why the banner was skipped (present, remote, or -).
CHANNELS="" SKIPPED="-"
used() { CHANNELS="${CHANNELS:+$CHANNELS,}$1"; }

main() {
    local in_term=false in_herdr=false
    [[ -z "$HOOK_MESSAGE" ]] || MESSAGE="$HOOK_MESSAGE"
    BODY="$MESSAGE"
    [[ -z "$SUBTITLE" ]] || BODY="$SUBTITLE: $MESSAGE"
    if notify_herdr; then in_term=true in_herdr=true; used herdr
    elif notify_tmux; then in_term=true; used tmux; fi
    if is_macos; then
        # Shown in the terminal: the banner is for when you can't see it.
        if [[ "$in_term" == true ]] && is_remote; then SKIPPED=remote; return 0; fi
        if [[ "$in_herdr" == true ]] && at_terminal; then SKIPPED=present; return 0; fi
        notify_macos && return 0
    fi
    [[ "$in_term" != true ]] || return 0
    if notify_linux_desktop; then used notify-send; elif notify_ntfy; then used ntfy; fi
}

# field VAR TEXT — TEXT as one notify.tsv field in VAR: control characters
# (tabs, newlines) as spaces, at most 80 characters, "-" when blank.
field() {
    local v="${2//[[:cntrl:]]/ }"
    v="${v:0:80}"
    [[ -n "${v// /}" ]] || v=-
    printf -v "$1" '%s' "$v"
}

# project_of DIR — the name agents gives a session in DIR (lib/agents/awk/
# lib_proc.awk's projname): REPO/NAME for a worktree under
# REPO/.claude/worktrees/NAME, "~" for $HOME, else the directory's name;
# "-" for none.
project_of() {
    local d="$1" r w p
    case "$d" in
        "$HOME") p='~' ;;
        */.claude/worktrees/*)
            r="${d%%/.claude/worktrees/*}"; w="${d#*/.claude/worktrees/}"
            p="${r##*/}/${w%%/*}" ;;
        *)  d="${d%/}"; p="${d##*/}" ;;
    esac
    printf '%s' "${p:--}"
}

# history_on — false when AGENTS_HISTORY=0, from the environment, else the
# first AGENTS_HISTORY line of agents.conf (where lib/agents/config.sh
# reads it).
history_on() {
    local v="${AGENTS_HISTORY-}" line conf="${AGENTS_CONF:-${XDG_CONFIG_HOME:-$HOME/.config}/agents.conf}"
    local re='^[[:space:]]*AGENTS_HISTORY=["'\'']?([01]?)["'\'']?([[:space:]]|#|$)'
    if [[ -z "${AGENTS_HISTORY+set}" && -r "$conf" ]]; then
        while IFS= read -r line || [[ -n "$line" ]]; do
            if [[ "$line" =~ $re ]]; then v="${BASH_REMATCH[1]}"; break; fi
        done < "$conf"
    fi
    [[ "$v" != 0 ]]
}

# log_notify — one line in the monitoring pack's notify.tsv (see the top),
# only when its data directory already exists and history is on.
log_notify() {
    local dir="${AGENTS_DATA_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/tuidev/agents}"
    local now tok=- proj kind
    [[ -d "$dir" && -w "$dir" ]] && history_on || return 0
    now="$(date +%s)"
    [[ "$now" =~ ^[0-9]+$ ]] || return 0
    if session && [[ "$TOKEN" =~ ^[0-9]+@[A-Za-z0-9_:]+$ ]]; then tok="$TOKEN"; fi
    field proj "$(project_of "${CLAUDE_PROJECT_DIR:-$PWD}")"
    field kind "$SUBTITLE"
    umask 077
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$now" "$tok" "$proj" "$kind" "${CHANNELS:-none}" "$SKIPPED" >> "$dir/notify.tsv"
}

HOOK_MESSAGE="$(hook_message 2>/dev/null)"
main >/dev/null 2>&1 </dev/null
log_notify >/dev/null 2>&1 </dev/null
exit 0
