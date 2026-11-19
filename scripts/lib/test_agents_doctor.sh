#!/bin/bash
# Unit tests for `agents doctor` (lib/agents/doctor.sh): each probe's ok,
# warn, fail and skipped rows (ps, the sampler, the memory guard, the hooks,
# the data and run dirs), --fix repairing and probing again, --fix -n
# running nothing, the --tsv rows `tuidev check` reads, and the exit codes.
# A temp HOME; launchctl, systemctl and the guard's state are stubs, and
# AGENTS_PATH is a stand-in: nothing real is loaded, started or signalled.
# Run: bash scripts/lib/test_agents_doctor.sh  -> exit 0 on pass.
# shellcheck disable=SC2016,SC2015  # $HOME in JSON on purpose; A && B || fail
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/tuidev-test.XXXXXX")"
tmp="$(cd "$tmp" && pwd)"
trap 'rm -rf "$tmp"' EXIT
for v in $(compgen -v AGENTS_) XDG_CONFIG_HOME XDG_STATE_HOME CLAUDE_CONFIG_DIR CODEX_SANDBOX TUIDEV_STATE_DIR; do unset "$v"; done
export HOME="$tmp/home" NO_COLOR=1 AGENTS_TESTING=1
export AGENTS_CONF="$tmp/none.conf" AGENTS_RUN_DIR="$tmp/run" AGENTS_DATA_DIR="$tmp/data"
mkdir -p "$HOME/.local/bin" "$HOME/.claude" "$HOME/Library/LaunchAgents" "$HOME/.config/systemd/user" "$tmp/run" "$tmp/data" "$tmp/stub"

# shellcheck source=../../bin/agents disable=SC1091
. "$REPO_DIR/bin/agents"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "PASS: $1"; }

