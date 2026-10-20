# shellcheck shell=bash
# lib/agents/tsv.sh — `agents tsv`, what the SwiftBar plugin
# (configs/swiftbar/agents.10s.sh) reads every refresh.
#
# Uses: config.sh, util.sh (_agents_bg), snapshot.sh (agents_collect,
#   _agents_herdr_health),
#   assess.sh (_agents_with_needs), system.sh, awake.sh, lid.sh, history.sh
#   (_agents_hist_line), report.sh (_agents_insight_line,
#   _agents_tokens_line), mcp.sh (_agents_mcp_load, agents_mcp_tsv), cool.sh
#   (_agents_cool_row).
# Public: agents_tsv.

# agents_tsv — agents_assess's need/evid rows (first, so the menu knows an
# item's verdict when it meets the item), the records (agent, stale, hog, top,
# total, act, herdr, ident, watched, job), then:
#   mcpcfg cli scope name source project  each configured MCP server, while
#     one runs (agents_mcp_tsv: who configured it, for the menu)
#   sys  cpu_pct load1 cores mem_free_pct mem_pressure battery_pct battery_state
#   awake mode pid until · thermal level name · power mode
#   hist state today_cpu_s top_job top_job_cpu_s  (_agents_hist_line)
#   insight view text  today's top insight, while current (_agents_insight_line)
#   tokens total cache_pct  today's tokens and cache hit %, from tokens.today
#   limit name window pct resets cli age  each CLI limit window not reset yet
#     (limits.tsv: _agents_limits_lines)
#   denials count top_reason · compacts count  today's, when there are any
#   lid on|off|stale guard_pid until max_secs  (keep-awake with the lid closed)
#   cool state mode soc control rpms low high pressure  (fan control, only
#     with the cooling pack: cool.sh)
#   conf KEY VALUE  for each AGENTS_BAR_* setting ("-" = empty)
# Built for the menu bar, every few seconds: Herdr is read from its cache
# (never waited on), the keep-awake state is read once, and the machine's
# state is read while the processes are collected (_agents_tsv_machine), and
# the MCP inventory's cache is read once, for the classify pass and the
# mcpcfg rows. Each refresh also feeds the run ledger (agents_collect with
# _AGENTS_FEED, runs.sh), so commands shorter than the minute between
# samples are recorded too.
agents_tsv() {
    local recs state pid="-" mode="off" until=0 sys thermal power lid cool key val cores mach _AGENTS_MCP_HAVE=1
    # One clock for the whole refresh: every _agents_now under it reads this.
    local _AGENTS_CLOCK=""
    _agents_now _AGENTS_CLOCK
    _agents_bg 6 _agents_tsv_machine
    _agents_awake_prime
    _agents_mcp_load
    if ! recs="$(AGENTS_HERDR_MODE=async _AGENTS_FEED=1 agents_collect)"; then
        _agents_bg_wait mach 6 || true
        return 1
    fi
    _agents_with_needs "$recs"
    [[ "$recs" != *$'\tmcp\t'* ]] || agents_mcp_tsv
    _agents_bg_wait mach 6 || true
    { IFS= read -r sys; IFS= read -r thermal; IFS= read -r power; IFS= read -r lid; IFS= read -r cool; } <<<"$mach"
    cores="${sys#*$'\t'}"; cores="${cores%%$'\t'*}"
    printf 'sys\t%s\t%s\n' "$(_agents_cpu_pct "$cores" "$recs")" "$sys"
    _agents_awake_now state && read -r pid mode until _ <<<"$state"
    printf 'awake\t%s\t%s\t%s\n' "$mode" "$pid" "$until"
    printf '%s\n%s\n' "$thermal" "$power"
    _agents_hist_line
    _agents_insight_line
    _agents_tokens_line
    # Usage (limits.sh): each CLI's limit windows, today's denials and
    # compactions, from the state files alone.
    _agents_limits_lines
    printf '%s\n' "$lid"
    [[ -z "$cool" ]] || printf '%s\n' "$cool"
    # Herdr: "hhealth server stale" and "hhealth outdated NAME…" while
    # Herdr's server or integrations need an update (an hourly check, never
    # waited on: _agents_herdr_health). Each session's Herdr pane and task
    # title came with the records ("herdr PID PANE TITLE", agents_enrich), and
    # so did each agent row's join key ("ident PID PANE SESSION").
    _agents_herdr_health
    for key in AGENTS_BAR_TITLE AGENTS_BAR_SECTIONS AGENTS_BAR_ICON AGENTS_BAR_TOP AGENTS_BAR_REFRESH AGENTS_LID AGENTS_CONF AGENTS_AUTO_REAP; do
        val="${!key}"
        printf 'conf\t%s\t%s\n' "$key" "${val:--}"
    done
}

# _agents_tsv_machine — the machine's part of agents_tsv, which nothing in the
# process table changes: agents_system's line (sys without its CPU%), then
# the thermal, power, lid and cool rows.
_agents_tsv_machine() {
    local lvl state lpid luntil lmax
    agents_system
    lvl="$(agents_thermal_level)"
    printf 'thermal\t%s\t%s\n' "${lvl:--}" "$(agents_thermal_name "${lvl:--}")"
    printf 'power\t%s\n' "$(agents_powermode)"
    lmax="$(_agents_lid_max)"
    if state="$(agents_lid_state)"; then
        read -r lpid luntil _ <<<"$state"; printf 'lid\ton\t%s\t%s\t%s\n' "$lpid" "$luntil" "$lmax"
    elif agents_lid_stale; then
        printf 'lid\tstale\t-\t0\t%s\n' "$lmax"
    else
        printf 'lid\toff\t-\t0\t%s\n' "$lmax"
    fi
    _agents_cool_row
}
