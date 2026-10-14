# shellcheck shell=bash
# lib/agents/system.sh — the machine's state, for display only.
#
# Owns: thermal pressure, the energy mode and whether sleep is disabled
#   (cached for a minute), load, memory, battery and the machine's CPU%.
# Uses: config.sh (AGENTS_RUN_DIR), util.sh (_agents_now).
# Public: agents_thermal_level, agents_thermal_name, agents_powermode,
#   agents_sleep_disabled, agents_system, _agents_cpu_pct.

agents_thermal_level() {
    local lvl=""
    if command -v notifyutil >/dev/null 2>&1; then
        read -r _ lvl < <(LC_ALL=C notifyutil -g com.apple.system.thermalpressurelevel 2>/dev/null)
        [[ "$lvl" =~ ^[0-9]+$ ]] && echo "$lvl"
    fi
    return 0
}
agents_thermal_name() {
    case "$1" in
        0) echo nominal ;; 1) echo moderate ;; 2) echo heavy ;;
        3) echo trapping ;; 4) echo sleeping ;; *) echo unknown ;;
    esac
}
# Energy mode: 0 automatic, 1 low, 2 high (macOS); the power profile on Linux.
# It rarely changes, so the answer is kept in the run dir for a minute, with
# whether sleep is disabled outright (pmset disablesleep, from the same pmset
# -g; `awake lid` drops the cache when it changes that).
agents_powermode() { local m sd; _agents_pm_read; echo "$m"; }
# agents_sleep_disabled — 1 when macOS has sleep disabled (the lid too), 0
# when not, - when unknown (not macOS).
agents_sleep_disabled() { local m sd; _agents_pm_read; echo "$sd"; }
_agents_pm_read() {   # sets m and sd in the caller (dynamic scope)
    local cache="$AGENTS_RUN_DIR/powermode" ts="" now
    _agents_now now; m="" sd=""
    [[ -r "$cache" ]] && read -r ts m sd < "$cache"
    [[ "$ts" =~ ^[0-9]+$ ]] || ts=0
    [[ -n "$m" && -n "$sd" && $((now - ${ts:-0})) -lt 60 ]] && return 0
    read -r m sd <<<"$(_agents_powermode_probe)"
    { mkdir -p "$AGENTS_RUN_DIR" && printf '%s %s %s\n' "$now" "$m" "$sd" > "$cache"; } 2>/dev/null
    return 0
}
# _agents_powermode_probe — "MODE SLEEP_DISABLED". pmset -g lists
# SleepDisabled under its system-wide settings only while it is 1.
_agents_powermode_probe() {
    local p
    if command -v pmset >/dev/null 2>&1; then
        LC_ALL=C pmset -g 2>/dev/null | LC_ALL=C awk '
            $1 == "powermode" && m == "" { m = ($2 == 1 ? "low" : $2 == 2 ? "high" : "automatic") }
            $1 == "lowpowermode" { lp = ($2 == 1 ? "low" : "automatic") }
            $1 == "SleepDisabled" { sd = ($2 == 1 ? 1 : 0) }
            END { if (NR == 0) { print "unknown -"; exit } if (m == "") m = (lp == "" ? "unknown" : lp); print m, (sd == "" ? 0 : sd) }'
    elif command -v powerprofilesctl >/dev/null 2>&1; then
        p="$(powerprofilesctl get 2>/dev/null)"; echo "${p:-unknown} -"
    else
        echo "unknown -"
    fi
}

# agents_system — "load1 cores mem_free_pct mem_level battery_pct battery_state",
# tab-separated, "-" where unknown. Unprivileged and cheap: one sysctl (cores,
# memory pressure level, load), memory_pressure -Q and pmset -g batt on macOS,
# parsed in bash; /proc and /sys on Linux.
agents_system() {
    local cores="" load="" memfree="" level="" batt="" state="" b
    if command -v memory_pressure >/dev/null 2>&1; then
        _agents_parse_sysctl < <(LC_ALL=C sysctl -n hw.ncpu kern.memorystatus_vm_pressure_level vm.loadavg 2>/dev/null)
        memfree="$(_agents_parse_memfree < <(LC_ALL=C memory_pressure -Q 2>/dev/null))"
    elif [[ -r /proc/meminfo ]]; then
        memfree="$(awk '/^MemTotal:/ { t = $2 } /^MemAvailable:/ { a = $2 } END { if (t) printf "%d", 100 * a / t }' /proc/meminfo)"
        [[ -r /proc/loadavg ]] && read -r load _ < /proc/loadavg
    fi
    [[ -n "$cores" ]] || cores="$(LC_ALL=C getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)"
    [[ -n "$load" ]] || load="$(LC_ALL=C uptime 2>/dev/null | LC_ALL=C awk -F 'load averages?: *' 'NF > 1 { split($2, a, /[ ,]+/); print a[1] }')"
    case "$level" in 1) level=normal ;; 2) level=warn ;; 4) level=critical ;; *) level="" ;; esac
    if command -v pmset >/dev/null 2>&1; then
        IFS=$'\t' read -r batt state < <(_agents_parse_batt < <(LC_ALL=C pmset -g batt 2>/dev/null))
    else
        for b in /sys/class/power_supply/BAT*; do
            [[ -r "$b/capacity" ]] || continue
            read -r batt < "$b/capacity"; state="$(tr '[:upper:]' '[:lower:]' < "$b/status" 2>/dev/null)"
            break
        done
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "${load:--}" "${cores:-1}" "${memfree:--}" "${level:--}" "${batt:--}" "${state:--}"
}

# _agents_parse_sysctl < `sysctl -n hw.ncpu kern.memorystatus_vm_pressure_level
# vm.loadavg` — sets cores, level and load in the caller (dynamic scope).
_agents_parse_sysctl() {
    local line n=0
    while IFS= read -r line; do
        n=$((n + 1))
        case "$n" in
            1) [[ "$line" =~ ^[0-9]+$ ]] && cores="$line" ;;
            2) [[ "$line" =~ ^[0-9]+$ ]] && level="$line" ;;
            3) [[ "$line" =~ ^\{\ *([0-9.]+) ]] && load="${BASH_REMATCH[1]}" ;;
        esac
    done
}

# _agents_parse_memfree < `memory_pressure -Q` — the free percentage.
_agents_parse_memfree() {
    local line
    while IFS= read -r line; do
        [[ "$line" =~ free\ percentage:\ *([0-9]+)% ]] && { echo "${BASH_REMATCH[1]}"; return; }
    done
}

# _agents_parse_batt < `pmset -g batt` — "percent<TAB>state" (charging,
# discharging, charged, AC attached…); nothing on a Mac without a battery.
_agents_parse_batt() {
    local line
    while IFS= read -r line; do
        if [[ "$line" == *InternalBattery* && "$line" =~ ([0-9]+)%\;\ *([^;]+) ]]; then
            printf '%s\t%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
            return
        fi
    done
}

# _agents_cpu_pct CORES RECORDS — machine CPU% (0-100) from the total record.
_agents_cpu_pct() {
    local type cpu cores="${1:-1}"
    [[ "$cores" =~ ^[1-9][0-9]*$ ]] || cores=1
    while IFS=$'\t' read -r type _ _ _ cpu _; do
        [[ "$type" == total ]] || continue
        cpu="${cpu%%.*}"
        echo $(( (${cpu:-0} + cores / 2) / cores ))
        return
    done <<<"$2"
    echo -
}
