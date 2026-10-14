# shellcheck shell=bash
# lib/agents/report.sh — `agents report`: where the CPU went, what was cleaned
# up, and what the run ledger says is worth changing.
#
# Owns: the report's window, its views, and insight.txt (the menu's top
#   insight: "EPOCH<TAB>UNTIL<TAB>VIEW<TAB>TEXT", or just "EPOCH<TAB>UNTIL"
#   when nothing stands out).
# Uses: config.sh, util.sh (agents_parse_duration, _agents_replace),
#   events.sh (_agents_data_dir), render.sh (colors); awk/report.awk and its
#   parts (report_fmt, report_runs, report_insights, report_views).
# Public: agents_report, agents_insight_write, _agents_insight_line.

_AGENTS_REPORT_VIEWS="summary runs waste trends agents"

# agents_report [--view VIEW] [--since 24h|7d|30d|today] [--json] — the
# summary (default): where the CPU went (by job, project, session and hour of
# day, from history.tsv), what was cleaned up (events.tsv), and the top
# insights from the run ledger (runs.tsv); or one of the ledger's views: runs,
# waste, trends (default --since 7d), agents.
agents_report() {
    local view=summary since="" json="" start now off period
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json)    json=1 ;;
            --since|--view)
                       [[ $# -ge 2 ]] || { _agents_report_usage; return 2; }
                       if [[ "$1" == --since ]]; then since="$2"; else view="$2"; fi
                       shift ;;
            --since=*) since="${1#--since=}" ;;
            --view=*)  view="${1#--view=}" ;;
            *)         _agents_report_usage; return 2 ;;
        esac
        shift
    done
    case " $_AGENTS_REPORT_VIEWS " in
        *" $view "*) ;;
        *) echo "agents: bad --view '$view' (${_AGENTS_REPORT_VIEWS// /, })" >&2; return 2 ;;
    esac
    if [[ -z "$since" ]]; then since=24h; [[ "$view" != trends ]] || since=7d; fi
    _agents_report_window "$since" || { echo "agents: bad --since '$since' (24h, 7d, 30d, today)" >&2; return 2; }
    _agents_report_awk "$view" "$since" "$json"
}
_agents_report_usage() { echo "usage: agents report [--view summary|runs|waste|trends|agents] [--since 24h|7d|30d|today] [--json]" >&2; }

# _agents_report_window SINCE — set the caller's start, now, off (the UTC
# offset, s) and period: the window is [start, now], the one before it
# [start - period, now - period) (for today: yesterday by this hour). False
# on a bad SINCE.
_agents_report_window() {
    local z secs
    read -r now z <<<"$(date '+%s %z')"
    off=0
    if [[ "$z" =~ ^([+-])([0-9][0-9])([0-9][0-9])$ ]]; then
        off=$(( 10#${BASH_REMATCH[2]} * 3600 + 10#${BASH_REMATCH[3]} * 60 ))
        [[ "${BASH_REMATCH[1]}" == + ]] || off=$((-off))
    fi
    if [[ "$1" == today ]]; then
        start=$(( now - (now + off) % 86400 )); period=86400
    elif secs="$(agents_parse_duration "$1")"; then
        start=$((now - secs)); period=$secs
    else
        return 1
    fi
}

# _agents_report_awk VIEW LABEL JSON — report.awk over the data directory,
# for the window the caller's _agents_report_window set.
_agents_report_awk() {
    B="${C_B:-}" DIM="${C_DIM:-}" N="${C_0:-}" \
    _agents_awk "lib_json lib_sort report_fmt report_runs report_insights report_views report" -F '\t' \
        -v view="$1" -v label="$2" -v json="$3" -v start="$start" -v now="$now" -v off="$off" \
        -v pstart="$((start - period))" -v pend="$((now - period))" -v hist="$AGENTS_HISTORY" \
        -v hf="$AGENTS_DATA_DIR/history.tsv" -v ef="$AGENTS_DATA_DIR/events.tsv" -v rf="$AGENTS_DATA_DIR/runs.tsv"
}

# agents_insight_write — refresh insight.txt with today's top insight (the
# summary's first, from runs.tsv), for the menu. At most every 5 minutes, and
# again once the last one expires (an hour after it was written, or at
# midnight); a no-op with AGENTS_HISTORY=0. Meant to run after each
# `agents sample`, in the background; it never prints.
agents_insight_write() {
    [[ "$AGENTS_HISTORY" == 1 ]] || return 0
    local f="$AGENTS_DATA_DIR/insight.txt" was="" until="" top start now off period
    [[ -r "$f" ]] && IFS=$'\t' read -r was until _ < "$f"
    _agents_report_window today
    if [[ "$was" =~ ^[0-9]+$ && "$until" =~ ^[0-9]+$ ]] && (( now >= was && now - was < 300 && now < until )); then
        return 0
    fi
    top="$(_agents_report_awk insight today "")"
    until=$((start + 86400)); [[ $until -le $((now + 3600)) ]] || until=$((now + 3600))
    _agents_data_dir || return 1
    ( umask 077; _agents_replace "$f" "$now"$'\t'"$until${top:+$'\t'$top}" )
}

# _agents_insight_line — the menu's insight row, from insight.txt alone:
#   insight VIEW TEXT  while it is current; nothing otherwise.
_agents_insight_line() {
    [[ "$AGENTS_HISTORY" == 1 && -r "$AGENTS_DATA_DIR/insight.txt" ]] || return 0
    local was="" until="" view="" text=""
    IFS=$'\t' read -r was until view text < "$AGENTS_DATA_DIR/insight.txt"
    [[ "$until" =~ ^[0-9]+$ && -n "$text" && " $_AGENTS_REPORT_VIEWS " == *" $view "* ]] || return 0
    [[ "$(date +%s)" -lt "$until" ]] || return 0
    printf 'insight\t%s\t%s\n' "$view" "$text"
}
