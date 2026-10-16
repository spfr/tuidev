#!/bin/bash
# Unit tests for scripts/notify.sh, the notification helper the Claude Code
# hooks (and, opt-in, Codex) call.
# Run: bash scripts/lib/test_notify.sh  -> exit 0 on pass.
#
# Stub uname, terminal-notifier, osascript, agents, herdr, tmux, notify-send,
# curl, ioreg and lsappinfo on PATH record their arguments, one per line:
# nothing is shown, and this Mac's own lock, idle time and front app never
# reach a test (ioreg and lsappinfo say "away" unless a test sets them).
# The timeout and escaping helpers notify.sh shares with lib/agents (it
# stands alone, so it carries its own copies) are run side by side. The last
# test runs the real agents under a fake claude process; it is skipped where
# ps can't report start times (a sandbox, BusyBox).

# Stubs are called indirectly; tests change settings inside ( … ).
# shellcheck disable=SC2016,SC2030,SC2031,SC2317,SC2329
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
NOTIFY="$REPO_DIR/scripts/notify.sh"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/tuidev-test.XXXXXX")"
live_pid=""
cleanup() {
    [[ -z "$live_pid" ]] || kill "$live_pid" 2>/dev/null || true
    rm -rf "$tmp"
}
trap cleanup EXIT
mkdir -p "$tmp/bin" "$tmp/log" "$tmp/home"
# Only what a test sets reaches notify.sh (run passes these through).
unset TMUX HERDR_ENV SSH_CONNECTION NTFY_URL TN TN_FAIL TN_HANG AGENTS_OUT STUB_UNAME \
    STUB_LOCKED STUB_IDLE STUB_FRONT STUB_PROBE_FAIL TUIDEV_NOTIFY_BANNER TUIDEV_NOTIFY_PRESENT_IDLE STDIN CLAUDE_PROJECT_DIR \
    AGENTS_DATA_DIR XDG_STATE_HOME AGENTS_HISTORY AGENTS_CONF

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "PASS: $1"; }

# stub NAME BODY — a program that logs its arguments to log/NAME, then runs BODY.
stub() {
    printf '#!/bin/bash\nprintf "%%s\\n" "$@" > "%s/log/%s"\n%s\n' "$tmp" "$1" "$2" > "$tmp/bin/$1"
    chmod +x "$tmp/bin/$1"
}
stub uname 'echo "${STUB_UNAME:-Darwin}"'
stub terminal-notifier '[[ -z "$TN_HANG" ]] || exec sleep 30; [[ -z "$TN_FAIL" ]]'
stub osascript 'exit 0'
stub agents 'printf "%s" "${AGENTS_OUT-}"; [[ -n "${AGENTS_OUT-}" ]]'
stub herdr 'exit 0'
stub tmux 'exit 0'
stub notify-send 'exit 0'
stub curl 'exit 0'
# ioreg: the lock state (STUB_LOCKED, default No) and the seconds since the
# last input (STUB_IDLE, default 600: away). lsappinfo: the app in front
# (STUB_FRONT, a bundle id). STUB_PROBE_FAIL makes both fail.
stub ioreg '[[ -z "$STUB_PROBE_FAIL" ]] || exit 1
case "$*" in
    *IOConsoleLocked*) echo "  \"IOConsoleLocked\" = ${STUB_LOCKED:-No}" ;;
    *HIDIdleTime*) echo "    | |   \"HIDIdleTime\" = ${STUB_IDLE:-600}000000000" ;;
esac'
stub lsappinfo '[[ -z "$STUB_PROBE_FAIL" ]] || exit 1
case "$1" in
    front) echo "ASN:0x0-0x1a2b:" ;;
    info) printf "%s\n" "[ NULL ]  ASN:0x0-0x1a2b: (in front) " "    bundleID=\"${STUB_FRONT:-com.mitchellh.ghostty}\"" ;;
esac'
JQ="$(command -v jq || true)"
[[ -z "$JQ" ]] || ln -s "$JQ" "$tmp/bin/jq"

TOK="4242@Wed_Oct_14_08:00:00_2026"
# What agents root-of prints: the session, its app, the app's bundle id and
# the command a click runs (agents builds and quotes it: posted as is).
CLICK="'$tmp/bin/agents' jump --notify $TOK"
GHOSTTY="$TOK"$'\t'Ghostty$'\t'com.mitchellh.ghostty$'\t'"$CLICK"

