# shellcheck shell=bash
# lib/agents/reap.sh — what `agents reap` stops, by hand or on its own.
#
# Owns: the reap plan (stale trees; with --stuck, stuck polling loops: by
#   hand only what agents_assess calls safe to stop, unless --all), each
#   item's reason for the event log, and auto-reap (only what agents_assess
#   calls safe for it, at most once a minute from the menu).
# Uses: config.sh, util.sh (_agents_lock, the auto-reap stamp), snapshot.sh
#   (agents_collect), assess.sh (agents_assess), kill.sh, notify.sh.
# Public: agents_reap, agents_reap_auto, agents_reap_items, agents_auto_tokens.

# agents_reap_items STUCK ALL(true|false) < NEEDS — what `agents reap` stops,
# read from agents_assess's verdicts: each stale tree and, with STUCK, each
# polling loop flagged stuck (the loop's tool shell and its sleep) that is
# "safe to stop"; with ALL, the "check first" ones too. One line each:
#   take PID@START REASON SESSION VERDICT   REASON: stale or stuck; SESSION:
#                                           the owning one as kind:pid, or -
#   skip PID - - VERDICT                    "check first", left out (no ALL)
agents_reap_items() {
    awk -F '\t' -v OFS='\t' -v stuck="$1" -v all="$2" '
        $1 != "need" || !($4 == "stale" || (stuck == "true" && $4 == "stuck")) || seen[$2]++ { next }
        $5 == "stop" || all == "true" { print "take", $2 "@" $3, $4, (($9 == "-" || $12 == "-") ? "-" : $12 ":" $9), $11; next }
        { print "skip", $2, "-", "-", $11 }'
}

# agents_auto_tokens < NEEDS — "PID@START<TAB>REASON<TAB>SESSION" for each
# item agents_assess marked for auto-reap.
agents_auto_tokens() {
    awk -F '\t' '$1 == "need" && $8 == 1 { print $2 "@" $3 "\t" $4 "\t" ($9 == "-" ? "-" : $12 ":" $9) }'
}

# _agents_auto_due — true once a minute at most (_AGENTS_MINUTE_DUE: 55 s, so
# a menu on a 60 s timer gets one each refresh; the menu runs auto-reap on
# every refresh that shows something it may stop). The stamp is read and
# written under a lock (_agents_lock), so two overlapping menu runs never
# both start a reap; a lock whose holder is gone is taken over (_agents_lock).
_agents_auto_due() {
    local f="$AGENTS_RUN_DIR/auto-reap" lock="$AGENTS_RUN_DIR/auto-reap.lock" now age rc=1
    mkdir -p "$AGENTS_RUN_DIR" 2>/dev/null || return 1
    _agents_lock "$lock" || return 1
    now="$(date +%s)"
    _agents_stamp_age age "$f" "$now"
    if [[ $age -ge $_AGENTS_MINUTE_DUE ]] && _agents_replace "$f" "$now"; then rc=0; fi
    _agents_unlock "$lock"
    return $rc
}

# agents_reap_auto — `agents reap --auto`: stop, without asking, only what
# agents_assess calls safe for that (stale trees a sample saw under an agent
# that listen on no port, when ports could be listed; loops stuck reading a
# file quiet for 2 x AGENTS_WAIT_STUCK). Never a long command, a listener, an
# age-only or exists-only stuck loop, or a caffeinate without -t. The usual PID@START kill with its grace
# period; each tree is logged (auto) and one notification sums them up.
agents_reap_auto() {
    local recs plan tokens="" reasons="" t r s notify="$AGENTS_NOTIFY"
    if [[ "${AGENTS_THROTTLE:-false}" == true ]] && ! _agents_auto_due; then return 0; fi
    recs="$(AGENTS_HERDR_MODE=async agents_collect)" || return 1
    plan="$(printf '%s\n' "$recs" | agents_assess | agents_auto_tokens)"
    if [[ -z "$plan" ]]; then
        echo "nothing to reap automatically"
        return 0
    fi
    while IFS=$'\t' read -r t r s; do
        [[ -n "$t" ]] || continue
        tokens+=" $t"; reasons+="${t%%@*}"$'\t'"$r"$'\t'"$s"$'\n'
    done <<<"$plan"
    # shellcheck disable=SC2086  # one token per word, none has spaces
    _AGENTS_EV_KIND=auto _AGENTS_EV_REASONS="$reasons" _agents_kill_unattended $tokens || return $?
    [[ "${_AGENTS_EV_N:-0}" -gt 0 ]] || return 0
    AGENTS_NOTIFY="$notify" _agents_notify "Auto-reap stopped $_AGENTS_EV_N: $_AGENTS_EV_DONE"
}

# _agents_reap_left N — what to say about N items left out as "check first".
_agents_reap_left() {
    printf 'left out: %s flagged "check first" (agents reap --all includes them; agents why PID explains one)\n' "$1"
}

# agents_reap — `agents reap [--stuck] [--all] | --auto`: each stale tree
# (and, with --stuck, each stuck polling loop) that agents_assess calls safe
# to stop, or with --all every one, through the kill engine. The plan shows
# each item's verdict and how many were left out; when every item is "check
# first" it says so and asks nothing.
agents_reap() {
    local recs kind t r s text tokens="" reasons="" notes="" left=0
    if [[ "$AGENTS_AUTO" == true ]]; then agents_reap_auto; return; fi
    recs="$(agents_collect)" || return 1
    while IFS=$'\t' read -r kind t r s text; do
        case "$kind" in
            take) tokens+=" $t"; reasons+="${t%%@*}"$'\t'"$r"$'\t'"$s"$'\n'; notes+="${t%%@*}"$'\t'"$text"$'\n' ;;
            skip) left=$((left + 1)) ;;
        esac
    done <<<"$(printf '%s\n' "$recs" | agents_assess | agents_reap_items "$AGENTS_STUCK" "${AGENTS_ALL:-false}")"
    if [[ -z "$tokens" && $left -gt 0 ]]; then
        printf 'nothing safe to stop; '; _agents_reap_left "$left"
        _agents_notify "Nothing safe to reap: $left to check first"; return 0
    elif [[ -z "$tokens" ]]; then
        if [[ "$AGENTS_STUCK" == true ]]; then echo "no stale processes or stuck polling loops"; else echo "no stale processes"; fi
        _agents_notify "Nothing to reap"; return 0
    fi
    # shellcheck disable=SC2086  # one token per word, none has spaces
    _AGENTS_KILL_NOTES="$notes" _AGENTS_KILL_AFTER="$([[ $left -eq 0 ]] || _agents_reap_left "$left")" \
        _AGENTS_EV_KIND=reap _AGENTS_EV_REASONS="$reasons" agents_kill_tokens true $tokens
}
