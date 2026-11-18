# shellcheck shell=bash
# lib/agents/hcphone.sh — what Herdr's phone app reaches on this machine.
# The phone lists herdr-core's terminals: the agents hosted there (`agents hc
# run`, automatic hosting) and the mirrors of Herdr panes (hcmirror.sh). This
# module says which those are, in three places:
#   - `agents hc ls`: one line a core terminal (its name, hosted or a mirror,
#     its state as the core has it, its directory), then one line for the
#     agent panes of this machine's Herdr the phone cannot reach, and why;
#   - the menu's `hc` record (tsv.sh): the core's state and how many mirrors;
#   - the board's mark (board.sh, awk/board_rows.awk): which sessions the
#     phone reaches, as hosted or mirrored, and which panes are opted out.
# The menu and the board read a cache in the run dir that a background check
# rewrites at most every 30 s: drawing either asks the core nothing, and
# nothing here ever starts a core (every herdr-core client command starts
# one, so a core is asked only after _agents_hc_running found one). Every
# call has hc.sh's time limit, and an answer that is not one says nothing.
#
# Owns: `agents hc ls`, hc-phone.cache and hc-phone.lock.
# Uses: config.sh (AGENTS_RUN_DIR), util.sh (_agents_timeout, _agents_lock,
#   _agents_unlock, _agents_replace, _agents_detach, _agents_now,
#   _agents_stamp_age), herdrlabel.sh (_agents_hl_ready), hc.sh
#   (_agents_hc_bin, _agents_hc_need, _agents_hc_running, _agents_hc_hello,
#   _agents_hc_gui, _agents_hc_is_mac, _agents_hc_marks, _AGENTS_HC_ID_RE,
#   _AGENTS_HC_WAIT), hcmirror.sh (_agents_hm_on, _agents_hm_list,
#   _agents_hm_have_of, _agents_hm_want, _agents_hm_off_read,
#   _agents_hm_is_off, _AGENTS_HM_LABEL, _AGENTS_HM_PANE_RE).
# Public: agents_hc_ls, _agents_hc_phone_rows (the menu's record, tsv.sh),
#   _agents_hc_phone_feed (the board's rows, board.sh).

# _agents_hc_phone [--reach] — herdr-core's phone status as one line for the
# menu (STATE, GUI and MIRRORS, tab-separated), or nothing:
#   down      TAB -    TAB 0   installed, no core runs
#   headless  TAB no   TAB 0   running outside the desktop login (macOS)
#   core      TAB GUI  TAB 0   running, mirrors off (the default); GUI as below
#   up        TAB GUI  TAB N   running, mirrors on; N live mirrors, GUI yes,
#                              no or unknown
# Nothing when herdr-core is not installed, when mirrors are off and no core
# runs, and when the core did not answer in time (never a guess). While no
# core runs it is file tests only, no call; a running one is asked `hello`
# and, with mirrors on, `terminal.list`, each under _AGENTS_HC_WAIT.
#
# With --reach (the cache's check), also what the phone reaches, after that
# line: "phone<TAB>PANE<TAB>mirror<TAB>NAME" for each live mirror (from
# terminal.list, asked with mirrors off too; none when it did not answer),
# then "phone<TAB>PANE<TAB>hosted<TAB>NAME" for each pane on a hosted agent
# (hc.sh's marks, no call).
_agents_hc_phone() {
    local reach=false hello gui st list have="" ok=false n=0 addr pane name
    [[ "${1:-}" != --reach ]] || reach=true
    command -v jq >/dev/null 2>&1 && _agents_hc_bin || return 0
    if ! _agents_hc_running; then
        ! _agents_hm_on || printf 'down\t-\t0\n'
        return 0
    fi
    hello="$(_agents_hc_hello)"
    [[ -n "$hello" ]] || return 0
    gui="$(_agents_hc_gui "$hello")"
    if [[ "$gui" == false ]] && _agents_hc_is_mac; then
        st=headless gui=no
    else
        case "$gui" in true) gui=yes ;; false) gui=no ;; *) gui=unknown ;; esac
        st=core
        ! _agents_hm_on || st=up
    fi
    if [[ "$st" == up || "$reach" == true ]]; then
        list="$(_agents_hm_list)" && have="$(_agents_hm_have_of "$list")" && ok=true
        [[ "$ok" == true || "$st" != up ]] || return 0
    fi
    [[ "$st" != up ]] || n="$(printf '%s\n' "$have" | grep -c .)"
    printf '%s\t%s\t%s\n' "$st" "$gui" "$n"
    [[ "$reach" == true ]] || return 0
    if [[ "$ok" == true ]]; then
        while IFS=$'\x1f' read -r addr pane name; do
            [[ "$pane" =~ $_AGENTS_HM_PANE_RE && "$addr" =~ $_AGENTS_HC_ID_RE ]] || continue
            [[ "$name" =~ $_AGENTS_HC_ID_RE ]] || name="$addr"
            printf 'phone\t%s\tmirror\t%s\n' "$pane" "$name"
        done <<<"$have"
    fi
    while IFS=$'\x1f' read -r pane addr name; do
        [[ -z "$pane" ]] || printf 'phone\t%s\thosted\t%s\n' "$pane" "$name"
    done <<<"$(_agents_hc_marks)"
}

