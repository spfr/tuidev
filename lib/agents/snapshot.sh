# shellcheck shell=bash
# lib/agents/snapshot.sh — what runs right now, read once per run.
#
# Owns: the ps snapshot, a process's start time, listening ports, working
#   directories, the pids never flagged stale (launchd jobs, systemd
#   services, our own keep-awake holder), Herdr's view (cached), the Herdr
#   pane each session runs in (HERDR_PANE_ID in its environment), Herdr's
#   health (an hourly check: a stale server, outdated integrations), and
#   agents_collect, the full record set every view starts from.
# Uses: config.sh, util.sh, classify.sh (agents_classify, agents_enrich),
#   watched.sh (_agents_watched, _agents_watch_info), awake.sh
#   (_agents_awake_pid), runs.sh (_agents_runs_feed), where.sh
#   (_agents_tmux_up, _agents_panes).
# Public: agents_snapshot, agents_collect, agents_secs, _agents_start,
#   _agents_cwds, _agents_proc_paths, _agents_pane_env, _agents_herdr_health.

# One line per process: pid ppid uid user %cpu rss(KiB) cputime etime
# lstart(5 words) args. BSD option syntax, which macOS and procps both take.
agents_snapshot() {
    LC_ALL=C ps axww -o pid=,ppid=,uid=,user=,pcpu=,rss=,time=,etime=,lstart=,args= 2>/dev/null
}

# agents_secs TIME — [DD-][HH:]MM:SS[.cc] to whole seconds.
# shellcheck disable=SC2016  # awk source
agents_secs() { printf '%s\n' "$1" | _agents_awk_eval lib_proc '{ print secs($1) }'; }

# _agents_start PID — the process's start time as one token, or nothing when
# it is gone. A zombie counts as gone: it has exited and only waits for its
# parent to reap it, which a container's init may do late.
# One ps, read by bash: it runs for every lock and state file.
_agents_start() {
    local st a b c d e
    read -r st a b c d e _ <<<"$(LC_ALL=C ps -o stat=,lstart= -p "$1" 2>/dev/null)"
    [[ -n "$e" && "$st" != Z* ]] && printf '%s_%s_%s_%s_%s\n' "$a" "$b" "$c" "$d" "$e"
    return 0
}

# _agents_zombie PID — succeeds when PID has exited but is not yet reaped
# (kill -0 still finds it).
_agents_zombie() {
    local st
    read -r st _ <<<"$(LC_ALL=C ps -o stat= -p "$1" 2>/dev/null)"
    [[ "$st" == Z* ]]
}

# "pid port" for every TCP listener we can see (our own processes, unprivileged).
# Fails when they could not be listed (no lsof or ss, or it failed): "no
# ports found" then is not "no ports" (agents_collect's probe row). lsof exits
# 1 with no output when nothing listens; an error also says so on stderr.
_agents_listeners() {
    local out rc=0
    if command -v lsof >/dev/null 2>&1; then
        out="$(lsof -b -w -nP -iTCP -sTCP:LISTEN -Fpn 2>&1)" || rc=$?
        printf '%s\n' "$out" | awk '
            /^p/ { p = substr($0, 2) }
            /^n/ { port = $0; sub(/.*:/, "", port); if (!seen[p " " port]++) print p " " port }'
        [[ $rc -eq 0 || -z "$out" ]]
    elif command -v ss >/dev/null 2>&1; then
        out="$(ss -Hltnp 2>/dev/null)" || return 1
        printf '%s\n' "$out" | awk '{
            port = $4; sub(/.*:/, "", port); s = $0
            while (match(s, /pid=[0-9]+/)) { print substr(s, RSTART + 4, RLENGTH - 4) " " port; s = substr(s, RSTART + RLENGTH) } }'
    else
        return 1
    fi
}

# _agents_cwds [--stdout] PID... — "pid<TAB>cwd" lines. With --stdout, each
# one's stdout too, from the same lsof: then every line is
# "pid<TAB>path<TAB>cwd|1" (agents_enrich reads both forms).
_agents_cwds() {
    if [[ "${1:-}" == --stdout ]]; then shift; _agents_proc_paths cwd,1 "$@"; else _agents_proc_paths cwd "$@"; fi
}

