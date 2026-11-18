#!/bin/bash
# Tests for scripts/install/packs/herdr-core.sh: the LaunchAgent that starts
# herdr-core at login. A throwaway HOME, a stand-in launchctl that logs its
# calls, and is_macos stubbed per case: nothing real is loaded or installed.
# Run: bash scripts/lib/test_herdr_core_pack.sh  -> exit 0 on pass.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
PACK="$REPO_DIR/scripts/install/packs/herdr-core.sh"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/tuidev-test.XXXXXX")"
tmp="$(cd "$tmp" && pwd)"
trap 'rm -rf "$tmp"' EXIT

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "PASS: $1"; }

export HOME="$tmp/home" TUIDEV_NO_COLOR=1 NO_COLOR=1 DRY_RUN=false
export TUIDEV_STATE_DIR="$HOME/.config/tuidev" TUIDEV_MANIFEST_ENABLED=1
export TUIDEV_MANIFEST_FILE="$TUIDEV_STATE_DIR/manifest"
mkdir -p "$HOME/.local/bin" "$tmp/stub"
LOG="$tmp/launchctl.log"; export LOG
PLIST="$HOME/Library/LaunchAgents/dev.tuidev.hc.plist"

# launchctl: logs "args"; `print` answers success only when LOADED=1.
cat > "$tmp/stub/launchctl" <<'EOF2'
#!/bin/sh
echo "$*" >> "$LOG"
if [ "$1" = print ]; then [ "${LOADED:-0}" = 1 ]; exit $?; fi
exit 0
EOF2
chmod +x "$tmp/stub/launchctl"
SAFE_PATH="$tmp/stub:/usr/bin:/bin:/usr/sbin:/sbin"