# _agents_hc_phone_rows — the menu's `hc STATE GUI MIRRORS` record, from a
# cache in the run dir that a background check rewrites at most every
# _AGENTS_HC_PHONE_TTL seconds (never waited on: the first refresh after it
# has nothing, like _agents_herdr_health). Nothing without herdr-core
# installed, so a machine without it starts nothing, and not under the test
# harness (AGENTS_TESTING; a test unsets it).
_AGENTS_HC_PHONE_TTL=30
_agents_hc_phone_rows() {
    [[ -z "${AGENTS_TESTING:-}" ]] || return 0
    local cache="$AGENTS_RUN_DIR/hc-phone.cache" now age line=""
    _agents_hc_bin || return 0
    _agents_now now
    _agents_stamp_age age "$cache" "$now"
    if [[ -r "$cache" ]]; then
        { read -r _; read -r line; } < "$cache" || true
    fi
    if [[ $age -ge $_AGENTS_HC_PHONE_TTL ]]; then
        _agents_detach _agents_hc_phone_refresh
    fi
    [[ -z "$line" ]] || printf 'hc\t%s\n' "$line"
    return 0
}

# Rewrite the cache (one check at a time): the epoch, the menu's line (empty
# for none), then what the phone reaches (_agents_hc_phone --reach). Its stamp
# is written even when the core did not answer, so one that hangs is asked
# once per TTL, not per refresh.
_agents_hc_phone_refresh() {
    local lock="$AGENTS_RUN_DIR/hc-phone.lock" out
    mkdir -p "$AGENTS_RUN_DIR" 2>/dev/null || return 0
    _agents_lock "$lock" || return 0
    out="$(_agents_hc_phone --reach)"
    _agents_replace "$AGENTS_RUN_DIR/hc-phone.cache" "$(date +%s)${out:+$'\n'$out}" || true
    _agents_unlock "$lock"
    return 0
}

# _agents_hc_phone_feed — what the board's rows (awk/board_rows.awk) take from
# the phone: "phonecore" while herdr-core is installed, then the cache's
# "phone" lines and "phoneoff<TAB>PANE" for each pane opted out of mirrors.
# Files only, read by bash (no fork); a cache older than the TTL is checked
# again in the background, as for the menu. Nothing without herdr-core, so
# the board stays as it was. Under the test harness only with a stand-in
# (AGENTS_HC_BIN), and never a check.
_agents_hc_phone_feed() {
    local cache="$AGENTS_RUN_DIR/hc-phone.cache" now age line p
    [[ -z "${AGENTS_TESTING:-}" || -n "${AGENTS_HC_BIN:-}" ]] || return 0
    _agents_hc_bin || return 0
    printf 'phonecore\n'
    if [[ -r "$cache" ]]; then
        { read -r _; read -r _
          while IFS= read -r line; do [[ "$line" != phone$'\t'* ]] || printf '%s\n' "$line"; done
        } < "$cache" 2>/dev/null || true
    fi
    _agents_hm_off_read
    while IFS= read -r p; do [[ -z "$p" ]] || printf 'phoneoff\t%s\n' "$p"; done <<<"$REPLY"
    [[ -z "${AGENTS_TESTING:-}" ]] || return 0
    _agents_now now
    _agents_stamp_age age "$cache" "$now"
    [[ $age -lt $_AGENTS_HC_PHONE_TTL ]] || _agents_detach _agents_hc_phone_refresh
    return 0
}

