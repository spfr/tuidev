# shellcheck shell=bash
# lib/agents/awake.sh — keeping the machine awake (`agents awake`).
#
# Owns: the keep-awake holder (caffeinate -di on macOS, systemd-inhibit on
#   Linux): on for a while, on until off, on while agents run; its state
#   file, its lock and its status line; the `agents awake` command.
# Uses: config.sh, util.sh (_agents_holder_check), snapshot.sh
#   (agents_snapshot, _agents_start),
#   classify.sh (agents_classify), lid.sh (lid mode runs alongside a holder:
#   its state, `awake off` and `awake restore` end it).
# Public: agents_awake, agents_awake_state, agents_awake_line,
#   agents_awake_holders, _agents_awake_prime, _agents_awake_now,
#   _agents_awake_pid; and, for lid.sh, _agents_hold, _agents_awake_write,
#   _agents_awake_off_holder, _agents_inhibitor.
#
# State: $AGENTS_RUN_DIR/awake holds "pid start mode until_epoch". The start
# time guards against a reused pid after a reboot or a crash.

_agents_awake_file() { echo "$AGENTS_RUN_DIR/awake"; }

# agents_awake_state — "pid mode until verified" for a recorded holder that
# still exists; verified is 1 when its start time matches the record, 0 when
# it can't be checked (ps unavailable, or a "-" start recorded in a sandbox).
# The record is cleared only when the holder is really gone: kill -0 says "No
# such process", or the pid now names a process with another start time. A
# permission error (EPERM) proves nothing and keeps the record.
agents_awake_state() {
    local file content pid start mode until verified=0
    file="$AGENTS_RUN_DIR/awake"   # _agents_awake_file, without the fork
    [[ -f "$file" ]] || return 1
    { IFS= read -r -d '' content < "$file"; } 2>/dev/null || true   # $(cat FILE) without the fork
    while [[ "$content" == *$'\n' ]]; do content="${content%$'\n'}"; done
    read -r pid start mode until <<<"$content" || true
    _agents_holder_check "$file" "$content" "$pid" "$start"
    case $? in 0) verified=1 ;; 1) return 1 ;; esac
    echo "$pid $mode ${until:-0} $verified"
}

# Serialize on/off/agents with a lock directory, waiting up to five seconds
# (a lock whose holder is gone is taken over: _agents_lock).
_agents_awake_lock() {
    mkdir -p "$AGENTS_RUN_DIR" || return 1
    _agents_lock "$AGENTS_RUN_DIR/awake.lock" 50 0.1 && return 0
    echo "agents: keep-awake is busy (remove $AGENTS_RUN_DIR/awake.lock if no other agents runs)" >&2
    return 1
}
_agents_awake_unlock() { _agents_unlock "$AGENTS_RUN_DIR/awake.lock"; }

# The platform's sleep inhibitor, or fail with a message.
_agents_inhibitor() {
    command -v caffeinate >/dev/null 2>&1 && return 0
    command -v systemd-inhibit >/dev/null 2>&1 && return 0
    echo "agents: no caffeinate or systemd-inhibit on this system; keep-awake is unavailable" >&2
    return 1
}
# _agents_awake_now [VAR] — agents_awake_state, read once per run once primed
# (the menu and the table ask several times; _agents_awake_prime re-reads it).
# With VAR, VAR gets it instead of stdout (no subshell). False when none.
_agents_awake_prime() { _AGENTS_AWAKE_STATE="$(agents_awake_state)"; _AGENTS_AWAKE_PRIMED=1; }
_agents_awake_now() {
    local _s
    if [[ -n "${_AGENTS_AWAKE_PRIMED:-}" ]]; then _s="$_AGENTS_AWAKE_STATE"; else _s="$(agents_awake_state)"; fi
    if [[ -n "${1:-}" ]]; then printf -v "$1" '%s' "$_s"; elif [[ -n "$_s" ]]; then echo "$_s"; fi
    [[ -n "$_s" ]]
}
_agents_awake_pid() { local s; _agents_awake_now s && echo "${s%% *}"; }

