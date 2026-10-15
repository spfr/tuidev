# shellcheck shell=bash
# lib/agents/report.sh — `agents report`: where the CPU and the tokens went,
# what was denied or cleaned up, what the sessions load and use, and what is
# worth changing.
#
# Owns: the report's views, insight.txt (the menu's top
#   insight: "EPOCH<TAB>UNTIL<TAB>VIEW<TAB>TEXT", or just "EPOCH<TAB>UNTIL"
#   when nothing stands out), the menu's tokens row (from tokens.today,
#   which the scanner writes; the report only reads the token files), the
#   price files a report reads (prices.tsv beside the modules, then
#   AGENTS_PRICES; AGENTS_PRICES=off: none), and one session's tokens for
#   another view (agents_session_tokens).
# Uses: config.sh, util.sh (_agents_window, _agents_replace),
#   events.sh (_agents_data_dir), render.sh (colors), tokens.sh
#   (_agents_tokens_raw_since), context.sh (the context view's inventory);
#   awk/report.awk and its parts (report_fmt, report_runs, report_tokens,
#   report_denials, report_context, report_insights, report_views),
#   awk/lib_price.awk, awk/tokens_session.awk.
# Public: agents_report, agents_insight_write, agents_session_tokens,
#   _agents_insight_line, _agents_tokens_line, _agents_prices_files.

_AGENTS_REPORT_VIEWS="summary runs waste trends agents tokens context denials"

# agents_report [--view VIEW] [--since 24h|7d|30d|today] [--json] — the
# summary (default): where the CPU went (by job, project, session and hour of
# day, from history.tsv), the tokens and denials, what was cleaned up
# (events.tsv), and the top insights; or one of the ledger's views: runs,
# waste, trends (default --since 7d), agents; or tokens (tokens.tsv,
# compacts.tsv, limits.tsv, the price files), context (uses.tsv and what is
# configured; default --since 7d), denials (denials.tsv).
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
    if [[ -z "$since" ]]; then since=24h; [[ "$view" != trends && "$view" != context ]] || since=7d; fi
    _agents_window "$since" || { echo "agents: bad --since '$since' (24h, 7d, 30d, today)" >&2; return 2; }
    _agents_report_awk "$view" "$since" "$json"
}
_agents_report_usage() { echo "usage: agents report [--view summary|runs|waste|trends|agents|tokens|context|denials] [--since 24h|7d|30d|today] [--json]" >&2; }

# _agents_report_awk VIEW LABEL JSON — report.awk over the data directory,
# for the window the caller's _agents_window set; the context view also
# gets the configured inventory (_agents_context_inventory) on fd 3.
_agents_report_awk() {
    local d="$AGENTS_DATA_DIR" inv=""
    [[ "$1" != context ]] || inv="$(_agents_context_inventory)"
    B="${C_B:-}" DIM="${C_DIM:-}" N="${C_0:-}" \
    _agents_awk "lib_json lib_sort lib_fmt lib_price report_fmt report_runs report_tokens report_denials report_context report_insights report_views report" -F '\t' \
        -v view="$1" -v label="$2" -v json="$3" -v start="$start" -v now="$now" -v off="$off" \
        -v pstart="$((start - period))" -v pend="$((now - period))" -v hist="$AGENTS_HISTORY" \
        -v rawb="$(_agents_tokens_raw_since "$now" "$off")" \
        -v hf="$d/history.tsv" -v ef="$d/events.tsv" -v rf="$d/runs.tsv" \
        -v tf="$d/tokens.tsv" -v cf="$d/compacts.tsv" -v df="$d/denials.tsv" -v lf="$d/limits.tsv" -v uf="$d/uses.tsv" \
        -v pfs="$(_agents_prices_files)" -v invf=/dev/fd/3 3<<<"$inv"
}

