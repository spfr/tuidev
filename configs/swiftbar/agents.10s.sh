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
SELF="${SWIFTBAR_PLUGIN_PATH:-$(cd "$(dirname "$0")" && pwd)/$(basename "$0")}"

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
AGENTS="${AGENTS_BIN:-$(command -v agents 2>/dev/null)}"
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

# Menu text must not contain "|" (SwiftBar's separator; shown as ¦) or start with "-"
# (a "--" prefix would turn a process name into a submenu or a separator).
clean() {
    local s="${1//|/¦}" t='~'
    s="${s#"${s%%[!-[:space:]]*}"}"
    printf '%s' "${s/#"$HOME"/$t}"
}
# Params carry only fixed words, PID@START tokens and the two trusted paths
# below (agents and this plugin), double-quoted. Nothing a process controls (a
# cwd, a name, Herdr's text) ever goes into a param: SwiftBar unescapes
# backslashes there, and a later key overrides an earlier one. Paths are
# resolved by `agents cwd|copy-path|reveal PID@START` when you click.
qv() { printf '"%s"' "$1"; }
# tok PID START — the action token, or nothing if either part looks odd.
tok() { [[ "$1" =~ ^[0-9]+$ && "$2" =~ ^[A-Za-z0-9_:]+$ ]] && printf '%s@%s' "$1" "$2"; }
mem() { if [[ $1 -ge 1048576 ]]; then echo "$(($1 * 10 / 1048576 / 10)).$(($1 * 10 / 1048576 % 10))G"; else echo "$(($1 / 1024))M"; fi; }
age() {
    local s="$1"
    if [[ $s -lt 3600 ]]; then echo "$((s / 60))m"
    elif [[ $s -lt 86400 ]]; then echo "$((s / 3600))h$(((s % 3600) / 60))m"
    else echo "$((s / 86400))d$(((s % 86400) / 3600))h"; fi
}
# Action prefixes, built once (each $(…) is a fork, and a menu has dozens).
if [[ "$AGENTS$SELF" == *[\"\\]* ]]; then
    echo ":exclamationmark.triangle: | sfcolor=#FF9F0A"
    echo "---"
    echo "Refusing to run: the agents or plugin path contains a quote or a backslash | color=red"
    exit 0
fi
ACT="bash=$(qv "$AGENTS") terminal=false refresh=true"
NOREF="bash=$(qv "$AGENTS") terminal=false"
TERM_OPEN="bash=$(qv "$AGENTS") param1=open-term terminal=false"
CALLBACK="bash=$(qv "$SELF") terminal=false"
num() { [[ "$1" =~ ^[0-9]+$ ]]; }
charging() { [[ "$1" == charging || "$1" == charged || "$1" == "AC attached" || "$1" == "finishing charge" ]]; }
battery_symbol() {
    local p="$1" s="battery.0percent"
    if charging "$2"; then echo "battery.100percent.bolt"; return; fi
    if [[ $p -ge 88 ]]; then s=battery.100percent
    elif [[ $p -ge 63 ]]; then s=battery.75percent
    elif [[ $p -ge 38 ]]; then s=battery.50percent
    elif [[ $p -ge 13 ]]; then s=battery.25percent; fi
    echo "$s"
}

# --- Read the snapshot -------------------------------------------------------------

me="${USER:-$(id -un)}"
n_agents=0 n_blocked=0 n_stale=0 n_hogs=0
needs_menu="" agents_menu="" daemon_menu="" stale_menu="" hogs_menu="" top_menu="" stale_tokens=""
awake_mode=off awake_until=0 thermal=- thermal_name=unknown power=unknown
lid_state=off lid_until=0 lid_max=28800 BAR_LID=1
cpu=- load=- cores=- memfree=- mempress=- batt=- bstate=-
BAR_TITLE="count awake" BAR_SECTIONS="needs agents jobs stale hogs awake system" BAR_ICON=terminal CONF=""
job_rows="" hist_state="" hist_total=0 hist_top=- hist_top_s=0 insight_view="" insight_text=""

# Per-session activity, gathered from the act rows into variables named after
# the session's pid (bash 3.2 has no associative arrays): A_<what>_<pid>.
aget() { local v="A_$1_$2"; printf '%s' "${!v-}"; }
aadd() { local v="A_$1_$2"; printf -v "$v" '%s%s' "${!v-}" "$3"; }
anum() { local v="A_$1_$2"; printf -v "$v" '%d' $(( ${!v:-0} + $3 )); }
short() { local c; c="$(clean "$1")"; [[ ${#c} -le 60 ]] || c="${c:0:57}..."; printf '%s' "$c"; }
# Fork-free twins of clean, short, age and mem for the per-row loops: they set
# REPLY instead of printing (each $(…) costs a fork, and a busy session has
# dozens of rows).
cl() { local s="${1//|/¦}" t='~'; s="${s#"${s%%[!-[:space:]]*}"}"; REPLY="${s/#"$HOME"/$t}"; }
sh60() { cl "$1"; [[ ${#REPLY} -le 60 ]] || REPLY="${REPLY:0:57}..."; }
memv() { if [[ $1 -ge 1048576 ]]; then REPLY="$(($1 * 10 / 1048576 / 10)).$(($1 * 10 / 1048576 % 10))G"; else REPLY="$(($1 / 1024))M"; fi; }
agev() {
    local s="$1"
    if [[ $s -lt 3600 ]]; then REPLY="$((s / 60))m"
    elif [[ $s -lt 86400 ]]; then REPLY="$((s / 3600))h$(((s % 3600) / 60))m"
    else REPLY="$((s / 86400))d$(((s % 86400) / 3600))h"; fi
}

# dup_groups LINES — for "cwd\037cmd<TAB>age<TAB>token" lines, one line per
# command running more than once in one directory: "count<TAB>cwd\037cmd<TAB>
# tokens of all but the newest".
dup_groups() {
    local cmd tk prev="" n=0 toks=""
    [[ -n "$1" ]] || return 0
    while IFS=$'\t' read -r cmd _ tk; do
        [[ -n "$tk" ]] || continue
        if [[ $n -gt 0 && "$cmd" == "$prev" ]]; then
            n=$((n + 1)); toks+=" $tk"
        else
            [[ $n -gt 1 ]] && printf '%d\t%s\t%s\n' "$n" "$prev" "$toks"
            prev="$cmd"; n=1; toks=""
        fi
    done < <(printf '%s' "$1" | sort -t $'\t' -k1,1 -k2,2n)
    [[ $n -gt 1 ]] && printf '%d\t%s\t%s\n' "$n" "$prev" "$toks"
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
        v="A_mcprss_$r"; memv "${!v:-0}"; v="A_mcpprocs_$r"
        SUB+="--MCP: $m server$([[ $m -gt 1 ]] && echo s) · ${!v:-0} procs · $REPLY | size=11"$'\n'
    fi
    v="A_dups_$r"
    [[ -n "${!v-}" ]] || return 0
    while IFS=$'\t' read -r g cmd toks; do
        [[ -n "$g" ]] || continue
        params="param1=kill param2=--confirm-gui param3=--notify"; i=4
        for tk in $toks; do params+=" param$i=$tk"; i=$((i + 1)); done
        sh60 "${cmd#*$'\037'}"
        SUB+="--Stop duplicates: ${g}× $REPLY (keep newest)… | $ACT $params sfimage=xmark.octagon symbolize=false"$'\n'
    done <<<"$(dup_groups "${!v}")"
}

# The submenu under a session: where it is, what it is, and what you can do.
# Sets SUB.
session_submenu() {   # PID START KIND AGE KIDS PORTS CWD
    local pid="$1" start="$2" kind="$3" age_s="$4" kids="$5" ports="$6" cwd="$7" t pl=""
    SUB=""
    if [[ "$cwd" != - ]]; then cl "$cwd"; SUB+="--$REPLY | symbolize=false"$'\n'; fi
    if [[ "$ports" != - ]]; then cl "$ports"; pl=" · ports $REPLY"; fi
    agev "$age_s"; t="$REPLY"; cl "$kind"
    SUB+="--$REPLY · pid $pid · up $t · $kids children$pl | symbolize=false"$'\n'
    [[ "$pid" =~ ^[0-9]+$ && "$start" =~ ^[A-Za-z0-9_:]+$ ]] || return 0
    t="$pid@$start"
    activity_submenu "$pid"
    SUB+="-----"$'\n'
    SUB+="--Kill $([[ "$kind" == daemon ]] && echo daemon || echo session)… | $ACT param1=kill param2=--confirm-gui param3=--notify param4=$t sfimage=xmark.octagon"$'\n'
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

# need_submenu PID TOKEN STOP_LINE — under an item: the verdict, the evidence,
# then Stop (STOP_LINE), Copy details (`agents why --copy`) and, while its
# session runs, Show session (`agents ps` of that session in your terminal).
# Sets SUB.
need_submenu() {
    local p="$1" v o look=info.circle
    SUB=""
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
    v="N_owner_$p"; o="${!v-}"
    if num "$o"; then SUB+="--Show session | $TERM_OPEN param2=--hold param3=ps param4=$o sfimage=terminal"$'\n'; fi
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
            r="$user"; num "$r" || continue
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
        stale)
            n_stale=$((n_stale + 1))
            v="N_short_$pid"; vs=""; [[ -n "${!v-}" ]] && { cl "${!v}"; vs=" · $REPLY"; }
            stale_menu+="$(clean "${args:0:60}") · $(age "$age_s") · $(mem "$rss")$vs | $ROW symbolize=false sfimage=$([[ "$kind" == server ]] && echo network || echo puzzlepiece.extension)"$'\n'
            stale_menu+="--$kind · pid $pid$([[ "$cwd" != - ]] && echo " · $(clean "$cwd")")$([[ "$ports" != - ]] && echo " · ports $(clean "$ports")") | symbolize=false"$'\n'
            if t="$(tok "$pid" "$start")"; then
                kl="--Kill tree | $ACT param1=kill param2=-y param3=--notify param4=$t sfimage=xmark.octagon"
                if [[ -n "$vs" ]]; then need_submenu "$pid" "$t" "$kl"; stale_menu+="$SUB"; else stale_menu+="$kl"$'\n'; fi
                stale_tokens+=" $t"
            fi
            ;;
        hog)
            n_hogs=$((n_hogs + 1))
            hogs_menu+="$(clean "$kind") · ${pcpu}% now · ${avg}% avg | $ROW symbolize=false sfimage=flame"$'\n'
            hogs_menu+="--pid $pid · $(clean "$user") · up $(age "$age_s") · $(mem "$rss") | symbolize=false"$'\n'
            if [[ "$user" == "$me" ]] && t="$(tok "$pid" "$start")"; then
                hogs_menu+="--Terminate (SIGTERM) | $ACT param1=term param2=-y param3=--notify param4=$t sfimage=xmark.octagon"$'\n'
            elif [[ "$user" != "$me" ]]; then
                hogs_menu+="--Owned by $(clean "$user"): run sudo kill $pid in a terminal | symbolize=false"$'\n'
            fi
            ;;
        top)     top_menu+="--$(clean "$kind") · ${pcpu}% · $(mem "$rss") | $CALLBACK param1=activity-monitor symbolize=false"$'\n' ;;
        sys)     cpu="$pid"; load="$kind"; cores="$age_s"; memfree="$pcpu"; mempress="$avg"; batt="$rss"; bstate="$kids" ;;
        awake)   awake_mode="$pid"; awake_until="$age_s" ;;   # awake MODE PID UNTIL
        thermal) thermal="$pid"; thermal_name="$kind" ;;
        power)   power="$pid" ;;
        lid)     lid_state="$pid"; lid_until="$age_s"; lid_max="$pcpu" ;;   # lid STATE PID UNTIL MAX
        # job ROOT JOB 0 CPU 0 RSS PROCS START own|sub UNIT KIND CWD - PROJECT
        job)     job_rows+="$kind"$'	'"$pcpu"$'	'"$rss"$'	'"$kids"$'	'"$herdr"$'	'"$project"$'	'"$pid"$'	'"$start"$'	'"$cwd"$'
' ;;
        hist)    hist_state="$pid"; hist_total="$kind"; hist_top="$age_s"; hist_top_s="$pcpu" ;;   # hist STATE TODAY_S TOP TOP_S
        insight) insight_view="$pid"; insight_text="$kind" ;;   # insight VIEW TEXT
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
        daemon_menu+="codex daemon · ${pcpu}% · $(mem "$rss") | sfimage=gearshape $ROW symbolize=false"$'\n'
        session_submenu "$pid" "$start" daemon "$age_s" "$kids" "$ports" -
        daemon_menu+="$SUB"
        continue
    fi
    n_agents=$((n_agents + 1))
    name="$(clean "${project:--}")"; [[ "$name" == - || -z "$name" ]] && name="$kind"
    status=""; [[ "$herdr" != - ]] && status=" · $(clean "$herdr")"
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
    t="$(tok "$pid" "$start")" && [[ "$cwd" != - ]] && click="$NOREF param1=reveal param2=$t"
    session_submenu "$pid" "$start" "$kind" "$age_s" "$kids" "$ports" "$cwd"; sub="$SUB"
    memv "$rss"
    agents_menu+="$name · $(clean "$kind")$status · ${pcpu}%$hint · $REPLY | $look $click symbolize=false"$'\n'"$sub"
    if [[ "$herdr" == blocked ]]; then
        n_blocked=$((n_blocked + 1)); n_attn=$((n_attn + 1))
        needs_menu+="$name · $(clean "$kind") · waiting for you | sfimage=exclamationmark.circle.fill $DOT_ORANGE $click symbolize=false"$'\n'"$sub"
    fi
    while IFS=$'\t' read -r g cmd toks; do
        [[ -n "$g" ]] || continue
        n_attn=$((n_attn + 1))
        params="param1=kill param2=--confirm-gui param3=--notify"; i=4
        for tk in $toks; do params+=" param$i=$tk"; i=$((i + 1)); done
        needs_menu+="$name: ${g}× $(short "${cmd#*$'\037'}") running | sfimage=square.stack.3d.up $DOT_ORANGE $ROW symbolize=false"$'\n'
        needs_menu+="--Stop duplicates (keep newest)… | $ACT $params sfimage=xmark.octagon"$'\n'
    done <<<"$(dup_groups "$(aget dups "$pid")")"
    while IFS=$'\t' read -r cmd lage tk; do
        [[ -n "$tk" ]] || continue
        n_attn=$((n_attn + 1))
        need_item clock "$name: $(short "$cmd") · running $(age "$lage")" "$tk"
    done <<<"$(aget longs "$pid")"
    while IFS=$'\t' read -r cmd lage tk; do
        [[ -n "$tk" ]] || continue
        n_attn=$((n_attn + 1))
        need_item hourglass "$name: $(short "$cmd") · stuck $(age "$lage")" "$tk"
    done <<<"$(aget stucks "$pid")"
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
            battery) num "$batt" && t+=" :$(battery_symbol "$batt" "$bstate"): ${batt}%" ;;
            thermal) num "$thermal" && [[ $thermal -ge 1 ]] && t+=" :thermometer.medium: $thermal_name" ;;
            awake)   [[ "$awake_mode" != off ]] && t+=" :cup.and.saucer.fill:" ;;
            warn)    [[ -n "$attention" ]] && t+=" :exclamationmark.triangle.fill:" ;;
        esac
    done
    printf '%s' "$t"
    [[ -z "$attention" ]] || printf ' | sfcolor=%s' "$attention"
    printf '\n'
}

