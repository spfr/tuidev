#!/bin/bash
# Unit tests for fan control: lib/agents/cool.sh (the daemon's status file,
# `agents cool`, the tsv's cool row), the menu's Fans line and `temp` title
# token, and tuidev-fan's curve (lib/fan/tuidev-fan.swift, built here when
# swiftc is around; its `curve` command needs no fans and no root).
# Run: bash scripts/lib/test_agents_cool.sh  -> exit 0 on pass.
#
# Everything runs in temp dirs with a fixed clock (AGENTS_NOW), a stand-in
# daemon plist and status file (AGENTS_FAN_PLIST, AGENTS_FAN_DIR): no SMC is
# touched and nothing runs as root.

# Tests change variables inside ( … ) on purpose; the stub's $1 is its own.
# shellcheck disable=SC2030,SC2031,SC2034
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/tuidev-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
for v in XDG_CONFIG_HOME XDG_STATE_HOME TUIDEV_STATE_DIR AGENTS_HISTORY; do unset "$v"; done
export HOME="$tmp/home" NO_COLOR=1 TZ=UTC AGENTS_CONF="$tmp/none.conf" AGENTS_DATA_DIR="$tmp/data" AGENTS_RUN_DIR="$tmp/run"
export AGENTS_TESTING=1 AGENTS_NO_HERDR=1
export AGENTS_FAN_PLIST="$tmp/dev.tuidev.fan.plist" AGENTS_FAN_DIR="$tmp/fan"
NOW=1792170000   # Fri 2026-10-16 17:00:00 UTC
export AGENTS_NOW="$NOW"
mkdir -p "$HOME" "$AGENTS_FAN_DIR"

# shellcheck source=../../bin/agents disable=SC1091
. "$REPO_DIR/bin/agents"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "PASS: $1"; }
T=$'\t'

# status UPDATED CONTROL — the daemon's status file, as tuidev-fan writes it.
status() {
    printf '%s\n' "updated${T}$1${T}2" "mode${T}auto${T}60${T}95" "soc${T}78.6${T}83.0" "pressure${T}0" \
        "control${T}$2${T}0" "fan${T}0${T}3502${T}3500${T}1350${T}5777${T}manual" \
        "fan${T}1${T}3484${T}3500${T}1350${T}5777${T}manual" > "$AGENTS_FAN_DIR/status"
}

# --- 1. Not installed ------------------------------------------------------------------
[[ "$(agents_cool_state)" == "absent${T}-${T}-${T}-${T}-${T}-${T}-${T}-" ]] || fail "absent state: $(agents_cool_state)"
out="$(agents_cool 2>&1)" && fail "agents cool succeeded without the daemon"
[[ "$out" == *"--pack cooling"* ]] || fail "absent: no install hint: $out"
[[ -z "$(_agents_cool_row)" ]] || fail "a cool row without the pack: $(_agents_cool_row)"
pass "not installed: absent, no tsv row, and agents cool says how to install it"

# --- 2. Running, and stopped ---------------------------------------------------------------
touch "$AGENTS_FAN_PLIST"
status $((NOW - 3)) tuidev
[[ "$(agents_cool_state)" == "on${T}auto${T}78${T}tuidev${T}3502,3484${T}60${T}95${T}0" ]] || fail "on state: $(agents_cool_state)"
out="$(agents_cool status)" || fail "status failed: $out"
[[ "$out" == *"tuidev holds them · mode auto (60–95 °C)"* && "$out" == *"SoC: 78 °C"* && "$out" == *"fan 1: 3484 rpm"* ]] || fail "status text: $out"
status $((NOW - 45)) tuidev
[[ "$(agents_cool_state)" == "stale${T}auto${T}"* ]] || fail "stale state: $(agents_cool_state)"
out="$(agents_cool 2>&1)" && fail "a stopped daemon reported as fine"
[[ "$out" == *"isn't running"* && "$out" == *"launchctl bootstrap"* ]] || fail "stale text: $out"
rm -f "$AGENTS_FAN_DIR/status"
[[ "$(agents_cool_state)" == "stale${T}"* ]] || fail "installed with no status file is not stale"
pass "running: mode, SoC, fans; a status older than 30 s (or none) is stale"

# --- 3. Switching the mode -------------------------------------------------------------------
printf 'auto\n' > "$AGENTS_FAN_DIR/mode"
agents_cool max >/dev/null || fail "max failed"
[[ "$(cat "$AGENTS_FAN_DIR/mode")" == max ]] || fail "max not written"
agents_cool quiet >/dev/null || fail "quiet failed"
[[ "$(cat "$AGENTS_FAN_DIR/mode")" == quiet ]] || fail "quiet not written"
agents_cool off >/dev/null || fail "off failed"
[[ "$(cat "$AGENTS_FAN_DIR/mode")" == off ]] || fail "off not written"
rc=0; agents_cool loud >/dev/null 2>&1 || rc=$?
[[ $rc -eq 2 ]] || fail "a bad mode was not a usage error ($rc)"
[[ "$(cat "$AGENTS_FAN_DIR/mode")" == off ]] || fail "a bad mode changed the file"
chmod 0444 "$AGENTS_FAN_DIR/mode"
if [[ ! -w "$AGENTS_FAN_DIR/mode" ]]; then   # root writes anyway
    out="$(agents_cool auto 2>&1)" && fail "an unwritable mode file succeeded"
    [[ "$out" == *"root:admin 0664"* ]] || fail "unwritable: $out"
fi
chmod 0644 "$AGENTS_FAN_DIR/mode"
pass "cool|auto|quiet|max|off write the mode file; a bad mode or an unwritable file changes nothing"

