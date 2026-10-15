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
# banner (3) shows it too, unless you are in over ssh: a toast or a status
# line can't be seen from another app. Otherwise the first of 3 to 5 that
# works does.
#
# Clicking the banner takes you to the session that asked. When this runs
# under a claude or codex process and the `agents` command is installed
# (the monitoring pack), `agents root-of` names that session as PID@START
# now (the hook is long gone by the click), and the banner runs `agents jump
# PID@START` when clicked: its Herdr pane, tmux pane, or Ghostty, iTerm or
# Terminal tab, refused if the pid has since been reused. It also brings that
# terminal app forward, and a newer notification from the same session
# replaces the older one. Without terminal-notifier the banner is osascript's,
# which a click can't take anywhere.
#
# It never prints and always exits 0: hook stdout is parsed by the calling CLI,
# and a failed notification must not surface as a hook error. Every outside
# command it waits for is bounded by a timeout.
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

# with_timeout SECS CMD... — CMD, killed after SECS seconds.
with_timeout() {
    local secs="$1" pid watcher rc
    shift
    "$@" &
    pid=$!
    ( sleep "$secs"; kill "$pid" 2>/dev/null ) >/dev/null 2>&1 &
    watcher=$!
    wait "$pid"
    rc=$?
    kill "$watcher" 2>/dev/null
    return "$rc"
}

# quote WORD — WORD as one single-quoted /bin/sh word.
quote() {
    local sq="'" r="'\\''"
    printf "'%s'" "${1//$sq/$r}"
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
is_remote() { [[ -n "${SSH_CONNECTION:-}${SSH_TTY:-}" ]]; }

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

# session AGENTS — sets TOKEN (PID@START) and BUNDLE (its terminal app's id,
# or nothing) for the agent session this script runs under; false when none.
session() {
    local out
    TOKEN="" BUNDLE=""
    out="$(with_timeout 3 "$1" root-of "$$" 2>/dev/null </dev/null)" || return 1
    IFS=$'\t' read -r TOKEN _ BUNDLE <<<"$out"
    [[ "$TOKEN" =~ ^[0-9]+@[A-Za-z0-9_:]+$ ]] || { TOKEN=""; return 1; }
    [[ "$BUNDLE" =~ ^[A-Za-z0-9.-]+$ && "$BUNDLE" != - ]] || BUNDLE=""
    return 0
}

# A banner a click can act on. The click runs a /bin/sh command with
# a minimal PATH, so it carries this one, and agents by its absolute path:
# only quoted words and the checked PID@START token, never a title or a
# message (those reach terminal-notifier as argv).
notify_terminal_notifier() {
    local tn agents args
    tn="$(notifier)"
    [[ -n "$tn" ]] || return 1
    args=(-title "$TITLE" -message "$MESSAGE" -sound "$SOUND")
    [[ -z "$SUBTITLE" ]] || args+=(-subtitle "$SUBTITLE")
    agents="$(agents_cmd)"
    if [[ -n "$agents" ]] && session "$agents"; then
        args+=(-group "agents-$TOKEN" -execute "PATH=$(quote "$PATH") $(quote "$agents") jump --notify $TOKEN")
        [[ -z "$BUNDLE" ]] || args+=(-activate "$BUNDLE")
    fi
    with_timeout 5 "$tn" "${args[@]}" </dev/null
}

notify_osascript() {
    have osascript || return 1
    with_timeout 5 osascript -e 'on run argv' \
        -e 'display notification (item 2 of argv) with title (item 1 of argv) subtitle (item 3 of argv) sound name (item 4 of argv)' \
        -e 'end run' "$TITLE" "$MESSAGE" "$SUBTITLE" "$SOUND"
}

notify_macos() {
    is_macos || return 1
    notify_terminal_notifier || notify_osascript
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
    if [[ "$in_term" == false ]] || ! is_remote; then
        notify_macos && return 0
    fi
    [[ "$in_term" == true ]] || notify_linux_desktop || notify_ntfy
}

main >/dev/null 2>&1 </dev/null
exit 0
