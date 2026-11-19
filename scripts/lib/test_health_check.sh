#!/bin/bash
# Unit tests for scripts/health_check.sh: the compinit check
# (check_zshrc_compinit), the Seatbelt smoke probe run inside a sandbox (a
# stub sandbox-exec), and the pack probes (packs.sh pack_check and each
# pack's <pack>_check, against stub commands). Fixtures in a temp HOME,
# nothing real read.
# Run: bash scripts/lib/test_health_check.sh  -> exit 0 on pass.
# shellcheck disable=SC2016  # zsh text in single quotes on purpose
set -eo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/tuidev-test.XXXXXX")"; trap 'rm -rf "$tmp"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

export HOME="$tmp/home" TUIDEV_STATE_DIR="$tmp/home/.config/tuidev" TUIDEV_NO_COLOR=1
unset ZDOTDIR XDG_CONFIG_HOME FNM_DIR
mkdir -p "$HOME" "$TUIDEV_STATE_DIR"

# shellcheck source=../ui.sh disable=SC1091
. "$LIB_DIR/ui.sh"
# shellcheck source=config_write.sh disable=SC1091
. "$LIB_DIR/config_write.sh"
eval "$(sed -n '/^check_zshrc_compinit() {/,/^}/p' "$LIB_DIR/../health_check.sh")"

B="$(tuidev_block_begin tuidev-zshrc)"; E="$(tuidev_block_end tuidev-zshrc)"
# The shipped block: two compinit branches, one of which runs.
block() { printf '%s\n' "$B"; grep -v '^#' "$LIB_DIR/../../configs/zsh/.zshrc"; printf '%s\n' "$E"; }
run() { ( OPT_WARN=0; check_zshrc_compinit 2>&1; echo "end $OPT_WARN" ); }

# The shipped file alone: one compinit.
block > "$HOME/.zshrc"
[[ "$(grep -c 'compinit' "$HOME/.zshrc")" -gt 1 ]] || fail "fixture: the shipped block has no compinit branches"
out="$(run)"; [[ "$out" == "end 0" ]] || fail "the shipped block alone warns: $out"
pass "the tuidev block counts as one compinit however many branches it has"

# An installer's own call after it: two. Comments and autoload are not calls.
{ block; printf '%s\n' '# compinit is run above' 'autoload -Uz compinit' 'autoload -U compinit && compinit' ; } > "$HOME/.zshrc"
out="$(run)"
[[ "$out" == *"compinit runs 2 times"*"~/.zshrc: 2"*"never edits"*"end 1" ]] || fail "an added compinit: $out"
pass "an installer's compinit after the block: warned once, with the advice"

# Others: indented, after ;, &&, then; and ~/.zshrc.local is counted too.
{ printf '%s\n' 'if true; then' '  compinit -i' 'fi' 'x=1; compinit'; } > "$HOME/.zshrc"
printf '%s\n' '[[ -n $X ]] && compinit -C' > "$HOME/.zshrc.local"
out="$(run)"; [[ "$out" == *"3 times"*"~/.zshrc.local: 1"*"end 1" ]] || fail "forms of a call: $out"
pass "indented calls and calls after ; or && count, ~/.zshrc.local included"

# Not the file's own business otherwise: one call, none, no file, a trailing comment.
printf '%s\n' 'autoload -Uz compinit && compinit  # once' > "$HOME/.zshrc"; rm -f "$HOME/.zshrc.local"
out="$(run)"; [[ "$out" == "end 0" ]] || fail "one call warned: $out"
rm -f "$HOME/.zshrc"
out="$(run)"; [[ "$out" == "end 0" ]] || fail "no file warned: $out"
before="$(printf '%s\n' 'compinit' 'compinit')"; printf '%s\n' "$before" > "$HOME/.zshrc"; run >/dev/null
[[ "$(cat "$HOME/.zshrc")" == "$before" ]] || fail "the check edited the file"
pass "one call, no file: silent; the file is never edited"

