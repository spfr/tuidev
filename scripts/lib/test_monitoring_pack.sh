#!/bin/bash
# Tests for the jobs scripts/install/packs/monitoring.sh installs beside
# agents: the sampler (`agents sample --scheduled` once a minute) and the
# memory guard, as LaunchAgents on macOS (with the link watcher) and as
# systemd user units on Linux; `tuidev check`'s probe for them; and
# uninstall.sh stopping and removing them. A throwaway HOME; stand-in
# launchctl, systemctl, loginctl and uname that log their calls; is_macos
# stubbed per case. Only the jobs' own functions run: nothing real is loaded,
# enabled or installed, and no package manager or `defaults` is asked.
# Run: bash scripts/lib/test_monitoring_pack.sh  -> exit 0 on pass.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
PACK="$REPO_DIR/scripts/install/packs/monitoring.sh"

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
AGENTS_DIR="$HOME/Library/LaunchAgents"
SAMPLE_PLIST="$AGENTS_DIR/dev.tuidev.sample.plist"

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

# run MAC(true|false) FUNCTION — one of the pack's functions in a subshell,
# its output in $out. Off macOS, PATH has the Linux stand-ins.
run() {
    local mac="$1" fn="$2" path="$SAFE_PATH"
    [[ "$mac" == true ]] || path="$LINUX_PATH"
    out="$(
        PATH="$path"
        # shellcheck source=../install/packs/monitoring.sh disable=SC1091
        . "$PACK"
        # shellcheck disable=SC2329  # called by the pack
        if [[ "$mac" == true ]]; then is_macos() { return 0; }; else is_macos() { return 1; }; fi
        "$fn" 2>&1
    )" || fail "$fn exited non-zero: $out"
}
mac_jobs() { _monitoring_sampler; _monitoring_memguard; _monitoring_link; }
reset() { rm -rf "$HOME/Library" "$HOME/.config/systemd" "$TUIDEV_STATE_DIR"; : > "$LOG"; : > "$SCTL_LOG"; }
# flat FILE — the plist without whitespace, for matching its keys.
flat() { tr -d ' \t\n' < "$1"; }

# 1. macOS dry run: nothing written, no launchctl, the plan printed.
reset
DRY_RUN=true run true mac_jobs
[[ ! -e "$HOME/Library" && ! -e "$TUIDEV_MANIFEST_FILE" ]] || fail "dry run wrote files"
[[ ! -s "$LOG" ]] || fail "dry run ran launchctl: $(cat "$LOG")"
grep -q "installing the sampler (LaunchAgent)" <<< "$out" || fail "dry run: no plan for the sampler: $out"
pass "macOS dry run writes nothing, runs no launchctl, prints the plan"

# 2. macOS: the sampler, the memory guard and the link watcher, each filled
# in, linted, recorded and bootstrapped.
reset
run true mac_jobs
for label in dev.tuidev.sample dev.tuidev.memguard dev.tuidev.link; do
    p="$AGENTS_DIR/$label.plist"
    [[ -f "$p" ]] || fail "$label not installed"
    if grep -q '@[A-Z]*@' "$p"; then fail "$label: unfilled placeholder: $(grep '@[A-Z]*@' "$p")"; fi
    if command -v plutil >/dev/null 2>&1; then plutil -lint "$p" >/dev/null || fail "$label: plutil -lint failed"; fi
    grep -qxF "file $p" "$TUIDEV_MANIFEST_FILE" || fail "$label not in the manifest"
    grep -qx "bootstrap gui/$(id -u) $p" "$LOG" || fail "$label not bootstrapped: $(cat "$LOG")"
