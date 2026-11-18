#!/bin/bash
# The "a newer tuidev is out" notice (lib/agents/release.sh): what counts as
# newer, when the daily check starts, the tsv row, the one menu row it
# becomes in the SwiftBar plugin, and the one command `agents open-term` runs
# for it. Run: bash scripts/lib/test_agents_release.sh  -> exit 0 on pass.
#
# Everything lives in a throwaway HOME; a stub `tuidev` stands in for the
# network check.

# Tests change variables inside ( … ) on purpose.
# shellcheck disable=SC2030,SC2031,SC2034,SC2329
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
PLUGIN="$REPO_DIR/configs/swiftbar/agents.10s.sh"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/tuidev-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
for v in $(compgen -v AGENTS_) XDG_CONFIG_HOME XDG_STATE_HOME XDG_CACHE_HOME TUIDEV_STATE_DIR SWIFTBAR SWIFTBAR_PLUGIN_REFRESH_REASON; do unset "$v"; done
export HOME="$tmp/home" NO_COLOR=1 AGENTS_CONF="$tmp/none.conf" AGENTS_RUN_DIR="$tmp/run" AGENTS_DATA_DIR="$tmp/data" AGENTS_TESTING=1 AGENTS_NO_HERDR=1
export TUIDEV_STATE_DIR="$HOME/.config/tuidev"
mkdir -p "$HOME" "$AGENTS_RUN_DIR" "$AGENTS_DATA_DIR" "$TUIDEV_STATE_DIR" "$HOME/.cache/tuidev" "$tmp/bin"