# run [ARGS...] — notify.sh in a clean environment (only the stubs and the
# system's tools on PATH); its stdout and stderr go to $tmp/out, its exit
# status to $tmp/rc. VAR=value pairs from the caller's environment pass
# through env.
run() {
    rm -f "$tmp/log/"*
    set +e
    env -i HOME="$tmp/home" PATH="$tmp/bin:/usr/bin:/bin" \
        TUIDEV_TERMINAL_NOTIFIER="${TN-$tmp/bin/terminal-notifier}" \
        ${AGENTS_OUT+AGENTS_OUT="$AGENTS_OUT"} ${STUB_UNAME:+STUB_UNAME="$STUB_UNAME"} \
        ${TN_FAIL:+TN_FAIL=1} ${TN_HANG:+TN_HANG=1} ${TMUX:+TMUX="$TMUX"} ${HERDR_ENV:+HERDR_ENV="$HERDR_ENV"} \
        ${SSH_CONNECTION:+SSH_CONNECTION="$SSH_CONNECTION"} ${NTFY_URL:+NTFY_URL="$NTFY_URL"} \
        ${STUB_LOCKED:+STUB_LOCKED="$STUB_LOCKED"} ${STUB_IDLE:+STUB_IDLE="$STUB_IDLE"} \
        ${STUB_FRONT:+STUB_FRONT="$STUB_FRONT"} ${STUB_PROBE_FAIL:+STUB_PROBE_FAIL=1} \
        ${TUIDEV_NOTIFY_BANNER:+TUIDEV_NOTIFY_BANNER="$TUIDEV_NOTIFY_BANNER"} \
        ${TUIDEV_NOTIFY_PRESENT_IDLE:+TUIDEV_NOTIFY_PRESENT_IDLE="$TUIDEV_NOTIFY_PRESENT_IDLE"} \
        ${CLAUDE_PROJECT_DIR:+CLAUDE_PROJECT_DIR="$CLAUDE_PROJECT_DIR"} \
        ${AGENTS_DATA_DIR:+AGENTS_DATA_DIR="$AGENTS_DATA_DIR"} ${XDG_STATE_HOME:+XDG_STATE_HOME="$XDG_STATE_HOME"} \
        ${AGENTS_HISTORY+AGENTS_HISTORY="$AGENTS_HISTORY"} ${AGENTS_CONF:+AGENTS_CONF="$AGENTS_CONF"} \
        /bin/bash "$NOTIFY" "$@" < "${STDIN:-/dev/null}" > "$tmp/out" 2>&1
    echo $? > "$tmp/rc"
    set -e
}
log() { cat "$tmp/log/$1" 2>/dev/null; }
called() { [[ -f "$tmp/log/$1" ]]; }
quiet() { [[ "$(cat "$tmp/rc")" == 0 && ! -s "$tmp/out" ]] || fail "$1: rc $(cat "$tmp/rc"), output: $(cat "$tmp/out")"; }
# arg OPTION — the value terminal-notifier got for OPTION.
arg() { awk -v o="$1" 'f { print; exit } $0 == o { f = 1 }' "$tmp/log/terminal-notifier"; }

# --- A clickable banner -----------------------------------------------------------------
AGENTS_OUT="$GHOSTTY" run "Claude Code" "Needs your approval" "Permission"
quiet "clickable banner"
[[ "$(log agents)" =~ ^root-of$'\n'[0-9]+$ ]] || fail "agents root-of not asked about this process: $(log agents)"
[[ "$(arg -title)" == "Claude Code" && "$(arg -message)" == "Needs your approval" && "$(arg -subtitle)" == Permission && "$(arg -sound)" == Glass ]] \
    || fail "banner fields: $(log terminal-notifier)"
[[ "$(arg -group)" == "agents-$TOK" ]] || fail "group: $(arg -group)"
[[ "$(arg -activate)" == com.mitchellh.ghostty ]] || fail "activate: $(arg -activate)"
[[ "$(arg -execute)" == "$CLICK" ]] || fail "execute: $(arg -execute)"
! called osascript || fail "osascript as well as terminal-notifier"
pass "a session's banner: clickable (agents' own jump command), activates its terminal app, one per session (group)"

# Titles and messages are argv, never shell: the click runs only the jump.
AGENTS_OUT="$GHOSTTY" run "Claude 'x' \"y\" \$(touch $tmp/pwned) \`touch $tmp/pwned\`" "a; touch $tmp/pwned" "\$HOME"
quiet "hostile title"
[[ "$(arg -title)" == "Claude 'x' \"y\" \$(touch $tmp/pwned) \`touch $tmp/pwned\`" && "$(arg -message)" == "a; touch $tmp/pwned" && "$(arg -subtitle)" == "\$HOME" ]] \
    || fail "hostile title not passed as is: $(log terminal-notifier)"
