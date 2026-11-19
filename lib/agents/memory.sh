# shellcheck shell=bash
# lib/agents/memory.sh — what holds the memory, and the guard against runaways.
#
# Owns: each process's footprint (macOS's phys_footprint, top's MEM, read
#   with footprint or top: it keeps counting the pages the compressor
#   squeezes and swap takes, while ps's RSS falls as a runaway grows), the
#   machine's memory (total, free %, pressure, swap), the
#   memory guard (`agents mem guard`: warn about, record and stop a runaway
#   in an agent tree before macOS runs out of application memory), its
#   state and its incident log, memory.tsv.
# Uses: config.sh, util.sh, palette.sh (the colors), snapshot.sh
#   (agents_snapshot, _agents_cwds), classify.sh (agents_project), system.sh
#   (_agents_parse_memfree), kill.sh (_agents_kill_unattended), events.sh
#   (_agents_data_dir), notify.sh, where.sh (agents_root_of); awk/memory.awk, awk/mem_view.awk.
# Public: agents_mem, agents_mem_tick, agents_mem_machine, _agents_mem_fp,
#   _agents_mem_tsv_row, _agents_mem_guard_state, _agents_swap_high,
#   _agents_swap_row.
#
# memory.tsv, in $AGENTS_DATA_DIR (private, names only, pruned with the
# history), one line per incident:
#   epoch event pid name label project session footprint_kib rss_kib free_pct swap_used_kib [why]
#   event:   warn (past the warning, or a doubling of it), grow (faster
#            than AGENTS_MEM_RATE), stop (the guard stopped it), escalate
#            (the same script was stopped again under the same tool command,
#            so that command was stopped: pid and name are the command's,
#            label the script's, and why says what repeated), refused (it
#            could not), pressure (memory pressure turned critical; the
#            biggest process at the time)
#   label:   the script an interpreter runs (clientFuelToday.test.js), "-"
#   session: the agent tree it ran in, as kind:pid ("-" outside one)

# The LaunchAgent the monitoring pack installs on macOS to run the guard.
AGENTS_MEM_LABEL="dev.tuidev.memguard"

# _AGENTS_MEM_PROBE_WAIT — seconds a footprint or top probe may take. Each
# takes well under a second; one that hangs (a wedged sampler under heavy
# memory pressure) is cut off, and the guard goes on with the readings it has
# (_agents_mem_fp fails with 124) instead of stalling. Two of them in a look
# are allowed for in the age at which `agents mem` calls it stalled.
_AGENTS_MEM_PROBE_WAIT=5

# _agents_mem_top ARGS... — macOS top, one sample, at most
# _AGENTS_MEM_PROBE_WAIT seconds (124 when cut off; the tests replace it).
_agents_mem_top() { _agents_timeout "$_AGENTS_MEM_PROBE_WAIT" env LC_ALL=C top -l 1 "$@" 2>/dev/null; }

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

# _agents_mem_footprint PID... — macOS footprint's totals for those pids, at
# most _AGENTS_MEM_PROBE_WAIT seconds (124 when cut off; the tests replace it).
_agents_mem_footprint() { _agents_timeout "$_AGENTS_MEM_PROBE_WAIT" env LC_ALL=C footprint --noCategories -f bytes "$@" 2>/dev/null; }

# _agents_mem_parse_footprint < footprint output — "pid<TAB>kib" for each
# process's phys_footprint (what top's MEM shows), from `footprint
# --noCategories -f bytes`: a "NAME [PID]: 64-bit  Footprint: …" header, then
# "phys_footprint: BYTES B".
_agents_mem_parse_footprint() {
    LC_ALL=C awk '
        /\]: [0-9]+-bit / { s = $0; sub(/\]: [0-9]+-bit .*/, "", s); sub(/.*\[/, "", s); p = (s ~ /^[0-9]+$/) ? s : "" }
        p != "" && $1 == "phys_footprint:" && $2 ~ /^[0-9]+$/ { printf "%d\t%d\n", p, $2 / 1024; p = "" }'
}

