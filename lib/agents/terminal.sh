# shellcheck shell=bash
# lib/agents/terminal.sh — opening `agents` views in a terminal window.
#
# The menu opens `agents watch` (and other views) in your terminal itself
# rather than through SwiftBar's terminal=true, which always uses Terminal.app.
#
# Uses: config.sh (AGENTS_TERMINAL, AGENTS_PATH).
# Public: agents_open_term, agents_terminal.

# _agents_app_dirs — where .app bundles are looked for (a test may override).
_agents_app_dirs() {
    if [[ -n "${AGENTS_TESTING:-}" && -n "${AGENTS_APP_DIRS:-}" ]]; then echo "$AGENTS_APP_DIRS"; return; fi
    echo "/Applications $HOME/Applications"
}

# agents_terminal — the terminal to open: AGENTS_TERMINAL, or with auto the
# first installed of Ghostty, iTerm, WezTerm, kitty, falling back to Terminal.
agents_terminal() {
    local want="${AGENTS_TERMINAL:-auto}" pair dir
    [[ "$want" == auto ]] || { echo "$want"; return; }
    for pair in Ghostty:ghostty iTerm:iterm WezTerm:wezterm kitty:kitty; do
        for dir in $(_agents_app_dirs); do
            [[ -d "$dir/${pair%%:*}.app" ]] || continue
            # `open -na Ghostty --args -e CMD` needs Ghostty 1.2 or later.
            [[ "$pair" != Ghostty:* ]] || _agents_ghostty_ok "$dir/Ghostty.app" || continue
            echo "${pair#*:}"; return
        done
    done
    echo terminal
}

# _agents_ghostty_ok APP — true for Ghostty 1.2 or later.
_agents_ghostty_ok() {
    local v
    v="$("$1/Contents/MacOS/ghostty" +version 2>/dev/null)"
    [[ "$v" =~ Ghostty\ ([0-9]+)\.([0-9]+) ]] || return 1
    [[ ${BASH_REMATCH[1]} -gt 1 || ( ${BASH_REMATCH[1]} -eq 1 && ${BASH_REMATCH[2]} -ge 2 ) ]]
}

# _agents_term_argv TERMINAL [--hold] ARGS... — the command (one word per line)
# that opens a window running `agents ARGS…`. The window gets this PATH and
# the absolute path of agents, so a login shell's PATH doesn't matter; --hold
# keeps it open after a one-shot command until a key is pressed.
_agents_term_argv() {
    local term="$1" hold="" inner run cmdline w; shift
    [[ "${1:-}" == --hold ]] && { hold=1; shift; }
    inner="$(printf '%q ' "$AGENTS_PATH" "$@")"
    [[ -z "$hold" ]] || inner+="; printf '\\n[press any key to close] '; read -r -s -n 1"
    run=(/usr/bin/env "PATH=$PATH" /bin/bash -c "$inner")
    cmdline="$(printf '%q ' "${run[@]}")"
    case "$term" in
        ghostty) set -- open -na Ghostty --args -e "${run[@]}" ;;
        kitty)   set -- open -na kitty --args "${run[@]}" ;;
        wezterm) set -- open -na WezTerm --args start -- "${run[@]}" ;;
        iterm)   set -- osascript -e 'on run argv' \
                     -e 'tell application "iTerm" to create window with default profile command (item 1 of argv)' \
                     -e 'end run' "$cmdline" ;;
        terminal) set -- osascript -e 'on run argv' \
                     -e 'tell application "Terminal" to do script (item 1 of argv)' \
                     -e 'tell application "Terminal" to activate' -e 'end run' "$cmdline" ;;
        *) echo "agents: unknown terminal '$term' (auto, ghostty, iterm, terminal, wezterm, kitty)" >&2; return 2 ;;
    esac
    for w in "$@"; do printf '%s\n' "$w"; done
}

# agents_open_term [-n] [--hold] ARGS... — run `agents ARGS…` in a new window
# of your terminal; -n prints the command instead.
agents_open_term() {
    local dry="" term line argv=()
    [[ "${1:-}" == -n ]] && { dry=1; shift; }
    [[ $# -gt 0 ]] || { echo "usage: agents open-term [-n] [--hold] COMMAND..." >&2; return 2; }
    term="$(agents_terminal)"
    while IFS= read -r line; do argv+=("$line"); done < <(_agents_term_argv "$term" "$@")
    [[ ${#argv[@]} -gt 0 ]] || return 2
    if [[ -n "$dry" ]]; then printf '%q ' "${argv[@]}"; echo; return 0; fi
    "${argv[@]}" >/dev/null 2>&1
}