# A refresh asks for the cwds of nearly the same processes as the one before
# (the sessions, the stale trees, the commands still running), and lsof takes
# as long for one pid as for ten. So agents_collect starts the lookup early,
# alongside ps, for the pids the last run asked about (cwd.hint in the run
# dir), and afterwards asks only about the new ones. Every answer is still
# this run's: the hint only says which pids to ask about. Where /proc answers
# at once (Linux), there is nothing to start early.

# _agents_cwd_prefetch FD [--stdout] — start that early lookup on FD (as
# _agents_bg), and set the caller's hint to the pids it asks about
# (" pid pid "); false, with hint empty, when there is none to make.
_agents_cwd_prefetch() {
    local fd="$1" h=""
    shift
    hint=""
    [[ ! -d /proc/self/fd && -f "$AGENTS_RUN_DIR/cwd.hint" ]] || return 1
    { read -r h < "$AGENTS_RUN_DIR/cwd.hint"; } 2>/dev/null || true
    [[ "$h" =~ ^[0-9]+( [0-9]+)*$ ]] || return 1
    # shellcheck disable=SC2086  # one pid per word
    _agents_bg "$fd" _agents_cwds "$@" $h
    hint=" $h "
}

# _agents_cwds_hinted VAR FD HINT [--stdout] PID... — set VAR to what
# _agents_cwds would print for PID...: the early lookup's lines (on FD, for
# the pids in HINT; "" when none was started) for the pids it asked about,
# and one lookup now for the rest. PID... become the next run's hint (a plain
# write: a reader that catches it half-written only asks again).
_agents_cwds_hinted() {
    local _var="$1" fd="$2" hint="$3" so="" pre="" line p want=" " rest=() out=""
    shift 3
    [[ "${1:-}" == --stdout ]] && { so=--stdout; shift; }
    if [[ -n "$hint" ]]; then
        _agents_bg_wait pre "$fd" || true
        for p in "$@"; do if [[ "$hint" == *" $p "* ]]; then want+="$p "; else rest+=("$p"); fi; done
        while IFS= read -r line; do
            [[ -n "$line" && "$want" == *" ${line%%$'\t'*} "* ]] && out+="$line"$'\n'
        done <<<"$pre"
    else
        rest=("$@")
    fi
    [[ ${#rest[@]} -eq 0 ]] || out+="$(_agents_cwds $so "${rest[@]}")"
    if [[ -d "$AGENTS_RUN_DIR" && ! -d /proc/self/fd ]]; then
        { printf '%s\n' "$*" > "$AGENTS_RUN_DIR/cwd.hint"; } 2>/dev/null
    fi
    while [[ "$out" == *$'\n' ]]; do out="${out%$'\n'}"; done
    printf -v "$_var" '%s' "$out"
}

# _agents_proc_paths cwd|FD|cwd,FD PID... — "pid<TAB>path" for each process's
# working directory or open file descriptor FD: from /proc on Linux ("-" when
# it can't be read), else one lsof for all of them (-b: never block on a
# stale mount). Asked for both (cwd,1), each line ends in a third column
# naming which one it is: "pid<TAB>path<TAB>cwd|1".
_agents_proc_paths() {
    local what="$1" p w link tag=""
    shift
    [[ $# -gt 0 ]] || return 0
    [[ "$what" == *,* ]] && tag=1
    if [[ -d /proc/self/fd ]]; then
        for p in "$@"; do
            for w in ${what//,/ }; do
                link="$w"; [[ "$w" == cwd ]] || link="fd/$w"
                printf '%s\t%s%s\n' "$p" "$(readlink "/proc/$p/$link" 2>/dev/null || echo -)" "${tag:+$'\t'$w}"
            done
        done
    elif command -v lsof >/dev/null 2>&1; then
        local IFS=,
        lsof -b -w -a -d "$what" -Fpfn -p "$*" 2>/dev/null | awk -v tag="$tag" '
            /^p/ { p = substr($0, 2) } /^f/ { f = substr($0, 2) } /^n/ { print p "\t" substr($0, 2) (tag ? "\t" f : "") }'
    fi
}

# Herdr's view: "agent<TAB>status<TAB>cwd<TAB>pane<TAB>title<TAB>session"
# per agent pane, "-" for what it does not say. The title is the pane's task
# title (terminal_title_stripped): control characters become spaces, at most
# 60 characters; the session is the agent's own session id, as Herdr's
# integration reports it (agent_session.value). A cache written before the
# last three columns existed still reads (agents_enrich takes three). Silent
# when Herdr, its socket or jq is missing, or when AGENTS_NO_HERDR=1; false
# when Herdr did not answer.
_agents_herdr_query() {
    local out
    out="$(herdr agent list 2>/dev/null)" || return 1
    printf '%s\n' "$out" | jq -r '.result.agents[]? | [(.agent // "-"), (.agent_status // "-"), (.cwd // "-"), (.pane_id // "-"),
        ((.terminal_title_stripped // "") | tostring | gsub("[[:cntrl:]]"; " ") | gsub("  +"; " ") | sub("^ +"; "")
            | .[0:60] | sub(" +$"; "") | if . == "" then "-" else . end),
        ((.agent_session | if type == "object" then .value elif type == "string" then . else null end) // "-"
            | tostring | gsub("[[:cntrl:]]"; "") | if . == "" then "-" else . end)] | map(tostring) | @tsv' 2>/dev/null
}
_agents_herdr() {
    [[ -z "${AGENTS_NO_HERDR:-}" ]] || return 0
    command -v herdr >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 || return 0
    [[ -S "${HERDR_SOCKET_PATH:-$HOME/.config/herdr/herdr.sock}" ]] || return 0
    _agents_herdr_cached "${1:-sync}"
}

# _agents_herdr_cached sync|async — Herdr's answer, cached for 10s in the run
# dir. Herdr answers in milliseconds, so a stale cache is refreshed first:
# sync (the terminal) waits up to 2s for it; async (the menu bar) up to 1s,
# and only when that fails (Herdr slow, or another refresh holds the lock)
# serves the cache while it is under a minute old and refreshes it in the
# background.
_agents_herdr_cached() {
    local cache="$AGENTS_RUN_DIR/herdr.tsv" now age
    _agents_now now
    _agents_stamp_age age "$cache" "$now"    # a damaged cache counts as stale
    if [[ $age -lt 10 ]]; then _agents_herdr_show "$cache"; return 0; fi
    if [[ "$1" == async ]]; then
        if _agents_herdr_refresh 1; then _agents_herdr_show "$cache"; return 0; fi
        [[ $age -lt 60 ]] && _agents_herdr_show "$cache"
        _agents_detach _agents_herdr_refresh
        return 0
    fi
    _agents_herdr_refresh 2 || true
    [[ -r "$cache" ]] && _agents_herdr_show "$cache"
    return 0
}

# _agents_herdr_show CACHE — its answer: every line after the epoch.
_agents_herdr_show() {
    local line
    { read -r _; while IFS= read -r line; do printf '%s\n' "$line"; done; } < "$1"
}

# _agents_herdr_refresh [SECS] — rewrite the cache from a fresh query, given
# SECS (default 2) to answer; one refresh at a time. False when it did not:
# another refresh holds the lock, or Herdr did not answer in time.
_agents_herdr_refresh() {
    local lock="$AGENTS_RUN_DIR/herdr.lock" now out rc=1
    mkdir -p "$AGENTS_RUN_DIR" 2>/dev/null || return 1
    _agents_lock "$lock" || return 1
    now="$(date +%s)"
    if out="$(_agents_timeout "${1:-2}" _agents_herdr_query)"; then
        _agents_replace "$AGENTS_RUN_DIR/herdr.tsv" "$now${out:+$'\n'$out}" && rc=0
    fi
    _agents_unlock "$lock"
    return "$rc"
}

# _agents_herdr_health — what a Herdr upgrade left behind, as records for the
# menu, from a cache in the run dir that a background check rewrites (never
# waited on: the first refresh after it has nothing):
#   hhealth server stale SV CV      the server runs an older binary than the
#                                   client (herdr status: server_binary_stale),
#                                   with the server's and the client's versions
#   hhealth outdated NAME…          integrations herdr integration status
#                                   reports outdated (space-separated names)
# The check runs at most once an hour while all is current, but every
# _AGENTS_HHEALTH_RETRY seconds while the cache reports a problem (fixing one,
# by a restart or a reinstall, clears its row within a minute), and at once
# when Herdr's server restarted after the last check: its socket, which a
# starting server binds anew, is newer than the cache (bash's -nt, no fork).
# Nothing when all is current, when Herdr is not installed, with
# AGENTS_NO_HERDR=1, or under the test harness (AGENTS_TESTING, whose run dir
# must not meet this machine's Herdr: a test unsets it and redefines
# _agents_herdr_health_check).
_AGENTS_HHEALTH_RETRY=60
_agents_herdr_health() {
    [[ -z "${AGENTS_NO_HERDR:-}" && -z "${AGENTS_TESTING:-}" ]] || return 0
    command -v herdr >/dev/null 2>&1 || return 0
    local cache="$AGENTS_RUN_DIR/herdr.health" now age line rows="" ttl=3600
    local sock="${HERDR_SOCKET_PATH:-$HOME/.config/herdr/herdr.sock}"
    _agents_now now
    _agents_stamp_age age "$cache" "$now"
    if [[ -r "$cache" ]]; then
        { read -r _; while IFS= read -r line; do [[ "$line" == hhealth$'\t'* ]] && rows+="$line"$'\n'; done; } < "$cache"
    fi
    [[ -z "$rows" ]] || ttl=$_AGENTS_HHEALTH_RETRY
    if [[ $age -ge $ttl ]] || { [[ -e "$sock" && -e "$cache" && "$sock" -nt "$cache" ]]; }; then
        _agents_detach _agents_herdr_health_refresh
    fi
    printf '%s' "$rows"
    return 0
}

# Rewrite the health cache (one check at a time); its stamp is written even
# when Herdr does not answer, so a broken Herdr is asked once an hour too.
_agents_herdr_health_refresh() {
    local lock="$AGENTS_RUN_DIR/herdr-health.lock" out
    mkdir -p "$AGENTS_RUN_DIR" 2>/dev/null || return 0
    _agents_lock "$lock" || return 0
    out="$(_agents_herdr_health_check)"
    _agents_replace "$AGENTS_RUN_DIR/herdr.health" "$(date +%s)${out:+$'\n'$out}" || true
    _agents_unlock "$lock"
    return 0
}

# _agents_herdr_health_check — the hhealth records, from `herdr status` and
# `herdr integration status` (5s each). The stale-server record also names
# the server's and the client's versions ("version:" under "server:" and
# "client:"; "-" when absent or not a plain version):
#   hhealth server stale SERVER_VERSION CLIENT_VERSION
# Integration lines read "NAME[ (experimental)]: outdated (v3 < v4) (PATH)":
# only the name is kept.
# shellcheck disable=SC2016  # awk source
_agents_herdr_health_check() {
    _agents_timeout 5 herdr status 2>/dev/null \
        | awk 'function ver(v) { return (v ~ /^[0-9A-Za-z._+-]+$/ && length(v) <= 32) ? v : "-" }
               /^[^ \t]/ { sec = $1 }
               $1 == "version:" && sec == "server:" { sv = $2 }
               $1 == "version:" && sec == "client:" { cv = $2 }
               $1 == "server_binary_stale:" && $2 == "yes" { st = 1 }
               END { if (st) print "hhealth\tserver\tstale\t" ver(sv) "\t" ver(cv) }'
    _agents_timeout 5 herdr integration status 2>/dev/null \
        | awk '/^[A-Za-z0-9_.-]+( \([^)]*\))?: outdated/ { n = $1; sub(/:$/, "", n); s = s (s == "" ? "" : " ") n }
               END { if (s != "") print "hhealth\toutdated\t" s }'
}

# _agents_herdr_panes HERDR RECORDS — agents_enrich's PANES: _agents_pane_env
# for the sessions whose "where" record (in RECORDS) places them in Herdr;
# asked only when HERDR (_agents_herdr's answer) lists agents. agents_collect
# and agents_sample both use it, so a sample's waits see the exact pane too.
_agents_herdr_panes() {
    local t p k hosted=()
    [[ -n "$1" ]] || return 0
    while IFS=$'\t' read -r t p k _; do
        [[ "$t" == where && "$k" == herdr ]] && hosted+=("$p")
    done <<<"$2"
    [[ ${#hosted[@]} -eq 0 ]] || _agents_pane_env "${hosted[@]}"
    return 0
}

# _agents_pane_env PID... — "pid<TAB>pane" for each PID started in a Herdr
# pane: HERDR_PANE_ID from its environment, which Herdr sets in every pane
# (so the agent in it knows exactly which pane it is, whatever its cwd). One
# read for all of them: /proc/PID/environ on Linux, else one `ps -E` (macOS
# shows a process's environment after its command line; only your own),
# given 2s. Never under the test harness (AGENTS_TESTING), whose fixture
# pids would meet this machine's processes: a test redefines it.
_agents_pane_env() {
    [[ $# -gt 0 && -z "${AGENTS_TESTING:-}" ]] || return 0
    local p kv out=""
    if [[ -r /proc/self/environ ]]; then
        for p in "$@"; do
            [[ "$p" =~ ^[0-9]+$ ]] || continue
            while IFS= read -r -d '' kv; do
                [[ "$kv" == HERDR_PANE_ID=* ]] && { out+="$p $kv"$'\n'; break; }
            done 2>/dev/null < "/proc/$p/environ"
        done
        [[ -z "$out" ]] || printf '%s' "$out" | _agents_pane_env_parse
        return 0
    fi
    local IFS=,
    _agents_timeout 2 env LC_ALL=C ps -E -ww -o pid=,command= -p "$*" 2>/dev/null | _agents_pane_env_parse
    return 0
}

# _agents_pane_env_parse < LINES — "pid<TAB>pane" from "PID COMMAND… ENV…"
# lines: the last HERDR_PANE_ID= word (the environment comes after the
# arguments), and only a pane id made of [A-Za-z0-9:_-].
# shellcheck disable=SC2016  # awk source
_agents_pane_env_parse() {
    awk '{
        p = $1; s = $0; id = ""; sub(/^[ \t]*[0-9]+/, "", s)
        while (match(s, /[ \t]HERDR_PANE_ID=[^ \t]*/)) { id = substr(s, RSTART + 15, RLENGTH - 15); s = substr(s, RSTART + RLENGTH) }
        if (p ~ /^[0-9]+$/ && id ~ /^[A-Za-z0-9:_-]+$/) print p "\t" id
    }'
}

# _agents_launchd_pids < `launchctl list` — the PIDs of running launchd jobs.
_agents_launchd_pids() { awk 'NR > 1 && $1 ~ /^[0-9]+$/ { print $1 }'; }

# _agents_cgroup_service < /proc/PID/cgroup — true when the process runs in a
# systemd .service unit (a user or system service, not a terminal scope).
_agents_cgroup_service() {
    awk -F ':' '{ n = split($NF, a, "/"); if (a[n] ~ /\.service$/) f = 1 } END { exit !f }'
}

# _agents_keep_pids SNAPSHOT — never stale: our keep-awake holder, launchd jobs
# (LaunchAgents, Homebrew services) on macOS, systemd services on Linux.
_agents_keep_pids() {
    local p
    _agents_awake_pid
    if command -v launchctl >/dev/null 2>&1; then
        launchctl list 2>/dev/null | _agents_launchd_pids
    elif [[ -r /proc/self/cgroup ]]; then
        for p in $(printf '%s\n' "$1" | awk '$2 == 1 { print $1 }'); do
            _agents_cgroup_service 2>/dev/null < "/proc/$p/cgroup" && echo "$p"
        done
    fi
    return 0
}

# agents_collect — the full record set for this moment, ending in
# "probe listen ok|fail": whether the listening ports could be listed (when
# not, a stale tree's "no ports" proves nothing, and auto-reap leaves it).
# Each session's "where" record (its tmux pane, Herdr, ssh or terminal app)
# comes just before, and agents_enrich's "herdr" records (the Herdr pane and
# task title of each session Herdr lists) with the agent rows. With _AGENTS_FEED=1 (agents tsv) and history on, it also
# hands what it saw to the run ledger (_agents_runs_feed): the same snapshot
# and lsof, plus the tool shells' stdout from that lsof.
agents_collect() {
    local ps listen keep kbg="" panes="" tbg="" recs pids lprobe=ok enr feed="" hint=""
    [[ "${_AGENTS_FEED:-}" == 1 && "$AGENTS_HISTORY" == 1 ]] && feed=1
    # Listing the listeners scans every process (lsof): the slowest probe, so
    # it runs while ps reads the process table; so do launchctl on macOS,
    # whose jobs (pids never stale) need no snapshot, tmux's pane list, and
    # the cwd lookup for the pids the last run asked about
    # (_agents_cwd_prefetch).
    _agents_bg 5 _agents_listeners
    if command -v launchctl >/dev/null 2>&1; then _agents_bg 7 _agents_keep_pids ""; kbg=1; fi
    if _agents_tmux_up; then _agents_bg 9 _agents_panes; tbg=1; fi
    _agents_cwd_prefetch 8 ${feed:+--stdout} || true
    ps="$(agents_snapshot)"
    _agents_bg_wait listen 5 || lprobe=fail
    if [[ -n "$kbg" ]]; then _agents_bg_wait keep 7; else keep="$(_agents_keep_pids "$ps")"; fi
    [[ -z "$tbg" ]] || _agents_bg_wait panes 9 || true
    if [[ -z "$ps" ]]; then
        [[ -z "$hint" ]] || _agents_bg_wait _ 8 || true
        echo "agents: cannot read the process table (is ps blocked by a sandbox?)" >&2
        return 1
    fi
    recs="$(printf '%s\n' "$ps" | AGENTS_JOBS_PROC="$feed" agents_classify "$listen" "$keep" "$panes")"
    local type pid kind rest watch="" where="" runs="" herdr
    set --
    while IFS=$'\t' read -r type pid kind rest; do
        case "$type" in
            agent|cand) set -- "$@" "$pid" ;;
            stale) set -- "$@" "$pid"; runs=1 ;;
            act) [[ "$kind" == tool ]] && { set -- "$@" "$pid"; runs=1; } ;;   # its origin
            watch) watch+="$pid"$'\t'"$kind"$'\t'"$rest"$'\n' ;;  # kind: the path; rest: read|exists
            where) where+="where"$'\t'"$pid"$'\t'"$kind"$'\t'"$rest"$'\n' ;;
        esac
    done <<<"$recs"
    _agents_cwds_hinted pids 8 "$hint" ${feed:+--stdout} "$@"
    herdr="$(_agents_herdr "${AGENTS_HERDR_MODE:-sync}")"
    enr="$(printf '%s\n' "$recs" | agents_enrich "$pids" "$herdr" "$(_agents_watched "$watch")" "$(_agents_herdr_panes "$herdr" "$where")")"
    [[ -z "$enr" ]] || printf '%s\n' "$enr"
    # Runs are tool commands and stale trees: with neither, nothing to feed.
    [[ -z "$feed" || -z "$runs" ]] || _agents_runs_feed "$enr" "$recs" "$pids"
    _agents_watch_info "$watch"     # "watched" rows: the evidence agents_assess reads
    printf '%s' "$where"
    printf 'probe\tlisten\t%s\n' "$lprobe"
}
