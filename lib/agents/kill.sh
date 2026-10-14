# shellcheck shell=bash
# lib/agents/kill.sh — signalling process trees, safely.
#
# Owns: the refusals (pid 1, this shell and its parents, other users',
#   critical and session-hosting processes), PID@START plans, SIGTERM then
#   SIGKILL after AGENTS_GRACE, and what joins a tree meanwhile.
# Uses: config.sh, util.sh, snapshot.sh, classify.sh (agents_project),
#   events.sh (_agents_log_cleanups), notify.sh; awk/refusal.awk,
#   awk/tree.awk, awk/new_members.awk.
# Public: agents_refusal, agents_tree, agents_kill_tokens,
#   _agents_kill_unattended.

# agents_refusal PID [SNAPSHOT] — why PID must not be signalled (exit 0 and a
# reason), or nothing (exit 1). Refuses pid <= 1, this process and its
# ancestors, unknown pids, other users' processes, critical ones (the login
# session, Finder, Dock, your terminal, anything under /System/Library,
# /usr/libexec or /usr/sbin), and any process hosting a shell or an agent
# below it (an agent root itself is fine).
agents_refusal() {
    local pid="$1" snap="${2-}"
    [[ "$pid" =~ ^[0-9]+$ ]] || { echo "not a pid"; return 0; }
    [[ "$pid" -gt 1 ]] || { echo "refusing pid $pid"; return 0; }
    [[ -n "$snap" ]] || snap="$(agents_snapshot)"
    local out
    out="$(printf '%s\n' "$snap" | AGENTS_UID="$AGENTS_UID" AGENTS_NAMES="$AGENTS_NAMES" _agents_awk "lib_proc refusal" -v t="$pid" -v self="$AGENTS_SELF")"
    [[ -n "$out" ]] || return 1
    echo "$out"
}

# agents_tree PID < SNAPSHOT — PID and its descendants, deepest first:
# "pid<TAB>start<TAB>uid<TAB>name<TAB>critical(0|1)".
agents_tree() {
    _agents_awk "lib_proc tree" -v t="$1" | sort -t "$(printf '\t')" -k1,1nr | cut -f2-
}

# _agents_signal SIG PID START — signal only if PID still has that start time.
_agents_signal() {
    local now; now="$(_agents_start "$2")"
    [[ -n "$now" ]] || return 0                       # already gone
    if [[ -n "$3" && "$now" != "$3" ]]; then
        echo "  skip $2: its start time changed (pid reused)" >&2
        return 1
    fi
    kill "-$1" "$2" 2>/dev/null
}

# _agents_kill_unattended TOKEN... — agents_kill_tokens on whole trees, with
# no question asked and no notification (auto-reap and the hooks; the
# caller's AGENTS_DRY_RUN still holds).
_agents_kill_unattended() {
    AGENTS_YES=true AGENTS_CONFIRM_GUI=false AGENTS_NOTIFY=false agents_kill_tokens true "$@"
}

# _agents_plan TOKEN SNAPSHOT TREE — print the planned victims ("pid start
# name" lines, the root last) for TOKEN = PID or PID@START; complain and fail
# otherwise. Tree members owned by someone else, or critical, are skipped.
_agents_plan() {
    local token="$1" snap="$2" tree="$3" pid want why now members
    pid="${token%%@*}"; want=""
    [[ "$token" == *@* ]] && want="${token#*@}"
    if why="$(agents_refusal "$pid" "$snap")"; then
        echo "  refuse $pid: $why" >&2; return 1
    fi
    now="$(printf '%s\n' "$snap" | awk -v t="$pid" '$1 == t { print $9 "_" $10 "_" $11 "_" $12 "_" $13 }')"
    if [[ -n "$want" && "$now" != "$want" ]]; then
        echo "  refuse $pid: not the process that was listed (its start time changed)" >&2; return 1
    fi
    members="$(printf '%s\n' "$snap" | agents_tree "$pid")"
    if [[ "$tree" == true ]]; then
        if printf '%s\n' "$members" | awk -F '\t' -v s="$AGENTS_SELF" '$1 == s { f = 1 } END { exit !f }'; then
            echo "  refuse $pid: this shell runs inside that tree" >&2; return 1
        fi
        printf '%s\n' "$members" | awk -F '\t' -v me="$AGENTS_UID" '
            $5 == 1  { printf "  skip %s (%s): a system or session process\n", $1, $4 > "/dev/stderr"; next }
            $3 == me { print $1 "\t" $2 "\t" $4; next }
            { printf "  skip %s (%s): another user owns it\n", $1, $4 > "/dev/stderr" }'
    else
        printf '%s\n' "$members" | awk -F '\t' -v t="$pid" '$1 == t { print $1 "\t" $2 "\t" $4 }'
    fi
}

# _agents_new_members ROOTS PLAN < SNAPSHOT — processes that joined a targeted
# tree after the plan was made ("pid start name"). ROOTS: "pid<TAB>start"
# lines; a root whose start time changed (or is gone) contributes nothing.
_agents_new_members() {
    AGENTS_ROOTS="$1" AGENTS_PLAN="$2" _agents_awk "lib_proc new_members" -v me="$AGENTS_UID" -v self="$AGENTS_SELF"
}

