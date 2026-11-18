#!/bin/bash
# Unit tests for lib/agents/hcmirror.sh (`agents hc mirror`): every agent pane
# of this machine's Herdr gets a mirror in herdr-core, kept in step by a sync,
# and what a mirror's core terminal runs (`agents hc _mirror`).
# Run: bash scripts/lib/test_agents_hcmirror.sh  -> exit 0 on pass.
#
# No herdr-core and no Herdr: AGENTS_HC_BIN and HERDR_BIN_PATH are stand-ins
# that answer from files in $FAKE and log every call, one argument a line
# after a "--" line, so a test sees exactly what reached each of them.

# Tests change variables inside ( … ) on purpose; the stand-ins are called by
# the code under test.
# SC2016: single quotes keep hostile pane ids literal. SC1003: ESC \ ends an OSC.
# shellcheck disable=SC2030,SC2031,SC2034,SC2329,SC2317,SC2016,SC1003
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq is not installed"; exit 0; }

tmp="$(mktemp -d "${TMPDIR:-/tmp}/tuidev-test.XXXXXX")"
holder_pid=""
trap '[[ -z "$holder_pid" ]] || kill "$holder_pid" 2>/dev/null; rm -rf "$tmp"' EXIT
for v in XDG_CONFIG_HOME XDG_STATE_HOME XDG_RUNTIME_DIR TUIDEV_STATE_DIR AGENTS_NO_HERDR AGENTS_HC_MIRROR HC_SOCKET HC_SESSION \
         HERDR_ENV HERDR_PANE_ID HERDR_SOCKET_PATH SSH_CONNECTION SSH_CLIENT SSH_TTY; do unset "$v"; done
export HOME="$tmp/home" NO_COLOR=1 TZ=UTC AGENTS_CONF="$tmp/none.conf" AGENTS_DATA_DIR="$tmp/data" AGENTS_RUN_DIR="$tmp/run"
export AGENTS_TESTING=1 FAKE="$tmp/fake"
mkdir -p "$HOME/.config/herdr" "$FAKE" "$AGENTS_RUN_DIR" "$tmp/proj-a" "$tmp/proj-b"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "PASS: $1"; }

# The stand-in herdr-core. `connect` answers terminal.list from list.json and
# anything else with a hello; run and kill only log. hang.CMD makes CMD hang.
cat > "$tmp/herdr-core" <<'EOF2'
#!/bin/bash
{ echo "--"; printf '%s\n' "$@"; } >> "$FAKE/hc.calls"
[[ ! -f "$FAKE/hang.$1" ]] || exec sleep 30
case "$1" in
    connect) req="$(cat)"
             if [[ "$req" == *terminal.list* ]]; then cat "$FAKE/list.json"
             else echo '{"result":{"login_session":{"gui":true}}}'; fi ;;
    ls)      cat "$FAKE/ls.json" ;;
    run)     echo "$*" >> "$FAKE/run.calls"; echo '{"address":"t9","state":"live"}' ;;
    kill)    echo "$2" >> "$FAKE/kill.calls" ;;