# _agents_mem_fp PID... — "pid<TAB>footprint_kib" for each it can read;
# nothing off macOS (RSS is the footprint there). footprint reads your own
# processes for 20 to 90 ms of CPU each; top, for the rest (other users'),
# samples every process whatever it is asked, about half a second. Fails with
# 124 when a probe was cut off: what it printed then is dropped (a cut-off
# sample could read as a tiny footprint), and the pids it did not answer for
# have no reading this look.
_agents_mem_fp() {
    [[ "$OSTYPE" == darwin* && $# -gt 0 ]] || return 0
    local a=() p got="" raw rc=0
    if raw="$(_agents_mem_footprint "$@")"; then :; elif [[ $? -eq 124 ]]; then rc=124 raw=""; fi
    [[ -z "$raw" ]] || got="$(printf '%s\n' "$raw" | _agents_mem_parse_footprint)"
    [[ -z "$got" ]] || printf '%s\n' "$got"
    for p in "$@"; do [[ $'\n'"$got" == *$'\n'"$p"$'\t'* ]] || a+=(-pid "$p"); done
    if [[ ${#a[@]} -gt 0 ]]; then
        if raw="$(_agents_mem_top -stats pid,mem "${a[@]}")"; then :; elif [[ $? -eq 124 ]]; then rc=124 raw=""; fi
        [[ -z "$raw" ]] || printf '%s\n' "$raw" | _agents_mem_parse_top
    fi
    return "$rc"
}

# _agents_mem_measured — true where a footprint is not RSS and costs a sample
# (macOS); elsewhere every look is RSS, for free. The tests replace it.
_agents_mem_measured() { [[ "$OSTYPE" == darwin* ]]; }

# _AGENTS_MEM_RECHECK — seconds before the guard samples again a candidate it
# could never stop (an app, an agent itself, another user's process) whose RSS
# has not moved.
_AGENTS_MEM_RECHECK=300

# _agents_mem_hot PID UID ROOT — true for a process the guard could stop: in
# an agent tree, below the agent, yours.
_agents_mem_hot() { [[ "$3" != - && "$3" != "$1" && "$2" == "$AGENTS_UID" ]]; }

# _agents_mem_stale RSS — true when the caller's candidate (its ts and srss
# from _agents_mem_state_get, and now) needs a new sample: never sampled, the
# last sample older than _AGENTS_MEM_RECHECK, or its RSS moved by an eighth
# (at least 512 MB) since.
_agents_mem_stale() {
    local d=$(($1 - srss)) m=$((srss / 8))
    [[ $d -ge 0 ]] || d=$((-d))
    [[ $m -ge 524288 ]] || m=524288
    [[ $ts -eq 0 || $((now - ts)) -ge $_AGENTS_MEM_RECHECK || $d -ge $m ]]
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
                *total\ =*) _agents_swap_parse "$line" && read -r su stot <<<"$REPLY" ;;
            esac
        done < <(LC_ALL=C sysctl -n kern.memorystatus_vm_pressure_level vm.swapusage 2>/dev/null)
    fi
    printf '%s\t%s\t%s\t%s\t%s\n' "${total:--}" "${free:--}" "${level:--}" "${su:--}" "${stot:--}"
}

# _agents_swap_parse LINE — REPLY: "used_kib total_kib" from vm.swapusage's
# `total = 13312.00M  used = 11800.25M  free = ...`; false when it isn't that.
_agents_swap_parse() {
    local re='total = ([0-9]+)\.?([0-9]*)([KMG])[[:space:]]+used = ([0-9]+)\.?([0-9]*)([KMG])' t
    [[ "$1" =~ $re ]] || return 1
    _agents_swap_kib "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}"; t="$REPLY"
    _agents_swap_kib "${BASH_REMATCH[4]}" "${BASH_REMATCH[5]}" "${BASH_REMATCH[6]}"
    REPLY="$REPLY $t"
}
# _agents_swap_kib WHOLE FRACTION UNIT — REPLY: that size in KiB (two decimals
# of it count: sysctl prints no more).
_agents_swap_kib() {
    local m=1024 f="${2}00"
    case "$3" in K) m=1 ;; G) m=1048576 ;; esac
    REPLY=$(( (10#$1 * 100 + 10#${f:0:2}) * m / 100 ))
}
# _agents_swap — "used_kib total_kib" of swap, nothing when unknown.
_agents_swap() {
    local k v u="" t=""
    if [[ -r /proc/meminfo ]]; then
        while read -r k v _; do
            case "$k" in SwapTotal:) t="$v" ;; SwapFree:) u="$v" ;; esac
        done < /proc/meminfo
        [[ -z "$t" || -z "$u" ]] || echo "$((t - u)) $t"
    elif _agents_swap_parse "$(LC_ALL=C sysctl -n vm.swapusage 2>/dev/null)"; then
        echo "$REPLY"
    fi
}
# _AGENTS_SWAP_HIGH — the % of swap worth a word in the summary and the menu: it
# fills up before a guard stop, and a little of it means nothing.
_AGENTS_SWAP_HIGH=80
# _agents_swap_high — true, REPLY the % and REPLY_USED, REPLY_TOTAL the KiB, when
# swap is past _AGENTS_SWAP_HIGH.
_agents_swap_high() {
    local u t
    read -r u t <<<"$(_agents_swap)"
    [[ "${t:-0}" -gt 0 ]] || return 1
    REPLY=$((u * 100 / t)) REPLY_USED="$u" REPLY_TOTAL="$t"
    [[ $REPLY -ge $_AGENTS_SWAP_HIGH ]]
}
# _agents_swap_row — agents tsv's swap row, while swap is high (a rare awk, for
# the bar): swap PCT USED_KIB TOTAL_KIB BAR.
_agents_swap_row() {
    _agents_swap_high || return 0
    local pct="$REPLY" u="$REPLY_USED" t="$REPLY_TOTAL" bar
    bar="$(_agents_awk_eval lib_fmt "BEGIN { printf \"%s\", gauge($pct, 12, -1, \"\", \"\", \"\") }")"
    printf 'swap\t%s\t%s\t%s\t%s\n' "$pct" "$u" "$t" "$bar"
}

# _agents_mem_kill_kib TOTAL_KIB — the size that gets an agent tree's process
# stopped: AGENTS_MEM_KILL GB, or half the RAM (0, the default).
_agents_mem_kill_kib() {
    if [[ "$AGENTS_MEM_KILL" -gt 0 ]]; then echo $((AGENTS_MEM_KILL * 1048576))
    elif [[ "${1:-0}" =~ ^[1-9][0-9]*$ ]]; then echo $(($1 / 2))
    else echo $((24 * 1048576)); fi
}

# _AGENTS_MEM_WARN_PCT — the warning never sits above this % of the stop
# size. With the stop at half the RAM, an 8 GB warning would be the stop
# itself on 16 GB and past it below that, so the first notice would be the
# stop. At 60 % the warning comes first everywhere, and 40 % of the stop size
# (1.6 GB on an 8 GB Mac, 3.2 GB on 16 GB) is left between them: at least
# 8 s at AGENTS_MEM_RATE, more than one poll; a lower share would warn about
# processes that are big but ordinary (2 GB on 8 GB at 50 %).
_AGENTS_MEM_WARN_PCT=60

# _agents_mem_warn_kib STOP_KIB — the guard's warning size: AGENTS_MEM_WARN GB,
# or _AGENTS_MEM_WARN_PCT % of STOP_KIB when that is smaller.
_agents_mem_warn_kib() {
    local w=$((AGENTS_MEM_WARN * 1048576)) f=$((${1:-0} * _AGENTS_MEM_WARN_PCT / 100))
    [[ $f -le 0 || $f -ge $w ]] || w="$f"
    echo "$w"
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

# _agents_mem_state_get TOKEN — set the caller's step, last, ts, grew and srss
# from the guard's state (_AGENTS_MEM_STATE: "TOKEN step last_kib ts grew
# srss_kib" lines; last and ts are the last sample's footprint and time, srss
# the RSS then; 0 for anything unknown).
_agents_mem_state_get() {
    local t s l w g r
    step=0 last=0 ts=0 grew=0 srss=0
    while read -r t s l w g r; do
        [[ "$t" == "$1" ]] || continue
        step="$s" last="$l" ts="$w" grew="$g"
        [[ "$r" =~ ^[0-9]+$ ]] && srss="$r"
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
# mem check` runs one and prints what it decided). One ps; a footprint sample
# (_agents_mem_fp) only for the few processes past half the warning (or the
# largest few while memory pressure is up), never for the rest, and of those
# only: each one the guard could stop, every look; any other once, then again
# when its RSS moves (_agents_mem_stale) or after _AGENTS_MEM_RECHECK seconds;
# all of them while memory pressure is warn or critical, or free memory falls
# faster than AGENTS_MEM_RATE. One not sampled keeps its last footprint (or
# its RSS, when larger). Per process, by footprint (or RSS when larger): in
# an agent tree, below its agent, yours, past the stop size (or the largest
# such past the warning while pressure is critical), it is stopped, tree and
# all, the usual way (SIGTERM, then SIGKILL after
# AGENTS_GRACE); past the warning, or a doubling of it, a warning; growing
# faster than AGENTS_MEM_RATE MB/s, one warning. An agent itself is never
# stopped, only warned about. Each is recorded (memory.tsv, a stop in
# events.tsv too) and notified, a click going to its session. A pressure
# level turning critical is recorded with the biggest process. With
# AGENTS_DRY_RUN=true it only says what it would stop.
agents_mem_tick() {
    local total free level su stot warn stopkib screen floor snap cands fps="" now
    local pid start rss uid name label root rkind fp f v tok step last ts grew srss rate news="" prev="" first=""
    local what proj session msg stopped="" dry="${AGENTS_DRY_RUN:-false}" meas=0 busy=0 want=" " pf pts seen
    local fall=0 hot=0 late=0 tool tstart tname esc gone=" " why
    [[ "$AGENTS_MEM_GUARD" != off ]] || { echo "the memory guard is off (AGENTS_MEM_GUARD=off)"; return 0; }
    _agents_now now
    IFS=$'\t' read -r total free level su stot <<<"$(agents_mem_machine)"
    [[ "$total" =~ ^[0-9]+$ ]] || total=0
    stopkib="$(_agents_mem_kill_kib "$total")"; warn="$(_agents_mem_warn_kib "$stopkib")"
    screen=$((warn / 2)); floor=0
    [[ "$level" == warn || "$level" == critical ]] && floor=524288
    snap="$(agents_snapshot)"
    cands="$(printf '%s\n' "$snap" | AGENTS_NAMES="$AGENTS_NAMES" \
        _agents_awk "lib_proc memory" -v self="$AGENTS_SELF" -v screen="$screen" -v floor="$floor" -v max=8)"
    [[ -n "${_AGENTS_MEM_STATE+set}" ]] || _agents_mem_state_load
    prev="${_AGENTS_MEM_LEVEL:--}"
    # How fast free memory fell since the last look, in KiB/s.
    read -r pf pts _ <<<"${_AGENTS_MEM_FREE:-}"
    if [[ "$free" =~ ^[0-9]+$ && "$pf" =~ ^[0-9]+$ && "$pts" =~ ^[0-9]+$ && $now -gt $pts && $pf -gt $free ]]; then
        fall=$(((pf - free) * total / 100 / (now - pts)))
    fi
    # Which candidates get a footprint sample this look (want: " PID PID ").
    if [[ -n "$cands" ]] && _agents_mem_measured; then
        meas=1
        [[ "$level" == warn || "$level" == critical ]] && busy=1
        [[ $fall -ge $((AGENTS_MEM_RATE * 1024)) ]] && busy=1
        while IFS=$'\t' read -r pid start rss uid _ _ root _; do
            [[ "$pid" =~ ^[0-9]+$ ]] || continue
            _agents_mem_state_get "$pid@$start"
            if [[ $busy == 1 ]] || _agents_mem_hot "$pid" "$uid" "$root" || _agents_mem_stale "$rss"; then want+="$pid "; fi
        done <<<"$cands"
        # A probe cut off (124) is no reading for the pids it did not answer
        # for: never a footprint of zero, never a reason to stop anything.
        # shellcheck disable=SC2086  # one pid per word
        if [[ "$want" != " " ]] && ! fps="$(_agents_mem_fp $want)"; then late=1; fi
    fi
    while IFS=$'\t' read -r pid start rss uid name label root rkind tool tstart tname; do
        [[ "$pid" =~ ^[0-9]+$ ]] || continue
        # Its tool command was stopped this look, with it in its tree.
        [[ "$gone" != *" ${tool:--} "* ]] || continue
        tok="$pid@$start"; what="$(_agents_mem_what "$name" "$label")"
        session=-; [[ "$root" == - ]] || session="$rkind:$root"
        _agents_mem_state_get "$tok"
        fp="$rss"
        if [[ $meas == 0 ]] || { [[ "$want" == *" $pid "* ]] && { [[ $late == 0 ]] || [[ $'\n'"$fps" == *$'\n'"$pid"$'\t'* ]]; }; }; then
            while IFS=$'\t' read -r f v; do [[ "$f" == "$pid" && "$v" -gt "$fp" ]] && fp="$v"; done <<<"$fps"
            seen="$fp $now" srss="$rss"
        else
            # Not sampled: its last footprint stands (RSS falls while a
            # footprint grows), and so does the last sample, for the growth rate.
            [[ "$last" -gt "$fp" ]] && fp="$last"
            seen="$last $ts"
        fi
        [[ $fp -lt $screen ]] || hot=1
        # The biggest one, for a pressure incident.
        [[ -n "$first" ]] || first="$pid"$'\t'"$name"$'\t'"$label"$'\t'"$session"$'\t'"$fp"$'\t'"$rss"
        if [[ "$AGENTS_MEM_GUARD" == kill ]] && _agents_mem_hot "$pid" "$uid" "$root" \
            && { [[ $fp -ge $stopkib ]] || { [[ "$level" == critical && $fp -ge $warn && -z "${stopped:-}" ]]; }; }; then
            proj="$(_agents_mem_project "$pid")"
            if [[ $fp -ge $stopkib ]]; then msg="past the $(_agents_mem_gb "$stopkib") limit"; else msg="while memory pressure is critical"; fi
            # Stopped before under the same tool command: its runner started
            # it again, so the runner goes (the command the agent started,
            # never the agent: memory.awk's TOOL is below it).
            esc=""
            if [[ "$tool" =~ ^[0-9]+$ && "$tool" != "$pid" && "$tool" != "$root" ]] \
                && _agents_mem_respawned "$tool@$tstart" "$what" "$now"; then
                esc="$REPLY"
                why="$what stopped again $((now - ${esc%% *}))s after the guard stopped pid ${esc#* } under the same command"
            fi
            if [[ "$dry" == true ]]; then
                if [[ -n "$esc" ]]; then echo "would stop $tname (pid $tool), the command running $what in $proj ($session): $why"
                else echo "would stop $what in $proj ($session): $(_agents_mem_gb "$fp") $msg"; fi
                continue
            fi
            if [[ -n "$esc" ]] && _AGENTS_EV_KIND=guard _AGENTS_EV_REASONS="$tool"$'\t'memory$'\t'"$session" \
                _agents_kill_unattended "$tool@$tstart" >/dev/null 2>&1; then
                _agents_mem_record escalate "$tool" "$tname" "$label" "$proj" "$session" "$fp" "$rss" "$free" "$su" "$why"
                _agents_mem_say "Stopped $tname in $proj, the command that keeps starting $what: it held $(_agents_mem_gb "$fp") $msg again $((now - ${esc%% *}))s after the last stop ($session)" "$pid" "$snap"
                stopped=1 gone+="$tool "
                continue
            fi
            # Refused for the command (it hosts a session, say), or the first
            # time: PID's own tree, as ever.
            if _AGENTS_EV_KIND=guard _AGENTS_EV_REASONS="$pid"$'\t'memory$'\t'"$session" _agents_kill_unattended "$tok" >/dev/null 2>&1; then
                _agents_mem_record stop "$pid" "$name" "$label" "$proj" "$session" "$fp" "$rss" "$free" "$su"
                _agents_mem_say "Stopped $what in $proj: it held $(_agents_mem_gb "$fp") $msg ($session)" "$pid" "$snap"
                stopped=1
                [[ ! "$tool" =~ ^[0-9]+$ ]] || _AGENTS_MEM_STOPS+="$now"$'\t'"$tool@$tstart"$'\t'"$what"$'\t'"$pid"$'\n'
            else
                _agents_mem_record refused "$pid" "$name" "$label" "$proj" "$session" "$fp" "$rss" "$free" "$su"
                _agents_mem_say "Could not stop $what in $proj ($(_agents_mem_gb "$fp")): agents kill $tok" "$pid" "$snap"
                news+="$tok $step $seen $grew $srss"$'\n'
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
        news+="$tok $step $seen $grew $srss"$'\n'
    done <<<"${cands:-}"
    if [[ "$level" == critical && "$prev" != critical && -n "$first" && "$dry" != true ]]; then
        IFS=$'\t' read -r pid name label session fp rss <<<"$first"
        proj="$(_agents_mem_project "$pid")"
        _agents_mem_record pressure "$pid" "$name" "$label" "$proj" "$session" "$fp" "$rss" "$free" "$su"
        _agents_mem_say "Memory pressure is critical: $(_agents_mem_what "$name" "$label") in $proj holds the most, $(_agents_mem_gb "$fp")" "$pid" "$snap"
    fi
    _agents_mem_next "$level" "$fall" "$hot" "$stopkib" "$screen" "$cands" "$snap"
    [[ "$dry" == true ]] && return 0
    _AGENTS_MEM_STATE="$news" _AGENTS_MEM_LEVEL="$level" _AGENTS_MEM_FREE="$free $now"
    _agents_mem_state_save
}

# _agents_mem_next LEVEL FALL_KIBS HOT STOP_KIB SCREEN_KIB CANDS SNAP — when
# the guard looks next, in _AGENTS_MEM_NEXT (seconds): we want it running when
# it is needed, not all the time. AGENTS_MEM_POLL while anything needs
# watching (a candidate at or past the screening size, memory pressure warn
# or critical, free memory falling at half AGENTS_MEM_RATE or faster);
# otherwise AGENTS_MEM_IDLE; and a minute (never less than the idle one) when
# no agent session runs at all, since nothing is then stoppable, within the
# same safety bound.
#
# Safety bound: the idle interval is clamped to the time a runaway growing at
# four times AGENTS_MEM_RATE needs to get from the screening size to the stop
# size, the distance the guard must still see it cross. A runaway that starts
# just after a look is then seen at the screening size on the next one, and
# from then on the guard looks every AGENTS_MEM_POLL, before the stop size,
# whatever AGENTS_MEM_IDLE says. The bound is never below AGENTS_MEM_POLL:
# that is the guard's best.
_agents_mem_next() {
    local level="$1" fall="$2" hot="$3" stopkib="$4" screen="$5" cands="$6" snap="$7" idle bound=""
    _AGENTS_MEM_NEXT="$AGENTS_MEM_POLL"
    [[ "$level" != warn && "$level" != critical && $hot == 0 && -z "$cands" ]] || return 0
    [[ $fall -lt $((AGENTS_MEM_RATE * 512)) ]] || return 0
    idle="$AGENTS_MEM_IDLE"
    [[ $idle -ge $AGENTS_MEM_POLL ]] || idle="$AGENTS_MEM_POLL"
    if [[ $stopkib -gt $screen ]]; then
        bound=$(((stopkib - screen) / (AGENTS_MEM_RATE * 4096)))
        [[ $bound -ge $AGENTS_MEM_POLL ]] || bound="$AGENTS_MEM_POLL"
        [[ $idle -le $bound ]] || idle="$bound"
    fi
    _AGENTS_MEM_NEXT="$idle"
    if ! printf '%s\n' "$snap" | AGENTS_NAMES="$AGENTS_NAMES" _agents_awk "lib_proc memory" -v probe=1 | grep -q 1; then
        [[ $idle -ge 60 ]] || idle=60
        [[ -z "$bound" || $idle -le $bound ]] || idle="$bound"
        _AGENTS_MEM_NEXT="$idle"
    fi
    return 0
}

# _AGENTS_MEM_RESPAWN — seconds after a stop in which the same script
# stopped again under the same tool command (pid and start) means its runner
# started it again (a test runner respawns a crashed worker within seconds),
# so the guard stops that command instead. Two minutes covers a respawned
# worker regrowing to the stop size of a 48 GB Mac (24 GB) at about the
# 200 MB/s of AGENTS_MEM_RATE; an agent running the command again starts a
# new one (another pid), which is never matched, however soon.
_AGENTS_MEM_RESPAWN=120

# _agents_mem_respawned TOOL_TOKEN WHAT NOW — true, REPLY "EPOCH PID" (the
# earlier stop), when the guard stopped WHAT under TOOL_TOKEN within
# _AGENTS_MEM_RESPAWN seconds of NOW (_AGENTS_MEM_STOPS: "epoch<TAB>tool
# token<TAB>what<TAB>pid" lines, the latest last).
_agents_mem_respawned() {
    local e t w p hit=""
    while IFS=$'\t' read -r e t w p; do
        [[ "$e" =~ ^[0-9]+$ && "$t" == "$1" && "$w" == "$2" ]] || continue
        [[ $e -lt $3 && $(($3 - e)) -le $_AGENTS_MEM_RESPAWN ]] && hit="$e $p"
    done <<<"${_AGENTS_MEM_STOPS:-}"
    [[ -n "$hit" ]] && REPLY="$hit"
}

# The guard's state, kept across its looks and restarts in the run dir:
# "level LEVEL", "free FREE_PCT EPOCH" (the last look's), one "stop<TAB>EPOCH
# <TAB>TOOL_TOKEN<TAB>WHAT<TAB>PID" line per stop of the last
# _AGENTS_MEM_RESPAWN seconds, then one "TOKEN step last_kib ts grew srss_kib"
# line per candidate.
_agents_mem_state_load() {
    local line
    _AGENTS_MEM_STATE="" _AGENTS_MEM_LEVEL=- _AGENTS_MEM_FREE="" _AGENTS_MEM_STOPS=""
    while IFS= read -r line; do
        case "$line" in
            "level "*) _AGENTS_MEM_LEVEL="${line#level }" ;;
            "free "*) _AGENTS_MEM_FREE="${line#free }" ;;
            stop$'\t'*) _AGENTS_MEM_STOPS+="${line#stop$'\t'}"$'\n' ;;
            *@*) _AGENTS_MEM_STATE+="$line"$'\n' ;;
        esac
    done < <(cat "$AGENTS_RUN_DIR/memguard.state" 2>/dev/null)
}
_agents_mem_state_save() {
    local line e now keep="" out=""
    _agents_now now
    # Only the stops still inside the window, in the file and in the loop's memory.
    while IFS= read -r line; do
        e="${line%%$'\t'*}"
        [[ "$e" =~ ^[0-9]+$ && $((now - e)) -le $_AGENTS_MEM_RESPAWN ]] || continue
        keep+="$line"$'\n' out+="stop"$'\t'"$line"$'\n'
    done <<<"${_AGENTS_MEM_STOPS:-}"
    _AGENTS_MEM_STOPS="$keep"
    { mkdir -p "$AGENTS_RUN_DIR" && _agents_replace "$AGENTS_RUN_DIR/memguard.state" \
        "level $_AGENTS_MEM_LEVEL"$'\n'"free ${_AGENTS_MEM_FREE:--}"$'\n'"$out${_AGENTS_MEM_STATE%$'\n'}"; } 2>/dev/null
    return 0
}

# _agents_mem_beat — the guard's heartbeat, memguard.beat: "EPOCH NEXT_SECS",
# written by its loop at the start and after every look, so `agents mem` can
# tell a guard that looks from one stuck in a look while its pid lives on.
_agents_mem_beat() {
    local now
    _agents_now now
    { mkdir -p "$AGENTS_RUN_DIR" && _agents_replace "$AGENTS_RUN_DIR/memguard.beat" "$now ${_AGENTS_MEM_NEXT:-$AGENTS_MEM_POLL}"; } 2>/dev/null
    return 0
}

# _agents_mem_ps_ok — true when this shell can read the process table (ps
# shows pid 1); false inside a sandbox that hides other processes or forbids
# ps (the tests replace it).
_agents_mem_ps_ok() { [[ -n "$(LC_ALL=C ps -o pid= -p 1 2>/dev/null)" ]]; }

# _agents_mem_guard_state — "on PID" (a guard runs and looks), "stalled PID
# AGE" (its pid lives, but its heartbeat is AGE seconds old: more than three
# of its polls), unknown (the process table can't be read: inside a
# sandbox), stopped (the LaunchAgent is installed but no guard runs), off
# (AGENTS_MEM_GUARD=off) or none (nothing runs one: Linux, or no monitoring
# pack).
_agents_mem_guard_state() {
    local h="" pid start b="" at next now rc=1
    [[ "$AGENTS_MEM_GUARD" != off ]] || { echo off; return; }
    { read -r h < "$AGENTS_RUN_DIR/memguard.lock/holder"; } 2>/dev/null
    read -r pid start _ <<<"$h"
    if [[ "$pid" =~ ^[0-9]+$ ]]; then _agents_holder_check "" "" "$pid" "${start:--}"; rc=$?; fi
    if [[ $rc -eq 0 ]]; then
        # No heartbeat is a guard from before it had one: on.
        { read -r b < "$AGENTS_RUN_DIR/memguard.beat"; } 2>/dev/null
        read -r at next _ <<<"$b"
        [[ "$next" =~ ^[0-9]+$ && $next -ge $AGENTS_MEM_POLL ]] || next="$AGENTS_MEM_POLL"
        _agents_now now
        if [[ "$at" =~ ^[0-9]+$ && $((now - at)) -gt $((3 * next + 2 * _AGENTS_MEM_PROBE_WAIT + ${AGENTS_GRACE:-3})) ]]; then echo "stalled $pid $((now - at))"; else echo "on $pid"; fi
        return
    fi
    # The holder lives but ps can't say whose it is, or ps reads nothing.
    if [[ $rc -eq 2 ]] || ! _agents_mem_ps_ok; then echo unknown; return; fi
    if [[ -f "$(_agents_mem_unit)" ]]; then echo stopped; else echo none; fi
}

# The file that runs the guard at login: the LaunchAgent on macOS, the systemd
# user service on Linux.
_agents_mem_unit() {
    if [[ "$OSTYPE" == darwin* ]]; then echo "$HOME/Library/LaunchAgents/$AGENTS_MEM_LABEL.plist"
    else echo "${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/tuidev-memguard.service"; fi
}

# _agents_mem_guard_loop — `agents mem guard`: a look every AGENTS_MEM_POLL
# seconds while something needs watching, every AGENTS_MEM_IDLE (a minute with
# no agent session) otherwise (_agents_mem_next), for good (the LaunchAgent
# runs it, KeepAlive on failure), a heartbeat after each (_agents_mem_beat). One
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
    _agents_mem_beat
    while :; do
        agents_mem_tick >/dev/null 2>&1 || true
        _agents_mem_beat
        sleep "${_AGENTS_MEM_NEXT:-$AGENTS_MEM_POLL}" &
        sleeper=$!
        wait "$sleeper"
        sleeper=""
    done
}

