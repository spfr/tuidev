#!/bin/bash
# <xbar.title>agents</xbar.title>
# <xbar.version>v1.5</xbar.version>
# <xbar.desc>Who needs you: sessions by state (needs you, to review, running, parked), limits with their pace, what the day went to, stale helpers and hogs when there are any, keep-awake, fans and a compact system view, from tuidev's `agents` command.</xbar.desc>
# <xbar.dependencies>bash,agents</xbar.dependencies>
# <swiftbar.hideAbout>true</swiftbar.hideAbout>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
#
# SwiftBar plugin. Installed by `./install.sh --pack monitoring` (macOS); the
# refresh interval is the `10s` in the file name (AGENTS_BAR_REFRESH in
# ~/.config/agents.conf, applied by the pack). Everything shown comes from one
# `agents tsv` call, every action runs `agents` (see `agents --help`), and the
# title and sections follow the AGENTS_BAR_* settings in that file. Windows
# open in your terminal via `agents open-term` (AGENTS_TERMINAL), never
# through SwiftBar's terminal=true, which always picks Terminal.app.
#
# It parses `agents tsv` row by row and ignores a row it doesn't know: during an
# update the plugin and `agents` can be a version apart, so whatever an older
# `agents` doesn't send (triage, pace, palette, swap, waitsum) has a fallback.

export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:${PATH:-/usr/bin:/bin:/usr/sbin:/sbin}"
# A refresh runs every few seconds, so the plugin forks as little as it can:
# one `agents tsv`, one awk for the jobs, and a clock read for keep-awake.
# Everything else is bash builtins (helpers set REPLY instead of printing).
if [[ -n "${SWIFTBAR_PLUGIN_PATH:-}" ]]; then SELF="$SWIFTBAR_PLUGIN_PATH"
else
    case "$0" in */*) SELF="${0%/*}" ;; *) SELF=. ;; esac
    SELF="$(cd "$SELF" && pwd)/${0##*/}"
fi

# Menu actions that are not `agents` subcommands call the plugin back, with
# fixed words only (and a numeric pid for copy).
case "${1:-}" in
    copy)
        [[ "${2:-}" =~ ^[0-9]+$ ]] && printf '%s' "$2" | pbcopy
        exit 0 ;;
    battery-settings)   # System Settings › Battery (Energy Mode lives there)
        open "x-apple.systempreferences:com.apple.Battery-Settings.extension" 2>/dev/null \
            || open -b com.apple.systempreferences
        exit 0 ;;
    activity-monitor)
        open -a "Activity Monitor"
        exit 0 ;;
esac

# AGENTS_BIN picks a specific agents (a checkout, while developing).
AGENTS="${AGENTS_BIN:-}"
if [[ -z "$AGENTS" ]]; then
    IFS=: read -r -a _path <<<"$PATH"
    for _d in ${_path[@]+"${_path[@]}"}; do
        [[ -n "$_d" && -f "$_d/agents" && -x "$_d/agents" ]] && { AGENTS="$_d/agents"; break; }
    done
    unset _path _d
fi
if [[ -z "$AGENTS" ]]; then
    echo ":exclamationmark.triangle: | sfcolor=#FF9F0A"
    echo "---"
    echo "The agents command is not on PATH | color=red"
    echo "Reinstall it: ./install.sh --pack monitoring"
    echo "Or remove this plugin: $SELF | symbolize=false"
    exit 0
fi

if ! data="$("$AGENTS" tsv 2>/dev/null)"; then
    err="$("$AGENTS" tsv 2>&1 >/dev/null | head -1)"
    echo ":exclamationmark.triangle: | sfcolor=#FF9F0A"
    echo "---"
    echo "agents tsv failed: ${err//|//} | symbolize=false color=red"
    echo "Refresh | refresh=true"
    exit 0
fi