# An empty process table (agents tsv reads it), and no other probes.
printf '#!/bin/sh\ncase "$*" in *axww*) printf "%%s\\n" "    1     0     0 root   0.0  20000 10:00.00 13-16:00:00 Wed Sep 30 16:57:15 2026     /sbin/launchd" ;; esac\n' > "$tmp/bin/ps"
for t in lsof osascript; do printf '#!/bin/sh\nexit 1\n' > "$tmp/bin/$t"; done
printf '#!/bin/sh\nexit 0\n' > "$tmp/bin/pmset"
chmod +x "$tmp/bin"/*
export PATH="$tmp/bin:$PATH"

# shellcheck source=../../bin/agents disable=SC1091
. "$REPO_DIR/bin/agents"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "PASS: $1"; }

VER="$TUIDEV_STATE_DIR/version" LATEST="$HOME/.cache/tuidev/latest"
NOW=1760400000
setup() {   # setup HAVE LATEST_LINE
    rm -f "$VER" "$LATEST"
    [[ -z "${1:-}" ]] || printf '%s\n' "$1" > "$VER"
    [[ -z "${2:-}" ]] || printf '%s\n' "$2" > "$LATEST"
}
newer() { setup "$1" "$2 $((NOW + 86400)) $NOW"; _agents_release; }

# 1. What counts as newer: numerically, per part.
newer 3.23.0 3.24.0 || fail "3.24.0 over 3.23.0 is newer"
[[ "$REPLY" == 3.24.0 && "$REPLY_HAVE" == 3.23.0 ]] || fail "REPLY $REPLY / $REPLY_HAVE"
newer 3.9.0 3.10.0 || fail "3.10.0 over 3.9.0 is newer (numeric, not text)"
newer 3.9.9 4.0.0 || fail "4.0.0 over 3.9.9"
newer 3.9.0 3.9.1 || fail "3.9.1 over 3.9.0"
newer 03.09.0 3.10.0 || fail "leading zeros are decimal"
! newer 3.23.0 3.23.0 || fail "equal is not newer"
! newer 3.10.0 3.9.0 || fail "3.9.0 under 3.10.0 is not newer"
! newer 4.0.0 3.99.99 || fail "older latest"
[[ -z "$REPLY" && -z "$REPLY_HAVE" ]] || fail "REPLY not cleared on false"
pass "a newer release is told numerically per part (3.10.0 over 3.9.0); equal and older are not"

# 2. Missing and garbage files.
setup "" "3.24.0 $((NOW + 86400)) $NOW"; ! _agents_release || fail "no version file"
setup 3.23.0 ""; ! _agents_release || fail "no latest file"
setup "" ""; ! _agents_release || fail "no files"
for bad in "-" "garbage" "3.24" "3.24.0-rc1" "v3.24.0" "3.24.0.1" ""; do
    setup 3.23.0 "$bad 0 0"; ! _agents_release || fail "latest '$bad' accepted"
    setup "$bad" "3.24.0 $((NOW + 86400)) $NOW"; ! _agents_release || fail "installed '$bad' accepted"
done
setup 3.23.0 "3.24.0 notanumber x"; _agents_release || fail "a bad NEXT should not hide a release"
setup 3.23.0 "3.24.0"; _agents_release || fail "a latest with no epochs"
pass "missing files and garbage in either file give no release"

# 3. The daily check: started when due and not under the harness, beside agents.
stub="$tmp/bin"
printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s/tuidev.calls"\n' "$tmp" > "$stub/tuidev"; chmod +x "$stub/tuidev"
waitcalls() { local i; for i in $(seq 1 50); do [[ -s "$tmp/tuidev.calls" ]] && return 0; sleep 0.1; done; return 1; }
check() {   # check NEXT: one run as a real (non-test) agents beside the stub
    rm -f "$tmp/tuidev.calls" "$AGENTS_RUN_DIR/release.kick"
    setup 3.23.0 "3.24.0 $1 $NOW"
    ( unset AGENTS_TESTING; AGENTS_PATH="$stub/agents"; _agents_release || true )
}
check 0; waitcalls || fail "a due check did not start tuidev"
[[ "$(cat "$tmp/tuidev.calls")" == "latest --if-due --notify" ]] || fail "tuidev argv: $(cat "$tmp/tuidev.calls")"
check "$(( $(date +%s) + 3600 ))"; sleep 0.5
[[ ! -e "$tmp/tuidev.calls" ]] || fail "a check that is not due started tuidev"
rm -f "$LATEST"; check 0; waitcalls || fail "no latest file yet is due"
rm -f "$tmp/tuidev.calls"; setup 3.23.0 "3.24.0 0 0"
( AGENTS_PATH="$stub/agents"; _agents_release || true ); sleep 0.5
[[ ! -e "$tmp/tuidev.calls" ]] || fail "the test harness started the check"
rm -f "$stub/tuidev"; ( unset AGENTS_TESTING; AGENTS_PATH="$stub/agents"; _agents_release || true )
pass "a due check runs 'tuidev latest --if-due --notify' beside agents; not when its time is ahead, not under AGENTS_TESTING, not without a tuidev"

# 3b. At most one start an hour (release.kick), though the cache says due every time.
printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s/tuidev.calls"\n' "$tmp" > "$stub/tuidev"; chmod +x "$stub/tuidev"
run_due() { setup 3.23.0 "3.24.0 0 $NOW"; ( unset AGENTS_TESTING; AGENTS_PATH="$stub/agents"; _agents_release || true ); }
rm -f "$tmp/tuidev.calls" "$AGENTS_RUN_DIR/release.kick"
run_due; waitcalls || fail "the first due run did not start the check"
[[ "$(cat "$AGENTS_RUN_DIR/release.kick")" =~ ^[0-9]+$ ]] || fail "release.kick is not an epoch: $(cat "$AGENTS_RUN_DIR/release.kick")"
run_due; run_due; sleep 0.5
[[ "$(wc -l < "$tmp/tuidev.calls" | tr -d ' ')" == 1 ]] || fail "a second run within the hour started the check again: $(cat "$tmp/tuidev.calls")"
# An hour later it starts again.
printf '%s\n' "$(( $(date +%s) - 3601 ))" > "$AGENTS_RUN_DIR/release.kick"
run_due; for _ in $(seq 1 50); do [[ "$(wc -l < "$tmp/tuidev.calls" | tr -d ' ')" == 2 ]] && break; sleep 0.1; done
[[ "$(wc -l < "$tmp/tuidev.calls" | tr -d ' ')" == 2 ]] || fail "a kick over an hour old did not allow a start: $(cat "$tmp/tuidev.calls")"
# A garbage kick file counts as none.
rm -f "$tmp/tuidev.calls"; echo garbage > "$AGENTS_RUN_DIR/release.kick"
run_due; waitcalls || fail "a garbage release.kick blocked the check"
# A run dir that cannot be written: no start, however due.
if [[ "$(id -u)" == 0 ]]; then
    echo "SKIP: running as root, a chmod 500 run dir stays writable"
else
    rm -f "$tmp/tuidev.calls" "$AGENTS_RUN_DIR/release.kick"; chmod 500 "$AGENTS_RUN_DIR"
    run_due; sleep 0.5
    chmod 700 "$AGENTS_RUN_DIR"
    [[ ! -e "$tmp/tuidev.calls" && ! -e "$AGENTS_RUN_DIR/release.kick" ]] || fail "an unwritable run dir still started the check"
fi
rm -f "$tmp/tuidev.calls" "$AGENTS_RUN_DIR/release.kick"
pass "the check starts at most once an hour (release.kick), not at all when the run dir cannot record it"

# 4. The tsv row, and the human line.
setup 3.23.0 "3.24.0 $((NOW + 86400)) $NOW"
[[ "$(_agents_release_row)" == $'release\t3.23.0\t3.24.0' ]] || fail "row: $(_agents_release_row)"
[[ "$(_agents_release_line)" == "tuidev 3.24.0 is out (you have 3.23.0): tuidev update" ]] || fail "line: $(_agents_release_line)"
[[ "$(agents_tsv 2>/dev/null)" == *$'\nrelease\t3.23.0\t3.24.0'* ]] || fail "agents tsv has no release row"
setup 3.24.0 "3.24.0 $((NOW + 86400)) $NOW"
[[ -z "$(_agents_release_row)" && -z "$(_agents_release_line)" ]] || fail "row or line with nothing newer"
[[ "$(agents_tsv 2>/dev/null)" != *$'\nrelease\t'* ]] || fail "agents tsv has a release row with nothing newer"
rm -f "$VER"; [[ "$(agents_tsv 2>/dev/null)" != *$'\nrelease\t'* ]] || fail "release row with no installed version"
pass "agents tsv emits the release row, and the human line, only while a newer release is known"

# 5. The plugin: one maintenance row and its two items.
M="$tmp/m"; mkdir -p "$M"
# shellcheck disable=SC2016  # the stub's own variable
printf '#!/bin/bash\n[[ "$1" != tsv ]] || cat "%s/tsv"\n' "$M" > "$M/agents"; chmod +x "$M/agents"
base_tsv() { printf 'sys\t5\t1.0\t8\t60\tnormal\t-\t-\nhist\tok\t0\t-\t0\nconf\tAGENTS_BAR_REFRESH\t1m\n' > "$M/tsv"; }
render() { env PATH="$tmp/bin:$PATH" AGENTS_BIN="$M/agents" bash "$PLUGIN" > "$M/out"; }
base_tsv; printf 'release\t3.23.0\t3.24.0\n' >> "$M/tsv"; render
out="$(cat "$M/out")"
[[ "$out" == *$'\nMaintenance (1) |'* ]] || fail "no Maintenance (1): $out"
[[ "$out" == *$'\n--tuidev 3.24.0 is out · you have 3.23.0 | '* ]] || fail "no release row: $out"
[[ "$out" == *$'\n----Update now… | bash="'*"param1=open-term terminal=false param2=--hold param3=tuidev param4=update param5=--ask "* ]] || fail "no Update now: $out"
[[ "$out" == *$'\n----What changed | href=https://github.com/spfr/tuidev/releases/tag/v3.24.0 '* ]] || fail "no What changed: $out"
top="${out%%$'\n---'*}"; [[ "$top" != *3.24.0* ]] || fail "the release is in the title: $top"
[[ "$out" != *"Needs you"*3.24.0* ]] || fail "the release is in Needs you"
for rows in $'release\t3.23.0' $'release\t3.23.0\t3.24' $'release\tv3.23.0\t3.24.0' $'release\t3.23.0\t3.24.0; rm -rf ~' $'release\t3.23.0\t3.24.0 | href=https://x' ''; do
    base_tsv; [[ -z "$rows" ]] || printf '%s\n' "$rows" >> "$M/tsv"; render
    ! grep -qE 'tuidev [^ ]+ is out|Maintenance|releases/tag' "$M/out" || fail "row '$rows' rendered: $(cat "$M/out")"
done
pass "the plugin renders one Maintenance row with Update now… and What changed; an absent or invalid row renders nothing"

# 6. A release is not activity: the idle mark is still written.
mkdir -p "$M/cache"; ln -sf "$PLUGIN" "$M/agents.1m.sh"
base_tsv; printf 'release\t3.23.0\t3.24.0\n' >> "$M/tsv"
env PATH="$tmp/bin:$PATH" AGENTS_BIN="$M/agents" SWIFTBAR=1 SWIFTBAR_PLUGIN_CACHE_PATH="$M/cache" SWIFTBAR_PLUGIN_PATH="$M/agents.1m.sh" \
    SWIFTBAR_PLUGIN_REFRESH_REASON=Schedule bash "$PLUGIN" > "$M/out"
[[ -s "$M/cache/last.idle" ]] || fail "a pending release defeated the idle fast path"
pass "a pending release does not defeat the idle fast path"

# 7. open-term runs tuidev for that one command only.
export AGENTS_TERMINAL=terminal
out="$(agents_open_term -n --hold tuidev update --ask 2>&1)" || fail "open-term tuidev update --ask: $out"
[[ "$out" == *bin/tuidev*update*--ask* && "$out" != *bin/agents* ]] || fail "open-term argv: $out"
for bad in "tuidev update" "tuidev update --ask --yes" "tuidev latest" "tuidev rm -rf x" "tuidev"; do
    # shellcheck disable=SC2086
    ! agents_open_term -n $bad >/dev/null 2>&1 || fail "open-term accepted: $bad"
done
pass "agents open-term runs the tuidev beside agents for exactly 'tuidev update --ask' and refuses any other tuidev command"

# 8. A Herdr sync starts the due check too.
printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s/tuidev.calls"\n' "$tmp" > "$stub/tuidev"; chmod +x "$stub/tuidev"
rm -f "$tmp/tuidev.calls" "$AGENTS_RUN_DIR/release.kick"; setup 3.23.0 "3.24.0 0 0"
( unset AGENTS_TESTING; AGENTS_PATH="$stub/agents" AGENTS_HERDR_NAMES=0; agents_herdr_sync -q || true )
waitcalls || fail "agents herdr sync did not start the due check"
pass "agents herdr sync starts the due release check"

echo "All agents release tests passed."