# _agents_hold [SECS] [WATCH_PID] — run the platform's sleep inhibitor in the
# foreground: caffeinate -di (system and display idle sleep) on macOS,
# systemd-inhibit on Linux.
_agents_hold() {
    local secs="${1:-}" watch="${2:-}"
    if command -v caffeinate >/dev/null 2>&1; then
        exec caffeinate -di ${secs:+-t "$secs"} ${watch:+-w "$watch"}
    elif command -v systemd-inhibit >/dev/null 2>&1; then
        exec systemd-inhibit --what=idle:sleep --who=agents --why="agents awake" sleep "${secs:-infinity}"
    fi
    echo "agents: no caffeinate or systemd-inhibit on this system" >&2
    return 1
}

# The forked child already has its final start time (exec keeps it), so the
# pidfile can be written straight away.
_agents_awake_write() {   # PID MODE UNTIL
    mkdir -p "$AGENTS_RUN_DIR"
    local start; start="$(_agents_start "$1")"
    printf '%s %s %s %s\n' "$1" "${start:--}" "$2" "$3" > "$(_agents_awake_file)"
}

# agents_awake_off — release: lid mode first (when on), then the holder.
agents_awake_off() {
    agents_lid_stop || return 1
    _agents_awake_off_holder
}

_agents_awake_off_holder() {
    local state pid file content
    file="$(_agents_awake_file)"
    content="$(cat "$file" 2>/dev/null)"
    state="$(agents_awake_state)" || { echo "awake: already off"; return 0; }
    pid="${state%% *}"
    if [[ "${state##* }" != 1 ]]; then
        echo "awake: can't verify that pid $pid is the keep-awake holder (its start time is unknown); not stopping it" >&2
        echo "awake: if it is, run 'kill $pid' and remove $file" >&2
        return 1
    fi
    kill "$pid" 2>/dev/null
    _agents_rm_if_same "$file" "$content"
    echo "awake: off (stopped pid $pid)"
}

agents_awake_on() {
    local secs="" until=0 pid mode
    _agents_inhibitor || return 1
    if [[ -n "${1:-}" ]]; then
        secs="$(agents_parse_duration "$1")" || { echo "agents: bad duration '$1' (try 30m, 2h, 1h30m)" >&2; return 2; }
        until=$(( $(date +%s) + secs ))
    fi
    # Only the holder is replaced: lid mode, when on, keeps running until it
    # times out or `awake off` / `awake restore` ends it (no dialog here).
    _agents_awake_off_holder >/dev/null || return 1
    _agents_detach _agents_hold "$secs"
    pid=$!
    if [[ -n "$secs" ]]; then mode=timed; else mode=on; fi
    _agents_awake_write "$pid" "$mode" "$until"
    if [[ -n "$secs" ]]; then echo "awake: on until $(_agents_clock "$until") (pid $pid)"; else echo "awake: on until 'agents awake off' (pid $pid)"; fi
}

agents_awake_agents() {
    local pid
    _agents_inhibitor || return 1
    if [[ "$(_agents_count)" -eq 0 ]]; then
        echo "awake: no claude or codex session is running; nothing to hold"
        return 0
    fi
    _agents_awake_off_holder >/dev/null || return 1   # lid mode keeps running
    nohup bash "$AGENTS_PATH" _awake-loop </dev/null >/dev/null 2>&1 &
    pid=$!
    disown "$pid" 2>/dev/null
    _agents_awake_write "$pid" agents 0
    echo "awake: on while agents run (pid $pid, re-checked every ${AGENTS_AWAKE_POLL}s)"
}

# Number of claude/codex roots running now (the daemon does not count).
_agents_count() {
    agents_snapshot | agents_classify "" "" | awk -F '\t' '$1 == "agent" && $3 != "daemon" { n++ } END { print n + 0 }'
}