# _agents_prices_files — the price files a report reads, "|"-separated, in
# order: the list prices that ship (prices.tsv beside the modules), then
# AGENTS_PRICES (~/ expanded) when it is a readable file, whose lines win.
# Nothing with AGENTS_PRICES=off: the reports then show no cost at all.
_agents_prices_files() {
    local f="$AGENTS_PRICES" t='~' o=""
    [[ "$f" != off ]] || return 0
    [[ ! -r "$_AGENTS_LIB/prices.tsv" ]] || o="$_AGENTS_LIB/prices.tsv"
    [[ "${f%%/*}" != "$t" ]] || f="$HOME/${f#*/}"
    [[ -z "$f" || ! -f "$f" || ! -r "$f" ]] || o="${o:+$o|}$f"
    printf '%s' "$o"
}

# agents_session_tokens SESSION... — what each session cost so far, for a
# view of one session (agents show): one line per session that has tokens,
#   session origin cli project model calls tokens usd
# origin: you, headless (tokens.sh), "-" when unknown; project: as the token
# report folds it; model: its main conversation's latest (any agent's when
# it has none); tokens: every token of the session and its subagents; usd:
# their API-equivalent cost ("-" when unpriced, or AGENTS_PRICES=off). One
# grep and one awk over tokens.tsv, however many sessions; a session id is
# matched whole.
agents_session_tokens() {
    local f="$AGENTS_DATA_DIR/tokens.tsv" s pats=()
    for s in "$@"; do [[ "$s" =~ ^[A-Za-z0-9_-]+$ ]] && pats+=(-e $'\t'"$s"$'\t'); done
    [[ ${#pats[@]} -gt 0 && -r "$f" ]] || return 0
    LC_ALL=C grep -F "${pats[@]}" "$f" 2>/dev/null \
        | _agents_awk "lib_json lib_fmt lib_price report_fmt tokens_session" -F '\t' -v ids="$*" -v pfs="$(_agents_prices_files)"
}

# agents_insight_write — refresh insight.txt with today's top insight (the
# summary's first, from runs.tsv and the token files), for the menu. At most
# every 5 minutes (it reads all of runs.tsv, tokens.tsv and denials.tsv, so
# not every sample), and again once the last one expires (an hour after it
# was written, or at midnight); a no-op with AGENTS_HISTORY=0. Runs at the
# end of each `agents sample` (history.sh), under its lock; it never prints.
agents_insight_write() {
    [[ "$AGENTS_HISTORY" == 1 ]] || return 0
    local f="$AGENTS_DATA_DIR/insight.txt" was="" until="" top start now off period
    [[ -r "$f" ]] && IFS=$'\t' read -r was until _ < "$f"
    _agents_window today
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
    local was="" until="" view="" text="" now
    IFS=$'\t' read -r was until view text < "$AGENTS_DATA_DIR/insight.txt"
    [[ "$until" =~ ^[0-9]+$ && -n "$text" && " $_AGENTS_REPORT_VIEWS " == *" $view "* ]] || return 0
    _agents_now now
    [[ $now -lt $until ]] || return 0
    printf 'insight\t%s\t%s\n' "$view" "$text"
}

# _agents_tokens_line — the menu's tokens row, from tokens.today alone (the
# scanner's sums for the local day: DAY TOTAL IN CACHE_WRITE CACHE_READ OUT):
#   tokens TOTAL CACHE_PCT  when its day is today; nothing otherwise.
_agents_tokens_line() {
    [[ "$AGENTS_HISTORY" == 1 && -r "$AGENTS_DATA_DIR/tokens.today" ]] || return 0
    local d="" tot="" tin="" tcw="" tcr="" inputs hit=0
    IFS=$'\t' read -r d tot tin tcw tcr _ < "$AGENTS_DATA_DIR/tokens.today"
    [[ "$d" == "$(date +%Y-%m-%d)" && "$tot" =~ ^[0-9]{1,15}$ && "$tin" =~ ^[0-9]{1,15}$ \
       && "$tcw" =~ ^[0-9]{1,15}$ && "$tcr" =~ ^[0-9]{1,15}$ ]] || return 0
    inputs=$((10#$tin + 10#$tcw + 10#$tcr))
    # (bash 3.2 evaluates both arms of ?:, so no division in one.)
    [[ $inputs -eq 0 ]] || hit=$(( (10#$tcr * 100 + inputs / 2) / inputs ))
    printf 'tokens\t%s\t%s\n' "$((10#$tot))" "$hit"
}
