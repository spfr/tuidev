# shellcheck shell=bash
# lib/agents/triage.sh — who needs you: every session in one of four states.
#
#   ▲ need     blocked: waiting for your answer
#   ◆ review   finished, not looked at, for under AGENTS_PARKED_MIN minutes
#   ● run      working
#   ○ parked   finished longer ago than that, or looked at and left idle
#   ? unknown  nothing says: not counted as any of those
#
# Herdr says what a session in one of its panes is: blocked, done, working or
# idle (it clears done once you look at the pane, so idle is parked at once:
# nothing is left to review). Claude Code's hooks say it for a session outside
# Herdr (waiting/, hooks.sh): blocked or done, from the moment it began. With
# neither (Codex in a plain tab, history off, no sample in the last hour, or
# Herdr not answering), all that can be known is whether it does anything:
# running while it runs a command or uses _AGENTS_BUSY_CPU% of a core. Otherwise
# it could as well be blocked as finished, so it gets a row of its own: parked
# means we know.
#
# How long comes from waits.now, and only from the latest stretch: Herdr numbers
# each state change, so its number tells a new stretch from an old record however
# old that is. Without one, a record older than _AGENTS_SAMPLE_FRESH seconds says
# nothing. Either way a session whose age can't be established stays to review
# with none shown: it never skips To review on a guess.
#
# Each `agents sample` rewrites two small files, so a refresh never reads all of
# waits.tsv (awk/waits_state.awk):
#   waits.now    TOKEN STATUS SINCE LAST SEQ  per live session blocked, done or
#                idle. SEQ: Herdr's number for that state change, "-" for none,
#                "~" when SINCE is only a lower bound (a gap with no number)
#   waits.today  DAY BLOCKED_S FRESH_S PARKED_S  today's waits by class
#
# Owns: the states (awk/triage.awk), those files, the view `agents` opens with
#   (awk/triage_view.awk) and `agents watch`.
# Uses: config.sh, util.sh, palette.sh, snapshot.sh (agents_collect), assess.sh
#   (_agents_with_needs), system.sh, awake.sh, lid.sh (_agents_lid_warning),
#   memory.sh (_agents_swap_high), history.sh (_agents_sample_kick).
# Public: agents_triage, agents_watch, _agents_triage_rows, _agents_waits_state,
#   _agents_waitsum_line.

_AGENTS_BUSY_CPU=3
# _AGENTS_SAMPLE_FRESH — samples run a minute apart while the menu or `agents
# watch` does: an older record has missed whatever happened since.
_AGENTS_SAMPLE_FRESH=180

