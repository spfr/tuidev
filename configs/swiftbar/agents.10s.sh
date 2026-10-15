#!/bin/bash
# <xbar.title>agents</xbar.title>
# <xbar.version>v1.3</xbar.version>
# <xbar.desc>Agentic-coding sessions (blocked first), where their CPU goes, stale helpers, CPU hogs, keep-awake and a compact system view, from tuidev's `agents` command.</xbar.desc>
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

ORANGE="#FF9F0A" RED="#FF453A"   # the title icon's tint (sfcolor works there)
# Menu-item symbols take their color only from sfconfig (base64 JSON, Palette
# mode); sfcolor colors inline :symbols: in titles, not an item's sfimage.
# These are {"renderingMode":"Palette","colors":["#RRGGBB"]} for each color.
DOT_GREEN="sfconfig=eyJyZW5kZXJpbmdNb2RlIjoiUGFsZXR0ZSIsImNvbG9ycyI6WyIjMzBEMTU4Il19"
DOT_ORANGE="sfconfig=eyJyZW5kZXJpbmdNb2RlIjoiUGFsZXR0ZSIsImNvbG9ycyI6WyIjRkY5RjBBIl19"
DOT_GRAY="sfconfig=eyJyZW5kZXJpbmdNb2RlIjoiUGFsZXR0ZSIsImNvbG9ycyI6WyIjOEU4RTkzIl19"
DOT_RED="sfconfig=eyJyZW5kZXJpbmdNb2RlIjoiUGFsZXR0ZSIsImNvbG9ycyI6WyIjRkY0NTNBIl19"
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
# memv KIB, agev SECS — a size and an age for people, in REPLY.
memv() { if [[ $1 -ge 1048576 ]]; then REPLY="$(($1 * 10 / 1048576 / 10)).$(($1 * 10 / 1048576 % 10))G"; else REPLY="$(($1 / 1024))M"; fi; }
agev() {
    local s="$1"
    if [[ $s -lt 3600 ]]; then REPLY="$((s / 60))m"
    elif [[ $s -lt 86400 ]]; then REPLY="$((s / 3600))h$(((s % 3600) / 60))m"
    else REPLY="$((s / 86400))d$(((s % 86400) / 3600))h"; fi
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
n_agents=0 n_blocked=0 n_stale=0 n_hogs=0
needs_menu="" agents_menu="" daemon_menu="" stale_menu="" hogs_menu="" top_menu="" stale_tokens=""
awake_mode=off awake_until=0 thermal=- thermal_name=unknown power=unknown
lid_state=off lid_until=0 lid_max=28800 BAR_LID=1
cpu=- load=- cores=- memfree=- mempress=- batt=- bstate=-
BAR_TITLE="count awake" BAR_SECTIONS="needs agents jobs stale hogs awake system" BAR_ICON=terminal CONF=""
job_rows="" mcp_cfg="" hist_state="" hist_total=0 hist_top=- hist_top_s=0 insight_view="" insight_text="" tok_total=0 tok_cache=0

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

# --- Needs you: verdicts ------------------------------------------------------------
# `agents tsv` starts with a verdict for each item that needs you (need rows,
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

# need_item SYMBOL TEXT TOKEN — one command in Needs you: its verdict at a
# glance on the line (orange for safe to stop and check first, gray for leave
# it and informational), the rest in its submenu. Appends to needs_menu.
need_item() {
    local p="${3%%@*}" v dot="$DOT_ORANGE" stop
    stop="--Stop command… | $ACT param1=kill param2=--confirm-gui param3=--notify param4=$3 sfimage=xmark.octagon"
    v="N_short_$p"
    if [[ -z "${!v-}" ]]; then
        needs_menu+="$2 | sfimage=$1 $DOT_ORANGE $ROW symbolize=false"$'\n'"$stop"$'\n'
        return 0
    fi
    cl "${!v}"; v="N_act_$p"
    [[ "${!v-}" == stop || "${!v-}" == check ]] || dot="$DOT_GRAY"
    needs_menu+="$2 · $REPLY | sfimage=$1 $dot $ROW symbolize=false"$'\n'
    need_submenu "$p" "$3" "$stop"
    needs_menu+="$SUB"
}

n_auto=0 BAR_AUTO=0
agent_rows=()
while IFS=$'\t' read -r type pid kind age_s pcpu avg rss kids start ports user herdr cwd args project aflags adup; do
    case "$type" in
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
                    if [[ ",$aflags," == *,stuck,* ]]; then fl+=" · stuck"; look=" sfimage=hourglass $DOT_ORANGE"
                    elif [[ ",$aflags," == *,wait,* ]]; then fl+=" · waiting"; look=" sfimage=hourglass $DOT_GRAY"; fi
                    sh60 "$args"; c="$REPLY"; agev "$age_s"; a="$REPLY"; cl "$project"
                    aadd tools "$r" "--$c · $a · ${pcpu%%.*}% · $REPLY$fl | $ROW$look symbolize=false"$'\n'"----Stop command… | $ACT param1=kill param2=--confirm-gui param3=--notify param4=$t sfimage=xmark.octagon"$'\n'
                    anum ntools "$r" 1; anum tcpu "$r" "${pcpu%%.*}"
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
        hog)
            n_hogs=$((n_hogs + 1))
            cl "$kind"; hogs_menu+="$REPLY · ${pcpu}% now · ${avg}% avg | $ROW symbolize=false sfimage=flame"$'\n'
            cl "$user"; c="$REPLY"; agev "$age_s"; a="$REPLY"; memv "$rss"
            hogs_menu+="--pid $pid · $c · up $a · $REPLY | symbolize=false"$'\n'
            if [[ "$user" == "$me" ]] && tok "$pid" "$start"; then
                hogs_menu+="--Terminate (SIGTERM) | $ACT param1=term param2=-y param3=--notify param4=$REPLY sfimage=xmark.octagon"$'\n'
            elif [[ "$user" != "$me" ]]; then
                hogs_menu+="--Owned by $c: run sudo kill $pid in a terminal | symbolize=false"$'\n'
            fi
            ;;
        top)     cl "$kind"; c="$REPLY"; memv "$rss"
                 top_menu+="--$c · ${pcpu}% · $REPLY | $CALLBACK param1=activity-monitor symbolize=false"$'\n' ;;
        sys)     cpu="$pid"; load="$kind"; cores="$age_s"; memfree="$pcpu"; mempress="$avg"; batt="$rss"; bstate="$kids" ;;
        awake)   awake_mode="$pid"; awake_until="$age_s" ;;   # awake MODE PID UNTIL
        thermal) thermal="$pid"; thermal_name="$kind" ;;
        power)   power="$pid" ;;
        lid)     lid_state="$pid"; lid_until="$age_s"; lid_max="$pcpu" ;;   # lid STATE PID UNTIL MAX
        # job ROOT JOB 0 CPU 0 RSS PROCS START own|sub UNIT KIND CWD NAME PROJECT VIA
        # (NAME and VIA: the MCP server's name and launcher for the mcp job, else "-")
        job)     job_rows+="$kind"$'\t'"$pcpu"$'\t'"$rss"$'\t'"$kids"$'\t'"$herdr"$'\t'"$project"$'\t'"$pid"$'\t'"$start"$'\t'"$cwd"$'\t'"$args"$'\t'"$user"$'\t'"${aflags:--}"$'\n' ;;
        # mcpcfg CLI SCOPE NAME SOURCE PROJECT: who configured each MCP server
        mcpcfg)  mcp_cfg+="$pid"$'\t'"$kind"$'\t'"$age_s"$'\t'"$pcpu"$'\t'"$avg"$'\n' ;;
        hist)    hist_state="$pid"; hist_total="$kind"; hist_top="$age_s"; hist_top_s="$pcpu" ;;   # hist STATE TODAY_S TOP TOP_S
        insight) insight_view="$pid"; insight_text="$kind" ;;   # insight VIEW TEXT
        tokens)  tok_total="$pid"; tok_cache="$kind" ;;         # tokens TOTAL CACHE_PCT (today)
        conf)
            [[ "$kind" == - ]] && kind=""
            case "$pid" in
                AGENTS_BAR_TITLE)    BAR_TITLE="$kind" ;;
                AGENTS_BAR_SECTIONS) BAR_SECTIONS="$kind" ;;
                AGENTS_BAR_ICON)     BAR_ICON="${kind:-terminal}" ;;
                AGENTS_LID)          BAR_LID="${kind:-1}" ;;
                AGENTS_CONF)         CONF="$kind" ;;
                AGENTS_AUTO_REAP)    BAR_AUTO="${kind:-0}" ;;
            esac
            ;;
    esac
