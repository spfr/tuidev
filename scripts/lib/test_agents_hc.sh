#!/bin/bash
# Unit tests for lib/agents/hc.sh (`agents hc`): agents hosted in herdr-core
# so Herdr's phone app lists them, the core kept in the desktop login, and
# each status herdr-core has reported to Herdr for the pane.
# Run: bash scripts/lib/test_agents_hc.sh  -> exit 0 on pass.
#
# No herdr-core and no Herdr: AGENTS_HC_BIN and HERDR_BIN_PATH are stand-ins
# that answer from files in $FAKE and log every call, one argument a line
# after a "--" line, so a test sees exactly what reached each of them.

# Tests change variables inside ( … ) on purpose; the stand-ins are called by
# the code under test.
# shellcheck disable=SC2016,SC2030,SC2031,SC2034,SC2329,SC2317
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq is not installed"; exit 0; }

tmp="$(mktemp -d "${TMPDIR:-/tmp}/tuidev-test.XXXXXX")"
tmp="$(cd "$tmp" && pwd)"   # as cd spells it ($TMPDIR may end in a slash)
trap 'rm -rf "$tmp"' EXIT
for v in XDG_CONFIG_HOME XDG_STATE_HOME XDG_RUNTIME_DIR TUIDEV_STATE_DIR AGENTS_NO_HERDR HC_SOCKET HC_SESSION \
         AGENTS_HC_AUTO HC_TERMINAL_ID HC_TERMINAL_SOCKET CLAUDE_CONFIG_DIR CODEX_HOME HERDR_ENV HERDR_PANE_ID HERDR_TAB_ID HERDR_WORKSPACE_ID HERDR_SOCKET_PATH SSH_CONNECTION SSH_CLIENT SSH_TTY; do
    unset "$v"
done
export HOME="$tmp/home" NO_COLOR=1 TZ=UTC AGENTS_CONF="$tmp/none.conf" AGENTS_DATA_DIR="$tmp/data" AGENTS_RUN_DIR="$tmp/run"
export AGENTS_TESTING=1 FAKE="$tmp/fake"
mkdir -p "$HOME/.config/herdr" "$FAKE" "$AGENTS_RUN_DIR"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "PASS: $1"; }