# run_pack MAC(true|false): the pack in a subshell, its output in $out.
run_pack() {
    local mac="$1"
    out="$(
        PATH="$SAFE_PATH"
        # shellcheck source=../install/packs/herdr-core.sh disable=SC1091
        . "$PACK"
        # shellcheck disable=SC2329  # called by the pack
        if [[ "$mac" == true ]]; then is_macos() { return 0; }; else is_macos() { return 1; }; fi
        herdr_core_install 2>&1
    )" || fail "pack exited non-zero: $out"
}
reset() { rm -rf "$HOME/Library" "$TUIDEV_STATE_DIR" "$HOME/.local/bin"/*; : > "$LOG"; }
fake_bins() { printf '#!/bin/sh\necho "herdr-core 1.0"\n' > "$HOME/.local/bin/herdr-core"
    printf '#!/bin/sh\n' > "$HOME/.local/bin/agents"; chmod +x "$HOME/.local/bin"/*; }

# 1. Dry run: nothing written, no launchctl, still says what it would do.
reset; fake_bins
DRY_RUN=true run_pack true
[[ ! -e "$HOME/Library" ]] || fail "dry run wrote under HOME/Library"
[[ ! -e "$TUIDEV_MANIFEST_FILE" ]] || fail "dry run wrote the manifest"
[[ ! -s "$LOG" ]] || fail "dry run ran launchctl: $(cat "$LOG")"
grep -q "installing herdr-core at login" <<< "$out" || fail "dry run did not say what it would do: $out"
grep -q "herdr-core pack complete" <<< "$out" || fail "dry run: no completion line"
pass "dry run writes nothing, runs no launchctl, prints the plan"

# 2. Real run on macOS.
reset; fake_bins
run_pack true
[[ -f "$PLIST" ]] || fail "plist not installed"
if grep -q '@[A-Z]*@' "$PLIST"; then fail "unfilled placeholder: $(grep '@[A-Z]*@' "$PLIST")"; fi
if command -v plutil >/dev/null 2>&1; then
    plutil -lint "$PLIST" >/dev/null || fail "plutil -lint failed"
fi
flat="$(tr -d ' \t\n' < "$PLIST")"
want="<array><string>/bin/bash</string><string>$HOME/.local/bin/agents</string><string>hc</string><string>up</string><string>-q</string></array>"
case "$flat" in *"$want"*) ;; *) fail "program arguments wrong: $flat" ;; esac
case "$flat" in *"<key>RunAtLoad</key><true/>"*) ;; *) fail "RunAtLoad not true" ;; esac
case "$flat" in *"<key>AbandonProcessGroup</key><true/>"*) ;; *) fail "AbandonProcessGroup not true" ;; esac
case "$flat" in *"<key>ProcessType</key><string>Standard</string>"*) ;; *) fail "ProcessType not Standard" ;; esac
case "$flat" in *KeepAlive*) fail "KeepAlive present" ;; esac
grep -qxF "file $PLIST" "$TUIDEV_MANIFEST_FILE" || fail "plist not in the manifest"
grep -qx "bootstrap gui/$(id -u) $PLIST" "$LOG" || fail "no bootstrap: $(cat "$LOG")"
pass "macOS install: plist filled, linted, recorded, bootstrapped"

# 3. Second run: idempotent; a loaded job is booted out first.
sum1="$(cksum < "$PLIST")"; : > "$LOG"
LOADED=1 run_pack true
[[ "$(cksum < "$PLIST")" == "$sum1" ]] || fail "plist changed on the second run"
[[ "$(grep -cxF "file $PLIST" "$TUIDEV_MANIFEST_FILE")" == 1 ]] || fail "manifest record duplicated"
job="gui/$(id -u)/dev.tuidev.hc"
b="$(grep -nx "bootout $job" "$LOG" | head -1 | cut -d: -f1)"
s="$(grep -nx "bootstrap gui/$(id -u) $PLIST" "$LOG" | head -1 | cut -d: -f1)"
{ [[ -n "$b" && -n "$s" ]] && [[ "$b" -lt "$s" ]]; } || fail "no bootout before bootstrap: $(cat "$LOG")"
pass "second run is idempotent and boots out before bootstrapping"

# 4. No herdr-core.
reset; printf '#!/bin/sh\n' > "$HOME/.local/bin/agents"; chmod +x "$HOME/.local/bin/agents"
run_pack true
grep -qi "herdr-core is not installed" <<< "$out" || fail "no herdr-core warning: $out"
grep -q "https://herdr.dev/core/" <<< "$out" || fail "warning lacks the URL"
grep -q "herdr-core pack complete" <<< "$out" || fail "did not complete"
pass "missing herdr-core warns with the URL and completes"

# 5. No agents: warns, still installs the plist (the job fails once, no retry).
reset; printf '#!/bin/sh\necho herdr-core\n' > "$HOME/.local/bin/herdr-core"; chmod +x "$HOME/.local/bin/herdr-core"
run_pack true
grep -q "monitoring" <<< "$out" || fail "no monitoring hint: $out"
grep -q "herdr-core pack complete" <<< "$out" || fail "did not complete"
[[ -f "$PLIST" ]] || fail "plist not installed without agents"
pass "missing agents warns (monitoring brings it) and still installs the plist"

# 6. Off macOS.
reset; fake_bins
run_pack false
[[ ! -e "$HOME/Library" ]] || fail "Linux path wrote a plist"
[[ ! -s "$LOG" ]] || fail "Linux path ran launchctl"
grep -q "herdr-core pack complete" <<< "$out" || fail "Linux: did not complete"
pass "off macOS: no plist, no launchctl"

# 7. Sourcing runs and prints nothing; the file never exits.
# shellcheck source=../install/packs/herdr-core.sh disable=SC1091
src_out="$(PATH="$SAFE_PATH"; . "$PACK" 2>&1)" || fail "sourcing failed"
[[ -z "$src_out" ]] || fail "sourcing printed: $src_out"
if grep -Eq '(^|[^_[:alnum:]])exit[[:space:]]' "$PACK"; then fail "pack calls exit"; fi
pass "sourcing is silent; no exit"

# 8. install.sh dry run, under both bash and /bin/bash.
for sh in bash /bin/bash; do
    o="$(cd "$REPO_DIR" && "$sh" ./install.sh --pack herdr-core --dry-run < /dev/null 2>&1)" \
        || fail "install.sh under $sh failed: $o"
    grep -q "herdr-core pack complete" <<< "$o" || fail "install.sh under $sh: no completion line"
done
pass "install.sh --pack herdr-core --dry-run under bash and /bin/bash"
