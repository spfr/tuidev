# shellcheck shell=bash
# lib/agents/json.sh — `agents json`.
#
# Uses: config.sh, awake.sh (_agents_awake_now), system.sh, lid.sh
#   (agents_lid_state); awk/json.awk.
# Public: agents_json.

# agents_json < RECORDS — {schema_version, agents (each with its activity),
# stale, hogs, top, system, awake, thermal, powermode}. The schema is a
# contract (docs/agent-workflows.md): add fields freely, bump schema_version
# for anything that removes or changes one.
agents_json() {
    local state="" pid="" mode="" until="" lvl sys
    state="$(_agents_awake_now)" && read -r pid mode until _ <<<"$state"
    lvl="$(agents_thermal_level)"
    sys="$(agents_system)"
    AW_PID="$pid" AW_MODE="$mode" AW_UNTIL="$until" TH="${lvl:-}" TH_NAME="$(agents_thermal_name "${lvl:--}")" \
    PM="$(agents_powermode)" SYS="$sys" NOW="$(date +%s)" LID="$(_agents_lid_json)" _agents_awk json -F '\t'
}

# _agents_lid_json — the "lid" object of agents json: numbers and booleans only.
_agents_lid_json() {
    local st pid=0 until=0 sd active=false stale=false
    if st="$(agents_lid_state)"; then active=true; read -r pid until _ <<<"$st"; fi
    sd="$(agents_sleep_disabled)"
    case "$sd" in 1) sd=true ;; 0) sd=false ;; *) sd=null ;; esac
    [[ "$active" == false && "$sd" == true ]] && stale=true
    if [[ "$active" == true ]]; then
        printf '{"active":true,"pid":%d,"until":%d,"sleep_disabled":%s,"stale":false}' "$pid" "$until" "$sd"
    else
        printf '{"active":false,"sleep_disabled":%s,"stale":%s}' "$sd" "$stale"
    fi
}
