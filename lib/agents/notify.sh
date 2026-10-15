# shellcheck shell=bash
# lib/agents/notify.sh — asking and telling the user.
#
# Owns: the y/N prompt, the macOS confirmation dialog (the menu bar's
#   kills), and macOS notifications (--notify; clickable through
#   terminal-notifier, a click jumping to the session one is about).
# Uses: config.sh (AGENTS_YES, AGENTS_NOTIFY), bin/agents (AGENTS_PATH),
#   util.sh (_agents_timeout).
# Public: _agents_confirm, _agents_gui_confirm, _agents_notifier,
#   _agents_jump_command, _agents_notify.

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

# _agents_quote WORD — WORD as one single-quoted /bin/sh word.
_agents_quote() { local sq="'" r="'\\''"; printf "'%s'" "${1//$sq/$r}"; }

# _agents_jump_command TOKEN — the /bin/sh command a click runs to go to the
# session PID@START TOKEN names: this agents by its absolute path, with this
# PATH (a click runs it with a minimal one, without tmux, herdr or jq). Only
# the token, checked here, and quoted words: nothing a process or a message
# controls reaches the shell. Nothing when TOKEN is not a PID@START.
_agents_jump_command() {
    [[ "${1:-}" =~ ^[0-9]+@[A-Za-z0-9_:]+$ && "${AGENTS_PATH:-}" == /* ]] || return 0
    printf 'PATH=%s %s jump --notify %s\n' "$(_agents_quote "$PATH")" "$(_agents_quote "$AGENTS_PATH")" "$1"
}

# _agents_notify MESSAGE [PID@START [BUNDLE]] — a macOS notification, when
# asked for (--notify). With terminal-notifier and a session's PID@START, a
# click goes there (agents jump) and brings BUNDLE's app (its terminal)
# forward; repeated notifications about one session replace each other. Else
# an osascript banner, which a click can't take anywhere.
_agents_notify() {
    [[ "${AGENTS_NOTIFY:-false}" == true ]] || return 0
    local tn cmd args
    tn="$(_agents_notifier)"
    if [[ -n "$tn" ]]; then
        args=(-title agents -message "$1")
        cmd="$(_agents_jump_command "${2:-}")"
        if [[ -n "$cmd" ]]; then
            args+=(-group "agents-$2" -execute "$cmd")
            [[ ! "${3:-}" =~ ^[A-Za-z0-9.-]+$ ]] || args+=(-activate "$3")
        fi
        _agents_timeout 5 "$tn" "${args[@]}" </dev/null >/dev/null 2>&1 && return 0
    fi
    command -v osascript >/dev/null 2>&1 || return 0
    osascript -e 'on run argv' -e 'display notification (item 1 of argv) with title "agents"' -e 'end run' "$1" >/dev/null 2>&1 || true
}