done <<<"$data"

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

# Second pass: sessions, now that their activity is known. A blocked session,
# a command running twice, a long-running command and a stuck polling loop
# each need a look.
n_attn=0
for row in ${agent_rows[@]+"${agent_rows[@]}"}; do
    IFS=$'\t' read -r pid kind age_s pcpu rss kids start ports herdr cwd project <<<"$row"
    if [[ "$kind" == daemon ]]; then
        memv "$rss"
        daemon_menu+="codex daemon · ${pcpu}% · $REPLY | sfimage=gearshape $ROW symbolize=false"$'\n'
        session_submenu "$pid" "$start" daemon "$age_s" "$kids" "$ports" -
        daemon_menu+="$SUB"
        continue
    fi
    n_agents=$((n_agents + 1))
    cl "${project:--}"; name="$REPLY"; [[ "$name" == - || -z "$name" ]] && name="$kind"
    cl "$kind"; ckind="$REPLY"
    status=""; [[ "$herdr" != - ]] && { cl "$herdr"; status=" · $REPLY"; }
    case "$herdr" in
        blocked)   look="sfimage=exclamationmark.circle.fill $DOT_ORANGE" ;;
        working)   look="sfimage=circle.fill $DOT_GREEN" ;;
        idle|done) look="sfimage=circle.fill $DOT_GRAY" ;;
        *)         look="sfimage=circle" ;;
    esac
    # When its commands use most of the CPU, say so: "346% (tools 300%)".
    v="A_tcpu_$pid"; tc="${!v-}"; hint=""
    [[ -n "$tc" && $tc -ge 20 && $((tc * 2)) -gt ${pcpu%%.*} ]] && hint=" (tools ${tc}%)"
    # Clicking the row itself shows the project in Finder (resolved from
    # PID@START); everything else is in its submenu.
    click="$ROW"
    tok "$pid" "$start" && [[ "$cwd" != - ]] && click="$NOREF param1=reveal param2=$REPLY"
    session_submenu "$pid" "$start" "$kind" "$age_s" "$kids" "$ports" "$cwd" "$herdr"; sub="$SUB"
    memv "$rss"
    agents_menu+="$name · $ckind$status · ${pcpu}%$hint · $REPLY | $look $click symbolize=false"$'\n'"$sub"
    if [[ "$herdr" == blocked ]]; then
        n_blocked=$((n_blocked + 1)); n_attn=$((n_attn + 1))
        needs_menu+="$name · $ckind · waiting for you | sfimage=exclamationmark.circle.fill $DOT_ORANGE $click symbolize=false"$'\n'"$sub"
    fi
    aget dups "$pid"; dup_groups "$REPLY"
    while IFS=$'\t' read -r g cmd toks; do
        [[ -n "$g" ]] || continue
        n_attn=$((n_attn + 1))
        params="param1=kill param2=--confirm-gui param3=--notify"; i=4
        for tk in $toks; do params+=" param$i=$tk"; i=$((i + 1)); done
        sh60 "${cmd#*$'\037'}"
        needs_menu+="$name: ${g}× $REPLY running | sfimage=square.stack.3d.up $DOT_ORANGE $ROW symbolize=false"$'\n'
        needs_menu+="--Stop duplicates (keep newest)… | $ACT $params sfimage=xmark.octagon"$'\n'
    done <<<"$DUPS"
    aget longs "$pid"
    while IFS=$'\t' read -r cmd lage tk; do
        [[ -n "$tk" ]] || continue
        n_attn=$((n_attn + 1))
        sh60 "$cmd"; c="$REPLY"; agev "$lage"
        need_item clock "$name: $c · running $REPLY" "$tk"
    done <<<"$REPLY"
    aget stucks "$pid"
    while IFS=$'\t' read -r cmd lage tk; do
        [[ -n "$tk" ]] || continue
        n_attn=$((n_attn + 1))
        sh60 "$cmd"; c="$REPLY"; agev "$lage"
        need_item hourglass "$name: $c · stuck $REPLY" "$tk"
    done <<<"$REPLY"
