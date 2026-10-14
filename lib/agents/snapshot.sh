# shellcheck shell=bash
# lib/agents/snapshot.sh — what runs right now, read once per run.
#
# Owns: the ps snapshot, a process's start time, listening ports, working
#   directories, the pids never flagged stale (launchd jobs, systemd
#   services, our own keep-awake holder), Herdr's view (cached), and
#   agents_collect, the full record set every view starts from.
# Uses: config.sh, util.sh, classify.sh (agents_classify, agents_enrich),
#   watched.sh (_agents_watched, _agents_watch_info), awake.sh
#   (_agents_awake_pid).
# Public: agents_snapshot, agents_collect, agents_secs, _agents_start,
#   _agents_cwds.

# One line per process: pid ppid uid user %cpu rss(KiB) cputime etime
# lstart(5 words) args. BSD option syntax, which macOS and procps both take.
agents_snapshot() {
    LC_ALL=C ps axww -o pid=,ppid=,uid=,user=,pcpu=,rss=,time=,etime=,lstart=,args= 2>/dev/null
}

# agents_secs TIME — [DD-][HH:]MM:SS[.cc] to whole seconds.
# shellcheck disable=SC2016  # awk source
agents_secs() { printf '%s\n' "$1" | _agents_awk_eval lib_proc '{ print secs($1) }'; }

# _agents_start PID — the process's start time as one token, or nothing.
_agents_start() { LC_ALL=C ps -o lstart= -p "$1" 2>/dev/null | awk 'NF >= 5 { print $1 "_" $2 "_" $3 "_" $4 "_" $5 }'; }

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

# _agents_cwds PID... — "pid<TAB>cwd" lines.
_agents_cwds() {
    [[ $# -gt 0 ]] || return 0
    local p
    if [[ -d /proc/self ]]; then
        for p in "$@"; do
            printf '%s\t%s\n' "$p" "$(readlink "/proc/$p/cwd" 2>/dev/null || echo -)"
        done
    elif command -v lsof >/dev/null 2>&1; then
        local IFS=,
        lsof -b -w -a -d cwd -Fpn -p "$*" 2>/dev/null | awk '/^p/ { p = substr($0, 2) } /^n/ { print p "\t" substr($0, 2) }'
    fi
}

# Herdr's view: "agent<TAB>status<TAB>cwd". Silent when Herdr, its socket or
# jq is missing, or when AGENTS_NO_HERDR=1.
_agents_herdr_query() {
    _agents_timeout 2 herdr agent list 2>/dev/null \
        | jq -r '.result.agents[]? | [(.agent // "-"), (.agent_status // "-"), (.cwd // "-")] | @tsv' 2>/dev/null
}
_agents_herdr() {
    [[ -z "${AGENTS_NO_HERDR:-}" ]] || return 0
    command -v herdr >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 || return 0
    [[ -S "${HERDR_SOCKET_PATH:-$HOME/.config/herdr/herdr.sock}" ]] || return 0
    _agents_herdr_cached "${1:-sync}"
}

# _agents_herdr_cached sync|async — Herdr's answer, cached for 10s in the run
# dir. async (the menu bar) never waits: it serves the cache (up to a minute
# old) and refreshes it in the background. sync (the terminal) asks Herdr
# when the cache is stale.
_agents_herdr_cached() {
    local cache="$AGENTS_RUN_DIR/herdr.tsv" ts="" now age line
    now="$(date +%s)"
    [[ -r "$cache" ]] && read -r ts < "$cache"
    [[ "$ts" =~ ^[0-9]+$ ]] || ts=0          # a damaged cache counts as stale
    age=$((now - ${ts:-0}))
    if [[ $age -lt 10 || ( "$1" == async && $age -lt 60 ) ]]; then
        { read -r _; while IFS= read -r line; do printf '%s\n' "$line"; done; } < "$cache"
        [[ $age -lt 10 ]] && return 0
    fi
    if [[ "$1" == async ]]; then
        ( _agents_herdr_refresh ) </dev/null >/dev/null 2>&1 &
        return 0
    fi
    _agents_herdr_refresh
    [[ -r "$cache" ]] && { read -r _; while IFS= read -r line; do printf '%s\n' "$line"; done; } < "$cache"
    return 0
}

# Rewrite the cache from a fresh query; one refresh at a time.
_agents_herdr_refresh() {
    local cache="$AGENTS_RUN_DIR/herdr.tsv" lock="$AGENTS_RUN_DIR/herdr.lock"
    mkdir -p "$AGENTS_RUN_DIR" 2>/dev/null || return 0
    [[ -z "$(find "$lock" -maxdepth 0 -mmin +1 2>/dev/null)" ]] || rmdir "$lock" 2>/dev/null
    mkdir "$lock" 2>/dev/null || return 0
    { date +%s; _agents_herdr_query; } > "$cache.$$" 2>/dev/null && mv -f "$cache.$$" "$cache"
    rm -f "$cache.$$"
    rmdir "$lock" 2>/dev/null
    return 0
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
agents_collect() {
    local ps listen recs pids lprobe=ok
    ps="$(agents_snapshot)"
    if [[ -z "$ps" ]]; then
        echo "agents: cannot read the process table (is ps blocked by a sandbox?)" >&2
        return 1
    fi
    listen="$(_agents_listeners)" || lprobe=fail
    recs="$(printf '%s\n' "$ps" | agents_classify "$listen" "$(_agents_keep_pids "$ps")")"
    local type pid kind rest watch=""
    set --
    while IFS=$'\t' read -r type pid kind rest; do
        case "$type" in
            agent|stale|cand) set -- "$@" "$pid" ;;
            act) [[ "$kind" == tool ]] && set -- "$@" "$pid" ;;   # its origin
            watch) watch+="$pid"$'\t'"$kind"$'\t'"$rest"$'\n' ;;  # kind: the path; rest: read|exists
        esac
    done <<<"$recs"
    pids="$(_agents_cwds "$@")"
    printf '%s\n' "$recs" | agents_enrich "$pids" "$(_agents_herdr "${AGENTS_HERDR_MODE:-sync}")" "$(_agents_watched "$watch")"
    _agents_watch_info "$watch"     # "watched" rows: the evidence agents_assess reads
    printf 'probe\tlisten\t%s\n' "$lprobe"
}