# _agents_mem_tsv_row — the menu's "memg" row:
#   memg STATE GUARD_PID WARN_KIB STOP_KIB LAST_EPOCH LAST_EVENT LAST_WHAT LAST_PROJECT LAST_FP_KIB
# STATE as _agents_mem_guard_state (on, stalled, unknown, stopped, off,
# none); WARN_KIB the guard's warning (_agents_mem_warn_kib); the last
# incident from memory.tsv ("-" and 0 when there is none).
_agents_mem_tsv_row() {
    local st gpid=- line e ev pid name label proj fp stop
    read -r st gpid _ <<<"$(_agents_mem_guard_state)"
    line="$(tail -n 1 "$AGENTS_DATA_DIR/memory.tsv" 2>/dev/null)"
    IFS=$'\t' read -r e ev pid name label proj _ fp _ <<<"$line"
    [[ "$e" =~ ^[0-9]+$ ]] || { e=0 ev=- name=- label=- proj=- fp=0; }
    stop="$(_agents_mem_kill_kib "$(_agents_mem_total)")"
    printf 'memg\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$st" "${gpid:--}" "$(_agents_mem_warn_kib "$stop")" \
        "$stop" "$e" "${ev:--}" "$(_agents_mem_what "${name:--}" "${label:--}")" "${proj:--}" "${fp:-0}"
}

