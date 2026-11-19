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
# writes them), keeps how long each live session has waited (triage.sh:
# waits.now, waits.today), scans the transcripts for tokens
# (tokens.sh; a failure there never stops the sample), updates the run
# ledger (runs.sh; a failure there never makes the next sample count history
# twice) and then the menu's top insight (report.sh: insight.txt). A sample
# that finds nothing going on (_agents_sample_quiet) writes the stamp and the
# baseline only; the history keeps a gap, which every reader takes for idle.
#
# Uses: config.sh, util.sh, snapshot.sh (_agents_herdr, _agents_herdr_panes),
#   classify.sh, events.sh (the data directory and the events lock), runs.sh (the run
#   ledger), tokens.sh (_agents_tokens_scan, _agents_tokens_prune), report.sh
#   (agents_insight_write), triage.sh (_agents_waits_state), bar.sh
#   (_agents_bar_target: does a menu run auto-reap); awk/sample.awk.
# Public: agents_sample, agents_sample_scheduled (the pack's sampler, once a
#   minute), _agents_sample_kick, _agents_hist_line, _agents_prune_file, and
#   how old the newest sample is (_agents_sample_when, _agents_sample_at,
#   _agents_sampler_line, _agents_sampler_say: `agents`, `agents report`
#   and `agents limits` say when no sampler runs).

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
    local dir="$AGENTS_DATA_DIR" now day ps recs type pid kind rest paths enr feed="" prev="" herdr waits
    read -r now day <<<"$(date '+%s %Y-%m-%d')"
    # The last sample that counted (sample.state's epoch): what waits credit.
    [[ ! -r "$dir/sample.state" ]] || read -r prev < "$dir/sample.state"
    # The stamp first: a failing sample is retried a minute later, not at once.
    _agents_replace "$dir/sample.stamp" "$now"
    ps="$(agents_snapshot)"
    [[ -n "$ps" ]] || { echo "agents: cannot read the process table (is ps blocked by a sandbox?)" >&2; return 1; }
    recs="$(printf '%s\n' "$ps" | AGENTS_JOBS_PROC=1 agents_classify "" "$(_agents_keep_pids "$ps")")"
    # What the menu saw since the last sample (runs.sh), oldest first.
    _agents_runs_take "$now"
    # Nothing happened: no agent, no stale tree, no command running, nothing
    # to read: the stamp is written (above) and the rest is skipped.
    if _agents_sample_quiet "$recs" "$now"; then
        _agents_replace "$dir/sample.state" "$now"
        _agents_history_prune "$now" "$day"
        return 0
    fi
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
    waits="$(printf '%s\n' "$enr" | _agents_waits_rows "$now" "$prev"
             printf '%s\n' "$enr" | _agents_hook_waits_rows "$now" "$prev")"
    { [[ -z "$waits" ]] || printf '%s\n' "$waits" >> "$dir/waits.tsv"; } \
        || echo "agents: waits.tsv was not updated" >&2
    # What the views read instead of that file (triage.sh).
    _agents_waits_state "$now" "$day" "$waits" "$enr" || echo "agents: waits.now was not updated" >&2
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

