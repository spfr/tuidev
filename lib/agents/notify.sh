# shellcheck shell=bash
# lib/agents/notify.sh — asking and telling the user.
#
# Owns: the y/N prompt, the macOS confirmation dialog (the menu bar's
#   kills), and macOS notifications (--notify).
# Uses: config.sh (AGENTS_YES, AGENTS_NOTIFY).
# Public: _agents_confirm, _agents_gui_confirm, _agents_notify.

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

# _agents_notify MESSAGE — a macOS notification, when asked for (--notify).
_agents_notify() {
    [[ "${AGENTS_NOTIFY:-false}" == true ]] || return 0
    command -v osascript >/dev/null 2>&1 || return 0
    osascript -e 'on run argv' -e 'display notification (item 1 of argv) with title "agents"' -e 'end run' "$1" >/dev/null 2>&1 || true
}