# --- Sections (each prints nothing when it has nothing to say) ----------------------

section_needs() {
    [[ $n_attn -gt 0 ]] || return 0
    echo "Needs you ($n_attn) | size=12"
    printf '%s' "$needs_menu"
}

section_agents() {
    echo "Agents ($n_agents) | size=12"
    [[ $n_agents -gt 0 ]] || echo "No agent sessions"
    printf '%s' "$agents_menu"
    printf '%s' "$daemon_menu"
}

# Where the CPU goes: CPU now by job type, busiest first, each with the
# sessions behind it (clicking one shows its project in Finder); then today's
# CPU-hours from the history, and the report.
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
# job_lines — job_rows summed per job ("J job cpu rss procs") and per job and
# session ("S job cpu rss procs project kind root start cwd"), busiest first.
job_lines() {
    printf '%s' "$job_rows" | LC_ALL=C awk -F '\t' -v OFS='\t' '
        function pc(x) { return (x > 0 && x < 0.5) ? "<1" : sprintf("%.0f", x) }
        function sortk(arr, keys, n,   i, j, b, t) {
            for (i = 1; i <= n; i++) { b = i; for (j = i + 1; j <= n; j++) if (arr[keys[j]] > arr[keys[b]]) b = j; t = keys[i]; keys[i] = keys[b]; keys[b] = t }
        }
        NF >= 9 {
            if (!($1 in jc)) jo[++nj] = $1
            jc[$1] += $2 + 0.001 * ($3 / 1048576); jcpu[$1] += $2; jm[$1] += $3; jn[$1] += $4
            k = $1 SUBSEP $7
            if (!(k in sc)) { sn[$1]++; sk[$1, sn[$1]] = k; sp[k] = $6; sd[k] = $5; ss[k] = $8; sw[k] = $9 }
            sc[k] += $2; sm[k] += $3; sx[k] += $4
            so[k] += $2 + 0.000000001 * $3          # the sort key: ties go to more memory
        }
        END {
            sortk(jc, jo, nj)
            for (i = 1; i <= nj; i++) {
                j = jo[i]; print "J", j, pc(jcpu[j]), jm[j], jn[j]
                m = sn[j]; for (q = 1; q <= m; q++) l[q] = sk[j, q]
                sortk(so, l, m)
                for (q = 1; q <= m; q++) { k = l[q]; split(k, r, SUBSEP); print "S", j, pc(sc[k]), sm[k], sx[k], sp[k], sd[k], r[2], ss[k], sw[k] }
            }
        }'
}
section_jobs() {
    local tag job cpu rss n proj kind root start cwd line t sym click
    [[ -n "$job_rows" || "$hist_state" == ok || "$hist_state" == due ]] || return 0
    echo "Where the CPU goes | size=12"
    while IFS=$'\t' read -r tag job cpu rss n proj kind root start cwd; do
        case "$tag" in
            J)  job_symbol "$job"; sym="$REPLY"; job_label "$job"; line="$REPLY · ${cpu}%"; memv "${rss:-0}"
                echo "$line · $REPLY | sfimage=$sym $ROW symbolize=false" ;;
            S)  cl "${proj:--}"; line="$REPLY"
                case "$kind" in -) line+=" · stale" ;; daemon) line+=" · codex daemon" ;; *) cl "$kind"; line+=" · $REPLY" ;; esac
                memv "${rss:-0}"; line+=" · ${cpu}% · $REPLY"
                click="$ROW"
                t="$(tok "$root" "$start")" && [[ "$cwd" != - ]] && click="$NOREF param1=reveal param2=$t"
                echo "--$line | $click symbolize=false" ;;
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
    echo "$line | sfimage=chart.bar.xaxis $ROW symbolize=false"
    # Today's top insight (from insight.txt, which `agents sample` refreshes):
    # its text in the label only; the param is one of the report's fixed views.
    case "$insight_view" in
        summary|runs|waste|trends|agents)
            if [[ -n "$insight_text" ]]; then
                cl "$insight_text"
                echo "${REPLY//\`/} | $TERM_OPEN param2=--hold param3=report param4=--view param5=$insight_view sfimage=lightbulb symbolize=false"
            fi ;;
    esac
    echo "Open report | $TERM_OPEN param2=--hold param3=report sfimage=doc.text.magnifyingglass"
}