# The tints: Apple's system hues for the menu's appearance, until `agents tsv`'s
# palette row says otherwise (use_palette).
if [[ "${OS_APPEARANCE:-Dark}" == Light ]]; then HUE_NEED="#FF3B30" HUE_DONE="#007AFF" HUE_RUN="#34C759" HUE_WARN="#FF9500"
else HUE_NEED="#FF453A" HUE_DONE="#0A84FF" HUE_RUN="#30D158" HUE_WARN="#FF9F0A"; fi
HUE_IDLE="#8E8E93"
# A title symbol with no tint of its own, once another has one (title_params).
HUE_PLAIN="#1D1D1F,#F2F2F5"
# sfconfig HEX — REPLY: the item param that tints its sfimage. Menu-item symbols
# take their color only from sfconfig (base64 JSON, Palette mode); sfcolor colors
# inline :symbols: in titles, not an item's sfimage. The JSON is
# {"renderingMode":"Palette","colors":["#RRGGBB"]}, whose base64 only differs in
# the six digits, which fall on a 3-byte boundary: those are encoded here, in
# bash, since this runs on every refresh.
B64=ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/
sfconfig() {
    local h="${1#\#}" o="" i a b c
    for i in 0 3; do
        printf -v a '%d' "'${h:$i:1}"; printf -v b '%d' "'${h:$((i + 1)):1}"; printf -v c '%d' "'${h:$((i + 2)):1}"
        o+="${B64:$((a >> 2)):1}${B64:$(( ((a & 3) << 4) | (b >> 4) )):1}${B64:$(( ((b & 15) << 2) | (c >> 6) )):1}${B64:$((c & 63)):1}"
    done
    REPLY="sfconfig=eyJyZW5kZXJpbmdNb2RlIjoiUGFsZXR0ZSIsImNvbG9ycyI6WyIj${o}Il19"
}
set_tints() {
    sfconfig "$HUE_NEED"; TINT_NEED="$REPLY"
    sfconfig "$HUE_DONE"; TINT_DONE="$REPLY"
    sfconfig "$HUE_RUN";  TINT_RUN="$REPLY"
    sfconfig "$HUE_WARN"; TINT_WARN="$REPLY"
    sfconfig "$HUE_IDLE"; TINT_IDLE="$REPLY"
}
set_tints
# use_palette NEED DONE RUN WARN BG — the theme's colors on the symbols, when it
# suits this menu: a dark palette's pastels wash out on a light menu, which then
# keeps the system's. Text stays the system's either way: SwiftBar colors symbols.
use_palette() {
    local dark=1 h
    if [[ "$5" =~ ^#[0-9a-fA-F]{6}$ ]]; then
        h="${5#\#}"
        [[ $(( (16#${h:0:2} * 299 + 16#${h:2:2} * 587 + 16#${h:4:2} * 114) / 1000 )) -lt 128 ]] || dark=""
        if [[ "${OS_APPEARANCE:-Dark}" == Light ]]; then [[ -z "$dark" ]] || return 0
        elif [[ -z "$dark" ]]; then return 0; fi
    fi
    [[ ! "$1" =~ ^#[0-9a-fA-F]{6}$ ]] || HUE_NEED="$1"
    [[ ! "$2" =~ ^#[0-9a-fA-F]{6}$ ]] || HUE_DONE="$2"
    [[ ! "$3" =~ ^#[0-9a-fA-F]{6}$ ]] || HUE_RUN="$3"
    [[ ! "$4" =~ ^#[0-9a-fA-F]{6}$ ]] || HUE_WARN="$4"
    set_tints
}
# Text keeps the system label color (no color=, which would also not adapt to
# light, dark and translucent menus). A row SwiftBar sees without an action
# (bash, href, refresh) renders disabled, i.e. secondary; primary rows get a
# harmless action (ROW, or something useful), and info lines stay secondary.
ROW="refresh=true"

# --- Formatting ------------------------------------------------------------------

# Menu text must not contain "|" (SwiftBar's separator; shown as ¦) or start
# with "-" (a "--" prefix would turn a process name into a submenu or a
# separator). cl TEXT sets REPLY to it made safe, and $HOME shortened to ~.
cl() { local s="${1//|/¦}" t='~'; s="${s#"${s%%[!-[:space:]]*}"}"; REPLY="${s/#"$HOME"/$t}"; }
# sh60 TEXT — cl, then at most 60 characters.
sh60() { cl "$1"; [[ ${#REPLY} -le 60 ]] || REPLY="${REPLY:0:57}..."; }
# Params carry only fixed words, PID@START tokens and the two trusted paths
# below (agents and this plugin), double-quoted. Nothing a process controls (a
# cwd, a name, Herdr's text) ever goes into a param: SwiftBar unescapes
# backslashes there, and a later key overrides an earlier one. Paths are
# resolved by `agents cwd|copy-path|reveal PID@START` when you click.
# tok PID START — REPLY = the action token PID@START; false (and REPLY empty)
# if either part looks odd.
tok() { REPLY=""; [[ "$1" =~ ^[0-9]+$ && "$2" =~ ^[A-Za-z0-9_:]+$ ]] && REPLY="$1@$2"; }
# memv KIB, agev SECS, longv SECS, cores PCPU — a size, an age, a long stretch
# (39 h) and a CPU share (8.4 cores) for people, in REPLY.
memv() { if [[ $1 -ge 1048576 ]]; then REPLY="$(($1 * 10 / 1048576 / 10)).$(($1 * 10 / 1048576 % 10))G"; else REPLY="$(($1 / 1024))M"; fi; }
agev() {
    local s="$1"
    if [[ $s -lt 3600 ]]; then REPLY="$((s / 60))m"
    elif [[ $s -lt 86400 ]]; then REPLY="$((s / 3600))h$(((s % 3600) / 60))m"
    else REPLY="$((s / 86400))d$(((s % 86400) / 3600))h"; fi
}
longv() {
    local s="$1"
    if [[ $s -lt 7200 ]]; then REPLY="$(( (s + 30) / 60 )) m"
    elif [[ $s -lt 259200 ]]; then REPLY="$(( (s + 1800) / 3600 )) h"
    else REPLY="$(( (s + 43200) / 86400 )) d"; fi
}
cores() {
    local i="${1%%.*}"
    num "$i" || { REPLY="$1"; return; }
    i=$(( (10#$i + 5) / 10 ))
    REPLY="$((i / 10)).$((i % 10)) cores"
}
# Action prefixes, built once.
if [[ "$AGENTS$SELF" == *[\"\\]* ]]; then
    echo ":exclamationmark.triangle: | sfcolor=#FF9F0A"
    echo "---"
    echo "Refusing to run: the agents or plugin path contains a quote or a backslash | color=red"
    exit 0
fi
ACT="bash=\"$AGENTS\" terminal=false refresh=true"
NOREF="bash=\"$AGENTS\" terminal=false"
TERM_OPEN="bash=\"$AGENTS\" param1=open-term terminal=false"
CALLBACK="bash=\"$SELF\" terminal=false"
num() { [[ "$1" =~ ^[0-9]+$ ]]; }
# humanize N — a count for people, in REPLY: 950, 64.2k, 640k, 12.4M, 1.2B.
humanize() {
    local n="$1" u=1 s="" t
    if [[ $n -ge 999500000 ]]; then u=1000000000 s=B
    elif [[ $n -ge 999500 ]]; then u=1000000 s=M
    elif [[ $n -ge 1000 ]]; then u=1000 s=k
    else REPLY="$n"; return; fi
    t=$(( (n * 10 + u / 2) / u ))
    if [[ $t -lt 1000 ]]; then
        REPLY="$((t / 10))"; [[ $((t % 10)) -eq 0 ]] || REPLY+=".$((t % 10))"
    else REPLY="$(( (n + u / 2) / u ))"; fi
    REPLY+="$s"
}
# pctv PCPU — a %cpu for people, whole like Where the CPU goes, in REPLY:
# 102.4 -> 102, 6.8 -> 7, 0.3 -> <1, 0.0 -> 0 (anything else as it came).
pctv() {
    local i="${1%%.*}" f=0
    [[ "$1" == *.* ]] && { f="${1#*.}"; f="${f:0:1}"; f="${f:-0}"; }
    if ! num "$i" || ! num "$f" || [[ ${#i} -gt 9 ]]; then REPLY="$1"; return 0; fi
    if [[ $i -eq 0 && $f -gt 0 && $f -lt 5 ]]; then REPLY="<1"; return 0; fi
    [[ $f -ge 5 ]] && i=$((10#$i + 1))
    REPLY="$((10#$i))"
}
charging() { [[ "$1" == charging || "$1" == charged || "$1" == "AC attached" || "$1" == "finishing charge" ]]; }
# battery_symbol PERCENT STATE — its SF Symbol, in REPLY.
battery_symbol() {
    local p="$1"
    REPLY=battery.0percent
    if charging "$2"; then REPLY=battery.100percent.bolt; return; fi
    if [[ $p -ge 88 ]]; then REPLY=battery.100percent
    elif [[ $p -ge 63 ]]; then REPLY=battery.75percent
    elif [[ $p -ge 38 ]]; then REPLY=battery.50percent
    elif [[ $p -ge 13 ]]; then REPLY=battery.25percent; fi
}

# --- Read the snapshot -------------------------------------------------------------

me="${USER:-}"; [[ -n "$me" ]] || me="$(id -un)"
n_agents=0 n_blocked=0 n_stale=0 n_hogs=0 n_review=0 n_running=0 n_parked=0 n_unknown=0 n_warned=0 oldest=-1
needs_menu="" review_menu="" running_menu="" parked_menu="" unknown_menu="" daemon_menu="" stale_menu="" hogs_menu="" top_menu="" stale_tokens=""
awake_mode=off awake_until=0 thermal=- thermal_name=unknown power=unknown
lid_state=off lid_until=0 lid_max=28800 BAR_LID=1
# Fan control (--pack cooling): absent until the cool row says otherwise.
cool_state=absent cool_mode=- cool_soc=- cool_ctl=- cool_rpms=- cool_low=- cool_high=-
cpu=- load=- cores=- memfree=- mempress=- batt=- bstate=-
# The memory guard (the memg row): its state, warning and stop sizes, and the
# last incident. Hogs are rendered once it is known (hog_rows).
mem_state=none mem_warn=0 mem_stop=0 mem_last=0 mem_ev=- mem_what=- mem_proj=- mem_fp=0
hog_rows=()
BAR_TITLE="triage awake" BAR_SECTIONS="needs review running parked limits today stale hogs awake system" BAR_ICON=terminal CONF=""
# Herdr's health (hhealth rows) is maintenance, at the bottom: never in Needs
# you, the tint or the title.
herdr_stale="" herdr_vers="" herdr_outdated=""
# Herdr sessions (in a Herdr pane), and whether one works or waits for you:
# a server restart restarts them all.
n_in_herdr=0 herdr_busy=""
job_rows="" mcp_cfg="" hist_state="" hist_total=0 hist_top=- hist_top_s=0 insight_view="" insight_text="" tok_total=0 tok_cache=0
# Usage: each CLI's limit windows ("name<TAB>window<TAB>pct<TAB>resets<TAB>
# cli<TAB>age" lines), the highest %, and today's denials and compactions.
usage_rows="" limit_max=-1 n_denials=0 denials_top=- n_compacts=0
# Swap, while it is high (the swap row); today's waits (the waitsum row).
swap_pct="" swap_used=0 swap_total=0 swap_bar="" wait_blocked=""

# Per-session activity, gathered from the act rows into variables named after
# the session's pid (bash 3.2 has no associative arrays): A_<what>_<pid>.
aget() { local v="A_$1_$2"; REPLY="${!v-}"; }
aadd() { local v="A_$1_$2"; printf -v "$v" '%s%s' "${!v-}" "$3"; }
anum() { local v="A_$1_$2"; printf -v "$v" '%d' $(( ${!v:-0} + $3 )); }

# dup_groups LINES — for "cwd\037cmd<TAB>age<TAB>token" lines, one line per
# command running more than once in one directory, in DUPS: "count<TAB>
# cwd\037cmd<TAB>tokens of all but the newest". Sorts only when there are any.
dup_groups() {
    local cmd tk prev="" n=0 toks=""
    DUPS=""
    [[ -n "$1" ]] || return 0
    while IFS=$'\t' read -r cmd _ tk; do
        [[ -n "$tk" ]] || continue
        if [[ $n -gt 0 && "$cmd" == "$prev" ]]; then
            n=$((n + 1)); toks+=" $tk"
        else
            [[ $n -gt 1 ]] && DUPS+="$n"$'\t'"$prev"$'\t'"$toks"$'\n'
            prev="$cmd"; n=1; toks=""
        fi
    done < <(printf '%s' "$1" | sort -t $'\t' -k1,1 -k2,2n)
    [[ $n -gt 1 ]] && DUPS+="$n"$'\t'"$prev"$'\t'"$toks"$'\n'
    return 0
}

# What a session runs, in its submenu: each command with Stop command…, the
# MCP servers on one line, and Stop duplicates when a command runs twice.
# Appends to SUB (no subshells: this runs for every session on every refresh).
activity_submenu() {   # PID
    local r="$1" n m g cmd toks params i tk v
    v="A_ntools_$r"; n="${!v-}"; v="A_mcpn_$r"; m="${!v-}"
    if [[ -n "$n" ]]; then
        v="A_tools_$r"
        SUB+="--Running ($n) | size=11"$'\n'"${!v}"
    fi
    if [[ -n "$m" ]]; then
        local s=""; [[ $m -gt 1 ]] && s=s
        v="A_mcprss_$r"; memv "${!v:-0}"; v="A_mcpprocs_$r"
        SUB+="--MCP: $m server$s · ${!v:-0} procs · $REPLY | size=11"$'\n'
    fi
    v="A_dups_$r"
    [[ -n "${!v-}" ]] || return 0
    dup_groups "${!v}"
    while IFS=$'\t' read -r g cmd toks; do
        [[ -n "$g" ]] || continue
        params="param1=kill param2=--confirm-gui param3=--notify"; i=4
        for tk in $toks; do params+=" param$i=$tk"; i=$((i + 1)); done
        sh60 "${cmd#*$'\037'}"
        SUB+="--Stop duplicates: ${g}× $REPLY (keep newest)… | $ACT $params sfimage=xmark.octagon symbolize=false"$'\n'
    done <<<"$DUPS"
}

# --- Going to a session ---------------------------------------------------------------
# Where each session lives comes with the snapshot (where rows: W_how_<pid>,
# W_place_<pid>) for its summary only: Jump to session, Peek and Details run
# `agents jump|peek|show`, which find it again when you click (a Herdr pane,
# a tmux pane, the terminal tab that shows it), never on a refresh.

# where_text PID — REPLY: where session PID lives, for people ("" unknown).
where_text() {
    local v="W_how_$1" h p
    h="${!v-}"; v="W_place_$1"; p="${!v-}"
    REPLY=""
    case "$h" in
        tmux)  cl "$p"; REPLY="in tmux pane $REPLY" ;;
        herdr) REPLY="in Herdr"; [[ -z "$p" || "$p" == - ]] || { cl "$p"; REPLY="in Herdr (in $REPLY)"; } ;;
        app)   cl "$p"; REPLY="in $REPLY" ;;
        ssh)   REPLY="over ssh" ;;
    esac
}
# jump_item TOKEN — REPLY: the Jump to session line (the first of a submenu).
jump_item() { REPLY="--Jump to session | $NOREF param1=jump param2=--notify param3=$1 sfimage=arrow.up.forward.app"; }
# look_items TOKEN SESSION — Peek (when SESSION lives in a tmux or Herdr
# pane) and Details (agents show, live). Appends to SUB.
look_items() {
    local v h=""
    if num "$2"; then v="W_how_$2"; h="${!v-}"; fi
    case "$h" in
        tmux|herdr) SUB+="--Peek | $TERM_OPEN param2=--hold param3=peek param4=$1 param5=60 sfimage=eye"$'\n' ;;
    esac
    SUB+="--Details | $TERM_OPEN param2=show param3=--watch param4=$1 sfimage=info.circle"$'\n'
}

# The submenu under a session: Jump to session first, then where it is, what
# it is and does, and what you can do. Sets SUB.
session_submenu() {   # PID START KIND AGE KIDS PORTS CWD [STATUS]
    local pid="$1" start="$2" kind="$3" age_s="$4" kids="$5" ports="$6" cwd="$7" status="${8:--}" t="" pl="" s v
    SUB=""
    [[ "$pid" =~ ^[0-9]+$ && "$start" =~ ^[A-Za-z0-9_:]+$ ]] && t="$pid@$start"
    if [[ -n "$t" && "$kind" != daemon ]]; then jump_item "$t"; SUB+="$REPLY"$'\n'; fi
    if [[ "$cwd" != - ]]; then cl "$cwd"; SUB+="--$REPLY | symbolize=false"$'\n'; fi
    if [[ "$ports" != - ]]; then cl "$ports"; pl=" · ports $REPLY"; fi
    agev "$age_s"; s="$REPLY"; cl "$kind"
    SUB+="--$REPLY · pid $pid · up $s · $kids children$pl | symbolize=false"$'\n'
    # Its state, where it lives, and the busiest command it runs.
    s=""
    case "$status" in
        blocked) s="blocked: waiting for you" ;;
        -|"")    ;;
        *)       cl "$status"; s="$REPLY" ;;
    esac
    where_text "$pid"; [[ -z "$REPLY" ]] || s+="${s:+ · }$REPLY"
    [[ -z "$s" ]] || SUB+="--$s | symbolize=false"$'\n'
    v="A_bcpu_$pid"; if [[ "${!v:-0}" -ge 1 ]]; then v="A_busy_$pid"; SUB+="--busiest: ${!v} | symbolize=false"$'\n'; fi
    [[ -n "$t" ]] || return 0
    activity_submenu "$pid"
    SUB+="-----"$'\n'
    look_items "$t" "$pid"
    local what=session; [[ "$kind" == daemon ]] && what=daemon
    SUB+="--Kill ${what}… | $ACT param1=kill param2=--confirm-gui param3=--notify param4=$t sfimage=xmark.octagon"$'\n'
    if [[ "$cwd" != - ]]; then
        SUB+="--Copy path | $NOREF param1=copy-path param2=$t sfimage=doc.on.doc"$'\n'
        SUB+="--Open in Finder | $NOREF param1=reveal param2=$t sfimage=folder"$'\n'
    fi
    SUB+="--Copy PID | $CALLBACK param1=copy param2=$pid sfimage=number"$'\n'
}

# --- Flagged items: verdicts ----------------------------------------------------------
# `agents tsv` starts with a verdict for each flagged item (need rows,
# from agents_assess) and its evidence (evid rows), kept here in N_<what>_<pid>
# and A_ev_<pid>. An item without one (an older agents) keeps the plain menu.

# need_submenu PID TOKEN STOP_LINE — under an item: while its session runs,
# Jump to session first (to where it runs: you can answer it there); then the
# verdict, the evidence, Stop (STOP_LINE), Copy details (`agents why
# --copy`), Show session (`agents ps` of that session in your terminal),
# Peek and Details. Sets SUB.
need_submenu() {
    local p="$1" v o look=info.circle
    SUB=""
    v="N_owner_$p"; o="${!v-}"
    if num "$o"; then jump_item "$2"; SUB+="$REPLY"$'\n'; fi
    v="N_act_$p"
    case "${!v-}" in
        stop)  look=checkmark.circle ;;
        check) look=questionmark.circle ;;
        leave) look=hand.raised ;;
    esac
    v="N_text_$p"; cl "${!v-}"
    SUB+="--$REPLY | $ROW sfimage=$look symbolize=false"$'\n'
    v="A_ev_$p"; SUB+="${!v-}"
    SUB+="-----"$'\n'"$3"$'\n'
    SUB+="--Copy details | $NOREF param1=why param2=--copy param3=$2 sfimage=doc.on.doc"$'\n'
    if num "$o"; then SUB+="--Show session | $TERM_OPEN param2=--hold param3=ps param4=$o sfimage=terminal"$'\n'; fi
    look_items "$2" "${o:--}"
}

# warn_item TEXT SYMBOL CMD TOKEN — one flagged command: its verdict at a glance
# on the line (the warn tint for safe to stop and check first, gray for leave it
# and informational), the command and the rest in its submenu. Adds a W row.
warn_item() {
    local p="${4%%@*}" v dot="$TINT_WARN" stop text="$1" head
    stop="--Stop command… | $ACT param1=kill param2=--confirm-gui param3=--notify param4=$4 sfimage=xmark.octagon"
    WN=$((WN + 1)); WS[WN]="$2"
    sh60 "$3"; head="--$REPLY | symbolize=false"$'\n'
    v="N_short_$p"
    if [[ -z "${!v-}" ]]; then
        WT[WN]="$text"; WD[WN]="$dot"; WB[WN]="$head$stop"$'\n'
        return 0
    fi
    cl "${!v}"; text+=" · $REPLY"; v="N_act_$p"
    [[ "${!v-}" == stop || "${!v-}" == check ]] || dot="$TINT_IDLE"
    need_submenu "$p" "$4" "$stop"
    WT[WN]="$text"; WD[WN]="$dot"; WB[WN]="$head$SUB"
}

# warn_rows PID WHO — what is flagged under a session: W rows, WN of them: each
# text (WT), symbol (WS), tint (WD) and submenu (WB).
warn_rows() {
    local p="$1" who="$2" g cmd toks params i tk lage c
    WN=0
    aget dups "$p"; dup_groups "$REPLY"
    while IFS=$'\t' read -r g cmd toks; do
        [[ -n "$g" ]] || continue
        params="param1=kill param2=--confirm-gui param3=--notify"; i=4
        for tk in $toks; do params+=" param$i=$tk"; i=$((i + 1)); done
        sh60 "${cmd#*$'\037'}"
        WN=$((WN + 1)); WT[WN]="$who · ${g}× $REPLY running"; WS[WN]=square.stack.3d.up; WD[WN]="$TINT_WARN"
        WB[WN]="--Stop duplicates (keep newest)… | $ACT $params sfimage=xmark.octagon"$'\n'
    done <<<"$DUPS"
    aget longs "$p"
    while IFS=$'\t' read -r cmd lage tk; do
        [[ -n "$tk" ]] || continue
        sh60 "$cmd"; c="$REPLY"; agev "$lage"
        warn_item "$who · $c · running $REPLY" clock "$cmd" "$tk"
    done <<<"$REPLY"
    aget stucks "$p"
    while IFS=$'\t' read -r cmd lage tk; do
        [[ -n "$tk" ]] || continue
        agev "$lage"
        warn_item "$who · wait-loop stuck $REPLY" hourglass "$cmd" "$tk"
    done <<<"$REPLY"
}

n_auto=0 BAR_AUTO=0 BAR_SERVICE=""
agent_rows=()
while IFS=$'\t' read -r type pid kind age_s pcpu avg rss kids start ports user herdr cwd args project aflags adup; do
    case "$type" in
        # palette NAME NEED DONE RUN WARN ACCENT BG: first, before anything tinted
        palette) use_palette "$kind" "$age_s" "$pcpu" "$avg" "$kids" ;;
        # triage PID STATE AGE LABEL: what the session is, as `agents` says it
        triage) num "$pid" || continue
                printf -v "T_state_$pid" '%s' "$kind"; printf -v "T_age_$pid" '%s' "$age_s"; printf -v "T_label_$pid" '%s' "$pcpu" ;;
        swap)   num "$pid" && { swap_pct="$pid"; swap_used="$kind"; swap_total="$age_s"; swap_bar="$pcpu"; } ;;
        waitsum) num "$pid" && wait_blocked="$pid" ;;   # waitsum BLOCKED_S FRESH_S PARKED_S
        need)   # need PID START FLAG ACTION CONF CODE AUTO OWNER SHORT VERDICT …
            num "$pid" || continue
            printf -v "N_short_$pid" '%s' "$ports"; printf -v "N_text_$pid" '%s' "$user"
            printf -v "N_act_$pid" '%s' "$pcpu"; printf -v "N_owner_$pid" '%s' "$start"
            [[ "$kids" == 1 ]] && n_auto=$((n_auto + 1))
            ;;
        evid)   # evid PID fact|next|auto TEXT: the facts and the auto-reap note
            num "$pid" || continue
            [[ "$kind" == fact || "$kind" == auto ]] || continue
            cl "$age_s"; aadd ev "$pid" "--$REPLY | symbolize=false"$'\n'
            ;;
        agent) agent_rows+=("$pid"$'\t'"$kind"$'\t'"$age_s"$'\t'"$pcpu"$'\t'"$rss"$'\t'"$kids"$'\t'"$start"$'\t'"$ports"$'\t'"$herdr"$'\t'"$cwd"$'\t'"$project") ;;
        act)   # act PID CLASS AGE CPU AVG RSS KIDS START PORTS ROOT LABEL CWD CMD ORIGIN FLAGS DUPS
            r="$user"; { num "$r" && num "$pid"; } || continue
            printf -v "U_start_$pid" '%s' "$start"      # an MCP server's token (Where the CPU goes)
            case "$kind" in
                tool)
                    [[ "$pid" =~ ^[0-9]+$ && "$start" =~ ^[A-Za-z0-9_:]+$ ]] || continue
                    t="$pid@$start" fl=""
                    [[ ",$aflags," == *,dup,* ]] && fl+=" · ${adup}× dup"
                    [[ ",$aflags," == *,long,* ]] && fl+=" · long"
                    [[ ",$aflags," == *,hot,* ]] && fl+=" · hot"
                    # A polling loop the agent waits on: marked, and attention
                    # only once it is stuck (it has waited too long).
                    look=""
                    if [[ ",$aflags," == *,stuck,* ]]; then fl+=" · stuck"; look=" sfimage=hourglass $TINT_WARN"
                    elif [[ ",$aflags," == *,wait,* ]]; then fl+=" · waiting"; look=" sfimage=hourglass $TINT_IDLE"; fi
                    sh60 "$args"; c="$REPLY"; agev "$age_s"; a="$REPLY"; cl "$project"
                    aadd tools "$r" "--$c · $a · ${pcpu%%.*}% · $REPLY$fl | $ROW$look symbolize=false"$'\n'"----Stop command… | $ACT param1=kill param2=--confirm-gui param3=--notify param4=$t sfimage=xmark.octagon"$'\n'
                    anum ntools "$r" 1
                    v="A_bcpu_$r"   # the busiest command, for the session's summary
                    if [[ -z "${!v-}" || ${pcpu%%.*} -gt ${!v} ]]; then
                        printf -v "$v" '%d' "${pcpu%%.*}"; printf -v "A_busy_$r" '%s' "$c · $a · ${pcpu%%.*}%"
                    fi
                    # Duplicates are the same command in the same directory.
                    [[ ",$aflags," == *,dup,* ]] && aadd dups "$r" "$cwd"$'\037'"$args"$'\t'"$age_s"$'\t'"$t"$'\n'
                    [[ ",$aflags," == *,long,* ]] && aadd longs "$r" "$args"$'\t'"$age_s"$'\t'"$t"$'\n'
                    [[ ",$aflags," == *,stuck,* ]] && aadd stucks "$r" "$args"$'\t'"$age_s"$'\t'"$t"$'\n'
                    ;;
                mcp)
                    v="A_mcpnames_$r"
                    [[ " ${!v-} " == *" $herdr "* ]] || { aadd mcpnames "$r" " $herdr"; anum mcpn "$r" 1; }
                    anum mcpprocs "$r" $((kids + 1)); anum mcprss "$r" "$rss"
                    ;;
            esac
            ;;
        where)  # where PID tmux|herdr|ssh|app|- PLACE
            num "$pid" || continue
            printf -v "W_how_$pid" '%s' "$kind"; printf -v "W_place_$pid" '%s' "$age_s" ;;
        herdr)  # herdr PID PANE TITLE: the session's Herdr pane and task title
            num "$pid" || continue
            [[ "$age_s" == - ]] || printf -v "H_title_$pid" '%s' "$age_s" ;;
        hhealth)   # hhealth server stale [SERVER_VERSION CLIENT_VERSION] | hhealth outdated NAME…
            case "$pid" in
                server)   if [[ "$kind" == stale ]]; then
                              herdr_stale=1
                              [[ "$age_s" =~ ^[0-9][0-9A-Za-z.+-]{0,30}$ && "$pcpu" =~ ^[0-9][0-9A-Za-z.+-]{0,30}$ ]] \
                                  && herdr_vers="$age_s → $pcpu"
                          fi ;;
                outdated) herdr_outdated="$kind" ;;
            esac ;;
        stale)
            n_stale=$((n_stale + 1))
            v="N_short_$pid"; vs=""; [[ -n "${!v-}" ]] && { cl "${!v}"; vs=" · $REPLY"; }
            cl "${args:0:60}"; c="$REPLY"; agev "$age_s"; a="$REPLY"; memv "$rss"
            look=puzzlepiece.extension; [[ "$kind" == server ]] && look=network
            stale_menu+="$c · $a · $REPLY$vs | $ROW symbolize=false sfimage=$look"$'\n'
            c="--$kind · pid $pid"
            [[ "$cwd" != - ]] && { cl "$cwd"; c+=" · $REPLY"; }
            [[ "$ports" != - ]] && { cl "$ports"; c+=" · ports $REPLY"; }
            stale_menu+="$c | symbolize=false"$'\n'
            if tok "$pid" "$start"; then
                t="$REPLY"
                kl="--Kill tree | $ACT param1=kill param2=-y param3=--notify param4=$t sfimage=xmark.octagon"
                if [[ -n "$vs" ]]; then need_submenu "$pid" "$t" "$kl"; stale_menu+="$SUB"
                else stale_menu+="$kl"$'\n'"--Details | $TERM_OPEN param2=show param3=--watch param4=$t sfimage=info.circle"$'\n'; fi
                stale_tokens+=" $t"
            fi
            ;;
        hog)     hog_rows+=("$pid"$'\t'"$kind"$'\t'"$age_s"$'\t'"$pcpu"$'\t'"$avg"$'\t'"$rss"$'\t'"$start"$'\t'"$user"$'\t'"$args") ;;
        # memg STATE GUARD_PID WARN_KIB STOP_KIB LAST_EPOCH LAST_EVENT LAST_WHAT LAST_PROJECT LAST_FP_KIB
        memg)    mem_state="$pid"; mem_warn="$age_s"; mem_stop="$pcpu"; mem_last="$avg"
                 mem_ev="$rss"; mem_what="$kids"; mem_proj="$start"; mem_fp="$ports" ;;
        top)     cl "$kind"; c="$REPLY"; pctv "$pcpu"; a="$REPLY"; memv "$rss"
                 top_menu+="--$c · $a% · $REPLY | $CALLBACK param1=activity-monitor symbolize=false"$'\n' ;;
        sys)     cpu="$pid"; load="$kind"; cores="$age_s"; memfree="$pcpu"; mempress="$avg"; batt="$rss"; bstate="$kids" ;;
        awake)   awake_mode="$pid"; awake_until="$age_s" ;;   # awake MODE PID UNTIL
        thermal) thermal="$pid"; thermal_name="$kind" ;;
        power)   power="$pid" ;;
        lid)     lid_state="$pid"; lid_until="$age_s"; lid_max="$pcpu" ;;   # lid STATE PID UNTIL MAX
        # cool STATE MODE SOC CONTROL RPMS LOW HIGH PRESSURE (fan control)
        cool)    cool_state="$pid"; cool_mode="$kind"; cool_soc="$age_s"; cool_ctl="$pcpu"
                 cool_rpms="$avg"; cool_low="$rss"; cool_high="$kids" ;;
        # job ROOT JOB 0 CPU 0 RSS PROCS START own|sub UNIT KIND CWD NAME PROJECT VIA
        # (NAME and VIA: the MCP server's name and launcher for the mcp job, else "-")
        job)     job_rows+="$kind"$'\t'"$pcpu"$'\t'"$rss"$'\t'"$kids"$'\t'"$herdr"$'\t'"$project"$'\t'"$pid"$'\t'"$start"$'\t'"$cwd"$'\t'"$args"$'\t'"$user"$'\t'"${aflags:--}"$'\n' ;;
        # mcpcfg CLI SCOPE NAME SOURCE PROJECT: who configured each MCP server
        mcpcfg)  mcp_cfg+="$pid"$'\t'"$kind"$'\t'"$age_s"$'\t'"$pcpu"$'\t'"$avg"$'\n' ;;
        hist)    hist_state="$pid"; hist_total="$kind"; hist_top="$age_s"; hist_top_s="$pcpu" ;;   # hist STATE TODAY_S TOP TOP_S
        insight) insight_view="$pid"; insight_text="$kind" ;;   # insight VIEW TEXT
        tokens)  tok_total="$pid"; tok_cache="$kind" ;;         # tokens TOTAL CACHE_PCT (today)
        # limit NAME WINDOW PCT RESETS CLI AGE, then its pace ELAPSED PACE LEFT BAR ·
        # denials COUNT TOP · compacts COUNT
        limit)   if num "$age_s"; then
                     usage_rows+="$pid"$'\t'"$kind"$'\t'"$age_s"$'\t'"$pcpu"$'\t'"$avg"$'\t'"$rss"$'\n'
                     [[ $age_s -le $limit_max ]] || limit_max="$age_s"
                 fi ;;
        pace)    [[ -z "$usage_rows" ]] || usage_rows="${usage_rows%$'\n'}"$'\t'"$pid"$'\t'"$kind"$'\t'"$age_s"$'\t'"$pcpu"$'\n' ;;
        denials)  num "$pid" && { n_denials="$pid"; denials_top="$kind"; } ;;
        compacts) num "$pid" && n_compacts="$pid" ;;
        conf)
            [[ "$kind" == - ]] && kind=""
            case "$pid" in
                AGENTS_BAR_TITLE)    BAR_TITLE="$kind" ;;
                AGENTS_BAR_SECTIONS) BAR_SECTIONS="$kind" ;;
                AGENTS_BAR_ICON)     BAR_ICON="${kind:-terminal}" ;;
                AGENTS_LID)          BAR_LID="${kind:-1}" ;;
                AGENTS_CONF)         CONF="$kind" ;;
                AGENTS_AUTO_REAP)    BAR_AUTO="${kind:-0}" ;;
                AGENTS_SERVICE_PATH) BAR_SERVICE="$kind" ;;
            esac
            ;;
    esac
