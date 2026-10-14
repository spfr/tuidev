# shellcheck shell=bash
# lib/agents/lid.sh — keeping a Mac awake with the lid closed (`awake lid`).
#
# Owns: the root command and its guard, the admin dialog, the lid state file,
#   noticing sleep left disabled with nothing to restore it.
# Uses: config.sh, util.sh, snapshot.sh (_agents_start), system.sh
#   (agents_sleep_disabled), awake.sh (the holder it runs alongside),
#   notify.sh (_agents_notify).
# Public: agents_awake_lid, agents_lid_stop, agents_lid_state,
#   agents_lid_stale, _agents_lid_max, _agents_lid_warning, _AGENTS_LID_FIX.
#
# caffeinate never keeps a closed lid awake (except in closed-display mode).
# `agents awake lid DURATION` does, with `pmset -a disablesleep 1`, which
# needs root: one admin dialog (osascript `with administrator privileges`, no
# sudo rights are stored) sets it and starts a root-owned guard that sets it
# back when the time is up, the battery runs low off AC, or thermal pressure
# reaches heavy (moderate is common in a closed Mac running a build).
# `awake off` ends it early with one more dialog. macOS keeps disablesleep
# across a reboot that killed the guard: agents_lid_stale notices.
# State: $AGENTS_RUN_DIR/lid holds "guard_pid start until_epoch".

# The guard, run as root by bash: $1 seconds, $2 the battery floor in %. It
# polls once a minute; SIGUSR1 retires it without touching the setting (a new
# `awake lid` replaces it). Fixed text, passed in single quotes, so it must
# never hold one; only numbers checked in _agents_lid_cmd go around it.
# shellcheck disable=SC2016  # expanded by the root bash, not here
_AGENTS_LID_GUARD='end=$(( $(/bin/date +%s) + $1 )); min=$2; re="([0-9]+)%;"
restore() { /usr/bin/pmset -a disablesleep 0; exit 0; }
trap restore TERM INT HUP
trap "exit 0" USR1
while [ "$(/bin/date +%s)" -lt "$end" ]; do
    b="$(/usr/bin/pmset -g batt)"
    case "$b" in
        *"AC Power"*) ;;
        *) if [[ $b =~ $re ]] && [ "${BASH_REMATCH[1]}" -lt "$min" ]; then restore; fi ;;
    esac
    t="$(/usr/bin/notifyutil -g com.apple.system.thermalpressurelevel 2>/dev/null)"
    t="${t##* }"
    case "$t" in
        ""|*[!0-9]*) ;;
        *) if [ "$t" -ge 2 ]; then restore; fi ;;
    esac
    /bin/sleep 60 &
    wait $!
done
restore'

# _agents_lid_cmd start SECS BATTERY [OLD_GUARD] | stop [GUARD] — the command
# `do shell script` runs as root. Only the numbers checked here are added to
# fixed text; anything else is refused (exit 2). A guard pid is signalled only
# while its real uid is root's and it is still named agents-lid-guard. Every
# command is an absolute path (no echo, [ or exit that an inherited function
# could replace).
_agents_lid_cmd() {
    local what="$1" secs="" batt="" old="" retire=""
    case "$what" in
        start) secs="${2:-}" batt="${3:-}" old="${4:-}"
               [[ "$secs" =~ ^[1-9][0-9]{0,6}$ && "$batt" =~ ^([0-9]|[1-9][0-9]|100)$ ]] || return 2 ;;
        stop)  old="${2:-}" ;;
        *)     return 2 ;;
    esac
    if [[ -n "$old" ]]; then
        [[ "$old" =~ ^[1-9][0-9]{0,7}$ ]] || return 2
        retire="if $(_agents_lid_root_check "$old"); then /bin/kill -USR1 $old; fi"
    fi
    [[ "$_AGENTS_LID_GUARD$_AGENTS_LID_SETSID" != *"'"* ]] || return 2
    if [[ "$what" == stop ]]; then
        printf '/usr/bin/pmset -a disablesleep 0%s\n' "${retire:+; $retire}"
    else
        # The guard starts in a session of its own (perl's setsid, then exec:
        # macOS has no setsid command), so nothing that ends the dialog's
        # process group takes it along; env -i, so the root bash reads nothing
        # from the caller's environment (BASH_ENV). Two seconds later it must
        # still run as root under its name, or sleep is turned back on right
        # here and the command fails: lid mode is never left without a guard.
        printf "%sif /usr/bin/pmset -a disablesleep 1; then /usr/bin/perl -MPOSIX -e '%s' /usr/bin/env -i /bin/bash -c '%s' agents-lid-guard %s %s </dev/null >/dev/null 2>&1 & g=\$!; /bin/sleep 2; if %s; then /bin/echo \$g; else /usr/bin/pmset -a disablesleep 0; /bin/echo \"%s\" >&2; /usr/bin/false; fi; else /bin/echo \"agents-lid: pmset failed; nothing changed\" >&2; /usr/bin/false; fi\n" \
            "${retire:+$retire; }" "$_AGENTS_LID_SETSID" "$_AGENTS_LID_GUARD" "$secs" "$batt" \
            "$(_agents_lid_root_check "\$g")" "$_AGENTS_LID_NOSTART"
    fi
}