done

# Sleep disabled with no guard to restore it (a reboot killed it): a Mac in a
# bag would never sleep. First in Needs you, and the icon turns red.
if [[ "$lid_state" == stale ]]; then
    n_attn=$((n_attn + 1))
    needs_menu="Restore lid sleep (disabled, nothing restores it)… | sfimage=exclamationmark.triangle.fill $DOT_RED $ACT param1=awake param2=restore param3=--notify symbolize=false"$'\n'"$needs_menu"
fi

# --- Title -------------------------------------------------------------------------
# The icon, the session count, and how many sessions wait for you. The icon is
# tinted only when something needs a look: orange for a blocked session, stale
# processes, hogs or memory pressure; red for heavy thermal or critical memory
# pressure.

attention=""
if [[ $n_attn -gt 0 || $n_stale -gt 0 || $n_hogs -gt 0 || "$mempress" == warn ]]; then attention="$ORANGE"; fi
if { num "$thermal" && [[ $thermal -ge 2 ]]; } || [[ "$mempress" == critical || "$lid_state" == stale ]]; then attention="$RED"; fi

bar_title() {
    local t=":$BAR_ICON:" tok
    for tok in $BAR_TITLE; do
        case "$tok" in
            count)   [[ $n_agents -gt 0 ]] && t+=" $n_agents"
                     [[ $n_blocked -gt 0 ]] && t+=" · $n_blocked blocked" ;;
            cpu)     num "$cpu" && t+=" :cpu: ${cpu}%" ;;
            mem)     num "$memfree" && t+=" :memorychip: $((100 - memfree))%" ;;
            load)    [[ "$load" != - ]] && t+=" :gauge.medium: $load" ;;
            battery) num "$batt" && { battery_symbol "$batt" "$bstate"; t+=" :$REPLY: ${batt}%"; } ;;
            thermal) num "$thermal" && [[ $thermal -ge 1 ]] && t+=" :thermometer.medium: $thermal_name" ;;
            awake)   [[ "$awake_mode" != off ]] && t+=" :cup.and.saucer.fill:" ;;
            warn)    [[ -n "$attention" ]] && t+=" :exclamationmark.triangle.fill:" ;;
        esac
    done
    printf '%s' "$t"
    [[ -z "$attention" ]] || printf ' | sfcolor=%s' "$attention"
    printf '\n'
}