# Stubs: launchctl and systemctl log their calls; a kickstart of the guard
# makes it "on"; the stand-in agents takes a sample by writing the stamp.
export CALLS="$tmp/calls"
cat > "$tmp/stub/launchctl" <<'EOF'
#!/bin/bash
echo "launchctl $*" >> "$CALLS"
case "$*" in *kickstart*dev.tuidev.memguard*) echo on > "$GUARD" ;; esac
exit 0
EOF
# SD_DOWN=1: no systemd user manager answers (a container).
cat > "$tmp/stub/systemctl" <<'EOF'
#!/bin/bash
[[ "$*" != "--user show-environment" ]] || exit "${SD_DOWN:-0}"
echo "systemctl $*" >> "$CALLS"
case "$*" in *restart*tuidev-memguard*) echo on > "$GUARD" ;; esac
exit 0
EOF
cat > "$tmp/agents-stub" <<EOF
#!/bin/bash
echo "agents \$*" >> "\$CALLS"
[[ "\$1" != sample ]] || date +%s > "$tmp/data/sample.stamp"
EOF
chmod +x "$tmp/stub"/* "$tmp/agents-stub"
export PATH="$tmp/stub:$PATH" GUARD="$tmp/guard"
AGENTS_PATH="$tmp/agents-stub"
_AGENTS_DOCTOR_WAIT=1

# The guard's state and ps, as the test sets them.
PS_OK=1
_agents_mem_ps_ok() { [[ "$PS_OK" == 1 ]]; }
_agents_mem_guard_state() { cat "$GUARD" 2>/dev/null || echo none; }
row() { printf '%s\n' "$_AGENTS_DOCTOR_ROWS" | awk -F '\t' -v n="$1" '$2 == n'; }
probe() { _AGENTS_DOCTOR_SBX=""; _agents_doctor_probe; }
now="$(date +%s)"

# 1. ps: readable, or a sandbox (skipped, never a failure).
probe; [[ "$(row ps)" == ok$'\t'* ]] || fail "ps readable: $(row ps)"
PS_OK=0 probe; [[ "$(row ps)" == "skip"$'\t'"ps"$'\t'"the process table can't be read from inside a sandbox"* ]] || fail "ps in a sandbox: $(row ps)"
pass "ps: readable is ok; a sandbox is a skip, with agents mem's wording"

# 2. The sampler, by history.sh's own staleness rule.
OSTYPE=darwin25
echo $((now - 30)) > "$tmp/data/sample.stamp"
probe; [[ "$(row sampler)" == ok$'\t'sampler$'\t'"last sample at "*"s ago)"* ]] || fail "a fresh sample: $(row sampler)"
echo $((now - 700)) > "$tmp/data/sample.stamp"
probe; [[ "$(row sampler)" == fail$'\t'sampler$'\t'"no sampler has run since "*$'\t'"tuidev install --pack monitoring" ]] \
    || fail "a stale sample, no LaunchAgent: $(row sampler)"
: > "$HOME/Library/LaunchAgents/dev.tuidev.sample.plist"
probe; [[ "$(row sampler)" == fail$'\t'*$'\t'"launchctl kickstart -k gui/$UID/dev.tuidev.sample" ]] || fail "a stale sample with the LaunchAgent: $(row sampler)"
rm -f "$tmp/data/sample.stamp"
probe; [[ "$(row sampler)" == fail$'\t'sampler$'\t'"no sampler has run yet"* ]] || fail "no sample at all: $(row sampler)"
AGENTS_SAMPLER=0 probe; [[ "$(row sampler)" == warn$'\t'* ]] || fail "AGENTS_SAMPLER=0 is a choice: $(row sampler)"
AGENTS_HISTORY=0 probe; [[ "$(row sampler)" == skip$'\t'sampler$'\t'"history is off"* ]] || fail "AGENTS_HISTORY=0: $(row sampler)"
OSTYPE=linux-gnu probe; [[ "$(row sampler)" == fail$'\t'*$'\t'"tuidev install --pack monitoring" ]] || fail "Linux without the timer: $(row sampler)"
: > "$HOME/.config/systemd/user/tuidev-sample.timer"
OSTYPE=linux-gnu probe; [[ "$(row sampler)" == fail$'\t'*$'\t'"systemctl --user enable --now tuidev-sample.timer" ]] || fail "Linux with the timer: $(row sampler)"
SD_DOWN=1 OSTYPE=linux-gnu probe
[[ "$(row sampler)" == skip$'\t'sampler$'\t'"nothing here can run one on a schedule: no systemd user manager answers here (a container, or a sandbox)"* ]] \
    || fail "Linux without a systemd user manager must skip the sampler: $(row sampler)"
echo $((now - 30)) > "$tmp/data/sample.stamp"
SD_DOWN=1 OSTYPE=linux-gnu probe; [[ "$(row sampler)" == ok$'\t'* ]] || fail "a fresh sample without systemd (agents watch): $(row sampler)"
rm -f "$tmp/data/sample.stamp"
pass "sampler: fresh is ok, stale or none fails with the command that starts its job, AGENTS_SAMPLER=0 warns, AGENTS_HISTORY=0 skips, no systemd skips"

# 3. The memory guard, every state.
for s in "on 42|ok|on (pid 42)" "stalled 42 900|fail|stalled: pid 42 has not looked for 900s" "stopped|fail|installed, but no guard runs" \
         "off|skip|off (AGENTS_MEM_GUARD=off)" "unknown|skip|the process table can't be read from inside a sandbox" "none|warn|nothing runs one here"; do
    IFS='|' read -r st want detail <<<"$s"
    echo "$st" > "$GUARD"; probe
    [[ "$(row "memory guard")" == "$want"$'\t'"memory guard"$'\t'"$detail"* ]] || fail "guard $st: $(row "memory guard")"
done
echo "stalled 42 900" > "$GUARD"; probe
[[ "$(row "memory guard")" == *$'\t'"agents mem restart" ]] || fail "a stalled guard's fix: $(row "memory guard")"
for s in "stopped|skip|nothing here can run one: no systemd user manager" "none|skip|nothing here can run one: no systemd user manager" \
         "on 42|ok|on (pid 42)" "stalled 42 900|fail|stalled: pid 42 has not looked for 900s"; do
    IFS='|' read -r st want detail <<<"$s"
    echo "$st" > "$GUARD"; SD_DOWN=1 OSTYPE=linux-gnu probe
    [[ "$(row "memory guard")" == "$want"$'\t'"memory guard"$'\t'"$detail"* ]] || fail "no systemd, guard $st: $(row "memory guard")"
done
[[ "$(row "memory guard")" != *$'\t'"agents mem restart" ]] || fail "without systemd, agents mem restart can't be the fix"
pass "memory guard: on ok; stalled and stopped fail (agents mem restart); off and unknown skip; none warns; without systemd stopped and none skip"

# 4. Claude Code's hooks call this agents.
S="$HOME/.claude/settings.json"
probe; [[ "$(row hooks)" == skip$'\t'hooks$'\t'"no ~/.claude/settings.json"$'\t' ]] || fail "no settings: $(row hooks)"
printf '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"echo hi"}]}]}}\n' > "$S"
probe; [[ "$(row hooks)" == skip$'\t'hooks$'\t'"Claude Code's hooks come with --pack ai-clis"* ]] || fail "no agents hook, no ai-clis pack: $(row hooks)"
mkdir -p "$HOME/.config/tuidev"; printf 'profile=custom\nextra_packs=monitoring ai-clis\n' > "$HOME/.config/tuidev/profile"
probe; [[ "$(row hooks)" == warn$'\t'hooks$'\t'"no hook or status line"* ]] || fail "no agents hook with ai-clis: $(row hooks)"
printf '%s\n' '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"[ -x \"$HOME/.local/bin/agents\" ] && \"$HOME/.local/bin/agents\" hook x"}]}]},' \
    '"statusLine":{"type":"command","command":"exec \"$HOME/.local/bin/agents\" statusline"}}' > "$S"
probe; [[ "$(row hooks)" == fail$'\t'hooks$'\t'"2 command(s) in ~/.claude/settings.json call ~/.local/bin/agents, which is not there"* ]] || fail "agents missing: $(row hooks)"
ln -s "$AGENTS_PATH" "$HOME/.local/bin/agents"
probe; [[ "$(row hooks)" == ok$'\t'hooks$'\t'"2 command(s)"*"call this agents"* ]] || fail "this agents: $(row hooks)"
rm "$HOME/.local/bin/agents"; cp "$AGENTS_PATH" "$HOME/.local/bin/agents"
probe; [[ "$(row hooks)" == warn$'\t'*"not this one ($AGENTS_PATH)"* ]] || fail "another agents: $(row hooks)"
before="$(cksum < "$S")"
( _AGENTS_DOCTOR_ROWS=""; PATH="$tmp/empty" _agents_doctor_hooks; printf "%s" "$_AGENTS_DOCTOR_ROWS" ) | grep -q $'^skip\thooks\tjq is not installed\t$' || fail "no jq: not skipped"
[[ "$(cksum < "$S")" == "$before" ]] || fail "the doctor changed settings.json"
pass "hooks: none (warns with ai-clis, else skipped), missing, this agents, another agents; no jq or no settings.json is a skip; the file is only read"

# 5. The data and run dirs.
probe; [[ "$(row dirs)" == ok$'\t'* ]] || fail "writable dirs: $(row dirs)"
if [[ "$(id -u)" != 0 ]]; then
    chmod 500 "$tmp/data"
    probe; [[ "$(row dirs)" == fail$'\t'dirs$'\t'"not writable: $tmp/data"* ]] || fail "a read-only data dir: $(row dirs)"
    PS_OK=0 probe; [[ "$(row dirs)" == skip$'\t'* ]] || fail "a read-only data dir in a sandbox must be skipped: $(row dirs)"
    CODEX_SANDBOX=seatbelt probe; [[ "$(row dirs)" == skip$'\t'* ]] || fail "under Codex's sandbox: $(row dirs)"
    chmod 700 "$tmp/data"
fi
AGENTS_RUN_DIR="$tmp/not/yet" probe; [[ "$(row dirs)" == ok$'\t'* ]] || fail "a dir that can be made: $(row dirs)"
pass "dirs: writable or makeable is ok, read-only fails, and inside a sandbox is a skip"

# 6. --fix: the sampler's job and the guard restarted, then probed again;
#    --fix -n runs nothing. Exit codes: 1 while a probe fails, 0 once none
#    does, 2 for a bad argument.
echo $((now - 700)) > "$tmp/data/sample.stamp"; echo stopped > "$GUARD"
: > "$HOME/Library/LaunchAgents/dev.tuidev.memguard.plist"; rm -f "$CALLS"
rc=0; out="$(agents_main doctor --fix -n --tsv)" || rc=$?
[[ $rc -eq 1 && ! -e "$CALLS" ]] || fail "--fix -n ran something (rc $rc): $(cat "$CALLS" 2>/dev/null)"
[[ "$out" == *$'would\tsampler\tlaunchctl kickstart -k gui/'"$UID"$'/dev.tuidev.sample\t'* && "$out" == *$'would\tmemory guard\tagents mem restart\t'* ]] || fail "--fix -n rows: $out"
[[ "$(cat "$GUARD")" == stopped ]] || fail "--fix -n changed the guard"
rc=0; out="$(agents_main doctor --fix --tsv)" || rc=$?
[[ $rc -eq 0 ]] || fail "--fix left a failure: $out"
[[ "$out" == *$'did\tsampler\t'* && "$out" == *$'did\tmemory guard\t'* && "$out" == *$'ok\tsampler\t'* && "$out" == *$'ok\tmemory guard\ton'* ]] || fail "--fix rows: $out"
grep -q "launchctl kickstart -k gui/$UID/dev.tuidev.sample" "$CALLS" && grep -q "launchctl kickstart -k gui/$UID/dev.tuidev.memguard" "$CALLS" \
    && grep -q "agents sample" "$CALLS" || fail "--fix calls: $(cat "$CALLS")"
rc=0; agents_main doctor >/dev/null || rc=$?; [[ $rc -eq 0 ]] || fail "healthy: exit $rc"
rc=0; agents_main doctor --bogus 2>/dev/null || rc=$?; [[ $rc -eq 2 ]] || fail "a bad argument: exit $rc"
pass "--fix restarts the sampler's job and the guard, probes again, exits 0; --fix -n runs nothing and exits 1; a bad argument is 2"

# Linux: systemd, through the same commands.
OSTYPE=linux-gnu
echo $((now - 700)) > "$tmp/data/sample.stamp"; echo stopped > "$GUARD"; rm -f "$CALLS"
: > "$HOME/.config/systemd/user/tuidev-memguard.service"
rc=0; out="$(agents_main doctor --fix --tsv)" || rc=$?
[[ $rc -eq 0 ]] && grep -q "systemctl --user enable --now tuidev-sample.timer" "$CALLS" && grep -q "systemctl --user restart tuidev-memguard.service" "$CALLS" \
    || fail "Linux --fix (rc $rc): $out / $(cat "$CALLS")"
echo $((now - 700)) > "$tmp/data/sample.stamp"; echo stopped > "$GUARD"; rm -f "$CALLS"
rc=0; out="$(SD_DOWN=1 agents_main doctor --fix --tsv)" || rc=$?
[[ $rc -eq 0 && ! -e "$CALLS" && "$out" != *did$'\t'* && "$out" == *$'skip\tsampler\t'* && "$out" == *$'skip\tmemory guard\t'* ]] \
    || fail "no systemd: --fix must do nothing and exit 0 (rc $rc): $out / $(cat "$CALLS" 2>/dev/null)"
echo "stalled 42 900" > "$GUARD"
rc=0; out="$(SD_DOWN=1 agents_main doctor --fix --tsv)" || rc=$?
[[ $rc -eq 1 && ! -e "$CALLS" ]] || fail "no systemd: a stalled guard by hand is not restarted (rc $rc): $(cat "$CALLS" 2>/dev/null)"
OSTYPE=darwin25
pass "Linux: --fix enables the sampler's timer and restarts the guard's service; without systemd it skips both and runs nothing"

# Nothing to repair automatically: no job installed, the guard nowhere.
rm -f "$HOME/Library/LaunchAgents/dev.tuidev.sample.plist" "$CALLS"; echo $((now - 700)) > "$tmp/data/sample.stamp"; echo none > "$GUARD"
rc=0; out="$(agents_main doctor --fix --tsv)" || rc=$?
[[ $rc -eq 1 && ! -e "$CALLS" && "$out" != *did$'\t'* ]] || fail "--fix ran something it can't repair (rc $rc): $out"
pass "a sampler with no job installed is not repaired: its fix is a command for you"

# 7. What a person reads.
echo $((now - 30)) > "$tmp/data/sample.stamp"; echo "on 42" > "$GUARD"
out="$(agents_main doctor)"
[[ "$out" == *"✓ sampler       last sample at"* && "$out" == *"✓ memory guard  on (pid 42)"* ]] || fail "the lines: $out"
echo "stalled 42 900" > "$GUARD"
out="$(agents_main doctor)" || true
[[ "$out" == *"✗ memory guard  stalled: pid 42 has not looked for 900s"*"fix: agents mem restart"* ]] || fail "a failure's fix line: $out"
pass "the lines: a mark, the name, the detail, the fix under a failure"

echo
echo "All agents doctor tests passed."