done <<<"$data"

# Hogs: a memory hog (RSS past the guard's warning, listed first) by its
# memory, the others by their CPU.
num "$mem_warn" || mem_warn=0
for row in ${hog_rows[@]+"${hog_rows[@]}"}; do
    IFS=$'\t' read -r pid kind age_s pcpu avg rss start user args <<<"$row"
    num "$rss" || rss=0
    n_hogs=$((n_hogs + 1))
    cl "$kind"; c="$REPLY"
    if [[ $mem_warn -gt 0 && $rss -ge $mem_warn ]]; then
        memv "$rss"
        hogs_menu+="$c · $REPLY memory | $ROW symbolize=false sfimage=memorychip $TINT_NEED"$'\n'
    else
        pctv "$pcpu"; a="$REPLY"; pctv "$avg"
        hogs_menu+="$c · $a% now · $REPLY% avg | $ROW symbolize=false sfimage=flame"$'\n'
    fi
    cl "$user"; c="$REPLY"; agev "$age_s"; a="$REPLY"; memv "$rss"
    hogs_menu+="--pid $pid · $c · up $a · $REPLY | symbolize=false"$'\n'
    # A system service: nothing to stop, its manager would only restart it.
    # Past the memory warning it has no "settles" to promise.
    if [[ -n "$BAR_SERVICE" && "$args" =~ $BAR_SERVICE ]]; then
        [[ $mem_warn -gt 0 && $rss -ge $mem_warn ]] || hogs_menu+="--A system service: it usually settles on its own | symbolize=false"$'\n'
    elif [[ "$user" == "$me" ]] && tok "$pid" "$start"; then
        hogs_menu+="--Terminate (SIGTERM) | $ACT param1=term param2=-y param3=--notify param4=$REPLY sfimage=xmark.octagon"$'\n'
    elif [[ "$user" != "$me" ]]; then
        hogs_menu+="--Owned by $c: run sudo kill $pid in a terminal | symbolize=false"$'\n'
    fi