# _agents_sample_quiet RECORDS NOW — true when a sample would find nothing to
# record: RECORDS (the classified snapshot) hold no agent, stale tree or
# command process; the menu fed no observations (_AGENTS_RUNS_FED); the run
# ledger has no open run to close; no hook wait is open or just ended to
# credit; waits.now holds no session; and no transcript or Grok session
# changed since the last scan, with none of the recent ones still waiting out
# the quiet time that counts its last message (tokens.sh:
# _agents_tokens_idle). The skipped sample would have appended nothing, so a
# gap in history.tsv, which every reader takes for idle, says the same;
# sample.state keeps only its epoch (the baseline the next sample's waits and
# new processes count from), exactly as a full one would have written it.
# Whatever is in doubt (a missing file: a first sample) says false.
_agents_sample_quiet() {
    local dir="$AGENTS_DATA_DIR" f
    case $'\n'"$1" in
        *$'\n'agent$'\t'*|*$'\n'stale$'\t'*|*$'\n'jp$'\t'*) return 1 ;;
    esac
    [[ ${#_AGENTS_RUNS_FED[@]} -eq 0 ]] || return 1
    [[ -f "$dir/sample.state" && -f "$dir/waits.now" && ! -s "$dir/waits.now" && ! -s "$dir/runs.state" ]] || return 1
    for f in "$dir"/waiting/* "$dir"/waited/*; do [[ ! -e "$f" ]] || return 1; done
    _agents_tokens_idle "$2"
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
# minute old or more (_AGENTS_MINUTE_DUE: 55 s, so the menu's 60 s timer
# samples on every refresh, not every other).
_agents_sample_due() {
    [[ "$AGENTS_HISTORY" == 1 ]] || return 1
    local now="${1:-}" age
    [[ -n "$now" ]] || now="$(date +%s)"
    _agents_stamp_age age "$AGENTS_DATA_DIR/sample.stamp" "$now"
    [[ $age -ge $_AGENTS_MINUTE_DUE ]]
}

# _agents_sample_kick — sample in the background when one is due (agents watch).
_agents_sample_kick() {
    _agents_sample_due || return 0
    _agents_detach agents_sample
    return 0
}

# agents_sample_scheduled — `agents sample --scheduled`: what the monitoring
# pack's own sampler runs once a minute (the LaunchAgent dev.tuidev.sample on
# macOS, the systemd user timer tuidev-sample.timer on Linux). Nothing with
# AGENTS_SAMPLER=0. Otherwise one sample when one is due (_agents_sample_due:
# none for 55 s), so a sample the menu or `agents watch` took stands and none
# is taken twice. Then, with AGENTS_AUTO_REAP=1 and no menu to run it
# (_agents_bar_target: none on Linux), `agents reap --auto --throttle
# --notify`, as the menu runs it, when a sample saw something under an agent
# (sample.state; with AGENTS_HISTORY=0 nothing says, and it runs): its
# throttle keeps it to once a minute, whoever starts it. The no-op loads four
# modules (bin/agents' fast path); the sample and the reap are whole runs of
# agents of their own.
agents_sample_scheduled() {
    [[ "$AGENTS_SAMPLER" != 0 ]] || return 0
    local now rc=0
    _agents_now now
    if _agents_sample_due "$now"; then
        "${BASH:-bash}" "$AGENTS_PATH" sample >/dev/null || rc=$?
    fi
    [[ "$AGENTS_AUTO_REAP" == 1 ]] || return "$rc"
    ! _agents_bar_target "$now" || return "$rc"
    if [[ "$AGENTS_HISTORY" == 1 ]]; then
        grep -q $'\t1$' "$AGENTS_DATA_DIR/sample.state" 2>/dev/null || return "$rc"
    fi
    "${BASH:-bash}" "$AGENTS_PATH" reap --auto --throttle --notify >/dev/null || rc=$?
    return "$rc"
}

# _AGENTS_SAMPLE_STALE — seconds after which the newest sample says no
# sampler runs: the scheduled one samples every minute, and the menu, idle,
# skips its samples for up to 5 minutes.
_AGENTS_SAMPLE_STALE=600

# _agents_sample_when — REPLY: the epoch of the newest sample (sample.stamp,
# written as each one starts), empty when none ran or history is off.
_agents_sample_when() {
    REPLY=""
    [[ "$AGENTS_HISTORY" == 1 && -r "$AGENTS_DATA_DIR/sample.stamp" ]] || return 0
    read -r REPLY < "$AGENTS_DATA_DIR/sample.stamp" 2>/dev/null
    [[ "$REPLY" =~ ^[0-9]+$ ]] || REPLY=""
}

# _agents_sample_at EPOCH NOW — REPLY: EPOCH as HH:MM, with the date in
# front when it is not NOW's day.
_agents_sample_at() {
    local d1 d2
    _agents_strftime d1 %Y-%m-%d "$1"
    _agents_strftime d2 %Y-%m-%d "$2"
    if [[ "$d1" == "$d2" ]]; then _agents_strftime REPLY %H:%M "$1"; else _agents_strftime REPLY '%b %d %H:%M' "$1"; fi
}

# _agents_sampler_line NOW — REPLY: one line when the newest sample is older
# than _AGENTS_SAMPLE_STALE, or none ran: since when, and what starts a
# sampler on this machine. Empty while samples are current, and with
# AGENTS_HISTORY=0 (nothing samples then, by choice). File tests only.
_agents_sampler_line() {
    local t fix units="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
    _agents_sample_when; t="$REPLY"; REPLY=""
    [[ "$AGENTS_HISTORY" == 1 ]] || return 0
    [[ -z "$t" || $(( $1 - t )) -ge $_AGENTS_SAMPLE_STALE ]] || return 0
    if [[ "$AGENTS_SAMPLER" == 0 ]]; then
        fix="AGENTS_SAMPLER=0 in agents.conf; agents watch samples while it runs"
    elif [[ "${OSTYPE:-}" != darwin* && -f "$units/tuidev-sample.timer" ]]; then
        fix="systemctl --user enable --now tuidev-sample.timer starts one"
    else
        fix="tuidev install --pack monitoring starts one"
    fi
    if [[ -z "$t" ]]; then REPLY="no sampler has run yet: $fix"; return 0; fi
    _agents_sample_at "$t" "$1"
    REPLY="no sampler has run since $REPLY: $fix"
}

# _agents_sampler_say NOW — print _agents_sampler_line's line, dimmed, if
# any, folded at the words to AGENTS_WIDTH (80 at most, as the views).
_agents_sampler_say() {
    local w="${AGENTS_WIDTH:-80}" out="" word words
    _agents_sampler_line "$1"
    [[ -n "$REPLY" ]] || return 0
    [[ "$w" =~ ^[0-9]+$ && $w -le 80 ]] || w=80
    [[ $w -ge 24 ]] || w=24
    read -r -a words <<<"$REPLY"
    for word in "${words[@]}"; do
        if [[ -z "$out" ]]; then out="$word"
        elif [[ $(( ${#out} + 1 + ${#word} )) -le $w ]]; then out+=" $word"
        else printf '%s%s%s\n' "$C_DIM" "$out" "$C_0"; out="  $word"; fi
    done
    printf '%s%s%s\n' "$C_DIM" "$out" "$C_0"
}

# _agents_hist_line — the menu's history line, from small files only:
#   hist STATE TODAY_CPU_S TOP_JOB TOP_JOB_CPU_S
# STATE: off (AGENTS_HISTORY=0), due (the menu then runs `agents sample` in the
# background) or ok.
_agents_hist_line() {
    local now day d="" tot=0 top="-" tops=0 state=ok
    if [[ "$AGENTS_HISTORY" != 1 ]]; then printf 'hist\toff\t0\t-\t0\n'; return 0; fi
    _agents_strftime day '%s %Y-%m-%d'
    read -r now day <<<"$day"
    if [[ -r "$AGENTS_DATA_DIR/today.tsv" ]]; then
        { IFS=$'\t' read -r d tot; IFS=$'\t' read -r top tops; } < "$AGENTS_DATA_DIR/today.tsv"
    fi
    if [[ "$d" != "$day" || ! "$tot" =~ ^[0-9]+$ ]]; then tot=0 top=- tops=0; fi
    [[ "$top" =~ ^[a-z]+$ && "$tops" =~ ^[0-9]+$ ]] || { top=-; tops=0; }
    _agents_sample_due "$now" && state=due
    printf 'hist\t%s\t%s\t%s\t%s\n' "$state" "$tot" "$top" "$tops"
}
