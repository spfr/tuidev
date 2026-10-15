# shellcheck shell=bash
# lib/agents/terminal.sh — opening `agents` views in a terminal window.
#
# The menu opens `agents watch` (and other views) in your terminal itself
# rather than through SwiftBar's terminal=true, which always uses Terminal.app.
#
# Ghostty 1.3 and later get a new window of the running instance, through its
# AppleScript; `open -na Ghostty` would start a second instance, which then
# answers AppleScript in place of yours (so `agents jump` can't find a tab by
# tty) and can be the one a notification's click brings forward.
#
# Uses: config.sh (AGENTS_TERMINAL, AGENTS_PATH), util.sh (_agents_quote,
#   _agents_timeout).
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

# _agents_ghostty_scriptable — true when the Ghostty open-term opens (the first
# found, as auto looks) speaks AppleScript: 1.3 and later ship its dictionary.
_agents_ghostty_scriptable() {
    local dir
    for dir in $(_agents_app_dirs); do
        [[ -d "$dir/Ghostty.app" ]] || continue
        [[ -f "$dir/Ghostty.app/Contents/Resources/Ghostty.sdef" ]]; return
    done
    return 1
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
# keeps it open after a one-shot command until a key is pressed. TERMINAL
# ghostty-window is Ghostty 1.3+'s AppleScript: a window of the instance that
# runs, printing ok, or down when none runs; its command is /bin/sh words in
# single quotes, which no character in them can end. Ghostty keeps that
# window after any command until a key is pressed (wait after command, which
# it forces for a scripted command anyway), so --hold adds nothing there.
_agents_term_argv() {
    local term="$1" hold="" inner run cmdline shline="" w; shift
    [[ "${1:-}" == --hold ]] && { hold=1; shift; }
    inner="$(printf '%q ' "$AGENTS_PATH" "$@")"
    [[ -z "$hold" || "$term" == ghostty-window ]] || inner+="; printf '\\n[press any key to close] '; read -r -s -n 1"
    run=(/usr/bin/env "PATH=$PATH" /bin/bash -c "$inner")
    cmdline="$(printf '%q ' "${run[@]}")"
    for w in "${run[@]}"; do shline+="${shline:+ }$(_agents_quote "$w")"; done
    case "$term" in
        ghostty) set -- open -na Ghostty --args -e "${run[@]}" ;;
        ghostty-window) set -- osascript -e 'on run argv' \
                     -e 'if application "Ghostty" is not running then return "down"' \
                     -e 'tell application "Ghostty"' \
                     -e 'set cfg to new surface configuration' \
                     -e 'set command of cfg to (item 1 of argv)' \
                     -e 'set wait after command of cfg to true' \
                     -e 'new window with configuration cfg' \
                     -e 'try' -e 'activate' -e 'end try' \
                     -e 'end tell' -e 'return "ok"' -e 'end run' "$shline" ;;
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

# _agents_ghostty_window OSASCRIPT_ARGV... — run the ghostty-window command:
# true when it opened the window; 1 when it opened none (no Ghostty runs, or
# AppleScript failed: no dictionary, scripting off, permission refused); 2
# when it ran out of time, and a window may still come.
_agents_ghostty_window() {
    local out rc=0
    out="$(_agents_timeout 10 "$@" 2>/dev/null)" || rc=$?
    [[ "$out" == ok ]] && return 0
    [[ $rc -gt 128 ]] && return 2
    return 1
}

# agents_open_term [-n] [--hold] ARGS... — run `agents ARGS…` in a new window
# of your terminal; -n prints the command instead (for Ghostty 1.3+, the
# AppleScript first, then the `open -na` it falls back to).
agents_open_term() {
    local dry="" term line rc argv=() first=()
    [[ "${1:-}" == -n ]] && { dry=1; shift; }
    [[ $# -gt 0 ]] || { echo "usage: agents open-term [-n] [--hold] COMMAND..." >&2; return 2; }
    term="$(agents_terminal)"
    if [[ "$term" == ghostty ]] && _agents_ghostty_scriptable; then
        while IFS= read -r line; do first+=("$line"); done < <(_agents_term_argv ghostty-window "$@")
    fi
    while IFS= read -r line; do argv+=("$line"); done < <(_agents_term_argv "$term" "$@")
    [[ ${#argv[@]} -gt 0 ]] || return 2
    if [[ -n "$dry" ]]; then
        [[ ${#first[@]} -eq 0 ]] || { printf '%q ' "${first[@]}"; echo; }
        printf '%q ' "${argv[@]}"; echo; return 0
    fi
    if [[ ${#first[@]} -gt 0 ]]; then
        # Only when no window opened does `open -na` follow: when none runs it
        # starts the one instance, else it is the last resort.
        rc=0; _agents_ghostty_window "${first[@]}" || rc=$?
        case $rc in 0) return 0 ;; 2) return 1 ;; esac
    fi
    "${argv[@]}" >/dev/null 2>&1
}
