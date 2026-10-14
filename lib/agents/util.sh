# shellcheck shell=bash
# lib/agents/util.sh — small helpers the other modules share.
#
# Owns: running the awk programs in awk/, durations and clock times, a word
#   of a line, a command with a timeout, removing a state file safely.
# Uses: _AGENTS_AWK_DIR (set by bin/agents).
# Public: _agents_awk, _agents_awk_eval, agents_parse_duration,
#   _agents_clock, _agents_field, _agents_timeout, _agents_rm_if_same.

# _agents_awk "FILE..." [AWK_OPTION...] — awk, under LC_ALL=C, running the
# concatenation of awk/FILE.awk... (the shared lib_*.awk first, then the
# program) over stdin. The options (-F, -v) go before the program.
_agents_awk() {
    local f files=() IFS=' '
    for f in $1; do files+=(-f "$_AGENTS_AWK_DIR/$f.awk"); done
    shift
    LC_ALL=C awk "$@" "${files[@]}"
}

# _agents_awk_eval "FILE..." PROGRAM [AWK_OPTION...] — the same, with a
# one-line PROGRAM given as text (agents_secs; the tests' probes).
_agents_awk_eval() {
    _agents_awk "$1" "${@:3}" -f /dev/fd/3 3<<<"$2"
}

# agents_parse_duration 30m|2h|1h30m|90s|1d — seconds; non-zero on bad input.
agents_parse_duration() {
    local s="$1" total=0 n unit
    [[ "$s" =~ ^([0-9]+[smhd])+$ ]] || return 1
    while [[ -n "$s" ]]; do
        [[ "$s" =~ ^([0-9]+)([smhd])(.*)$ ]] || return 1
        n=$((10#${BASH_REMATCH[1]})); unit="${BASH_REMATCH[2]}"; s="${BASH_REMATCH[3]}"
        case "$unit" in
            m) n=$((n * 60)) ;;
            h) n=$((n * 3600)) ;;
            d) n=$((n * 86400)) ;;
        esac
        total=$((total + n))
    done
    [[ $total -gt 0 ]] || return 1
    echo "$total"
}

# _agents_timeout SECS CMD... — run CMD, killing it after SECS.
_agents_timeout() {
    local secs="$1" pid watcher rc; shift
    "$@" &
    pid=$!
    ( sleep "$secs"; kill "$pid" 2>/dev/null ) >/dev/null 2>&1 &
    watcher=$!
    wait "$pid"; rc=$?
    kill "$watcher" 2>/dev/null
    return "$rc"
}

# _agents_rm_if_same FILE CONTENT — remove FILE only if it still holds CONTENT,
# so a reader never deletes a state file another `agents` just rewrote.
_agents_rm_if_same() {
    local now=""
    [[ -f "$1" ]] && now="$(cat "$1" 2>/dev/null)"
    [[ "$now" == "$2" ]] && rm -f "$1"
    return 0
}

_agents_field() { local a; read -r -a a <<<"$2"; echo "${a[$1 - 1]}"; }   # N WORDS
_agents_clock() { date -r "$1" +%H:%M 2>/dev/null || date -d "@$1" +%H:%M 2>/dev/null; }