done
# A memory incident in the last 15 minutes (warn, grow, stop, refused,
# pressure) needs a look, and so does a guard that should run but doesn't.
mem_recent=0
if num "$mem_last" && [[ $mem_last -gt 0 ]]; then
    NOW_S="$(date +%s)"   # now_s, defined with the sections below
    [[ $((NOW_S - mem_last)) -lt 900 ]] && mem_recent=1
fi

# Auto-reap (AGENTS_AUTO_REAP=1): when something here is safe to stop on its
# own, `agents reap --auto` runs in the background, at most once a minute
# (--throttle), and never holds up the menu.
if [[ "$BAR_AUTO" == 1 && $n_auto -gt 0 ]]; then
    ( "$AGENTS" reap --auto --throttle --notify </dev/null >/dev/null 2>&1 & )
fi
# `sys` packs battery state into the kids column, which can hold spaces.
[[ "$bstate" == - ]] && bstate=""
# History: a sample a minute (`agents sample`), in the background, never waited on.
if [[ "$hist_state" == due ]]; then
    ( trap '' HUP; exec "$AGENTS" sample ) </dev/null >/dev/null 2>&1 &
fi

# Second pass: sessions, now that their activity is known. Each goes in the
# section of its state; a flagged command takes over a running session's row, and
# gets a row of its own in Running under a session in any other state.
n_attn=0
running_extra=""
for row in ${agent_rows[@]+"${agent_rows[@]}"}; do
    IFS=$'\t' read -r pid kind age_s pcpu rss kids start ports herdr cwd project <<<"$row"
    if [[ "$kind" == daemon ]]; then
        pctv "$pcpu"; pc="$REPLY"; memv "$rss"
        daemon_menu+="codex daemon · $pc% · $REPLY | sfimage=gearshape $ROW symbolize=false"$'\n'
        session_submenu "$pid" "$start" daemon "$age_s" "$kids" "$ports" -
        daemon_menu+="$SUB"
        continue
    fi
    n_agents=$((n_agents + 1))
    # In Herdr and not idle or done (or its state unknown): not a time to
    # restart Herdr's server.
    v="W_how_$pid"
    if [[ "$herdr" != - || "${!v-}" == herdr ]]; then
        n_in_herdr=$((n_in_herdr + 1))
        [[ "$herdr" == idle || "$herdr" == "done" ]] || herdr_busy=1
    fi
    cl "${project:--}"; name="$REPLY"; [[ "$name" == - || -z "$name" ]] && { cl "$kind"; name="$REPLY"; }
    # Herdr's task title for the pane, when it has one, says it better than the
    # project (two sessions of a project are told apart by it); the project and
    # the kind are the first lines of its submenu.
    v="H_title_$pid"; who="$name"
    if [[ -n "${!v-}" ]]; then sh60 "${!v}"; who="$REPLY"; fi
    # An older `agents` sends no triage row: Herdr's status alone, then.
    v="T_state_$pid"; state="${!v-}"
    v="T_age_$pid"; tage="${!v-}"
    v="T_label_$pid"; cl "${!v-}"; label="$REPLY"
    if [[ -z "$state" ]]; then
        tage=-
        case "$herdr" in
            blocked) state=need label=blocked ;;
            "done")  state=review label="done" ;;
            idle)    state=parked label=idle ;;
            working) state=run label=working ;;
            *)       state=unknown label="no signal" ;;
        esac
    fi
    # Clicking the row itself shows the project in Finder (resolved from
    # PID@START); everything else is in its submenu.
    click="$ROW"
    tok "$pid" "$start" && [[ "$cwd" != - ]] && click="$NOREF param1=reveal param2=$REPLY"
    session_submenu "$pid" "$start" "$kind" "$age_s" "$kids" "$ports" "$cwd" "$herdr"; sub="$SUB"
    warn_rows "$pid" "$who"
    i=1
    case "$state" in
        need)
            n_blocked=$((n_blocked + 1))
            t=""; if num "$tage"; then agev "$tage"; t=" · $REPLY"; fi
            needs_menu+="$who · $label$t | sfimage=exclamationmark.circle.fill $TINT_NEED $click symbolize=false"$'\n'"$sub" ;;
        review)
            n_review=$((n_review + 1))
            t=""; if num "$tage"; then agev "$tage"; t=" $REPLY"; fi
            review_menu+="$who · $label$t | sfimage=checkmark.circle $TINT_DONE $click symbolize=false"$'\n'"$sub" ;;
        parked)
            n_parked=$((n_parked + 1))
            t=""; if num "$tage"; then longv "$tage"; t=" · $REPLY"; [[ $tage -le $oldest ]] || oldest="$tage"; fi
            SUB="--${sub//$'\n'/$'\n'--}"
            parked_menu+="--$who · $label$t | sfimage=circle $TINT_IDLE $click symbolize=false"$'\n'"${SUB%--}" ;;
        unknown)
            n_unknown=$((n_unknown + 1))
            memv "$rss"; m="$REPLY"; cores "$pcpu"
            unknown_menu+="$who · $label · $REPLY · $m | sfimage=questionmark.circle $TINT_IDLE $click symbolize=false"$'\n'"$sub" ;;
        *)
            n_running=$((n_running + 1))
            if [[ $WN -gt 0 ]]; then
                # The flag is what you'd want to read; the session is one level down.
                running_menu+="${WT[1]} | sfimage=${WS[1]} ${WD[1]} $ROW symbolize=false"$'\n'"${WB[1]}"$'-----\n'"$sub"
                i=2
            else
                memv "$rss"; m="$REPLY"; cores "$pcpu"
                running_menu+="$who · $label · $REPLY · $m | sfimage=circle.fill $TINT_RUN $click symbolize=false"$'\n'"$sub"
            fi ;;
    esac
    while [[ $i -le $WN ]]; do
        n_warned=$((n_warned + 1))
        running_extra+="${WT[i]} | sfimage=${WS[i]} ${WD[i]} $ROW symbolize=false"$'\n'"${WB[i]}"
        i=$((i + 1))
    done
done

# Sleep disabled with no guard to restore it (a reboot killed it): a Mac in a
# bag would never sleep. First in Needs you, and the icon turns red.
if [[ "$lid_state" == stale ]]; then
    n_attn=$((n_attn + 1))
    needs_menu="Restore lid sleep (disabled, nothing restores it)… | sfimage=exclamationmark.triangle.fill $TINT_NEED $ACT param1=awake param2=restore param3=--notify symbolize=false"$'\n'"$needs_menu"
fi

