# shellcheck shell=bash
# lib/agents/runs.sh — the run ledger: one record per finished command, and
# `agents runs`.
#
# A run is one command a session started (a tool shell and everything under
# it: agents_classify's "act" tool record) or one stale tree, named by its
# root's pid@start, so a reused pid is a new run. A run that outlives its
# session and turns stale stays the same run. The ledger follows each run
# from the first snapshot that shows it to the first that does not, then
# appends one line to runs.tsv:
#   end_epoch start_epoch job project session agent cmd duration_s cpu_s peak_rss_kib exit dup cleaned
# session: claude:PID, codex:PID, "-" (a stale tree); agent: the subagent type
# that started it (Explore, implementor-complex…), main for the main
# conversation, "-" when unknown; cmd: a name only (go, pnpm, wait-loop),
# never arguments; exit: the code a Claude Code task's output file ends with
# ("[exited with code N]"), else "-"; dup: 1 when the same command ran in the
# same directory at the same time; cleaned: 1 when agents stopped it (an
# events.tsv kill, reap, auto or hook of its pid or its session's, within
# seconds of its end). cpu_s counts every process ever seen in the run at its
# largest CPU time; a process that starts and ends between two snapshots is
# missed. Snapshots: every `agents sample` (a minute apart), and every menu
# refresh in between (10 s): `agents tsv` drops what it saw into the spool
# (_agents_runs_feed) and the next sample reads it, so runs shorter than a
# minute are recorded too, without another ps or lsof.
#
# Files, private like the rest of $AGENTS_DATA_DIR, none with AGENTS_HISTORY=0:
#   runs.tsv     the finished runs; one writer (agents sample, under
#                sample.lock); pruned with history.tsv.
#   runs.state   the runs alive at the last sample:
#                  run  KEY START JOB PROJECT SESSION CMD PEAK_RSS DUP LAST ORIGIN OUT
#                  proc RUN_KEY PROC_KEY CPUTIME_S   (the largest seen)
#                  done KEY EPOCH   (finished within the hour: never reopened)
#                ORIGIN: the subagent worktree it ran in (agent-ID) or "-";
#                OUT: its Claude Code task output file or "-". Both stay here
#                and are dropped when the run ends.
#   $AGENTS_RUN_DIR/runs.feed/EPOCH.PID  one menu refresh's observation
#                (awk/runs_obs.awk), in a 700 directory, removed by the
#                sample that reads it.
#
# Uses: config.sh, util.sh, watched.sh (_agents_last_line, _agents_mtimes),
#   transcript.sh and tokens.sh (whose task it was: the scan's tasks.idx,
#   else a bounded search); awk/runs_obs.awk, awk/runs.awk,
#   awk/runs_view.awk.
# Public: agents_runs, _agents_runs_feed, _agents_runs_observe,
#   _agents_runs_take, _agents_runs_update.

# Refreshes the spool holds at most: with no sample to read them (history
# broken, a sandbox), it stops growing.
_AGENTS_RUNS_SPOOL_MAX=64

# _agents_runs_observe NOW PATHS < RECORDS — the run and runp lines of one
# snapshot (awk/runs_obs.awk). RECORDS: enriched agent, stale and act
# records, and jp lines; PATHS: _agents_cwds --stdout's.
_agents_runs_observe() {
    AGENTS_PATHS="$2" _agents_awk "lib_proc lib_activity runs_obs" -F '\t' -v now="$1"
}

