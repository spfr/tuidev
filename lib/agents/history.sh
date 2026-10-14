# shellcheck shell=bash
# lib/agents/history.sh — sampling where the CPU goes, for `agents report`.
#
# `agents sample` appends one row per job, project and session to history.tsv:
#   epoch job project session cpu_s rss_kib procs
# session is the agent kind (claude, codex; the Codex daemon counts as codex),
# "-" for a stale tree. cpu_s is the CPU time used since the previous sample:
# each process's cputime minus the one sample.state recorded for it, keyed by
# pid@start (a reused pid starts afresh); a process that started since then
# counts whole, one seen for the first time otherwise counts from now on.
# rss_kib and procs are the moment's. Rows without CPU are left out. A process
# that ends between two samples loses its last interval, so short runs count
# low. today.tsv keeps today's totals for the menu ("day<TAB>cpu_s", then
# "job<TAB>cpu_s" lines, busiest first), sample.stamp the last sample's epoch.
# sample.state: the epoch, then "pid@start<TAB>cputime_s<TAB>agent" for each
# process in an agent tree or a stale one; agent is 1 once a sample has seen
# it under an agent (kept while it lives, so an orphan keeps it): the
# provenance auto-reap needs before it stops a stale tree.
#
# Uses: config.sh, util.sh, snapshot.sh, classify.sh, events.sh (the data
#   directory and the events lock); awk/sample.awk.
# Public: agents_sample, _agents_sample_kick, _agents_hist_line.

# agents_sample — take one sample (a no-op with AGENTS_HISTORY=0). One at a
# time: a second one while the first runs returns at once.
agents_sample() {
    [[ "$AGENTS_HISTORY" == 1 ]] || return 0
    (
        umask 077
        lock="$AGENTS_DATA_DIR/sample.lock"
        _agents_data_dir || { echo "agents: cannot create $AGENTS_DATA_DIR" >&2; exit 1; }
        [[ -z "$(find "$lock" -maxdepth 0 -mmin +1 2>/dev/null)" ]] || rmdir "$lock" 2>/dev/null
        mkdir "$lock" 2>/dev/null || exit 0
        _agents_sample_locked; rc=$?
        rmdir "$lock" 2>/dev/null
        exit "$rc"
    )
}

_agents_sample_locked() {
    local dir="$AGENTS_DATA_DIR" now day ps recs type pid rest
    read -r now day <<<"$(date '+%s %Y-%m-%d')"
    # The stamp first: a failing sample is retried a minute later, not at once.
    printf '%s\n' "$now" > "$dir/sample.stamp.$$" && mv -f "$dir/sample.stamp.$$" "$dir/sample.stamp"
    ps="$(agents_snapshot)"
    [[ -n "$ps" ]] || { echo "agents: cannot read the process table (is ps blocked by a sandbox?)" >&2; return 1; }
    recs="$(printf '%s\n' "$ps" | AGENTS_JOBS_PROC=1 agents_classify "" "$(_agents_keep_pids "$ps")")"
    set --
    while IFS=$'\t' read -r type pid rest; do
        case "$type" in agent|stale) set -- "$@" "$pid" ;; esac
    done <<<"$recs"
    { printf '%s\n' "$recs" | agents_enrich "$(_agents_cwds "$@")" "" ""; printf '%s\n' "$recs"; } \
        | _agents_sample_rows "$now" "$day" "$dir" >> "$dir/history.tsv" || return 1
    mv -f "$dir/sample.state.new" "$dir/sample.state" && mv -f "$dir/today.tsv.new" "$dir/today.tsv"
    _agents_history_prune "$now" "$day"
}

# _agents_sample_rows NOW DAY DIR < ENRICHED_AND_JP_RECORDS — the history rows
# (stdout); writes DIR/sample.state.new and DIR/today.tsv.new.
_agents_sample_rows() {
    _agents_awk sample -F '\t' -v now="$1" -v day="$2" -v sf="$3/sample.state" -v tf="$3/today.tsv"
}