done
f="$(flat "$SAMPLE_PLIST")"
case "$f" in *"<array><string>/bin/bash</string><string>$HOME/.local/bin/agents</string><string>sample</string><string>--scheduled</string></array>"*) ;; *) fail "sampler program arguments: $f" ;; esac
case "$f" in *"<key>StartInterval</key><integer>60</integer>"*) ;; *) fail "the sampler does not run every 60 s" ;; esac
case "$f" in *"<key>RunAtLoad</key><true/>"*) ;; *) fail "the sampler does not run at load" ;; esac
case "$f" in *"<key>KeepAlive</key>"*) fail "the sampler is KeepAlive: a one-shot job would be restarted at once" ;; esac
case "$f" in *"<key>StandardErrorPath</key><string>$HOME/Library/Logs/tuidev-sample.log</string>"*) ;; *) fail "the sampler's log path: $f" ;; esac
grep -q "AGENTS_SAMPLER=0" <<< "$out" || fail "no off switch printed: $out"
[[ ! -e "$HOME/.config/systemd" && ! -s "$SCTL_LOG" ]] || fail "macOS path installed or enabled a systemd unit"
pass "macOS: the sampler (sample --scheduled every 60 s, not KeepAlive), the guard and the link watcher filled in, linted, recorded, bootstrapped"

# 3. A second run: idempotent; a loaded job is booted out before it is
# bootstrapped again, so a changed plist and a new agents take over.
sum1="$(cksum < "$SAMPLE_PLIST")"; : > "$LOG"
LOADED=1 run true _monitoring_sampler
[[ "$(cksum < "$SAMPLE_PLIST")" == "$sum1" ]] || fail "the plist changed on the second run"
[[ "$(grep -cxF "file $SAMPLE_PLIST" "$TUIDEV_MANIFEST_FILE")" == 1 ]] || fail "manifest record duplicated"
b="$(grep -nx "bootout gui/$(id -u)/dev.tuidev.sample" "$LOG" | head -1 | cut -d: -f1)"
s="$(grep -nx "bootstrap gui/$(id -u) $SAMPLE_PLIST" "$LOG" | head -1 | cut -d: -f1)"
{ [[ -n "$b" && -n "$s" ]] && [[ "$b" -lt "$s" ]]; } || fail "no bootout before bootstrap: $(cat "$LOG")"
pass "macOS: a second run is idempotent and boots the sampler out before bootstrapping it"

# 4. Linux with systemd, lingering off: the units as shipped, recorded; a
# reload, then the timer enabled and the guard enabled and restarted.
reset
LINGER=no run false _monitoring_linux_units
[[ ! -e "$HOME/Library" && ! -s "$LOG" ]] || fail "the Linux path wrote a plist or ran launchctl"
for u in tuidev-sample.service tuidev-sample.timer tuidev-memguard.service; do
    cmp -s "$UNITS/$u" "$REPO_DIR/configs/agents/$u" || fail "$u not installed as shipped"
    grep -qxF "file $UNITS/$u" "$TUIDEV_MANIFEST_FILE" || fail "$u not in the manifest"
done
r="$(grep -nx -- "--user daemon-reload" "$SCTL_LOG" | head -1 | cut -d: -f1)"
e="$(grep -nx -- "--user enable --now tuidev-sample.timer" "$SCTL_LOG" | head -1 | cut -d: -f1)"
g="$(grep -nx -- "--user enable tuidev-memguard.service" "$SCTL_LOG" | head -1 | cut -d: -f1)"
k="$(grep -nx -- "--user restart tuidev-memguard.service" "$SCTL_LOG" | head -1 | cut -d: -f1)"
{ [[ -n "$r" && -n "$e" && -n "$g" && -n "$k" ]] && [[ "$r" -lt "$e" && "$r" -lt "$g" && "$g" -lt "$k" ]]; } \
    || fail "not reload, enable --now the timer, enable then restart the guard: $(cat "$SCTL_LOG")"
if grep -q -- "tuidev-sample.service" "$SCTL_LOG"; then fail "the sampler's one-shot service was touched: $(cat "$SCTL_LOG")"; fi
grep -qF "sudo loginctl enable-linger $USER" <<< "$out" || fail "no linger command: $out"
grep -q "AGENTS_SAMPLER=0" <<< "$out" || fail "no off switch printed: $out"
pass "Linux: sampler timer and service, guard service installed as shipped, recorded; reload, enable --now the timer, enable and restart the guard; linger off says how"

