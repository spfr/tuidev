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
# rss_kib and procs are the moment's. Rows without CPU are left out. A
# command's process that ends between two samples counts up to the last menu
# refresh that saw it (runs.sh: the menu's run feed, every 10 s); any other
# process loses its last interval. today.tsv keeps today's totals for the
# menu ("day<TAB>cpu_s", then "job<TAB>cpu_s" lines, busiest first),
# sample.stamp the last sample's epoch. sample.state: the epoch, then
# "pid@start<TAB>cputime_s<TAB>agent" for each process in an agent tree or a
# stale one; agent is 1 once a sample has seen it under an agent (kept while
# it lives, so an orphan keeps it): the provenance auto-reap needs before it
# stops a stale tree. Once those files are in place (and the feed it counted
# removed), each sample appends to waits.tsv the sessions Herdr shows
# blocked or done (_agents_waits_rows) and the waits Claude Code's hooks
# recorded for sessions outside Herdr (_agents_hook_waits_rows; hooks.sh
# writes them), scans the transcripts for tokens
# (tokens.sh; a failure there never stops the sample), updates the run
# ledger (runs.sh; a failure there never makes the next sample count history
# twice) and then the menu's top insight (report.sh: insight.txt).
#
# Uses: config.sh, util.sh, snapshot.sh (_agents_herdr, _agents_herdr_panes),
#   classify.sh, events.sh (the data directory and the events lock), runs.sh (the run
#   ledger), tokens.sh (_agents_tokens_scan, _agents_tokens_prune), report.sh
#   (agents_insight_write); awk/sample.awk.
# Public: agents_sample, _agents_sample_kick, _agents_hist_line,
#   _agents_prune_file.

# agents_sample — take one sample (a no-op with AGENTS_HISTORY=0). One at a
# time: a second one while the first runs returns at once.
agents_sample() {
    [[ "$AGENTS_HISTORY" == 1 ]] || return 0
    (
        umask 077
        lock="$AGENTS_DATA_DIR/sample.lock"
        _agents_data_dir || { echo "agents: cannot create $AGENTS_DATA_DIR" >&2; exit 1; }
        _agents_lock "$lock" || exit 0
        _agents_sample_locked; rc=$?
        _agents_unlock "$lock"
        exit "$rc"
    )
}