cmd="$(arg -execute)"
[[ "$cmd" != *pwned* && "$cmd" != *Claude* && "$cmd" != *HOME* ]] || fail "a title reached the execute string: $cmd"
rm -f "$tmp/log/agents"
/bin/sh -c "$cmd" || true   # the stub fails: it has nothing to print
[[ "$(log agents)" == $'jump\n--notify\n'"$TOK" && ! -e "$tmp/pwned" ]] || fail "the click: $(log agents)"
pass "titles, messages and subtitles with quotes, \$() and backticks reach terminal-notifier as argv, never the click's shell"

# What agents leaves unknown ("-") is left out.
AGENTS_OUT="$TOK"$'\t-\t-\t'"$CLICK" run "T" "M"
[[ "$(arg -execute)" == "$CLICK" && "$(log terminal-notifier)" != *-activate* ]] || fail "no app: $(log terminal-notifier)"
AGENTS_OUT="$TOK"$'\tGhostty\tcom.mitchellh.ghostty\t-' run "T" "M"
[[ "$(log terminal-notifier)" != *-execute* && "$(log terminal-notifier)" != *-group* ]] || fail "no click command: $(log terminal-notifier)"
pass "no app: no -activate; no click command: a plain banner"

# terminal-notifier reads a value starting with [ ( { < or a quote as a
# property list (and drops the banner), one starting with - as an option.
AGENTS_OUT="$GHOSTTY" run "[Claude] x" '"quoted" y' "-sub"
[[ "$(arg -title)" == '\[Claude] x' && "$(arg -message)" == '\"quoted" y' && "$(arg -subtitle)" == ' -sub' ]] \
    || fail "not escaped for terminal-notifier: $(log terminal-notifier)"
[[ "$(log osascript)" == "" ]] || fail "osascript too"
TN="" run "[Claude] x" "(m" "{s"
[[ "$(log osascript)" == *$'end run\n[Claude] x\n(m\n{s\nGlass' ]] || fail "osascript's text escaped: $(log osascript)"
pass "a title, message or subtitle starting with [ ( { < or a quote is escaped for terminal-notifier (not for osascript), one starting with - too"

# No agent above this process: a plain banner.
AGENTS_OUT="" run "T" "M"
quiet "no agent"
[[ "$(arg -message)" == M && "$(log terminal-notifier)" != *-execute* && "$(log terminal-notifier)" != *-group* && "$(log terminal-notifier)" != *-activate* ]] \
    || fail "no agent ancestor: $(log terminal-notifier)"
# No agents command (the monitoring pack is not installed): a plain banner.
rm "$tmp/bin/agents"
AGENTS_OUT="$GHOSTTY" run "T" "M"
quiet "no agents"
[[ "$(arg -message)" == M && "$(log terminal-notifier)" != *-execute* ]] || fail "without agents: $(log terminal-notifier)"
# ... unless the pack put it in ~/.local/bin, which a hook's PATH may lack.
mkdir -p "$tmp/home/.local/bin"
printf '#!/bin/bash\nprintf "%%s" "$AGENTS_OUT"\n' > "$tmp/home/.local/bin/agents"; chmod +x "$tmp/home/.local/bin/agents"
AGENTS_OUT="$GHOSTTY" run "T" "M"
[[ "$(arg -execute)" == "$CLICK" ]] || fail "agents in HOME/.local/bin: $(log terminal-notifier)"
rm "$tmp/home/.local/bin/agents"
stub agents 'printf "%s" "${AGENTS_OUT-}"; [[ -n "${AGENTS_OUT-}" ]]'
pass "no agent session, or no agents command: a plain banner; agents is found in ~/.local/bin too"

# --- Without terminal-notifier ----------------------------------------------------------
TN="" AGENTS_OUT="$GHOSTTY" run "Claude Code" "Waiting \"for\" you" "Idle"
quiet "osascript"
! called terminal-notifier || fail "terminal-notifier used though absent"
[[ "$(log osascript)" == *$'end run\nClaude Code\nWaiting "for" you\nIdle\nGlass' ]] || fail "osascript argv: $(log osascript)"
! called agents || fail "agents asked though nothing can click"
TN_FAIL=1 AGENTS_OUT="$GHOSTTY" run "T" "M"
quiet "terminal-notifier fails"
[[ "$(log osascript)" == *$'end run\nT\nM\n\nGlass' ]] || fail "no osascript after terminal-notifier failed: $(log osascript)"
pass "without terminal-notifier, or when it fails: osascript's banner, text as argv"