# --- 4. The menu ---------------------------------------------------------------------------
cat > "$tmp/agents-stub" <<EOF
#!/bin/bash
case "\$1" in tsv) cat "$tmp/tsv" ;; esac
EOF
chmod +x "$tmp/agents-stub"
menu() { AGENTS_BIN="$tmp/agents-stub" bash "$REPO_DIR/configs/swiftbar/agents.10s.sh"; }
sys="sys${T}12${T}2.1${T}14${T}40${T}normal${T}80${T}charging"
printf '%s\n' "$sys" "thermal${T}0${T}nominal" "cool${T}on${T}auto${T}78${T}tuidev${T}3502,3610${T}60${T}95${T}0" \
    "conf${T}AGENTS_BAR_TITLE${T}count temp" > "$tmp/tsv"
m="$(menu)"
[[ "$m" == *"Fans 3610 rpm · SoC 78 °C · balanced | sfimage=fan"* ]] || fail "menu Fans line: $(printf '%s\n' "$m" | grep -i fan)"
[[ "$m" == *"--Balanced (from 60 °C) checked=true | "*"param1=cool param2=auto"* ]] || fail "Balanced not checked: $m"
[[ "$m" == *"--Now: minimum at 60 °C, full speed at 95 °C"* ]] || fail "range line"
[[ "$m" == *"--Cool: palms first (from 55 °C) | "*"param2=cool param3=--notify"* && "$m" == *"--Quiet (from 70 °C) | "*"param2=quiet"* ]] || fail "Cool/Quiet items: $m"
[[ "$m" == *"--Max: full speed | "*"param1=cool param2=max param3=--notify"* ]] || fail "Max item: $m"
[[ "$(printf '%s\n' "$m" | head -1)" == *":thermometer.medium: 78°"* ]] || fail "temp title token: $(printf '%s\n' "$m" | head -1)"
printf '%s\n' "$sys" "cool${T}on${T}auto${T}55${T}macos${T}1350,1458${T}60${T}95${T}0" > "$tmp/tsv"
[[ "$(menu)" == *"Fans 1458 rpm · SoC 55 °C · balanced (macOS below 60 °C)"* ]] || fail "auto below the curve"
printf '%s\n' "$sys" "cool${T}stale${T}auto${T}-${T}-${T}-${T}60${T}95${T}-" > "$tmp/tsv"
m="$(menu)"
[[ "$m" == *"Fan control stopped"* && "$m" != *"--Balanced"* ]] || fail "stale menu: $m"
printf '%s\n' "$sys" "cool${T}absent${T}-${T}-${T}-${T}-${T}-${T}-${T}-" > "$tmp/tsv"
[[ "$(menu)" != *Fan* ]] || fail "a Fans line without the cooling pack"
pass "menu: Fans line with Cool/Balanced/Quiet/Max/Off under System, stopped when stale, none without the pack; temp token"

# --- 5. The curve (tuidev-fan curve) --------------------------------------------------------
if [[ "$(uname)" == Darwin ]] && command -v swiftc >/dev/null 2>&1 \
    && swiftc -O -swift-version 5 "$REPO_DIR/lib/fan/tuidev-fan.swift" -o "$tmp/tuidev-fan" 2>"$tmp/swiftc.err"; then
    c() { "$tmp/tuidev-fan" curve "$@"; }
    [[ "$(c 59 0)" == macos && "$(c 60 0)" == 1350 && "$(c 80 0)" == 3880 && "$(c 95 0)" == 5777 && "$(c 104 0)" == 5777 ]] \
        || fail "curve: 59→$(c 59 0) 60→$(c 60 0) 80→$(c 80 0) 95→$(c 95 0)"
    # Presets: cool 55–85 °C, quiet 70–100 °C, whatever fan.conf says.
    [[ "$(c 54 0 cool)" == macos && "$(c 75 0 cool)" == 4301 && "$(c 85 0 cool)" == 5777 ]] || fail "cool preset: $(c 75 0 cool)"
    [[ "$(c 69 0 quiet)" == macos && "$(c 75 0 quiet)" == 2088 && "$(c 100 0 quiet)" == 5777 ]] || fail "quiet preset: $(c 75 0 quiet)"
    [[ "$(c 50 2)" == 5777 ]] || fail "heavy thermal pressure is not full speed: $(c 50 2)"
    [[ "$(c 50 0 max)" == 5777 && "$(c 99 0 off)" == macos ]] || fail "max/off modes"
    # Engaged (a previous target): hysteresis keeps it to 55 °C, and the
    # target falls at most 150 rpm a tick; it never falls below the minimum.
    [[ "$(c 57 0 auto 60 95 1350 5777 2000)" == 1850 && "$(c 54 0 auto 60 95 1350 5777 2000)" == macos ]] || fail "hysteresis"
    [[ "$(c 61 0 auto 60 95 1350 5777 1400)" == 1476 && "$(c 58 0 auto 60 95 1350 5777 1400)" == 1350 ]] \
        || fail "rise/floor: $(c 61 0 auto 60 95 1350 5777 1400) $(c 58 0 auto 60 95 1350 5777 1400)"
    rc=0; c nan 0 >/dev/null 2>&1 || rc=$?
    [[ $rc -eq 2 && "$(c 70 0 auto 60 60 1350 5777)" == 5777 ]] || fail "nan ($rc) or low = high did not hold"
    pass "curve: balanced 60–95 °C, cool 55–85, quiet 70–100; macOS below, full at heavy pressure, hysteresis and a gentle fall"
else
    echo "SKIP: tuidev-fan curve (needs macOS and swiftc)"
fi

echo "all cool tests passed"
