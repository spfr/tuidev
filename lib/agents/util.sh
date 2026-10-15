# shellcheck shell=bash
# lib/agents/util.sh — small helpers the other modules share.
#
# Owns: running the awk programs in awk/, durations, --since windows and
#   clock times, a word of a line, a command with a timeout or in the
#   background, and the state files in the run and data directories: lock
#   directories, epoch stamps, replacing or removing a file safely.
# Uses: _AGENTS_AWK_DIR (set by bin/agents).
# Public: _agents_awk, _agents_awk_eval, agents_parse_duration,
#   _agents_window, _agents_now, _agents_clock, _agents_field, _agents_timeout,
#   _agents_detach, _agents_lock, _agents_unlock, _agents_stamp_age, _agents_replace,
#   _agents_rm_if_same.

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

# _agents_window SINCE — set the caller's start, now, off and period (declare
# them local) for a --since window: a duration back from now (24h, 7d, 30m)
# or today (since local midnight). The window is [start, now]; the one before
# it is [start - period, now - period) (for today: yesterday up to this time
# of day); off is the UTC offset in seconds. False on any other SINCE.
# shellcheck disable=SC2034  # it sets the caller's variables
_agents_window() {
    local z secs
    read -r now z <<<"$(date '+%s %z')"
    off=0
    if [[ "$z" =~ ^([+-])([0-9][0-9])([0-9][0-9])$ ]]; then
        off=$(( 10#${BASH_REMATCH[2]} * 3600 + 10#${BASH_REMATCH[3]} * 60 ))
        [[ "${BASH_REMATCH[1]}" == + ]] || off=$((-off))
    fi
    if [[ "$1" == today ]]; then
        start=$(( now - (now + off) % 86400 )); period=86400
    elif secs="$(agents_parse_duration "$1")"; then
        start=$((now - secs)); period=$secs
    else
        return 1
    fi
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

# _agents_detach CMD... — run CMD in the background, immune to hangups, with
# no terminal, and forget it (no job to wait for). Its pid is in $!.
_agents_detach() {
    ( trap '' HUP; "$@" ) </dev/null >/dev/null 2>&1 &
    disown $! 2>/dev/null
}

# _agents_lock DIR [TRIES [PAUSE]] — take the lock DIR (mkdir is atomic),
# trying TRIES times (default 1), PAUSE seconds apart (default 0.1). A lock
# older than a minute was left by a run that died: the first failed try takes
# it over. False when it could not be had; _agents_unlock DIR releases it.
_agents_lock() {
    local lock="$1" tries="${2:-1}" pause="${3:-0.1}" i=0
    until mkdir "$lock" 2>/dev/null; do
        if [[ $i -eq 0 && -n "$(find "$lock" -maxdepth 0 -mmin +1 2>/dev/null)" ]]; then
            rmdir "$lock" 2>/dev/null; i=1; continue
        fi
        i=$((i + 1))
        [[ $i -lt $tries ]] || return 1
        sleep "$pause" 2>/dev/null || sleep 1
    done
}
_agents_unlock() { rmdir "$1" 2>/dev/null; return 0; }

# _agents_stamp_age VAR FILE NOW — set VAR to the seconds from the epoch on
# FILE's first line to NOW; NOW itself when FILE is missing or damaged (the
# stamp then counts as long ago).
_agents_stamp_age() {
    local _stamp=""
    [[ -r "$2" ]] && read -r _stamp < "$2"
    [[ "$_stamp" =~ ^[0-9]+$ ]] || _stamp=0
    printf -v "$1" '%s' "$(( $3 - _stamp ))"
}

# _agents_replace FILE TEXT — FILE now holds TEXT (and a newline): written
# beside it and renamed over it, so a reader never sees half of it.
_agents_replace() {
    { printf '%s\n' "$2" > "$1.$$"; } 2>/dev/null && mv -f "$1.$$" "$1" && return 0
    rm -f "$1.$$"
    return 1
}

# _agents_rm_if_same FILE CONTENT — remove FILE only if it still holds CONTENT,
# so a reader never deletes a state file another `agents` just rewrote.
_agents_rm_if_same() {
    local now=""
    [[ -f "$1" ]] && now="$(cat "$1" 2>/dev/null)"
    [[ "$now" == "$2" ]] && rm -f "$1"
    return 0
}

# _agents_now VAR — set VAR to the epoch: the one clock of the `agents tsv`
# refresh this runs in (_AGENTS_CLOCK, a local of agents_tsv: never exported,
# never read from the environment), else a test's fixed AGENTS_NOW (only with
# AGENTS_TESTING), else date's.
_agents_now() {
    local t="${_AGENTS_CLOCK:-}"
    [[ -n "$t" || -z "${AGENTS_TESTING:-}" ]] || t="${AGENTS_NOW:-}"
    printf -v "$1" '%s' "${t:-$(date +%s)}"
}

_agents_field() { local a; read -r -a a <<<"$2"; echo "${a[$1 - 1]}"; }   # N WORDS
_agents_clock() { date -r "$1" +%H:%M 2>/dev/null || date -d "@$1" +%H:%M 2>/dev/null; }