section_stale() {
    [[ $n_stale -gt 0 ]] || return 0
    echo "Stale ($n_stale) | size=12"
    printf '%s' "$stale_menu"
    # Exactly the processes listed above, not whatever is stale at click time.
    local params="param1=kill param2=-y param3=--notify" i=4 tk
    for tk in $stale_tokens; do params+=" param$i=$tk"; i=$((i + 1)); done
    echo "Reap all stale | $ACT $params sfimage=trash"
}

section_hogs() {
    [[ $n_hogs -gt 0 ]] || return 0
    echo "Hogs ($n_hogs) | size=12"
    printf '%s' "$hogs_menu"
}

section_awake() {
    local text left
    case "$awake_mode" in
        off)    text="Awake: off" ;;
        agents) text="Awake: while agents run" ;;
        timed|lid) num "$awake_until" || awake_until=0
                left=$((awake_until - $(date +%s)))
                if [[ $left -lt 60 ]]; then text="Awake: <1m left"; else text="Awake: $(age "$left") left"; fi ;;
        *)      text="Awake: on until turned off" ;;
    esac
    # Lid mode reads its time from the guard's record.
    if [[ "$lid_state" == on ]]; then
        num "$lid_until" || lid_until=0
        left=$((lid_until - $(date +%s)))
        if [[ $left -lt 60 ]]; then text="Awake: lid closed · <1m left"; else text="Awake: lid closed · $(age "$left") left"; fi
    fi
    ck() { [[ "$awake_mode" == "$1" ]] && printf ' checked=true'; }
    if [[ "$lid_state" == stale ]]; then
        echo "Lid sleep disabled, nothing restores it | sfimage=exclamationmark.triangle.fill $DOT_RED $ROW"
        echo "Restore lid sleep… | $ACT param1=awake param2=restore param3=--notify sfimage=lock.open"
    fi
    echo "$text | sfimage=$([[ "$lid_state" == on ]] && echo laptopcomputer || echo cup.and.saucer) $ROW"
    echo "--Until turned off | $ACT param1=awake param2=on$(ck on)"
    echo "--For 1 hour | $ACT param1=awake param2=on param3=1h"
    echo "--For 3 hours | $ACT param1=awake param2=on param3=3h"
    echo "--While agents run | $ACT param1=awake param2=agents$(ck agents)"
    # Lid mode (AGENTS_LID=0 hides it): disables lid sleep as root, time-boxed,
    # after a password dialog. Results come back as notifications (--notify):
    # a menu action has no terminal.
    if [[ "$BAR_LID" == 1 ]]; then
        echo "--Lid closed too… | sfimage=laptopcomputer $ROW"
        num "$lid_max" || lid_max=28800
        [[ $lid_max -ge 3600 ]] && echo "----For 1 hour | $ACT param1=awake param2=lid param3=1h param4=--notify"
        [[ $lid_max -ge 10800 ]] && echo "----For 3 hours | $ACT param1=awake param2=lid param3=3h param4=--notify"
        [[ $lid_max -ge 28800 ]] && echo "----For 8 hours | $ACT param1=awake param2=lid param3=8h param4=--notify"
        echo "----Asks for your password; restores on timeout or low battery | size=11"
    fi
    echo "--Off | $ACT param1=awake param2=off$(ck off)"
    echo "-----"
    echo "--Who holds the Mac awake? | $TERM_OPEN param2=--hold param3=awake param4=status"
    if [[ "$lid_state" == on ]]; then
        echo "End lid mode now… | $ACT param1=awake param2=off param3=--notify sfimage=laptopcomputer.slash"
    fi
}