# perl: become a session leader, then exec the guard (fixed text, no quotes).
_AGENTS_LID_SETSID='POSIX::setsid() >= 0 or die "setsid: $!"; exec @ARGV; die "exec: $!"'
_AGENTS_LID_NOSTART="agents-lid: the guard did not start; sleep restored"
# _agents_lid_root_check PID — the root shell's test that PID (a number, or
# $g) is root's agents-lid-guard: its real uid is 0 and its argv names it.
_agents_lid_root_check() {
    # shellcheck disable=SC2016  # expanded by the root shell, not here
    printf '/bin/test "$(/bin/ps -o ruid= -p %s 2>/dev/null)" -eq 0 2>/dev/null && /bin/ps -ww -o args= -p %s 2>/dev/null | /usr/bin/grep -q " agents-lid-guard "' "$1" "$1"
}

# The osascript that asks for the password: always /usr/bin/osascript, except
# that the test harness (AGENTS_TESTING) points it at a stub.
_agents_osascript() {
    if [[ -n "${AGENTS_TESTING:-}" && -n "${AGENTS_OSASCRIPT:-}" ]]; then echo "$AGENTS_OSASCRIPT"; else echo /usr/bin/osascript; fi
}

# _agents_admin_run COMMAND PROMPT — run COMMAND as root after macOS's own
# password dialog (PROMPT says why). Both travel as arguments, never inside
# AppleScript source, and osascript starts with an empty environment, so no
# PATH, BASH_ENV or exported function reaches the root shell. Fails when the
# dialog is cancelled; osascript's own message goes to stderr.
_agents_admin_run() {
    local osa; osa="$(_agents_osascript)"
    [[ -x "$osa" ]] || { echo "agents: no $osa to ask for an administrator password" >&2; return 1; }
    /usr/bin/env -i "$osa" -e 'on run argv' \
        -e 'do shell script (item 1 of argv) with prompt (item 2 of argv) with administrator privileges' \
        -e 'end run' "$1" "$2"
}

_agents_lid_supported() {
    command -v pmset >/dev/null 2>&1 && [[ -x "$(_agents_osascript)" ]] && return 0
    echo "agents: keeping awake with the lid closed is macOS only (it needs pmset and osascript)" >&2
    return 2
}

# agents_lid_state — "pid until verified" while the recorded guard runs (the
# same checks as agents_awake_state: cleared once it is really gone or its
# pid names another process; a root process answers kill -0 with EPERM).
agents_lid_state() {
    local file="$AGENTS_RUN_DIR/lid" content pid start until verified=0
    [[ -f "$file" ]] || return 1
    content="$(cat "$file" 2>/dev/null)"
    read -r pid start until <<<"$content" || true
    _agents_holder_check "$file" "$content" "$pid" "$start"
    case $? in
        0) verified=1 ;;
        1) return 1 ;;
    esac
    if [[ $verified -eq 0 && ( -z "$start" || "$start" == - ) ]]; then
        # No start time was recorded: only root's agents-lid-guard counts. A
        # pid that now names something else is dropped; when ps answers
        # nothing, it can't be told, and the guard is not counted as live.
        _agents_lid_is_guard "$pid"
        case $? in
            0) verified=1 ;;
            1) _agents_rm_if_same "$file" "$content"; return 1 ;;
            *) return 1 ;;
        esac
    fi
    echo "$pid ${until:-0} $verified"
}

