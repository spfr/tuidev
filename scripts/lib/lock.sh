#!/bin/bash
# scripts/lib/lock.sh - one update at a time. update.sh and install.sh take
# $TUIDEV_STATE_DIR/update.lock before they change anything, so an update
# started from the terminal, the menu bar and Herdr's popup at once runs
# once, and the others say who holds it. --dry-run and --check take none.
#
# Source after ui.sh. Idempotent; bash 3.2-clean.
#
#   tuidev_excl FILE TEXT     make FILE holding TEXT, only if it is not there:
#                             true for the one process that made it (bash's
#                             noclobber opens it with O_EXCL). bin/tuidev's
#                             _tuidev_excl is its twin (test_contract.sh).
#   tuidev_update_lock        take the lock, or say who holds it and fail
#   tuidev_update_unlock      release it, while it is still this process's
#
# The lock is a file holding its holder, "PID START" (START: when that
# process started, as ps prints it). Making it decides who holds it: mkdir
# is not used, since the mkdir of uutils coreutils (Ubuntu from 25.10) can
# succeed for two processes at once. A holder that is gone (no such pid, or
# the pid is another process now) is taken over, by one process at a time
# (update.lock.claim). Its own holder finds it
# held by itself after update.sh hands over with exec (same pid, same
# start), and keeps it.

if [[ -n "${_TUIDEV_LOCK_LOADED:-}" ]]; then
    return 0
fi
_TUIDEV_LOCK_LOADED=1

# shellcheck source=./ui.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/ui.sh"

_TUIDEV_LOCK_HELD=""

tuidev_excl() {
    local rc=0
    set -C
    { printf '%s\n' "$2" > "$1"; } 2>/dev/null || rc=1
    set +C
    return "$rc"
}

# _tuidev_proc_start PID — when PID started, as ps prints it; "" when ps
# can't tell (no such process, or a ps without lstart).
_tuidev_proc_start() {
    LC_ALL=C ps -o lstart= -p "$1" 2>/dev/null | awk 'NF { $1 = $1; print; exit }'
}

# _tuidev_holder_alive "PID START" — is that process still running? By its
# start time where ps gives one, else by kill -0.
_tuidev_holder_alive() {
    local pid="${1%% *}" start="" now
    [[ "$1" == *" "* ]] && start="${1#* }"
    [[ "$pid" =~ ^[0-9]+$ ]] || return 1
    if [[ -n "$start" && "$start" != - ]]; then
        now="$(_tuidev_proc_start "$pid")"
        if [[ -n "$now" ]]; then [[ "$now" == "$start" ]]; return; fi
    fi
    kill -0 "$pid" 2>/dev/null
}

tuidev_update_lock() {
    local lock="$TUIDEV_STATE_DIR/update.lock" me h="" start claim now _
    start="$(_tuidev_proc_start $$)"
    me="$$ ${start:--}"
    mkdir -p "$TUIDEV_STATE_DIR" 2>/dev/null || true
    for _ in 1 2 3; do   # a few goes: a takeover can lose a race
        if tuidev_excl "$lock" "$me"; then _TUIDEV_LOCK_HELD="$me"; return 0; fi
        h=""; { read -r h < "$lock"; } 2>/dev/null || true
        # This process already: update.sh handed over to a newer update.sh.
        if [[ "$h" == "$me" ]]; then _TUIDEV_LOCK_HELD="$me"; return 0; fi
        if [[ -z "$h" ]]; then
            # Its maker is between making it and writing it; one that died
            # right there leaves it empty, and after a minute it is taken.
            [[ -n "$(find "$lock" -maxdepth 0 -mmin +1 2>/dev/null)" ]] || break
        elif _tuidev_holder_alive "$h"; then
            break
        fi
        # Gone. One taker at a time: the claim is made like the lock, so of
        # several that saw the dead holder only the claim's maker looks again,
        # and removes the lock only while it still names that holder. (A
        # rename could move a live holder's file away and put it back over a
        # third process's lock.) A claim whose maker died goes after a minute.
        claim="$lock.claim"
        if ! tuidev_excl "$claim" "$me"; then
            [[ -z "$(find "$claim" -maxdepth 0 -mmin +1 2>/dev/null)" ]] || rm -f "$claim"
            sleep 0.2 2>/dev/null || sleep 1
            continue
        fi
        now=""; { read -r now < "$lock"; } 2>/dev/null || true
        [[ "$now" != "$h" ]] || rm -f "$lock"
        rm -f "$claim"
    done
    # The last go may have just cleared a dead holder's lock.
    if tuidev_excl "$lock" "$me"; then _TUIDEV_LOCK_HELD="$me"; return 0; fi
    h="${h%% *}"
    print_error "another tuidev update is running (pid ${h:-?}); try again when it has finished"
    print_info "The lock is $lock: remove it if no update is running."
    return 1
}

tuidev_update_unlock() {
    local lock="$TUIDEV_STATE_DIR/update.lock" h=""
    [[ -n "$_TUIDEV_LOCK_HELD" ]] || return 0
    { read -r h < "$lock"; } 2>/dev/null || true
    [[ "$h" != "$_TUIDEV_LOCK_HELD" ]] || rm -f "$lock"
    _TUIDEV_LOCK_HELD=""
    return 0
}
