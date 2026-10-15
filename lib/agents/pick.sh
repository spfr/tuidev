# shellcheck shell=bash
# lib/agents/pick.sh — `agents pick`: browse what runs, Activity Monitor style,
# in fzf.
#
# The list is every session with what it runs (MCP servers by name, commands,
# nested sessions), then stale processes and hogs (awk/pick.awk); the preview
# is `agents show` of the line under the cursor. Keys: enter jumps to its
# pane (agents jump), ctrl-p peeks at that pane (agents peek), ctrl-d opens
# its details live (agents show --watch), ctrl-k kills its tree (agents kill:
# the same refusals and y/N question), ctrl-r reloads. Where fzf has every()
# and --id-nth (0.70 and later), the list reloads every 2 s and the cursor
# stays on its process. Without fzf: a hint, and agents ls.
#
# Owns: `agents pick`, its list and the fzf command line it runs.
# Uses: config.sh (AGENTS_PATH), snapshot.sh (agents_collect), cli.sh
#   (agents_main, for ls without fzf); awk/pick.awk.
# Public: agents_pick.

# agents_pick [--list] — the browser; --list prints its list.
agents_pick() {
    local argv=() line
    case "${1:-}" in
        --list) _agents_pick_list; return ;;
        "")     ;;
        *)      echo "usage: agents pick [--list]" >&2; return 2 ;;
    esac
    if ! command -v fzf >/dev/null 2>&1; then
        echo "agents: pick needs fzf (the ui pack installs it: ./install.sh --pack ui, or brew install fzf); here is agents ls" >&2
        agents_main ls
        return
    fi
    while IFS= read -r line; do argv+=("$line"); done < <(_agents_pick_argv)
    _agents_pick_list | SHELL="${BASH:-/bin/bash}" "${argv[@]}" >/dev/null
    return 0
}

# _agents_pick_list — the list (awk/pick.awk), Herdr from its cache.
_agents_pick_list() {
    local r
    r="$(AGENTS_HERDR_MODE=async agents_collect)" || return 1
    printf '%s\n' "$r" | _agents_awk "lib_fmt pick" -v home="$HOME"
}

# _agents_pick_live — true when this fzf can reload on a timer and keep the
# cursor on the same process: every() and --id-nth (an unknown option or
# event is fzf's exit status 2).
_agents_pick_live() {
    fzf --track --id-nth 1 --bind 'every(2):abort' --filter x </dev/null >/dev/null 2>&1
    [[ $? -ne 2 ]]
}

# _agents_pick_argv — the fzf command line, one word per line. Its commands
# run `agents` by its absolute path ({1}: the pid, {2}: PID@START).
_agents_pick_argv() {
    local a list
    a="$(printf '%q' "$AGENTS_PATH")"
    list="$a pick --list"
    printf '%s\n' fzf --delimiter "$(printf '\t')" --with-nth '3..' --header-lines 1 --layout reverse --no-sort \
        --prompt 'agents> ' \
        --header 'enter jump · ctrl-p peek · ctrl-d details · ctrl-k kill · ctrl-r reload · esc quit' \
        --preview "$a show {1}" --preview-window 'right,55%,wrap' \
        --bind "enter:execute-silent($a jump {2})" \
        --bind "ctrl-p:execute($a peek {2} 200; printf '\\n[press any key] '; read -r -s -n 1)" \
        --bind "ctrl-d:execute($a show --watch {2})" \
        --bind "ctrl-k:execute($a kill {2}; printf '\\n[press any key] '; read -r -s -n 1)+reload-sync($list)" \
        --bind "ctrl-r:reload-sync($list)+refresh-preview"
    if _agents_pick_live; then
        printf '%s\n' --track --id-nth 1 --bind "every(2):reload-sync($list)+refresh-preview"
    fi
}