# _agents_lid_is_guard PID — 0 when PID is root's agents-lid-guard (real uid
# 0, named in its argv), 1 when ps shows another process or none, 2 when ps
# can't be asked.
_agents_lid_is_guard() {
    local out
    out="$(LC_ALL=C ps -ww -o ruid=,args= -p "$1" 2>/dev/null)"
    if [[ -z "$out" ]]; then
        LC_ALL=C ps -o pid= -p "$$" >/dev/null 2>&1 && return 1
        return 2
    fi
    printf '%s\n' "$out" | awk 'NR == 1 && $1 == 0 { r = 1 } / agents-lid-guard / { g = 1 } END { exit !(r && g) }'
}

# _agents_lid_max — AGENTS_LID_MAX in seconds (8h if it does not parse).
_agents_lid_max() { agents_parse_duration "$AGENTS_LID_MAX" || echo 28800; }

# agents_lid_stale — true when sleep is disabled and no guard of ours will
# turn it back on (a reboot killed it, or someone ran pmset by hand).
agents_lid_stale() {
    [[ "$(agents_sleep_disabled)" == 1 ]] || return 1
    ! agents_lid_state >/dev/null
}
_AGENTS_LID_FIX="agents awake restore (or: sudo pmset -a disablesleep 0)"
_agents_lid_warning() {
    agents_lid_stale || return 0
    printf '%sWARNING: lid sleep is disabled and nothing will restore it. Fix: %s%s\n' "${C_R:-}${C_B:-}" "$_AGENTS_LID_FIX" "${C_0:-}"
}

# agents_awake_lid DURATION — keep awake with the lid closed for DURATION (at
# most AGENTS_LID_MAX), plus the usual caffeinate holder for the same time.
agents_awake_lid() {
    local dur="${1:-}" secs max cmd out gpid old="" state until start pid v
    _agents_lid_supported || return 2
    if [[ -z "$dur" ]]; then
        echo "usage: agents awake lid DURATION (30m, 3h; at most $AGENTS_LID_MAX)" >&2; return 2
    fi
    secs="$(agents_parse_duration "$dur")" || { echo "agents: bad duration '$dur' (try 30m, 3h, 1h30m)" >&2; return 2; }
    max="$(_agents_lid_max)"
    if [[ $secs -gt $max ]]; then
        echo "agents: $dur is longer than AGENTS_LID_MAX ($AGENTS_LID_MAX); lid mode is always time-boxed" >&2; return 2
    fi
    if ! [[ "$AGENTS_LID_MIN_BATTERY" =~ ^([0-9]|[1-9][0-9]|100)$ ]]; then
        echo "agents: AGENTS_LID_MIN_BATTERY must be 0-100" >&2; return 2
    fi
    _agents_inhibitor || return 1
    mkdir -p "$AGENTS_RUN_DIR" || return 1
    # Refuse before the dialog what we could not clean up after it.
    if state="$(agents_awake_state)" && [[ "${state##* }" != 1 ]]; then
        echo "awake: can't verify the current keep-awake holder (pid ${state%% *}); run 'agents awake off' first" >&2; return 1
    fi
    if state="$(agents_lid_state)"; then
        read -r pid _ v <<<"$state"; [[ "$v" == 1 ]] && old="$pid"
    fi
    cmd="$(_agents_lid_cmd start "$secs" "$AGENTS_LID_MIN_BATTERY" "$old")" || { echo "agents: refusing to build the root command" >&2; return 2; }
    if ! out="$(_agents_admin_run "$cmd" "agents wants to keep your Mac awake with the lid closed for $dur. Lid sleep comes back after that, below ${AGENTS_LID_MIN_BATTERY}% battery, or when the Mac runs hot." 2>"$AGENTS_RUN_DIR/lid.err")"; then
        _agents_admin_failed "lid mode was not started"; return 1
    fi
    rm -f "$AGENTS_RUN_DIR/lid.err"
    gpid="${out##*$'\n'}"
    if [[ ! "$gpid" =~ ^[0-9]+$ ]]; then
        _agents_lid_failed "the root step reported no guard"; return 1
    fi
    # The root step checked the guard before it returned; check again now
    # that it has, in case ending the dialog took the guard along.
    sleep 1
    _agents_lid_is_guard "$gpid"
    case $? in
        1) _agents_lid_failed "its guard (pid $gpid) stopped when the dialog ended"; return 1 ;;
        2) echo "awake: can't run ps to check the guard (pid $gpid); see 'agents awake status'" >&2 ;;
    esac
    until=$(( $(date +%s) + secs ))
    start="$(_agents_start "$gpid")"
    # The record first, then the cached SleepDisabled: never "disabled with no
    # guard" in between.
    printf '%s %s %s\n' "$gpid" "${start:--}" "$until" > "$AGENTS_RUN_DIR/lid"
    rm -f "$AGENTS_RUN_DIR/powermode"
    _agents_awake_off_holder >/dev/null || true
    _agents_detach _agents_hold "$secs"
    pid=$!
    _agents_awake_write "$pid" lid "$until"
    echo "awake: on with the lid closed until $(_agents_clock "$until") (guard pid $gpid): lid sleep comes back then, below ${AGENTS_LID_MIN_BATTERY}% battery off AC, or when the Mac runs hot (heavy thermal pressure)"
    _agents_notify "Awake with the lid closed until $(_agents_clock "$until")"
}