# _agents_runs_feed ENRICHED RECORDS PATHS — a menu refresh's share: what its
# snapshot shows of the runs, into the spool for the next sample. Nothing
# when no run is alive or the spool is full. It runs every 10 s, so it forks
# little: the refresh's clock (_agents_now), one awk, one mv; the spool is
# made private (700) once, which keeps the files in it private too.
_agents_runs_feed() {
    local now obs spool="$AGENTS_RUN_DIR/runs.feed" files
    _agents_now now
    obs="$(_agents_runs_observe "$now" "$3" <<<"$1"$'\n'"$2")"
    [[ -n "$obs" ]] || return 0
    [[ -d "$spool" ]] || ( umask 077; mkdir -p "$spool" ) 2>/dev/null || return 0
    files=("$spool"/[0-9]*.[0-9]*)
    [[ ${#files[@]} -lt $_AGENTS_RUNS_SPOOL_MAX ]] || return 0
    _agents_replace "$spool/$now.$$" "$obs"
    return 0
}

# _agents_runs_take NOW — set _AGENTS_RUNS_FED to the spool files written
# before NOW, oldest first (a refresh in the same second as the sample waits
# for the next one: its snapshot may be newer than the sample's).
_agents_runs_take() {
    local f e
    _AGENTS_RUNS_FED=()
    for f in "$AGENTS_RUN_DIR/runs.feed"/[0-9]*.[0-9]*; do
        e="${f##*/}"
        [[ "$e" =~ ^([0-9]+)\.[0-9]+$ && -f "$f" && "${BASH_REMATCH[1]}" -lt "$1" ]] && _AGENTS_RUNS_FED+=("$f")
    done
    return 0
}

# _agents_runs_update NOW FEED OBS — fold the menu's observations (FEED,
# oldest first) and this sample's (OBS, at NOW) into the ledger: replaces
# runs.state, then appends one runs.tsv line per run that ended (the state
# first: a failure loses those lines rather than writing them twice). False,
# with runs.state as it was, when the update could not be made. Runs inside
# agents_sample (sample.lock, umask 077), after the history is committed.
_agents_runs_update() {
    local dir="$AGENTS_DATA_DIR" ended
    if ! ended="$( { [[ -z "$2" ]] || printf '%s\n' "$2"; [[ -z "$3" ]] || printf '%s\n' "$3"; } \
        | _agents_awk runs -F '\t' -v now="$1" -v sf="$dir/runs.state" -v ef="$dir/events.tsv")" \
        || ! mv -f "$dir/runs.state.new" "$dir/runs.state" 2>/dev/null; then
        rm -f "$dir/runs.state.new" 2>/dev/null
        return 1
    fi
    [[ -z "$ended" ]] || _agents_runs_finish "$ended" >> "$dir/runs.tsv"
}

# _agents_runs_finish ENDED — the runs.tsv lines for runs.awk's ended runs.
# A background task keeps its output file (a foreground command's is gone
# once it ends): its last line gives the exit code, its mtime the end (when
# it falls between the last snapshot that saw the run and the first that did
# not), and its task id the agent that started it. Else the end is the last
# snapshot that saw it, or the stop agents logged. A command in a subagent's
# worktree (agent-ID) is that subagent's even without an output file.
_agents_runs_finish() {
    local start job proj sess cmd last gone cpu peak dup orig out cleaned stop
    local outs=() stats="" owners="" end code agent l e p main since=0
    while IFS=$'\t' read -r _ start job proj sess cmd last gone cpu peak dup orig out cleaned stop; do
        [[ "$out" == /* && -f "$out" && ! -L "$out" ]] || continue
        outs+=("$out")
        [[ ! "$start" =~ ^[0-9]+$ ]] || [[ $since -gt 0 && $since -le $start ]] || since=$start
    done <<<"$1"
    if [[ ${#outs[@]} -gt 0 ]]; then
        stats="$(_agents_mtimes "${outs[@]}")"
        owners="$(_agents_runs_owners "$((since > 60 ? since - 60 : 1))" "${outs[@]}")"
    fi
    while IFS=$'\t' read -r _ start job proj sess cmd last gone cpu peak dup orig out cleaned stop; do
        [[ "$start" =~ ^[0-9]+$ && "$last" =~ ^[0-9]+$ ]] || continue
        code=- agent=- end="$last"
        [[ "$cleaned" == 1 && "$stop" =~ ^[0-9]+$ && $stop -gt $last ]] && end="$stop"
        if [[ "$out" == /* && -f "$out" && ! -L "$out" ]]; then
            l="$(_agents_last_line "$out")"
            [[ "$l" =~ ^\[exited\ with\ code\ (-?[0-9]+)\]$ ]] && code="${BASH_REMATCH[1]}"
            while IFS=$'\t' read -r e p; do
                [[ "$p" == "$out" && "$e" =~ ^[0-9]+$ && "$cleaned" != 1 && $e -ge $last && $e -le $gone ]] && end="$e"
            done <<<"$stats"
            while IFS=$'\t' read -r p l; do [[ "$p" == "$out" ]] && agent="$l"; done <<<"$owners"
        fi
        if [[ "$agent" == - && "$sess" == claude:* && "$orig" =~ ^agent-[A-Za-z0-9]+$ ]] && main="$(_agents_tx_main_of "$out")"; then
            agent="$(_agents_tx_agent_type "${main%.jsonl}/subagents/$orig.jsonl")"
        fi
        [[ $end -ge $start ]] || end="$start"
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$end" "$start" "$job" "$proj" "$sess" "$agent" \
            "$cmd" "$((end - start))" "$cpu" "$peak" "$code" "$dup" "$cleaned"
    done <<<"$1"
}

# _agents_runs_owners SINCE OUTPUT... — "output<TAB>agent" for each task
# output file whose task id a transcript of its session names: from the
# token scan's index (_agents_tokens_task_sources; the scan runs just
# before the ledger), and for an id not indexed yet from a search bounded to
# the transcripts changed since SINCE, near their end
# (_agents_tx_task_sources), both resolved alike (_agents_tx_task_resolve).
# One index read and at most one search per session, however many of its
# tasks ended.
_agents_runs_owners() {
    local since="$1" o m id mm out list="" mains="" ids miss srcs owners i a
    shift
    for o in "$@"; do
        m="$(_agents_tx_main_of "$o")" || continue
        id="${o##*/}"; id="${id%.output}"
        list+="$m"$'\t'"$id"$'\t'"$o"$'\n'
        [[ $'\n'"$mains" == *$'\n'"$m"$'\n'* ]] || mains+="$m"$'\n'
    done
    while IFS= read -r m; do
        [[ -n "$m" ]] || continue
        ids=() miss=()
        while IFS=$'\t' read -r mm id out; do [[ "$mm" == "$m" ]] && ids+=("$id"); done <<<"$list"
        srcs="$(_agents_tokens_task_sources "$m" "${ids[@]}")"
        for id in "${ids[@]}"; do [[ $'\n'"$srcs" == *$'\n'"$id"$'\t'* ]] || miss+=("$id"); done
        [[ ${#miss[@]} -eq 0 ]] || srcs+=$'\n'"$(_agents_tx_task_sources "$m" "$since" "${miss[@]}")"
        owners="$(printf '%s\n' "$srcs" | _agents_tx_task_resolve)"
        while IFS=$'\t' read -r mm id out; do
            [[ "$mm" == "$m" ]] || continue
            while IFS=$'\t' read -r i a; do [[ "$i" == "$id" ]] && printf '%s\t%s\n' "$out" "$a"; done <<<"$owners"
        done <<<"$list"
    done <<<"$mains"
}

# agents_runs [--since 24h|7d|30d|today] [--json] — the runs that ended in
# the window (default 24h), newest first: a table, or one JSON object
# (schema_version 1).
agents_runs() {
    # shellcheck disable=SC2034  # _agents_window sets period too
    local since=24h json="" start now off period
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json)    json=1 ;;
            --since)   [[ $# -ge 2 ]] || { _agents_runs_usage; return 2; }
                       since="$2"; shift ;;
            --since=*) since="${1#--since=}" ;;
            *)         _agents_runs_usage; return 2 ;;
        esac
        shift
    done
    _agents_window "$since" || { echo "agents: bad --since '$since' (24h, 7d, 30d, today)" >&2; return 2; }
    local rf="$AGENTS_DATA_DIR/runs.tsv"
    { [[ ! -r "$rf" ]] || LC_ALL=C sort -t "$(printf '\t')" -k1,1nr -k2,2nr "$rf"; } \
        | B="${C_B:-}" DIM="${C_DIM:-}" R="${C_R:-}" N="${C_0:-}" _agents_awk "lib_fmt lib_json runs_view" -F '\t' \
            -v start="$start" -v now="$now" -v off="$off" -v label="$since" -v json="$json" \
            -v hist="$AGENTS_HISTORY" -v have="$([[ -r "$rf" ]] && echo 1)"
}
_agents_runs_usage() { echo "usage: agents runs [--since 24h|7d|30d|today] [--json]" >&2; }
