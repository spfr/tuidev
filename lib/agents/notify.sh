# shellcheck shell=bash
# lib/agents/notify.sh — asking and telling the user.
#
# Owns: the y/N prompt, the macOS confirmation dialog (the menu bar's
#   kills), and macOS notifications (--notify; clickable through
#   terminal-notifier, a click jumping to the session one is about).
# Uses: config.sh (AGENTS_YES, AGENTS_NOTIFY), bin/agents (AGENTS_PATH),
#   util.sh (_agents_timeout, _agents_token).
# Public: _agents_confirm, _agents_gui_confirm, _agents_notifier,
#   _agents_tn_text, _agents_jump_command, _agents_notify.

_agents_confirm() {
    [[ "$AGENTS_YES" == true ]] && return 0
    if [[ ! -t 0 ]]; then
        echo "agents: not a terminal; pass -y to confirm" >&2
        return 1
    fi
    local reply
    read -r -p "$1 [y/N] " reply
    [[ "$reply" == [yY]* ]]
}

# _agents_gui_confirm MESSAGE — a native dialog with Cancel as the default;
# true only for "Kill". No GUI (or no osascript) means no.
_agents_gui_confirm() {
    local out
    command -v osascript >/dev/null 2>&1 || { echo "agents: no osascript to confirm with; not killing" >&2; return 1; }
    out="$(osascript -e 'on run argv' \
        -e 'display dialog (item 1 of argv) with title "agents" buttons {"Cancel", "Kill"} default button "Cancel" cancel button "Cancel" with icon caution' \
        -e 'end run' "$1" 2>/dev/null)" || return 1
    [[ "$out" == *"button returned:Kill"* ]]
}

# _agents_notifier — terminal-notifier's path, nothing when there is none:
# TUIDEV_TERMINAL_NOTIFIER when set (empty: none), else Homebrew's (an older
# Ruby gem of the same name can come first on PATH), else PATH's. Never one
# of this machine's under the test harness (AGENTS_TESTING).
_agents_notifier() {
    local d
    if [[ -n "${TUIDEV_TERMINAL_NOTIFIER+set}" ]]; then
        [[ -x "$TUIDEV_TERMINAL_NOTIFIER" ]] && printf '%s\n' "$TUIDEV_TERMINAL_NOTIFIER"
        return 0
    fi
    [[ -z "${AGENTS_TESTING:-}" ]] || return 0
    for d in /opt/homebrew/bin /usr/local/bin; do
        [[ -x "$d/terminal-notifier" ]] && { printf '%s\n' "$d/terminal-notifier"; return 0; }
    done
    command -v terminal-notifier 2>/dev/null
    return 0
}

# _agents_tn_text TEXT — TEXT as terminal-notifier shows it literally. It
# reads every option's value as a property list first, so a value starting
# with [ ( { < or a quote is misread and the notification dropped: those get
# a leading backslash, which it strips (its README, "Escaping"). One starting
# with - is taken for the next option: that gets a leading space, as its own
# error message says. scripts/notify.sh escapes the same way.
_agents_tn_text() {
    case "$1" in
        \[*|\(*|\{*|\<*|\"*|\'*) printf '\\%s' "$1" ;;
        -*) printf ' %s' "$1" ;;
        *)  printf '%s' "$1" ;;
    esac
}

# _agents_quote WORD — WORD as one single-quoted /bin/sh word.
_agents_quote() { local sq="'" r="'\\''"; printf "'%s'" "${1//$sq/$r}"; }

# _agents_jump_command TOKEN — the /bin/sh command a click runs to go to the
# session PID@START TOKEN names: this agents by its absolute path, with this
# PATH (a click runs it with a minimal one, without tmux, herdr or jq). Only
# the token, checked here, and quoted words: nothing a process or a message
# controls reaches the shell. The one place that command is built (agents
# root-of hands it to scripts/notify.sh). Nothing when TOKEN is not a
# PID@START, or when a newline would split the command's line.
_agents_jump_command() {
    _agents_token "${1:-}" && [[ "${AGENTS_PATH:-}" == /* && "$PATH$AGENTS_PATH" != *$'\n'* ]] || return 0
    printf 'PATH=%s %s jump --notify %s\n' "$(_agents_quote "$PATH")" "$(_agents_quote "$AGENTS_PATH")" "$1"
}

# _agents_notify MESSAGE [TARGET [GROUP]] — a macOS notification, when asked
# for (--notify). With terminal-notifier and a TARGET (agents_root_of's
# line for a session), a click goes there (agents jump) and brings its
# terminal app forward; notifications with the same GROUP about one session
# replace each other (group GROUP-PID@START). Else an osascript banner, which
# a click can't take anywhere: only when terminal-notifier is missing or
# failed. One the timeout cut off (124) may well have posted, or be waiting
# on macOS's first permission prompt, and a second banner would repeat it.
_agents_notify() {
    [[ "${AGENTS_NOTIFY:-false}" == true ]] || return 0
    local tn tok _app bundle _click cmd args rc
    tn="$(_agents_notifier)"
    if [[ -n "$tn" ]]; then
        args=(-title agents -message "$(_agents_tn_text "$1")")
        IFS=$'\t' read -r tok _app bundle _click <<<"${2:-}"
        cmd="$(_agents_jump_command "$tok")"
        if [[ -n "$cmd" ]]; then
            args+=(-execute "$cmd")
            [[ -z "${3:-}" ]] || args+=(-group "$3-$tok")
            [[ ! "$bundle" =~ ^[A-Za-z0-9][A-Za-z0-9-]*(\.[A-Za-z0-9-]+)+$ ]] || args+=(-activate "$bundle")
        fi
        rc=0; _agents_timeout 5 "$tn" "${args[@]}" >/dev/null 2>&1 || rc=$?
        [[ $rc -ne 0 && $rc -ne 124 ]] || return 0
    fi
    command -v osascript >/dev/null 2>&1 || return 0
    osascript -e 'on run argv' -e 'display notification (item 1 of argv) with title "agents"' -e 'end run' "$1" >/dev/null 2>&1 || true
}