# The stand-in herdr-core. Switches, files in $FAKE: connect.hang (a core
# that does not answer), events.N (the Nth stream, which then ends: the core
# restarted) else events, events.live (that stream stays open, its pid in
# events.pid), attach.wait (seconds attached), attach.sig (then that signal
# to the attach's process group: a closed pane), start.gui (what a core
# started here says about the desktop login).
cat > "$tmp/herdr-core" <<'EOF'
#!/bin/bash
{ echo "--"; printf '%s\n' "$@"; } >> "$FAKE/hc.calls"
# The Herdr identity the core, and what it runs, would get.
[[ "$1" != server && "$1" != run ]] || env | grep -E '^(HERDR|AGENTS)_' > "$FAKE/$1.env" || true
case "$1" in
    --version) echo "hc 0.1.21" ;;
    connect)   cat >/dev/null
               [[ ! -e "$FAKE/connect.hang" ]] || exec sleep 30
               cat "$FAKE/hello.json" ;;
    ls)        cat "$FAKE/ls.json" ;;
    get)       cat "$FAKE/get.json" 2>/dev/null ;;
    events)    n=$(( $(cat "$FAKE/events.n" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$FAKE/events.n"
               if [[ -e "$FAKE/events.$n" ]]; then cat "$FAKE/events.$n"; exit 0; fi
               cat "$FAKE/events" 2>/dev/null
               [[ ! -e "$FAKE/events.live" ]] || { echo "$$" > "$FAKE/events.pid"; exec sleep 30; } ;;
    attach)    cat "$AGENTS_RUN_DIR"/hc-pane.* > "$FAKE/mark.seen" 2>/dev/null || true
               [[ ! -e "$FAKE/attach.wait" ]] || sleep "$(cat "$FAKE/attach.wait")"
               [[ ! -e "$FAKE/attach.sig" ]] || { kill -"$(cat "$FAKE/attach.sig")" 0; sleep 5; }
               [[ ! -e "$FAKE/attach.rc" ]] || exit "$(cat "$FAKE/attach.rc")" ;;
    server)    [[ ! -e "$FAKE/server.fail" ]] || exit 1
               [[ "$2" != start ]] || echo "{\"result\":{\"login_session\":{\"gui\":$(cat "$FAKE/start.gui" 2>/dev/null || echo true)}}}" > "$FAKE/hello.json" ;;
    run)       [[ ! -e "$FAKE/run.fail" ]] || { echo '{"error":{"message":"name taken"}}'; exit 1; }
               [[ ! -e "$FAKE/run.mute" ]] || { echo '{}'; exit 0; }
               name=""; while [[ $# -gt 0 ]]; do [[ "$1" != --name ]] || name="$2"; shift; done
               if [[ -n "$name" ]]; then printf '{"address":"t3","name":"%s","state":"live"}\n' "$name"
               else echo '{"address":"t3","name":null,"state":"live"}'; fi ;;
esac
EOF
# The stand-in herdr: it only records, and hangs after that with herdr.hang.
cat > "$tmp/herdr" <<'EOF'
#!/bin/bash
{ echo "--"; printf '%s\n' "$@"; } >> "$FAKE/herdr.calls"
[[ ! -e "$FAKE/herdr.hang" ]] || exec sleep 30
EOF
chmod +x "$tmp/herdr-core" "$tmp/herdr"
export AGENTS_HC_BIN="$tmp/herdr-core" HERDR_BIN_PATH="$tmp/herdr"

# shellcheck source=../../bin/agents disable=SC1091
. "$REPO_DIR/bin/agents"

# What the machine is, and whether a core is up, are the test's to say.
MAC=true RUNNING=true
_agents_hc_is_mac() { [[ "$MAC" == true ]]; }
_agents_hc_running() { [[ "$RUNNING" == true ]]; }
_agents_hl_socket() { return 0; }
# Shorter time limits, so a test of one does not take long.
_AGENTS_HC_WAIT=2 _AGENTS_HC_HERDR_WAIT=1 _AGENTS_HC_PAUSE=0.2

LS_ONE='{"terminals":[{"name":"api","state":"live"},{"name":"old","state":"finished"}]}'
reset() {
    rm -f "$AGENTS_RUN_DIR/hc-up.said" "$FAKE"/*.calls "$FAKE"/*.fail "$FAKE"/*.env "$FAKE"/*.hang "$FAKE"/*.mute "$FAKE"/attach.* "$FAKE"/events.* "$FAKE"/start.gui \
          "$FAKE"/agent.*
    echo "$LS_ONE" > "$FAKE/ls.json"
}
hello() { printf '{"result":{"login_session":{"gui":%s}}}\n' "$1" > "$FAKE/hello.json"; }
calls() { tr '\n' ' ' 2>/dev/null < "$FAKE/$1.calls"; }
# The argument after FLAG in each logged call, a line each.
arg() { awk -v f="$2" '$0 == f { getline; print }' "$FAKE/$1.calls" 2>/dev/null; }
reset

# --- the socket a core would listen on ---
# With a runtime dir (a Linux login has /run/user/UID) the state dir is not used.
if [[ -d "/run/user/$(id -u)" ]]; then
    [[ "$(_agents_hc_socket)" == "/run/user/$(id -u)/herdr-core/default.sock" ]] || fail "default socket: $(_agents_hc_socket)"
    [[ "$(HC_SESSION=work _agents_hc_socket)" == "/run/user/$(id -u)/herdr-core/work.sock" ]] || fail "session socket"
else
    [[ "$(_agents_hc_socket)" == "$HOME/.local/state/herdr-core/default/default.sock" ]] || fail "default socket: $(_agents_hc_socket)"
    [[ "$(HC_SESSION=work XDG_STATE_HOME="$tmp/st" _agents_hc_socket)" == "$tmp/st/herdr-core/work/work.sock" ]] || fail "session socket"
fi
[[ "$(HC_SOCKET=/x/y.sock _agents_hc_socket)" == /x/y.sock ]] || fail "HC_SOCKET"
mkdir -p "$tmp/rt"
[[ "$(XDG_RUNTIME_DIR="$tmp/rt" _agents_hc_socket)" == "$tmp/rt/herdr-core/default.sock" ]] || fail "runtime dir socket"
pass "the core's socket follows herdr-core's rules: HC_SOCKET, the runtime dir, the state dir"

# --- a socket a crashed core left behind is not a running core ---
# The kernel's table, as netstat (macOS) and /proc/net/unix (Linux) print it.
mkdir -p "$tmp/state dir"
ln -s "$tmp/state dir" "$tmp/link"
SOCK="$tmp/state dir/default.sock"
REAL="$(cd -P "$tmp/state dir" && pwd -P)/default.sock"
BSD_HEAD=$'Active LOCAL (UNIX) domain sockets\nAddress          Type   Recv-Q Send-Q            Inode             Conn             Refs          Nextref Addr'
bsd_row() { printf '%s stream      0      0 %16s %16s                0                0 %s\n' 1d431880699cda58 "$1" "$2" "$3"; }
(
_agents_hc_unix_table() { printf '%s\n' "$TABLE"; }
listening() { local rc=0; _agents_hc_listening "$1" || rc=$?; echo "$rc"; }
TABLE="$BSD_HEAD"$'\n'"$(bsd_row 6b1720ae02190280 0 "$REAL")"
[[ "$(listening "$SOCK")" == 0 ]] || fail "a bound socket (macOS) was not found: $(listening "$SOCK")"
[[ "$(listening "$tmp/link/default.sock")" == 0 ]] || fail "a socket named through a symlink was not found"
TABLE="$BSD_HEAD"$'\n'"$(bsd_row 0 1dd0a38828874090 "$REAL")"$'\n'"$(bsd_row 6b1720ae02190280 0 "$tmp/other.sock")"
[[ "$(listening "$SOCK")" == 1 ]] || fail "a connection's end, or another socket, counted as the core (macOS)"
TABLE=$'Num       RefCount Protocol Flags    Type St Inode Path\n0000000000000000: 00000002 00000000 00010000 0001 01 22334 '"$REAL"
[[ "$(listening "$SOCK")" == 0 ]] || fail "a listening socket (Linux) was not found"
TABLE=$'Num       RefCount Protocol Flags    Type St Inode Path\n0000000000000000: 00000003 00000000 00000000 0001 03 22335 '"$REAL"
[[ "$(listening "$SOCK")" == 1 ]] || fail "a connected socket (Linux) counted as the core"
TABLE=""
[[ "$(listening "$SOCK")" == 2 ]] || fail "no table (a sandbox) was taken for no core"
)
(. "$REPO_DIR/lib/agents/hc.sh"; HC_SOCKET="$tmp/state dir/none.sock" _agents_hc_running) && fail "no socket file, and a core runs"
pass "a socket file counts only while the kernel says a process has it bound; without the table, the file decides"

# --- status ---
out="$(AGENTS_HC_BIN="$tmp/nope" agents_main hc status 2>&1)" && fail "status without herdr-core succeeded"
[[ "$out" == *"not installed"* && "$out" == *"herdr.dev/core"* ]] || fail "no herdr-core: $out"
pass "without herdr-core it says where the installer is, and runs nothing"

reset; RUNNING=false
out="$(agents_main hc status 2>&1)" && fail "status with no core succeeded"
[[ "$out" == *"not running"* ]] || fail "not running: $out"
[[ "$(calls hc)" != *connect* ]] || fail "status of a core that is down talked to it (that starts one)"
pass "a core that is down is reported without starting it"

reset; RUNNING=true; hello true
out="$(agents_main hc status 2>&1)" || fail "status of a good core failed: $out"
[[ "$out" == *"0.1.21: running, 1 live"* && "$out" == *"desktop login"* ]] || fail "good core: $out"
hello false
out="$(agents_main hc status 2>&1)" && fail "a headless core on macOS passed"
[[ "$out" == *"started over SSH"* && "$out" == *"up --restart"* ]] || fail "headless core: $out"
out="$(MAC=false; agents_main hc status 2>&1)" || fail "a core that is not in a desktop login failed off macOS: $out"
pass "status says when a macOS core runs outside the desktop login, and how to fix it"

reset; hello true; touch "$FAKE/connect.hang"
t0=$SECONDS
out="$(agents_main hc status 2>&1)" && fail "status of a core that does not answer passed"
[[ $((SECONDS - t0)) -le $((_AGENTS_HC_WAIT + 2)) ]] || fail "status waited $((SECONDS - t0)) s on a core that does not answer"
[[ "$out" == *"did not answer within $_AGENTS_HC_WAIT s"* ]] || fail "no answer: $out"
[[ "$(calls hc)" != *"-- ls"* ]] || fail "status asked more of a core that did not answer: $(calls hc)"
t0=$SECONDS
out="$(agents_main hc up -q 2>&1)" && fail "up passed a core that does not answer"
[[ $((SECONDS - t0)) -le $((_AGENTS_HC_WAIT + 2)) && "$out" == *"did not answer"* ]] || fail "up, no answer: $out"
[[ "$(calls hc)" != *server* ]] || fail "up touched a core that did not answer: $(calls hc)"
pass "a core that does not answer holds status and up for $_AGENTS_HC_WAIT s at most"

# --- up ---
reset; hello true
out="$(agents_main hc up 2>&1)" || fail "up with a good core failed: $out"
[[ "$(calls hc)" != *server* ]] || fail "up touched a core that was fine: $(calls hc)"
reset; hello false
out="$(agents_main hc up 2>&1)" && fail "up left a headless core without saying so"
[[ "$out" == *"--restart"* && "$out" == *"1 live"* ]] || fail "headless up: $out"
[[ "$(calls hc)" != *"server stop"* ]] || fail "up stopped a core without --restart"
out="$(agents_main hc up --restart 2>&1)" || fail "up --restart failed: $out"
[[ "$(calls hc)" == *"server stop"*"server start"* ]] || fail "up --restart: $(calls hc)"
reset; RUNNING=false; hello true
agents_main hc up -q >"$tmp/out" 2>&1 || fail "up with no core failed: $(cat "$tmp/out")"
[[ ! -s "$tmp/out" && "$(calls hc)" == *"server start"* && "$(calls hc)" != *"server stop"* ]] || fail "up, no core: $(calls hc) / $(cat "$tmp/out")"
touch "$FAKE/server.fail"
out="$(agents_main hc up 2>&1)" && fail "a core that did not start passed"
[[ "$out" == *"did not start"* ]] || fail "failed start: $out"
out="$(agents_main hc up --bogus 2>&1)" && fail "up took an unknown option"
RUNNING=true
pass "up starts a missing core, leaves a good one, restarts a headless one only when told"

# SSH_CONNECTION is a guess (a Herdr or tmux server started over SSH hands it
# to every pane): the core's own word on the desktop login decides.
SSH="1.2.3.4 5 6.7.8.9 22"
reset; RUNNING=true; hello true
out="$(SSH_CONNECTION="$SSH" agents_main hc up 2>&1)" || fail "up refused a good core in a shell that looks like SSH: $out"
[[ "$(calls hc)" != *server* ]] || fail "up touched a good core: $(calls hc)"
reset; RUNNING=false
out="$(SSH_CONNECTION="$SSH" agents_main hc up 2>&1)" || fail "up refused to start a core that lands in the desktop login: $out"
[[ "$(calls hc)" == *"server start"* && "$(calls hc)" != *"server stop"* ]] || fail "up, SSH guess, good start: $(calls hc)"
reset; echo false > "$FAKE/start.gui"; echo '{"terminals":[]}' > "$FAKE/ls.json"
out="$(agents_main hc up 2>&1)" && fail "a core started outside the desktop login passed"
[[ "$out" == *"left running"* && "$out" == *"up --restart"* && "$out" == *"ends the core's terminals"* ]] || fail "headless start: $out"
[[ "$(calls hc)" == *"server start"* && "$(calls hc)" != *"server stop"* ]] || fail "a new headless core was stopped: $(calls hc)"
reset; echo false > "$FAKE/start.gui"
out="$(agents_main hc up -q 2>&1)" && fail "a new headless core with terminals passed"
[[ "$(calls hc)" != *"server stop"* && "$out" == *"up --restart"* ]] || fail "a core with terminals was stopped: $(calls hc) / $out"
reset; echo false > "$FAKE/start.gui"
(MAC=false; SSH_CONNECTION="$SSH" agents_main hc up -q) || fail "up failed off macOS"
reset; RUNNING=true; hello false
out="$(SSH_CONNECTION="$SSH" agents_main hc up --restart 2>&1)" && fail "up --restart over SSH ended a core's terminals"
[[ "$out" == *"at the Mac"* && "$(calls hc)" != *server* ]] || fail "up --restart over SSH: $out / $(calls hc)"
pass "a shell that looks like SSH is not refused; a core that starts outside the desktop login is reported, never stopped"

# --- the pack's job: up -q at login and every 5 minutes ---
# A problem is said once, not at every run that finds it again; all well
# clears that, so the same problem is said again when it comes back.
MARK="$AGENTS_RUN_DIR/hc-up.said"
reset; rm -f "$MARK"; RUNNING=true; hello false
out="$(agents_main hc up -q 2>&1)" && fail "up -q passed a headless core"
[[ "$out" == *"started over SSH"* ]] || fail "up -q, headless, first run: $out"
out="$(agents_main hc up -q 2>&1)" && fail "up -q passed a headless core the second time"
[[ -z "$out" ]] || fail "up -q said the same problem twice: $out"
echo '{"terminals":[{"name":"a","state":"live"},{"name":"b","state":"live"}]}' > "$FAKE/ls.json"
out="$(agents_main hc up -q 2>&1)" || true
[[ -z "$out" ]] || fail "a new count of terminals counted as a new problem: $out"
out="$(agents_main hc up 2>&1)" || true
[[ "$out" == *"started over SSH"* ]] || fail "up without -q is quiet about a known problem: $out"
touch "$FAKE/connect.hang"
out="$(agents_main hc up -q 2>&1)" || true
[[ "$out" == *"did not answer"* ]] || fail "a different problem was not said: $out"
rm -f "$FAKE/connect.hang"; hello true
out="$(agents_main hc up -q 2>&1)" || fail "up -q failed with a good core: $out"
[[ -z "$out" && ! -e "$MARK" ]] || fail "all well: '$out', mark: $(cat "$MARK" 2>/dev/null)"
hello false
out="$(agents_main hc up -q 2>&1)" || true
[[ "$out" == *"started over SSH"* ]] || fail "a problem that came back was not said: $out"
[[ "$(calls hc)" != *"server stop"* ]] || fail "the job stopped a core: $(calls hc)"
pass "up -q says a problem once, again when it changes or comes back, and never stops a core"

# AGENTS_HC_UP=0: the job starts nothing; up without -q still does.
reset; rm -f "$MARK"; RUNNING=false; hello true
out="$(AGENTS_HC_UP=0 agents_main hc up -q 2>&1)" || fail "up -q, AGENTS_HC_UP=0: $out"
[[ -z "$out" && -z "$(calls hc)" ]] || fail "AGENTS_HC_UP=0 and the job ran: $out / $(calls hc)"
out="$(AGENTS_HC_UP=0 agents_main hc up 2>&1)" || fail "up, AGENTS_HC_UP=0: $out"
[[ "$(calls hc)" == *"server start"* ]] || fail "AGENTS_HC_UP=0 kept up itself from starting a core: $(calls hc)"
RUNNING=true
pass "AGENTS_HC_UP=0 turns the job off, not agents hc up"

# Once a core is found or started, up syncs the mirrors quietly: a core
# started again has none. A sync that fails or talks fails nothing and says
# nothing; an up that failed syncs nothing.
reset; rm -f "$MARK"; RUNNING=true; hello true
( agents_hc_mirror_sync() { echo "$*" >> "$FAKE/msync.calls"; echo "noise"; echo "noise" >&2; return 1; }
  out="$(agents_main hc up -q 2>&1)" || fail "up -q failed because of the mirror sync: $out"
  [[ -z "$out" && "$(calls msync)" == "-q " && ! -e "$MARK" ]] || fail "up -q, good core: '$out', sync: $(calls msync)"
  RUNNING=false; out="$(agents_main hc up 2>&1)" || fail "up failed because of the mirror sync: $out"
  [[ "$out" == "herdr-core started" && "$(calls msync)" == "-q -q " ]] || fail "up, started: '$out', sync: $(calls msync)"
  RUNNING=true; hello false; rm -f "$FAKE/msync.calls"
  agents_main hc up -q >/dev/null 2>&1 && fail "up -q passed a headless core"
  [[ ! -e "$FAKE/msync.calls" ]] || fail "an up that failed synced the mirrors"
) || exit 1
# With mirrors off, or no Herdr here, the sync is nothing: no call to Herdr
# or to the core beyond up's own hello.
reset; rm -f "$MARK"; hello true
AGENTS_HC_MIRROR=0 agents_main hc up -q >/dev/null 2>&1 || fail "up -q, mirrors off"
[[ ! -e "$FAKE/herdr.calls" && "$(grep -c '^connect$' "$FAKE/hc.calls")" == 1 ]] || fail "up -q, mirrors off, asked more: $(calls herdr) / $(calls hc)"
reset; rm -f "$MARK"; hello true
AGENTS_HC_MIRROR=1 AGENTS_NO_HERDR=1 agents_main hc up -q >/dev/null 2>&1 || fail "up -q, no Herdr"
[[ ! -e "$FAKE/herdr.calls" && "$(grep -c '^connect$' "$FAKE/hc.calls")" == 1 ]] || fail "up -q, no Herdr, asked more: $(calls herdr) / $(calls hc)"
pass "up syncs the mirrors once it found or started a core, quietly and never failing for it; nothing with mirrors off or no Herdr"

# A core gets neither the pane's identity nor what loading agents exported.
reset; RUNNING=false; hello true
out="$(HERDR_ENV=1 HERDR_PANE_ID=w1-1 agents_main hc up -q 2>&1)" || fail "up -q: $out"
[[ "$(grep -c '^start$' "$FAKE/hc.calls")" == 1 ]] || fail "started more than once: $(calls hc)"
[[ -e "$FAKE/server.env" && ! -s "$FAKE/server.env" ]] || fail "the core inherits: $(cut -d= -f1 "$FAKE/server.env" 2>/dev/null | tr '\n' ' ')"
RUNNING=true
pass "a core is started once, without the pane's identity or agents' own exports"

# --- a pane's mark ---
# kill -0 says EPERM for someone else's live process in a sandbox: still alive.
echo 424242 > "$(_agents_hc_pane_mark w1:p1)"; echo 999999 > "$(_agents_hc_pane_mark w1:p2)"
(
kill() { return 1; }
ps() { [[ "$*" == *" 424242" ]] && echo 424242; return 0; }
_agents_hc_pane_marked w1:p1 || fail "a mark of a live process kill -0 may not signal was ignored"
! _agents_hc_pane_marked w1:p2 || fail "a mark of a gone process counted"
! _agents_hc_pane_marked w1:p3 || fail "a pane with no mark counted"
)
rm -f "$AGENTS_RUN_DIR"/hc-pane.*
pass "a pane's mark counts while its process lives, even where kill -0 may not signal it"

# The hosted panes, from their marks alone: the pane, the terminal it shows
# and its name; not a mark an older agents wrote (the pid only), one whose
# attach is gone, or one whose fields are not ids.
printf '%s\nw1:p1\tt7\tapi\n' $$ > "$(_agents_hc_pane_mark w1:p1)"
printf '%s\nw1:p2\tt8\t\n' $$ > "$(_agents_hc_pane_mark w1:p2)"
echo $$ > "$(_agents_hc_pane_mark w1:p3)"
printf '999999\nw1:p4\tt9\tgone\n' > "$(_agents_hc_pane_mark w1:p4)"
printf '%s\nw1:p5\t-x\tbad\n' $$ > "$(_agents_hc_pane_mark w1:p5)"
printf '%s\nw1 p6\tt6\tbad\n' $$ > "$(_agents_hc_pane_mark w1:p6)"
out="$(_agents_hc_marks | tr '\037' '|' | LC_ALL=C sort)"
[[ "$out" == $'w1:p1|t7|api\nw1:p2|t8|t8' ]] || fail "the hosted panes from their marks: $out"
rm -f "$AGENTS_RUN_DIR"/hc-pane.*
[[ -z "$(_agents_hc_marks)" ]] || fail "no marks: no hosted panes"
pass "the hosted panes come from their marks: pane, terminal and name; old, dead or odd marks are left out"

# --- names ---
reset; _agents_hc_bin
[[ "$(_agents_hc_name "/src/My App.v2")" == "my-app-v2" ]] || fail "name: $(_agents_hc_name "/src/My App.v2")"
[[ "$(_agents_hc_name /src/api)" == "api-2" ]] || fail "taken name: $(_agents_hc_name /src/api)"
[[ "$(_agents_hc_name /src/old)" == "old" ]] || fail "a finished terminal's name is free"
[[ -z "$(_agents_hc_name /)" ]] || fail "no directory name"
n="$(_agents_hc_name "/src/$(printf 'x%.0s' 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0)")"
[[ "$n" =~ $_AGENTS_HC_NAME_RE ]] || fail "long name: $n"
[[ "$(_agents_hc_name /src/t7)" == dir-t7 ]] || fail "a directory named like an address: $(_agents_hc_name /src/t7)"
[[ "$(_agents_hc_name /src/T12b)" == dir-t12b ]] || fail "an address with a suffix: $(_agents_hc_name /src/T12b)"
[[ "$(_agents_hc_name /src/t7xy)" == t7xy ]] || fail "not an address: $(_agents_hc_name /src/t7xy)"
[[ "$(_agents_hc_name /src/--rm)" == rm ]] || fail "leading dashes: $(_agents_hc_name /src/--rm)"
pass "a terminal is named after its directory, in herdr-core's alphabet, with a number when taken, never like an address or an option"

# --- the bridge: herdr-core's statuses, reported to Herdr for the pane ---
reset
{
    echo '{"channel":null,"seq":3,"terminals":[{"address":"t3","status":{"app":"claude-code","state":"idle"}}]}'
    echo '{"jsonrpc":"2.0","method":"event","params":{"data":{"name":"node","pid":5},"seq":4,"terminal":"t3","type":"foreground"}}'
    printf '%s\n' '{"jsonrpc":"2.0","method":"event","params":{"data":{"reported":true,"status":{"app":"claude-code","msg":"Run the\ttests","state":"working"}},"seq":5,"terminal":"t3","type":"status"}}'
    echo '{"jsonrpc":"2.0","method":"event","params":{"data":{"reported":true,"status":{"app":"claude-code","kind":"permission","state":"blocked"}},"seq":6,"terminal":"t3","type":"status"}}'
    echo '{"jsonrpc":"2.0","method":"event","params":{"data":{"reported":true,"status":{"app":"claude-code","state":"error"}},"seq":7,"terminal":"t3","type":"status"}}'
    echo '{"jsonrpc":"2.0","method":"event","params":{"data":{"reported":true,"status":{"app":"claude-code","state":"done"}},"seq":8,"terminal":"t3","type":"status"}}'
    echo 'not json'
    echo '{"jsonrpc":"2.0","method":"heartbeat","params":{"seq":8}}'
    echo '{"jsonrpc":"2.0","method":"event","params":{"data":{"reported":true,"status":null},"seq":9,"terminal":"t3","type":"status"}}'
    echo '{"jsonrpc":"2.0","method":"event","params":{"data":{"reason":"exited"},"seq":10,"terminal":"t3","type":"finished"}}'
    echo '{"jsonrpc":"2.0","method":"event","params":{"data":{"reported":true,"status":{"app":"claude-code","state":"working"}},"seq":11,"terminal":"t3","type":"status"}}'
} > "$FAKE/events"
_agents_hc_bridge w1:p2 < "$FAKE/events"
states="$(awk '$0 == "--state" { getline; printf "%s ", $0 }' "$FAKE/herdr.calls")"
[[ "$states" == "idle working blocked blocked idle unknown " ]] || fail "bridge states: $states"
grep -qx 'Run the tests' "$FAKE/herdr.calls" || fail "the status message did not reach Herdr (tabs made spaces)"
[[ "$(grep -c '^report-agent$' "$FAKE/herdr.calls")" -eq 6 ]] || fail "reports: $(calls herdr)"
[[ "$(awk '$0 == "--agent" { getline; print }' "$FAKE/herdr.calls" | sort -u)" == claude ]] || fail "agent label: $(calls herdr)"
[[ "$(calls herdr)" == *"-- pane release-agent w1:p2 --source tuidev-hc --agent claude " ]] || fail "release: $(calls herdr)"
pass "each status becomes a report for the pane (done is idle, error is blocked), and the end releases it"

reset
echo '{"channel":null,"seq":1,"terminals":[{"address":"t4","status":null}]}' | _agents_hc_bridge w1:p2
[[ "$(calls herdr)" == *"--agent agent --state unknown w1:p2"* ]] || fail "a program that reports nothing: $(calls herdr)"
pass "a program that never reported a status is an unnamed agent in an unknown state"

# A status with a message and no app: the message is a message, not the
# agent's name (an empty field between two separators stays a field).
reset
echo '{"jsonrpc":"2.0","method":"event","params":{"data":{"status":{"state":"working","msg":"Thinking"}},"seq":2,"terminal":"t3","type":"status"}}' \
    | _agents_hc_bridge w1:p2
[[ "$(calls herdr)" == *"--agent agent --state working --message Thinking w1:p2"* ]] || fail "msg without app: $(calls herdr)"
[[ "$(arg herdr --agent | sort -u)" == agent ]] || fail "the message became the agent's name: $(calls herdr)"
pass "a status with a message and no app keeps its message out of the agent's name"

# A message is the program's own words: no control character, no leading
# dash (it would read as an option), 200 characters at most.
reset
long="$(printf 'y%.0s' $(seq 1 250))"
{
    printf '%s\n' '{"jsonrpc":"2.0","method":"event","params":{"data":{"status":{"app":"codex","state":"working","msg":"-- \u001b]0;pwn\u0007 rm\nx\u007fend '"$long"'"}},"type":"status"}}'
    printf '%s\n' '{"jsonrpc":"2.0","method":"event","params":{"data":{"status":{"app":"codex","state":"working","msg":"--help"}},"type":"status"}}'
    printf '%s\n' '{"jsonrpc":"2.0","method":"event","params":{"data":{"status":{"app":"codex","state":"idle","msg":"- - -"}},"type":"status"}}'
} | _agents_hc_bridge w1:p2
msgs="$(arg herdr --message)"
[[ "$(printf '%s\n' "$msgs" | wc -l | tr -d ' ')" -eq 2 ]] || fail "messages: $(calls herdr)"
m1="$(printf '%s\n' "$msgs" | sed -n 1p)"
[[ "$m1" == "]0;pwn  rm x end yyy"* && ${#m1} -eq 200 ]] || fail "a message with control characters: [$m1] (${#m1})"
! LC_ALL=C grep -q '[[:cntrl:]]' "$FAKE/herdr.calls" || fail "a control character reached Herdr: $(calls herdr | od -c | head -3)"
[[ "$(printf '%s\n' "$msgs" | sed -n 2p)" == help ]] || fail "a message that looks like an option: $(calls herdr)"
[[ "$(calls herdr)" == *"--state idle w1:p2"* ]] || fail "a message of dashes only was not dropped: $(calls herdr)"
pass "control characters and leading dashes never reach herdr --message, and it is capped at 200"

# A Herdr that hangs holds the bridge for _AGENTS_HC_HERDR_WAIT a call, no longer.
reset; touch "$FAKE/herdr.hang"
echo '{"channel":null,"seq":1,"terminals":[{"address":"t3","status":{"app":"codex","state":"working"}}]}' > "$tmp/one"
bridge_one() { _agents_hc_bridge w1:p2 < "$tmp/one"; }
t0=$SECONDS rc=0
_agents_timeout 10 bridge_one || rc=$?
[[ $rc -ne 124 && $((SECONDS - t0)) -le $((2 * _AGENTS_HC_HERDR_WAIT + 2)) ]] || fail "a hung Herdr held the bridge $((SECONDS - t0)) s (rc $rc)"
[[ "$(calls herdr)" == *report-agent*release-agent* ]] || fail "a hung report kept the release from being tried: $(calls herdr)"
pass "a Herdr that hangs does not hold the bridge: each report and the release are timed out"

# --- the events stream, again after the core restarts ---
reset; RUNNING=false; _AGENTS_HC_TRIES=3
echo '{"channel":null,"seq":1,"terminals":[]}' > "$FAKE/events"
rc=0; _agents_timeout 5 _agents_hc_events t3 $$ >/dev/null || rc=$?
[[ $rc -eq 0 && "$(calls hc)" != *events* ]] || fail "with no core, the stream was asked for (that starts one): rc $rc, $(calls hc)"
RUNNING=true
rc=0; _agents_timeout 5 _agents_hc_events t3 $$ > "$tmp/stream" || rc=$?
[[ $rc -eq 0 && "$(grep -cx events "$FAKE/hc.calls")" -eq 3 && "$(grep -c terminals "$tmp/stream")" -eq 3 ]] \
    || fail "streams that keep ending: rc $rc, $(grep -cx events "$FAKE/hc.calls") tries"
reset; ( exit 0 ) & gone=$!; wait "$gone"
rc=0; _agents_timeout 5 _agents_hc_events t3 "$gone" >/dev/null || rc=$?
[[ $rc -eq 0 && "$(calls hc)" != *events* ]] || fail "a stream was opened for a reader that is gone: $(calls hc)"
_AGENTS_HC_TRIES=30
pass "a stream that ends is opened again a few times, never while no core runs, and not for a reader that is gone"

# --- run and attach ---
reset; RUNNING=true; hello true; echo '{"state":"live"}' > "$FAKE/get.json"
out="$(cd "$tmp" && agents_main hc run -- claude --resume 2>&1)" || fail "run failed: $out"
grep -qx -- '--bg' "$FAKE/hc.calls" || fail "run did not start it in the background: $(calls hc)"
grep -qx -- '--no-parent' "$FAKE/hc.calls" || fail "run did not start it without a parent: $(calls hc)"
# Through env(1), with this shell's PATH over the core's (a core the pack's
# job started has launchd's or systemd's), and never a token of the shell's.
[[ "$(calls hc)" == *" -- /usr/bin/env PATH=$PATH "*" claude --resume -- attach"* ]] || fail "the command did not reach herdr-core whole: $(calls hc)"
[[ "$(calls hc)" != *"HERDR_"* ]] || fail "run handed the pane's identity on: $(calls hc)"
[[ "$(calls hc)" == *"-- attach "* ]] || fail "run did not attach: $(calls hc)"
[[ "$out" == *"still runs in herdr-core"*"agents hc attach"*"herdr-core kill"* ]] || fail "leaving a live agent: $out"
[[ ! -e "$FAKE/herdr.calls" ]] || fail "outside a Herdr pane, Herdr was told something: $(calls herdr)"
pass "run starts the command in herdr-core with no parent, attaches, and says a detached agent still runs"

# A name can point at another terminal after a core restart: the address is
# what attach and get take; the name is only shown.
reset; echo '{"state":"live"}' > "$FAKE/get.json"
out="$(agents_main hc run --name web bun dev 2>&1)" || fail "named run failed: $out"
[[ "$(calls hc)" == *"-- attach t3 "*"-- get t3 "* && "$(calls hc)" != *"attach web"* ]] || fail "run used the name: $(calls hc)"
[[ "$out" == "web still runs"*"agents hc attach t3"* ]] || fail "shown name: $out"
reset; echo '{"state":"finished"}' > "$FAKE/get.json"
out="$(agents_main hc run --name web bun dev 2>&1)" || fail "named run failed: $out"
[[ "$(calls hc)" == *"--name web -- /usr/bin/env PATH="*" bun dev -- attach t3 "* ]] || fail "named run: $(calls hc)"
[[ -z "$out" ]] || fail "an agent that ended left a note: $out"
reset
out="$(agents_main hc run --name 'Bad Name' x 2>&1)" && fail "a bad name passed"
out="$(agents_main hc run --name -- claude 2>&1)" && fail "--name took -- for a name"
[[ "$out" == *"a name is"* ]] || fail "--name --: $out"
out="$(agents_main hc run --name -x claude 2>&1)" && fail "--name took an option for a name"
out="$(agents_main hc run --name 2>&1)" && fail "--name with nothing after it passed"
[[ ! -e "$FAKE/hc.calls" ]] || fail "a refused name still reached herdr-core: $(calls hc)"
out="$(agents_main hc run 2>&1)" && fail "run with no command passed"
reset; touch "$FAKE/run.fail"
out="$(agents_main hc run claude 2>&1)" && fail "a failed start passed"
[[ "$out" == *"name taken"* && "$(calls hc)" != *"-- attach"* ]] || fail "failed start: $out / $(calls hc)"
pass "a name is checked (an option is not one), an ended agent leaves no note, and a start that fails attaches nothing"

reset; hello false
out="$(agents_main hc run --name a claude 2>&1)" || fail "run on a headless core failed: $out"
[[ "$out" == *"warning"*"started over SSH"* ]] || fail "headless warning: $out"
pass "run warns when the core is outside the desktop login"

# With no core, run starts one first: without the pane's Herdr identity, and
# not one outside the desktop login.
reset; RUNNING=false; hello true
out="$(HERDR_ENV=1 HERDR_PANE_ID=w5:p5 HERDR_TAB_ID=w5:t1 HERDR_WORKSPACE_ID=w5 HERDR_SOCKET_PATH="$tmp/h.sock" \
       AGENTS_NO_HERDR=1 agents_main hc run --name a claude 2>&1)" || fail "run with no core failed: $out"
[[ "$(calls hc)" == *"server start"*"-- run "* ]] || fail "run did not start the core first: $(calls hc)"
grep -q '^HERDR_PANE_ID=w5:p5$' "$FAKE/run.env" || fail "(the caller did not carry a pane's identity: the test proves nothing)"
[[ -e "$FAKE/server.env" && ! -s "$FAKE/server.env" ]] || fail "the core started with Herdr's environment: $(tr '\n' ' ' < "$FAKE/server.env")"
reset; echo false > "$FAKE/start.gui"; echo '{"terminals":[]}' > "$FAKE/ls.json"
out="$(agents_main hc run --name a claude 2>&1)" && fail "run went on with a core it started outside the desktop login"
[[ "$out" == *"left running"* && "$(calls hc)" != *"server stop"* && "$(calls hc)" != *"-- run "* ]] || fail "run, headless start: $out / $(calls hc)"
RUNNING=true
pass "run with no core starts one without the pane's Herdr identity, and refuses one outside the desktop login without stopping it"

# Leaving an attach asks the core about the terminal only while it runs.
reset; RUNNING=false; echo '{"state":"live"}' > "$FAKE/get.json"
out="$(_agents_hc_attach t3 2>&1)" || fail "attach to a core that went away failed: $out"
[[ "$(calls hc)" == *"-- attach t3 "* && "$(calls hc)" != *"-- get"* ]] || fail "leaving asked a core that is gone (that starts one): $(calls hc)"
reset
out="$(agents_main hc attach t3 2>&1)" && fail "attach with no core passed"
[[ "$out" == *"no core runs"* && ! -e "$FAKE/hc.calls" ]] || fail "attach, no core: $out / $(calls hc)"
RUNNING=true
pass "an attach with no core is refused, and leaving one whose core went away starts none"

# In a Herdr pane the bridge runs beside the attach, and ends with it.
reset; hello true; echo 1 > "$FAKE/attach.wait"
echo '{"channel":null,"seq":3,"terminals":[{"address":"t3","status":{"app":"codex","state":"working"}}]}' > "$FAKE/events"
out="$(HERDR_PANE_ID=w9:p1 agents_main hc attach t3 2>&1)" || fail "attach in a pane failed: $out"
# (The two stand-in calls log at the same time: look for the words, not their order.)
{ grep -qx 'events' "$FAKE/hc.calls" && grep -qx -- '--terminal' "$FAKE/hc.calls"; } || fail "no events stream: $(calls hc)"
[[ "$(calls herdr)" == *"--agent codex --state working w9:p1"*"release-agent w9:p1"* ]] || fail "pane bridge: $(calls herdr)"
[[ "$(sed -n 2p "$FAKE/mark.seen")" == "w9:p1"$'\t'"t3"$'\t'"t3" ]] || fail "the pane's mark while attached: $(cat "$FAKE/mark.seen")"
for f in "$AGENTS_RUN_DIR"/hc-bridge.* "$AGENTS_RUN_DIR"/hc-pane.*; do [[ ! -e "$f" ]] || fail "left behind: $f"; done
reset; echo 1 > "$FAKE/attach.wait"
out="$(AGENTS_NO_HERDR=1 HERDR_PANE_ID=w9:p1 agents_main hc attach t3 2>&1)" || fail "attach with AGENTS_NO_HERDR failed"
[[ ! -e "$FAKE/herdr.calls" ]] || fail "AGENTS_NO_HERDR did not keep Herdr out of it"
out="$(agents_main hc attach 2>&1)" && fail "attach with no terminal passed"
out="$(agents_main hc bogus 2>&1)" && fail "an unknown subcommand passed"
pass "in a Herdr pane the status bridge runs while attached and cleans up; AGENTS_NO_HERDR turns it off"

# A live stream (it stays open) is ended when the attach ends.
reset; echo 1 > "$FAKE/attach.wait"; touch "$FAKE/events.live"
attach_pane() { HERDR_PANE_ID=w9:p1 agents_main hc attach t3 >/dev/null 2>&1; }
t0=$SECONDS rc=0
_agents_timeout 10 attach_pane || rc=$?
[[ $rc -ne 124 && $((SECONDS - t0)) -le 4 ]] || fail "the attach waited $((SECONDS - t0)) s on its events stream (rc $rc)"
[[ -s "$FAKE/events.pid" ]] || fail "(the stream never opened: the test proves nothing)"
! kill -0 "$(cat "$FAKE/events.pid")" 2>/dev/null || fail "the events stream outlived the attach"
[[ "$(calls herdr)" == *"release-agent w9:p1"* ]] || fail "live stream: no release: $(calls herdr)"
pass "a live events stream ends with the attach"

# The core restarts under the attach: its stream ends, and the bridge opens
# another, the pane released only once, at the end.
reset; echo 2 > "$FAKE/attach.wait"; touch "$FAKE/events.live"
echo '{"channel":null,"seq":3,"terminals":[{"address":"t3","status":{"app":"codex","state":"working"}}]}' > "$FAKE/events.1"
echo '{"channel":null,"seq":9,"terminals":[{"address":"t3","status":{"app":"codex","state":"idle"}}]}' > "$FAKE/events"
rc=0; _agents_timeout 10 attach_pane || rc=$?
[[ $rc -eq 0 ]] || fail "attach across a restart: rc $rc"
[[ "$(grep -cx events "$FAKE/hc.calls")" -eq 2 ]] || fail "streams: $(grep -cx events "$FAKE/hc.calls"), want 2"
[[ "$(calls herdr)" == *"--state working w9:p1"*"--state idle w9:p1"*"release-agent w9:p1"* ]] || fail "across a restart: $(calls herdr)"
[[ "$(grep -c '^release-agent$' "$FAKE/herdr.calls")" -eq 1 ]] || fail "the pane was released mid-attach: $(calls herdr)"
pass "after the core restarts the bridge opens a new stream, and the pane stays reported"

# A closed pane hangs up the whole attach; a kill terminates it. Either way
# the pane is released and the pipe and the pane's mark go. (_agents_timeout
# gives the attach a process group of its own, which the stand-in signals.)
for sig in HUP TERM; do
    reset; echo 0.5 > "$FAKE/attach.wait"; echo "$sig" > "$FAKE/attach.sig"; touch "$FAKE/events.live"
    t0=$SECONDS rc=0
    _agents_timeout 15 attach_pane || rc=$?
    [[ $((SECONDS - t0)) -le 6 ]] || fail "SIG$sig: the attach took $((SECONDS - t0)) s to end (rc $rc)"
    [[ "$sig" != HUP || $rc -eq 129 ]] || fail "SIGHUP: rc $rc"
    [[ "$(calls herdr)" == *"--state idle w9:p1"*"release-agent w9:p1"* ]] || fail "SIG$sig: the pane was not released before the attach ended: $(calls herdr)"
    for f in "$AGENTS_RUN_DIR"/hc-bridge.* "$AGENTS_RUN_DIR"/hc-pane.*; do [[ ! -e "$f" ]] || fail "SIG$sig left $f behind"; done
    ! kill -0 "$(cat "$FAKE/events.pid" 2>/dev/null || echo 0)" 2>/dev/null || fail "SIG$sig: the events stream outlived the attach"
done
pass "an attach that is hung up or killed still releases the pane and leaves no pipe or mark"

# --- automatic hosting: agents hc auto ---
# What counts as an interactive start: only options an interactive session
# takes; a prompt, a subcommand, -p, --help or --version is run as typed.
while IFS='|' read -r want line; do
    [[ -n "$want" ]] || continue
    # shellcheck disable=SC2086  # the table's words are the arguments
    set -f; eval "set -- $line"; set +f
    got=1; _agents_hc_auto_interactive "$@" && got=0
    [[ "$got" == "$want" ]] || fail "interactive start: [$line] is $got, not $want"
done <<'EOF'
0|claude
0|claude --continue
0|claude -c
0|claude --resume
0|claude -r 4f1c
0|claude --resume 4f1c --fork-session
0|claude --model opus
0|claude --model=opus --verbose
0|claude --permission-mode plan --add-dir ../a --add-dir '../b c' --ide
0|claude --dangerously-skip-permissions --mcp-config a.json
0|/opt/bin/claude --continue
0|codex
0|codex --model gpt-5 --search
0|codex -p work -c model=o3 --no-alt-screen
0|codex --no-daemon
0|codex resume
0|codex resume --last
0|codex resume 0199ab
1|claude -p hi
1|claude --print hi
1|claude -p
1|claude --continue -p 'sum up'
1|claude --help
1|claude -h
1|claude --version
1|claude -v
1|claude 'fix the bug'
1|claude --plugin-dir ./p mcp list
1|claude --add-dir ../a ../b
1|codex --add-dir ../x exec 'run tests'
1|codex --add-dir ../x login status
1|codex -i a.png review
1|claude ''
1|claude mcp list
1|claude update
1|claude doctor
1|claude setup-token
1|claude --model
1|claude --model opus 'do it'
1|claude --append-system-prompt -x
1|claude --continue=yes
1|claude -cr
1|claude --no-such-flag
1|claude --
1|claude -
1|codex exec 'run tests'
1|codex login
1|codex mcp list
1|codex --version
1|codex -h
1|codex 'fix it'
1|codex review
1|codex resume a b
1|grok
1|bash -c true
EOF
pass "an interactive start is claude or codex with only an interactive session's options; anything else is run as typed"

# Stand-in agents on PATH: each logs its name and arguments (a line each,
# after a "--" line) and what it saw of the environment, says one line, and
# exits with $FAKE/agent.rc.
mkdir -p "$tmp/bin" "$tmp/My Proj"
for a in claude codex; do
    cat > "$tmp/bin/$a" <<'EOF'
#!/bin/bash
{ echo "--"; printf '%s\n' "${0##*/}" "$@"; } >> "$FAKE/agent.calls"
{ echo "jre=$(env | grep -c '^AGENTS_JRE_')"; echo "token=${MY_TOKEN-unset}"; echo "mine=${AGENTS_MINE-unset}"; } > "$FAKE/agent.env"
echo "agent here"
exit "$(cat "$FAKE/agent.rc" 2>/dev/null || echo 0)"
EOF
    chmod +x "$tmp/bin/$a"
done
PATH="$tmp/bin:$PATH"
TTY=true
_agents_hc_auto_tty() { [[ "$TTY" == true ]]; }
AGENTS_HC_AUTO=1 HERDR_ENV=1 HERDR_PANE_ID=w1:p1 AGENTS_NO_HERDR=1

# auto ARG... — agents hc auto in "My Proj", in a subshell (it may exec):
# what it printed in $out, its status in $rc.
# The pane's own account or network settings keep a start out of the core
# (below); a sandbox's proxy must not decide these tests.
# shellcheck disable=SC2086  # a list of names
unset $_AGENTS_HC_AUTO_OWN
auto() { rc=0; out="$(cd "$tmp/My Proj" && agents_main hc auto "$@" 2>&1)" || rc=$?; }
# ran_plain WHY RC ARG... — the agent ran here exactly as typed, with its
# status, and nothing was said but what it said; herdr-core started nothing.
ran_plain() {
    local why="$1" want="$2"
    shift 2
    [[ $rc -eq $want ]] || fail "$why: status $rc, not $want: $out"
    [[ "$(cat "$FAKE/agent.calls" 2>/dev/null)" == "$(printf '%s\n' -- "$@")" ]] || fail "$why: the agent ran as: $(calls agent)"
    [[ "$out" == "agent here" ]] || fail "$why: more than the agent said: $out"
    [[ "$(calls hc)" != *"-- run "* ]] || fail "$why: herdr-core was asked to run it: $(calls hc)"
}
no_core() { [[ ! -e "$FAKE/hc.calls" ]] || fail "$1: herdr-core was asked: $(calls hc)"; }

RUNNING=true MAC=true
reset; hello true; echo 3 > "$FAKE/agent.rc"
AGENTS_HC_AUTO=0 auto claude --model opus;  ran_plain "setting off" 3 claude --model opus; no_core "setting off"
reset; hello true
(unset AGENTS_HC_AUTO; auto claude; ran_plain "setting unset" 0 claude; no_core "setting unset")
reset; HERDR_ENV='' auto claude;            ran_plain "not a Herdr pane" 0 claude; no_core "not a Herdr pane"
reset; HERDR_PANE_ID='' auto claude;        ran_plain "no pane id" 0 claude; no_core "no pane id"
reset; HC_TERMINAL_ID=t9 auto claude;       ran_plain "in a herdr-core terminal" 0 claude; no_core "in a herdr-core terminal"
reset; TTY=false auto codex --search;       ran_plain "no terminal" 0 codex --search; no_core "no terminal"
reset; auto claude -p "a  b" --model opus;  ran_plain "claude -p" 0 claude -p "a  b" --model opus; no_core "claude -p"
reset; auto codex exec "x y";               ran_plain "codex exec" 0 codex exec "x y"; no_core "codex exec"
reset; echo $$ > "$(_agents_hc_pane_mark w1:p1)"
auto claude;                                ran_plain "a pane already on a core terminal" 0 claude; no_core "a marked pane"
rm -f "$AGENTS_RUN_DIR"/hc-pane.*
reset; AGENTS_HC_BIN="$tmp/nope" auto claude; ran_plain "no herdr-core" 0 claude; no_core "no herdr-core"
reset; RUNNING=false auto claude;           ran_plain "no core" 0 claude; no_core "no core"
reset; hello false; auto claude;            ran_plain "a core outside the desktop login" 0 claude
reset; echo '{"result":{"version":"0.1.21"}}' > "$FAKE/hello.json"
auto claude;                                ran_plain "a core that does not say where it runs (macOS)" 0 claude
reset; hello true; HTTPS_PROXY=http://proxy.invalid:1 auto claude
ran_plain "a proxy set in the pane" 0 claude; no_core "a proxy set in the pane"
reset; hello true; ANTHROPIC_API_KEY=k auto claude; ran_plain "an API key set in the pane" 0 claude
pass "every case that cannot host runs the agent as typed, with its status and no word of its own; no core is asked before it is known to run"

# A core that does not answer: the start waited for it, so one line says why.
reset; hello true; touch "$FAKE/connect.hang"; echo 4 > "$FAKE/agent.rc"
t0=$SECONDS; auto claude --continue
[[ $((SECONDS - t0)) -le $((_AGENTS_HC_WAIT + 2)) ]] || fail "a core that does not answer held the start $((SECONDS - t0)) s"
[[ $rc -eq 4 && "$(cat "$FAKE/agent.calls")" == "$(printf '%s\n' -- claude --continue)" ]] || fail "no answer: rc $rc, $(calls agent)"
[[ "$out" == "agents hc: herdr-core did not answer within $_AGENTS_HC_WAIT s; claude starts here, not in herdr-core"$'\n'"agent here" ]] \
    || fail "no answer: $out"
pass "a core that does not answer in time: the agent starts here, after one line that says why"

# Hosting: herdr-core runs the real binary through env(1), in this
# directory, with the pane's PATH and the few variables that are passed on;
# no token of the shell's, no Herdr identity. The pane attaches to it.
reset; hello true; echo '{"state":"finished"}' > "$FAKE/get.json"; echo 5 > "$FAKE/attach.rc"
export MY_TOKEN=s3cret
CLAUDE_CONFIG_DIR="$tmp/cc" auto claude --model opus --add-dir "a b" --add-dir c
unset MY_TOKEN
[[ $rc -eq 5 ]] || fail "hosted: the attach's status was not passed on: rc $rc ($out)"
[[ ! -e "$FAKE/agent.calls" ]] || fail "hosted, and run here too: $(calls agent)"
log="$(cat "$FAKE/hc.calls")"
[[ "$log" == *"$(printf '%s\n' run --bg --json --no-parent --cwd "$tmp/My Proj" --name my-proj -- /usr/bin/env "PATH=$PATH")"* ]] \
    || fail "hosted: the start: $(calls hc)"
[[ "$log" == *"$(printf '%s\n' "CLAUDE_CONFIG_DIR=$tmp/cc" "$tmp/bin/claude" --model opus --add-dir "a b" --add-dir c --)"* ]] \
    || fail "hosted: the command and its arguments: $(calls hc)"
[[ "$log" == *"$(printf '%s\n' -- attach t3)"* ]] || fail "hosted: no attach: $(calls hc)"
! grep -qE '^(MY_TOKEN|HERDR_[A-Z_]*|AGENTS_[A-Z_]*|CODEX_HOME)=' "$FAKE/hc.calls" || fail "hosted: passed on what it must not: $(calls hc)"
pass "hosting starts the real binary in herdr-core in this directory with PATH and a few named variables only, attaches, and passes on the attach's status"

# Hosting decided, and the core then refuses: the agent starts here, after one line.
reset; hello true; touch "$FAKE/run.fail"; echo 6 > "$FAKE/agent.rc"
auto claude --resume 4f1c
[[ $rc -eq 6 && "$(cat "$FAKE/agent.calls")" == "$(printf '%s\n' -- claude --resume 4f1c)" ]] || fail "refused: rc $rc, $(calls agent)"
[[ "$out" == "agents hc: herdr-core did not start it (name taken); claude starts here, not in herdr-core"$'\n'"agent here" ]] || fail "refused: $out"
[[ "$(calls hc)" != *"-- attach"* ]] || fail "refused, and attached: $(calls hc)"
[[ "$(calls hc)" != *"-- kill"* ]] || fail "refused, and something was ended: $(calls hc)"
# A start whose answer has no address may have started: it is ended before
# the agent starts here, or there would be two.
reset; hello true; touch "$FAKE/run.mute"
auto claude --continue
rm -f "$FAKE/run.mute"
[[ "$out" == *"did not say what it started; claude starts here"*"agent here" ]] || fail "no address: $out"
[[ "$(cat "$FAKE/hc.calls")" == *"$(printf '%s\n' -- kill my-proj)"* ]] || fail "no address: the half start was not ended: $(calls hc)"
# codex is hosted with --no-daemon (herdr-core's rule), once.
reset; hello true; echo '{"state":"finished"}' > "$FAKE/get.json"
auto codex --search
[[ "$(cat "$FAKE/hc.calls")" == *"$(printf '%s\n' "$tmp/bin/codex" --no-daemon --search --)"* ]] || fail "codex without --no-daemon: $(calls hc)"
reset; hello true; echo '{"state":"finished"}' > "$FAKE/get.json"
auto codex --no-daemon
[[ "$(cat "$FAKE/hc.calls")" == *"$(printf '%s\n' "$tmp/bin/codex" --no-daemon --)"* ]] || fail "codex --no-daemon twice: $(calls hc)"
# Off macOS the core is not asked where it runs.
reset; hello false; MAC=false auto codex
[[ $rc -eq 0 && ! -e "$FAKE/agent.calls" && "$(calls hc)" != *"-- connect"* && "$(calls hc)" == *"-- run "* ]] \
    || fail "Linux: $(calls hc) / $out"
pass "a core that refuses the start leaves the agent to start here, with one line; off macOS the desktop login is not asked about"

reset
out="$(agents_main hc auto 2>&1)" && fail "auto with no command passed"
rc=0; out="$(agents_main hc auto no-such-agent 2>&1)" || rc=$?
[[ $rc -eq 127 && "$out" == *"no-such-agent: command not found"* ]] || fail "a missing command: rc $rc, $out"
pass "auto needs a command, and a missing one is 127 like the shell's"

# Through bin/agents itself: the modules its `hc auto` fast path loads hold
# everything hc.sh calls (test_agents_install.sh checks every fast path's
# reach), and the agent gets the environment it was given, without the
# patterns loading agents exports.
auto_mods=""
for row in "${_AGENTS_FAST_PATHS[@]}"; do [[ "${row%%|*}" != "hc auto" ]] || { auto_mods="${row#*|}"; auto_mods="${auto_mods%%|*}"; }; done
[[ "$auto_mods" == config\ * ]] || fail "no hc auto row in _AGENTS_FAST_PATHS: ${_AGENTS_FAST_PATHS[*]}"
fns="$(grep -oE '_agents_[a-z0-9_]+' "$REPO_DIR/lib/agents/hc.sh" | sort -u)"
missing="$(env -i PATH="$PATH" HOME="$HOME" AGENTS_CONF="$AGENTS_CONF" bash -c '
    for m in $1; do . "$2/lib/agents/$m.sh"; done
    for f in $3; do declare -F "$f" >/dev/null || echo "$f"; done' _ "$auto_mods" "$REPO_DIR" "$fns")"
[[ -z "$missing" ]] || fail "agents hc auto does not load what defines: $missing"
reset
rc=0; out="$(cd "$tmp/My Proj" && env -i PATH="$PATH" HOME="$HOME" FAKE="$FAKE" AGENTS_CONF="$AGENTS_CONF" AGENTS_HC_AUTO=1 \
    MY_TOKEN=x AGENTS_MINE=1 "$REPO_DIR/bin/agents" hc auto claude -p "a b" 2>&1)" || rc=$?
[[ $rc -eq 0 && "$out" == "agent here" && "$(cat "$FAKE/agent.calls")" == "$(printf '%s\n' -- claude -p "a b")" ]] || fail "bin/agents: rc $rc, $out"
[[ "$(cat "$FAKE/agent.env")" == $'jre=0\ntoken=x\nmine=1' ]] || fail "bin/agents: the agent's environment: $(cat "$FAKE/agent.env")"
pass "bin/agents hc auto loads only what it needs, and a start it does not host gets the environment it was given"

# Status says whether it is on.
reset; hello true
out="$(AGENTS_HC_AUTO=0 agents_main hc status 2>&1)" || true
[[ "$out" == *"automatic hosting: off (AGENTS_HC_AUTO=1"* ]] || fail "status, off: $out"
out="$(agents_main hc status 2>&1)" || true
[[ "$out" == *"automatic hosting: on, but the shell fragment is missing"* ]] || fail "status, no fragment: $out"
mkdir -p "$HOME/.config/tuidev/shell.d"; : > "$HOME/.config/tuidev/shell.d/hc-auto.zsh"
out="$(RUNNING=false agents_main hc status 2>&1)" || true
[[ "$out" == *"not running"*"automatic hosting: on for claude and codex"* ]] || fail "status, on, no core: $out"
pass "agents hc says whether automatic hosting is on, and when the shell fragment is missing"
unset AGENTS_HC_AUTO HERDR_ENV HERDR_PANE_ID AGENTS_NO_HERDR

# --- the shell fragment (zsh) ---
if ! command -v zsh >/dev/null 2>&1; then
    echo "SKIP: no zsh: the hc-auto fragment's functions not checked"
else
    frag="$REPO_DIR/configs/zsh/hc-auto.zsh"
    zsh -n "$frag" || fail "hc-auto.zsh is not valid zsh"
    zb="$tmp/zbin"; mkdir -p "$zb"
    printf '#!/bin/sh\n[ "$*" != "hc auto --supported" ] || exit "${ZOLD:-0}"\n{ echo --; printf "%%s\\n" agents "$@"; } >> "$FAKE/zagents.calls"\n' > "$zb/agents"
    printf '#!/bin/sh\nexit 0\n' > "$zb/herdr-core"
    cp "$tmp/bin/claude" "$tmp/bin/codex" "$zb/"
    chmod +x "$zb"/*
    # zsh_frag [NAME=VALUE...] -- [ZSH OPTION...] — an interactive zsh -f that
    # sources the fragment, then runs $ZCMD; the environment is only these.
    zsh_frag() {
        local envs=()
        while [[ $# -gt 0 && "$1" != -- ]]; do envs+=("$1"); shift; done
        [[ $# -eq 0 ]] || shift
        env -i PATH="$zb:/usr/bin:/bin" HOME="$HOME" FAKE="$FAKE" AGENTS_CONF="$tmp/z.conf" ${envs[@]+"${envs[@]}"} \
            zsh -f "${@:--i}" -c "source '$frag'; $ZCMD" 2>&1
    }
    printf 'AGENTS_HC_MIRROR=0\nAGENTS_HC_AUTO=1   # on\n' > "$tmp/z.conf"
    ZCMD='whence -w claude codex'
    [[ "$(zsh_frag HERDR_ENV=1)" == $'claude: function\ncodex: function' ]] || fail "fragment, on: $(zsh_frag HERDR_ENV=1)"
    # Not typed at a terminal (an agent's tool shell, a pipe): the real command, agents not run.
    reset; ZCMD='claude --model opus "a b"; echo "rc=$?"'
    out="$(echo 2 > "$FAKE/agent.rc"; zsh_frag HERDR_ENV=1)"
    [[ "$out" == $'agent here\nrc=2' && "$(cat "$FAKE/agent.calls")" == "$(printf '%s\n' -- claude --model opus "a b")" ]] \
        || fail "fragment, no terminal: $out / $(calls agent)"
    [[ ! -e "$FAKE/zagents.calls" ]] || fail "fragment, no terminal: agents was run: $(calls zagents)"
    # Where it does not apply, nothing is defined: a shell that is not
    # interactive (an agent's), the setting off, a herdr-core terminal, no Herdr.
    ZCMD='whence -w claude'
    for c in "HERDR_ENV=1 -- +i" "HERDR_ENV=1 AGENTS_HC_AUTO=0" "HERDR_ENV=1 HC_TERMINAL_ID=t1" "HERDR_ENV="; do
        # shellcheck disable=SC2086  # the case's words
        got="$(zsh_frag $c)"
        [[ "$got" == "claude: command" ]] || fail "fragment where it does not apply ($c): $got"
    done
    printf 'AGENTS_HC_AUTO=1\nAGENTS_HC_AUTO=0\n' > "$tmp/z.conf"
    [[ "$(zsh_frag HERDR_ENV=1)" == "claude: command" ]] || fail "fragment: the conf's last line did not win"
    rm -f "$tmp/z.conf"
    [[ "$(zsh_frag HERDR_ENV=1)" == "claude: command" ]] || fail "fragment: no agents.conf is off"
    [[ "$(zsh_frag HERDR_ENV=1 AGENTS_HC_AUTO=1)" == "claude: function" ]] || fail "fragment: the environment's setting"
    for b in herdr-core agents; do
        mv "$zb/$b" "$tmp/$b.keep"
        [[ "$(zsh_frag HERDR_ENV=1 AGENTS_HC_AUTO=1)" == "claude: command" ]] || fail "fragment without $b"
        mv "$tmp/$b.keep" "$zb/$b"
    done
    # An agents from before `hc auto`: nothing defined. agents.conf as config.sh
    # reads it: a quoted value with a comment after it is no value.
    [[ "$(zsh_frag HERDR_ENV=1 AGENTS_HC_AUTO=1 ZOLD=2)" == "claude: command" ]] || fail "fragment with an agents that has no hc auto"
    printf 'AGENTS_HC_AUTO="1"   # on\n' > "$tmp/z.conf"
    [[ "$(zsh_frag HERDR_ENV=1)" == "claude: command" ]] || fail "fragment: a conf line config.sh refuses turned it on"
    printf "AGENTS_HC_AUTO='1'\n" > "$tmp/z.conf"
    [[ "$(zsh_frag HERDR_ENV=1)" == "claude: function" ]] || fail "fragment: a quoted value"
    rm -f "$tmp/z.conf"
    # A claude alias of the user's, and nounset: the file still loads, in
    # every shell, with nothing said.
    ZCMD='echo loaded'
    got="$(env -i PATH="$zb:/usr/bin:/bin" HOME="$HOME" zsh -f -i -c "setopt nounset; alias claude='claude --verbose' codex=x; source '$frag'; $ZCMD" 2>&1)"
    [[ "$got" == loaded ]] || fail "fragment with an alias, outside Herdr: $got"
    got="$(env -i PATH="$zb:/usr/bin:/bin" HOME="$HOME" FAKE="$FAKE" HERDR_ENV=1 AGENTS_HC_AUTO=1 zsh -f -i -c "setopt nounset; alias claude='claude --verbose'; source '$frag'; whence -w _tuidev_hc_auto" 2>&1)"
    [[ "$got" == "_tuidev_hc_auto: function" ]] || fail "fragment with an alias, on: $got"
    pass "the fragment defines claude and codex only in an interactive Herdr pane with the setting on, and a call not typed at a terminal is the real command"

    # Typed at a terminal: agents hc auto gets the command and its arguments
    # whole; with agents gone since the shell started, the real command runs.
    # script(1) gives zsh a pseudo-terminal (util-linux and BusyBox take -c,
    # BSD the command after the file); there is none in some sandboxes.
    printf '#!/bin/sh\nexec env -i PATH="%s:/usr/bin:/bin" HOME="%s" FAKE="%s" HERDR_ENV=1 AGENTS_HC_AUTO=1 zsh -f -i -c "source %s; $ZCMD"\n' \
        "$zb" "$HOME" "$FAKE" "'$frag'" > "$tmp/ztty"
    chmod +x "$tmp/ztty"
    ztty() {
        if script -qc true /dev/null >/dev/null 2>&1 </dev/null; then
            ZCMD="$1" script -qc "$tmp/ztty" /dev/null >/dev/null 2>&1 </dev/null || true
        elif script -q /dev/null true >/dev/null 2>&1 </dev/null; then
            ZCMD="$1" script -q /dev/null "$tmp/ztty" >/dev/null 2>&1 </dev/null || true
        fi
    }
    reset; ztty 'claude --model opus "a b"'
    if [[ ! -e "$FAKE/zagents.calls" && ! -e "$FAKE/agent.calls" ]]; then
        echo "SKIP: no pseudo-terminal here (sandbox?): the fragment's call at a terminal not checked"
    else
        [[ "$(cat "$FAKE/zagents.calls" 2>/dev/null)" == "$(printf '%s\n' -- agents hc auto claude --model opus "a b")" ]] \
            || fail "fragment at a terminal: agents got: $(calls zagents) (the agent: $(calls agent))"
        [[ ! -e "$FAKE/agent.calls" ]] || fail "fragment at a terminal: the agent ran here as well: $(calls agent)"
        cp "$zb/agents" "$tmp/agents.keep"
        reset; ztty 'rm -f '"'$zb/agents'"'; codex --search'
        cp "$tmp/agents.keep" "$zb/agents"
        [[ "$(cat "$FAKE/agent.calls" 2>/dev/null)" == "$(printf '%s\n' -- codex --search)" ]] \
            || fail "fragment at a terminal, agents gone: the agent ran as: $(calls agent)"
        pass "typed at a terminal, claude goes to agents hc auto with its arguments whole; without agents, the real command runs"
    fi
fi

agents_usage | grep -q 'agents hc run' || fail "agents --help does not list agents hc"
pass "agents --help lists it"

echo "all agents hc tests passed"