# --- Which channels -----------------------------------------------------------------------
TMUX=/tmp/x,1,0 AGENTS_OUT="$GHOSTTY" run "T" "M" "S"
quiet "tmux on a Mac"
[[ "$(log tmux)" == $'display-message\n-l\n[T] S: M' ]] || fail "tmux message: $(log tmux)"
[[ "$(arg -execute)" == *"jump --notify $TOK" ]] || fail "no clickable banner inside tmux on a Mac: $(log terminal-notifier)"
HERDR_ENV=1 AGENTS_OUT="$GHOSTTY" run "T" "M"
[[ "$(log herdr)" == $'notification\nshow\nT\n--body\nM' ]] || fail "herdr toast: $(log herdr)"
called terminal-notifier || fail "no banner inside Herdr on a Mac"
HERDR_ENV=1 SSH_CONNECTION="10.0.0.1 1 10.0.0.2 22" run "T" "M"
if ! called herdr || called terminal-notifier || called osascript; then fail "a banner on the Mac for a session reached over ssh"; fi
HERDR_ENV=1 SSH_CONNECTION="10.0.0.1 1 10.0.0.2 22" AGENTS_OUT="$TOK"$'\t-\t-\t'"$CLICK" run "T" "M"
if called terminal-notifier || called osascript; then fail "a banner for an ssh session agents finds in no app here"; fi
SSH_CONNECTION="10.0.0.1 1 10.0.0.2 22" run "T" "M"
called terminal-notifier || fail "over ssh with no toast or status line, the Mac's banner is the only channel"
pass "on a Mac, away from it, the banner fires inside Herdr and tmux too (not over ssh, where the toast or status line is enough)"

# --- At the Mac: the toast is the one alert ----------------------------------------------
HERDR_ENV=1 STUB_IDLE=5 AGENTS_OUT="$GHOSTTY" run "T" "M"
quiet "present in Herdr"
if ! called herdr || called terminal-notifier || called osascript; then fail "a banner while at the Mac with Ghostty in front: $(log terminal-notifier)"; fi
TMUX=/tmp/x,1,0 STUB_IDLE=5 AGENTS_OUT="$GHOSTTY" run "T" "M"
if ! called tmux || ! called terminal-notifier; then fail "tmux at the Mac: its status line is silent and brief, the banner stays"; fi
STUB_IDLE=5 AGENTS_OUT="$GHOSTTY" run "T" "M"
called terminal-notifier || fail "a plain Ghostty tab, at the Mac: the banner is its only alert"
pass "at the Mac (unlocked, input within 2 min, the session's terminal in front): inside Herdr, no banner; tmux and a plain tab keep it"

HERDR_ENV=1 STUB_IDLE=5 STUB_FRONT=com.google.Chrome AGENTS_OUT="$GHOSTTY" run "T" "M"
called terminal-notifier || fail "another app in front: no banner"
HERDR_ENV=1 STUB_IDLE=5 STUB_FRONT=com.googlecode.iterm2 AGENTS_OUT="$GHOSTTY" run "T" "M"
called terminal-notifier || fail "another terminal than the session's in front: no banner"
HERDR_ENV=1 STUB_IDLE=5 AGENTS_OUT="" run "T" "M"
called terminal-notifier || fail "the session unknown to agents: no banner"
HERDR_ENV=1 STUB_IDLE=5 AGENTS_OUT="$TOK"$'\t-\t-\t'"$CLICK" run "T" "M"
called terminal-notifier || fail "a Herdr session no client shows (detached): no banner"
HERDR_ENV=1 STUB_IDLE=5 STUB_LOCKED=Yes AGENTS_OUT="$GHOSTTY" run "T" "M"
called terminal-notifier || fail "screen locked: no banner"
HERDR_ENV=1 STUB_IDLE=120 AGENTS_OUT="$GHOSTTY" run "T" "M"
called terminal-notifier || fail "idle 2 min: no banner"
HERDR_ENV=1 STUB_IDLE=5 STUB_PROBE_FAIL=1 AGENTS_OUT="$GHOSTTY" run "T" "M"
called terminal-notifier || fail "a failed probe: no banner"
pass "another app in front, a session agents can't place (detached Herdr), a locked screen, 2 min idle or a failed probe: the banner, as before"

