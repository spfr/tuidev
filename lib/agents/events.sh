# shellcheck shell=bash
# lib/agents/events.sh — the local log of cleanups.
#
# Owns: the private data directory and events.tsv, with its lock.
# Uses: config.sh (AGENTS_DATA_DIR, AGENTS_HISTORY), util.sh (_agents_lock).
# Public: agents_event, _agents_log_cleanups, _agents_data_dir,
#   _agents_events_lock, _agents_events_unlock.
#
# $AGENTS_DATA_DIR holds what `agents report` reads. Names only, never full
# command lines (runs.state, the ledger's working file, also keeps the task
# output paths of live runs: runs.sh), and nothing leaves the machine.
# Private: the directory is 700 and its files 600 (every writer runs under
# umask 077).
#   events.tsv  one line per cleanup: epoch kind reason pid name project session
#               kind:   kill (you), reap (`agents reap`), auto (AGENTS_AUTO_REAP),
#                       hook (a session's or subagent's end), guard (the
#                       memory guard: memory.sh)
#               reason: manual stale stuck long subagent-end session-end memory
#               session: the owning session as kind:pid (claude:4242), "-"
#                       for a stale tree

# _agents_data_dir — create $AGENTS_DATA_DIR, private (call under umask 077),
# and make an older one private too.
_agents_data_dir() {
    mkdir -p "$AGENTS_DATA_DIR" 2>/dev/null || return 1
    chmod -R go= "$AGENTS_DATA_DIR" 2>/dev/null
    return 0
}

# _agents_events_lock — take events.lock (a directory: mkdir is atomic),
# waiting up to a second; a lock whose holder is gone is taken over
# (_agents_lock). agents_event appends and _agents_history_prune rewrites
# events.tsv only under it, so a prune never drops a line. False when it
# could not be had.
_agents_events_lock() { _agents_lock "$AGENTS_DATA_DIR/events.lock" 20 0.05; }
_agents_events_unlock() { _agents_unlock "$AGENTS_DATA_DIR/events.lock"; }

# _agents_tsv_field TEXT — one TSV field: tabs and newlines become spaces, empty is "-".
_agents_tsv_field() {
    local v="${1//$'\t'/ }"; v="${v//$'\n'/ }"
    printf '%s' "${v:--}"
}

# agents_event KIND REASON PID NAME PROJECT SESSION — append one cleanup to
# events.tsv (a no-op with AGENTS_HISTORY=0), under the events lock (if it
# can't be had within a second, the line is appended anyway). Never fails
# the caller.
agents_event() {
    [[ "$AGENTS_HISTORY" == 1 ]] || return 0
    local f out="" now
    now="$(date +%s)"
    for f in "$@"; do out+=$'\t'"$(_agents_tsv_field "$f")"; done
    (
        umask 077
        _agents_data_dir || exit 0
        locked=0; _agents_events_lock && locked=1
        printf '%s%s\n' "$now" "$out" >> "$AGENTS_DATA_DIR/events.tsv" 2>/dev/null
        [[ $locked -eq 0 ]] || _agents_events_unlock
    ) 2>/dev/null
    return 0
}

# _agents_log_cleanups ROOTS — one event per tree agents_kill_tokens signalled
# (ROOTS: its "pid<TAB>name<TAB>children<TAB>project" lines), but only for a
# caller that names the kind: _AGENTS_EV_KIND (kill, reap or auto), with
# _AGENTS_EV_REASONS ("pid<TAB>reason<TAB>session" lines; reason defaults to
# manual). Sets _AGENTS_EV_N and _AGENTS_EV_DONE ("name (reason) in project, …").
_agents_log_cleanups() {
    _AGENTS_EV_N=0 _AGENTS_EV_DONE=""
    [[ -n "${_AGENTS_EV_KIND:-}" ]] || return 0
    local pid name proj reason session p r s
    while IFS=$'\t' read -r pid name _ proj; do
        [[ -n "$pid" ]] || continue
        reason=manual session=-
        while IFS=$'\t' read -r p r s; do
            [[ "$p" == "$pid" ]] && { reason="$r"; session="${s:--}"; break; }
        done <<<"${_AGENTS_EV_REASONS:-}"
        agents_event "$_AGENTS_EV_KIND" "$reason" "$pid" "$name" "$proj" "$session"
        _AGENTS_EV_N=$((_AGENTS_EV_N + 1))
        _AGENTS_EV_DONE+="${_AGENTS_EV_DONE:+, }$name ($reason)"
        [[ -z "$proj" || "$proj" == - ]] || _AGENTS_EV_DONE+=" in $proj"
    done <<<"$1"
}