# Maintenance: Herdr after an upgrade (an hourly check, hhealth rows). A
# server older than its client is fine (Herdr supports the mismatch) and
# restarting it restarts every Herdr session, losing their context: so it
# waits for the next restart, never nags, and offers the commands only
# while no Herdr session works or waits for you. Integrations older than
# the client reinstall without a restart. One dim line near the bottom,
# its submenu holding the rest; never Needs you, the tint or the title.
# Nothing is run from here.
maint_menu="" n_maint=0
if [[ -n "$herdr_stale" ]]; then
    n_maint=$((n_maint + 1))
    if [[ -n "$herdr_vers" ]]; then cl "$herdr_vers"; v="Herdr server $REPLY on next restart"
    else v="Herdr server update on next restart"; fi
    maint_menu+="--$v | sfimage=arrow.triangle.2.circlepath $TINT_IDLE $ROW symbolize=false"$'\n'
    maint_menu+="----The version difference is fine; restarting the server restarts every Herdr session | size=11"$'\n'
    if [[ -z "$herdr_busy" ]]; then
        v="No agents running"; [[ $n_in_herdr -eq 0 ]] || v="Its agents are idle"
        maint_menu+="----$v: restart now (it also stops shells and servers in its panes) | sfimage=checkmark.circle $TINT_IDLE $ROW symbolize=false"$'\n'
        maint_menu+="------In a terminal outside Herdr: | size=11"$'\n'
        maint_menu+="------herdr server stop | $ROW sfimage=terminal symbolize=false"$'\n'"------then: herdr | $ROW sfimage=terminal symbolize=false"$'\n'
    fi
fi
herdr_names=""
for v in $herdr_outdated; do [[ "$v" =~ ^[A-Za-z0-9_.-]+$ ]] && herdr_names+=" $v"; done
if [[ -n "$herdr_names" ]]; then
    n_maint=$((n_maint + 1))
    maint_menu+="--Herdr integrations outdated:$herdr_names | sfimage=puzzlepiece.extension $TINT_IDLE $ROW symbolize=false"$'\n'
    maint_menu+="----Reinstall each, in a terminal: | size=11"$'\n'
    for v in $herdr_names; do maint_menu+="----herdr integration install $v | $ROW sfimage=terminal symbolize=false"$'\n'; done
fi

# --- Title -------------------------------------------------------------------------
# It counts only what needs you: how many sessions are blocked (the need tint, the
# most weight anything here carries), then how many finished ones you have not
# looked at (the done tint), and is calm otherwise: the icon alone, in the menu
# bar's colors. Stale processes, hogs and flagged commands wait in the menu. The
# icon comes back, tinted, for what the machine itself can't take much more of:
# the warn tint for memory pressure, a recent memory incident, a guard that isn't
# running or a usage limit at 95%; the need tint for heavy thermal or critical
# memory pressure, or sleep disabled with nothing to restore it.

attention=""
if [[ "$mempress" == warn || $mem_recent -eq 1 || "$mem_state" == stopped || $limit_max -ge 95 ]]; then attention="$HUE_WARN"; fi
if { num "$thermal" && [[ $thermal -ge 2 ]]; } || [[ "$mempress" == critical || "$lid_state" == stale ]]; then attention="$HUE_NEED"; fi

# title_sym NAME [TINT] — a symbol in the title. SwiftBar colors them by position,
# and one past the last color takes the last: so with any tint, each has its own.
title_sym() { TITLE+=" :$1:"; TITLE_TINT+=("${2:-}"); [[ -z "${2:-}" ]] || TITLE_TINTED=1; }
# title_params — the sfcolor parameters: sfcolor, sfcolor1, sfcolor2...
title_params() {
    local i=0 c
    [[ -n "$TITLE_TINTED" ]] || return 0
    for c in ${TITLE_TINT[@]+"${TITLE_TINT[@]}"} END; do
        [[ "$c" == END ]] && break
        if [[ $i -eq 0 ]]; then printf ' |'; printf ' sfcolor=%s' "${c:-$HUE_PLAIN}"
        else printf ' sfcolor%d=%s' "$i" "${c:-$HUE_PLAIN}"; fi
        i=$((i + 1))
    done
}
bar_title() {
    local tok g
    TITLE="" TITLE_TINT=() TITLE_TINTED=""
    # Under the triage token, what needs you stands in for the icon, unless the
    # machine has something to say too.
    if [[ " $BAR_TITLE " != *" triage "* || $((n_blocked + n_review)) -eq 0 || -n "$attention" ]]; then
        title_sym "$BAR_ICON" "$attention"
    fi
    for tok in $BAR_TITLE; do
        case "$tok" in
            triage)  if [[ $n_blocked -gt 0 ]]; then title_sym exclamationmark.circle.fill "$HUE_NEED"; TITLE+=" $n_blocked"; fi
                     if [[ $n_review -gt 0 ]]; then title_sym checkmark.circle "$HUE_DONE"; TITLE+=" $n_review"; fi ;;
            count)   [[ $n_agents -gt 0 ]] && TITLE+=" $n_agents"
                     [[ $n_blocked -gt 0 ]] && TITLE+=" · $n_blocked blocked"
                     [[ $n_review -gt 0 ]] && TITLE+=" · $n_review done" ;;
            cpu)     num "$cpu" && { title_sym cpu; TITLE+=" ${cpu}%"; } ;;
            mem)     num "$memfree" && { title_sym memorychip; TITLE+=" $((100 - memfree))%"; } ;;
            load)    [[ "$load" != - ]] && { title_sym gauge.medium; TITLE+=" $load"; } ;;
            battery) num "$batt" && { battery_symbol "$batt" "$bstate"; title_sym "$REPLY"; TITLE+=" ${batt}%"; } ;;
            thermal) num "$thermal" && [[ $thermal -ge 1 ]] && { title_sym thermometer.medium; TITLE+=" $thermal_name"; } ;;
            temp)    num "$cool_soc" && { title_sym thermometer.medium; TITLE+=" ${cool_soc}°"; } ;;
            awake)   [[ "$awake_mode" != off ]] && title_sym cup.and.saucer.fill ;;
            warn)    [[ -n "$attention" ]] && title_sym exclamationmark.triangle.fill ;;
            limit)   [[ $limit_max -ge 0 ]] && { gauge "$limit_max" -; g="${REPLY%% *}"; title_sym "${g#sfimage=}"; TITLE+=" ${limit_max}%"; } ;;
        esac
    done
    printf '%s' "${TITLE# }"
    title_params
    printf '\n'
}

# --- Sections (each adds nothing when it has nothing to say) -------------------------
# A section appends its lines to OUT (put LINE), in this shell: no subshell
# per section.

put() { OUT+="$1"$'\n'; }

# Needs you: blocked sessions (and sleep left disabled), the most weight here.
section_needs() {
    local n=$((n_blocked + n_attn))
    [[ $n -gt 0 ]] || return 0
    put "Needs you ($n) | size=12"
    OUT+="$needs_menu"
}

section_review() {
    [[ $n_review -gt 0 ]] || return 0
    put "To review ($n_review) | size=12"
    OUT+="$review_menu"
}

# Running: working sessions, and what is flagged under any session. Then those
# nothing says anything about: not running for sure, and not parked either.
section_running() {
    local n=$((n_running + n_warned))
    if [[ $n_agents -eq 0 ]]; then put "No agent sessions"; return 0; fi
    if [[ $n -gt 0 ]]; then
        put "Running ($n) | size=12"
        OUT+="$running_menu$running_extra"
    fi
    if [[ $n_unknown -gt 0 ]]; then
        put "No signal ($n_unknown) | size=12"
        OUT+="$unknown_menu"
    fi
}

# Parked: one row; the sessions, with all they can do, in its submenu.
section_parked() {
    local t=""
    [[ $n_parked -gt 0 ]] || return 0
    if [[ $oldest -ge 0 ]]; then longv "$oldest"; t=" · oldest $REPLY"; fi
    put "Parked ($n_parked)$t | sfimage=archivebox $TINT_IDLE $ROW symbolize=false"
    OUT+="$parked_menu"
}