HERDR_ENV=1 STUB_IDLE=5 TUIDEV_NOTIFY_BANNER=always AGENTS_OUT="$GHOSTTY" run "T" "M"
called terminal-notifier || fail "TUIDEV_NOTIFY_BANNER=always: no banner"
HERDR_ENV=1 STUB_IDLE=5 TUIDEV_NOTIFY_PRESENT_IDLE=0 AGENTS_OUT="$GHOSTTY" run "T" "M"
called terminal-notifier || fail "TUIDEV_NOTIFY_PRESENT_IDLE=0: no banner"
HERDR_ENV=1 STUB_IDLE=200 TUIDEV_NOTIFY_PRESENT_IDLE=300 AGENTS_OUT="$GHOSTTY" run "T" "M"
! called terminal-notifier || fail "TUIDEV_NOTIFY_PRESENT_IDLE=300, idle 200 s: a banner"
pass "TUIDEV_NOTIFY_BANNER=always and TUIDEV_NOTIFY_PRESENT_IDLE=0 keep the banner; the idle limit is configurable"

# --- The hook's own message ----------------------------------------------------------------
if [[ -n "$JQ" ]]; then
    printf '%s' '{"hook_event_name":"Notification","notification_type":"permission_prompt","message":"Claude needs your permission to use Bash"}' > "$tmp/hook.json"
    STDIN="$tmp/hook.json" CLAUDE_PROJECT_DIR=/p HERDR_ENV=1 AGENTS_OUT="$GHOSTTY" run "Claude Code" "Needs your approval" "Permission"
    quiet "hook message"
    [[ "$(log herdr)" == $'notification\nshow\nClaude Code\n--body\nPermission: Claude needs your permission to use Bash' ]] || fail "toast body: $(log herdr)"
    [[ "$(arg -message)" == "Claude needs your permission to use Bash" ]] || fail "banner message: $(arg -message)"
    STDIN="$tmp/hook.json" AGENTS_OUT="$GHOSTTY" run "T" "M"
    [[ "$(arg -message)" == M ]] || fail "stdin read outside a Claude Code hook: $(arg -message)"
    printf '%s' '{"message": 42}' > "$tmp/hook.json"
    STDIN="$tmp/hook.json" CLAUDE_PROJECT_DIR=/p AGENTS_OUT="$GHOSTTY" run "T" "M"
    [[ "$(arg -message)" == M ]] || fail "a non-string message: $(arg -message)"
    printf '%s' 'not json "message"' > "$tmp/hook.json"
    STDIN="$tmp/hook.json" CLAUDE_PROJECT_DIR=/p AGENTS_OUT="$GHOSTTY" run "T" "M"
    [[ "$(arg -message)" == M ]] || fail "not JSON: $(arg -message)"
    pass "under a Claude Code hook, its JSON message replaces the fixed one (toast and banner); any other stdin, or anything else, keeps it"
else
    echo "SKIP: no jq: the hook-message test not run"
fi

# A tmux server started over ssh keeps SSH_CONNECTION in its panes after you
# attach at the Mac: agents finding the session in a terminal app here wins.
TMUX=/tmp/x,1,0 SSH_CONNECTION="10.0.0.1 1 10.0.0.2 22" AGENTS_OUT="$GHOSTTY" run "T" "M"
if ! called tmux || [[ "$(arg -execute)" != "$CLICK" ]]; then fail "stale SSH_CONNECTION, attached locally: no banner: $(log terminal-notifier)"; fi
[[ "$(log agents)" =~ ^root-of$'\n'[0-9]+$ ]] || fail "agents asked more than once: $(log agents)"
pass "a session agents finds in a terminal app on this Mac is local, whatever SSH_CONNECTION says (asked once)"

STUB_UNAME=Linux TMUX=/tmp/x,1,0 run "T" "M"
if ! called tmux || called notify-send || called terminal-notifier; then fail "Linux in tmux: tmux only"; fi
STUB_UNAME=Linux run "T" "M" "S"
if [[ "$(log notify-send)" != $'--app-name=T\nT\nS: M' ]] || called terminal-notifier; then fail "Linux desktop: $(log notify-send)"; fi
rm "$tmp/bin/notify-send"
STUB_UNAME=Linux NTFY_URL=https://ntfy.example/topic run "T" "M"
[[ "$(log curl)" == *"Title: T"$'\n--data-raw\nM\n'"https://ntfy.example/topic" ]] || fail "ntfy: $(log curl)"
stub notify-send 'exit 0'
pass "Linux unchanged: Herdr or tmux, else notify-send, else ntfy"

# --- Silent, exit 0, bounded --------------------------------------------------------------
for s in terminal-notifier osascript agents herdr tmux notify-send curl; do
    stub "$s" 'echo "noise on stdout"; echo "noise on stderr" >&2; exit 3'