# --- The Seatbelt smoke probe inside a sandbox ---------------------------------------
# A fake sandbox-exec: Seatbelt refusing to nest (rc 71), or another failure.
STUBS="$tmp/stubs"; mkdir -p "$STUBS"
cat > "$STUBS/sandbox-exec" <<'EOF'
#!/bin/bash
case "${SBX_STUB:-ok}" in
    nested) echo "sandbox-exec: sandbox_apply: Operation not permitted" >&2; exit 71 ;;
    broken) echo "sandbox-exec: invalid profile" >&2; exit 65 ;;
esac
EOF
chmod +x "$STUBS/sandbox-exec"
for f in check_required check_optional have_cmd check_sandbox; do
    body="$(sed -n "/^$f() [{]/,/^[}]/p" "$LIB_DIR/../health_check.sh")"   # in a variable first: bash 3.2
    eval "$body"
done
# shellcheck disable=SC2034  # TUIDEV_OS is read by check_sandbox
smoke() { ( PATH="$STUBS:/usr/bin:/bin" TUIDEV_OS=Darwin REQ_PASS=0 REQ_FAIL=0 OPT_WARN=0; SBX_STUB="$1" check_sandbox required 2>&1 || true; echo "fail=$REQ_FAIL pass=$REQ_PASS" ); }
out="$(smoke nested)"
[[ "$out" == *"sandbox-exec works (inline smoke profile): skipped, already inside a sandbox"* && "$out" != *"sandbox-exec works (inline smoke profile) (required)"* && "$out" == *"fail=2 pass=0" ]] \
    || fail "nested Seatbelt: the smoke probe must be skipped (the other two still fail here): $out"
out="$(smoke broken)"
[[ "$out" == *"sandbox-exec works (inline smoke profile) (required)"* && "$out" == *"fail=3 "* ]] || fail "another sandbox-exec failure must stay a required failure: $out"
out="$(smoke ok)"
[[ "$out" != *"skipped"* && "$out" == *"fail=2 pass=1" ]] || fail "a working sandbox-exec passes: $out"
pass "sandbox-exec refused for nesting is a skip; any other failure is still a required failure"

# --- Pack probes (scripts/lib/packs.sh pack_check, each pack's <pack>_check) ----------
# shellcheck source=packs.sh disable=SC1091
. "$LIB_DIR/packs.sh"
# shellcheck source=pkg.sh disable=SC1091
. "$LIB_DIR/pkg.sh"
PB="$tmp/pbin"; mkdir -p "$PB"
stub() { local c; for c in "$@"; do printf '#!/bin/bash\n' > "$PB/$c"; chmod +x "$PB/$c"; done; }
os() { printf '#!/bin/bash\necho %s\n' "$1" > "$PB/uname"; chmod +x "$PB/uname"; }
probe() { PATH="$PB:/usr/bin:/bin" RELEASE_AGE_TOOL_DIRS="$tmp/none" pack_check "$1" >/dev/null 2>&1; }
os Linux

# release-age (no binary of its own): passes when each installed tool waits.
probe release-age || fail "release-age with none of npm, bun, uv installed has nothing to wait for"
stub bun; ! probe release-age || fail "release-age: bun without a minimumReleaseAge passed"
printf '[install]\nminimumReleaseAge = 259200\n' > "$HOME/.bunfig.toml"; probe release-age || fail "release-age: bun waits"
stub npm; ! probe release-age || fail "release-age: npm without a setting or a record passed"
printf 'block tuidev-release-age %s\n' "$HOME/.npmrc" > "$TUIDEV_STATE_DIR/manifest"
probe release-age || fail "release-age: npm with our block recorded (the file is not read then)"
rm -f "$TUIDEV_STATE_DIR/manifest"; printf 'min-release-age=5\n' > "$HOME/.npmrc"
probe release-age || fail "release-age: npm with your own setting"
pass "release-age: each installed npm, bun and uv waits, by our block or your own setting"

# cooling: nothing to do off Apple Silicon, so it passes there.
probe cooling || fail "cooling on Linux has nothing to do"
pass "cooling: passes where the pack has nothing to do"