# --- Sections (each adds nothing when it has nothing to say) -------------------------
# A section appends its lines to OUT (put LINE), in this shell: no subshell
# per section.

put() { OUT+="$1"$'\n'; }

section_needs() {
    [[ $n_attn -gt 0 ]] || return 0
    put "Needs you ($n_attn) | size=12"
    OUT+="$needs_menu"
}

section_agents() {
    put "Agents ($n_agents) | size=12"
    [[ $n_agents -gt 0 ]] || put "No agent sessions"
    OUT+="$agents_menu$daemon_menu"
}

# Where the CPU goes: CPU now by job type, busiest first, each with the
# sessions behind it (clicking one shows its project in Finder); then today's
# CPU-hours and tokens from the history, and the report.
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
                        v = (v == "" || v == sv[l[q]]) ? sv[l[q]] : "-"
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
section_jobs() {
    local tag job cpu rss n proj kind root start cwd name unit about via line t sym click tip q="'" d named
    [[ -n "$job_rows" || "$hist_state" == ok || "$hist_state" == due ]] || return 0
    put "Where the CPU goes | size=12"
    while IFS=$'\t' read -r tag job cpu rss n proj kind root start cwd name unit about via; do
        case "$tag" in
            J)  job_symbol "$job"; sym="$REPLY"; job_label "$job"; line="$REPLY · ${cpu}%"; memv "${rss:-0}"
                put "$line · $REPLY | sfimage=$sym $ROW symbolize=false"
                # The size is memory, which "1.2G" alone does not say.
                [[ "$job" != mcp ]] || put "--memory in use now (RSS), not data sent | size=11 symbolize=false" ;;
            G)  # An MCP server in several sessions (proj: its copies, kind:
                # the stale ones), who configured it and how it starts, then
                # its copies (C).
                cl "$name"; line="$REPLY · $proj copies"
                [[ "$kind" == 0 ]] || line+=", $kind stale"
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
    done < <([[ -z "$job_rows" ]] || job_lines)
    [[ "$hist_state" == ok || "$hist_state" == due ]] || return 0
    if num "$hist_total" && [[ $hist_total -gt 0 ]]; then
        if [[ $hist_total -ge 3600 ]]; then
            t=$(( (hist_total + 180) / 360 )); line="Today: $((t / 10)).$((t % 10)) CPU-h"
        elif [[ $hist_total -ge 60 ]]; then line="Today: $((hist_total / 60)) CPU-min"
        else line="Today: <1 CPU-min"; fi
        if num "$hist_top_s" && [[ "$hist_top" =~ ^[a-z]+$ ]]; then
            job_label "$hist_top"; line+=" · $REPLY $(( (hist_top_s * 100 + hist_total / 2) / hist_total ))%"
        fi
    else
        line="Today: nothing recorded yet (a sample a minute)"
    fi
    put "$line | sfimage=chart.bar.xaxis $ROW symbolize=false"
    # Today's tokens (from tokens.today, which `agents sample` writes) and the
    # share read from the prompt cache; opens today's token report.
    if num "$tok_total" && num "$tok_cache" && [[ $tok_total -gt 0 ]]; then
        humanize "$tok_total"
        put "$REPLY tokens today · ${tok_cache}% cached | $TERM_OPEN param2=--hold param3=report param4=--view param5=tokens param6=--since param7=today sfimage=text.bubble symbolize=false"
    fi
    # Today's top insight (from insight.txt, which `agents sample` refreshes):
    # what it found as the label (the text before " — ", at most 70
    # characters, cut at a word), the whole sentence with its advice as the
    # tooltip; the only param is one of the report's fixed views.
    case "$insight_view" in
        summary|runs|waste|trends|agents|tokens|denials)
            if [[ -n "$insight_text" ]]; then
                cl "${insight_text//\`/}"
                tip="${REPLY//\"/$q}" line="${REPLY%% — *}"
                [[ ${#line} -le 70 ]] || { line="${line:0:67}"; line="${line% *}..."; }
                put "$line | $TERM_OPEN param2=--hold param3=report param4=--view param5=$insight_view tooltip=\"$tip\" sfimage=lightbulb symbolize=false"
            fi ;;
    esac
    put "Open report | $TERM_OPEN param2=--hold param3=report sfimage=doc.text.magnifyingglass"
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
        put "Lid sleep disabled, nothing restores it | sfimage=exclamationmark.triangle.fill $DOT_RED $ROW"
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

# System: the CPU line opens agents watch (its submenu lists the busiest
# processes, each opening Activity Monitor); the power line opens System
# Settings › Battery, where Energy Mode lives. A
# warning colors the symbol (orange or red), never the text.
section_system() {
    local used="" line hot="" bolt=""
    num "$memfree" && used=" · Mem $((100 - memfree))%"
    line="CPU ${cpu}%$used · Load $load/$cores"
    case "$mempress" in
        warn)     line+=" · memory pressure | sfimage=memorychip $DOT_ORANGE" ;;
        critical) line+=" · memory pressure critical | sfimage=memorychip $DOT_RED" ;;
        *)        line+=" | sfimage=cpu" ;;
    esac
    put "$line $TERM_OPEN param2=watch"
    if [[ -n "$top_menu" ]]; then
        put "--Busiest processes | size=11"
        OUT+="$top_menu"
    fi
    num "$thermal" && [[ $thermal -ge 2 ]] && hot=" $DOT_RED"
    if num "$batt"; then
        charging "$bstate" && bolt=" :bolt.fill:"
        battery_symbol "$batt" "$bstate"
        put "Battery ${batt}%$bolt · Thermal $thermal_name · Energy $power | sfimage=$REPLY$hot $CALLBACK param1=battery-settings"
    else
        put "Thermal $thermal_name · Energy $power | sfimage=thermometer.medium$hot $CALLBACK param1=battery-settings"
    fi
}

bar_title
for section in $BAR_SECTIONS; do
    OUT=""
    case "$section" in
        needs|agents|jobs|stale|hogs|awake|system) "section_$section" ;;
    esac
    while [[ "$OUT" == *$'\n' ]]; do OUT="${OUT%$'\n'}"; done
    [[ -n "$OUT" ]] || continue
    echo "---"
    printf '%s\n' "$OUT"
done
echo "---"
echo "Open agents watch | $TERM_OPEN param2=watch sfimage=rectangle.and.text.magnifyingglass"
[[ -n "$CONF" && -f "$CONF" ]] && echo "Edit settings… | $NOREF param1=config param2=--edit sfimage=slider.horizontal.3"
echo "Refresh | refresh=true sfimage=arrow.clockwise"