# The units: a one-shot `agents sample --scheduled` every minute; the guard
# restarted when it fails, never after it exits 0 (AGENTS_MEM_GUARD=off).
SVC="$UNITS/tuidev-sample.service" TMR="$UNITS/tuidev-sample.timer" MG="$UNITS/tuidev-memguard.service"
for want in "Type=oneshot" "ExecStart=/bin/bash %h/.local/bin/agents sample --scheduled"; do
    grep -qxF "$want" "$SVC" || fail "the sampler's service lacks $want"
done
if grep -Eq '^(Restart|RemainAfterExit)=' "$SVC"; then fail "the sampler's service restarts or stays: $(grep -E '^(Restart|RemainAfterExit)=' "$SVC")"; fi
for want in "OnStartupSec=1min" "OnUnitActiveSec=1min" "WantedBy=timers.target"; do
    grep -qxF "$want" "$TMR" || fail "the sampler's timer lacks $want"
done
for want in "ExecStart=/bin/bash %h/.local/bin/agents mem guard" "Restart=on-failure" "WantedBy=default.target"; do
    grep -qxF "$want" "$MG" || fail "the guard's service lacks $want"
done
if grep -Eq '^Type=oneshot' "$MG"; then fail "the guard's service is a one-shot"; fi
pass "the units: sample --scheduled once a minute in a one-shot; the guard a long-running service, restarted on failure"

# 5. Lingering on: nothing about it; a second run changes nothing.
sum1="$(cat "$SVC" "$TMR" "$MG" | cksum)"; : > "$SCTL_LOG"
LINGER=yes run false _monitoring_linux_units
if grep -q "enable-linger" <<< "$out"; then fail "linger on, and the command was printed: $out"; fi
[[ "$(cat "$SVC" "$TMR" "$MG" | cksum)" == "$sum1" ]] || fail "units changed on the second run"
[[ "$(grep -cxF "file $SVC" "$TUIDEV_MANIFEST_FILE")" == 1 ]] || fail "manifest record duplicated"
pass "Linux: lingering on prints nothing about it; a second run is idempotent"

# 6. The units follow XDG_CONFIG_HOME.
reset
XDG_CONFIG_HOME="$tmp/xdg" LINGER=yes run false _monitoring_linux_units
[[ -f "$tmp/xdg/systemd/user/tuidev-sample.timer" && -f "$tmp/xdg/systemd/user/tuidev-memguard.service" && ! -e "$UNITS" ]] \
    || fail "units not under XDG_CONFIG_HOME"
rm -rf "$tmp/xdg"
pass "Linux: the units follow XDG_CONFIG_HOME"

# 7. No systemd (a container): the files for later, a warning and what to
# run by hand; never a failure, nothing asked of systemd.
reset
NO_SYSTEMD=1 run false _monitoring_linux_units
grep -q "no systemd user manager" <<< "$out" || fail "no warning without systemd: $out"
grep -q "systemctl --user enable --now tuidev-sample.timer tuidev-memguard.service" <<< "$out" || fail "no by-hand command: $out"
grep -q "agents watch" <<< "$out" || fail "no tmux fallback: $out"
[[ ! -s "$SCTL_LOG" ]] || fail "systemd asked without a user manager: $(cat "$SCTL_LOG")"
[[ -f "$UNITS/tuidev-sample.timer" ]] || fail "the unit files were not placed for a later systemd"
pass "Linux without systemd: warns, prints what to run, places the files, completes"

# 8. Linux dry run: nothing written, nothing enabled, the plan printed.
reset
DRY_RUN=true LINGER=no run false _monitoring_linux_units
[[ ! -e "$HOME/.config/systemd" && ! -e "$TUIDEV_MANIFEST_FILE" ]] || fail "Linux dry run wrote files"
if grep -Eq "enable|restart" "$SCTL_LOG"; then fail "Linux dry run enabled: $(cat "$SCTL_LOG")"; fi
grep -q "DRY RUN.*systemctl --user enable --now tuidev-sample.timer" <<< "$out" || fail "Linux dry run plan: $out"
pass "Linux dry run writes nothing, enables nothing, prints the plan"

