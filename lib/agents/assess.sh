# shellcheck shell=bash
# lib/agents/assess.sh — Needs you: evidence and a verdict.
#
# Why an item is listed, how far to trust that, and what to do about it. The
# verdict is made in one place, agents_assess; `agents why`, `json`, `tsv` (the
# menu) and auto-reap only read its rows.
#
# Owns: agents_assess (awk/assess.awk) and `agents why`.
# Uses: config.sh, util.sh, snapshot.sh (agents_collect), render.sh (colors).
# Public: agents_assess, agents_why, _agents_with_needs.

# agents_assess [PID] < RECORDS — evidence and a verdict for each item that
# needs you (stale trees; commands flagged stuck, long or dup), or with PID,
# for that one item whatever it is. Two row types:
#   need PID START FLAG ACTION CONF CODE AUTO OWNER SHORT VERDICT OKIND OPROJ
#        AGE CPU PORTS WATCHED QUIET LAST MARKER
#   evid PID fact|next|auto TEXT
# FLAG: stale stuck long dup wait tool mcp keepawake session other agent hog.
# ACTION: stop (safe to stop), check (check first), leave (leave it), info.
# CONF: high medium low, how sure the verdict is. AUTO: 1 when auto-reap may
# stop it: a stale tree that listens on no port (the ports could be listed:
# the "probe listen" row), that a sample saw under an agent before it was
# orphaned (sample.state; never a caffeinate without -t), or a stuck loop
# whose condition reads its watched file and that file has been quiet for
# 2 x AGENTS_WAIT_STUCK. OWNER: the owning session's pid ("-" once it ended).
# QUIET: seconds since the watched file changed. MARKER: 1 when its last line
# says the work it waits for has finished.
agents_assess() {
    local now
    _agents_now now
    AGENTS_TARGET="${1:-}" NOW="$now" HOME="$HOME" AGENTS_WAIT_STUCK="$AGENTS_WAIT_STUCK" \
    AGENTS_AUTO_REAP="$AGENTS_AUTO_REAP" AGENTS_HISTORY="$AGENTS_HISTORY" AGENTS_SEEN="$AGENTS_DATA_DIR/sample.state" \
    _agents_awk assess -F '\t' -v OFS='\t'
}

# _agents_with_needs RECORDS — agents_assess rows first, then the records
# (agents_json and the menu build an item when they meet it, so they need its
# verdict before that).
_agents_with_needs() {
    [[ -n "$1" ]] || return 0
    printf '%s\n' "$1" | agents_assess
    printf '%s\n' "$1"
}

# _agents_why_text NEEDS RECORDS — `agents why` as text, from agents_assess
# rows for one pid and the records (for the command line).
_agents_why_text() {
    local type pid start flag conf verdict cmd what kind text facts="" next="" autot=""
    while IFS=$'\t' read -r type pid kind text; do
        [[ "$type" == evid ]] || continue
        case "$kind" in
            fact) facts+="  $text"$'\n' ;;
            next) next+="  $text"$'\n' ;;
            auto) autot="  $text"$'\n' ;;
        esac
    done <<<"$1"
    IFS=$'\t' read -r type pid start flag _ conf _ _ _ _ verdict _ <<<"$(printf '%s\n' "$1" | awk -F '\t' '$1 == "need" { print; exit }')"
    cmd="$(printf '%s\n' "$2" | awk -F '\t' -v p="$pid" -v t="$flag" 'NF >= 14 && $2 == p && (t == "hog") == ($1 == "hog") { print ($1 == "hog" ? $3 : $14); exit }')"
    case "$flag" in
        stale) what="stale process (its session ended)" ;;
        stuck) what="stuck polling loop" ;;
        wait)  what="polling loop" ;;
        long)  what="long-running command" ;;
        dup)   what="duplicate command" ;;
        tool)  what="command" ;;
        mcp)   what="MCP server" ;;
        keepawake) what="keep-awake helper" ;;
        session) what="nested agent session" ;;
        agent) what="agent session" ;;
        hog)   what="CPU hog" ;;
        *)     what="process" ;;
    esac
    [[ ${#cmd} -le 200 ]] || cmd="${cmd:0:197}..."
    printf '%s%s%s · pid %s@%s\n  %s\n\n' "$C_B" "$what" "$C_0" "$pid" "$start" "$cmd"
    printf '%sverdict:%s %s\nconfidence: %s\n\n' "$C_B" "$C_0" "$verdict" "$conf"
    printf '%sevidence:%s\n%s\n' "$C_B" "$C_0" "$facts"
    printf '%snext:%s\n%s%s' "$C_B" "$C_0" "$next" "$autot"
}

# agents_why [--copy] PID[@START] — the evidence and verdict for one item;
# --copy puts the text on the clipboard instead (the menu's Copy details).
agents_why() {
    local copy="" token="" a pid want="" recs now needs text
    for a in "$@"; do
        case "$a" in
            --copy) copy=1 ;;
            -*)     echo "agents: unknown option $a" >&2; return 2 ;;
            *)      token="$a" ;;
        esac
    done
    if [[ ! "$token" =~ $_AGENTS_TOKEN_RE ]]; then
        echo "usage: agents why [--copy] PID[@START]" >&2; return 2
    fi
    pid="${BASH_REMATCH[1]}" want="${BASH_REMATCH[3]}"
    recs="$(AGENTS_HERDR_MODE="${copy:+async}" agents_collect)" || return 1
    now="$(printf '%s\n' "$recs" | awk -F '\t' -v p="$pid" 'NF >= 14 && $2 == p { print $9; exit }')"
    if [[ -n "$want" && -n "$now" && "$now" != "$want" ]]; then
        echo "agents: pid $pid now names another process (not the one listed)" >&2; return 1
    fi
    needs="$(printf '%s\n' "$recs" | agents_assess "$pid")"
    if [[ -z "$needs" ]]; then
        echo "agents: pid $pid is not a session, a command a session runs, a stale process or a hog" >&2; return 1
    fi
    if [[ -n "$copy" ]]; then
        text="$(C_B='' C_0='' _agents_why_text "$needs" "$recs")"
        if command -v pbcopy >/dev/null 2>&1; then printf '%s\n' "$text" | pbcopy; else printf '%s\n' "$text"; fi
        return 0
    fi
    _agents_why_text "$needs" "$recs"
}