esac
EOF2
# The stand-in herdr: a snapshot, a pane, a queue of states for `agent wait`
# (wait.1, wait.2 … one a call; then it fails), and an attach. hang.snapshot
# makes the snapshot hang; wait.hang makes `agent wait` hang (its pid in
# wait.pid), and the attach then lasts until that wait has started.
cat > "$tmp/herdr" <<'EOF2'
#!/bin/bash
{ echo "--"; printf '%s\n' "$@"; } >> "$FAKE/herdr.calls"
case "$1 $2" in
    "api snapshot") [[ ! -f "$FAKE/hang.snapshot" ]] || exec sleep 30
                    cat "$FAKE/snap.json" ;;
    "pane get")     cat "$FAKE/pane.json" 2>/dev/null || exit 1 ;;
    "agent wait")   if [[ -f "$FAKE/wait.hang" ]]; then echo "$$" > "$FAKE/wait.pid"; exec sleep 30; fi
                    n=$(( $(cat "$FAKE/wait.n" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$FAKE/wait.n"
                    [[ -f "$FAKE/wait.$n" ]] || exit 1
                    cat "$FAKE/wait.$n" ;;
    "agent attach") echo "$*" >> "$FAKE/attach.calls"
                    if [[ -f "$FAKE/wait.hang" ]]; then
                        for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30; do
                            [[ ! -s "$FAKE/wait.pid" ]] || break; sleep 0.1
                        done
                    fi
                    exit "$(cat "$FAKE/attach.rc" 2>/dev/null || echo 0)" ;;
esac
EOF2
chmod +x "$tmp/herdr-core" "$tmp/herdr"
export AGENTS_HC_BIN="$tmp/herdr-core" HERDR_BIN_PATH="$tmp/herdr"
# Mirrors are off unless asked for; the tests below ask.
export AGENTS_HC_MIRROR=1

# shellcheck source=../../bin/agents disable=SC1091
. "$REPO_DIR/bin/agents"

# Whether a core is up, and whether Herdr has a socket, are the test's to say.
RUNNING=true
_agents_hc_is_mac() { return 0; }
_agents_hc_running() { [[ "$RUNNING" == true ]]; }
_agents_hl_socket() { return 0; }

reset() {
    rm -f "${FAKE:?}"/*.calls "${FAKE:?}"/wait.* "${FAKE:?}"/attach.rc "${FAKE:?}"/pane.json "${FAKE:?}"/hang.* "${AGENTS_RUN_DIR:?}"/hc-pane.*
    rm -rf "${AGENTS_RUN_DIR:?}/hc-mirror.lock" "${AGENTS_RUN_DIR:?}/hc-mirror.started"
    unset AGENTS_NOW
    RUNNING=true
    echo '{"jsonrpc":"2.0","id":1,"result":{"terminals":[]}}' > "$FAKE/list.json"
    echo '{"terminals":[]}' > "$FAKE/ls.json"
}
calls() { [[ ! -f "$FAKE/$1.calls" ]] || tr '\n' ' ' < "$FAKE/$1.calls"; }
# snap 'PANE|AGENT|STATUS|CWD' …  (layout rects from RECT="PANE:W:H …")
snap() {
    local p arr="" lay="" r id ag st cw w h
    for p in "$@"; do
        IFS='|' read -r id ag st cw <<<"$p"
        arr="$arr${arr:+,}$(jq -nc --arg id "$id" --arg ag "$ag" --arg st "$st" --arg cw "$cw" \
            '{pane_id:$id,agent:$ag,agent_status:$st,cwd:$cw,foreground_cwd:$cw}')"
    done
    for r in ${RECT:-}; do
        IFS=: read -r id w h <<<"$r"
        lay="$lay${lay:+,}{\"pane_id\":\"$id\",\"rect\":{\"width\":$w,\"height\":$h}}"
    done
    printf '{"result":{"snapshot":{"layouts":[{"panes":[%s]}],"panes":[%s]}}}\n' "$lay" "$arr" > "$FAKE/snap.json"
}
# terms 'ADDRESS|NAME|STATE|PANE' … ; PANE empty = no mirror label
terms() {
    local t out="" ad nm stt pn
    for t in "$@"; do
        IFS='|' read -r ad nm stt pn <<<"$t"
        out="$out${out:+,}$(jq -nc --arg a "$ad" --arg n "$nm" --arg s "$stt" --arg p "$pn" \
            '{address:$a,name:$n,state:$s,labels:(if $p == "" then {} else {tuidev_mirror:$p} end)}')"
    done
    printf '{"jsonrpc":"2.0","id":1,"result":{"terminals":[%s]}}\n' "$out" > "$FAKE/list.json"
}
# The `run` calls, one a line (the "--" of the program makes hc.calls
# ambiguous), and the addresses `kill` got.
runs() { [[ ! -f "$FAKE/run.calls" ]] || cat "$FAKE/run.calls"; }
kills() { [[ ! -f "$FAKE/kill.calls" ]] || tr '\n' ' ' < "$FAKE/kill.calls"; }
mark() { echo "$2" > "$(_agents_hc_pane_mark "$1")"; }

# --- starting ---
reset; RECT="p1:120:40"; snap "p1|claude|working|$tmp/proj-a"
out="$(agents_hc_mirror_sync 2>&1)" || fail "sync failed: $out"
r="$(runs)"
[[ "$(printf '%s\n' "$r" | grep -c .)" == 1 ]] || fail "one mirror expected: $r"
[[ "$r" == "run --bg --json --no-parent --no-notify --rm --name proj-a --label tuidev_mirror=p1 --cwd $tmp/proj-a -- /usr/bin/env HERDR_BIN_PATH=$tmp/herdr HERDR_SOCKET_PATH=$HOME/.config/herdr/herdr.sock bash $AGENTS_PATH hc _mirror p1 120 40" ]] \
    || fail "mirror command: $r"
[[ "$out" == *"mirror p1 (claude, proj-a)"* ]] || fail "output: $out"
[[ -f "$AGENTS_RUN_DIR/hc-mirror.started/p1" ]] || fail "no start time kept for p1"
pass "an agent pane with no mirror gets one (--rm): name, label, cwd, size from its layout, Herdr's paths"

reset; RECT=""; snap "p2|codex|idle|$tmp/proj-b"
agents_hc_mirror_sync -q
[[ "$(runs)" == *"_mirror p2 160 50" ]] || fail "default size: $(runs)"
(HERDR_SOCKET_PATH=/x/h.sock; reset; snap "p2|codex|idle|$tmp/proj-b"; agents_hc_mirror_sync -q
 [[ "$(runs)" == *"HERDR_SOCKET_PATH=/x/h.sock bash"* ]]) || fail "HERDR_SOCKET_PATH not passed"
pass "a pane with no layout is 160x50; the socket path of the caller is passed on"

# --- nothing to start ---
reset; snap "p1||idle|$tmp/proj-a" "p2|claude|idle|$tmp/proj-a" "p3|claude|idle|$tmp/proj-b" "p4|claude|idle|$tmp/proj-b" "p5|claude|idle|$tmp/proj-b"
terms "t1|x|live|p2"
mark p3 $$
mark p4 999999
agents_hc_mirror_sync -q
r="$(runs)"
[[ "$r" != *"_mirror p1 "* ]] || fail "a pane with no agent was mirrored"
[[ "$r" != *"_mirror p2 "* ]] || fail "a pane with a live mirror was mirrored again"
[[ "$r" != *"_mirror p3 "* ]] || fail "a core-hosted pane was mirrored"
[[ "$r" == *"_mirror p4 "* && "$r" == *"_mirror p5 "* ]] || fail "dead mark / plain pane not mirrored: $r"
[[ "$(printf '%s\n' "$r" | grep -c .)" == 2 ]] || fail "extra runs: $r"
pass "no mirror for a pane with no agent, one that has a live mirror, or a core-hosted one; a dead mark does not count"

# a finished mirror does not count as a mirror
reset; snap "p1|claude|idle|$tmp/proj-a"; terms "t1|x|finished|p1"
agents_hc_mirror_sync -q
[[ "$(runs)" == *"_mirror p1 "* ]] || fail "a finished mirror hid a pane"
pass "a finished mirror is no mirror: the pane gets a new one"

# --- ending ---
reset; snap "p1|claude|idle|$tmp/proj-a" "p2|claude|idle|$tmp/proj-a" "p3||idle|$tmp/proj-a" "p4|claude|idle|$tmp/proj-a"
terms "t1|a|live|p1" "t2|b|live|gone" "t3|c|live|p3" "t4|d|finished|gone2" "t5|e|live|" "t6|f|live|p4"
mark p4 $$
out="$(agents_hc_mirror_sync 2>&1)"
[[ "$(kills)" == "t2 t3 t6 " ]] || fail "kills: $(kills) / $out"
[[ "$out" == *"end the mirror of gone (b)"* ]] || fail "end line: $out"
pass "it ends live labelled mirrors whose pane lost its agent or went core-hosted, nothing else"

# --- parsing ---
reset; snap "p1|claude||$tmp/proj-a" "p2|claude|idle|"
agents_hc_mirror_sync -q
r="$(runs)"
[[ "$r" == *"--cwd $tmp/proj-a -- "*"_mirror p1 160 50"* ]] || fail "empty status: $r"
[[ "$r" == *"--cwd $HOME -- "*"_mirror p2 160 50"* ]] || fail "empty cwd falls back to HOME: $r"
reset; snap "p1|claude|idle|$tmp/does-not-exist"
agents_hc_mirror_sync -q
[[ "$(runs)" == *"--cwd $HOME -- "* ]] || fail "missing dir: $(runs)"
mkdir -p "$tmp/-dir"
reset; snap "p1|claude|idle|-dir"
(cd "$tmp" && agents_hc_mirror_sync -q)
[[ "$(runs)" == *"--cwd $HOME -- "* ]] || fail "a relative cwd (one that reads as an option) was passed: $(runs)"
pass "an empty status or cwd stays a field; a directory that is gone, or a relative one, becomes HOME"

# --- pane ids ---
reset; snap "p 1|claude|idle|$tmp/proj-a" 'p;rm|claude|idle|x' 'a$(x)|claude|idle|x' 'p`x`|claude|idle|x' '-p|claude|idle|x' "ok:1|claude|idle|$tmp/proj-a"
agents_hc_mirror_sync -q
r="$(runs)"
[[ "$(printf '%s\n' "$r" | grep -c .)" == 1 && "$r" == *"_mirror ok:1 "* ]] || fail "bad pane ids: $r"
[[ "$(calls hc)" != *'$('* && "$(calls hc)" != *';rm'* ]] || fail "a bad id reached a command line"
pass "pane ids with spaces or shell metacharacters are skipped"

# --- -n, -q ---
reset; snap "p1|claude|idle|$tmp/proj-a" "p2|claude|idle|$tmp/proj-a"; terms "t1|a|live|p1" "t2|b|live|gone"
out="$(agents_hc_mirror_sync -n 2>&1)"
[[ "$out" == *"mirror p2 (claude, proj-a)"* && "$out" == *"end the mirror of gone"* ]] || fail "-n output: $out"
[[ -z "$(runs)" && -z "$(kills)" ]] || fail "-n changed something: $(calls hc)"
out="$(agents_hc_mirror_sync -q 2>&1)"; [[ -z "$out" ]] || fail "-q printed: $out"
reset; snap "p1|claude|idle|$tmp/proj-a"; terms "t1|a|live|p1"
out="$(agents_hc_mirror_sync 2>&1)"; [[ "$out" == *"every agent pane has its mirror"* ]] || fail "settled: $out"
agents_hc_mirror_sync -x >/dev/null 2>&1 && fail "a bad option passed"
pass "-n says what it would do and does nothing; -q is silent; a settled sync says so"

# --- not ready: nothing that could start a core ---

quiet_calls() { [[ "$(calls hc)" != *connect* && "$(calls hc)" != *"run "* && "$(calls hc)" != *ls* && ! -s "$FAKE/herdr.calls" ]]; }
reset; snap "p1|claude|idle|$tmp/proj-a"
for off in 0 ""; do
    out="$(AGENTS_HC_MIRROR="$off" agents_hc_mirror_sync 2>&1)"
    [[ "$out" == *"AGENTS_HC_MIRROR=1"* ]] || fail "off ('$off'): $out / $(calls hc)"
    quiet_calls || fail "off ('$off') called the core or Herdr: $(calls hc) $(calls herdr)"
done
out="$(unset AGENTS_HC_MIRROR; agents_hc_mirror_sync 2>&1)"
[[ "$out" == *"AGENTS_HC_MIRROR=1"* ]] || fail "unset is not off: $out"
quiet_calls || fail "unset called the core or Herdr: $(calls hc)"
out="$(AGENTS_NO_HERDR=1 agents_hc_mirror_sync 2>&1)"
[[ "$out" == *"Herdr is not reachable"* ]] || fail "no herdr: $out"
quiet_calls || fail "called the core or Herdr: $(calls hc) $(calls herdr)"
out="$(AGENTS_HC_BIN="$tmp/nope" agents_hc_mirror_sync 2>&1)"
[[ "$out" == *"not installed"* ]] || fail "no core binary: $out"
quiet_calls || fail "called the core or Herdr: $(calls hc) $(calls herdr)"
RUNNING=false
out="$(agents_hc_mirror_sync 2>&1)"
[[ "$out" == *"not running"* ]] || fail "no core running: $out"
quiet_calls || fail "called the core or Herdr: $(calls hc) $(calls herdr)"
out="$(agents_hc_mirror_sync -q 2>&1)"
[[ -z "$out" ]] || fail "-q when not ready: $out"
quiet_calls || fail "-q called the core or Herdr"
agents_hc_mirror_sync >/dev/null || fail "not ready must return 0"
pass "off, no Herdr, no herdr-core, no running core: says why (not with -q), starts nothing, calls nothing"

# --- the lock ---
reset; snap "p1|claude|idle|$tmp/proj-a"
sleep 60 & holder_pid=$!
mkdir "$AGENTS_RUN_DIR/hc-mirror.lock"
echo "$holder_pid $(_agents_start "$holder_pid")" > "$AGENTS_RUN_DIR/hc-mirror.lock/holder"
agents_hc_mirror_sync -q || fail "a held lock must not fail the sync"
[[ -z "$(runs)" ]] || fail "sync ran while the lock was held: $(runs)"
kill "$holder_pid" 2>/dev/null; wait "$holder_pid" 2>/dev/null || true; holder_pid=""
rm -rf "${AGENTS_RUN_DIR:?}/hc-mirror.lock"
agents_hc_mirror_sync -q
[[ -n "$(runs)" ]] || fail "no mirror after the lock was free"
[[ ! -e "$AGENTS_RUN_DIR/hc-mirror.lock" ]] || fail "lock left behind"
pass "a sync yields to a live holder of the lock and releases it when done"

# --- status ---
reset; snap "p1|claude|working|$tmp/proj-a" "p2|codex|idle|$tmp/proj-b" "p3|claude|idle|$tmp/proj-b"
terms "t1|proj-a|live|p1"; mark p3 $$
out="$(agents_main hc mirror 2>&1)" || fail "status failed: $out"
[[ "$out" == *"p1 "*"mirrored as proj-a"* ]] || fail "status p1: $out"
[[ "$out" == *"p2 "*"not mirrored yet"* ]] || fail "status p2: $out"
[[ "$out" == *"p3 "*"in herdr-core itself"* ]] || fail "status p3: $out"
[[ "$(printf '%s\n' "$out" | grep -c .)" == 3 ]] || fail "status lines: $out"
[[ -z "$(runs)" ]] || fail "status started a mirror"
snap; out="$(agents_main hc mirror status 2>&1)"; [[ "$out" == *"no agent panes"* ]] || fail "empty status: $out"
agents_main hc mirror bogus >/dev/null 2>&1 && fail "bad subcommand passed"
pass "status: a line for each agent pane, mirrored / not yet / in herdr-core itself"

# --- agents herdr sync ---
reset; snap "p1|claude|idle|$tmp/proj-a"
agents_main herdr sync -q >/dev/null 2>&1 || true
[[ "$(runs)" == *"_mirror p1 "* ]] || fail "herdr sync -q did not sync the mirrors: $(calls hc)"
reset; snap "p1|claude|idle|$tmp/proj-a"
agents_main herdr sync -n >/dev/null 2>&1 || true
[[ ! -e "$FAKE/hc.calls" ]] || fail "herdr sync -n touched the core: $(calls hc)"
pass "agents herdr sync also syncs the mirrors; with -n it does not"

# --- the report ---
for s in idle working blocked "done"; do
    got="$(_agents_hm_report "$s" claude | od -An -tx1 | tr -d ' \n')"
    want="$(printf '\033]7501;state=%s:app=claude\033\\' "$s" | od -An -tx1 | tr -d ' \n')"
    [[ "$got" == "$want" && "$got" == 1b5d37353031* && "$got" == *1b5c ]] || fail "report $s: $got"
done
[[ -z "$(_agents_hm_report unknown claude)" && -z "$(_agents_hm_report "" claude)" && -z "$(_agents_hm_report bogus claude)" ]] || fail "unknown state reported"
want="$(printf '\033]7501;state=idle:app=agent\033\\' | od -An -tx1)"
for a in 'a b' 'a;b' 'a$b' '' 'abc/def'; do
    [[ "$(_agents_hm_report idle "$a" | od -An -tx1)" == "$want" ]] || fail "agent name '$a' not replaced"
done
[[ "$(_agents_hm_report idle my-agent_1.2 | od -An -tx1)" == "$(printf '\033]7501;state=idle:app=my-agent_1.2\033\\' | od -An -tx1)" ]] || fail "a good name changed"
pass "the report is exactly ESC ] 7501;state=S:app=A ESC \\; unknown says nothing; odd agent names become agent"

# --- follow ---
st() { printf '{"result":{"agent":{"agent_status":"%s"}}}\n' "$1" > "$FAKE/wait.$2"; }
reset; echo '{"result":{"pane":{"agent":"claude","agent_status":"idle"}}}' > "$FAKE/pane.json"
st working 1; st blocked 2; st "done" 3
got="$(_agents_hm_follow p1 | od -An -tx1 | tr -d ' \n')"
want="$(for s in idle working blocked "done"; do printf '\033]7501;state=%s:app=claude\033\\' "$s"; done | od -An -tx1 | tr -d ' \n')"
[[ "$got" == "$want" ]] || fail "follow reports: $got"
h="$(calls herdr)"
[[ "$h" == *"agent wait p1 --until working --until blocked --until done --until unknown "* ]] || fail "first wait: $h"
[[ "$h" == *"agent wait p1 --until idle --until blocked --until done --until unknown "* ]] || fail "wait after working: $h"
[[ "$h" == *"agent wait p1 --until idle --until working --until done --until unknown "* ]] || fail "wait after blocked: $h"
pass "follow reports the state now, then each change; waits for every state but the current; ends when wait fails"

reset; echo '{"result":{"pane":{"agent":"","agent_status":"idle"}}}' > "$FAKE/pane.json"
out="$(_agents_hm_follow p1)"; [[ -z "$out" && "$(calls herdr)" != *"agent wait"* ]] || fail "follow of a pane with no agent: $out"
reset
out="$(_agents_hm_follow p1)"; [[ -z "$out" && "$(calls herdr)" != *"agent wait"* ]] || fail "follow of a missing pane: $out"
pass "follow of a pane with no agent reports nothing and ends"

# --- _mirror ---
reset
for bad in "" "p 1" "p;x" "-p"; do
    rc=0; agents_main hc _mirror "$bad" 100 40 >/dev/null 2>&1 || rc=$?
    [[ "$rc" == 2 ]] || fail "bad pane '$bad': exit $rc"
done
for bad in "" x 1x -3; do
    rc=0; agents_main hc _mirror p1 "$bad" 40 >/dev/null 2>&1 || rc=$?
    [[ "$rc" == 2 ]] || fail "bad cols '$bad': exit $rc"
    rc=0; agents_main hc _mirror p1 100 "$bad" >/dev/null 2>&1 || rc=$?
    [[ "$rc" == 2 ]] || fail "bad rows '$bad': exit $rc"
done
[[ ! -e "$FAKE/herdr.calls" ]] || fail "a bad call reached herdr: $(calls herdr)"
rc=0; agents_main hc _mirror p1 100 40 </dev/null >/dev/null 2>&1 || rc=$?
[[ "$rc" == 0 && "$(cat "$FAKE/attach.calls")" == "agent attach p1" ]] || fail "attach: rc=$rc $(cat "$FAKE/attach.calls")"
echo 7 > "$FAKE/attach.rc"
rc=0; agents_main hc _mirror p1 100 40 </dev/null >/dev/null 2>&1 || rc=$?
[[ "$rc" == 7 ]] || fail "attach's exit status: $rc"
pass "_mirror refuses a bad pane or size with 2; otherwise it attaches and returns the attach's status"

# --- an answer that is not one changes nothing ---
# Read as "no mirrors", a failed list would start a second mirror for every
# pane; read as "no panes", a failed snapshot would end every mirror.
nothing_changed() { [[ -z "$(runs)" && -z "$(kills)" && ! -e "$AGENTS_RUN_DIR/hc-mirror.lock" ]]; }
for bad in '{"jsonrpc":"2.0","id":1,"error":{"message":"no"}}' 'not json' '' '{"jsonrpc":"2.0","id":1,"result":{}}' \
           '{"jsonrpc":"2.0","id":1,"result":{"terminals":null}}' '{"jsonrpc":"2.0","id":2,"result":{"terminals":[]}}' \
           '{"jsonrpc":"2.0","method":"event","params":{"type":"status"}}'; do
    reset; snap "p1|claude|idle|$tmp/proj-a" "p2|claude|idle|$tmp/proj-a"
    printf '%s\n' "$bad" > "$FAKE/list.json"
    out="$(agents_hc_mirror_sync 2>&1)" || fail "a bad list failed the sync"
    nothing_changed || fail "list '$bad' changed something: runs=$(runs) kills=$(kills)"
    [[ "$out" == *"herdr-core did not answer; nothing changed"* ]] || fail "list '$bad' output: $out"
    [[ -z "$(agents_hc_mirror_sync -q 2>&1)" ]] || fail "-q printed on a bad list"
done
reset; snap "p1|claude|idle|$tmp/proj-a" "p2|claude|idle|$tmp/proj-a"; terms "t1|a|live|p1" "t2|b|live|gone"
{ echo '{"jsonrpc":"2.0","method":"event","params":{"type":"status","id":1}}'; echo 'garbage'; cat "$FAKE/list.json"; } > "$FAKE/list.new"
mv "$FAKE/list.new" "$FAKE/list.json"
agents_hc_mirror_sync -q
[[ "$(runs)" == *"_mirror p2 "* && "$(runs)" != *"_mirror p1 "* && "$(kills)" == "t2 " ]] \
    || fail "a notification before the response: runs=$(runs) kills=$(kills)"
pass "terminal.list: an error, garbage, no list, another id or only a notification changes nothing; a notification or garbage before the response is skipped"

for bad in 'garbage' '' '{}' '{"result":{"snapshot":{}}}' '{"result":{"snapshot":{"panes":"x"}}}' '{"error":{"message":"no"}}'; do
    reset; terms "t1|a|live|p1" "t2|b|live|p2"
    printf '%s\n' "$bad" > "$FAKE/snap.json"
    out="$(agents_hc_mirror_sync 2>&1)" || fail "a bad snapshot failed the sync"
    nothing_changed || fail "snapshot '$bad' changed something: runs=$(runs) kills=$(kills)"
    [[ "$out" == *"Herdr did not answer; nothing changed"* ]] || fail "snapshot '$bad' output: $out"
    [[ "$(calls hc)" != *connect* ]] || fail "snapshot '$bad': the core was asked anyway"
done
reset; terms "t1|a|live|p1"; echo 'garbage' > "$FAKE/snap.json"
out="$(agents_main hc mirror status 2>&1)" && fail "status on a bad snapshot passed: $out"
reset; snap "p1|claude|idle|$tmp/proj-a"; echo 'garbage' > "$FAKE/list.json"
out="$(agents_main hc mirror status 2>&1)" && fail "status on a bad list passed: $out"
[[ "$out" == *"herdr-core did not answer"* ]] || fail "status on a bad list: $out"
pass "a snapshot with no list of panes ends nothing and starts nothing; status says which one did not answer"

# --- duplicates ---
reset; snap "p1|claude|idle|$tmp/proj-a" "p2|claude|idle|$tmp/proj-a"
terms "t1|a|live|p1" "t2|b|live|p1" "t3|c|live|p2" "t4|d|live|p1" "t5|e|finished|p2"
out="$(agents_hc_mirror_sync 2>&1)"
[[ "$(kills)" == "t2 t4 " && -z "$(runs)" ]] || fail "duplicates: kills=$(kills) runs=$(runs) / $out"
pass "a pane with more than one live mirror keeps the first; the rest are ended"

# --- time limits ---
# Every call to the core or to Herdr is cut off; the sync returns 0, frees
# the lock, and does not ask a core that hung again.
saved_wait=$_AGENTS_HC_WAIT saved_hwait=$_AGENTS_HC_HERDR_WAIT
_AGENTS_HC_WAIT=1 _AGENTS_HC_HERDR_WAIT=1
timed_sync() {
    local t0=$SECONDS rc=0
    agents_hc_mirror_sync -q || rc=$?
    [[ $rc -eq 0 ]] || fail "$1: the sync failed ($rc)"
    [[ $((SECONDS - t0)) -le 4 ]] || fail "$1: the sync took $((SECONDS - t0)) s"
    [[ ! -e "$AGENTS_RUN_DIR/hc-mirror.lock" ]] || fail "$1: the lock was left behind"
}
reset; snap "p1|claude|idle|$tmp/proj-a"; : > "$FAKE/hang.snapshot"
timed_sync snapshot; nothing_changed || fail "a hung snapshot changed something"
reset; snap "p1|claude|idle|$tmp/proj-a"; : > "$FAKE/hang.connect"
timed_sync connect; nothing_changed || fail "a hung list changed something"
reset; snap "p1|claude|idle|$tmp/proj-a" "p2|claude|idle|$tmp/proj-a"; : > "$FAKE/hang.run"
timed_sync run
[[ "$(grep -cx run "$FAKE/hc.calls")" == 1 ]] || fail "a hung run was followed by another: $(calls hc)"
reset; snap "p1|claude|idle|$tmp/proj-a"; terms "t1|a|live|gone" "t2|b|live|gone2"; : > "$FAKE/hang.kill"
timed_sync kill
[[ "$(grep -cx kill "$FAKE/hc.calls")" == 1 && "$(grep -cx run "$FAKE/hc.calls")" == 0 ]] || fail "a hung kill was followed by more: $(calls hc)"
rm -f "$FAKE/hang.kill"; agents_hc_mirror_sync -q
[[ "$(kills)" == "t1 t2 " && "$(runs)" == *"_mirror p1 "* ]] || fail "the next sync after a hang: kills=$(kills) runs=$(runs)"
_AGENTS_HC_WAIT=$saved_wait _AGENTS_HC_HERDR_WAIT=$saved_hwait
pass "a hung snapshot, list, run or kill is cut off: the sync returns 0 in time, frees the lock, and stops asking that core"

# --- starting again ---
reset; snap "p1|claude|idle|$tmp/proj-a"
AGENTS_NOW=1000; agents_hc_mirror_sync -q
AGENTS_NOW=1059; out="$(agents_hc_mirror_sync 2>&1)"
[[ "$(grep -c . <<<"$(runs)")" == 1 ]] || fail "started again within a minute: $(runs)"
[[ "$out" == *"mirror p1 again in 1 s"* && "$out" != *"every agent pane"* ]] || fail "backoff output: $out"
AGENTS_NOW=1060; agents_hc_mirror_sync -q
[[ "$(grep -c . <<<"$(runs)")" == 2 ]] || fail "not started again after a minute: $(runs)"
mkdir -p "$AGENTS_RUN_DIR/hc-mirror.started"; echo 1000 > "$AGENTS_RUN_DIR/hc-mirror.started/p9"
snap "p1||idle|$tmp/proj-a"; agents_hc_mirror_sync -q
[[ ! -e "$AGENTS_RUN_DIR/hc-mirror.started/p1" && ! -e "$AGENTS_RUN_DIR/hc-mirror.started/p9" ]] \
    || fail "start times of panes with no agent kept: $(ls "$AGENTS_RUN_DIR/hc-mirror.started")"
reset; snap "p1|claude|idle|$tmp/proj-a"; AGENTS_NOW=1000
agents_hc_mirror_sync -n >/dev/null
[[ ! -e "$AGENTS_RUN_DIR/hc-mirror.started/p1" ]] || fail "-n kept a start time"
reset; snap "ok:1|claude|idle|$tmp/proj-a"; AGENTS_NOW=1000; agents_hc_mirror_sync -q
[[ -f "$AGENTS_RUN_DIR/hc-mirror.started/ok_1" ]] || fail "start time file name: $(ls "$AGENTS_RUN_DIR/hc-mirror.started")"
AGENTS_NOW=1001; agents_hc_mirror_sync -q
[[ "$(grep -c . <<<"$(runs)")" == 1 && -f "$AGENTS_RUN_DIR/hc-mirror.started/ok_1" ]] || fail "backoff for ok:1: $(runs)"
unset AGENTS_NOW
pass "a pane's mirror is started again only a minute after its last start; start times of panes with no agent go; -n keeps none"

# --- agents herdr sync --throttle ---
reset; snap "p1|claude|idle|$tmp/proj-a"
AGENTS_NOW=5000; echo 4990 > "$AGENTS_RUN_DIR/herdr-labels.stamp"
agents_main herdr sync --throttle -q >/dev/null 2>&1 || true
[[ ! -e "$FAKE/hc.calls" ]] || fail "a throttled herdr sync synced the mirrors: $(calls hc)"
echo 4000 > "$AGENTS_RUN_DIR/herdr-labels.stamp"
agents_main herdr sync --throttle -q >/dev/null 2>&1 || true
[[ "$(runs)" == *"_mirror p1 "* ]] || fail "a due herdr sync --throttle did not sync the mirrors: $(calls hc)"
reset; snap "p1|claude|idle|$tmp/proj-a"
agents_main -n herdr sync -q >/dev/null 2>&1 || true
[[ ! -e "$FAKE/hc.calls" ]] || fail "agents -n herdr sync touched the core: $(calls hc)"
unset AGENTS_NOW; rm -f "$AGENTS_RUN_DIR/herdr-labels.stamp"
pass "herdr sync --throttle: the mirrors are synced only when the labels are; agents -n herdr sync leaves the core alone"

# --- the size ---
reset
( _agents_hm_tty() { return 0; }
  stty() { echo "$*" >> "$FAKE/stty.calls"; return "${STTY_RC:-0}"; }
  for sz in "3 1:cols 20 rows 5" "120 40:cols 120 rows 40" "99999 0040:cols 1000 rows 40" "100 123456789012345678901:cols 100 rows 500"; do
      rm -f "$FAKE/stty.calls" "$FAKE/attach.calls"
      # shellcheck disable=SC2086  # COLS ROWS, two words
      agents_main hc _mirror p1 ${sz%%:*} </dev/null >/dev/null 2>&1 || fail "_mirror ${sz%%:*} failed"
      [[ "$(cat "$FAKE/stty.calls")" == "${sz#*:}" ]] || fail "size ${sz%%:*}: $(cat "$FAKE/stty.calls")"
      [[ -s "$FAKE/attach.calls" ]] || fail "size ${sz%%:*}: not attached"
  done
  rm -f "$FAKE/attach.calls"; rc=0
  STTY_RC=1 agents_main hc _mirror p1 120 40 </dev/null >/dev/null 2>&1 || rc=$?
  [[ "$rc" == 1 && ! -e "$FAKE/attach.calls" ]] || fail "a tty that took no size was attached: rc=$rc"
) || fail "size"
reset
( stty() { echo "$*" >> "$FAKE/stty.calls"; return 1; }
  agents_main hc _mirror p1 3 1 </dev/null >/dev/null 2>&1 || fail "_mirror with no tty failed"
  [[ ! -e "$FAKE/stty.calls" && -s "$FAKE/attach.calls" ]] || fail "no tty: stty=$(calls stty) attach=$(calls attach)"
) || fail "no tty"
pass "_mirror sizes its tty to the pane, kept within 20x5 and 1000x500; no attach when the tty takes no size; no tty, no stty"

# --- the follower ends with the attach ---
reset; echo '{"result":{"pane":{"agent":"claude","agent_status":"idle"}}}' > "$FAKE/pane.json"; : > "$FAKE/wait.hang"
agents_main hc _mirror p1 100 40 </dev/null >/dev/null 2>&1 || fail "_mirror with a following wait failed"
wpid="$(cat "$FAKE/wait.pid" 2>/dev/null)"
[[ "$wpid" =~ ^[0-9]+$ ]] || fail "the wait never started"
! kill -0 "$wpid" 2>/dev/null || { kill "$wpid" 2>/dev/null; fail "herdr agent wait outlived the mirror"; }
ls "$AGENTS_RUN_DIR"/hc-mirror-wait.* >/dev/null 2>&1 && fail "the follower left its file: $(ls "$AGENTS_RUN_DIR")"
pass "when the attach ends, the follower ends and its herdr agent wait with it"

# --- off ends what an earlier sync started; `mirror end` ends them by hand ---
reset; snap "p1|claude|idle|$tmp/proj-a"; terms "t1|a|live|p1" "t2|b|live|p2" "t3|mine|live|"
mkdir -p "$AGENTS_RUN_DIR/hc-mirror.started"; echo 1 > "$AGENTS_RUN_DIR/hc-mirror.started/p1"
out="$(AGENTS_HC_MIRROR=0 agents_hc_mirror_sync -n 2>&1)"
[[ -z "$(kills)" && -d "$AGENTS_RUN_DIR/hc-mirror.started" ]] || fail "-n ended mirrors: $(kills)"
AGENTS_HC_MIRROR=0 agents_hc_mirror_sync -q
[[ "$(kills)" == "t1 t2 " && -z "$(runs)" ]] || fail "off did not end the mirrors, or ended more: kills=$(kills) runs=$(runs)"
[[ ! -d "$AGENTS_RUN_DIR/hc-mirror.started" && ! -e "$AGENTS_RUN_DIR/hc-mirror.lock" ]] || fail "off left its record or lock"
rm -f "$FAKE"/*.calls
AGENTS_HC_MIRROR=0 agents_hc_mirror_sync -q
[[ ! -e "$FAKE/hc.calls" ]] || fail "off asked the core again with nothing to end: $(calls hc)"
reset; terms "t1|a|live|p1"; mkdir -p "$AGENTS_RUN_DIR/hc-mirror.started"; printf 'garbage\n' > "$FAKE/list.json"
AGENTS_HC_MIRROR=0 agents_hc_mirror_sync -q
[[ -z "$(kills)" && -d "$AGENTS_RUN_DIR/hc-mirror.started" ]] || fail "a core that did not answer: the record went, so nothing tries again"
reset; mkdir -p "$AGENTS_RUN_DIR/hc-mirror.started"
(RUNNING=false; AGENTS_HC_MIRROR=0 agents_hc_mirror_sync -q; [[ ! -e "$FAKE/hc.calls" && ! -d "$AGENTS_RUN_DIR/hc-mirror.started" ]]) \
    || fail "off with no core running asked one, or kept the record"
reset; terms "t1|a|live|p1" "t2|b|finished|p2" "t3|mine|live|"
out="$(AGENTS_HC_MIRROR=0 agents_main hc mirror end 2>&1)"
[[ "$(kills)" == "t1 " && "$out" == *"ended the mirror of p1 (a)"* ]] || fail "mirror end: $out / $(kills)"
reset; terms "t3|mine|live|"
out="$(agents_main hc mirror end 2>&1)"; [[ -z "$(kills)" && "$out" == *"no mirror runs"* ]] || fail "mirror end with none: $out"
pass "off: a sync ends the mirrors an earlier one started, once, and nothing else; mirror end ends them by hand"

# --- the report's app name ---
[[ "$(_agents_hm_report idle a+b | od -An -tx1)" == "$(printf '\033]7501;state=idle:app=a+b\033\\' | od -An -tx1)" ]] || fail "+ refused"
n32="abcdefghijabcdefghijabcdefghij12"
[[ "$(_agents_hm_report idle "$n32" | od -An -tx1)" == "$(printf '\033]7501;state=idle:app=%s\033\\' "$n32" | od -An -tx1)" ]] || fail "32 refused"
[[ "$(_agents_hm_report idle "${n32}3" | od -An -tx1)" == "$(printf '\033]7501;state=idle:app=agent\033\\' | od -An -tx1)" ]] || fail "33 passed"
pass "the report's app is the spec's: [A-Za-z0-9_.+-], 32 at most"

echo "All hcmirror tests passed"
