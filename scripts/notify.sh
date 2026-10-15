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
# (is_remote). Otherwise the first of 3 to 5 that works does.
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
# It never prints and always exits 0: hook stdout is parsed by the calling CLI,
# and a failed notification must not surface as a hook error. Every outside
# command it waits for is bounded by a timeout, with every process it starts.
#
# Usage:
#   notify.sh <title> <message> [subtitle] [sound]
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
# ============================================================================

TITLE="${1:-}"
MESSAGE="${2:-}"
SUBTITLE="${3:-}"
SOUND="${4:-Glass}"

[[ -n "$TITLE" && -n "$MESSAGE" ]] || exit 0

# Message with the subtitle folded in, for channels that have no subtitle field.
BODY="$MESSAGE"
[[ -n "$SUBTITLE" ]] && BODY="$SUBTITLE: $MESSAGE"

have() { command -v "$1" >/dev/null 2>&1; }

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
    [[ $rc -ne 0 && $rc -ne 124 ]] || return 0
    notify_osascript
}

notify_linux_desktop() {
    have notify-send || return 1
    with_timeout 5 notify-send --app-name="$TITLE" "$TITLE" "$BODY"
}

notify_ntfy() {
    [[ -n "${NTFY_URL:-}" ]] && have curl || return 1
    curl -fsS --max-time 5 -H "Title: $TITLE" -d "$BODY" "$NTFY_URL"
}

main() {
    local in_term=false
    if notify_herdr || notify_tmux; then in_term=true; fi
    if is_macos && { [[ "$in_term" == false ]] || ! is_remote; }; then
        notify_macos && return 0
    fi
    [[ "$in_term" == true ]] || notify_linux_desktop || notify_ntfy
}

main >/dev/null 2>&1 </dev/null
exit 0
