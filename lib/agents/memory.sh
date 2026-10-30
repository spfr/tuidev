# shellcheck shell=bash
# lib/agents/memory.sh — what holds the memory, and the guard against runaways.
#
# Owns: each process's footprint (macOS's top MEM, which keeps counting the
#   pages the compressor squeezes and swap takes: ps's RSS falls while a
#   runaway grows), the machine's memory (total, free %, pressure, swap), the
#   memory guard (`agents mem guard`: warn about, record and stop a runaway
#   in an agent tree before macOS runs out of application memory), its
#   state and its incident log, memory.tsv.
# Uses: config.sh, util.sh, render.sh (the colors), snapshot.sh
#   (agents_snapshot, _agents_cwds), classify.sh (agents_project), system.sh
#   (_agents_parse_memfree), kill.sh (_agents_kill_unattended), events.sh
#   (_agents_data_dir), notify.sh, where.sh (agents_root_of); awk/memory.awk.
# Public: agents_mem, agents_mem_tick, agents_mem_machine, _agents_mem_fp,
#   _agents_mem_tsv_row, _agents_mem_guard_state.
#
# memory.tsv, in $AGENTS_DATA_DIR (private, names only, pruned with the
# history), one line per incident:
#   epoch event pid name label project session footprint_kib rss_kib free_pct swap_used_kib
#   event:   warn (past AGENTS_MEM_WARN, or a doubling of it), grow (faster
#            than AGENTS_MEM_RATE), stop (the guard stopped it), refused (it
#            could not), pressure (memory pressure turned critical; the
#            biggest process at the time)
#   label:   the script an interpreter runs (clientFuelToday.test.js), "-"
#   session: the agent tree it ran in, as kind:pid ("-" outside one)

# The LaunchAgent the monitoring pack installs on macOS to run the guard.
AGENTS_MEM_LABEL="dev.tuidev.memguard"

# _agents_mem_top ARGS... — macOS top, one sample (the tests replace it).
_agents_mem_top() { LC_ALL=C top -l 1 "$@" 2>/dev/null; }

# _agents_mem_parse_top < top output — "pid<TAB>kib" for each row of a
# `top -stats pid,mem` sample (MEM as 2809M, 1.2G, 512K or 0B, maybe with a
# trailing + or -).
_agents_mem_parse_top() {
    LC_ALL=C awk '
        f && $1 ~ /^[0-9]+$/ {
            v = $2; sub(/[+-]$/, "", v); u = substr(v, length(v)); x = substr(v, 1, length(v) - 1) + 0
            k = (u == "G") ? x * 1048576 : (u == "M") ? x * 1024 : (u == "K") ? x : (u == "B") ? x / 1024 : v + 0
            printf "%d\t%d\n", $1, k
        }
        $1 == "PID" { f = 1 }'
}

