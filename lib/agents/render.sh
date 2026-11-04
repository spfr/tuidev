# shellcheck shell=bash
# lib/agents/render.sh — the full table: `agents ls`, `ps`, `stale` and `hogs`.
#
# Owns: the table (awk/render.awk) and the status lines under it.
# Uses: config.sh, palette.sh (the colors), system.sh, awake.sh
#   (agents_awake_line), lid.sh (_agents_lid_warning).
# Public: agents_render, _agents_footer.

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
    AGENTS_SECTIONS="$1" W="${AGENTS_WIDTH:-120}" HOME="$HOME" \
    LS_TOOLS="$AGENTS_LS_TOOLS" MEMWARN=$((AGENTS_MEM_WARN * 1048576)) FOCUS="${AGENTS_FOCUS:-}" _agents_awk_colored "lib_fmt render" -F '\t'
}
