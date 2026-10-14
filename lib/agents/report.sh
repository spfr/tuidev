# shellcheck shell=bash
# lib/agents/report.sh — `agents report`: where the CPU went, and what was
# cleaned up, from the history files.
#
# Uses: config.sh, util.sh (_agents_window), render.sh (colors);
#   awk/report.awk.
# Public: agents_report.

# agents_report [--since 24h|7d|30d|today] [--json] — where the CPU went (by
# job, project, session and hour of day) and what was cleaned up, from
# history.tsv and events.tsv.
agents_report() {
    local since=24h json="" win now off start
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json)    json=1 ;;
            --since)   [[ $# -ge 2 ]] || { _agents_report_usage; return 2; }
                       since="$2"; shift ;;
            --since=*) since="${1#--since=}" ;;
            *)         _agents_report_usage; return 2 ;;
        esac
        shift
    done
    win="$(_agents_window "$since")" || { echo "agents: bad --since '$since' (24h, 7d, 30d, today)" >&2; return 2; }
    read -r start now off <<<"$win"
    _agents_report_awk "$start" "$now" "$off" "$since" "$json"
}
_agents_report_usage() { echo "usage: agents report [--since 24h|7d|30d|today] [--json]" >&2; }

# _agents_report_awk START NOW UTC_OFFSET_S LABEL JSON
_agents_report_awk() {
    B="${C_B:-}" DIM="${C_DIM:-}" N="${C_0:-}" _agents_awk "lib_json lib_sort report" -F '\t' \
        -v start="$1" -v now="$2" -v off="$3" -v label="$4" -v json="$5" -v hist="$AGENTS_HISTORY" \
        -v hf="$AGENTS_DATA_DIR/history.tsv" -v ef="$AGENTS_DATA_DIR/events.tsv"
}
