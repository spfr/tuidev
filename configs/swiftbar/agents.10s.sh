#!/bin/bash
# <xbar.title>agents</xbar.title>
# <xbar.version>v1.2</xbar.version>
# <xbar.desc>Agentic-coding sessions (blocked first), stale helpers, CPU hogs, keep-awake and a compact system view, from tuidev's `agents` command.</xbar.desc>
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
cpu=- load=- cores=- memfree=- mempress=- batt=- bstate=-
BAR_TITLE="count awake" BAR_SECTIONS="needs agents stale hogs awake system" BAR_ICON=terminal CONF=""

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
        SUB+="--Stop duplicates: $g× $REPLY (keep newest)… | $ACT $params sfimage=xmark.octagon symbolize=false"$'\n'
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

agent_rows=()
while IFS=$'\t' read -r type pid kind age_s pcpu avg rss kids start ports user herdr cwd args project aflags adup; do
    case "$type" in
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
                    # A polling loop the agent waits on: marked, never attention.
                    look=""; [[ ",$aflags," == *,wait,* ]] && { fl+=" · waiting"; look=" sfimage=hourglass $DOT_GRAY"; }
                    sh60 "$args"; c="$REPLY"; agev "$age_s"; a="$REPLY"; cl "$project"
                    aadd tools "$r" "--$c · $a · ${pcpu%%.*}% · $REPLY$fl | $ROW$look symbolize=false"$'\n'"----Stop command… | $ACT param1=kill param2=--confirm-gui param3=--notify param4=$t sfimage=xmark.octagon"$'\n'
                    anum ntools "$r" 1; anum tcpu "$r" "${pcpu%%.*}"
                    # Duplicates are the same command in the same directory.
                    [[ ",$aflags," == *,dup,* ]] && aadd dups "$r" "$cwd"$'\037'"$args"$'\t'"$age_s"$'\t'"$t"$'\n'
                    [[ ",$aflags," == *,long,* ]] && aadd longs "$r" "$args"$'\t'"$age_s"$'\t'"$t"$'\n'
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
            stale_menu+="$(clean "${args:0:60}") · $(age "$age_s") · $(mem "$rss") | $ROW symbolize=false sfimage=$([[ "$kind" == server ]] && echo network || echo puzzlepiece.extension)"$'\n'
            stale_menu+="--$kind · pid $pid$([[ "$cwd" != - ]] && echo " · $(clean "$cwd")")$([[ "$ports" != - ]] && echo " · ports $(clean "$ports")") | symbolize=false"$'\n'
            if t="$(tok "$pid" "$start")"; then
                stale_menu+="--Kill tree | $ACT param1=kill param2=-y param3=--notify param4=$t sfimage=xmark.octagon"$'\n'
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
        conf)
            [[ "$kind" == - ]] && kind=""
            case "$pid" in
                AGENTS_BAR_TITLE)    BAR_TITLE="$kind" ;;
                AGENTS_BAR_SECTIONS) BAR_SECTIONS="$kind" ;;
                AGENTS_BAR_ICON)     BAR_ICON="${kind:-terminal}" ;;
                AGENTS_CONF)         CONF="$kind" ;;
            esac
            ;;
    esac
done <<<"$data"
# `sys` packs battery state into the kids column, which can hold spaces.
[[ "$bstate" == - ]] && bstate=""

# Second pass: sessions, now that their activity is known. A blocked session,
# a command running twice and a long-running command each need a look.
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
        needs_menu+="$name: $g× $(short "${cmd#*$'\037'}") running | sfimage=square.stack.3d.up $DOT_ORANGE $ROW symbolize=false"$'\n'
        needs_menu+="--Stop duplicates (keep newest)… | $ACT $params sfimage=xmark.octagon"$'\n'
    done <<<"$(dup_groups "$(aget dups "$pid")")"
    while IFS=$'\t' read -r cmd lage tk; do
        [[ -n "$tk" ]] || continue
        n_attn=$((n_attn + 1))
        needs_menu+="$name: $(short "$cmd") · running $(age "$lage") | sfimage=clock $DOT_ORANGE $ROW symbolize=false"$'\n'
        needs_menu+="--Stop command… | $ACT param1=kill param2=--confirm-gui param3=--notify param4=$tk sfimage=xmark.octagon"$'\n'
    done <<<"$(aget longs "$pid")"
done

# --- Title -------------------------------------------------------------------------
# The icon, the session count, and how many sessions wait for you. The icon is
# tinted only when something needs a look: orange for a blocked session, stale
# processes, hogs or memory pressure; red for heavy thermal or critical memory
# pressure.

attention=""
if [[ $n_attn -gt 0 || $n_stale -gt 0 || $n_hogs -gt 0 || "$mempress" == warn ]]; then attention="$ORANGE"; fi
if { num "$thermal" && [[ $thermal -ge 2 ]]; } || [[ "$mempress" == critical ]]; then attention="$RED"; fi

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
        timed)  num "$awake_until" || awake_until=0
                left=$((awake_until - $(date +%s)))
                if [[ $left -lt 60 ]]; then text="Awake: <1m left"; else text="Awake: $(age "$left") left"; fi ;;
        *)      text="Awake: on until turned off" ;;
    esac
    ck() { [[ "$awake_mode" == "$1" ]] && printf ' checked=true'; }
    echo "$text | sfimage=cup.and.saucer $ROW"
    echo "--Until turned off | $ACT param1=awake param2=on$(ck on)"
    echo "--For 1 hour | $ACT param1=awake param2=on param3=1h"
    echo "--For 3 hours | $ACT param1=awake param2=on param3=3h"
    echo "--While agents run | $ACT param1=awake param2=agents$(ck agents)"
    echo "--Off | $ACT param1=awake param2=off$(ck off)"
    echo "-----"
    echo "--Who holds the Mac awake? | $TERM_OPEN param2=--hold param3=awake param4=status"
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
        needs|agents|stale|hogs|awake|system) out="$("section_$section")" ;;
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
