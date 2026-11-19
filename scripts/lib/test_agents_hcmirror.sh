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
# (wait.1, wait.2 … one a call; then it fails), and an attach. pane.fail N
# makes the next N `pane get` fail. hang.snapshot
# makes the snapshot hang; wait.hang makes `agent wait` hang (its pid in
# wait.pid), and the attach then lasts until that wait has started.
cat > "$tmp/herdr" <<'EOF2'
#!/bin/bash
{ echo "--"; printf '%s\n' "$@"; } >> "$FAKE/herdr.calls"
case "$1 $2" in
    "api snapshot") [[ ! -f "$FAKE/hang.snapshot" ]] || exec sleep 30
                    cat "$FAKE/snap.json" ;;
    "pane get")     n="$(cat "$FAKE/pane.fail" 2>/dev/null || echo 0)"
                    if [[ $n -gt 0 ]]; then echo $((n - 1)) > "$FAKE/pane.fail"; exit 1; fi
                    cat "$FAKE/pane.json" 2>/dev/null || exit 1 ;;
    "pane process-info") cat "$FAKE/procinfo.json" 2>/dev/null || exit 1 ;;
    "agent wait")   if [[ -f "$FAKE/wait.hang" ]]; then echo "$$" > "$FAKE/wait.pid"; exec sleep 30; fi
                    n=$(( $(cat "$FAKE/wait.n" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$FAKE/wait.n"
                    [[ -f "$FAKE/wait.$n" ]] || exit 1
                    cat "$FAKE/wait.$n" ;;
    "agent attach") echo "$*" >> "$FAKE/attach.calls"; echo "$$" > "$FAKE/attach.pid"
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
    rm -f "${FAKE:?}"/*.calls "${FAKE:?}"/wait.* "${FAKE:?}"/attach.rc "${FAKE:?}"/attach.pid "${FAKE:?}"/report.* "${FAKE:?}"/pane.json "${FAKE:?}"/pane.fail "${FAKE:?}"/hang.* "${AGENTS_RUN_DIR:?}"/hc-pane.*
    rm -rf "${AGENTS_RUN_DIR:?}/hc-mirror.lock" "${AGENTS_RUN_DIR:?}/hc-mirror.started" "${AGENTS_RUN_DIR:?}/hc-mirror.off" \
        "${AGENTS_RUN_DIR:?}/hc-mirror.dirty" "${AGENTS_RUN_DIR:?}/hc-mirror.wait" "${AGENTS_RUN_DIR:?}"/hc-mirror-wait.* \
        "${AGENTS_RUN_DIR:?}/herdr-labels.lock" "${AGENTS_RUN_DIR:?}/herdr-labels.dirty" \
        "${AGENTS_RUN_DIR:?}/hc-mirror-fit.lock" "${AGENTS_RUN_DIR:?}/hc-mirror-fit.dirty"
    unset AGENTS_NOW
    RUNNING=true
    echo '{"jsonrpc":"2.0","id":1,"result":{"terminals":[]}}' > "$FAKE/list.json"
    echo '{"terminals":[]}' > "$FAKE/ls.json"
}
calls() { [[ ! -f "$FAKE/$1.calls" ]] || tr '\n' ' ' < "$FAKE/$1.calls"; }
# snap 'PANE|AGENT|STATUS|CWD[|TITLE]' …  (layout rects from RECT="PANE:W:H …")
snap() {
    local p arr="" lay="" r id ag st cw ti w h
    for p in "$@"; do
        IFS='|' read -r id ag st cw ti <<<"$p"
        arr="$arr${arr:+,}$(jq -nc --arg id "$id" --arg ag "$ag" --arg st "$st" --arg cw "$cw" --arg ti "$ti" \
            '{pane_id:$id,agent:$ag,agent_status:$st,cwd:$cw,foreground_cwd:$cw} + (if $ti == "" then {} else {terminal_title_stripped:$ti} end)')"
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
[[ "$r" == "run --bg --json --no-parent --no-notify --rm --name proj-a --label tuidev_mirror=p1 --cwd $tmp/proj-a -- /usr/bin/env HERDR_BIN_PATH=$tmp/herdr HERDR_SOCKET_PATH=$HOME/.config/herdr/herdr.sock bash $AGENTS_PATH hc _mirror p1 120 40 120 40" ]] \
    || fail "mirror command: $r"
[[ "$out" == *"mirror p1 (claude, proj-a)"* ]] || fail "output: $out"
[[ -f "$AGENTS_RUN_DIR/hc-mirror.started/p1" ]] || fail "no start time kept for p1"

# A mirror is named after its session's task title, so the phone tells two
# sessions of one project apart; a title with nothing to name it by, or none,
# leaves the directory's name.
reset; snap "p1|claude|working|$tmp/proj-a|Fix Login redirect!" "p2|claude|idle|$tmp/proj-a|API docs" "p3|claude|idle|$tmp/proj-a|***" "p4|codex|idle|$tmp/proj-a"
agents_hc_mirror_sync >/dev/null 2>&1 || fail "sync with titles failed"
r="$(runs)"
[[ "$r" == *"--name fix-login-redirect --label tuidev_mirror=p1 "* ]] || fail "a mirror named after its title: $r"
[[ "$r" == *"--name api-docs --label tuidev_mirror=p2 "* ]] || fail "a second session of the project, by its own title: $r"
[[ "$r" == *"--name proj-a --label tuidev_mirror=p3 "* && "$r" == *"--name proj-a --label tuidev_mirror=p4 "* ]] || fail "no usable title: the directory's name: $r"
[[ "$(_agents_hm_name "A title far longer than any name herdr-core takes for one terminal" "$tmp/proj-a")" =~ ^[a-z0-9-]{1,30}$ ]] || fail "a long title is cut to a legal name"
[[ "$(_agents_hm_title $'Fix \033]0;x\007login' | od -An -c | tr -s ' \n' ' ')" == " 033 ] 2 ; F i x ] 0 ; x l o g i n 033 \\ " ]] \
    || fail "the terminal title: one OSC 2, no control character from the title: $(_agents_hm_title $'Fix \033]0;x\007login' | od -An -c)"
[[ -z "$(_agents_hm_title "")" ]] || fail "no title: nothing written"
pass "a mirror is named after its session's task title, and its terminal takes that title"
pass "an agent pane with no mirror gets one (--rm): name, label, cwd, size from its layout, Herdr's paths"

reset; RECT=""; snap "p2|codex|idle|$tmp/proj-b"
agents_hc_mirror_sync -q
[[ "$(runs)" == *"_mirror p2 160 50 160 50" ]] || fail "default size: $(runs)"
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
# The mirror's terminal takes the session's title, at once and when a change brings a new one.
reset; echo '{"result":{"pane":{"agent":"claude","agent_status":"idle","terminal_title_stripped":"Fix login"}}}' > "$FAKE/pane.json"
printf '{"result":{"agent":{"agent_status":"working","terminal_title_stripped":"Fix login redirect"}}}\n' > "$FAKE/wait.1"
got="$(_agents_hm_follow p1 | od -An -tx1 | tr -d ' \n')"
want="$({ printf '\033]7501;state=idle:app=claude\033\\\033]2;Fix login\033\\'; printf '\033]7501;state=working:app=claude\033\\\033]2;Fix login redirect\033\\'; } | od -An -tx1 | tr -d ' \n')"
[[ "$got" == "$want" ]] || fail "follow sets the title: $got"
pass "follow sets the terminal's title to the session's, then again when a change carries a new one"

reset; echo '{"result":{"pane":{"agent":"","agent_status":"idle"}}}' > "$FAKE/pane.json"
out="$(_agents_hm_follow p1)"; [[ -z "$out" && "$(calls herdr)" != *"agent wait"* ]] || fail "follow of a pane with no agent: $out"
reset
out="$(_agents_hm_follow p1)"; [[ -z "$out" && "$(calls herdr)" != *"agent wait"* ]] || fail "follow of a missing pane: $out"
pass "follow of a pane with no agent reports nothing and ends"

# The follower ends when its attach is gone: it looks before each wait.
reset; echo '{"result":{"pane":{"agent":"claude","agent_status":"idle"}}}' > "$FAKE/pane.json"; st working 1; st idle 2
# A pid that has ended. Not a killed `sleep &`: bash 3.2 can take the signal
# in its fork before the exec and run this script's EXIT trap there.
gone="$(/bin/sh -c 'echo $$')"
out="$(_agents_hm_follow p1 "$gone")"
[[ "$(calls herdr)" != *"agent wait"* ]] || fail "the follower waited for a pane whose attach is gone: $(calls herdr)"
[[ "$out" == *"state=idle"* ]] || fail "the follower did not report before it ended: $out"
ls "$AGENTS_RUN_DIR"/hc-mirror.wait/* >/dev/null 2>&1 && fail "a follower with no attach left its file"
# While the attach lives, a follower Herdr does not answer asks again, after
# 2 s doubling to 60 s (the pause is a stand-in that only counts; the tenth
# ends the test's follower), and a wait that worked starts the doubling over.
# Each time Herdr answers again, the pane's state now is reported.
reset; echo '{"result":{"pane":{"agent":"claude","agent_status":"idle"}}}' > "$FAKE/pane.json"
echo 2 > "$FAKE/pane.fail"; st working 1; st blocked 3
out="$( _agents_hm_pause() { echo "$1" >> "$FAKE/pause.calls"; [[ "$(grep -c . "$FAKE/pause.calls")" -lt 10 ]] || exit 0; }
        _agents_hm_follow p1 "$$" )"
[[ "$(calls pause)" == "2 4 2 2 4 8 16 32 60 60 " ]] || fail "the follower's pauses: $(calls pause)"
[[ "$(printf '%s' "$out" | grep -o 'state=[a-z]*' | tr '\n' ' ')" == "state=idle state=working state=idle state=blocked state=idle state=idle "* ]] \
    || fail "the follower's reports across Herdr's misses: $(printf '%s' "$out" | grep -o 'state=[a-z]*' | tr '\n' ' ')"
[[ "$(grep -cx get "$FAKE/herdr.calls")" -ge 9 ]] || fail "the follower did not ask for the pane again: $(calls herdr)"
# A pane with no agent for now is asked again too.
reset; echo '{"result":{"pane":{"agent":"","agent_status":""}}}' > "$FAKE/pane.json"
out="$( _agents_hm_pause() { echo "$1" >> "$FAKE/pause.calls"; [[ "$(grep -c . "$FAKE/pause.calls")" -lt 3 ]] || exit 0; }
        _agents_hm_follow p1 "$$" )"
[[ -z "$out" && "$(calls pause)" == "2 4 8 " ]] || fail "a follower of a pane with no agent for now: $(calls pause) $out"
# With its attach gone, a miss ends it: no pause, no report.
reset; echo '{"result":{"pane":{"agent":"claude","agent_status":"idle"}}}' > "$FAKE/pane.json"; echo 5 > "$FAKE/pane.fail"
out="$( _agents_hm_pause() { echo "$1" >> "$FAKE/pause.calls"; }; _agents_hm_follow p1 "$gone" )"
[[ -z "$out" && ! -e "$FAKE/pause.calls" && "$(grep -cx get "$FAKE/herdr.calls")" == 1 ]] || fail "a follower whose attach is gone went on after a miss: $(calls pause) $(calls herdr)"
# The attach ends during a pause: it ends right after it.
reset; echo '{"result":{"pane":{"agent":"claude","agent_status":"idle"}}}' > "$FAKE/pane.json"; echo 5 > "$FAKE/pane.fail"
# The owner is no child of this shell (one that ended would stay a zombie,
# which kill -0 still finds), and keeps no EXIT trap of this script's.
owner="$( (trap - EXIT; sleep 30 >/dev/null 2>&1 & echo $!) )"
out="$( _agents_hm_pause() { echo "$1" >> "$FAKE/pause.calls"; kill "$owner" 2>/dev/null
            for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do kill -0 "$owner" 2>/dev/null || break; sleep 0.1; done; }
        _agents_hm_follow p1 "$owner" )"
kill "$owner" 2>/dev/null || true
[[ -z "$out" && "$(calls pause)" == "2 " && "$(grep -cx get "$FAKE/herdr.calls")" == 1 ]] || fail "a follower whose attach ended during a pause went on: $(calls pause) $(calls herdr)"
pass "a follower whose attach is gone ends before it waits; while the attach lives, a miss of Herdr's is asked again, 2 s doubling to 60 s"
# A report the terminal does not take ends the follower: at once, or after a change.
reset; echo '{"result":{"pane":{"agent":"claude","agent_status":"idle"}}}' > "$FAKE/pane.json"; st working 1; st blocked 2
(_agents_hm_follow p1 "$$" >&-) 2>/dev/null
[[ "$(calls herdr)" != *"agent wait"* ]] || fail "a follower whose first report failed waited: $(calls herdr)"
ls "$AGENTS_RUN_DIR"/hc-mirror.wait/* >/dev/null 2>&1 && fail "a follower whose first report failed left its file"
reset; echo '{"result":{"pane":{"agent":"claude","agent_status":"idle"}}}' > "$FAKE/pane.json"; st working 1; st blocked 2
( _agents_hm_report() { [[ ! -e "$FAKE/report.1" ]] || return 1; : > "$FAKE/report.1"; }
  _agents_hm_follow p1 "$$" >/dev/null )
[[ "$(grep -cx wait "$FAKE/herdr.calls")" == 1 ]] || fail "a follower whose report failed after a change went on: $(calls herdr)"
ls "$AGENTS_RUN_DIR"/hc-mirror.wait/* >/dev/null 2>&1 && fail "a follower whose report failed left its file"
pass "a report the terminal does not take ends the follower, and it leaves no file"

# --- _mirror ---
# The attach takes the mirror's process (exec), so each call runs in a ( ).
# The follower is a stand-in here that says what it was given; the real one
# is tested with a real mirror process below.
await() { local _; for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30; do [[ ! -s "$1" ]] || return 0; sleep 0.1; done; return 1; }
reset
( _agents_hm_follow() { echo "$*" > "$FAKE/follow.calls"; }
  for bad in "" "p 1" "p;x" "-p"; do
      rc=0; (agents_main hc _mirror "$bad" 100 40 >/dev/null 2>&1) || rc=$?
      [[ "$rc" == 2 ]] || fail "bad pane '$bad': exit $rc"
  done
  for bad in "" x 1x -3; do
      rc=0; (agents_main hc _mirror p1 "$bad" 40 >/dev/null 2>&1) || rc=$?
      [[ "$rc" == 2 ]] || fail "bad cols '$bad': exit $rc"
      rc=0; (agents_main hc _mirror p1 100 "$bad" >/dev/null 2>&1) || rc=$?
      [[ "$rc" == 2 ]] || fail "bad rows '$bad': exit $rc"
  done
  [[ ! -e "$FAKE/herdr.calls" && ! -e "$FAKE/follow.calls" ]] || fail "a bad call reached herdr or started a follower: $(calls herdr) $(calls follow)"
  rc=0; (agents_main hc _mirror p1 100 40 </dev/null >/dev/null 2>&1) || rc=$?
  [[ "$rc" == 0 && "$(cat "$FAKE/attach.calls")" == "agent attach p1" ]] || fail "attach: rc=$rc $(calls attach)"
  await "$FAKE/follow.calls" || fail "no follower started"
  [[ "$(cat "$FAKE/follow.calls")" == "p1 $$" ]] || fail "the follower was not given the pane and the attach's pid: $(calls follow)"
  echo 7 > "$FAKE/attach.rc"
  rc=0; (agents_main hc _mirror p1 100 40 </dev/null >/dev/null 2>&1) || rc=$?
  [[ "$rc" == 7 ]] || fail "attach's exit status: $rc"
) || fail "_mirror"
reset
( _agents_hm_follow() { echo "$*" > "$FAKE/follow.calls"; }
  _agents_hm_tty() { return 0; }; stty() { echo "$*" >> "$FAKE/stty.calls"; }
  PATH=/usr/bin:/bin HERDR_BIN_PATH="$tmp/nope"
  rc=0; out="$(agents_main hc _mirror p1 100 40 </dev/null 2>&1)" || rc=$?
  [[ "$rc" == 127 && "$out" == *"herdr is not installed"* ]] || fail "no herdr: rc=$rc $out"
  sleep 0.2
  [[ ! -e "$FAKE/follow.calls" && ! -e "$FAKE/stty.calls" ]] || fail "no herdr, yet a follower or a size: $(calls follow) $(calls stty)"
) || fail "no herdr"
pass "_mirror refuses a bad pane or size with 2, and 127 with no herdr, starting no follower; otherwise the attach takes its place, its status is the mirror's, and the follower gets the pane and the attach's pid"

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

# --- a burst of events: coalesced, and one snapshot ---
# Syncs that come in while one runs leave a mark and return at once; the one
# running goes again once for all of them. Here each pass is a stand-in that
# counts, and the first one's events are five more syncs.
reset
( _AGENTS_HM_PAUSE=0
  _agents_hm_pass() {
      echo "pass ${3:-asked}" >> "$FAKE/pass.calls"
      [[ "$(grep -c . "$FAKE/pass.calls")" -gt 1 ]] && return 0
      local i; for i in 1 2 3 4 5; do _agents_hm_sync "" -q; done
  }
  _agents_hm_sync '{"given":1}' -q
  [[ "$(cat "$FAKE/pass.calls")" == $'pass {"given":1}\npass asked' ]] || fail "a burst of six syncs: $(calls pass)"
  [[ ! -e "$AGENTS_RUN_DIR/hc-mirror.dirty" && ! -e "$AGENTS_RUN_DIR/hc-mirror.lock" ]] || fail "a coalesced sync left its mark or lock"
) || exit 1
pass "a burst of syncs is two passes: the snapshot given for the first, a fresh one for the one the burst asked for"
# agents herdr sync hands the mirror sync the label sync's snapshot: one
# `herdr api snapshot` for both.
reset; snap "p1|claude|idle|$tmp/proj-a"
agents_main herdr sync -q >/dev/null 2>&1 || true
[[ "$(runs)" == *"_mirror p1 "* ]] || fail "herdr sync -q did not start the mirror: $(calls hc)"
[[ "$(grep -c '^snapshot$' "$FAKE/herdr.calls")" == 1 ]] || fail "herdr sync asked for $(grep -c '^snapshot$' "$FAKE/herdr.calls") snapshots, not one"
# A herdr sync that finds a label sync running leaves both syncs to it: a
# mark, no Herdr call, nothing asked of the core.
reset; snap "p1|claude|idle|$tmp/proj-a"
sleep 60 & holder_pid=$!
mkdir "$AGENTS_RUN_DIR/herdr-labels.lock"
echo "$holder_pid $(_agents_start "$holder_pid")" > "$AGENTS_RUN_DIR/herdr-labels.lock/holder"
agents_main herdr sync -q >/dev/null 2>&1 || fail "a held label lock failed the sync"
[[ -e "$AGENTS_RUN_DIR/herdr-labels.dirty" && ! -e "$FAKE/hc.calls" && "$(calls herdr)" != *snapshot* ]] \
    || fail "a herdr sync left to a running one still synced: $(calls hc) $(calls herdr)"
kill "$holder_pid" 2>/dev/null; wait "$holder_pid" 2>/dev/null || true; holder_pid=""
# Names off: no label sync, so the mirror sync asks for its own.
reset; snap "p1|claude|idle|$tmp/proj-a"
AGENTS_HERDR_NAMES=0 agents_main herdr sync -q >/dev/null 2>&1 || true
[[ "$(runs)" == *"_mirror p1 "* && "$(grep -c '^snapshot$' "$FAKE/herdr.calls")" == 1 ]] || fail "names off: the mirrors were not synced: $(calls hc)"
pass "agents herdr sync: the mirror sync reads the label sync's snapshot, and a sync left to a running one leaves the mirrors to it"
# off holds the sync's lock: a sync that came in meanwhile is taken up when it lets go.
reset; snap "p1|claude|idle|$tmp/proj-a" "p2|codex|idle|$tmp/proj-b"; : > "$AGENTS_RUN_DIR/hc-mirror.dirty"
agents_hc_mirror_off p2 >/dev/null 2>&1 || fail "off failed"
[[ "$(runs)" == *"_mirror p1 "* && "$(runs)" != *"_mirror p2 "* && ! -e "$AGENTS_RUN_DIR/hc-mirror.dirty" ]] || fail "off did not take up the sync that came in: $(runs)"
pass "off takes up a sync that found its lock held"

# --- the followers' files ---
# One a pane, in hc-mirror.wait/: a sync removes those of panes with no agent
# with their start times. The random names of 3.25.0 and before go once, the
# first time the folder is made.
reset; snap "p1|claude|idle|$tmp/proj-a"
: > "$AGENTS_RUN_DIR/hc-mirror-wait.AbC123"; : > "$AGENTS_RUN_DIR/hc-mirror-wait.zz9XyQ"
agents_hc_mirror_sync -q -n
[[ -e "$AGENTS_RUN_DIR/hc-mirror-wait.AbC123" && ! -d "$AGENTS_RUN_DIR/hc-mirror.wait" ]] || fail "a dry sync swept the old files"
mkdir -p "$AGENTS_RUN_DIR/hc-mirror.started"; echo 1 > "$AGENTS_RUN_DIR/hc-mirror.started/p9"
agents_hc_mirror_sync -q
[[ ! -e "$AGENTS_RUN_DIR/hc-mirror-wait.AbC123" && ! -e "$AGENTS_RUN_DIR/hc-mirror-wait.zz9XyQ" && -d "$AGENTS_RUN_DIR/hc-mirror.wait" ]] \
    || fail "the old followers' files were not swept: $(ls "$AGENTS_RUN_DIR")"
: > "$AGENTS_RUN_DIR/hc-mirror-wait.Q1w2E3"
: > "$AGENTS_RUN_DIR/hc-mirror.wait/p1"; : > "$AGENTS_RUN_DIR/hc-mirror.wait/p9"; echo 1 > "$AGENTS_RUN_DIR/hc-mirror.started/p9"
agents_hc_mirror_sync -q
[[ -e "$AGENTS_RUN_DIR/hc-mirror-wait.Q1w2E3" ]] || fail "the old files were swept again"
[[ -e "$AGENTS_RUN_DIR/hc-mirror.wait/p1" && ! -e "$AGENTS_RUN_DIR/hc-mirror.wait/p9" && ! -e "$AGENTS_RUN_DIR/hc-mirror.started/p9" ]] \
    || fail "a pane with no agent kept its follower's file or start time: $(ls -R "$AGENTS_RUN_DIR")"
pass "a sync removes a gone pane's follower file with its start time, and the old random-named ones once"

# --- the size ---
reset
( _agents_hm_tty() { return 0; }; _agents_hm_follow() { echo "$*" > "$FAKE/follow.calls"; }
  stty() { [[ "$1" != size ]] || { echo "120 200"; return 0; }; echo "$*" >> "$FAKE/stty.calls"; return "${STTY_RC:-0}"; }
  for sz in "3 1:cols 20 rows 5" "120 40:cols 120 rows 40" "99999 0040:cols 1000 rows 40" "100 123456789012345678901:cols 100 rows 500"; do
      rm -f "$FAKE/stty.calls" "$FAKE/attach.calls"
      # shellcheck disable=SC2086  # COLS ROWS, two words
      (agents_main hc _mirror p1 ${sz%%:*} </dev/null >/dev/null 2>&1) || fail "_mirror ${sz%%:*} failed"
      [[ "$(cat "$FAKE/stty.calls")" == "${sz#*:}" ]] || fail "size ${sz%%:*}: $(cat "$FAKE/stty.calls")"
      [[ -s "$FAKE/attach.calls" ]] || fail "size ${sz%%:*}: not attached"
  done
  rm -f "$FAKE/attach.calls" "$FAKE/follow.calls"; rc=0
  (STTY_RC=1 agents_main hc _mirror p1 120 40 </dev/null >/dev/null 2>&1) || rc=$?
  sleep 0.2
  [[ "$rc" == 1 && ! -e "$FAKE/attach.calls" && ! -e "$FAKE/follow.calls" ]] || fail "a tty that took no size was attached or followed: rc=$rc"
) || fail "size"
reset
( stty() { echo "$*" >> "$FAKE/stty.calls"; return 1; }; _agents_hm_follow() { :; }
  (agents_main hc _mirror p1 3 1 </dev/null >/dev/null 2>&1) || fail "_mirror with no tty failed"
  [[ ! -e "$FAKE/stty.calls" && -s "$FAKE/attach.calls" ]] || fail "no tty: stty=$(calls stty) attach=$(calls attach)"
) || fail "no tty"
pass "_mirror sizes its tty to the pane, kept within 20x5 and 1000x500; no attach when the tty takes no size; no tty, no stty"

# --- the pane's own size, and getting it back ---
# A pane's terminal can be a column or a row smaller than its place in the
# layout; a size that is not near the place is not the pane's own.
cat > "$FAKE/procinfo.json" <<<'{"result":{"process_info":{"shell_pid":4242}}}'
( ps() { echo " null"; }
  stty() { cat "$FAKE/stty.size"; }
  echo "39 119" > "$FAKE/stty.size"
  [[ "$(_agents_hm_pane_size p1 120 40)" == "119 39" ]] || fail "a pane a column and a row smaller: $(_agents_hm_pane_size p1 120 40)"
  echo "40 120" > "$FAKE/stty.size"
  [[ "$(_agents_hm_pane_size p1 120 40)" == "120 40" ]] || fail "a pane as large as its place"
  for odd in "120 200" "31 43" "41 120" "x y" ""; do
      echo "$odd" > "$FAKE/stty.size"
      [[ "$(_agents_hm_pane_size p1 120 40)" == "120 40" ]] || fail "size '$odd' was taken for the pane's own"
  done
  ps() { echo "??"; }; echo "39 119" > "$FAKE/stty.size"
  [[ "$(_agents_hm_pane_size p1 120 40)" == "120 40" ]] || fail "a shell with no tty"
) || fail "pane size"
rm -f "$FAKE/procinfo.json"
[[ "$(_agents_hm_pane_size p1 120 40)" == "120 40" ]] || fail "Herdr did not say the pane's process"
reset; snap "p1|claude|idle|$tmp/proj-a"; cat > "$FAKE/procinfo.json" <<<'{"result":{"process_info":{"shell_pid":4242}}}'
( ps() { echo "null"; }; stty() { echo "49 159"; }
  RECT="p1:160:50"; snap "p1|claude|idle|$tmp/proj-a"; agents_hc_mirror_sync -q
  [[ "$(runs)" == *"_mirror p1 159 49 160 50" ]] || fail "the mirror did not start at the pane's own size: $(runs)"
) || fail "start size"
rm -f "$FAKE/procinfo.json"
# The core gives a terminal its own size back when its last viewer leaves:
# only then is the pane's size set again, from its place as it is now.
( _AGENTS_HM_TTY=/dev/null _AGENTS_HM_BASE="120 200" _AGENTS_HM_COLS=119 _AGENTS_HM_ROWS=39 _AGENTS_HM_DC=1 _AGENTS_HM_DR=1
  stty() { if [[ "$1" == size ]]; then cat "$FAKE/stty.size"; else echo "$*" >> "$FAKE/stty.calls"; fi; }
  RECT="p1:120:40"; snap "p1|claude|idle|$tmp/proj-a"
  for viewer in "31 43" "39 119" "50 80"; do
      echo "$viewer" > "$FAKE/stty.size"; _agents_hm_resized p1
      [[ ! -e "$FAKE/stty.calls" ]] || fail "size $viewer (a viewer's, or the pane's own) was changed: $(calls stty)"
  done
  echo "120 200" > "$FAKE/stty.size"; _agents_hm_resized p1
  [[ "$(cat "$FAKE/stty.calls")" == "cols 119 rows 39" ]] || fail "back at the core's size: $(calls stty)"
  rm -f "$FAKE/stty.calls"; RECT="p1:90:30"; snap "p1|claude|idle|$tmp/proj-a"; _agents_hm_resized p1
  [[ "$(cat "$FAKE/stty.calls")" == "cols 89 rows 29" ]] || fail "the pane's place changed meanwhile: $(calls stty)"
  rm -f "$FAKE/stty.calls"; printf 'garbage\n' > "$FAKE/snap.json"; _agents_hm_resized p1
  [[ "$(cat "$FAKE/stty.calls")" == "cols 119 rows 39" ]] || fail "Herdr did not answer: $(calls stty)"
  rm -f "$FAKE/stty.calls"; _AGENTS_HM_BASE=""; _agents_hm_resized p1
  [[ ! -e "$FAKE/stty.calls" ]] || fail "with no size from the core, a size was set"
) || fail "resized"
pass "a mirror starts at the pane's own size; a terminal back at the core's size gets the pane's size again, a viewer's size is left alone"

# --- a focus at the desk takes the size back: agents hc mirror fit ---
# The phone may keep a session attached while it shows its Inbox; a fit sets
# the mirror's terminal (the attach's tty) to the pane's place less its
# border, while the viewer stays. Here the attach's pid is 4242, ps says its
# tty is /dev/null, and stty reads $FAKE/stty.size and logs what it sets.
# fitterm PANE PID [ARGV TAIL...] — a live mirror of PANE, started as `_mirror ARGV TAIL`.
fitterm() {
    local pane="$1" pid="$2"; shift 2
    jq -nc --arg p "$pane" --arg pid "$pid" --args '{jsonrpc:"2.0",id:1,result:{terminals:[
        {address:"t1",name:"m",state:"live",labels:{tuidev_mirror:$p},pid:($pid | tonumber? // $pid),
         argv:(["/usr/bin/env","bash","agents","hc","_mirror",$p] + $ARGS.positional)}]}}' "$@" > "$FAKE/list.json"
}
focus() { jq -c --arg p "$1" '.result.snapshot.focused_pane_id = $p' "$FAKE/snap.json" > "$FAKE/snap.new" && mv "$FAKE/snap.new" "$FAKE/snap.json"; }
started() { mkdir -p "$AGENTS_RUN_DIR/hc-mirror.started"; echo 1 > "$AGENTS_RUN_DIR/hc-mirror.started/$(_agents_hm_file_name "$1")"; }
( ps() { case "$*" in *args=*) echo "herdr agent attach p1 p2 p9" ;; *) echo " null" ;; esac; }
  stty() { if [[ "$1" == size ]]; then cat "$FAKE/stty.size"; else echo "$*" >> "$FAKE/stty.calls"; fi; }
  reset; RECT="p1:120:40 p2:80:24"; snap "p1|claude|idle|$tmp/proj-a" "p2|claude|idle|$tmp/proj-b"; focus p1
  fitterm p1 4242 119 39 120 40
  # The phone's size; the fit sets the pane's place less its border, 1x1 here.
  echo "31 43" > "$FAKE/stty.size"
  out="$(agents_main hc mirror fit p1 2>&1)" || fail "fit failed: $out"
  [[ "$(calls stty)" == "cols 119 rows 39 " && "$out" == "p1: 119x39, its place in the layout" ]] || fail "fit: $(calls stty) / $out"
  # No PANE: the one Herdr has focused.
  rm -f "$FAKE/stty.calls"; out="$(agents_main hc mirror fit 2>&1)"
  [[ "$(calls stty)" == "cols 119 rows 39 " ]] || fail "fit, the focused pane: $(calls stty) / $out"
  # Its place now, not the one it started in; a mirror started without one has no border.
  rm -f "$FAKE/stty.calls"; RECT="p1:150:45"; snap "p1|claude|idle|$tmp/proj-a"; focus p1; fitterm p1 4242 119 39
  agents_main hc mirror fit p1 >/dev/null 2>&1
  [[ "$(calls stty)" == "cols 150 rows 45 " ]] || fail "fit, a new place and no border: $(calls stty)"
  pass "fit: the mirror's terminal gets the pane's place now, less the border it started with; no PANE is the focused one"

  # At its size already: nothing set, so the follower gets no WINCH for nothing.
  rm -f "$FAKE/stty.calls"; RECT="p1:120:40"; snap "p1|claude|idle|$tmp/proj-a"; focus p1; fitterm p1 4242 119 39 120 40
  echo "39 119" > "$FAKE/stty.size"
  out="$(agents_main hc mirror fit p1 2>&1)"
  [[ ! -e "$FAKE/stty.calls" && "$out" == "p1: at its place's size already (119x39)" ]] || fail "fit at its size: $(calls stty) / $out"
  pass "fit: a pane at its size already is left alone"
  # The core's pid now belongs to another program (reused since it was
  # listed): its terminal is not touched.
  rm -f "$FAKE/stty.calls"; echo "31 43" > "$FAKE/stty.size"
  # (the stub is a function of its own: bash 3.2 cannot parse a case inside $( ))
  ps_reused() { if [[ "$*" == *args=* ]]; then echo "vim notes.txt"; else echo " null"; fi; }
  out="$( ps() { ps_reused "$@"; }; agents_main hc mirror fit p1 2>&1 )" || true
  [[ ! -e "$FAKE/stty.calls" && "$out" == *"cannot be read; nothing changed"* ]] || fail "fit on a reused pid: $(calls stty) / $out"
  pass "fit: a pid that is no longer the pane's attach is never resized"

  # A pane with no mirror: nothing; by hand it says so. The hook's -q asks
  # no core for a pane no sync gave a mirror.
  echo "31 43" > "$FAKE/stty.size"; fitterm p2 4242 79 24 80 24
  rm -f "$FAKE"/*.calls; out="$(agents_main hc mirror fit p1 2>&1)"
  [[ ! -e "$FAKE/stty.calls" && "$out" == *"p1 has no mirror; nothing to fit"* ]] || fail "fit, no mirror: $(calls stty) / $out"
  terms "t1|x|live|p1"
  rm -f "$FAKE"/*.calls; agents_main hc mirror fit p1 >/dev/null 2>&1
  [[ ! -e "$FAKE/stty.calls" ]] || fail "fit, a mirror with no pid: $(calls stty)"
  fitterm p1 4242 119 39 120 40; rm -f "$FAKE"/*.calls
  out="$(agents_main hc mirror fit -q 2>&1)"
  [[ -z "$out" && ! -e "$FAKE/hc.calls" && ! -e "$FAKE/stty.calls" ]] || fail "fit -q, no start time: $(calls hc) / $out"
  started p1; rm -f "$FAKE"/*.calls
  out="$(agents_main hc mirror fit -q 2>&1)"
  [[ -z "$out" && "$(calls stty)" == "cols 119 rows 39 " ]] || fail "fit -q, a mirrored pane: $(calls stty) / $out"
  rc=0; out="$(agents_main hc mirror fit 'p1;x' 2>&1)" || rc=$?
  [[ $rc -eq 2 && "$out" == *"not a pane id"* ]] || fail "fit, a bad id: $rc $out"
  rc=0; agents_main hc mirror fit p1 p2 >/dev/null 2>&1 || rc=$?; [[ $rc -eq 2 ]] || fail "fit, two panes: $rc"
  pass "fit: a pane with no mirror is ignored; the hook's -q asks no core for a pane no sync mirrored"

  # The off switch: the hook does nothing at all; by hand it still fits.
  rm -f "$FAKE"/*.calls
  AGENTS_HC_MIRROR_FIT=0 agents_main hc mirror fit -q >/dev/null 2>&1
  [[ ! -e "$FAKE/herdr.calls" && ! -e "$FAKE/hc.calls" && ! -e "$FAKE/stty.calls" ]] || fail "AGENTS_HC_MIRROR_FIT=0: $(calls herdr) $(calls hc) $(calls stty)"
  AGENTS_HC_MIRROR_FIT=0 agents_main hc mirror fit p1 >/dev/null 2>&1
  [[ "$(calls stty)" == "cols 119 rows 39 " ]] || fail "AGENTS_HC_MIRROR_FIT=0, by hand: $(calls stty)"
  rm -f "$FAKE"/*.calls
  AGENTS_HC_MIRROR=0 agents_main hc mirror fit -q >/dev/null 2>&1
  [[ ! -e "$FAKE/hc.calls" && ! -e "$FAKE/stty.calls" ]] || fail "mirrors off: a fit asked the core: $(calls hc)"
  pass "AGENTS_HC_MIRROR_FIT=0: the focus hook fits nothing and asks nothing; by hand it still fits; nothing with mirrors off"

  # One sizing: the follower's WINCH and the fit both go through _agents_hm_set_size.
  ( _agents_hm_set_size() { echo "set $*" >> "$FAKE/set.calls"; return 0; }
    rm -f "$FAKE"/*.calls
    agents_main hc mirror fit p1 >/dev/null 2>&1
    _AGENTS_HM_TTY=/dev/null _AGENTS_HM_BASE="120 200" _AGENTS_HM_COLS=119 _AGENTS_HM_ROWS=39 _AGENTS_HM_DC=1 _AGENTS_HM_DR=1
    echo "120 200" > "$FAKE/stty.size"; _agents_hm_resized p1
    [[ "$(cat "$FAKE/set.calls")" == $'set /dev/null 120 40 1 1\nset /dev/null 120 40 1 1 119 39' ]] || fail "one sizing: $(cat "$FAKE/set.calls")"
  ) || exit 1
  # No loop: what a fit set is no core size, so the follower's WINCH for it
  # sets nothing; and a fit after the follower set the size sets nothing.
  rm -f "$FAKE"/*.calls
  ( _AGENTS_HM_TTY=/dev/null _AGENTS_HM_BASE="120 200" _AGENTS_HM_COLS=119 _AGENTS_HM_ROWS=39 _AGENTS_HM_DC=1 _AGENTS_HM_DR=1
    echo "39 119" > "$FAKE/stty.size"; _agents_hm_resized p1
    agents_main hc mirror fit p1 >/dev/null 2>&1
    [[ ! -e "$FAKE/stty.calls" ]] || fail "a loop: $(calls stty)" ) || exit 1
  pass "one sizing for the follower and the fit, and no loop between them"
) || exit 1

# A burst of focus events: fits that come in while one runs leave a mark and
# return at once; the running one goes again once for all of them.
reset
( _agents_hm_fit_pass() {
      echo "pass" >> "$FAKE/pass.calls"
      [[ "$(grep -c . "$FAKE/pass.calls")" -gt 1 ]] && return 0
      local i; for i in 1 2 3 4 5; do agents_hc_mirror_fit -q; done
  }
  agents_hc_mirror_fit -q
  [[ "$(grep -c . "$FAKE/pass.calls")" == 2 ]] || fail "a burst of six fits: $(grep -c . "$FAKE/pass.calls") passes"
  [[ ! -e "$AGENTS_RUN_DIR/hc-mirror-fit.dirty" && ! -e "$AGENTS_RUN_DIR/hc-mirror-fit.lock" ]] || fail "a coalesced fit left its mark or lock"
) || exit 1
pass "a burst of six fits is two passes, the second for the pane focused by then"

# The plugin's pane.focused hook: one file test decides; agents only for a
# pane a sync mirrored.
plugin="$REPO_DIR/configs/herdr/plugins/tuidev-link"
cat > "$tmp/agents-stub" <<'EOF2'
#!/bin/sh
printf '%s\n' "$*" >> "$FAKE/plugin.calls"
EOF2
chmod +x "$tmp/agents-stub"
reset
phook() { ( cd "$plugin" && env HERDR_PANE_ID="$1" AGENTS_BIN="$tmp/agents-stub" AGENTS_RUN_DIR="$AGENTS_RUN_DIR" sh run.sh fit ); }
phook p1; [[ ! -e "$FAKE/plugin.calls" ]] || fail "hook: a pane no sync mirrored ran agents"
started 'w1:p1'; phook 'w1:p1'
[[ "$(cat "$FAKE/plugin.calls")" == "hc mirror fit -q" ]] || fail "hook: a mirrored pane: $(cat "$FAKE/plugin.calls" 2>/dev/null)"
rm -f "$FAKE/plugin.calls"; started 'x_y'; phook 'x;y'; phook ''
[[ ! -e "$FAKE/plugin.calls" ]] || fail "hook: a bad or no pane id ran agents"
[[ "$(grep -A1 '^on = "pane.focused"' "$plugin/herdr-plugin.toml")" == *'"run.sh", "fit"'* ]] \
    || fail "the plugin has no pane.focused hook that runs fit"
pass "plugin: pane.focused runs agents hc mirror fit -q only for a pane a sync mirrored"

# Status says when a mirrored pane is not at its place's size.
reset; RECT="p1:120:40"; snap "p1|claude|idle|$tmp/proj-a"; terms "t1|m|live|p1"
cat > "$FAKE/procinfo.json" <<<'{"result":{"process_info":{"shell_pid":4242}}}'
( ps() { case "$*" in *args=*) echo "herdr agent attach p1 p2 p9" ;; *) echo " null" ;; esac; }; stty() { cat "$FAKE/stty.size"; }
  echo "31 43" > "$FAKE/stty.size"
  out="$(agents_main hc mirror 2>&1)"
  [[ "$out" == *"mirrored as m; phone-sized: 43x31 of 120x40 (agents hc mirror fit p1)"* ]] || fail "status, phone-sized: $out"
  echo "39 119" > "$FAKE/stty.size"
  out="$(agents_main hc mirror 2>&1)"
  [[ "$out" == *"mirrored as m" && "$out" != *"phone-sized"* ]] || fail "status, at its size: $out"
) || exit 1
rm -f "$FAKE/procinfo.json"
pass "status names a phone-sized pane and the command that fits it"

# --- the follower ends with the attach ---
# Nothing kills the follower by hand: the terminal's hangup, sent to the
# mirror's process group when the attach ends, does. Here the mirror is a real
# process in its own group, and the test sends that hangup.
reset; echo '{"result":{"pane":{"agent":"claude","agent_status":"idle"}}}' > "$FAKE/pane.json"; : > "$FAKE/wait.hang"
set -m
bash "$REPO_DIR/bin/agents" hc _mirror p1 100 40 </dev/null >/dev/null 2>&1 &
mpid=$!
set +m
rc=0; wait "$mpid" || rc=$?
[[ "$rc" == 0 && "$(cat "$FAKE/attach.calls" 2>/dev/null)" == "agent attach p1" ]] || fail "the mirror did not attach: rc=$rc"
[[ "$(cat "$FAKE/attach.pid")" == "$mpid" ]] || fail "the attach did not take the mirror's process: $(cat "$FAKE/attach.pid") vs $mpid"
wpid="$(cat "$FAKE/wait.pid" 2>/dev/null)"
[[ "$wpid" =~ ^[0-9]+$ ]] || fail "the wait never started"
kill -0 "$wpid" 2>/dev/null || fail "the wait ended before any hangup"
[[ -f "$AGENTS_RUN_DIR/hc-mirror.wait/p1" ]] || fail "the follower's file is not the pane's: $(ls -R "$AGENTS_RUN_DIR")"
kill -HUP -- "-$mpid" 2>/dev/null || fail "no process group to hang up"
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30; do
    kill -0 "$wpid" 2>/dev/null || break; sleep 0.1
done
! kill -0 "$wpid" 2>/dev/null || { kill "$wpid" 2>/dev/null; fail "herdr agent wait outlived the mirror's hangup"; }
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do ls "$AGENTS_RUN_DIR"/hc-mirror.wait/* >/dev/null 2>&1 || break; sleep 0.1; done
ls "$AGENTS_RUN_DIR"/hc-mirror.wait/* >/dev/null 2>&1 && fail "the follower left its file: $(ls -R "$AGENTS_RUN_DIR")"
pass "the attach takes the mirror's process; the follower's file is the pane's; the hangup of its group ends the follower and its herdr agent wait, and no file is left"
# A follower in a pause (Herdr did not answer) ends with the hangup at once,
# its sleep with it: the pause is a job, as the wait is.
reset; echo 100 > "$FAKE/pane.fail"; _AGENTS_HM_RETRY=30
set -m
( trap - EXIT; _agents_hm_follow p1 "$$" ) </dev/null >/dev/null 2>&1 &
fpid=$!
set +m
_AGENTS_HM_RETRY=2
await "$FAKE/herdr.calls" || fail "the follower never asked Herdr"
sleep 0.5
kill -0 "$fpid" 2>/dev/null || fail "the follower ended after one miss of Herdr's"
t0=$SECONDS
kill -HUP -- "-$fpid" 2>/dev/null || fail "no process group to hang up"
rc=0; wait "$fpid" || rc=$?
[[ $((SECONDS - t0)) -le 3 ]] || fail "a follower in a pause outlived its hangup by $((SECONDS - t0)) s"
[[ "$(grep -cx get "$FAKE/herdr.calls")" == 1 ]] || fail "the follower asked again before its pause ended: $(calls herdr)"
pass "a follower pausing after a miss of Herdr's ends with the terminal's hangup at once"

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

# --- the phone status line the menu shows ---
reset; RUNNING=false
[[ "$(_agents_hc_phone)" == $'down\t-\t0' ]] || fail "no core: $(_agents_hc_phone)"
[[ ! -s "$FAKE/hc.calls" ]] || fail "a core that is down was asked: $(calls hc)"
[[ -z "$(AGENTS_HC_MIRROR=0 _agents_hc_phone)" ]] || fail "AGENTS_HC_MIRROR=0 and no core still said something"
[[ -z "$(AGENTS_HC_BIN="$tmp/nope" _agents_hc_phone)" ]] || fail "herdr-core not installed still said something"
[[ ! -s "$FAKE/hc.calls" ]] || fail "a status with no core or no herdr-core asked one: $(calls hc)"
reset
[[ "$(_agents_hc_phone)" == $'up\tyes\t0' ]] || fail "no mirrors: $(_agents_hc_phone)"
terms 't4|app|live|%1' 't5|api|live|%2' 't6|old|exited|%3' 't7|plain|live|' 't8|dup|live|%4'
[[ "$(_agents_hc_phone)" == $'up\tyes\t3' ]] || fail "live mirrors only: $(_agents_hc_phone)"
[[ "$(AGENTS_HC_MIRROR=0 _agents_hc_phone)" == $'core\tyes\t0' ]] || fail "a core that runs is shown with mirrors off too: $(AGENTS_HC_MIRROR=0 _agents_hc_phone)"
printf 'garbage\n' > "$FAKE/list.new"; cp "$FAKE/list.json" "$FAKE/list.keep"; mv "$FAKE/list.new" "$FAKE/list.json"
[[ "$(AGENTS_HC_MIRROR=0 _agents_hc_phone)" == $'core\tyes\t0' ]] || fail "mirrors off still needed the core's list of terminals"
mv "$FAKE/list.keep" "$FAKE/list.json"
( _agents_hc_hello() { echo '{"result":{"login_session":{"gui":false}}}'; }
  [[ "$(_agents_hc_phone)" == $'headless\tno\t0' ]] || fail "headless: $(_agents_hc_phone)"
  _agents_hc_is_mac() { return 1; }
  [[ "$(_agents_hc_phone)" == $'up\tno\t3' ]] || fail "gui false off macOS: $(_agents_hc_phone)"
  _agents_hc_hello() { echo '{"result":{}}'; }
  [[ "$(_agents_hc_phone)" == $'up\tunknown\t3' ]] || fail "gui not said: $(_agents_hc_phone)"
) || exit 1
: > "$FAKE/hc.calls"
( _agents_hc_hello() { :; }
  [[ -z "$(_agents_hc_phone)" ]] || fail "a core that did not say hello was guessed at" )
printf '{"jsonrpc":"2.0","id":1,"result":{"terminals":"x"}}\n' > "$FAKE/list.json"
[[ -z "$(_agents_hc_phone)" ]] || fail "a list that is not one was counted: $(_agents_hc_phone)"
: > "$FAKE/hang.connect"; t0=$SECONDS
[[ -z "$(_agents_hc_phone)" && $((SECONDS - t0)) -le $((_AGENTS_HC_WAIT + 2)) ]] || fail "a core that hangs held the status ($((SECONDS - t0)) s)"
pass "the phone status: down without asking the core, headless on macOS, live mirrors counted, nothing when not installed, off, or unanswered"

# --- the menu's cached record: one background check, never waited on ---
reset; terms 't4|app|live|%1'
( unset AGENTS_TESTING
  rm -f "$AGENTS_RUN_DIR/hc-phone.cache"
  [[ -z "$(_agents_hc_phone_rows)" ]] || fail "the first call waited for the check"
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25; do
      [[ -s "$AGENTS_RUN_DIR/hc-phone.cache" ]] && break; sleep 0.2
  done
  [[ "$(_agents_hc_phone_rows)" == $'hc\tup\tyes\t1' ]] || fail "the cached record: $(_agents_hc_phone_rows)"
  sleep 0.3; : > "$FAKE/hc.calls"
  _agents_hc_phone_rows >/dev/null; sleep 0.5
  [[ ! -s "$FAKE/hc.calls" ]] || fail "asked the core again within the TTL: $(calls hc)"
  # An old cache is served while it is checked again.
  printf '%s\n%s\n' "$(( $(date +%s) - 100 ))" $'up\tno\t9' > "$AGENTS_RUN_DIR/hc-phone.cache"
  [[ "$(_agents_hc_phone_rows)" == $'hc\tup\tno\t9' ]] || fail "an old record was not served: $(_agents_hc_phone_rows)"
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25; do
      [[ "$(sed -n 2p "$AGENTS_RUN_DIR/hc-phone.cache")" == $'up\tyes\t1' ]] && break; sleep 0.2
  done
  [[ "$(sed -n 2p "$AGENTS_RUN_DIR/hc-phone.cache")" == $'up\tyes\t1' ]] || fail "an old record was not checked again"
  # Without herdr-core: nothing, and no check starts.
  rm -f "$AGENTS_RUN_DIR/hc-phone.cache"
  [[ -z "$(AGENTS_HC_BIN="$tmp/nope" _agents_hc_phone_rows)" ]]; sleep 0.5
  [[ ! -e "$AGENTS_RUN_DIR/hc-phone.cache" ]] || fail "a check started without herdr-core"
) || exit 1
[[ -z "$(_agents_hc_phone_rows)" ]] || fail "the menu's record was built under AGENTS_TESTING"
pass "the menu's record comes from a cache a background check rewrites each 30 s; nothing and no check without herdr-core"

# --- opting a pane out of mirrors ---
OFF="$AGENTS_RUN_DIR/hc-mirror.off"
reset; snap "p1|claude|idle|$tmp/proj-a" "p2|claude|working|$tmp/proj-b"; terms "t1|a|live|p1" "t2|b|live|p2" "t3|mine|live|"
out="$(agents_main hc mirror off p2 2>&1)" || fail "off failed: $out"
[[ "$(cat "$OFF")" == p2 && "$(kills)" == "t2 " ]] || fail "off: recorded $(cat "$OFF" 2>/dev/null), kills $(kills)"
[[ "$out" == *"ended the mirror of p2 (b)"* && "$out" == *"p2: no mirror from now on"* ]] || fail "off output: $out"
[[ ! -e "$AGENTS_RUN_DIR/hc-mirror.lock" ]] || fail "off left the lock"
terms "t1|a|live|p1"; rm -f "$FAKE"/*.calls
agents_hc_mirror_sync -q
[[ -z "$(runs)" && -z "$(kills)" ]] || fail "a sync mirrored an opted-out pane: runs=$(runs) kills=$(kills)"
out="$(agents_hc_mirror_sync 2>&1)"
[[ "$out" == *"every agent pane has its mirror, but the 1 opted out"* ]] || fail "sync output with one opted out: $out"
terms "t1|a|live|p1" "t4|late|live|p2"
agents_hc_mirror_sync -q
[[ "$(kills)" == "t4 " && -z "$(runs)" ]] || fail "a sync left a mirror of an opted-out pane running: kills=$(kills) runs=$(runs)"
terms "t1|a|live|p1"
out="$(agents_main hc mirror status 2>&1)"
[[ "$out" == *"p2"*"opted out (agents hc mirror on p2)"* && "$out" == *"opted out of mirrors: p2 "* && "$out" == *"mirrored as a"* ]] \
    || fail "status with an opted-out pane: $out"
out="$(HERDR_PANE_ID=p1 agents_main hc mirror off 2>&1)"
agents_main hc mirror off p2 >/dev/null 2>&1
[[ "$(cat "$OFF")" == $'p2\np1' && "$out" == *"p1: no mirror from now on"* ]] || fail "off this pane, and twice: $(cat "$OFF")"
pass "off: recorded, its mirror ended at once; a sync starts none for it and ends one that appears; status lists it"

reset; snap "p1|claude|idle|$tmp/proj-a" "p2|claude|idle|$tmp/proj-b"; terms "t1|a|live|p1"; printf 'p2\np1\n' > "$OFF"
out="$(agents_main hc mirror on p2 2>&1)" || fail "on failed: $out"
[[ "$(cat "$OFF")" == p1 && "$out" == *"p2: mirrored again"* && "$(runs)" == *"_mirror p2 "* ]] || fail "on: $(cat "$OFF") / $out / $(runs)"
out="$(agents_main hc mirror on p1 2>&1)"
[[ ! -e "$OFF" ]] || fail "the last one on: the file stays: $(cat "$OFF")"
out="$(agents_main hc mirror on p1 2>&1)"; [[ "$out" == *"p1: not opted out; nothing changed"* ]] || fail "on twice: $out"
reset; printf 'p2\n' > "$OFF"
out="$(AGENTS_HC_MIRROR=0 agents_main hc mirror on p2 2>&1)"
[[ ! -e "$OFF" && "$out" == *"once mirrors run"* && ! -e "$FAKE/run.calls" ]] || fail "on with mirrors off: $out"
pass "on: off the list, then a sync when mirrors run; the list goes with its last pane"

reset
rc=0; out="$(agents_main hc mirror off 2>&1)" || rc=$?
[[ $rc -eq 2 && "$out" == *"usage: agents hc mirror off [PANE]"* && ! -e "$OFF" ]] || fail "off with no pane: $rc $out"
rc=0; out="$(agents_main hc mirror off 'p1;rm' 2>&1)" || rc=$?
[[ $rc -eq 2 && "$out" == *"not a pane id"* && ! -e "$OFF" ]] || fail "off with a bad id: $rc $out"
rc=0; agents_main hc mirror off p1 p2 >/dev/null 2>&1 || rc=$?; [[ $rc -eq 2 ]] || fail "off with two panes: $rc"
RUNNING=false
out="$(agents_main hc mirror off p1 2>&1)"
[[ "$(cat "$OFF")" == p1 && ! -e "$FAKE/hc.calls" ]] || fail "off with no core: recorded, nothing asked: $(calls hc)"
RUNNING=true; reset; terms "t1|a|live|p1"; printf 'garbage\n' > "$FAKE/list.json"
out="$(agents_main hc mirror off p1 2>&1)"
[[ "$(cat "$OFF")" == p1 && -z "$(kills)" && "$out" == *"the next sync ends its mirror"* ]] || fail "off, a core that did not answer: $out"
pass "off needs a pane id; with no core it only records, with no answer it says the next sync ends the mirror"

# The ids of panes Herdr no longer has go at a sync; a pane with no agent now keeps its own.
reset; snap "p1|claude|idle|$tmp/proj-a" "p5||idle|$tmp/proj-a"; terms "t1|a|live|p1"; printf 'p1\ngone9\np5\n' > "$OFF"
agents_hc_mirror_sync -n >/dev/null
[[ "$(cat "$OFF")" == $'p1\ngone9\np5' ]] || fail "-n dropped an entry: $(cat "$OFF")"
agents_hc_mirror_sync -q
[[ "$(cat "$OFF")" == $'p1\np5' ]] || fail "stale entries: $(cat "$OFF")"
printf 'garbage\n' > "$FAKE/snap.json"; printf 'p1\ngone9\n' > "$OFF"
agents_hc_mirror_sync -q
[[ "$(cat "$OFF")" == $'p1\ngone9' ]] || fail "a snapshot that did not parse dropped entries: $(cat "$OFF")"
reset; snap "p7|claude|idle|$tmp/proj-a"; printf 'p1\n' > "$OFF"
agents_hc_mirror_sync -q
[[ ! -e "$OFF" && "$(runs)" == *"_mirror p7 "* ]] || fail "the last stale entry: the file stays: $(cat "$OFF" 2>/dev/null)"
# A Herdr that names no pane at all (starting up) drops nothing.
reset; printf '{"result":{"snapshot":{"layouts":[],"panes":[]}}}\n' > "$FAKE/snap.json"; printf 'p1\np2\n' > "$OFF"
agents_hc_mirror_sync -q
[[ "$(cat "$OFF" 2>/dev/null)" == $'p1\np2' ]] || fail "a snapshot with no panes dropped the list: $(cat "$OFF" 2>/dev/null)"
pass "a sync drops the opted-out panes Herdr no longer has (not with -n, not on a bad snapshot); a pane with no agent keeps its entry"

# --- what the phone reaches: agents hc ls ---
# One line, as the core sends each message.
lsfix() {
    jq -c . > "$FAKE/list.json" <<EOF2
{"jsonrpc":"2.0","id":1,"result":{"terminals":[
 {"address":"t1","name":"fix-login","state":"live","labels":{"tuidev_mirror":"p1"},"status":{"state":"working","app":"claude"},"foreground":{"pid":1,"cwd":"$HOME/w/myapp"}},
 {"address":"t2","name":"api","state":"live","labels":{},"status":{"state":"blocked","app":"claude"},"cwd":"/srv/api"},
 {"address":"t3","name":null,"state":"finished","exit":{"code":3},"foreground":null},
 {"address":"t4","name":"quiet","state":"live","status":null},
 {"address":"t5","name":"old-mirror","state":"finished","labels":{"tuidev_mirror":"p2"}}
]}}
EOF2
}
reset; lsfix
snap "p1|claude|working|$tmp/proj-a" "p2|codex|idle|$tmp/proj-a" "p3|claude|blocked|$tmp/proj-b" "p4|claude|idle|$tmp/proj-b" "p6||idle|$tmp/proj-b"
printf '%s\np3\tt2\tapi\n' $$ > "$(_agents_hc_pane_mark p3)"
printf 'p4\n' > "$OFF"
out="$(agents_main hc ls 2>&1)" || fail "ls failed: $out"
line() { printf '%s\n' "$out" | grep -E "^  $1 " || true; }
[[ "$(line fix-login)" =~ mirror\ of\ p1\ \(claude\)\ +working\ +~/w/myapp$ ]] || fail "ls, a mirror: $(line fix-login)"
[[ "$(line api)" =~ hosted,\ in\ pane\ p3\ +needs\ you\ +/srv/api$ ]] || fail "ls, a hosted one: $(line api)"
[[ "$(line t3)" =~ hosted\ +exited\ 3\ +-$ ]] || fail "ls, a finished one: $(line t3)"
[[ "$(line quiet)" =~ hosted\ +live\ +-$ ]] || fail "ls, no status: $(line quiet)"
[[ "$(line old-mirror)" =~ mirror\ of\ p2\ \(codex\)\ +finished\ +-$ ]] || fail "ls, a finished mirror: $(line old-mirror)"
[[ "$(printf '%s\n' "$out" | tail -n 1)" == "Not on the phone: 2 agent panes of this machine's Herdr: 1 opted out (agents hc mirror on PANE), 1 not mirrored yet (agents hc mirror sync)" ]] \
    || fail "ls, the panes it cannot reach: $out"
[[ "$(calls hc)" != *" run "* && -z "$(kills)" && -z "$(runs)" ]] || fail "ls changed something: $(calls hc)"
out="$(AGENTS_HC_MIRROR=0 agents_main hc ls 2>&1)"
[[ "$(printf '%s\n' "$out" | tail -n 1)" == *"1 opted out (agents hc mirror on PANE), 1 with mirrors off (AGENTS_HC_MIRROR=1 in agents.conf)" ]] \
    || fail "ls, mirrors off: $out"
terms "t1|a|live|p1" "t2|b|live|p2"; printf '%s\np3\tt9\tx\n' $$ > "$(_agents_hc_pane_mark p3)"; rm -f "$OFF"
out="$(agents_main hc ls 2>&1)"
[[ "$(printf '%s\n' "$out" | tail -n 1)" == *"Not on the phone: 1 agent pane of this machine's Herdr: 1 not mirrored yet"* ]] || fail "ls, one pane: $out"
snap "p1|claude|idle|$tmp/proj-a" "p2|claude|idle|$tmp/proj-a"
[[ "$(agents_main hc ls 2>&1 | tail -n 1)" == "Every agent pane of this machine's Herdr is on the phone" ]] || fail "ls, all reachable"
snap "p6||idle|$tmp/proj-a"; terms
out="$(agents_main hc ls 2>&1)"
[[ "$out" == *"herdr-core has no terminals"* && "$out" == *"No agent panes in this machine's Herdr"* ]] || fail "ls, nothing: $out"
printf 'garbage\n' > "$FAKE/snap.json"
[[ "$(agents_main hc ls 2>&1 | tail -n 1)" == "Herdr did not answer within ${_AGENTS_HC_HERDR_WAIT} s: its agent panes are not counted" ]] || fail "ls, Herdr did not answer"
rm -f "$AGENTS_RUN_DIR"/hc-pane.*
pass "ls: each core terminal (hosted, in a pane, or a mirror of one; its state and directory), then the agent panes the phone cannot reach and why"

reset; RUNNING=false
rc=0; out="$(agents_main hc ls 2>&1)" || rc=$?
[[ $rc -eq 1 && "$out" == *"herdr-core is not running here"* && ! -e "$FAKE/hc.calls" ]] || fail "ls, no core: $rc $out $(calls hc)"
RUNNING=true
for bad in 'garbage' '' '{"jsonrpc":"2.0","id":1,"result":{"terminals":"x"}}' '{"jsonrpc":"2.0","id":1,"error":{"message":"no"}}'; do
    printf '%s\n' "$bad" > "$FAKE/list.json"
    rc=0; out="$(agents_main hc ls 2>&1)" || rc=$?
    [[ $rc -eq 1 && "$out" == "herdr-core did not answer within ${_AGENTS_HC_WAIT} s; nothing is listed" ]] || fail "ls, list '$bad': $rc $out"
done
saved_wait=$_AGENTS_HC_WAIT; _AGENTS_HC_WAIT=1; : > "$FAKE/hang.connect"; t0=$SECONDS
rc=0; out="$(agents_main hc ls 2>&1)" || rc=$?
[[ $rc -eq 1 && $((SECONDS - t0)) -le 3 && "$out" == *"did not answer"* ]] || fail "ls, a core that hangs: $rc after $((SECONDS - t0)) s: $out"
_AGENTS_HC_WAIT=$saved_wait
rc=0; out="$(AGENTS_HC_BIN="$tmp/nope" agents_main hc ls 2>&1)" || rc=$?
[[ $rc -eq 1 && "$out" == *"not installed"* ]] || fail "ls, no herdr-core: $rc $out"
[[ "$(agents_main hc ls extra 2>&1)" == "usage: agents hc ls" ]] || fail "ls takes no argument"
pass "ls never starts a core, and a core that does not answer, answers no list or hangs is one line and exit 1"

# --- what the phone reaches, for the board: the cache's check and its feed ---
reset; lsfix; printf '%s\np3\tt2\tapi\n' $$ > "$(_agents_hc_pane_mark p3)"
out="$(_agents_hc_phone --reach)"
[[ "$out" == $'up\tyes\t1\nphone\tp1\tmirror\tfix-login\nphone\tp3\thosted\tapi' ]] || fail "--reach: $out"
[[ "$(_agents_hc_phone)" == $'up\tyes\t1' ]] || fail "without --reach: one line: $(_agents_hc_phone)"
out="$(AGENTS_HC_MIRROR=0 _agents_hc_phone --reach)"
[[ "$out" == $'core\tyes\t0\nphone\tp1\tmirror\tfix-login\nphone\tp3\thosted\tapi' ]] || fail "--reach, mirrors off: $out"
printf 'garbage\n' > "$FAKE/list.json"
out="$(AGENTS_HC_MIRROR=0 _agents_hc_phone --reach)"
[[ "$out" == $'core\tyes\t0\nphone\tp3\thosted\tapi' ]] || fail "--reach, no list: no mirror is guessed: $out"
lsfix; _agents_hc_phone_refresh
[[ "$(sed -n '2,$p' "$AGENTS_RUN_DIR/hc-phone.cache")" == $'up\tyes\t1\nphone\tp1\tmirror\tfix-login\nphone\tp3\thosted\tapi' ]] \
    || fail "the cache: $(cat "$AGENTS_RUN_DIR/hc-phone.cache")"
printf 'p4\n' > "$OFF"; rm -f "$FAKE"/*.calls
[[ "$(_agents_hc_phone_feed)" == $'phonecore\nphone\tp1\tmirror\tfix-login\nphone\tp3\thosted\tapi\nphoneoff\tp4' ]] || fail "the feed: $(_agents_hc_phone_feed)"
[[ ! -e "$FAKE/hc.calls" ]] || fail "the feed asked the core: $(calls hc)"
[[ -z "$(AGENTS_HC_BIN="" _agents_hc_phone_feed)" ]] || fail "the feed under the test harness without a stand-in"
[[ -z "$(AGENTS_HC_BIN="$tmp/nope" _agents_hc_phone_feed)" ]] || fail "the feed without herdr-core"
printf '%s\n\n' "$(date +%s)" > "$AGENTS_RUN_DIR/hc-phone.cache"; rm -f "$OFF"
[[ "$(_agents_hc_phone_feed)" == phonecore ]] || fail "the feed with nothing reachable: $(_agents_hc_phone_feed)"
rm -f "$AGENTS_RUN_DIR"/hc-pane.* "$AGENTS_RUN_DIR/hc-phone.cache"
pass "the phone's cache keeps the menu's line, then each mirror and hosted pane; the board's feed reads it and the opt-outs, asking no core"

echo "All hcmirror tests passed"
