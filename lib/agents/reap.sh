# shellcheck shell=bash
# lib/agents/reap.sh — what `agents reap` stops, by hand or on its own.
#
# Owns: the reap plan (stale trees; with --stuck, stuck polling loops),
#   each item's reason for the event log, and auto-reap (only what
#   agents_assess calls safe for it, at most once a minute from the menu).
# Uses: config.sh, util.sh (_agents_lock, the auto-reap stamp), snapshot.sh
#   (agents_collect), assess.sh (agents_assess), kill.sh, notify.sh.
# Public: agents_reap, agents_reap_auto, agents_reap_tokens,
#   agents_reap_reasons, agents_auto_tokens.

# agents_reap_tokens STUCK(true|false) < RECORDS — what reap kills: the
# PID@START of every stale tree and, with STUCK, of every polling loop
# flagged stuck (the loop's tool shell and its sleep).
agents_reap_tokens() {
    awk -F '\t' -v stuck="$1" '$1 == "stale" || (stuck == "true" && $1 == "act" && index("," $16 ",", ",stuck,")) { print $2 "@" $9 }'
}

# agents_reap_reasons < RECORDS — "pid<TAB>reason<TAB>session" for what
# `agents reap` stops: stale trees and stuck polling loops (session: the
# owning one, as kind:pid).
agents_reap_reasons() {
    awk -F '\t' '
        $1 == "agent" { k[$2] = $3 }
        $1 == "stale" { print $2 "\tstale\t-" }
        $1 == "act" && index("," $16 ",", ",stuck,") { print $2 "\tstuck\t" (($11 in k) ? k[$11] ":" $11 : "-") }'
}

# agents_auto_tokens < NEEDS — "PID@START<TAB>REASON<TAB>SESSION" for each
# item agents_assess marked for auto-reap.
agents_auto_tokens() {
    awk -F '\t' '$1 == "need" && $8 == 1 { print $2 "@" $3 "\t" $4 "\t" ($9 == "-" ? "-" : $12 ":" $9) }'
}

# _agents_auto_due — true at most once a minute (the menu runs auto-reap on
# every refresh that shows something it may stop). The stamp is read and
# written under a lock (mkdir is atomic), so two overlapping menu runs never
# both start a reap; a lock older than a minute is a leftover and is removed.
_agents_auto_due() {
    local f="$AGENTS_RUN_DIR/auto-reap" lock="$AGENTS_RUN_DIR/auto-reap.lock" now age rc=1
    mkdir -p "$AGENTS_RUN_DIR" 2>/dev/null || return 1
    _agents_lock "$lock" || return 1
    now="$(date +%s)"
    _agents_stamp_age age "$f" "$now"
    if [[ $age -ge 60 ]] && _agents_replace "$f" "$now"; then rc=0; fi
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

# agents_reap — `agents reap [--stuck|--auto]`: every stale tree (and, with
# --stuck, every stuck polling loop), through the kill engine.
agents_reap() {
    local recs tokens
    if [[ "$AGENTS_AUTO" == true ]]; then agents_reap_auto; return; fi
    recs="$(agents_collect)" || return 1
    tokens="$(printf '%s\n' "$recs" | agents_reap_tokens "$AGENTS_STUCK")"
    if [[ -z "$tokens" ]]; then
        if [[ "$AGENTS_STUCK" == true ]]; then echo "no stale processes or stuck polling loops"; else echo "no stale processes"; fi
        _agents_notify "Nothing to reap"; return 0
    fi
    # shellcheck disable=SC2086  # one token per word, none has spaces
    _AGENTS_EV_KIND=reap _AGENTS_EV_REASONS="$(printf '%s\n' "$recs" | agents_reap_reasons)" \
        agents_kill_tokens true $tokens
}