# _agents_mem_show — `agents mem`: the machine's memory and swap as bars, the
# guard, the processes holding the most (by footprint on macOS) on a bar to the
# guard's stop size, with the session and project each runs in, and the last
# incidents (an escalation with why under it). The bars are awk/mem_view.awk's.
_agents_mem_show() {
    local total free level su stot st gpid gage top pids="" rows line pid fp cwds e ev name label proj session rss what n=0 stops="0 0" list=""
    local stop note late=0
    IFS=$'\t' read -r total free level su stot <<<"$(agents_mem_machine)"
    read -r st gpid gage <<<"$(_agents_mem_guard_state)"
    stop="$(_agents_mem_kill_kib "$total")"
    # The ten holding the most: top's own order on macOS, ps's RSS elsewhere.
    if [[ "$OSTYPE" == darwin* ]]; then
        if top="$(_agents_mem_top -o mem -n 10 -stats pid,mem)"; then top="$(printf '%s\n' "$top" | _agents_mem_parse_top)"
        else [[ $? -ne 124 ]] || late=1; top=""; fi
    else
        top="$(LC_ALL=C ps axo pid=,rss= 2>/dev/null | sort -k2,2nr | head -n 10 | awk '{ print $1 "\t" $2 }')"
    fi
    while IFS=$'\t' read -r pid _; do [[ "$pid" =~ ^[0-9]+$ ]] && pids+="$pid "; done <<<"$top"
    rows="$(agents_snapshot | AGENTS_NAMES="$AGENTS_NAMES" _agents_awk "lib_proc memory" \
        -v self="$AGENTS_SELF" -v screen=0 -v max=400 -v pids=" $pids")"
    # shellcheck disable=SC2086  # one pid per word
    cwds="$(_agents_cwds $pids 2>/dev/null)"
    # Biggest first by what is shown: the footprint, or RSS when larger.
    top="$(printf '%s\n' "$top" | _ROWS="$rows" awk -F '\t' '
        BEGIN { n = split(ENVIRON["_ROWS"], r, "\n"); for (i = 1; i <= n; i++) { split(r[i], f, "\t"); rss[f[1]] = f[3] } }
        $1 ~ /^[0-9]+$/ { v = ($1 in rss && rss[$1] > $2) ? rss[$1] : $2; print $1 "\t" v }' | sort -t "$(printf '\t')" -k2,2nr)"
    while IFS=$'\t' read -r pid fp; do
        [[ "$pid" =~ ^[0-9]+$ ]] || continue
        line="$(awk -F '\t' -v p="$pid" '$1 == p { print; exit }' <<< "$rows")"
        [[ -n "$line" ]] || continue
        IFS=$'\t' read -r _ _ rss _ name label root rkind _ <<<"$line"
        [[ $rss -gt $fp ]] && fp="$rss"
        proj="$(awk -F '\t' -v p="$pid" '$1 == p { print $2; exit }' <<< "$cwds")"
        if [[ "$proj" == /* ]]; then proj="$(agents_project "$proj")"; else proj=-; fi
        session=-; [[ "$root" == - ]] || session="$rkind:$root"
        what="$(_agents_mem_what "$name" "$label")"
        list+="$pid"$'\t'"$fp"$'\t'"$rss"$'\t'"$what"$'\t'"$proj"$'\t'"$session"$'\n'
    done <<<"$top"
    [[ ! -s "$AGENTS_DATA_DIR/memory.tsv" ]] || stops="$(_agents_mem_stops)"
    printf '%s' "$list" | W="${AGENTS_WIDTH:-120}" _agents_awk_colored "lib_fmt mem_view" -F '\t' \
        -v total="${total:--}" -v free="${free:--}" -v level="${level:--}" -v su="${su:--}" -v stot="${stot:--}" \
        -v gstate="$st" -v gpid="${gpid:--}" -v gage="${gage:-0}" -v gmode="$AGENTS_MEM_GUARD" -v stops="${stops% *}" -v escal="${stops#* }" \
        -v warn="$(_agents_mem_warn_kib "$stop")" -v stop="$stop" -v high="$_AGENTS_SWAP_HIGH" -v late="$late" -v wait="$_AGENTS_MEM_PROBE_WAIT"
    [[ -s "$AGENTS_DATA_DIR/memory.tsv" ]] || return 0
    echo
    printf '%sINCIDENTS%s %s(%s; agents mem log)%s\n' "$C_B" "$C_0" "$C_DIM" "${AGENTS_DATA_DIR/#"$HOME"/\~}/memory.tsv" "$C_0"
    while IFS=$'\t' read -r e ev pid name label proj session fp _ _ _ note; do
        [[ "$e" =~ ^[0-9]+$ ]] || continue
        n=$((n + 1))
        printf '  %s  %-8s %-38.38s %-18.18s %8s  %s\n' "$(date -r "$e" '+%b %d %H:%M' 2>/dev/null || date -d "@$e" '+%b %d %H:%M' 2>/dev/null)" \
            "$ev" "$(_agents_mem_what "$name" "$label")" "$proj" "$(_agents_mem_gb "${fp:-0}")" "$session"
        [[ "$ev" != escalate || -z "$note" || "$note" == - ]] || printf '  %s%14s %s%s\n' "$C_DIM" "" "$note" "$C_0"
    done < <(tail -n 8 "$AGENTS_DATA_DIR/memory.tsv" 2>/dev/null)
}

# _agents_mem_stops — "STOPS ESCALATIONS": how many runaways the guard stopped
# in the last 7 days (an escalation, which stopped the command that kept
# starting one, counts as a stop), and how many of those were escalations.
_agents_mem_stops() {
    local now
    _agents_now now
    LC_ALL=C awk -F '\t' -v cut=$((now - 7 * 86400)) '
        ($2 == "stop" || $2 == "escalate") && $1 + 0 >= cut { n++; if ($2 == "escalate") x++ }
        END { print n + 0, x + 0 }' "$AGENTS_DATA_DIR/memory.tsv"
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
                [[ -f "$(_agents_mem_unit)" ]] \
                    || { echo "agents: the memory guard is not installed: tuidev install --pack monitoring" >&2; return 1; }
                if [[ "$OSTYPE" != darwin* ]]; then
                    systemctl --user restart tuidev-memguard.service \
                        || { echo "agents: systemd did not restart it; run 'agents mem guard' in a tmux pane" >&2; return 1; }
                    return 0
                fi
                launchctl bootstrap "gui/$UID" "$HOME/Library/LaunchAgents/$AGENTS_MEM_LABEL.plist" 2>/dev/null || true
                launchctl kickstart -k "gui/$UID/$AGENTS_MEM_LABEL" ;;
        *)      echo "usage: agents mem [show|check [-n]|guard|log [N]|restart]" >&2; return 2 ;;
    esac
}