# _agents_lid_failed WHY — lid mode started but has no guard: say so, and turn
# lid sleep back on (one more dialog).
_agents_lid_failed() {
    rm -f "$AGENTS_RUN_DIR/powermode"
    echo "awake: lid mode failed to start: $1; turning lid sleep back on" >&2
    if agents_lid_stop --always >/dev/null; then
        echo "awake: lid mode failed to start; sleep restored" >&2
        _agents_notify "Lid mode failed to start ($1); sleep restored"
    else
        echo "awake: lid sleep is disabled and nothing will restore it: run '$_AGENTS_LID_FIX'" >&2
        _agents_notify "Lid mode failed and lid sleep is still disabled: use Restore lid sleep"
    fi
}

# agents_lid_stop [--always] — turn lid sleep back on (one admin dialog) and
# retire our guard. Without --always, only when a guard of ours runs.
agents_lid_stop() {
    local state pid="" v cmd
    if state="$(agents_lid_state)"; then
        read -r pid _ v <<<"$state"; [[ "$v" == 1 ]] || pid=""
    elif [[ "${1:-}" != --always ]]; then
        # No guard of ours: still act when sleep is disabled with nothing to
        # restore it (a reboot or a crash killed the guard). Ask pmset afresh.
        rm -f "$AGENTS_RUN_DIR/powermode"
        [[ "$(agents_sleep_disabled)" == 1 ]] || return 0
    fi
    _agents_lid_supported || return 2
    cmd="$(_agents_lid_cmd stop "$pid")" || { echo "agents: refusing to build the root command" >&2; return 2; }
    mkdir -p "$AGENTS_RUN_DIR" || return 1
    if ! _agents_admin_run "$cmd" "agents wants to let your Mac sleep with the lid closed again." >/dev/null 2>"$AGENTS_RUN_DIR/lid.err"; then
        _agents_admin_failed "lid sleep was not restored"; return 1
    fi
    rm -f "$AGENTS_RUN_DIR/lid.err"
    # The cached SleepDisabled first, then the record (see agents_awake_lid).
    rm -f "$AGENTS_RUN_DIR/powermode"
    rm -f "$AGENTS_RUN_DIR/lid"
    echo "awake: lid sleep restored"
    _agents_notify "Lid sleep restored"
}

# _agents_admin_failed WHAT — report a failed admin step with osascript's own
# message. Cancelling the dialog (-128) runs nothing; any other failure may
# have run part of the root command, so say how to check.
_agents_admin_failed() {
    local err=""
    err="$(cat "$AGENTS_RUN_DIR/lid.err" 2>/dev/null)"; rm -f "$AGENTS_RUN_DIR/lid.err" "$AGENTS_RUN_DIR/powermode"
    if [[ "$err" == *"(-128)"* ]]; then
        echo "awake: cancelled in the password dialog; $1, nothing ran as root" >&2
        _agents_notify "Cancelled: $1"
    elif [[ "$err" == *"$_AGENTS_LID_NOSTART"* || "$err" == *"agents-lid: pmset failed; nothing changed"* ]]; then
        if [[ "$err" == *"$_AGENTS_LID_NOSTART"* ]]; then
            echo "awake: lid mode failed to start: its guard did not start; sleep restored" >&2
            _agents_notify "Lid mode failed to start (no guard); sleep restored"
        else
            echo "awake: lid mode failed to start: pmset refused; nothing changed" >&2
            _agents_notify "Lid mode failed to start: pmset refused"
        fi
    else
        _agents_notify "Failed: $1; check Restore lid sleep in the menu"
        echo "awake: the administrator step failed${err:+: $err}" >&2
        echo "awake: $1 as asked, but part of it may have run: check 'pmset -g | grep SleepDisabled'; to be sure, run '$_AGENTS_LID_FIX'" >&2
    fi
}
