# shellcheck shell=bash
# lib/agents/util.sh — small helpers the other modules share.
#
# Owns: running the awk programs in awk/, durations, --since windows and
#   clock times, a word of a line, a command with a timeout or in the
#   background, and the state files in the run and data directories: lock
#   directories, epoch stamps, replacing or removing a file safely.
# Uses: _AGENTS_AWK_DIR (set by bin/agents); snapshot.sh (_agents_start) for
#   a lock's or a state file's holder.
# Public: _agents_awk, _agents_awk_eval, agents_parse_duration,
#   _agents_window, _agents_now, _agents_clock, _agents_field, _agents_timeout,
#   _agents_detach, _agents_lock, _agents_unlock, _agents_holder_check,
#   _agents_mypid, _agents_stamp_age, _agents_replace, _agents_rm_if_same.

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

# _agents_window SINCE [NOW] — set the caller's start, now, off and period
# (declare them local) for a --since window: a duration back from now (24h,
# 7d, 30m) or today (since local midnight). The window is [start, now]; the
# one before it is [start - period, now - period) (for today: yesterday up to
# this time of day); off is the UTC offset in seconds. NOW (epoch) is the
# clock to use instead of a fresh one, and off is then its own (date -d @NOW
# on GNU and BusyBox, -r on BSD). False on any other SINCE.
# shellcheck disable=SC2034  # it sets the caller's variables
_agents_window() {
    local z secs
    if [[ "${2:-}" =~ ^[0-9]+$ ]]; then
        now=$2
        z="$(date -d "@$now" +%z 2>/dev/null || date -r "$now" +%z 2>/dev/null || date +%z)"
    else
        read -r now z <<<"$(date '+%s %z')"
    fi
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
# trying TRIES times (default 1), PAUSE seconds apart (default 0.1), and
# record the holder in DIR/holder: "PID START", this shell and its start time
# (_agents_start; "-" when ps can't tell). The first failed try takes a held
# lock over only when its holder is gone (_agents_holder_check: the pid ended,
# or names another process now), however long it has held it; only a lock
# whose holder can't be told (no holder file, no start time to check) is
# taken over by age, once older than a minute. False when it could not be
# had; _agents_unlock DIR releases it.
_agents_lock() {
    local lock="$1" tries="${2:-1}" pause="${3:-0.1}" i=0 me start
    until mkdir "$lock" 2>/dev/null; do
        if [[ $i -eq 0 ]] && _agents_lock_takeover "$lock"; then i=1; continue; fi
        i=$((i + 1))
        [[ $i -lt $tries ]] || return 1
        sleep "$pause" 2>/dev/null || sleep 1
    done
    _agents_mypid me
    start="$(_agents_start "$me")"
    me="$me ${start:--}"
    _agents_replace "$lock/holder" "$me" || true
    _AGENTS_LOCKS="${_AGENTS_LOCKS:-}$lock"$'\t'"$me"$'\n'
}

# _agents_unlock DIR — release a lock this shell took, only while it is still
# its own (the holder file says so): never one another run took over since.
_agents_unlock() {
    local lock="$1" line mine="" keep="" h=""
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        if [[ "${line%%$'\t'*}" == "$lock" ]]; then mine="${line#*$'\t'}"; else keep+="$line"$'\n'; fi
    done <<<"${_AGENTS_LOCKS:-}"
    _AGENTS_LOCKS="$keep"
    [[ -z "$mine" ]] || { read -r h < "$lock/holder"; } 2>/dev/null
    if [[ -n "$mine" && "$h" == "$mine" ]]; then
        rm -f "$lock/holder"; rmdir "$lock" 2>/dev/null
    fi
    return 0
}

# _agents_lock_takeover DIR — remove the held lock DIR when its holder is
# gone (or, unknown, the lock is older than a minute). Of two runs that found
# the same dead holder, only the one that renames its holder file goes on.
_agents_lock_takeover() {
    local lock="$1" h="" pid="" start="" moved
    { read -r h < "$lock/holder"; } 2>/dev/null
    read -r pid start _ <<<"$h"
    if [[ "$pid" =~ ^[0-9]+$ ]]; then
        _agents_holder_check "" "" "$pid" "$start"
        case $? in
            0) return 1 ;;
            2) [[ -n "$(find "$lock" -maxdepth 0 -mmin +1 2>/dev/null)" ]] || return 1 ;;
        esac
    else
        [[ -n "$(find "$lock" -maxdepth 0 -mmin +1 2>/dev/null)" ]] || return 1
    fi
    if [[ -n "$h" ]]; then
        moved="$lock/holder.$$.$RANDOM"
        mv "$lock/holder" "$moved" 2>/dev/null || return 1
        if [[ "$(cat "$moved" 2>/dev/null)" != "$h" ]]; then
            mv "$moved" "$lock/holder" 2>/dev/null; return 1   # a new holder's: give it back
        fi
        rm -f "$moved"
    fi
    rmdir "$lock" 2>/dev/null
}

# _agents_holder_check FILE CONTENT PID START — is PID, which the state file
# FILE (holding CONTENT) records with start time START, still that process?
# 0: yes, its start time matches. 1: no: kill -0 says "No such process", it
# is a zombie, or the pid now names a process with another start time (a
# reused pid); FILE
# (unless "") is removed if it still holds CONTENT. 2: it exists, but START
# is unknown ("-") or ps can't tell (a permission error, EPERM, also proves
# nothing).
_agents_holder_check() {
    local file="$1" content="$2" pid="$3" start="$4" err now
    if [[ ! "$pid" =~ ^[0-9]+$ ]] || { ! err="$(kill -0 "$pid" 2>&1)" && [[ "$err" == *"No such process"* ]]; } \
        || _agents_zombie "$pid"; then
        [[ -z "$file" ]] || _agents_rm_if_same "$file" "$content"
        return 1
    fi
    [[ -n "$start" && "$start" != - ]] || return 2
    now="$(_agents_start "$pid" 2>/dev/null)"
    [[ -n "$now" ]] || return 2
    [[ "$now" == "$start" ]] && return 0
    [[ -z "$file" ]] || _agents_rm_if_same "$file" "$content"
    return 1
}

# _agents_mypid VAR — set VAR to this shell's own pid, in a subshell too:
# $BASHPID, or in bash 3.2 (where a subshell's $$ is its parent's) the parent
# pid of a child it execs.
_agents_mypid() {
    if [[ ${BASH_VERSINFO[0]} -ge 4 ]]; then
        printf -v "$1" '%s' "$BASHPID"
    else
        # shellcheck disable=SC2016  # expanded by sh
        printf -v "$1" '%s' "$(exec sh -c 'echo "$PPID"')"
    fi
}

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