done
for u in Darwin Linux; do
    STUB_UNAME=$u TMUX=/tmp/x,1,0 HERDR_ENV=1 NTFY_URL=https://ntfy.example/t run "T" "M"
    quiet "everything fails ($u)"
done
run; quiet "no arguments"; ! called terminal-notifier || fail "notified with no message"
run "T"; quiet "no message"
stub terminal-notifier '[[ -z "$TN_HANG" ]] || exec sleep 30; [[ -z "$TN_FAIL" ]]'
stub osascript 'exit 0'
stub agents 'printf "%s" "${AGENTS_OUT-}"; [[ -n "${AGENTS_OUT-}" ]]'
start=$SECONDS
TN_HANG=1 AGENTS_OUT="$GHOSTTY" run "T" "M"
quiet "terminal-notifier hangs"
[[ $((SECONDS - start)) -le 8 ]] || fail "a hung terminal-notifier held the hook $((SECONDS - start))s"
! called osascript || fail "osascript after terminal-notifier timed out: a second banner"
pass "prints nothing and exits 0 whatever fails; a hung notifier is cut off after 5 s, with no second banner"

# --- The notification log (notify.tsv, for agents report --view waits) -------------------
for s in herdr tmux notify-send curl; do stub "$s" 'exit 0'; done   # working again
state="$tmp/home/.local/state"
ntsv="$state/tuidev/agents/notify.tsv"
# nlast — the log's last line; nlines — how many it has.
nlast() { tail -1 "$ntsv" 2>/dev/null; }
nlines() { if [[ -f "$ntsv" ]]; then grep -c . "$ntsv"; else echo 0; fi; }
CLAUDE_PROJECT_DIR=/Users/NAME/code/sentula AGENTS_OUT="$GHOSTTY" run "Claude Code" "Needs your approval" "Permission"
quiet "no data directory"
[[ ! -e "$state" ]] || fail "notify.sh created $(find "$state" | tr '\n' ' ')without the monitoring pack's data directory"
mkdir -p "$state/tuidev/agents"
before=$(date +%s)
CLAUDE_PROJECT_DIR=/Users/NAME/code/sentula AGENTS_OUT="$GHOSTTY" run "Claude Code" "Needs your approval" "Permission"
quiet "a logged notification"
IFS=$'\t' read -r ts tok proj kind chans skip extra <<<"$(nlast)"
[[ "$ts" =~ ^[0-9]+$ && $ts -ge $before && $ts -le $(( $(date +%s) + 1 )) ]] || fail "log epoch: $(nlast)"
[[ "$tok|$proj|$kind|$chans|$skip|${extra:-}" == "$TOK|sentula|Permission|banner|-|" ]] || fail "log line: $(nlast)"
if [[ "$(uname)" == Darwin ]]; then m="$(stat -f %Lp "$ntsv")"; else m="$(stat -c %a "$ntsv")"; fi
[[ "$m" == 600 ]] || fail "notify.tsv mode $m"
HERDR_ENV=1 STUB_IDLE=5 AGENTS_OUT="$GHOSTTY" run "Claude Code" "M" "Idle"
[[ "$(nlast | cut -f2,4-6)" == "$TOK"$'\tIdle\therdr\tpresent' ]] || fail "at the Mac in Herdr: $(nlast)"
HERDR_ENV=1 SSH_CONNECTION="10.0.0.1 1 10.0.0.2 22" run "T" "M"
[[ "$(nlast | cut -f2,4-6)" == $'-\t-\therdr\tremote' ]] || fail "over ssh, no session, no subtitle: $(nlast)"
TMUX=/tmp/x,1,0 AGENTS_OUT="$GHOSTTY" run "T" "M" "Agent Teams"
[[ "$(nlast | cut -f4-6)" == $'Agent Teams\ttmux,banner\t-' ]] || fail "tmux and a banner: $(nlast)"
TN="" run "T" "M"
[[ "$(nlast | cut -f5)" == osascript ]] || fail "osascript: $(nlast)"
STUB_UNAME=Linux run "T" "M"
[[ "$(nlast | cut -f5)" == notify-send ]] || fail "Linux desktop: $(nlast)"
stub osascript 'exit 3'; rm "$tmp/bin/notify-send"
TN_FAIL=1 run "T" "M"
[[ "$(nlast | cut -f5,6)" == $'none\t-' ]] || fail "nothing worked: $(nlast)"
stub osascript 'exit 0'; stub notify-send 'exit 0'
[[ "$(nlines)" == 7 ]] || fail "one line per notification: $(nlines)"
pass "notify.tsv: one line per notification (session, project, kind, channels, why the banner was skipped), only once the data directory exists"