# herdr-core: the binary and the job that keeps it up.
! probe herdr-core || fail "herdr-core without herdr-core passed"
stub herdr-core; ! probe herdr-core || fail "herdr-core without its systemd timer passed"
mkdir -p "$HOME/.config/systemd/user"; : > "$HOME/.config/systemd/user/tuidev-hc.timer"
probe herdr-core || fail "herdr-core with its binary and timer"
pass "herdr-core: its binary and the job that keeps it up"

# The fallback, for packs with no probe of their own: what they declare.
! probe hunk || fail "hunk without hunk passed"
stub hunk; probe hunk || fail "hunk with hunk"
stub nvim; probe nvim || fail "nvim: the neovim formula's command is nvim"
stub actionlint zizmor; ! probe ci || fail "ci with two of its three tools passed"
stub betterleaks; probe ci || fail "ci with all three"
stub agents btm; ! probe monitoring || fail "monitoring without its sampler's systemd timer passed"
: > "$HOME/.config/systemd/user/tuidev-sample.timer"
probe monitoring || fail "monitoring on Linux needs no terminal-notifier"
os Darwin; ! probe monitoring || fail "monitoring on macOS without the sampler's LaunchAgent passed"
mkdir -p "$HOME/Library/LaunchAgents"; : > "$HOME/Library/LaunchAgents/dev.tuidev.sample.plist"
probe monitoring || fail "monitoring on macOS with agents, btm and the sampler's LaunchAgent"
os Linux
stub tmux; ! probe tmux || fail "tmux without its config passed"
mkdir -p "$HOME/.config/tmux"; : > "$HOME/.config/tmux/tmux.conf"; probe tmux || fail "tmux with its config"
pass "the fallback looks for the declared commands (macOS-only ones skipped elsewhere); tmux checks its config too"

# --- Runtime probes and --fix: the whole script, against a fixture home ----------
# Stubs: every core command this machine lacks, zsh, uname (FAKE_OS),
# launchctl (state in $RT.loaded.LABEL; LCTL=sandbox answers as inside
# Seatbelt), systemctl (state in $RT.sd.UNIT.*; SD_DOWN=1: no user manager).
# Both log every call to $RT.calls. Nothing real is loaded or started.
HC="$LIB_DIR/../health_check.sh"; REPO="$(cd "$LIB_DIR/../.." && pwd)"
RT="$tmp/rt"; RS="$tmp/rts"; RL="$tmp/rtl"; RD="$tmp/rtd"; SYS="$tmp/sys"; JQ=""
mkdir -p "$RS" "$RL" "$RD" "$SYS"
ln -s /usr/bin/* "$SYS/" 2>/dev/null || true
ln -s /bin/* "$SYS/" 2>/dev/null || true
rm -f "$SYS/jq" "$SYS/launchctl" "$SYS/systemctl" "$SYS/uname" "$SYS/tuidev" "$SYS/agents"
if command -v jq >/dev/null 2>&1; then mkdir -p "$tmp/jq"; ln -s "$(command -v jq)" "$tmp/jq/jq"; JQ="$tmp/jq"; fi
for b in $(pack_binaries core) zsh; do
    [[ "$b" == jq ]] || PATH="$SYS" command -v "$b" >/dev/null 2>&1 || printf '#!/bin/sh\nexit 0\n' > "$RS/$b"
done
cat > "$RS/uname" <<'EOF'
#!/bin/sh
case "$1" in -r) echo 1.0 ;; -m) echo arm64 ;; *) echo "${FAKE_OS:-Darwin}" ;; esac
EOF
cat > "$RL/launchctl" <<'EOF'
#!/bin/bash
echo "launchctl $*" >> "$RTM.calls"
case "$1" in
    print) if [[ "${LCTL:-}" == sandbox ]]; then echo "Could not print domain: 1: Operation not permitted" >&2; exit 1; fi
           [[ ! -e "$RTM.loaded.${2##*/}" ]] || exit 0
           printf 'Bad request.\nCould not find service "%s" in domain for user gui: 501\n' "${2##*/}" >&2; exit 113 ;;
    bootstrap) l="${3##*/}"; : > "$RTM.loaded.${l%.plist}" ;;
