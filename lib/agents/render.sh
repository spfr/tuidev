# shellcheck shell=bash
# lib/agents/render.sh — the views for people: `agents`, `ps`, `stale`,
# `hogs` and `watch`.
#
# Owns: colors, the table (awk/render.awk), the status lines under it, and
#   the live view.
# Uses: config.sh, snapshot.sh (agents_collect), system.sh, awake.sh
#   (agents_awake_line, _agents_awake_prime), lid.sh (_agents_lid_warning),
#   history.sh (_agents_sample_kick).
# Public: agents_render, agents_watch, _agents_footer, _agents_colors.

_agents_colors() {
    if [[ -t 1 && -z "${NO_COLOR:-}" && -z "${TUIDEV_NO_COLOR:-}" ]]; then
        C_B=$'\033[1m' C_DIM=$'\033[2m' C_Y=$'\033[33m' C_R=$'\033[31m' C_G=$'\033[32m' C_0=$'\033[0m'
    else
        C_B='' C_DIM='' C_Y='' C_R='' C_G='' C_0=''
    fi
}

# _agents_footer [RECORDS] — the status lines under the table.
_agents_footer() {
    local lvl load cores memfree level batt state cpu="-"
    lvl="$(agents_thermal_level)"
    IFS=$'\t' read -r load cores memfree level batt state <<<"$(agents_system)"
    [[ -z "${1:-}" ]] || cpu="$(_agents_cpu_pct "$cores" "$1")"
    printf 'cpu: %s%% · load: %s/%s cores · memory: %s%% free%s%s\n' "$cpu" "$load" "$cores" "$memfree" \
        "$([[ "$level" == - || "$level" == normal ]] || echo " ($level pressure)")" \
        "$([[ "$batt" == - ]] || echo " · battery: $batt% $state")"
    printf 'thermal: %s · energy: %s · %s\n' "$(agents_thermal_name "${lvl:--}")" "$(agents_powermode)" "$(agents_awake_line)"
    _agents_lid_warning
}

# agents_render SECTIONS < RECORDS — the human table. SECTIONS: any of
# "agents stale hogs"; "quiet" hides empty stale/hogs sections behind one line;
# "detail" lists everything each session runs (agents ps), AGENTS_FOCUS=PID
# only that session. Sessions are counted without the Codex daemon, which gets
# a dim last row. Under each session: its MCP servers on one line, then its
# commands (busiest first, AGENTS_LS_TOOLS of them) and nested sessions.
agents_render() {
    AGENTS_SECTIONS="$1" W="${AGENTS_WIDTH:-120}" HOME="$HOME" B="$C_B" DIM="$C_DIM" Y="$C_Y" R="$C_R" G="$C_G" N="$C_0" \
    LS_TOOLS="$AGENTS_LS_TOOLS" FOCUS="${AGENTS_FOCUS:-}" _agents_awk render -F '\t'
}

agents_watch() {
    local secs="${1:-2}" out key
    [[ "$secs" =~ ^[1-9][0-9]*$ ]] || { echo "usage: agents watch [SECONDS]" >&2; return 2; }
    trap 'tput cnorm 2>/dev/null; echo; exit 0' INT TERM
    tput civis 2>/dev/null
    while :; do
        _agents_awake_prime
        _agents_sample_kick          # history, where no menu bar samples it
        out="$(r="$(agents_collect)"; printf '%s\n' "$r" | agents_render "agents stale hogs quiet"; echo; _agents_footer "$r")"
        printf '\033[H\033[2J%sagents · %s · every %ss · q quit%s\n\n%s\n' "$C_DIM" "$(date +%H:%M:%S)" "$secs" "$C_0" "$out"
        if [[ -t 0 ]]; then
            read -r -s -n 1 -t "$secs" key && [[ "$key" == q ]] && break
        else
            sleep "$secs"
        fi
    done
    tput cnorm 2>/dev/null
}