CLAUDE_PROJECT_DIR=$'/Users/NAME/code/repo/.claude/worktrees/feat\tx' run "T" "M" $'Perm\tis\nsion'
IFS=$'\t' read -r _ _ proj kind chans skip extra <<<"$(nlast)"
[[ "$proj|$kind|${extra:-}" == "repo/feat x|Perm is sion|" && "$(grep -c . "$ntsv")" == 8 ]] || fail "control characters in a field: $(tail -2 "$ntsv")"
CLAUDE_PROJECT_DIR=/Users/NAME/code/app/ run "T" "M" "$(printf 'x%.0s' $(seq 1 120))"
[[ "$(nlast | cut -f3)" == app && "$(nlast | cut -f4)" == "$(printf 'x%.0s' $(seq 1 80))" ]] || fail "a long subtitle, a trailing slash: $(nlast)"
run "T" "M" "   "
[[ "$(nlast | cut -f4)" == - ]] || fail "a blank subtitle: $(nlast)"
run; run "T"
[[ "$(nlines)" == 10 ]] || fail "logged a call that showed nothing"
pass "notify.tsv fields: control characters as spaces, at most 80 characters, blank as -"

AGENTS_HISTORY=0 run "T" "M"
mkdir -p "$tmp/home/.config"
printf '# history\n  AGENTS_HISTORY="0"  # off\n' > "$tmp/home/.config/agents.conf"
run "T" "M"
[[ "$(nlines)" == 10 ]] || fail "logged with AGENTS_HISTORY=0: $(nlast)"
AGENTS_HISTORY=1 run "T" "M"
[[ "$(nlines)" == 11 ]] || fail "the environment's AGENTS_HISTORY=1 does not win over agents.conf"
printf 'AGENTS_HISTORY=1\nAGENTS_HISTORY=0\n' > "$tmp/conf"
AGENTS_CONF="$tmp/conf" run "T" "M"
[[ "$(nlines)" == 12 ]] || fail "AGENTS_CONF: the first AGENTS_HISTORY line wins, as agents reads it"
rm "$tmp/home/.config/agents.conf"
mkdir -p "$tmp/xdg/tuidev/agents" "$tmp/own"
XDG_STATE_HOME="$tmp/xdg" run "T" "M"
AGENTS_DATA_DIR="$tmp/own" run "T" "M"
[[ "$(nlines)" == 12 && -s "$tmp/xdg/tuidev/agents/notify.tsv" && -s "$tmp/own/notify.tsv" ]] || fail "XDG_STATE_HOME or AGENTS_DATA_DIR not followed"
chmod 500 "$state/tuidev/agents"
run "T" "M"; quiet "a data directory it can't write"
chmod 700 "$state/tuidev/agents"
rm -rf "$state" "$tmp/xdg" "$tmp/own"
pass "notify.tsv: off with AGENTS_HISTORY=0 (environment, then agents.conf); XDG_STATE_HOME and AGENTS_DATA_DIR as agents resolves them; silent when it can't write"