# _agents_alive PLAN — "pid start name" lines still running with that start
# (one ps for the whole plan).
_agents_alive() {
    local pid start name pids="" now
    while IFS=$'\t' read -r pid start name; do
        [[ "$pid" =~ ^[0-9]+$ ]] && pids+="${pids:+,}$pid"
    done <<<"$1"
    [[ -n "$pids" ]] || return 0
    now="$(LC_ALL=C ps -o pid=,lstart= -p "$pids" 2>/dev/null | LC_ALL=C awk 'NF >= 6 { print $1 "\t" $2 "_" $3 "_" $4 "_" $5 "_" $6 }')"
    while IFS=$'\t' read -r pid start name; do
        [[ -n "$pid" && -n "$start" ]] || continue
        [[ $'\n'"$now"$'\n' == *$'\n'"$pid"$'\t'"$start"$'\n'* ]] && printf '%s\t%s\t%s\n' "$pid" "$start" "$name"
    done <<<"$1"
}

# _agents_kill_message ROOTS — the confirmation text. ROOTS: one
# "pid<TAB>name<TAB>children<TAB>project" line per tree.
_agents_kill_message() {
    local pid name kids proj n=0 one="" all=""
    while IFS=$'\t' read -r pid name kids proj; do
        [[ -n "$pid" ]] || continue
        n=$((n + 1))
        one="$name"
        [[ -z "$proj" || "$proj" == - ]] || one+=" in $proj"
        one+=" (pid $pid"
        case "$kids" in 0) ;; 1) one+=", 1 child process" ;; *) one+=", $kids child processes" ;; esac
        one+=")"
        all+="• $one"$'\n'
    done <<<"$1"
    if [[ $n -eq 1 ]]; then echo "Kill $one?"; else printf 'Kill %d process trees?\n\n%s' "$n" "$all"; fi
}

# agents_kill_tokens TREE(true|false) TOKEN... — the kill/reap/term engine.
agents_kill_tokens() {
    local tree="$1" snap plan="" roots="" desc="" one token pid start name n left extra waited=0 errf refused cwd; shift
    snap="$(agents_snapshot)"
    [[ -n "$snap" ]] || { echo "agents: cannot read the process table" >&2; _agents_notify "Nothing done: cannot read the process table"; return 1; }
    errf="$(mktemp "${TMPDIR:-/tmp}/agents.XXXXXX")" || errf=/dev/null
    for token in "$@"; do
        one="$(_agents_plan "$token" "$snap" "$tree" 2>>"$errf")" || continue
        [[ -n "$one" ]] || continue
        plan+="$one"$'\n'
        IFS=$'\t' read -r pid start name <<<"$(printf '%s\n' "$one" | tail -1)"
        roots+="$pid"$'\t'"$start"$'\n'
        cwd="$(_agents_cwds "$pid" | cut -f2)"
        desc+="$pid"$'\t'"$name"$'\t'"$(( $(printf '%s\n' "$one" | grep -c .) - 1 ))"$'\t'"$(agents_project "$cwd")"$'\n'
    done
    refused=""
    if [[ "$errf" != /dev/null ]]; then
        cat "$errf" >&2
        refused="$(grep -m1 'refuse' "$errf" | sed 's/^ *refuse //')"
        rm -f "$errf"
    fi
    plan="${plan%$'\n'}"; roots="${roots%$'\n'}"
    if [[ -z "$plan" ]]; then
        echo "nothing to signal"
        _agents_notify "Nothing killed${refused:+: $refused}"
        return 1
    fi
    n="$(printf '%s\n' "$plan" | grep -c .)"
    printf '%s\n' "$plan" | awk -F '\t' '{ printf "  %-7s %s\n", $1, $3 }'
    if [[ "$AGENTS_DRY_RUN" == true ]]; then
        if [[ "$tree" == true ]]; then
            echo "dry run: would send SIGTERM to $n process(es), then SIGKILL to any left after ${AGENTS_GRACE}s"
        else
            echo "dry run: would send SIGTERM to $n process(es)"
        fi
        return 0
    fi
    if [[ "${AGENTS_CONFIRM_GUI:-false}" == true ]]; then
        _agents_gui_confirm "$(_agents_kill_message "$desc")" || { echo "cancelled"; return 1; }
    else
        _agents_confirm "Send SIGTERM to $n process(es)?" || { echo "cancelled"; return 1; }
    fi
    while IFS=$'\t' read -r pid start name; do
        [[ -n "$pid" ]] || continue
        _agents_signal TERM "$pid" "$start"
    done <<<"$plan"
    _agents_log_cleanups "$desc"    # events.tsv, when the caller set _AGENTS_EV_KIND
    IFS=$'\t' read -r pid name _ <<<"$desc"
    if [[ "$tree" != true ]]; then
        echo "sent SIGTERM"
        _agents_notify "Sent SIGTERM to $name (pid $pid)"
        return 0
    fi
    # Wait up to the grace period, returning as soon as everything is gone.
    while [[ $waited -lt $((AGENTS_GRACE * 5)) ]]; do
        [[ -n "$(_agents_alive "$plan")" ]] || break
        sleep 0.2; waited=$((waited + 1))
    done
    # What survived, plus anything a still-running root's tree spawned meanwhile.
    left="$(_agents_alive "$plan")"
    extra="$(agents_snapshot | _agents_new_members "$roots" "$plan")"
    while IFS=$'\t' read -r pid start name; do
        [[ -n "$pid" ]] || continue
        echo "  SIGKILL $pid ($name)"
        _agents_signal KILL "$pid" "$start"
    done <<<"$left${extra:+$'\n'$extra}"
    echo "done"
    IFS=$'\t' read -r pid name _ <<<"$desc"
    if [[ "$(printf '%s\n' "$roots" | grep -c .)" -eq 1 ]]; then
        _agents_notify "Killed $name (pid $pid)$([[ $n -gt 1 ]] && echo " and $((n - 1)) child processes")"
    else
        _agents_notify "Killed $n processes in $(printf '%s\n' "$roots" | grep -c .) trees"
    fi
}