# _agents_mem_fp PID... — "pid<TAB>footprint_kib" for each that top reports;
# nothing off macOS (RSS is the footprint there). One top sample costs about
# a third of a second of CPU, however many pids: the guard asks only about
# its few candidates.
_agents_mem_fp() {
    [[ "$OSTYPE" == darwin* && $# -gt 0 ]] || return 0
    local a=() p
    for p in "$@"; do a+=(-pid "$p"); done
    _agents_mem_top -stats pid,mem "${a[@]}" | _agents_mem_parse_top
}

# _agents_mem_total — the RAM in KiB (it never changes: cached in the run dir).
_agents_mem_total() {
    local f="$AGENTS_RUN_DIR/memtotal" t=""
    { read -r t < "$f"; } 2>/dev/null
    if [[ ! "$t" =~ ^[1-9][0-9]*$ ]]; then
        if [[ -r /proc/meminfo ]]; then
            t="$(awk '/^MemTotal:/ { print $2; exit }' /proc/meminfo)"
        else
            t="$(LC_ALL=C sysctl -n hw.memsize 2>/dev/null)"
            [[ "$t" =~ ^[0-9]+$ ]] && t=$((t / 1024))
        fi
        [[ "$t" =~ ^[1-9][0-9]*$ ]] || t=0
        [[ $t -eq 0 ]] || { mkdir -p "$AGENTS_RUN_DIR" && _agents_replace "$f" "$t"; } 2>/dev/null
    fi
    echo "$t"
}

# agents_mem_machine — "total_kib free_pct level swap_used_kib swap_total_kib",
# tab-separated. level: normal, warn or critical (macOS's memory pressure;
# on Linux, MemAvailable under 15% or 5%), "-" when unknown; "-" for any
# number it can't read.
agents_mem_machine() {
    local total free="" level="" su="-" stot="-" line
    total="$(_agents_mem_total)"
    if [[ -r /proc/meminfo ]]; then
        read -r free su stot <<<"$(awk '
            /^MemTotal:/ { t = $2 } /^MemAvailable:/ { a = $2 } /^SwapTotal:/ { st = $2 } /^SwapFree:/ { sf = $2 }
            END { printf "%s %s %s\n", (t ? int(100 * a / t) : "-"), (st == "" ? "-" : st - sf), (st == "" ? "-" : st) }' /proc/meminfo)"
        if [[ "$free" =~ ^[0-9]+$ ]]; then
            if [[ $free -lt 5 ]]; then level=critical; elif [[ $free -lt 15 ]]; then level=warn; else level=normal; fi
        fi
    else
        free="$(_agents_parse_memfree < <(LC_ALL=C memory_pressure -Q 2>/dev/null))"
        while IFS= read -r line; do
            case "$line" in
                1) level=normal ;; 2) level=warn ;; 4) level=critical ;;
                *total\ =*) read -r su stot <<<"$(printf '%s\n' "$line" | LC_ALL=C awk '
                    function k(v,   u, x) { u = substr(v, length(v)); x = substr(v, 1, length(v) - 1) + 0
                        return int(u == "G" ? x * 1048576 : u == "M" ? x * 1024 : u == "K" ? x : x / 1024) }
                    { for (i = 1; i < NF; i++) { if ($i == "total") t = k($(i + 2)); if ($i == "used") u = k($(i + 2)) } print u + 0, t + 0 }')" ;;
            esac
        done < <(LC_ALL=C sysctl -n kern.memorystatus_vm_pressure_level vm.swapusage 2>/dev/null)
    fi
    printf '%s\t%s\t%s\t%s\t%s\n' "${total:--}" "${free:--}" "${level:--}" "${su:--}" "${stot:--}"
}

# _agents_mem_kill_kib TOTAL_KIB — the size that gets an agent tree's process
# stopped: AGENTS_MEM_KILL GB, or half the RAM (0, the default).
_agents_mem_kill_kib() {
    if [[ "$AGENTS_MEM_KILL" -gt 0 ]]; then echo $((AGENTS_MEM_KILL * 1048576))
    elif [[ "${1:-0}" =~ ^[1-9][0-9]*$ ]]; then echo $(($1 / 2))
    else echo $((24 * 1048576)); fi
}

# _agents_mem_gb KIB — "16.6G" (one decimal), for messages.
_agents_mem_gb() { printf '%d.%dG' $(($1 / 1048576)) $(($1 * 10 / 1048576 % 10)); }

# _agents_mem_what NAME LABEL — "node (clientFuelToday.test.js)", or NAME.
_agents_mem_what() { if [[ "$2" == - || -z "$2" ]]; then printf '%s' "$1"; else printf '%s (%s)' "$1" "$2"; fi; }

