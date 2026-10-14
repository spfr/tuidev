# shellcheck shell=bash
# lib/agents/tsv.sh — `agents tsv`, what the SwiftBar plugin
# (configs/swiftbar/agents.10s.sh) reads every refresh.
#
# Uses: config.sh, snapshot.sh (agents_collect), assess.sh
#   (_agents_with_needs), system.sh, awake.sh, lid.sh, history.sh
#   (_agents_hist_line), report.sh (_agents_insight_line).
# Public: agents_tsv.

# agents_tsv — agents_assess's need/evid rows (first, so the menu knows an
# item's verdict when it meets the item), the records (agent, stale, hog, top,
# total, act, watched), then:
#   sys  cpu_pct load1 cores mem_free_pct mem_pressure battery_pct battery_state
#   awake mode pid until · thermal level name · power mode
#   hist state today_cpu_s top_job top_job_cpu_s  (_agents_hist_line)
#   insight view text  today's top insight, while current (_agents_insight_line)
#   lid on|off|stale guard_pid until max_secs  (keep-awake with the lid closed)
#   conf KEY VALUE  for each AGENTS_BAR_* setting ("-" = empty)
# Built for the menu bar: Herdr is read from its cache (never waited on), and
# the keep-awake state is read once. Each refresh also feeds the run ledger
# (agents_collect with _AGENTS_FEED, runs.sh), so commands shorter than the
# minute between samples are recorded too.
agents_tsv() {
    local recs state pid="-" mode="off" until=0 lvl sys key val cores lmax lpid luntil
    # One clock for the whole refresh (_agents_now), unless the caller set it.
    local AGENTS_NOW="${AGENTS_NOW:-}"
    [[ -n "$AGENTS_NOW" ]] || AGENTS_NOW="$(date +%s)"
    _agents_awake_prime
    recs="$(AGENTS_HERDR_MODE=async _AGENTS_FEED=1 agents_collect)" || return 1
    _agents_with_needs "$recs"
    sys="$(agents_system)"
    cores="${sys#*$'\t'}"; cores="${cores%%$'\t'*}"
    printf 'sys\t%s\t%s\n' "$(_agents_cpu_pct "$cores" "$recs")" "$sys"
    state="$(_agents_awake_now)" && read -r pid mode until _ <<<"$state"
    lvl="$(agents_thermal_level)"
    printf 'awake\t%s\t%s\t%s\n' "$mode" "$pid" "$until"
    printf 'thermal\t%s\t%s\n' "${lvl:--}" "$(agents_thermal_name "${lvl:--}")"
    printf 'power\t%s\n' "$(agents_powermode)"
    _agents_hist_line
    _agents_insight_line
    lmax="$(_agents_lid_max)"
    if state="$(agents_lid_state)"; then
        read -r lpid luntil _ <<<"$state"; printf 'lid\ton\t%s\t%s\t%s\n' "$lpid" "$luntil" "$lmax"
    elif agents_lid_stale; then
        printf 'lid\tstale\t-\t0\t%s\n' "$lmax"
    else
        printf 'lid\toff\t-\t0\t%s\n' "$lmax"
    fi
    for key in AGENTS_BAR_TITLE AGENTS_BAR_SECTIONS AGENTS_BAR_ICON AGENTS_BAR_TOP AGENTS_BAR_REFRESH AGENTS_LID AGENTS_CONF AGENTS_AUTO_REAP; do
        val="${!key}"
        printf 'conf\t%s\t%s\n' "$key" "${val:--}"
    done
}