# The core's terminals from terminal.list: ADDRESS, NAME, STATE (live or
# finished), STATUS (the word the program last reported: working, blocked,
# idle, done, error; "" for none), MIRROR (the pane a mirror shows; "" for
# any other terminal), DIRECTORY (where its program runs now, else where it
# started) and EXIT (its exit code once finished), unit separators between
# them. A field herdr-core does not send is "". An error (jq exits 5) when
# the answer has no list of terminals.
# shellcheck disable=SC2016  # jq's $names, not the shell's
_AGENTS_HC_LS_JQ='
if (.result.terminals | type) != "array" then error("no list") else . end
| .result.terminals[] | objects
| [(.address // ""), (.name // ""), (.state // ""),
   ((.status | objects | .state) // (.status | strings) // ""),
   (((.labels // {}) | objects | .[$l]) // ""),
   ((.foreground | objects | .cwd) // .cwd // ""),
   ((.exit | objects | .code) // .exit_code // "")]
| map(tostring | gsub("[\u0000-\u001f\u007f]"; " ") | .[0:160]) | join("\u001f")'

# _agents_hc_ls_state STATE STATUS EXIT — REPLY: the state in a word or two.
_agents_hc_ls_state() {
    if [[ "$1" != live ]]; then REPLY="finished"; [[ -z "$3" ]] || REPLY="exited $3"; return 0; fi
    case "$2" in
        blocked|error) REPLY="needs you" ;;
        "")            REPLY="live" ;;
        *)             REPLY="$2" ;;
    esac
}

# agents_hc_ls — what the phone lists from this machine: each of the core's
# terminals, then the agent panes of this machine's Herdr it cannot reach.
# Never starts a core: "not running" when none runs. One terminal.list and,
# with Herdr here, one snapshot, each under its time limit. A core that does
# not answer (or an answer that is not a list) is one line and a non-zero
# exit; it changes nothing.
agents_hc_ls() {
    local list rows hosted want="" herdr=false addr name state status pane cwd code kind dir line
    local mirrored=$'\n' off p agent n_off=0 n_disabled=0 n_yet=0 n_agents=0 why=""
    _agents_hc_need || return 1
    if ! _agents_hc_running; then
        echo "herdr-core is not running here, so the phone reaches nothing on this machine (agents hc up starts it)"
        return 1
    fi
    if ! list="$(_agents_hm_list)" \
        || ! rows="$(printf '%s\n' "$list" | jq -r --arg l "$_AGENTS_HM_LABEL" "$_AGENTS_HC_LS_JQ" 2>/dev/null)"; then
        echo "herdr-core did not answer within ${_AGENTS_HC_WAIT} s; nothing is listed" >&2
        return 1
    fi
    hosted="$(_agents_hc_marks)"
    if _agents_hl_ready; then
        herdr=true
        want="$(_agents_hm_want)" || herdr=unanswered
    fi
    if [[ -z "$rows" ]]; then
        echo "The phone lists nothing from this machine: herdr-core has no terminals"
    else
        echo "The phone lists from this machine (herdr-core's terminals):"
        while IFS=$'\x1f' read -r addr name state status pane cwd code; do
            [[ -n "$addr" ]] || continue
            [[ -n "$name" ]] || name="$addr"
            if [[ -n "$pane" ]]; then
                [[ "$state" != live ]] || mirrored+="$pane"$'\n'
                kind="mirror of $pane"
                while IFS=$'\x1f' read -r p _ _ agent _ _ _; do
                    [[ "$p" != "$pane" || -z "$agent" ]] || { kind+=" ($agent)"; break; }
                done <<<"$want"
            else
                kind="hosted"
                while IFS=$'\x1f' read -r p line _; do
                    [[ "$line" != "$addr" ]] || { kind+=", in pane $p"; break; }
                done <<<"$hosted"
            fi
            _agents_hc_ls_state "$state" "$status" "$code"
            dir="${cwd:--}"
            # shellcheck disable=SC2088  # a ~ to read, not to expand
            [[ "$dir" != "$HOME"/* ]] || dir="~/${dir#"$HOME"/}"
            printf '  %-22s %-28s %-12s %s\n' "$name" "$kind" "$REPLY" "$dir"
        done <<<"$rows"
    fi
    case "$herdr" in
        false)      return 0 ;;
        unanswered) echo "Herdr did not answer within ${_AGENTS_HC_HERDR_WAIT} s: its agent panes are not counted"; return 0 ;;
    esac
    _agents_hm_off_read; off="$REPLY"
    while IFS=$'\x1f' read -r p _ _ agent _ _ _; do
        [[ -n "$p" ]] || continue
        n_agents=$((n_agents + 1))
        [[ "$mirrored" != *$'\n'"$p"$'\n'* ]] || continue
        # The mark itself: one the release before wrote names no terminal.
        ! _agents_hc_pane_marked "$p" || continue
        if _agents_hm_is_off "$p" "$off"; then n_off=$((n_off + 1))
        elif ! _agents_hm_on; then n_disabled=$((n_disabled + 1))
        else n_yet=$((n_yet + 1)); fi
    done <<<"$want"
    if [[ $n_agents -eq 0 ]]; then echo "No agent panes in this machine's Herdr"; return 0; fi
    if [[ $((n_off + n_disabled + n_yet)) -eq 0 ]]; then echo "Every agent pane of this machine's Herdr is on the phone"; return 0; fi
    [[ $n_off -eq 0 ]] || why+=", $n_off opted out (agents hc mirror on PANE)"
    [[ $n_disabled -eq 0 ]] || why+=", $n_disabled with mirrors off (AGENTS_HC_MIRROR=1 in agents.conf)"
    [[ $n_yet -eq 0 ]] || why+=", $n_yet not mirrored yet (agents hc mirror sync)"
    p=s; [[ $((n_off + n_disabled + n_yet)) -ne 1 ]] || p=""
    echo "Not on the phone: $((n_off + n_disabled + n_yet)) agent pane$p of this machine's Herdr: ${why#, }"
}