# Where the CPU goes: CPU now by job type, busiest first, each with the
# sessions behind it (clicking one shows its project in Finder). In Today's
# submenu.
job_label() {
    case "$1" in
        test) REPLY=tests ;; build) REPLY=builds ;; server) REPLY="dev servers" ;;
        browser) REPLY=browsers ;; mcp) REPLY="MCP servers" ;; agent) REPLY=agents ;;
        wait) REPLY="polling loops" ;; *) REPLY=other ;;
    esac
}
job_symbol() {
    case "$1" in
        test) REPLY=checkmark.seal ;; build) REPLY=hammer ;; server) REPLY=server.rack ;;
        browser) REPLY=globe ;; mcp) REPLY=puzzlepiece.extension ;; agent) REPLY=sparkles ;;
        wait) REPLY=hourglass ;; *) REPLY=ellipsis.circle ;;
    esac
}
# job_lines — job_rows summed per job ("J job cpu rss procs"), then per job
# and session ("S job cpu rss procs project kind root start cwd name unit
# about via", unit its first process), busiest first. MCP servers go by
# server: one running once is an S row with its name, about (who configured
# it, in words, from the mcpcfg rows in MCP_CFG) and via (the launcher its
# command line shows); one running in several sessions is a "G mcp cpu rss
# procs copies stale - - - name - about via" row, then a C row (S's
# columns) per copy. Elsewhere name, about and via are "-".
job_lines() {
    printf '%s' "$job_rows" | MCP_CFG="$mcp_cfg" LC_ALL=C awk -F '\t' -v OFS='\t' '
        function pc(x) { return (x > 0 && x < 0.5) ? "<1" : sprintf("%.0f", x) }
        function sortk(arr, keys, n,   i, j, b, t) {
            for (i = 1; i <= n; i++) { b = i; for (j = i + 1; j <= n; j++) if (arr[keys[j]] > arr[keys[b]]) b = j; t = keys[i]; keys[i] = keys[b]; keys[b] = t }
        }
        function tilde(s,   i, h) {
            h = ENVIRON["HOME"]; if (h == "" || h == "/") return s
            while ((i = index(s, h)) > 0) s = substr(s, 1, i - 1) "~" substr(s, i + length(h))
            return s
        }
        # cfg(name, kind, cwd): the mcpcfg row that starts server name in a
        # session of kind (any CLI for a stale tree) started in cwd: local
        # scope there, then project scope there, then user or plugin; a row
        # for another project only when nothing else names it; 0 for none.
        function cfg(nm, kd, cwd,   i, r, b, br) {
            b = 0; br = -1
            for (i = 1; i <= nc; i++) {
                if (Cn[i] != nm || ((kd == "claude" || kd == "codex") && Cc[i] != kd)) continue
                r = 1
                if (Cs[i] == "local" || Cs[i] == "project") r = (Cp[i] != cwd) ? 0 : (Cs[i] == "local") ? 3 : 2
                if (r > br) { br = r; b = i }
            }
            return b
        }
        # about(i): what config row i means, in words: a scope and a path,
        # never a command line.
        function about(i,   f) {
            if (!i) return "not found in the configs agents reads"
            if (Cc[i] == "codex") return "Codex config (" tilde(Csrc[i]) ") — starts in every Codex session"
            if (Cs[i] == "user") return "user scope (" tilde(Csrc[i]) ") — starts in every session"
            if (Cs[i] == "plugin") { f = Csrc[i]; sub(/@.*/, "", f); return "plugin " f " — starts in every session" }
            if (Cs[i] == "local") { f = substr(Csrc[i], 1, length(Csrc[i]) - length(Cp[i]) - 1); return "local scope (" tilde(f) ") — starts in sessions in " tilde(Cp[i]) }
            if (Cs[i] == "project") return "project scope (" tilde(Csrc[i]) ") — starts in sessions in " tilde(Cp[i])
            return Cs[i] " scope (" tilde(Csrc[i]) ")"
        }
        function srow(tag, j, k, ab, via,   r) {
            split(k, r, SUBSEP)
            print tag, j, pc(sc[k]), sm[k], sx[k], sp[k], sd[k], r[2], ss[k], sw[k], r[3], su[k], ab, via
        }
        BEGIN {
            n = split(ENVIRON["MCP_CFG"], t, "\n")
            for (i = 1; i <= n; i++) if (split(t[i], f, "\t") >= 5) { nc++; Cc[nc] = f[1]; Cs[nc] = f[2]; Cn[nc] = f[3]; Csrc[nc] = f[4]; Cp[nc] = f[5] }
        }
        NF >= 9 {
            if (!($1 in jc)) jo[++nj] = $1
            jc[$1] += $2 + 0.001 * ($3 / 1048576); jcpu[$1] += $2; jm[$1] += $3; jn[$1] += $4
            nm = ($1 == "mcp" && $10 != "" && $10 != "-") ? $10 : "-"
            k = $1 SUBSEP $7 SUBSEP nm
            if (!(k in sc)) {
                sn[$1]++; sk[$1, sn[$1]] = k; sp[k] = $6; sd[k] = $5; ss[k] = $8; sw[k] = $9; su[k] = ($11 == "" ? "-" : $11); sv[k] = "-"
                if (nm != "-") { sa[k] = cfg(nm, $5, $9); if (!(nm in gn)) go[++ng] = nm; gn[nm]++; if ($5 == "-") gst[nm]++ }
            }
            if (sv[k] == "-" && NF >= 12 && $12 != "") sv[k] = $12
            sc[k] += $2; sm[k] += $3; sx[k] += $4
            so[k] += $2 + 0.000000001 * $3          # the sort key: ties go to more memory
            if (nm != "-") { gc[nm] += $2; gm[nm] += $3; gx[nm] += $4; gso[nm] += $2 + 0.000000001 * $3 }
        }
        END {
            sortk(jc, jo, nj)
            sortk(gso, go, ng)
            for (i = 1; i <= nj; i++) {
                j = jo[i]; print "J", j, pc(jcpu[j]), jm[j], jn[j]
                m = sn[j]; for (q = 1; q <= m; q++) l[q] = sk[j, q]
                sortk(so, l, m)
                if (j != "mcp") { for (q = 1; q <= m; q++) srow("S", j, l[q], "-", "-"); continue }
                for (g = 1; g <= ng; g++) {
                    nm = go[g]; a = -1; v = ""
                    for (q = 1; q <= m; q++) {
                        split(l[q], r, SUBSEP); if (r[3] != nm) continue
                        a = (a == -1 || a == sa[l[q]]) ? sa[l[q]] : -2
                        # Copies behind mcp-lazy, some started: lazy.
                        v = (v == "" || v == sv[l[q]]) ? sv[l[q]] : (v ~ /^lazy/ && sv[l[q]] ~ /^lazy/) ? "lazy" : "-"
                    }
                    ab = (a == -2) ? "configured in more than one place (agents mcp lists them)" : about(a)
                    if (gn[nm] > 1) print "G", j, pc(gc[nm]), gm[nm], gx[nm], gn[nm], gst[nm] + 0, "-", "-", "-", nm, "-", ab, v
                    for (q = 1; q <= m; q++) {
                        split(l[q], r, SUBSEP); if (r[3] != nm) continue
                        if (gn[nm] > 1) srow("C", j, l[q], "-", "-"); else srow("S", j, l[q], ab, v)
                    }
                }
                for (q = 1; q <= m; q++) { split(l[q], r, SUBSEP); if (r[3] == "-") srow("S", j, l[q], "-", "-") }
            }
        }'
}
# mcp_about PREFIX ABOUT VIA — REPLY = an MCP server's info lines (gray, at
# PREFIX's depth): who configured it and how it starts; "-" leaves one out.
mcp_about() {
    local p="$1" out=""
    if [[ "$2" != - ]]; then cl "$2"; out+="$p$REPLY | symbolize=false"$'\n'; fi
    if via_text "$3"; then out+="$p$REPLY | symbolize=false"$'\n'; fi
    REPLY="$out"
}
# via_text VIA — REPLY = how an MCP server is started, from the launcher its
# command line shows (job rows' via); false when it shows none.
via_text() {
    case "$1" in
        lazy-idle)     REPLY="via mcp-lazy: not started, starts on its first tool call" ;;
        lazy)          REPLY="via mcp-lazy: starts on its first tool call" ;;
        npx)           REPLY="via npx (adds an npm wrapper process)" ;;
        pnpm)          REPLY="via pnpm dlx" ;;
        bunx|uvx)      REPLY="via $1" ;;
        docker|podman) REPLY="via $1 run (the container's own memory is not counted)" ;;
        *)             REPLY=""; return 1 ;;
    esac
}
# job_submenu JOB PROCS KIND ROOT START NAME UNIT [ABOUT VIA] — under a
# session's share of a job (or one MCP server): Jump to session, what it is
# and where (and for an MCP server, who configured it and how it starts:
# mcp_about), Peek and Details (of the MCP server itself, else of the
# session), and Kill tree for a stale one. Sets SUB, one level deeper
# ("----").
job_submenu() {
    local job="$1" n="$2" kind="$3" root="$4" start="$5" name="$6" unit="$7" t="" d v s es=es
    SUB=""
    tok "$root" "$start" && t="$REPLY"
    [[ -n "$t" ]] || return 0
    d="$t"
    if [[ "$name" != - && "$unit" != "$root" ]] && num "$unit"; then
        v="U_start_$unit"; d="$unit"; tok "$unit" "${!v-}" && d="$REPLY"
    fi
    if [[ "$kind" != - && "$kind" != daemon ]]; then jump_item "$t"; SUB+="--$REPLY"$'\n'; fi
    job_label "$job"; s="$REPLY"
    [[ "$name" == - ]] || { cl "$name"; s="MCP server $REPLY"; }
    [[ "$n" == 1 ]] && es=""
    s+=" · $n process$es"
    case "$kind" in
        -)      s+=" · stale: its session ended" ;;
        daemon) s+=" · the codex daemon" ;;
        *)      cl "$kind"; s+=" · $REPLY $root"; where_text "$root"; [[ -z "$REPLY" ]] || s+=" · $REPLY" ;;
    esac
    SUB+="----$s | symbolize=false"$'\n'
    mcp_about "----" "${8:--}" "${9:--}"; SUB+="$REPLY"
    local keep="$SUB"
    SUB=""; look_items "$d" "$root"
    SUB="$keep--${SUB//$'\n'--/$'\n'----}"
    SUB="${SUB%----}"
    [[ "$kind" != - ]] || SUB+="----Kill tree | $ACT param1=kill param2=-y param3=--notify param4=$t sfimage=xmark.octagon"$'\n'
}
job_rows_menu() {
    local tag job cpu rss n proj kind root start cwd name unit about via line sym click d named
    while IFS=$'\t' read -r tag job cpu rss n proj kind root start cwd name unit about via; do
        case "$tag" in
            J)  job_symbol "$job"; sym="$REPLY"; job_label "$job"; line="$REPLY · ${cpu}%"; memv "${rss:-0}"
                put "$line · $REPLY | sfimage=$sym $ROW symbolize=false"
                # The size is memory, which "1.2G" alone does not say.
                [[ "$job" != mcp ]] || put "--memory in use now (RSS), not data sent | size=11 symbolize=false" ;;
            G)  # An MCP server in several sessions (proj: its copies, kind:
                # the stale ones), who configured it and how it starts, then
                # its copies (C).
                # Every copy an mcp-lazy proxy whose server never started:
                # proxies, not copies of the server.
                cl "$name"; line="$REPLY · $proj copies"
                [[ "$via" != lazy-idle ]] || line="$REPLY · $proj lazy proxies"
                [[ "$kind" == 0 ]] || line+=", $kind stale"
                [[ "$via" != lazy-idle ]] || line+=" · server not started"
                memv "${rss:-0}"; put "--$line · ${cpu}% · $REPLY | $ROW symbolize=false"
                mcp_about "----" "${about:--}" "${via:--}"; OUT+="$REPLY"
                put "-------" ;;
            S|C) # An MCP server running once: server · project; a copy of
                # one (C, a level deeper) or anything else: project · kind.
                d="--" named=""
                [[ "$tag" == C ]] && d="----"
                [[ "$tag" == S && -n "$name" && "$name" != - ]] && named=1
                line=""
                [[ -z "$named" ]] || { cl "$name"; line="$REPLY · "; }
                cl "${proj:--}"; line+="$REPLY"
                case "$kind" in
                    -)      line+=" · stale" ;;
                    daemon) line+=" · codex daemon" ;;
                    *)      [[ -n "$named" ]] || { cl "$kind"; line+=" · $REPLY"; } ;;
                esac
                memv "${rss:-0}"; line+=" · ${cpu}% · $REPLY"
                click="$ROW"
                tok "$root" "$start" && [[ "$cwd" != - ]] && click="$NOREF param1=reveal param2=$REPLY"
                put "$d$line | $click symbolize=false"
                job_submenu "$job" "$n" "$kind" "$root" "$start" "$name" "${unit:--}" "${about:--}" "${via:--}"
                [[ "$tag" == S ]] || { SUB="--${SUB//$'\n'/$'\n'--}"; SUB="${SUB%--}"; }
                OUT+="$SUB" ;;
        esac
    done < <(job_lines)
}

# indent_out — OUT, one submenu level down.
indent_out() { [[ -z "$OUT" ]] || { OUT="--${OUT//$'\n'/$'\n'--}"; OUT="${OUT%--}"; }; }

# today_summary — REPLY: Today's row: the time sessions blocked, the CPU-hours and
# the job they went to, each when there is any; "" when nothing is known yet.
today_summary() {
    local line="" t
    if num "$wait_blocked" && [[ $wait_blocked -ge 60 ]]; then
        if [[ $wait_blocked -lt 5400 ]]; then line="$((wait_blocked / 60)) min blocked"
        else t=$(( (wait_blocked + 180) / 360 )); line="$((t / 10)).$((t % 10)) h blocked"; fi
    fi
    if num "$hist_total" && [[ $hist_total -gt 0 ]]; then
        if [[ $hist_total -ge 3600 ]]; then
            t=$(( (hist_total + 180) / 360 )); line+="${line:+ · }$((t / 10)).$((t % 10)) CPU-h"
        elif [[ $hist_total -ge 60 ]]; then line+="${line:+ · }$((hist_total / 60)) CPU-min"
        else line+="${line:+ · }<1 CPU-min"; fi
        if num "$hist_top_s" && [[ "$hist_top" =~ ^[a-z]+$ ]]; then
            job_label "$hist_top"; line+=" · $REPLY $(( (hist_top_s * 100 + hist_total / 2) / hist_total ))%"
        fi
    fi
    REPLY="$line"
}