esac
exit 0
EOF
cat > "$RD/systemctl" <<'EOF'
#!/bin/bash
echo "systemctl $*" >> "$RTM.calls"
[[ "$1" != --user ]] || shift
cmd="$1"; shift
now=0; units=()
for a in "$@"; do case "$a" in --now) now=1 ;; -*) ;; *) units+=("$a") ;; esac; done
case "$cmd" in
    show-environment) exit "${SD_DOWN:-0}" ;;
    is-enabled) if [[ -e "$RTM.sd.${units[0]}.enabled" ]]; then echo enabled; else echo disabled; exit 1; fi ;;
    is-active)  if [[ -e "$RTM.sd.${units[0]}.active" ]]; then echo active; else echo inactive; exit 3; fi ;;
    enable)     for u in "${units[@]}"; do : > "$RTM.sd.$u.enabled"; [[ $now == 0 ]] || : > "$RTM.sd.$u.active"; done ;;
    start|restart) for u in "${units[@]}"; do : > "$RTM.sd.$u.active"; done ;;
esac
exit 0
EOF
chmod +x "$RS"/* "$RL/launchctl" "$RD/systemctl"

# rt_fixture PACKS — a fresh home: the profile, this release applied, and the
# commands every install puts in ~/.local/bin, as these files have them.
# With monitoring, agents and its modules too.
H="$RT/home"; HS="$H/.config/tuidev"
rt_fixture() {
    rm -rf "$RT" "$RT".*; mkdir -p "$HS" "$H/.local/bin" "$H/Library/LaunchAgents" "$H/.config/systemd/user" "$H/.claude"
    printf 'profile=minimal\ncore=true\nremote=false\nsandbox=false\nui=false\nextras=false\nextra_packs=%s\nrepo=%s\n' "$1" "$REPO" > "$HS/profile"
    cp "$REPO/VERSION" "$HS/version"
    cp "$REPO/bin/tuidev" "$REPO/bin/secret" "$REPO/bin/mcp-lazy" "$H/.local/bin/"
    cp "$REPO/scripts/notify.sh" "$H/.local/bin/notify.sh"
    if [[ " $1 " == *" monitoring "* ]]; then
        mkdir -p "$H/.local/lib/tuidev/agents"
        cp -R "$REPO/lib/agents/." "$H/.local/lib/tuidev/agents/"
        cp "$REPO/bin/agents" "$H/.local/bin/agents"
    fi
    chmod +x "$H/.local/bin/"*
    printf '# tuidev install manifest\n' > "$HS/manifest"
}
# hc ARGS... — the whole check as tuidev check runs it; output, then "rc=N".
# PRE: a dir first on PATH; NOLC=1, NOSD=1, NOJQ=1: no launchctl, systemctl, jq.
hc() {
    local rc=0 p="${PRE:+$PRE:}$RS"
    [[ -n "${NOLC:-}" ]] || p+=":$RL"
    [[ -n "${NOSD:-}" ]] || p+=":$RD"
    p+=":$H/.local/bin:$SYS"
    [[ -n "${NOJQ:-}" || -z "$JQ" ]] || p+=":$JQ"
    env -u XDG_CONFIG_HOME -u XDG_STATE_HOME -u CODEX_HOME -u CLAUDE_CONFIG_DIR -u CODEX_SANDBOX \
        HOME="$H" TUIDEV_STATE_DIR="$HS" TUIDEV_NO_COLOR=1 RTM="$RT" FAKE_OS="${FAKE_OS:-Darwin}" \
        AGENTS_HISTORY=0 AGENTS_MEM_GUARD=off AGENTS_NO_HERDR=1 AGENTS_CONF="$tmp/none.conf" PATH="$p" \
        "$BASH" "$HC" --profile minimal "$@" 2>&1 || rc=$?
    echo "rc=$rc"
}
has() { [[ "$out" == *"$1"* ]] || fail "${2:-expected}: no '$1' in: $(printf '%s\n' "$out" | sed -n '/Runtime/,$p')"; }
hasnt() { [[ "$out" != *"$1"* ]] || fail "${2:-unexpected}: '$1' in: $(printf '%s\n' "$out" | sed -n '/Runtime/,$p')"; }
snap() { find "$H" -type f -exec cksum {} + 2>/dev/null | LC_ALL=C sort; find "$H" | LC_ALL=C sort; }

# Exit codes on a healthy fixture, and a bad argument.
rt_fixture ""
out="$(hc)"; has "rc=0" "a healthy home"; has "Runtime failed:    0"
out="$(hc --bogus)"; has "rc=2" "a bad argument"
rm "$HS/profile"; out="$(hc)"; has "runtime: skipped: no install is recorded here"; hasnt "is not installed (fix"
pass "exit 0 when nothing fails, 2 for a bad argument; with no install recorded the runtime probes are skipped"

# 1. macOS: each LaunchAgent the active packs declare is loaded, not only on disk.
rt_fixture monitoring
for l in sample memguard; do printf '<plist/>\n' > "$H/Library/LaunchAgents/dev.tuidev.$l.plist"; done
: > "$RT.loaded.dev.tuidev.memguard"
out="$(hc)"
has "✗ dev.tuidev.sample is installed but not loaded (fix: launchctl bootstrap gui/$UID ~/Library/LaunchAgents/dev.tuidev.sample.plist; tuidev check --fix does it)"
has "✓ dev.tuidev.memguard loaded (launchd)"
has "✗ dev.tuidev.link: no LaunchAgent at ~/Library/LaunchAgents/dev.tuidev.link.plist"
has "Runtime failed:    2"; has "rc=1" "a job not loaded is a failure"
grep -q "launchctl print gui/$UID/dev.tuidev.sample" "$RT.calls" || fail "launchctl print was not asked"
! grep -qE 'launchctl (bootstrap|bootout|kickstart)' "$RT.calls" || fail "the check changed launchd: $(cat "$RT.calls")"
out="$(LCTL=sandbox hc)"
has "dev.tuidev.sample loaded: skipped: launchd can't be asked from inside a sandbox"
hasnt "✗ dev.tuidev.sample" "inside a sandbox a job must be skipped, not failed"
out="$(NOLC=1 hc)"
has "dev.tuidev.memguard loaded: skipped: launchctl is not here"
pass "LaunchAgents: loaded passes, unloaded and missing fail with the command, a sandbox or no launchctl is a skip"

# --fix --dry-run changes nothing and says what it would do; --fix loads them
# with the pack's own step (the plist written as the pack writes it) and probes again.
before="$(snap)"; rm -f "$RT.calls"
out="$(hc --fix --dry-run)"
has "[DRY RUN] the monitoring pack's step for its sampler (_monitoring_sampler)"
has "[DRY RUN] the monitoring pack's step for its link watcher (_monitoring_link)"
has "That was a dry run"; has "rc=1" "a dry run leaves the failures"
[[ "$(snap)" == "$before" ]] || fail "--fix --dry-run changed the home: $(diff <(echo "$before") <(snap) | head -5)"
! grep -qE 'launchctl (bootstrap|bootout|kickstart)' "$RT.calls" || fail "--fix --dry-run ran launchctl: $(cat "$RT.calls")"
out="$(hc --fix)"
has "--fix: the monitoring pack's step for its sampler (_monitoring_sampler)"
has "✓ dev.tuidev.sample loaded (launchd)"; has "✓ dev.tuidev.link loaded (launchd)"
has "Runtime failed:    0"; has "rc=0" "--fix repaired every failure"
grep -q "launchctl bootstrap gui/$UID $H/Library/LaunchAgents/dev.tuidev.link.plist" "$RT.calls" || fail "no bootstrap: $(cat "$RT.calls")"
grep -q "<string>$H/.local/bin/agents</string>" "$H/Library/LaunchAgents/dev.tuidev.link.plist" || fail "the link plist was not written from the template"
grep -qxF "file $H/Library/LaunchAgents/dev.tuidev.link.plist" "$HS/manifest" || fail "--fix did not record what it wrote"
[[ ! -e "$HS/update.lock" ]] || fail "--fix left its lock"
pass "--fix --dry-run changes nothing; --fix loads each LaunchAgent with the pack's step, records it, probes again: exit 0"

# 2. Linux: user units enabled (and a timer active); no systemd is a skip.
FAKE_OS=Linux; export FAKE_OS
rt_fixture monitoring
U="$H/.config/systemd/user"; : > "$U/tuidev-sample.timer"; : > "$U/tuidev-memguard.service"
: > "$RT.sd.tuidev-sample.timer.enabled"; : > "$RT.sd.tuidev-sample.timer.active"; : > "$RT.sd.tuidev-memguard.service.enabled"
out="$(hc)"
has "✓ tuidev-sample.timer enabled and active (systemd)"; has "✓ tuidev-memguard.service enabled (systemd)"
hasnt "dev.tuidev." "LaunchAgents are not probed on Linux"; has "rc=0"
rm -f "$RT.sd.tuidev-sample.timer.active"
out="$(hc)"; has "✗ tuidev-sample.timer is enabled but inactive (fix: systemctl --user enable --now tuidev-sample.timer"; has "rc=1"
rm -f "$RT.sd.tuidev-sample.timer.enabled"
out="$(hc)"; has "✗ tuidev-sample.timer is disabled"
out="$(SD_DOWN=1 hc)"; has "tuidev-sample.timer enabled: skipped: no systemd user manager answers here"; hasnt "✗ tuidev-sample"
out="$(NOSD=1 hc)"; has "tuidev-sample.timer enabled: skipped: systemctl is not here"
out="$(hc --fix)"
has "--fix: start tuidev-sample.timer"; has "✓ tuidev-sample.timer enabled and active (systemd)"; has "rc=0"
rm -f "$U/tuidev-memguard.service" "$RT".sd.*
out="$(hc --fix)"
has "--fix: the monitoring pack's step for its sampler and memory guard units (_monitoring_linux_units)"
has "✓ tuidev-memguard.service enabled (systemd)"; has "rc=0"
cmp -s "$U/tuidev-memguard.service" "$REPO/configs/agents/tuidev-memguard.service" || fail "the unit was not written as shipped"
FAKE_OS=Darwin
pass "Linux: units enabled and a timer active; disabled or inactive fails; no systemd is a skip; --fix enables, or writes the units first"

# 3. Version drift: the installed commands against these files, and PATH.
rt_fixture ""
echo "# edited" >> "$H/.local/bin/tuidev"; rm "$H/.local/bin/notify.sh"; echo 0.0.1 > "$HS/version"
mkdir -p "$tmp/other"; printf '#!/bin/sh\n' > "$tmp/other/secret"; chmod +x "$tmp/other/secret"
out="$(PRE="$tmp/other" hc)"
has "⚠ tuidev: ~/.local/bin/tuidev is not the one in $REPO (1 file(s) differ)"
has "✗ notify.sh: ~/.local/bin/notify.sh is not installed"
has "⚠ tuidev: the configs applied are 0.0.1's, the files in $REPO are $(cat "$REPO/VERSION") (fix: tuidev update --configs)"
has "⚠ secret: PATH finds $tmp/other/secret before ~/.local/bin/secret (fix: remove $tmp/other/secret, or put ~/.local/bin earlier in PATH)"
has "rc=1"
out="$(PRE="$tmp/other" hc --fix)"
{ cmp -s "$H/.local/bin/tuidev" "$REPO/bin/tuidev" && cmp -s "$H/.local/bin/notify.sh" "$REPO/scripts/notify.sh"; } || fail "--fix did not put the commands back"
has "✓ notify.sh: ~/.local/bin/notify.sh is the one in these files"
[[ "$(cat "$HS/version")" == 0.0.1 ]] || fail "--fix wrote the installed version (an unfinished update would look finished)"
has "⚠ secret: PATH finds $tmp/other/secret"; [[ -e "$tmp/other/secret" ]] || fail "--fix touched a file on PATH that is not tuidev's"
pass "version drift: an edited or missing copy, configs from another release, another copy first on PATH; --fix reinstalls tuidev's own"

# 4. Hooks that start a program that is gone: tuidev's fail, the rest warn, none is edited.
if [[ -n "$JQ" ]]; then
rt_fixture ""
rm "$H/.local/bin/notify.sh"; mkdir -p "$H/bin" "$H/.codex"; printf '#!/bin/sh\n' > "$H/bin/ok-hook"; chmod +x "$H/bin/ok-hook"; : > "$H/bin/not-exec"
cat > "$H/.claude/settings.json" <<'EOF'
{"hooks":{
  "Notification":[{"matcher":"x","hooks":[{"type":"command","command":"\"$HOME/.local/bin/notify.sh\" 'Claude Code' 'Needs you'"}]}],
  "Stop":[{"hooks":[{"type":"command","command":"~/bin/their-hook.sh --flag"},{"type":"command","command":"python3 ${HOME}/bin/gone.py"},
                    {"type":"command","command":"~/bin/ok-hook"},{"type":"command","command":"$HOME/bin/not-exec"},
                    {"type":"command","command":"[ -x \"$HOME/.local/bin/agents\" ] && exit 0"},{"type":"command","command":"jq -n 1"}]}]},
 "statusLine":{"type":"command","command":"/opt/nowhere/status"}}
EOF
printf '{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"/opt/codex-hook.sh"}]}]}}\n' > "$H/.codex/hooks.json"
printf 'model = "x"\nnotify = ["/opt/notifier", "--x"]\n[tui]\nnotify = ["/ignored"]\n' > "$H/.codex/config.toml"
before="$(cksum "$H/.claude/settings.json" "$H/.codex/hooks.json" "$H/.codex/config.toml")"
out="$(hc)"
has "✗ ~/.claude/settings.json: the Notification hook runs ~/.local/bin/notify.sh, which is not there (fix: tuidev update --configs; tuidev check --fix does it)"
has "⚠ ~/.claude/settings.json: the Stop hook runs ~/bin/their-hook.sh, which is not there (not tuidev's"
has "⚠ ~/.claude/settings.json: the Stop hook runs ~/bin/gone.py, which is not there (not tuidev's"
has "⚠ ~/.claude/settings.json: the Stop hook runs ~/bin/not-exec, which is not executable (not tuidev's"
has "⚠ ~/.claude/settings.json: the statusLine hook runs /opt/nowhere/status, which is not there"
has "⚠ ~/.codex/hooks.json: the SessionStart hook runs /opt/codex-hook.sh, which is not there (not tuidev's"
has "⚠ ~/.codex/config.toml: the notify hook runs /opt/notifier, which is not there (not tuidev's"
hasnt "ok-hook" "a hook whose program is there"; hasnt "/ignored" "notify under another table"
out="$(hc --fix)"
has "✓ notify.sh: ~/.local/bin/notify.sh is the one in these files"; hasnt "✗ ~/.claude/settings.json" "the tuidev hook after --fix"
has "the Stop hook runs ~/bin/their-hook.sh, which is not there (not tuidev's"
[[ "$(cksum "$H/.claude/settings.json" "$H/.codex/hooks.json" "$H/.codex/config.toml")" == "$before" ]] || fail "--fix edited a hooks file"
out="$(NOJQ=1 hc)"; has "hooks: skipped: jq is not installed"; hasnt "Notification hook"
pass "hooks: tuidev's missing program fails and --fix reinstalls it; others warn as not tuidev's and are never edited; no jq is a skip"
else
    echo "SKIP: hooks (no jq on this machine)"
fi

# 5. The manifest against the disk.
rt_fixture monitoring
printf '<plist/>\n' > "$H/Library/LaunchAgents/dev.tuidev.memguard.plist"; printf '<plist/>\n' > "$H/Library/LaunchAgents/dev.tuidev.mine.plist"
: > "$RT.loaded.dev.tuidev.memguard"
{ echo "file $H/.config/gone.conf"; echo "block tuidev-x $H/.gone-rc"; echo "file $H/.local/bin/tuidev"
  echo "file $H/.local/lib/tuidev/agents/cli.sh"; } >> "$HS/manifest"
rm "$H/.local/lib/tuidev/agents/cli.sh"
out="$(hc)"
has "⚠ the manifest records files that are gone: ~/.config/gone.conf, ~/.gone-rc (uninstall skips them"
has "✗ gone, though tuidev installed them: ~/.local/lib/tuidev/agents/cli.sh (fix: tuidev update --configs; tuidev check --fix does it)"
has "⚠ not in the manifest, so tuidev uninstall would leave them: ~/Library/LaunchAgents/dev.tuidev.memguard.plist, ~/Library/LaunchAgents/dev.tuidev.mine.plist"
cp "$HS/manifest" "$tmp/manifest.before"
out="$(hc --fix --dry-run)"
has "[DRY RUN] tuidev_manifest_drop file $H/.config/gone.conf"; has "[DRY RUN] tuidev_manifest_record file $H/Library/LaunchAgents/dev.tuidev.memguard.plist"
cmp -s "$HS/manifest" "$tmp/manifest.before" || fail "--fix --dry-run changed the manifest"
out="$(hc --fix)"
! grep -q "gone.conf\|\.gone-rc" "$HS/manifest" || fail "--fix kept the records of files that are gone"
grep -qxF "file $H/.local/bin/tuidev" "$HS/manifest" || fail "--fix dropped a record whose file is there"
grep -qxF "file $H/Library/LaunchAgents/dev.tuidev.memguard.plist" "$HS/manifest" || fail "--fix did not record tuidev's job"
! grep -q "dev.tuidev.mine" "$HS/manifest" || fail "--fix recorded a plist tuidev does not ship"
has "dev.tuidev.mine.plist is not a job tuidev ships: left as it is"; [[ -f "$H/Library/LaunchAgents/dev.tuidev.mine.plist" ]] || fail "a plist that is not tuidev's was touched"
cmp -s "$H/.local/lib/tuidev/agents/cli.sh" "$REPO/lib/agents/cli.sh" || fail "--fix did not put the module back"
hasnt "gone, though tuidev installed them" "after --fix"
pass "manifest: gone records warn and --fix drops them; tuidev's own files come back; unrecorded jobs tuidev ships get recorded, others are left alone"

# 6. agents doctor's rows are counted here: one implementation.
rt_fixture monitoring
mkdir -p "$tmp/dr"
cat > "$tmp/dr/agents" <<'EOF'
#!/bin/bash
echo "agents $*" >> "$RTM.calls"
case "$1" in
    doctor) [[ -z "${DOCTOR_RC:-}" ]] || exit "$DOCTOR_RC"
            case " $* " in *" --fix "*) printf 'did\tmemory guard\tagents mem restart\t\nok\tmemory guard\ton (pid 9)\t\n'; exit 0 ;; esac
            printf 'ok\tsampler\tlast sample at 10:00 (5s ago)\t\nfail\tmemory guard\tinstalled, but no guard runs\tagents mem restart\nskip\tps\tthe process table cannot be read here\t\n'; exit 1 ;;
esac
exit 0
EOF
chmod +x "$tmp/dr/agents"
out="$(PRE="$tmp/dr" hc)"
has "✓ sampler: last sample at 10:00 (5s ago)"; has "ℹ ps: skipped: the process table cannot be read here"
has "✗ memory guard: installed, but no guard runs (fix: agents mem restart; tuidev check --fix does it)"; has "rc=1"
grep -q "agents doctor --tsv$" "$RT.calls" || fail "doctor was not asked for its rows: $(cat "$RT.calls")"
out="$(PRE="$tmp/dr" hc --fix)"; has "--fix: agents mem restart (memory guard)"; has "✓ memory guard: on (pid 9)"
grep -q "agents doctor --tsv --fix$" "$RT.calls" || fail "doctor --fix: $(cat "$RT.calls")"
out="$(PRE="$tmp/dr" hc --fix --dry-run)"; grep -q "agents doctor --tsv --fix -n$" "$RT.calls" || fail "doctor --fix -n: $(cat "$RT.calls")"
out="$(DOCTOR_RC=2 PRE="$tmp/dr" hc)"; has "agents doctor: skipped: this agents has no doctor"
out="$(DOCTOR_RC=1 PRE="$tmp/dr" hc)"; has "⚠ agents doctor did not run (exit 1; agents --help says why)"
pass "agents doctor's rows: counted as the check's own, --fix and -n passed on, an agents without doctor is a skip"

echo
echo "All health check tests passed."