# System: the CPU line opens agents watch (its submenu lists the busiest
# processes, each opening Activity Monitor); the power line opens System
# Settings › Battery, where Energy Mode lives. A
# warning colors the symbol (orange or red), never the text.
section_system() {
    local used="" line hot=""
    num "$memfree" && used=" · Mem $((100 - memfree))%"
    line="CPU ${cpu}%$used · Load $load/$cores"
    case "$mempress" in
        warn)     line+=" · memory pressure | sfimage=memorychip $DOT_ORANGE" ;;
        critical) line+=" · memory pressure critical | sfimage=memorychip $DOT_RED" ;;
        *)        line+=" | sfimage=cpu" ;;
    esac
    echo "$line $TERM_OPEN param2=watch"
    if [[ -n "$top_menu" ]]; then
        echo "--Busiest processes | size=11"
        printf '%s' "$top_menu"
    fi
    num "$thermal" && [[ $thermal -ge 2 ]] && hot=" $DOT_RED"
    if num "$batt"; then
        echo "Battery ${batt}%$(charging "$bstate" && echo " :bolt.fill:") · Thermal $thermal_name · Energy $power | sfimage=$(battery_symbol "$batt" "$bstate")$hot $CALLBACK param1=battery-settings"
    else
        echo "Thermal $thermal_name · Energy $power | sfimage=thermometer.medium$hot $CALLBACK param1=battery-settings"
    fi
}

bar_title
for section in $BAR_SECTIONS; do
    case "$section" in
        needs|agents|jobs|stale|hogs|awake|system) out="$("section_$section")" ;;
        *) out="" ;;
    esac
    [[ -n "$out" ]] || continue
    echo "---"
    printf '%s\n' "$out"
done
echo "---"
echo "Open agents watch | $TERM_OPEN param2=watch sfimage=rectangle.and.text.magnifyingglass"
[[ -n "$CONF" && -f "$CONF" ]] && echo "Edit settings… | $NOREF param1=config param2=--edit sfimage=slider.horizontal.3"
echo "Refresh | refresh=true sfimage=arrow.clockwise"