# Today: one row, its submenu the day and the moment: where the CPU goes now,
# today's tokens, denials and compactions, the top insight, and the report.
section_today() {
    local line sub="" tip q="'" keep
    today_summary; line="$REPLY"
    if [[ -n "$job_rows" ]]; then
        put "Where the CPU goes | size=11"
        job_rows_menu
    fi
    today_lines
    # Today's top insight (from insight.txt, which `agents sample` refreshes):
    # what it found as the label (the text before " — ", at most 70
    # characters, cut at a word), the whole sentence with its advice as the
    # tooltip; a click opens its view of the report (one of the fixed views),
    # for today, as the insight is.
    case "$hist_state:$insight_view" in
        ok:summary|ok:runs|ok:waste|ok:trends|ok:agents|ok:tokens|ok:denials|ok:waits|due:summary|due:runs|due:waste|due:trends|due:agents|due:tokens|due:denials|due:waits)
            if [[ -n "$insight_text" ]]; then
                cl "${insight_text//\`/}"
                tip="${REPLY//\"/$q}" sub="${REPLY%% — *}"
                [[ ${#sub} -le 70 ]] || { sub="${sub:0:67}"; sub="${sub% *}..."; }
                put "$sub | $TERM_OPEN param2=--hold param3=report param4=--view param5=$insight_view param6=--since param7=today tooltip=\"$tip\" sfimage=lightbulb symbolize=false"
            fi ;;
    esac
    [[ -n "$OUT" || "$hist_state" == ok || "$hist_state" == due ]] || return 0
    # Today's, like the rows above it (agents report alone covers the last 24h).
    if [[ "$hist_state" == ok || "$hist_state" == due ]]; then
        put "Open report | $TERM_OPEN param2=--hold param3=report param4=--since param5=today sfimage=doc.text.magnifyingglass"
    fi
    indent_out; keep="$OUT"; OUT=""
    put "Today: ${line:-nothing recorded yet (a sample a minute)} | sfimage=chart.bar.xaxis $TERM_OPEN param2=--hold param3=report param4=--since param5=today symbolize=false"
    OUT+="$keep"
}

# --- Limits and memory ---------------------------------------------------------------
# One row per CLI window that has not reset, a gauge drawn in a monospaced font
# (`Claude 5h ██▎░░░░░│░░░ 23%`), the marker where the time gone in that window
# is, from the limit and pace rows (`agents limits` has them all, with how old
# each reading is). Each account is a CLI of its own (Claude, then Claude (work):
# cli claude:work), and a CLI whose quotas go by model (USAGE_BY_MODEL) has one
# row per window, its highest model's, the rest in the row's submenu. The symbol
# turns the warn tint from 80% or over pace, the need tint from 95% (and the icon
# with it: bar_title), gray while nothing is used. Swap joins them only while it
# is high.
MONO="font=Menlo size=12"

# CLIs (limits.tsv's family, the cli before its ":") whose cli FAMILY:NAME
# rows are quotas per model, not accounts.
USAGE_BY_MODEL="agy"
LIMITS="$TERM_OPEN param2=--hold param3=limits"
TODAY_VIEW="$TERM_OPEN param2=--hold param3=report param4=--view"

# wmin WINDOW — REPLY: a window's length in minutes (5h, day, week, month,
# 3d, 2h, 90m), to order a line's windows; anything else sorts last.
wmin() {
    local n="${1%?}" u=0
    case "$1" in
        day)   REPLY=1440; return ;;
        week)  REPLY=10080; return ;;
        month) REPLY=43200; return ;;
        *d) u=1440 ;; *h) u=60 ;; *m) u=1 ;;
    esac
    if [[ $u -gt 0 && ${#n} -le 6 ]] && num "$n"; then REPLY=$((n * u)); else REPLY=99999999; fi
}
# wshort WINDOW — REPLY: the window as a CLI's line names it (wk, mo).
wshort() { case "$1" in week) REPLY=wk ;; month) REPLY=mo ;; *) REPLY="$1" ;; esac; }
# gauge PCT PACE — REPLY: the gauge for a share used, as item params: its needle
# (the nearest of 0, 33, 50, 67 and 100%), tinted warn from 80% or over pace, need
# from 95%, gray at 0%.
gauge() {
    local p="$1" s=0
    if [[ $p -ge 84 ]]; then s=100
    elif [[ $p -ge 59 ]]; then s=67
    elif [[ $p -ge 42 ]]; then s=50
    elif [[ $p -ge 17 ]]; then s=33; fi
    REPLY="sfimage=gauge.with.dots.needle.${s}percent"
    if [[ $p -ge 95 ]]; then REPLY+=" $TINT_NEED"
    elif [[ $p -ge 80 || "${2:-}" == over ]]; then REPLY+=" $TINT_WARN"
    elif [[ $p -eq 0 ]]; then REPLY+=" $TINT_IDLE"; fi
}

# usage_lines — the limit rows. Groups go by index (U*_N: key, title, how many
# windows, the oldest reading), each window by group and index (UW/UP/UR/UE/UV/UL/
# UB/US_N_M: its name, highest %, that one's reset, the time gone, its pace, the
# seconds left, the bar and the submenu); bash 3.2 has no associative arrays. One
# pass over the rows, then one over the groups: no subshell, no fork.
usage_lines() {
    local name win pct rst cli age pv left bar fam key title model i j k n x ng=0 v p w line used best bm lw=0 lab sub
    while IFS=$'\t' read -r name win pct rst cli age _ pv left bar; do
        num "$pct" || continue
        [[ -n "$win" ]] || continue
        fam="${cli%%:*}" key="$cli"
        [[ -n "$cli" && "$cli" != - ]] || { fam="$name" key="$name"; }
        case " $USAGE_BY_MODEL " in *" $fam "*) key="$fam" ;; esac
        # A model's quota (agy:gemini, named "Antigravity · Gemini").
        model=""
        [[ "$key" != "$cli" && "$name" == *" · "* ]] && model="${name#* · }"
        i=0
        for ((j = 1; j <= ng; j++)); do v="UK_$j"; [[ "${!v}" == "$key" ]] && { i=$j; break; }; done
        if [[ $i -eq 0 ]]; then
            ng=$((ng + 1)); i=$ng
            # Claude · work (cli claude:work) reads Claude (work).
            title="$name"
            if [[ "$key" != "$cli" ]]; then title="${name%% · *}"
            elif [[ "$key" == *:* && "$name" == *" · "* ]]; then title="${name%% · *} (${name#* · })"; fi
            cl "$title"
            printf -v "UK_$i" '%s' "$key"; printf -v "UT_$i" '%s' "$REPLY"
            printf -v "UN_$i" '%d' 0; printf -v "UA_$i" '%d' 0
        fi
        v="UN_$i"; n="${!v}"; k=0
        for ((j = 1; j <= n; j++)); do v="UW_${i}_$j"; [[ "${!v}" == "$win" ]] && { k=$j; break; }; done
        if [[ $k -eq 0 ]]; then
            n=$((n + 1)); k=$n
            printf -v "UN_$i" '%d' "$n"; printf -v "UW_${i}_$k" '%s' "$win"; printf -v "UP_${i}_$k" '%d' -1; printf -v "US_${i}_$k" '%s' ""
        fi
        v="UP_${i}_$k"
        if [[ $pct -gt ${!v} ]]; then
            printf -v "$v" '%d' "$pct"; printf -v "UR_${i}_$k" '%s' "$rst"
            printf -v "UV_${i}_$k" '%s' "${pv:--}"; printf -v "UL_${i}_$k" '%s' "${left:--}"; printf -v "UB_${i}_$k" '%s' "$bar"
        fi
        v="UA_$i"; if num "$age" && [[ $age -gt ${!v} ]]; then printf -v "$v" '%d' "$age"; fi
        # A model's line in the window's submenu.
        if [[ -n "$model" ]]; then
            cl "$model"; line="$REPLY $pct%"
            [[ "$rst" == - || -z "$rst" ]] || { cl "$rst"; line+=" · resets $REPLY"; }
            gauge "$pct" "$pv"; v="US_${i}_$k"
            printf -v "$v" '%s%s' "${!v}" "--$line | $REPLY $LIMITS symbolize=false"$'\n'
        fi
        wshort "$win"; cl "$title $REPLY"; [[ ${#REPLY} -le $lw ]] || lw=${#REPLY}
    done <<<"$usage_rows"
    [[ -z "$swap_pct" || $lw -ge 9 ]] || lw=9
    for ((i = 1; i <= ng; i++)); do
        v="UN_$i"; n="${!v}"; used=" "
        for ((x = 1; x <= n; x++)); do   # its windows, shortest first
            best=0 bm=0
            for ((j = 1; j <= n; j++)); do
                [[ "$used" == *" $j "* ]] && continue
                v="UW_${i}_$j"; wmin "${!v}"
                if [[ $best -eq 0 || $REPLY -lt $bm ]]; then best=$j bm=$REPLY; fi
            done
            used+="$best "
            v="UT_$i"; w="${!v}"; v="UW_${i}_$best"; win="${!v}"; wshort "$win"; cl "$w $REPLY"; lab="$REPLY"
            v="UP_${i}_$best"; p="${!v}"; v="UV_${i}_$best"; pv="${!v}"; v="UL_${i}_$best"; left="${!v}"; v="UB_${i}_$best"; bar="${!v}"
            gauge "$p" "$pv"; sub="$REPLY"
            if [[ -n "$bar" ]]; then
                printf -v line '%-*s %s %3d%%' "$lw" "$lab" "$bar" "$p"
                put "$line | $sub $MONO $LIMITS symbolize=false"
            else
                # An older `agents`: no bar to draw.
                put "$lab $p% | $sub $LIMITS symbolize=false"
            fi
            # Its reset and pace, then what it folds, then how old the reading is.
            v="UR_${i}_$best"; line=""
            [[ "${!v}" == - || -z "${!v}" ]] || { cl "${!v}"; line="resets $REPLY"; }
            case "$pv" in
                under) line+="${line:+ · }under pace" ;;
                over)  line+="${line:+ · }over pace"
                       if num "$left"; then longv "$left"; line+=", $REPLY left at this rate"; fi ;;
            esac
            [[ -z "$line" ]] || put "--$line | $LIMITS symbolize=false"
            v="US_${i}_$best"; OUT+="${!v}"
            v="UA_$i"
            if [[ ${!v} -lt 60 ]]; then put "--updated just now | size=11"
            else agev "${!v}"; put "--updated $REPLY ago | size=11"; fi
        done
    done
    [[ -n "$swap_pct" ]] || return 0
    printf -v line '%-*s %s %3d%%' "$lw" Swap "$swap_bar" "$swap_pct"
    put "$line | sfimage=memorychip $TINT_WARN $MONO $TERM_OPEN param2=--hold param3=mem symbolize=false"
    memv "$swap_used"; line="$REPLY"; memv "$swap_total"
    put "--$line of $REPLY in use: what fills up before a guard stop | size=11"
}

# today_lines — today's tokens, denials and compactions, each opening its view of
# today's report. Nothing when there is none of them.
today_lines() {
    local s top=""
    if num "$tok_total" && num "$tok_cache" && [[ $tok_total -gt 0 ]]; then
        humanize "$tok_total"
        put "$REPLY tokens · ${tok_cache}% read from the prompt cache | $TODAY_VIEW param5=tokens param6=--since param7=today sfimage=text.bubble symbolize=false"
    fi
    if [[ $n_denials -gt 0 ]]; then
        s=s; [[ $n_denials -eq 1 ]] && s=""
        [[ "$denials_top" == - || -z "$denials_top" ]] || { cl "$denials_top"; top=" · top: $REPLY"; }
        put "$n_denials denial$s$top | $TODAY_VIEW param5=denials param6=--since param7=today sfimage=hand.raised symbolize=false"
    fi
    if [[ $n_compacts -gt 0 ]]; then
        s=s; [[ $n_compacts -eq 1 ]] && s=""
        put "$n_compacts context compaction$s | $TODAY_VIEW param5=tokens param6=--since param7=today sfimage=arrow.down.right.and.arrow.up.left symbolize=false"
    fi
}

section_limits() {
    [[ -n "$usage_rows" || -n "$swap_pct" ]] || return 0
    put "Limits and memory | size=12"
    usage_lines
}

section_stale() {
    [[ $n_stale -gt 0 ]] || return 0
    put "Stale ($n_stale) | size=12"
    OUT+="$stale_menu"
    # Exactly the processes listed above, not whatever is stale at click time.
    local params="param1=kill param2=-y param3=--notify" i=4 tk
    for tk in $stale_tokens; do params+=" param$i=$tk"; i=$((i + 1)); done
    put "Reap all stale | $ACT $params sfimage=trash"
}

section_hogs() {
    [[ $n_hogs -gt 0 ]] || return 0
    put "Hogs ($n_hogs) | size=12"
    OUT+="$hogs_menu"
}

# now_s — the epoch in NOW_S, read once (bash 3.2 has no $EPOCHSECONDS).
now_s() { [[ -n "${NOW_S:-}" ]] || NOW_S="$(date +%s)"; }
# left_text SECS PREFIX — REPLY = "PREFIX<1m left" or "PREFIX2h5m left".
left_text() { if [[ $1 -lt 60 ]]; then REPLY="$2<1m left"; else agev "$1"; REPLY="$2$REPLY left"; fi; }
# ck MODE — REPLY = " checked=true" for the active keep-awake mode.
ck() { REPLY=""; [[ "$awake_mode" == "$1" ]] && REPLY=" checked=true"; return 0; }

