# shellcheck shell=bash
# lib/agents/cool.sh — fan control (`agents cool`), the cooling pack's daemon.
#
# Owns: reading the dev.tuidev.fan daemon's status file, switching its mode,
#   the `agents cool` command, and the cool row the menu reads.
# Uses: config.sh, util.sh (_agents_now), notify.sh (_agents_notify).
# Public: agents_cool, agents_cool_state, _agents_cool_row.
#
# The daemon (lib/fan/tuidev-fan.swift, ./install.sh --pack cooling) runs as
# root and owns the fans. agents only reads its status file (rewritten every
# 2 s while the fans are its own or the SoC is warm, every 10 s otherwise) and
# writes its mode file (root:admin 0664), so nothing here asks for a
# password; the daemon clamps whatever the mode and curve files hold.

_AGENTS_FAN_PLIST="/Library/LaunchDaemons/dev.tuidev.fan.plist"
_AGENTS_FAN_DIR="/Library/Application Support/tuidev/fan"
# Only the test harness (AGENTS_TESTING) points these elsewhere, and it never
# sees the machine's own daemon: unset, they name nothing.
if [[ -n "${AGENTS_TESTING:-}" ]]; then
    _AGENTS_FAN_PLIST="${AGENTS_FAN_PLIST:-/nonexistent/dev.tuidev.fan.plist}"
    _AGENTS_FAN_DIR="${AGENTS_FAN_DIR:-/nonexistent/fan}"
fi

# agents_cool_state — one line, tab-separated:
#   STATE MODE SOC CONTROL RPMS LOW HIGH PRESSURE
# STATE: on (the daemon wrote its status in the last 30 s), stale (installed,
# but no fresh status: the daemon stopped), absent (not installed; the rest
# "-"). CONTROL: tuidev while it holds the fans, macos otherwise. RPMS: each
# fan's speed, comma-separated. SOC: the hottest CPU/GPU core, smoothed as
# the curve reads it, °C.
agents_cool_state() {
    local file="$_AGENTS_FAN_DIR/status" key a b c now updated=0
    local mode=- low=- high=- soc=- control=- pressure=- rpms=""
    if [[ ! -f "$_AGENTS_FAN_PLIST" ]]; then
        printf 'absent\t-\t-\t-\t-\t-\t-\t-\n'; return 0
    fi
    if [[ -r "$file" ]]; then
        while IFS=$'\t' read -r key a b c _; do
            case "$key" in
                updated)  [[ "$a" =~ ^[0-9]+$ ]] && updated="$a" ;;
                mode)     mode="$a" low="$b" high="$c" ;;
                soc)      soc="${a%.*}" ;;
                pressure) pressure="$a" ;;
                control)  control="$a" ;;
                fan)      rpms+="${rpms:+,}$b" ;;
            esac
        done < "$file"
    fi
    _agents_now now
    if [[ $updated -eq 0 || $((now - updated)) -gt 30 ]]; then
        printf 'stale\t%s\t-\t-\t-\t%s\t%s\t-\n' "$mode" "$low" "$high"; return 0
    fi
    printf 'on\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$mode" "${soc:--}" "$control" "${rpms:--}" "$low" "$high" "$pressure"
}

# _agents_cool_row — the tsv's cool row (agents_tsv): "cool" and the state;
# nothing without the cooling pack.
_agents_cool_row() {
    local s; s="$(agents_cool_state)"
    [[ "$s" == absent$'\t'* ]] || printf 'cool\t%s\n' "$s"
}

# agents_cool [status|cool|auto|quiet|max|off] [--notify]
agents_cool() {
    local what="status" a notify=false
    for a in "$@"; do
        case "$a" in
            --notify) notify=true ;;
            status|cool|auto|quiet|max|off) what="$a" ;;
            *) echo "usage: agents cool [status|cool|auto|quiet|max|off] [--notify]" >&2; return 2 ;;
        esac
    done
    if [[ ! -f "$_AGENTS_FAN_PLIST" ]]; then
        echo "agents: fan control isn't installed (Apple Silicon: ./install.sh --pack cooling)" >&2
        return 1
    fi
    if [[ "$what" == status ]]; then
        _agents_cool_print; return
    fi
    local file="$_AGENTS_FAN_DIR/mode" text
    if [[ ! -w "$file" ]]; then
        if id -Gn 2>/dev/null | tr ' ' '\n' | grep -qx admin; then
            echo "agents: can't write $file (it should be root:admin 0664; reinstall: ./install.sh --pack cooling)" >&2
        else
            echo "agents: only an admin user can switch the fans (the mode file is root:admin 0664)" >&2
        fi
        return 1
    fi
    printf '%s\n' "$what" > "$file" || return 1
    case "$what" in
        cool)  text="Fans: cool (palms first: they start at 55 °C)" ;;
        auto)  text="Fans: balanced (they follow the SoC's temperature)" ;;
        quiet) text="Fans: quiet (they start at 70 °C)" ;;
        max)  text="Fans: full speed until you switch back" ;;
        off)  text="Fans: macOS runs them" ;;
    esac
    echo "$text (the daemon applies it at once)"
    [[ "$notify" == true ]] && _agents_notify "$text"
    return 0
}

_agents_cool_print() {
    local state mode soc control rpms low high pressure i=0 r rpm line
    IFS=$'\t' read -r state mode soc control rpms low high pressure <<<"$(agents_cool_state)"
    if [[ "$state" == stale ]]; then
        echo "fans: the dev.tuidev.fan daemon isn't running (sudo launchctl bootstrap system $_AGENTS_FAN_PLIST; its log: /var/log/tuidev-fan.log)"
        return 1
    fi
    line="fans: "
    if [[ "$control" == tuidev ]]; then line+="tuidev holds them"; else line+="macOS runs them"; fi
    line+=" · mode $mode"
    case "$mode" in cool|auto|quiet) line+=" (${low}–${high} °C)" ;; esac
    echo "$line"
    echo "SoC: ${soc} °C (hottest CPU/GPU core) · thermal pressure: $(agents_thermal_name "$pressure")"
    IFS=, read -r -a r <<<"$rpms"
    for rpm in ${r[@]+"${r[@]}"}; do echo "fan $i: $rpm rpm"; i=$((i + 1)); done
    return 0
}