# 9. tuidev check's probe: agents, a process monitor and the sampler's job.
reset
mkdir -p "$tmp/probe"
for c in agents btm; do printf '#!/bin/sh\n' > "$tmp/probe/$c"; chmod +x "$tmp/probe/$c"; done
probe() {
    ( PATH="$tmp/probe:$1"
      # shellcheck source=../install/packs/monitoring.sh disable=SC1091
      . "$PACK" >/dev/null 2>&1
      # shellcheck disable=SC2329  # called by monitoring_check
      if [[ "$2" == true ]]; then is_macos() { return 0; }; else is_macos() { return 1; }; fi
      set +e; monitoring_check )
}
! probe "$LINUX_PATH" false || fail "Linux probe passed without the sampler's timer"
mkdir -p "$UNITS"; : > "$UNITS/tuidev-sample.timer"
probe "$LINUX_PATH" false || fail "Linux probe failed with agents, btm and the timer"
! probe "$SAFE_PATH" true || fail "macOS probe passed without the sampler's LaunchAgent"
mkdir -p "$AGENTS_DIR"; : > "$SAMPLE_PLIST"
probe "$SAFE_PATH" true || fail "macOS probe failed with agents, btm and the LaunchAgent"
rm -f "$tmp/probe/agents"; ! probe "$SAFE_PATH" true || fail "probe passed without agents"
pass "tuidev check: monitoring fails without the sampler's unit file (the LaunchAgent, or the systemd timer)"

# 10. uninstall.sh: the units disabled (the guard stopped with it), removed
# and systemd reloaded; the sampler's LaunchAgent booted out and removed.
reset
LINGER=yes run false _monitoring_linux_units
mkdir -p "$AGENTS_DIR"; cp "$REPO_DIR/configs/agents/dev.tuidev.sample.plist" "$SAMPLE_PLIST"
: > "$SCTL_LOG"; : > "$LOG"
# No package manager to ask, and no sudo: uninstall.sh looks at this
# machine's /Library for the cooling pack's root daemon, and must not reach it.
for t in brew sudo; do printf '#!/bin/sh\nexit 1\n' > "$tmp/linux/$t"; chmod +x "$tmp/linux/$t"; done
u_out="$(cd "$tmp" && PATH="$LINUX_PATH" bash "$REPO_DIR/uninstall.sh" --all </dev/null 2>&1)" || fail "uninstall.sh: $(tail -20 <<< "$u_out")"
rm -f "$tmp/linux/brew" "$tmp/linux/sudo"
for u in tuidev-sample.service tuidev-sample.timer tuidev-memguard.service; do [[ ! -e "$UNITS/$u" ]] || fail "uninstall left $u"; done
grep -qx -- "--user disable --now tuidev-sample.timer" "$SCTL_LOG" || fail "the sampler's timer not disabled: $(cat "$SCTL_LOG")"
grep -qx -- "--user disable --now tuidev-memguard.service" "$SCTL_LOG" || fail "the guard not disabled and stopped: $(cat "$SCTL_LOG")"
grep -qx -- "--user daemon-reload" "$SCTL_LOG" || fail "no daemon-reload after the removal: $(cat "$SCTL_LOG")"
[[ ! -e "$SAMPLE_PLIST" ]] || fail "uninstall left the sampler's plist"
grep -qx "bootout gui/$(id -u)/dev.tuidev.sample" "$LOG" || fail "the sampler not booted out: $(cat "$LOG")"
pass "uninstall disables and removes the sampler's and the guard's units, reloads systemd, boots out and removes the sampler's LaunchAgent"

# 11. Sourcing runs and prints nothing; the file never exits.
# shellcheck source=../install/packs/monitoring.sh disable=SC1091
src_out="$(PATH="$SAFE_PATH"; . "$PACK" 2>&1)" || fail "sourcing failed"
[[ -z "$src_out" ]] || fail "sourcing printed: $src_out"
if grep -Eq '(^|[^_[:alnum:]])exit[[:space:]]' "$PACK"; then fail "pack calls exit"; fi
pass "sourcing is silent; no exit"

echo
echo "All monitoring pack tests passed."