section_awake() {
    local text sym=cup.and.saucer
    case "$awake_mode" in
        off)    text="Awake: off" ;;
        agents) text="Awake: while agents run" ;;
        timed|lid) num "$awake_until" || awake_until=0
                now_s; left_text $((awake_until - NOW_S)) "Awake: "; text="$REPLY" ;;
        *)      text="Awake: on until turned off" ;;
    esac
    # Lid mode reads its time from the guard's record.
    if [[ "$lid_state" == on ]]; then
        num "$lid_until" || lid_until=0
        now_s; left_text $((lid_until - NOW_S)) "Awake: lid closed · "; text="$REPLY"; sym=laptopcomputer
    fi
    if [[ "$lid_state" == stale ]]; then
        put "Lid sleep disabled, nothing restores it | sfimage=exclamationmark.triangle.fill $TINT_NEED $ROW"
        put "Restore lid sleep… | $ACT param1=awake param2=restore param3=--notify sfimage=lock.open"
    fi
    put "$text | sfimage=$sym $ROW"
    ck on; put "--Until turned off | $ACT param1=awake param2=on$REPLY"
    put "--For 1 hour | $ACT param1=awake param2=on param3=1h"
    put "--For 3 hours | $ACT param1=awake param2=on param3=3h"
    ck agents; put "--While agents run | $ACT param1=awake param2=agents$REPLY"
    # Lid mode (AGENTS_LID=0 hides it): disables lid sleep as root, time-boxed,
    # after a password dialog. Results come back as notifications (--notify):
    # a menu action has no terminal.
    if [[ "$BAR_LID" == 1 ]]; then
        put "--Lid closed too… | sfimage=laptopcomputer $ROW"
        num "$lid_max" || lid_max=28800
        [[ $lid_max -ge 3600 ]] && put "----For 1 hour | $ACT param1=awake param2=lid param3=1h param4=--notify"
        [[ $lid_max -ge 10800 ]] && put "----For 3 hours | $ACT param1=awake param2=lid param3=3h param4=--notify"
        [[ $lid_max -ge 28800 ]] && put "----For 8 hours | $ACT param1=awake param2=lid param3=8h param4=--notify"
        put "----Asks for your password; restores on timeout or low battery | size=11"
    fi
    ck off; put "--Off | $ACT param1=awake param2=off$REPLY"
    put "-----"
    put "--Who holds the Mac awake? | $TERM_OPEN param2=--hold param3=awake param4=status"
    if [[ "$lid_state" == on ]]; then
        put "End lid mode now… | $ACT param1=awake param2=off param3=--notify sfimage=laptopcomputer.slash"
    fi
}

# System: one row, CPU, memory and thermal pressure, opening agents watch. A
# warning tints its symbol, and says so on the row; the rest is in its submenu:
# the load, the busiest processes (each opens Activity Monitor), battery and energy
# mode (opens System Settings › Battery, where Energy Mode lives), the Codex
# daemon, the memory guard and the fans.
section_system() {
    local used="" line look="sfimage=cpu" bolt="" keep s
    num "$memfree" && used=" · Mem $((100 - memfree))%"
    line="CPU ${cpu}%$used · Thermal $thermal_name"
    if num "$thermal" && [[ $thermal -ge 2 ]]; then look="sfimage=thermometer.medium $TINT_NEED"; fi
    case "$mempress" in
        warn)     line+=" · memory pressure"; look="sfimage=memorychip $TINT_WARN" ;;
        critical) line+=" · memory pressure critical"; look="sfimage=memorychip $TINT_NEED" ;;
    esac
    if [[ "$mem_state" == stopped ]]; then line+=" · guard not running"; look="sfimage=shield.slash $TINT_WARN"; fi
    if [[ "$cool_state" == stale ]]; then line+=" · fan control stopped"; look="sfimage=fan $TINT_WARN"; fi
    put "$line | $look $TERM_OPEN param2=watch"
    put "--Load $load/$cores | size=11"
    if [[ -n "$top_menu" ]]; then
        put "--Busiest processes | size=11"
        OUT+="$top_menu"
    fi
    put "-----"
    s=thermometer.medium
    if num "$batt"; then
        charging "$bstate" && bolt=" :bolt.fill:"
        battery_symbol "$batt" "$bstate"; s="$REPLY"
        put "--Battery ${batt}%$bolt · Energy $power | sfimage=$s $CALLBACK param1=battery-settings"
    else
        put "--Energy $power | sfimage=$s $CALLBACK param1=battery-settings"
    fi
    keep="$OUT"; OUT="$daemon_menu"
    section_memguard
    section_fans
    indent_out
    OUT="$keep$OUT"
}

# The memory guard: on (with the size it stops a runaway at), not running
# (with Start), or off; then its last incident, and the memory view.
section_memguard() {
    local line ago=""
    case "$mem_state" in
        on)      memv "${mem_stop:-0}"; line="Memory guard: on · stops agent runaways at $REPLY | sfimage=shield.lefthalf.filled $TERM_OPEN param2=--hold param3=mem" ;;
        stopped) line="Memory guard not running | sfimage=shield.slash $TINT_WARN $TERM_OPEN param2=--hold param3=mem" ;;
        off)     line="Memory guard: off (AGENTS_MEM_GUARD) | sfimage=shield.slash $TINT_IDLE $TERM_OPEN param2=--hold param3=mem" ;;
        *)       line="Memory guard: not set up (agents mem guard) | sfimage=shield.slash $TINT_IDLE $TERM_OPEN param2=--hold param3=mem" ;;
    esac
    put "$line"
    [[ "$mem_state" != stopped ]] || put "--Start it | $ACT param1=mem param2=restart sfimage=play.circle"
    if num "$mem_last" && [[ $mem_last -gt 0 ]]; then
        now_s; agev $((NOW_S - mem_last)); ago="$REPLY"
        cl "$mem_what"; line="$REPLY"
        [[ "$mem_proj" == - ]] || { cl "$mem_proj"; line+=" in $REPLY"; }
        num "$mem_fp" && { memv "$mem_fp"; line+=" · $REPLY"; }
        case "$mem_ev" in
            stop)     line="Stopped $line" ;;
            refused)  line="Could not stop $line" ;;
            grow)     line="Growing fast: $line" ;;
            pressure) line="Pressure critical, biggest: $line" ;;
            *)        line="Warned: $line" ;;
        esac
        put "--$line · $ago ago | symbolize=false size=11"
    fi
    put "--Memory view (agents mem) | $TERM_OPEN param2=--hold param3=mem sfimage=memorychip"
}

# Fans (--pack cooling only): the speed, the SoC's temperature and the mode,
# with Cool, Balanced, Quiet, Max and Off. Changing the mode needs no password: the root
# daemon reads a file you can write, and clamps what it holds.
cool_ck() { REPLY=""; [[ "$cool_mode" == "$1" ]] && REPLY=" checked=true"; return 0; }
section_fans() {
    local line rpm="" r m
    case "$cool_state" in
        on) ;;
        stale) put "Fan control stopped (the daemon isn't running) | sfimage=fan $TINT_WARN $ROW"
               put "--Start it: sudo launchctl bootstrap system /Library/LaunchDaemons/dev.tuidev.fan.plist | size=11"
               put "--Its log: /var/log/tuidev-fan.log | size=11"
               return ;;
        *)  return ;;
    esac
    # The fastest fan stands for them all (a MacBook Pro's two run together).
    IFS=, read -r -a r <<<"$cool_rpms"
    for m in ${r[@]+"${r[@]}"}; do num "$m" && { [[ -z "$rpm" || $m -gt $rpm ]] && rpm="$m"; }; done
    line="Fans ${rpm:-?} rpm"
    num "$cool_soc" && line+=" · SoC ${cool_soc} °C"
    local name
    case "$cool_mode" in
        cool|auto|quiet)
              name="$cool_mode"; [[ "$name" == auto ]] && name=balanced
              if [[ "$cool_ctl" == tuidev ]]; then line+=" · $name"; else line+=" · $name (macOS below ${cool_low} °C)"; fi ;;
        max)  line+=" · max" ;;
        off)  line+=" · macOS" ;;
    esac
    put "$line | sfimage=fan $ROW"
    # checked=true is a parameter (after the |): SwiftBar draws the checkmark.
    cool_ck cool;  put "--Cool: palms first (from 55 °C) | $ACT param1=cool param2=cool param3=--notify$REPLY"
    cool_ck auto;  put "--Balanced (from 60 °C) | $ACT param1=cool param2=auto param3=--notify$REPLY"
    cool_ck quiet; put "--Quiet (from 70 °C) | $ACT param1=cool param2=quiet param3=--notify$REPLY"
    cool_ck max;   put "--Max: full speed | $ACT param1=cool param2=max param3=--notify$REPLY"
    cool_ck off;   put "--Off: macOS runs them | $ACT param1=cool param2=off param3=--notify$REPLY"
    put "--Fans follow the chip's temperature averaged over minutes, as your palms feel it | size=11"
    case "$cool_mode" in cool|auto|quiet) put "--Now: minimum at ${cool_low} °C, full speed at ${cool_high} °C | size=11" ;; esac
    put "-----"
    put "--Fan status | $TERM_OPEN param2=--hold param3=cool param4=status"
}

# sections_now — BAR_SECTIONS as sections today: the names before the triage still
# work (agents is running and parked, usage is limits, jobs is today), and a list
# of only those, the old default among them, reads as the new layout: Needs you
# held the finished sessions too, and Agents every session.
sections_now() {
    local s a out=" " names=" $BAR_SECTIONS " old=1 add
    case "$names" in *" review "*|*" running "*|*" parked "*|*" limits "*|*" today "*) old="" ;; esac
    for s in $BAR_SECTIONS; do
        add="$s"
        case "$s" in
            agents) add="running parked"
                    [[ -z "$old" || "$names" == *" needs "* ]] || add="needs review running parked" ;;
            usage)  add=limits ;;
            jobs)   add=today ;;
            needs)  [[ -z "$old" ]] || add="needs review" ;;
        esac
        for a in $add; do [[ "$out" == *" $a "* ]] || out+="$a "; done
    done
    REPLY="$out"
}

bar_title
sections_now
last_group=""
for section in $REPLY; do
    OUT=""
    case "$section" in
        needs|review|running|parked|limits|today|stale|hogs|awake|system) "section_$section" ;;
    esac
    while [[ "$OUT" == *$'\n' ]]; do OUT="${OUT%$'\n'}"; done
    [[ -n "$OUT" ]] || continue
    # The sessions read as one block, and so do Awake and the system row.
    case "$section" in
        needs|review|running|parked) group=sessions ;;
        awake|system) group=machine ;;
        *) group="$section" ;;
    esac
    [[ "$group" == "$last_group" ]] || echo "---"
    last_group="$group"
    printf '%s\n' "$OUT"
done
echo "---"
# Maintenance first in the footer: small and gray, everything in its submenu.
if [[ $n_maint -gt 0 ]]; then
    echo "Maintenance ($n_maint) | size=12 sfimage=wrench.and.screwdriver $TINT_IDLE $ROW"
    printf '%s' "$maint_menu"
fi
echo "Open agents watch | $TERM_OPEN param2=watch sfimage=rectangle.and.text.magnifyingglass"
echo "--Full table (agents ls) | $TERM_OPEN param2=--hold param3=ls sfimage=tablecells"
[[ -n "$CONF" && -f "$CONF" ]] && echo "--Edit settings… | $NOREF param1=config param2=--edit sfimage=slider.horizontal.3"
echo "Refresh | refresh=true sfimage=arrow.clockwise"