# _agents_history_prune NOW DAY — drop history and events older than
# AGENTS_HISTORY_DAYS, at most once a day. history.tsv has one writer (the
# sample this runs in, under sample.lock); events.tsv is rewritten under the
# events lock, or left for tomorrow when that can't be had.
_agents_history_prune() {
    local stamp="" cut=$(( $1 - AGENTS_HISTORY_DAYS * 86400 ))
    [[ -r "$AGENTS_DATA_DIR/prune.stamp" ]] && read -r stamp < "$AGENTS_DATA_DIR/prune.stamp"
    [[ "$stamp" != "$2" ]] || return 0
    _agents_prune_file "$AGENTS_DATA_DIR/history.tsv" "$cut"
    if _agents_events_lock; then
        _agents_prune_file "$AGENTS_DATA_DIR/events.tsv" "$cut"
        _agents_events_unlock
    fi
    printf '%s\n' "$2" > "$AGENTS_DATA_DIR/prune.stamp"
}

# _agents_prune_file FILE CUTOFF — keep the lines from CUTOFF on, rewriting the
# file atomically. The caller keeps its writers out; lines that still got in
# while it ran are carried over.
_agents_prune_file() {
    local file="$1" tmp="$1.prune.$$" seen kept
    [[ -f "$file" ]] || return 0
    read -r seen kept <<<"$(LC_ALL=C awk -F '\t' -v cut="$2" -v out="$tmp" '
        ($1 + 0) >= cut { print > out; k++ } END { close(out); print NR + 0, k + 0 }' "$file")"
    if [[ ! "$seen" =~ ^[0-9]+$ || "$seen" == "$kept" ]]; then rm -f "$tmp"; return 0; fi
    [[ -f "$tmp" ]] || : > "$tmp"
    tail -n "+$((seen + 1))" "$file" >> "$tmp" 2>/dev/null
    mv -f "$tmp" "$file"
}

# _agents_sample_due [NOW] — true when history is on and the last sample is a
# minute old or more.
_agents_sample_due() {
    [[ "$AGENTS_HISTORY" == 1 ]] || return 1
    local now="${1:-}" stamp=""
    [[ -n "$now" ]] || now="$(date +%s)"
    [[ -r "$AGENTS_DATA_DIR/sample.stamp" ]] && read -r stamp < "$AGENTS_DATA_DIR/sample.stamp"
    [[ "$stamp" =~ ^[0-9]+$ ]] || stamp=0
    [[ $((now - stamp)) -ge 60 ]]
}

# _agents_sample_kick — sample in the background when one is due (agents watch).
_agents_sample_kick() {
    _agents_sample_due || return 0
    ( trap '' HUP; agents_sample ) </dev/null >/dev/null 2>&1 &
    disown $! 2>/dev/null
    return 0
}

# _agents_hist_line — the menu's history line, from small files only:
#   hist STATE TODAY_CPU_S TOP_JOB TOP_JOB_CPU_S
# STATE: off (AGENTS_HISTORY=0), due (the menu then runs `agents sample` in the
# background) or ok.
_agents_hist_line() {
    local now day d="" tot=0 top="-" tops=0 state=ok
    if [[ "$AGENTS_HISTORY" != 1 ]]; then printf 'hist\toff\t0\t-\t0\n'; return 0; fi
    read -r now day <<<"$(date '+%s %Y-%m-%d')"
    if [[ -r "$AGENTS_DATA_DIR/today.tsv" ]]; then
        { IFS=$'\t' read -r d tot; IFS=$'\t' read -r top tops; } < "$AGENTS_DATA_DIR/today.tsv"
    fi
    if [[ "$d" != "$day" || ! "$tot" =~ ^[0-9]+$ ]]; then tot=0 top=- tops=0; fi
    [[ "$top" =~ ^[a-z]+$ && "$tops" =~ ^[0-9]+$ ]] || { top=-; tops=0; }
    _agents_sample_due "$now" && state=due
    printf 'hist\t%s\t%s\t%s\t%s\n' "$state" "$tot" "$top" "$tops"
}