# _agents_triage_rows RECORDS — the triage rows (awk/triage.awk). No fork but
# its one awk, and a tail of notify.tsv while a session blocks.
_agents_triage_rows() {
    local dir="$AGENTS_DATA_DIR" f line hooks="" notify="" now
    [[ -n "$1" ]] || return 0
    for f in "$dir"/waiting/*; do
        [[ -f "$f" ]] || continue
        line=""; IFS= read -r line < "$f" 2>/dev/null || [[ -n "$line" ]] || continue
        hooks+="$line"$'\n'
    done
    case "$hooks$1" in
        *$'\tblocked\t'*) notify="$(tail -n 64 "$dir/notify.tsv" 2>/dev/null)" ;;
    esac
    _agents_now now
    printf '%s\n' "$1" | T_HOOKS="$hooks" T_NOTIFY="$notify" \
        _agents_awk "lib_fmt triage" -v now="$now" -v PARKED_S=$((AGENTS_PARKED_MIN * 60)) -v wf="$dir/waits.now" -v busy="$_AGENTS_BUSY_CPU" -v fresh="$_AGENTS_SAMPLE_FRESH"
}

# _agents_waits_state NOW DAY ROWS ENRICHED_RECORDS — after a sample appended
# ROWS to waits.tsv, update waits.now and waits.today. The first time (no
# waits.now), the whole file: sessions parked before this version knew the word
# are parked now, and today's numbers are counted from it alone.
_agents_waits_state() {
    # shellcheck disable=SC2034  # _agents_window sets off and period too
    local dir="$AGENTS_DATA_DIR" gap=999999999 first="" rows="$3" mid start off period now="$1"
    if [[ ! -f "$dir/waits.now" ]]; then
        first=1 gap="$_AGENTS_WAIT_CAP"
        rows="$(cat "$dir/waits.tsv" 2>/dev/null)"
    fi
    _agents_window today "$now" || return 0
    mid="$start"
    { printf '%s\n' "$4"; [[ -z "$rows" ]] || printf '%s\n' "$rows"; } \
        | _agents_awk "lib_waits waits_state" -F '\t' -v sf="$dir/waits.now" -v tf="$dir/waits.today" \
            -v now="$now" -v day="$2" -v mid="$mid" -v PARKED_S=$((AGENTS_PARKED_MIN * 60)) -v gap="$gap" \
            -v first="$first" -v fresh="$_AGENTS_SAMPLE_FRESH" || return 1
    [[ ! -f "$dir/waits.now.new" ]] || mv -f "$dir/waits.now.new" "$dir/waits.now"
    mv -f "$dir/waits.today.new" "$dir/waits.today"
}

# _agents_waitsum_line — the menu's row, from waits.today alone:
#   waitsum BLOCKED_S FRESH_S PARKED_S  when its day is today.
_agents_waitsum_line() {
    [[ "$AGENTS_HISTORY" == 1 && -r "$AGENTS_DATA_DIR/waits.today" ]] || return 0
    local d="" b="" f="" p="" today
    IFS=$'\t' read -r d b f p < "$AGENTS_DATA_DIR/waits.today"
    today="$(date +%Y-%m-%d)"
    [[ "$d" == "$today" && "$b" =~ ^[0-9]+$ && "$f" =~ ^[0-9]+$ && "$p" =~ ^[0-9]+$ ]] || return 0
    printf 'waitsum\t%s\t%s\t%s\n' "$b" "$f" "$p"
}

# _agents_status_line RECORDS — the one compact line under the triage: CPU,
# memory, thermal pressure, keep-awake.
_agents_status_line() {
    local lvl cores memfree level aw cpu=- dot='·'
    _agents_utf8 || dot=-
    lvl="$(agents_thermal_level)"
    IFS=$'\t' read -r _ cores memfree level _ <<<"$(agents_system)"
    cpu="$(_agents_cpu_pct "$cores" "$1")"
    aw="$(agents_awake_line)"; aw="${aw#awake: }"; aw="${aw%% (*}"
    printf 'cpu %s%% %s mem %s%% free%s %s thermal %s %s awake %s' "$cpu" "$dot" "$memfree" \
        "$([[ "$level" == - || "$level" == normal ]] || echo " ($level pressure)")" \
        "$dot" "$(agents_thermal_name "${lvl:--}")" "$dot" "$aw"
}

# _agents_triage_render RECORDS — the view (awk/triage_view.awk): the summary,
# Needs you, To review, Running and No signal, one parked line, one system line.
# Empty groups disappear; below 72 columns it folds to the narrow form.
_agents_triage_render() {
    local swap=""
    _agents_swap_high && swap="$REPLY"
    _agents_with_needs "$1" | SYSLINE="$(_agents_status_line "$1")" SWAP="$swap" W="${AGENTS_WIDTH:-80}" \
        _agents_awk_colored "lib_fmt triage_view" -F '\t'
    _agents_lid_warning
}

# agents_triage — `agents`.
agents_triage() {
    local r
    _agents_awake_prime
    r="$(agents_collect)" || return 1
    _agents_triage_render "$r"
}

# agents_watch [SECONDS] — the triage, redrawn.
agents_watch() {
    local secs="${1:-2}" out key
    [[ "$secs" =~ ^[1-9][0-9]*$ ]] || { echo "usage: agents watch [SECONDS]" >&2; return 2; }
    trap 'tput cnorm 2>/dev/null; echo; exit 0' INT TERM
    tput civis 2>/dev/null
    while :; do
        _agents_awake_prime
        _agents_sample_kick          # history, where no menu bar samples it
        out="$(_agents_triage_render "$(agents_collect)")"
        printf '\033[H\033[2J%sagents · %s · every %ss · q quit%s\n\n%s\n' "$C_DIM" "$(date +%H:%M:%S)" "$secs" "$C_0" "$out"
        if [[ -t 0 ]]; then
            read -r -s -n 1 -t "$secs" key && [[ "$key" == q ]] && break
        else
            sleep "$secs"
        fi
    done
    tput cnorm 2>/dev/null
}