# The `awake agents` background loop: hold while any agent runs, then exit.
_agents_awake_loop() {
    local hold="" sleeper=""
    trap '[[ -n "$hold" ]] && kill "$hold" 2>/dev/null; [[ -n "$sleeper" ]] && kill "$sleeper" 2>/dev/null; exit 0' TERM INT HUP
    while [[ "$(_agents_count)" -gt 0 ]]; do
        if [[ -z "$hold" ]] || ! kill -0 "$hold" 2>/dev/null || _agents_zombie "$hold"; then
            _agents_detach _agents_hold "" "$$"
            hold=$!
        fi
        sleep "$AGENTS_AWAKE_POLL" &
        sleeper=$!
        wait "$sleeper"
    done
    [[ -n "$hold" ]] && kill "$hold" 2>/dev/null
    local file; file="$(_agents_awake_file)"
    [[ -f "$file" && "$(awk '{ print $1 }' "$file")" == "$$" ]] && rm -f "$file"
    exit 0
}

agents_awake_line() {
    local state pid mode until verified lid=""
    lid="$(agents_lid_state)" || lid=""
    if _agents_awake_now state; then
        read -r pid mode until verified <<<"$state"
        local note="pid $pid"
        [[ "$verified" == 1 ]] || note="pid $pid, unverified"
        case "$mode" in
            timed)  echo "awake: on until $(_agents_clock "$until") ($note)${lid:+; lid closed too until $(_agents_clock "$(_agents_field 2 "$lid")")}" ;;
            agents) echo "awake: while agents run ($note)${lid:+; lid closed too until $(_agents_clock "$(_agents_field 2 "$lid")")}" ;;
            lid)    if [[ -n "$lid" ]]; then echo "awake: lid closed too, until $(_agents_clock "$until") ($note; guard pid ${lid%% *})"
                    elif agents_lid_stale; then echo "awake: on until $(_agents_clock "$until") ($note; lid sleep is disabled and nothing will restore it)"
                    else echo "awake: on until $(_agents_clock "$until") ($note; lid mode ended, a closed lid sleeps again)"; fi ;;
            *)      echo "awake: on ($note)" ;;
        esac
    elif [[ -n "$lid" ]]; then
        read -r pid until _ <<<"$lid"
        echo "awake: lid closed, until $(_agents_clock "$until") (guard pid $pid)"
    else
        echo "awake: off"
    fi
}

# Who else holds the Mac awake: owner names from `pmset -g assertions`, deduplicated.
agents_awake_holders() {
    command -v pmset >/dev/null 2>&1 || return 0
    pmset -g assertions 2>/dev/null | awk '
        /^Listed by owning process:/ { on = 1; next }
        /^[A-Z]/ { on = 0 }
        on && /pid [0-9]+\(/ && /Prevent(UserIdle)?(System|Display)Sleep|NoIdleSleep|NoDisplaySleep/ {
            s = $0; sub(/^[^(]*\(/, "", s); sub(/\):.*$/, "", s)
            pid = $2; sub(/\(.*/, "", pid)
            if (s == "powerd" || seen[pid]++) next
            if (!(s in c)) o[++n] = s
            c[s]++
        }
        END { for (i = 1; i <= n; i++) printf "%s%s%s", (i > 1 ? ", " : ""), o[i], (c[o[i]] > 1 ? " x" c[o[i]] : ""); if (n) print "" }'
}

agents_awake() {
    local rc
    case "${1:-status}" in
        on|off|agents|lid|restore)
            _agents_awake_lock || return 1
            # Release the lock however this ends (an error exit, Ctrl-C, kill).
            trap '_agents_awake_unlock' EXIT
            trap '_agents_awake_unlock; exit 130' INT
            trap '_agents_awake_unlock; exit 143' TERM
            case "$1" in
                on)      agents_awake_on "${2:-}" ;;
                off)     agents_awake_off ;;
                agents)  agents_awake_agents ;;
                lid)     agents_awake_lid "${2:-}" ;;
                restore) agents_lid_stop --always ;;
            esac
            rc=$?
            _agents_awake_unlock
            trap - EXIT INT TERM
            return "$rc"
            ;;
        status)
            agents_awake_line
            local h; h="$(agents_awake_holders)"
            [[ -z "$h" ]] || echo "held awake by: $h"
            _agents_lid_warning
            ;;
        *) echo "usage: agents awake [on [DURATION]|lid DURATION|off|agents|restore|status]" >&2; return 2 ;;
    esac
}