# --- The helpers notify.sh shares with lib/agents -----------------------------------------
# helper FILE NAME — define the function NAME as FILE has it.
helper() {
    local prog="/^$2() {/,/^}/p"   # a variable: bash 3.2 misparses the braces inside "$( )"
    eval "$(sed -n "$prog" "$1")"
    declare -F "$2" >/dev/null || fail "no $2 in $1"
}
helper "$NOTIFY" with_timeout
helper "$NOTIFY" tn_text
helper "$REPO_DIR/lib/agents/util.sh" _agents_timeout
helper "$REPO_DIR/lib/agents/notify.sh" _agents_tn_text
mkdir -p "$tmp/sleep"
# shellcheck disable=SC2016  # the stub's own $$ and $@
printf '#!/bin/bash\necho $$ >> "%s"\nexec /bin/sleep "$@"\n' "$tmp/sleep.pids" > "$tmp/sleep/sleep"
chmod +x "$tmp/sleep/sleep"
gone() { local _; for _ in $(seq 40); do kill -0 "$1" 2>/dev/null || return 0; /bin/sleep 0.05; done; return 1; }
for to in with_timeout _agents_timeout; do
    # A grandchild (here a sleep a shell started) holds the $( ) pipe open:
    # it is killed with the rest, and the timeout says 124.
    start=$SECONDS; rc=0
    out="$("$to" 1 bash -c 'echo started; sleep 6 & wait')" || rc=$?
    [[ $rc == 124 && "$out" == started && $((SECONDS - start)) -le 3 ]] \
        || fail "$to: a grandchild outlived the timeout: rc $rc, '$out', $((SECONDS - start)) s"
    # A command that ends first (once the watcher's sleep runs) takes that
    # sleep with it.
    : > "$tmp/sleep.pids"; rc=0
    ( PATH="$tmp/sleep:$PATH"; "$to" 30 bash -c 'for _ in $(seq 100); do [ -s "$1" ] && break; /bin/sleep 0.05; done
        echo out; echo err >&2; exit 7' _ "$tmp/sleep.pids" ) > "$tmp/to.out" 2>&1 || rc=$?
    [[ $rc == 7 && "$(cat "$tmp/to.out")" == $'out\nerr' ]] || fail "$to: status or output: rc $rc, $(cat "$tmp/to.out")"
    pid="$(head -1 "$tmp/sleep.pids")"
    if [[ -z "$pid" ]] || ! gone "$pid"; then fail "$to: the watcher's sleep ($pid) outlived the command"; fi
    # Killed: 124, with nothing from bash about it.
    rc=0; out="$("$to" 1 sleep 5 2>&1)" || rc=$?
    [[ $rc == 124 && -z "$out" ]] || fail "$to: a killed command: rc $rc, '$out'"
done
pass "the timeout (notify.sh's and lib/agents'): kills grandchildren, takes its watcher's sleep along, 124 when it fired"
for m in '[x' '(x' '{x' '<x' '"x' "'x" '-x' 'x [y' '' 'plain'; do
    [[ "$(tn_text "$m")" == "$(_agents_tn_text "$m")" ]] || fail "notify.sh and lib/agents escape '$m' differently"
done
pass "notify.sh and lib/agents escape terminal-notifier text the same way"
helper "$NOTIFY" project_of
for d in /Users/NAME/code/app /Users/NAME/code/app/ /x/repo/.claude/worktrees/feat /x/repo/.claude/worktrees/feat/sub "$tmp/home" / ""; do
    want="$(HOME="$tmp/home" AGENTS_CONF=/nonexistent bash -c '. "$1"; agents_project "$2"' _ "$REPO_DIR/bin/agents" "$d")"
    [[ "$(HOME="$tmp/home" project_of "$d")" == "$want" ]] || fail "project of '$d': $(HOME="$tmp/home" project_of "$d"), agents says $want"
done
pass "notify.sh names a project as agents does (a worktree as REPO/NAME, \$HOME as ~)"

# --- Live: the real agents under a fake claude -------------------------------------------
if ps -o lstart= -p $$ >/dev/null 2>&1; then
    ln -sf "$REPO_DIR/bin/agents" "$tmp/bin/agents"
    stub terminal-notifier 'exit 0'
    rm -f "$tmp/log/"*
    # claude -> sh -c (the hook's shell) -> notify.sh, as Claude Code runs it.
    # Started twice removed, so it is no child of this test (which may itself
    # run under a claude: the outermost agent is the session).
    ( ( exec -a claude /bin/bash -c '
        echo $$ > "$5"
        env -i HOME="$1" PATH="$2:/usr/bin:/bin" TUIDEV_TERMINAL_NOTIFIER="$2/terminal-notifier" AGENTS_CONF=/nonexistent \
            /bin/sh -c "\"$3\" \"Claude Code\" \"Needs your approval\" Permission; :"
        echo done > "$4"
        sleep 30' _ "$tmp/home" "$tmp/bin" "$NOTIFY" "$tmp/live.done" "$tmp/live.pid" ) </dev/null >/dev/null 2>&1 & )
    for _ in $(seq 100); do [[ -s "$tmp/live.done" ]] && break; sleep 0.1; done
    live_pid="$(cat "$tmp/live.pid" 2>/dev/null)"
    [[ -s "$tmp/live.done" ]] || fail "live: notify.sh did not finish"
    start="$(LC_ALL=C ps -o lstart= -p "$live_pid" | awk '{ print $1 "_" $2 "_" $3 "_" $4 "_" $5 }')"
    [[ "$(arg -execute)" == "PATH='$tmp/bin:/usr/bin:/bin' '"*"/agents' jump --notify $live_pid@$start" && "$(arg -group)" == "agents-$live_pid@$start" ]] \
        || fail "live: the banner does not jump to the fake claude $live_pid@$start: $(log terminal-notifier)"
    kill "$live_pid" 2>/dev/null || true; live_pid=""
    pass "live: under a fake claude, through the hook's shell, the banner jumps to that claude's PID@START"
else
    echo "SKIP: ps can't report start times here (sandbox? BusyBox?): live notify test not run"
fi

echo "All notify tests passed."
