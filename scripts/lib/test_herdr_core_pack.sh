#!/bin/bash
# Tests for scripts/install/packs/herdr-core.sh: the LaunchAgent (macOS) and
# the systemd user timer (Linux) that start herdr-core at login and again
# every 5 minutes, and uninstall.sh removing the timer. A throwaway HOME;
# stand-in launchctl, systemctl, loginctl and uname that log their calls; and
# is_macos stubbed per case: nothing real is loaded, enabled or installed.
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

unset XDG_CONFIG_HOME
export HOME="$tmp/home" TUIDEV_NO_COLOR=1 NO_COLOR=1 DRY_RUN=false USER="${USER:-tester}"
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

# Linux: systemctl logs "args" (NO_SYSTEMD=1: no user manager, as in a
# container), loginctl answers Linger=$LINGER, uname says Linux.
SCTL_LOG="$tmp/systemctl.log"; export SCTL_LOG
mkdir -p "$tmp/linux"
cat > "$tmp/linux/systemctl" <<'EOF2'
#!/bin/sh
[ "${NO_SYSTEMD:-0}" = 1 ] && { echo "Failed to connect to bus: No medium found" >&2; exit 1; }
echo "$*" >> "$SCTL_LOG"
exit 0
EOF2
cat > "$tmp/linux/loginctl" <<'EOF2'
#!/bin/sh
echo "loginctl $*" >> "$SCTL_LOG"
[ "$1" = show-user ] && echo "Linger=${LINGER:-no}"
exit 0
EOF2
cat > "$tmp/linux/uname" <<'EOF2'
#!/bin/sh
case "$1" in -m) echo aarch64 ;; *) echo Linux ;; esac
EOF2
chmod +x "$tmp/linux"/*
LINUX_PATH="$tmp/linux:$SAFE_PATH"
UNITS="$HOME/.config/systemd/user"
SVC="$UNITS/tuidev-hc.service" TMR="$UNITS/tuidev-hc.timer"

# run_pack MAC(true|false): the pack in a subshell, its output in $out. Off
# macOS, PATH has the Linux stand-ins.
run_pack() {
    local mac="$1" path="$SAFE_PATH"
    [[ "$mac" == true ]] || path="$LINUX_PATH"
    out="$(
        PATH="$path"
        # shellcheck source=../install/packs/herdr-core.sh disable=SC1091
        . "$PACK"
        # shellcheck disable=SC2329  # called by the pack
        if [[ "$mac" == true ]]; then is_macos() { return 0; }; else is_macos() { return 1; }; fi
        herdr_core_install 2>&1
    )" || fail "pack exited non-zero: $out"
}
reset() { rm -rf "$HOME/Library" "$HOME/.config/systemd" "$TUIDEV_STATE_DIR" "$HOME/.local/bin"/*; : > "$LOG"; : > "$SCTL_LOG"; }
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
case "$flat" in *"<key>StartInterval</key><integer>300</integer>"*) ;; *) fail "no StartInterval of 300 s" ;; esac
case "$flat" in *"<key>AbandonProcessGroup</key><true/>"*) ;; *) fail "AbandonProcessGroup not true" ;; esac
case "$flat" in *"<key>ProcessType</key><string>Standard</string>"*) ;; *) fail "ProcessType not Standard" ;; esac
case "$flat" in *"<key>KeepAlive</key>"*) fail "KeepAlive present" ;; esac
grep -qxF "file $PLIST" "$TUIDEV_MANIFEST_FILE" || fail "plist not in the manifest"
grep -qx "bootstrap gui/$(id -u) $PLIST" "$LOG" || fail "no bootstrap: $(cat "$LOG")"
[[ ! -e "$HOME/.config/systemd" && ! -s "$SCTL_LOG" ]] || fail "macOS path installed or enabled a systemd unit"
pass "macOS install: plist filled (every 5 minutes, not KeepAlive), linted, recorded, bootstrapped"

# 3. Second run: idempotent; a loaded job is booted out first, so a changed
# plist (a new interval) applies without a migration.
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

# 6. Linux with systemd, lingering off: the timer and service installed as
# shipped, recorded, enabled; the linger command printed; no plist.
reset; fake_bins
LINGER=no run_pack false
[[ ! -e "$HOME/Library" ]] || fail "Linux path wrote a plist"
[[ ! -s "$LOG" ]] || fail "Linux path ran launchctl"
for u in tuidev-hc.service tuidev-hc.timer; do
    cmp -s "$UNITS/$u" "$REPO_DIR/configs/agents/$u" || fail "$u not installed as shipped"
    grep -qxF "file $UNITS/$u" "$TUIDEV_MANIFEST_FILE" || fail "$u not in the manifest"
done
r="$(grep -nx -- "--user daemon-reload" "$SCTL_LOG" | head -1 | cut -d: -f1)"
e="$(grep -nx -- "--user enable --now tuidev-hc.timer" "$SCTL_LOG" | head -1 | cut -d: -f1)"
{ [[ -n "$r" && -n "$e" ]] && [[ "$r" -lt "$e" ]]; } || fail "no daemon-reload, then enable --now: $(cat "$SCTL_LOG")"
if grep -q "tuidev-hc.service" "$SCTL_LOG"; then fail "the service itself was touched: $(cat "$SCTL_LOG")"; fi
grep -qF "sudo loginctl enable-linger $USER" <<< "$out" || fail "no linger command: $out"
grep -q "claude setup-token" <<< "$out" || fail "no setup-token line: $out"
grep -q "systemctl --user disable --now tuidev-hc.timer" <<< "$out" || fail "no off switch: $out"
grep -q "herdr-core pack complete" <<< "$out" || fail "Linux: did not complete"
pass "Linux: timer and service installed as shipped, recorded, enabled; linger off prints the sudo command"

# The units: a one-shot run of agents hc up -q every 5 minutes, the core in a
# scope of its own, nothing that restarts or stops it.
for want in "Type=oneshot" "ExecStart=/bin/bash %h/.local/bin/agents hc up -q" "Environment=AGENTS_HC_SCOPE=1" \
            "KillMode=process" "SuccessExitStatus=1"; do
    grep -qxF "$want" "$SVC" || fail "service lacks $want"
done
for want in "OnStartupSec=15s" "OnUnitActiveSec=5min" "WantedBy=timers.target"; do
    grep -qxF "$want" "$TMR" || fail "timer lacks $want"
done
if grep -Eq '^(Restart|ExecStop|RemainAfterExit)=' "$SVC"; then fail "the service restarts, stops or stays: $(grep -E '^(Restart|ExecStop|RemainAfterExit)=' "$SVC")"; fi
pass "the service runs agents hc up -q once, in no restart loop; the timer runs it every 5 minutes"

# 7. Lingering on: nothing about it. A second run changes nothing.
sum1="$(cat "$SVC" "$TMR" | cksum)"; : > "$SCTL_LOG"
LINGER=yes run_pack false
if grep -q "enable-linger" <<< "$out"; then fail "linger on, and the command was printed: $out"; fi
[[ "$(cat "$SVC" "$TMR" | cksum)" == "$sum1" ]] || fail "units changed on the second run"
[[ "$(grep -cxF "file $SVC" "$TUIDEV_MANIFEST_FILE")" == 1 ]] || fail "manifest record duplicated"
grep -qx -- "--user enable --now tuidev-hc.timer" "$SCTL_LOG" || fail "second run did not enable: $(cat "$SCTL_LOG")"
pass "Linux: lingering on prints nothing about it; a second run is idempotent"

# 8. The units go under XDG_CONFIG_HOME.
reset; fake_bins
XDG_CONFIG_HOME="$tmp/xdg" LINGER=yes run_pack false
[[ -f "$tmp/xdg/systemd/user/tuidev-hc.timer" && ! -e "$UNITS" ]] || fail "units not under XDG_CONFIG_HOME"
rm -rf "$tmp/xdg"
pass "Linux: the units follow XDG_CONFIG_HOME"

# 9. No systemd (a container): a warning and the commands, never a failure.
reset; fake_bins
NO_SYSTEMD=1 run_pack false
grep -q "no systemd user manager" <<< "$out" || fail "no warning without systemd: $out"
grep -q "systemctl --user enable --now tuidev-hc.timer" <<< "$out" || fail "no by-hand command: $out"
grep -q "agents hc up after each boot" <<< "$out" || fail "no agents hc up fallback: $out"
[[ ! -s "$SCTL_LOG" ]] || fail "systemd asked without a user manager: $(cat "$SCTL_LOG")"
grep -q "herdr-core pack complete" <<< "$out" || fail "no systemd: did not complete"
pass "Linux without systemd: warns, prints what to run, completes"

# 10. Linux dry run: nothing written, nothing enabled, the plan printed.
reset; fake_bins
DRY_RUN=true LINGER=no run_pack false
[[ ! -e "$HOME/.config/systemd" && ! -e "$TUIDEV_MANIFEST_FILE" ]] || fail "Linux dry run wrote files"
if grep -q "enable" "$SCTL_LOG"; then fail "Linux dry run enabled: $(cat "$SCTL_LOG")"; fi
grep -q "DRY RUN.*systemctl --user enable --now tuidev-hc.timer" <<< "$out" || fail "Linux dry run plan: $out"
pass "Linux dry run writes nothing, enables nothing, prints the plan"

# 11. uninstall.sh disables the timer and removes both units, and never
# stops the service: the core and its agents run on.
reset; fake_bins
LINGER=yes run_pack false; : > "$SCTL_LOG"
# No package manager to ask, and no sudo: uninstall.sh looks at this
# machine's /Library for the cooling pack's root daemon, and must not reach it.
for t in brew sudo; do printf '#!/bin/sh\nexit 1\n' > "$tmp/linux/$t"; chmod +x "$tmp/linux/$t"; done
u_out="$(cd "$tmp" && PATH="$LINUX_PATH" bash "$REPO_DIR/uninstall.sh" --all </dev/null 2>&1)" || fail "uninstall.sh: $(tail -20 <<< "$u_out")"
rm -f "$tmp/linux/brew" "$tmp/linux/sudo"
[[ ! -e "$SVC" && ! -e "$TMR" ]] || fail "uninstall left a unit: $(ls "$UNITS")"
grep -qx -- "--user disable --now tuidev-hc.timer" "$SCTL_LOG" || fail "timer not disabled: $(cat "$SCTL_LOG")"
grep -qx -- "--user daemon-reload" "$SCTL_LOG" || fail "no daemon-reload after the removal: $(cat "$SCTL_LOG")"
if grep -q "tuidev-hc.service" "$SCTL_LOG"; then fail "uninstall touched the service: $(cat "$SCTL_LOG")"; fi
pass "uninstall disables the timer, removes both units, leaves the core alone"

# 12. Sourcing runs and prints nothing; the file never exits.
# shellcheck source=../install/packs/herdr-core.sh disable=SC1091
src_out="$(PATH="$SAFE_PATH"; . "$PACK" 2>&1)" || fail "sourcing failed"
[[ -z "$src_out" ]] || fail "sourcing printed: $src_out"
if grep -Eq '(^|[^_[:alnum:]])exit[[:space:]]' "$PACK"; then fail "pack calls exit"; fi
pass "sourcing is silent; no exit"

# 13. install.sh dry run, under both bash and /bin/bash.
for sh in bash /bin/bash; do
    o="$(cd "$REPO_DIR" && "$sh" ./install.sh --pack herdr-core --dry-run < /dev/null 2>&1)" \
        || fail "install.sh under $sh failed: $o"
    grep -q "herdr-core pack complete" <<< "$o" || fail "install.sh under $sh: no completion line"
done
pass "install.sh --pack herdr-core --dry-run under bash and /bin/bash"