_agents_sample_locked() {
    local dir="$AGENTS_DATA_DIR" now day ps recs type pid kind rest paths enr feed="" prev="" herdr
    read -r now day <<<"$(date '+%s %Y-%m-%d')"
    # The last sample that counted (sample.state's epoch): what waits credit.
    [[ ! -r "$dir/sample.state" ]] || read -r prev < "$dir/sample.state"
    # The stamp first: a failing sample is retried a minute later, not at once.
    _agents_replace "$dir/sample.stamp" "$now"
    ps="$(agents_snapshot)"
    [[ -n "$ps" ]] || { echo "agents: cannot read the process table (is ps blocked by a sandbox?)" >&2; return 1; }
    recs="$(printf '%s\n' "$ps" | AGENTS_JOBS_PROC=1 agents_classify "" "$(_agents_keep_pids "$ps")")"
    set --
    while IFS=$'\t' read -r type pid kind rest; do
        case "$type" in
            agent|stale) set -- "$@" "$pid" ;;
            act) [[ "$kind" == tool ]] && set -- "$@" "$pid" ;;   # where it runs (dup), its output file
        esac
    done <<<"$recs"
    paths="$(_agents_cwds --stdout "$@")"
    # Herdr's status (blocked, done…) as the terminal sees it, by each
    # session's own pane (_agents_herdr_panes): what waits count.
    herdr="$(_agents_herdr sync)"
    enr="$(printf '%s\n' "$recs" | agents_enrich "$paths" "$herdr" "" "$(_agents_herdr_panes "$herdr" "$recs")")"
    # What the menu saw since the last sample (runs.sh), oldest first.
    _agents_runs_take "$now"
    [[ ${#_AGENTS_RUNS_FED[@]} -eq 0 ]] || feed="$(cat "${_AGENTS_RUNS_FED[@]}" 2>/dev/null)"
    { printf '%s\n' "$enr"; printf '%s\n' "$recs"; [[ -z "$feed" ]] || printf '%s\n' "$feed"; } \
        | _agents_sample_rows "$now" "$day" "$dir" >> "$dir/history.tsv" || return 1
    # The history is committed before the ledger runs: its state, today's
    # totals and the feed it counted, so nothing the ledger does can make the
    # next sample count this interval again.
    mv -f "$dir/sample.state.new" "$dir/sample.state" && mv -f "$dir/today.tsv.new" "$dir/today.tsv" || return 1
    [[ ${#_AGENTS_RUNS_FED[@]} -eq 0 ]] || rm -f "${_AGENTS_RUNS_FED[@]}"
    # The sessions waiting on you, once the interval they are credited is
    # committed (a sample that fails before this credits nothing twice).
    { printf '%s\n' "$enr" | _agents_waits_rows "$now" "$prev"
      printf '%s\n' "$enr" | _agents_hook_waits_rows "$now" "$prev"; } >> "$dir/waits.tsv" \
        || echo "agents: waits.tsv was not updated" >&2
    # Where the tokens went (tokens.sh), in a subshell: nothing it does can
    # stop the sample. Before the ledger: the task ids it indexes name the
    # agent of each background command that just ended.
    ( _agents_tokens_scan "$now" "$day" ) || echo "agents: the token scan failed (its state kept)" >&2
    _agents_runs_update "$now" "$feed" "$( { printf '%s\n' "$enr"; printf '%s\n' "$recs"; } | _agents_runs_observe "$now" "$paths")" \
        || echo "agents: the run ledger was not updated (runs.state kept)" >&2
    _agents_history_prune "$now" "$day"
    # The menu's top insight, from the ledger this sample just updated.
    agents_insight_write || true
}

# _agents_sample_rows NOW DAY DIR < ENRICHED_AND_JP_RECORDS [RUNP_LINES] — the
# history rows (stdout); writes DIR/sample.state.new and DIR/today.tsv.new.
# RUNP_LINES: the menu's observations since the last sample (runs.sh), which
# count the last stretch of a run's process that ended before this sample.
_agents_sample_rows() {
    _agents_awk "lib_sort sample" -F '\t' -v now="$1" -v day="$2" -v sf="$3/sample.state" -v tf="$3/today.tsv"
}

# _AGENTS_WAIT_CAP — the most seconds one sample credits a wait: the menu
# samples about once a minute, so a longer gap is the Mac asleep (or no
# menu), not a session waiting all along.
_AGENTS_WAIT_CAP=300

# _agents_waits_rows NOW PREV < ENRICHED_RECORDS — waits.tsv's rows (stdout):
#   epoch project agent status session secs
# one per agent session whose Herdr status is blocked (waiting for your
# answer) or done (finished, not yet looked at); session is its PID@START,
# secs the time since PREV, the last sample's epoch, at most
# _AGENTS_WAIT_CAP (60 without one; nothing when no time passed). The Codex
# daemon is never one.
_agents_waits_rows() {
    LC_ALL=C awk -F '\t' -v now="$1" -v prev="$2" -v cap="$_AGENTS_WAIT_CAP" '
        BEGIN { s = prev ~ /^[0-9]+$/ ? now - prev : 60; if (s > cap) s = cap; if (s < 0) s = 0 }
        s > 0 && $1 == "agent" && NF >= 15 && ($12 == "blocked" || $12 == "done") && $3 != "daemon" {
            print now "\t" $15 "\t" $3 "\t" $12 "\t" $2 "@" $9 "\t" s
        }'
}

# _agents_hook_waits_rows NOW PREV < ENRICHED_RECORDS — waits.tsv's rows
# (stdout, agent claude) for the waits Claude Code's hooks recorded outside
# Herdr (hooks.sh: waiting/ and waited/ in the data directory), credited
# like _agents_waits_rows: the part of the sample's interval (since PREV,
# at most _AGENTS_WAIT_CAP) the wait was open, ending at its END for an
# ended one. A session Herdr counted this sample (blocked or done) is left
# to Herdr. Then removes the ended waits, and the open ones whose session
# (PID@START) is no longer an agent here: it exited without a hook. A sample
# that sees no agent at all (a ps that shows only its own processes, under
# a sandbox) can't tell, so it neither credits nor removes open waits.
_agents_hook_waits_rows() {
    local dir="$AGENTS_DATA_DIR" f line waits="" out
    for f in "$dir"/waiting/* "$dir"/waited/*; do
        [[ -f "$f" ]] || continue
        line=""; IFS= read -r line < "$f" 2>/dev/null || [[ -n "$line" ]] || continue
        waits+="$f"$'\t'"$line"$'\n'
    done
    if [[ -z "$waits" ]]; then cat >/dev/null; return 0; fi
    out="$(H_WAITS="$waits" LC_ALL=C awk -F '\t' -v now="$1" -v prev="$2" -v cap="$_AGENTS_WAIT_CAP" '
        BEGIN { s = prev ~ /^[0-9]+$/ ? now - prev : 60; if (s > cap) s = cap; if (s < 0) s = 0 }
        $1 == "agent" && NF >= 15 && $3 != "daemon" {
            live[$2 "@" $9] = 1; nlive++
            if (s > 0 && ($12 == "blocked" || $12 == "done")) herdr[$2 "@" $9] = 1
        }
        END {
            n = split(ENVIRON["H_WAITS"], w, "\n")
            for (i = 1; i <= n; i++) {
                if (split(w[i], f, "\t") < 5) continue
                path = f[1]; base = path; sub(/.*\//, "", base)
                ended = path ~ /\/waited\/[^\/]*$/
                if (ended) { if (base !~ /^[A-Za-z0-9_-]+@[0-9]+$/) continue; end = substr(base, index(base, "@") + 1) + 0 }
                else if (base !~ /^[A-Za-z0-9_-]+$/) continue
                start = f[2]; st = f[3]; proj = f[4]; tok = f[5]
                ok = start ~ /^[0-9]+$/ && (st == "blocked" || st == "done") && tok ~ /^[0-9]+@[A-Za-z0-9_:]+$/
                if (ok && !ended && !(tok in live)) { if (nlive) print "rm\t" path; continue }
                if (ended || !ok) print "rm\t" path
                if (!ok || tok in herdr) continue
                from = now - s; if (start + 0 > from) from = start + 0
                to = ended && end < now ? end : now
                if (to > from) print "row\t" now "\t" (proj == "" ? "-" : proj) "\tclaude\t" st "\t" tok "\t" (to - from)
            }
        }')"
    [[ -n "$out" ]] || return 0
    while IFS=$'\t' read -r f line; do
        case "$f" in
            row) printf '%s\n' "$line" ;;
            rm)  rm -f "$line" ;;
        esac
    done <<<"$out"
}

# _agents_history_prune NOW DAY — drop history, runs, waits, memory incidents
# (memory.tsv, the memory guard's), notification
# (notify.tsv, which scripts/notify.sh appends to) and token rows (tokens.sh:
# _agents_tokens_prune, which also rolls tokens.tsv up by day) and events
# older than AGENTS_HISTORY_DAYS, at most once a day. history.tsv, runs.tsv,
# waits.tsv and the token files have one writer (the sample this runs in,
# under sample.lock); notify.tsv's lines that arrive while it is rewritten
# are carried over (_agents_prune_file); events.tsv is rewritten under the
# events lock, or left for tomorrow when that can't be had.
_agents_history_prune() {
    local stamp="" cut=$(( $1 - AGENTS_HISTORY_DAYS * 86400 ))
    [[ -r "$AGENTS_DATA_DIR/prune.stamp" ]] && read -r stamp < "$AGENTS_DATA_DIR/prune.stamp"
    [[ "$stamp" != "$2" ]] || return 0
    _agents_prune_file "$AGENTS_DATA_DIR/history.tsv" "$cut"
    _agents_prune_file "$AGENTS_DATA_DIR/hooks.log" "$cut"
    _agents_prune_file "$AGENTS_DATA_DIR/runs.tsv" "$cut"
    _agents_prune_file "$AGENTS_DATA_DIR/waits.tsv" "$cut"
    _agents_prune_file "$AGENTS_DATA_DIR/notify.tsv" "$cut"
    _agents_prune_file "$AGENTS_DATA_DIR/memory.tsv" "$cut"
    _agents_tokens_prune "$1" "$cut" || echo "agents: the token files were not pruned" >&2
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
    local now="${1:-}" age
    [[ -n "$now" ]] || now="$(date +%s)"
    _agents_stamp_age age "$AGENTS_DATA_DIR/sample.stamp" "$now"
    [[ $age -ge 60 ]]
}

# _agents_sample_kick — sample in the background when one is due (agents watch).
_agents_sample_kick() {
    _agents_sample_due || return 0
    _agents_detach agents_sample
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