# _agents_mem_project PID — the short name of PID's working directory, "-".
_agents_mem_project() {
    local c
    c="$(_agents_cwds "$1" 2>/dev/null | cut -f2)"
    if [[ "$c" == /* ]]; then agents_project "$c"; else echo -; fi
}

# _agents_mem_record EVENT PID NAME LABEL PROJECT SESSION FP RSS FREE SWAP —
# one incident in memory.tsv (nothing with AGENTS_HISTORY=0). Never fails.
_agents_mem_record() {
    [[ "$AGENTS_HISTORY" == 1 ]] || return 0
    local f out="" now
    _agents_now now
    for f in "$@"; do out+=$'\t'"$(_agents_tsv_field "$f")"; done
    (
        umask 077
        _agents_data_dir || exit 0
        printf '%s%s\n' "$now" "$out" >> "$AGENTS_DATA_DIR/memory.tsv"
    ) 2>/dev/null
    return 0
}

# _agents_mem_say MESSAGE PID SNAPSHOT — MESSAGE on stdout and as a
# notification (unless AGENTS_MEM_QUIET=1), a click going to the session PID
# runs under (when it runs under one).
_agents_mem_say() {
    local target=""
    printf '%s\n' "$1"
    [[ "${AGENTS_MEM_QUIET:-0}" != 1 ]] || return 0
    target="$(agents_root_of "$2" "$3" 2>/dev/null)" || target=""
    AGENTS_NOTIFY=true _agents_notify "$1" "$target" memory
}

# _agents_mem_state_get TOKEN — set the caller's step, last, ts and grew from
# the guard's state (_AGENTS_MEM_STATE: "TOKEN step last_kib ts grew" lines).
_agents_mem_state_get() {
    local t s l w g
    step=0 last=0 ts=0 grew=0
    while read -r t s l w g; do
        [[ "$t" == "$1" ]] || continue
        step="$s" last="$l" ts="$w" grew="$g"
        return 0
    done <<<"${_AGENTS_MEM_STATE:-}"
}

# _agents_mem_step FP WARN — 0 under WARN, 1 past it, 2 past twice it, 3 past
# four times… (a warning for each step up).
_agents_mem_step() {
    local fp="$1" t="$2" s=0
    [[ "$t" -gt 0 ]] || { echo 0; return; }
    while [[ $fp -ge $t && $s -lt 16 ]]; do s=$((s + 1)); t=$((t * 2)); done
    echo "$s"
}

# agents_mem_tick — one look by the memory guard (AGENTS_MEM_GUARD; `agents
# mem check` runs one and prints what it decided). One ps; top only for the
# few processes past half the warning (or the largest few while memory
# pressure is up), never for the rest. Per process, by footprint (or RSS
# when larger): in an agent tree, below its agent, yours, past the stop size
# (or the largest such past the warning while pressure is critical), it is
# stopped, tree and all, the usual way (SIGTERM, then SIGKILL after
# AGENTS_GRACE); past the warning, or a doubling of it, a warning; growing
# faster than AGENTS_MEM_RATE MB/s, one warning. An agent itself is never
# stopped, only warned about. Each is recorded (memory.tsv, a stop in
# events.tsv too) and notified, a click going to its session. A pressure
# level turning critical is recorded with the biggest process. With
# AGENTS_DRY_RUN=true it only says what it would stop.
agents_mem_tick() {
    local total free level su stot warn stopkib screen floor snap cands fps now
    local pid start rss uid name label root rkind fp f v tok step last ts grew rate news="" prev="" first=""
    local what proj session msg stopped="" dry="${AGENTS_DRY_RUN:-false}"
    [[ "$AGENTS_MEM_GUARD" != off ]] || { echo "the memory guard is off (AGENTS_MEM_GUARD=off)"; return 0; }
    _agents_now now
    IFS=$'\t' read -r total free level su stot <<<"$(agents_mem_machine)"
    [[ "$total" =~ ^[0-9]+$ ]] || total=0
    warn=$((AGENTS_MEM_WARN * 1048576)); stopkib="$(_agents_mem_kill_kib "$total")"
    screen=$((warn / 2)); floor=0
    [[ "$level" == warn || "$level" == critical ]] && floor=524288
    snap="$(agents_snapshot)"
    cands="$(printf '%s\n' "$snap" | AGENTS_NAMES="$AGENTS_NAMES" \
        _agents_awk "lib_proc memory" -v self="$AGENTS_SELF" -v screen="$screen" -v floor="$floor" -v max=8)"
    [[ -n "${_AGENTS_MEM_STATE+set}" ]] || _agents_mem_state_load
    prev="${_AGENTS_MEM_LEVEL:--}"
    if [[ -n "$cands" ]]; then
        # shellcheck disable=SC2046  # one pid per word
        fps="$(_agents_mem_fp $(printf '%s\n' "$cands" | cut -f1))"
    fi
    while IFS=$'\t' read -r pid start rss uid name label root rkind; do
        [[ "$pid" =~ ^[0-9]+$ ]] || continue
        fp="$rss"
        while IFS=$'\t' read -r f v; do [[ "$f" == "$pid" && "$v" -gt "$fp" ]] && fp="$v"; done <<<"${fps:-}"
        tok="$pid@$start"; what="$(_agents_mem_what "$name" "$label")"
        session=-; [[ "$root" == - ]] || session="$rkind:$root"
        # The biggest one, for a pressure incident.
        [[ -n "$first" ]] || first="$pid"$'\t'"$name"$'\t'"$label"$'\t'"$session"$'\t'"$fp"$'\t'"$rss"
        _agents_mem_state_get "$tok"
        if [[ "$AGENTS_MEM_GUARD" == kill && "$root" != - && "$root" != "$pid" && "$uid" == "$AGENTS_UID" ]] \
            && { [[ $fp -ge $stopkib ]] || { [[ "$level" == critical && $fp -ge $warn && -z "${stopped:-}" ]]; }; }; then
            proj="$(_agents_mem_project "$pid")"
            if [[ $fp -ge $stopkib ]]; then msg="past the $(_agents_mem_gb "$stopkib") limit"; else msg="while memory pressure is critical"; fi
            if [[ "$dry" == true ]]; then
                echo "would stop $what in $proj ($session): $(_agents_mem_gb "$fp") $msg"
                continue
            fi
            if _AGENTS_EV_KIND=guard _AGENTS_EV_REASONS="$pid"$'\t'memory$'\t'"$session" _agents_kill_unattended "$tok" >/dev/null 2>&1; then
                _agents_mem_record stop "$pid" "$name" "$label" "$proj" "$session" "$fp" "$rss" "$free" "$su"
                _agents_mem_say "Stopped $what in $proj: it held $(_agents_mem_gb "$fp") $msg ($session)" "$pid" "$snap"
                stopped=1
            else
                _agents_mem_record refused "$pid" "$name" "$label" "$proj" "$session" "$fp" "$rss" "$free" "$su"
                _agents_mem_say "Could not stop $what in $proj ($(_agents_mem_gb "$fp")): agents kill $tok" "$pid" "$snap"
                news+="$tok $step $fp $now $grew"$'\n'
            fi
            continue
        fi
        v="$(_agents_mem_step "$fp" "$warn")"
        if [[ $v -gt $step ]]; then
            proj="$(_agents_mem_project "$pid")"
            [[ "$dry" == true ]] || _agents_mem_record warn "$pid" "$name" "$label" "$proj" "$session" "$fp" "$rss" "$free" "$su"
            msg="$what in $proj holds $(_agents_mem_gb "$fp")"
            if [[ "$root" == - || "$root" == "$pid" || "$AGENTS_MEM_GUARD" != kill ]]; then msg+=" (not stopped by the guard)"
            else msg+="; stopped at $(_agents_mem_gb "$stopkib")"; fi
            if [[ "$dry" == true ]]; then echo "would warn: $msg"; else _agents_mem_say "$msg" "$pid" "$snap"; fi
            step="$v"
        elif [[ $v -lt $step ]]; then
            step="$v"
        fi
        # Growth since the last look, in KiB/s: one warning per process.
        if [[ "$grew" == 0 && $ts -gt 0 && $now -gt $ts && $fp -ge 1048576 ]]; then
            rate=$(( (fp - last) / (now - ts) ))
            if [[ $rate -ge $((AGENTS_MEM_RATE * 1024)) ]]; then
                proj="$(_agents_mem_project "$pid")"
                msg="$what in $proj is growing $((rate / 1024)) MB/s ($(_agents_mem_gb "$fp") now)"
                if [[ "$dry" == true ]]; then echo "would warn: $msg"
                else
                    _agents_mem_record grow "$pid" "$name" "$label" "$proj" "$session" "$fp" "$rss" "$free" "$su"
                    _agents_mem_say "$msg" "$pid" "$snap"; grew=1
                fi
            fi
        fi
        news+="$tok $step $fp $now $grew"$'\n'
    done <<<"${cands:-}"
    if [[ "$level" == critical && "$prev" != critical && -n "$first" && "$dry" != true ]]; then
        IFS=$'\t' read -r pid name label session fp rss <<<"$first"
        proj="$(_agents_mem_project "$pid")"
        _agents_mem_record pressure "$pid" "$name" "$label" "$proj" "$session" "$fp" "$rss" "$free" "$su"
        _agents_mem_say "Memory pressure is critical: $(_agents_mem_what "$name" "$label") in $proj holds the most, $(_agents_mem_gb "$fp")" "$pid" "$snap"
    fi
    [[ "$dry" == true ]] && return 0
    _AGENTS_MEM_STATE="$news" _AGENTS_MEM_LEVEL="$level"
    _agents_mem_state_save
}

# The guard's state, kept across its looks and restarts in the run dir:
# "level LEVEL", then one "TOKEN step last_kib ts grew" line per candidate.
_agents_mem_state_load() {
    local line
    _AGENTS_MEM_STATE="" _AGENTS_MEM_LEVEL=-
    while IFS= read -r line; do
        case "$line" in
            "level "*) _AGENTS_MEM_LEVEL="${line#level }" ;;
            *@*) _AGENTS_MEM_STATE+="$line"$'\n' ;;
        esac
    done < <(cat "$AGENTS_RUN_DIR/memguard.state" 2>/dev/null)
}
_agents_mem_state_save() {
    { mkdir -p "$AGENTS_RUN_DIR" && _agents_replace "$AGENTS_RUN_DIR/memguard.state" "level $_AGENTS_MEM_LEVEL"$'\n'"${_AGENTS_MEM_STATE%$'\n'}"; } 2>/dev/null
    return 0
}

# _agents_mem_guard_state — on PID (a guard runs), stopped (the LaunchAgent is
# installed but no guard runs), off (AGENTS_MEM_GUARD=off) or none (nothing
# runs one: Linux, or no monitoring pack).
_agents_mem_guard_state() {
    local h="" pid start
    [[ "$AGENTS_MEM_GUARD" != off ]] || { echo off; return; }
    { read -r h < "$AGENTS_RUN_DIR/memguard.lock/holder"; } 2>/dev/null
    read -r pid start _ <<<"$h"
    if [[ "$pid" =~ ^[0-9]+$ ]] && _agents_holder_check "" "" "$pid" "${start:--}"; then echo "on $pid"; return; fi
    if [[ -f "$HOME/Library/LaunchAgents/$AGENTS_MEM_LABEL.plist" ]]; then echo stopped; else echo none; fi
}

# _agents_mem_guard_loop — `agents mem guard`: a look every AGENTS_MEM_POLL
# seconds, for good (the LaunchAgent runs it, KeepAlive on failure). One
# guard at a time (memguard.lock): a second one waits a minute and fails, so
# launchd tries again later; with the guard off it exits 0 and stays down.
_agents_mem_guard_loop() {
    local lock="$AGENTS_RUN_DIR/memguard.lock" sleeper=""
    if [[ "$AGENTS_MEM_GUARD" == off ]]; then echo "agents: the memory guard is off (AGENTS_MEM_GUARD=off)"; return 0; fi
    mkdir -p "$AGENTS_RUN_DIR" 2>/dev/null
    if ! _agents_lock "$lock"; then
        echo "agents: a memory guard already runs" >&2
        sleep 60
        return 1
    fi
    trap '[[ -n "$sleeper" ]] && kill "$sleeper" 2>/dev/null; _agents_unlock "$lock"; exit 0' TERM INT HUP
    while :; do
        agents_mem_tick >/dev/null 2>&1 || true
        sleep "$AGENTS_MEM_POLL" &
        sleeper=$!
        wait "$sleeper"
        sleeper=""
    done
}

# _agents_mem_tsv_row — the menu's "memg" row:
#   memg STATE GUARD_PID WARN_KIB STOP_KIB LAST_EPOCH LAST_EVENT LAST_WHAT LAST_PROJECT LAST_FP_KIB
# STATE as _agents_mem_guard_state (on, stopped, off, none); the last
# incident from memory.tsv ("-" and 0 when there is none).
_agents_mem_tsv_row() {
    local st gpid=- line e ev pid name label proj fp
    read -r st gpid <<<"$(_agents_mem_guard_state)"
    line="$(tail -n 1 "$AGENTS_DATA_DIR/memory.tsv" 2>/dev/null)"
    IFS=$'\t' read -r e ev pid name label proj _ fp _ <<<"$line"
    [[ "$e" =~ ^[0-9]+$ ]] || { e=0 ev=- name=- label=- proj=- fp=0; }
    printf 'memg\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$st" "${gpid:--}" $((AGENTS_MEM_WARN * 1048576)) \
        "$(_agents_mem_kill_kib "$(_agents_mem_total)")" "$e" "${ev:--}" "$(_agents_mem_what "${name:--}" "${label:--}")" "${proj:--}" "${fp:-0}"
}

# _agents_mem_show — `agents mem`: the machine's memory, the guard, the
# processes holding the most (by footprint on macOS) with the session and
# project each runs in, and the last incidents.
_agents_mem_show() {
    local total free level su stot st gpid top pids="" rows line pid fp cwds e ev name label proj session rss what c n=0
    IFS=$'\t' read -r total free level su stot <<<"$(agents_mem_machine)"
    printf '%sMEMORY%s  ' "$C_B" "$C_0"
    [[ "$total" =~ ^[0-9]+$ && $total -gt 0 ]] && printf '%s total · ' "$(_agents_mem_gb "$total")"
    [[ "$free" =~ ^[0-9]+$ ]] && printf '%s%% free · ' "$free"
    case "$level" in
        critical) printf '%spressure critical%s' "$C_R$C_B" "$C_0" ;;
        warn)     printf '%spressure warn%s' "$C_Y" "$C_0" ;;
        *)        printf 'pressure %s' "${level:--}" ;;
    esac
    [[ "$su" =~ ^[0-9]+$ && "$stot" =~ ^[0-9]+$ && $stot -gt 0 ]] && printf ' · swap %s of %s' "$(_agents_mem_gb "$su")" "$(_agents_mem_gb "$stot")"
    echo
    read -r st gpid <<<"$(_agents_mem_guard_state)"
    printf '%sGUARD%s   ' "$C_B" "$C_0"
    case "$st" in
        on)      printf 'running (pid %s) · ' "$gpid" ;;
        stopped) printf '%snot running%s (agents mem restart) · ' "$C_Y" "$C_0" ;;
        off)     printf 'off (AGENTS_MEM_GUARD=off)\n' ;;
        none)    printf 'not running (run "agents mem guard" in a tmux pane) · ' ;;
    esac
    [[ "$st" == off ]] || printf '%s · warns at %s · stops agent-tree processes at %s\n' "$AGENTS_MEM_GUARD" \
        "$(_agents_mem_gb $((AGENTS_MEM_WARN * 1048576)))" "$(_agents_mem_gb "$(_agents_mem_kill_kib "$total")")"
    echo
    # The ten holding the most: top's own order on macOS, ps's RSS elsewhere.
    if [[ "$OSTYPE" == darwin* ]]; then
        top="$(_agents_mem_top -o mem -n 10 -stats pid,mem | _agents_mem_parse_top)"
    else
        top="$(LC_ALL=C ps axo pid=,rss= 2>/dev/null | sort -k2,2nr | head -n 10 | awk '{ print $1 "\t" $2 }')"
    fi
    while IFS=$'\t' read -r pid _; do [[ "$pid" =~ ^[0-9]+$ ]] && pids+="$pid "; done <<<"$top"
    rows="$(agents_snapshot | AGENTS_NAMES="$AGENTS_NAMES" _agents_awk "lib_proc memory" \
        -v self="$AGENTS_SELF" -v screen=0 -v max=400 -v pids=" $pids")"
    # shellcheck disable=SC2086  # one pid per word
    cwds="$(_agents_cwds $pids 2>/dev/null)"
    printf '%s  %-7s %9s %8s  %-38s %-18s %s%s\n' "$C_DIM" PID FOOTPRINT RSS PROCESS PROJECT SESSION "$C_0"
    # Biggest first by what is shown: the footprint, or RSS when larger.
    top="$(printf '%s\n' "$top" | _ROWS="$rows" awk -F '\t' '
        BEGIN { n = split(ENVIRON["_ROWS"], r, "\n"); for (i = 1; i <= n; i++) { split(r[i], f, "\t"); rss[f[1]] = f[3] } }
        $1 ~ /^[0-9]+$/ { v = ($1 in rss && rss[$1] > $2) ? rss[$1] : $2; print $1 "\t" v }' | sort -t "$(printf '\t')" -k2,2nr)"
    while IFS=$'\t' read -r pid fp; do
        [[ "$pid" =~ ^[0-9]+$ ]] || continue
        line="$(printf '%s\n' "$rows" | awk -F '\t' -v p="$pid" '$1 == p { print; exit }')"
        [[ -n "$line" ]] || continue
        IFS=$'\t' read -r _ _ rss _ name label root rkind <<<"$line"
        [[ $rss -gt $fp ]] && fp="$rss"
        proj="$(printf '%s\n' "$cwds" | awk -F '\t' -v p="$pid" '$1 == p { print $2; exit }')"
        if [[ "$proj" == /* ]]; then proj="$(agents_project "$proj")"; else proj=-; fi
        session=-; [[ "$root" == - ]] || session="$rkind:$root"
        what="$(_agents_mem_what "$name" "$label")"
        c=""
        [[ $fp -ge $((AGENTS_MEM_WARN * 1048576)) ]] && c="$C_R$C_B"
        printf '  %-7s %s%9s%s %8s  %-38.38s %-18.18s %s\n' "$pid" "$c" "$(_agents_mem_gb "$fp")" "$C_0" "$(_agents_mem_gb "$rss")" "$what" "$proj" "$session"
    done <<<"$top"
    [[ -s "$AGENTS_DATA_DIR/memory.tsv" ]] || return 0
    echo
    printf '%sINCIDENTS%s %s(%s)%s\n' "$C_B" "$C_0" "$C_DIM" "${AGENTS_DATA_DIR/#"$HOME"/\~}/memory.tsv" "$C_0"
    while IFS=$'\t' read -r e ev pid name label proj session fp _; do
        [[ "$e" =~ ^[0-9]+$ ]] || continue
        n=$((n + 1))
        printf '  %s  %-8s %-38.38s %-18.18s %8s  %s\n' "$(date -r "$e" '+%b %d %H:%M' 2>/dev/null || date -d "@$e" '+%b %d %H:%M' 2>/dev/null)" \
            "$ev" "$(_agents_mem_what "$name" "$label")" "$proj" "$(_agents_mem_gb "${fp:-0}")" "$session"
    done < <(tail -n 8 "$AGENTS_DATA_DIR/memory.tsv" 2>/dev/null)
}

# agents_mem [show|check [-n]|guard|log [N]|restart] — `agents mem`.
agents_mem() {
    local a
    case "${1:-show}" in
        show)   _agents_mem_show ;;
        check)  shift
                for a in "$@"; do
                    case "$a" in
                        -n|--dry-run) AGENTS_DRY_RUN=true ;;
                        *) echo "usage: agents mem check [-n]" >&2; return 2 ;;
                    esac
                done
                local out
                out="$(agents_mem_tick)" || return 1
                printf '%s\n' "${out:-nothing past the limits of the guard}" ;;
        guard)  _agents_mem_guard_loop ;;
        log)    [[ -z "${2:-}" || "$2" =~ ^[1-9][0-9]*$ ]] || { echo "usage: agents mem log [N]" >&2; return 2; }
                [[ -s "$AGENTS_DATA_DIR/memory.tsv" ]] || { echo "no memory incidents recorded"; return 0; }
                tail -n "${2:-20}" "$AGENTS_DATA_DIR/memory.tsv" ;;
        restart)
                [[ "$OSTYPE" == darwin* ]] || { echo "agents: restart is for the macOS LaunchAgent; run 'agents mem guard' in a tmux pane" >&2; return 2; }
                [[ -f "$HOME/Library/LaunchAgents/$AGENTS_MEM_LABEL.plist" ]] \
                    || { echo "agents: no LaunchAgent ($AGENTS_MEM_LABEL): ./install.sh --pack monitoring" >&2; return 1; }
                launchctl bootstrap "gui/$UID" "$HOME/Library/LaunchAgents/$AGENTS_MEM_LABEL.plist" 2>/dev/null || true
                launchctl kickstart -k "gui/$UID/$AGENTS_MEM_LABEL" ;;
        *)      echo "usage: agents mem [show|check [-n]|guard|log [N]|restart]" >&2; return 2 ;;
    esac
}
