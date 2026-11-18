#!/bin/bash
# Unit tests for Herdr's labels: lib/agents/herdrlabel.sh (`agents herdr`),
# the tuidev.link plugin's event hooks that run it, and the herdr pack's
# sidebar block.
# Run: bash scripts/lib/test_agents_herdrlabel.sh  -> exit 0 on pass.
#
# No Herdr: HERDR_BIN_PATH is a stand-in that serves a snapshot from a JSON
# file, applies each write to it (as Herdr would), and logs every call, one
# argument a line, so a test sees exactly what reached `herdr`.

# Tests change variables inside ( … ) on purpose; the stand-ins are called by
# the code under test; $( ) in single quotes is text that must stay unexpanded.
# shellcheck disable=SC2030,SC2031,SC2034,SC2329,SC2016,SC2317
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq is not installed"; exit 0; }

tmp="$(mktemp -d "${TMPDIR:-/tmp}/tuidev-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
for v in XDG_CONFIG_HOME XDG_STATE_HOME TUIDEV_STATE_DIR AGENTS_NO_HERDR AGENTS_GLYPHS AGENTS_HERDR_NAMES \
         HERDR_SOCKET_PATH HERDR_ENV HERDR_PANE_ID; do unset "$v"; done
export HOME="$tmp/home" NO_COLOR=1 TZ=UTC AGENTS_CONF="$tmp/none.conf" AGENTS_DATA_DIR="$tmp/data" AGENTS_RUN_DIR="$tmp/run"
export AGENTS_TESTING=1 AGENTS_NOW=1792170000 FAKE="$tmp/fake"
mkdir -p "$HOME" "$FAKE" "$AGENTS_RUN_DIR"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "PASS: $1"; }

# The stand-in herdr. Each call: its arguments in $FAKE/calls, one a line,
# after a "--" line. Writes change $FAKE/snap.json as Herdr would.
cat > "$tmp/herdr" <<'EOF'
#!/bin/bash
{ echo "--"; printf '%s\n' "$@"; } >> "$FAKE/calls"
snap="$FAKE/snap.json"
edit() { jq "$@" "$snap" > "$snap.new" && mv "$snap.new" "$snap"; }
case "$1 $2" in
    "api snapshot")
        [[ ! -e "$FAKE/down" ]] || exit 1
        # A sync that comes in while this one runs (the first time only).
        if [[ -e "$FAKE/poke" ]]; then rm -f "$FAKE/poke"; : > "$AGENTS_RUN_DIR/herdr-labels.dirty"; fi
        cat "$snap" ;;
    "tab rename")
        id="$3"; shift 3
        edit --arg id "$id" --arg l "$*" '(.result.snapshot.tabs[] | select(.tab_id == $id) | .label) = $l' ;;
    "workspace report-metadata")
        id="$3"; shift 3
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --token)       edit --arg id "$id" --arg k "${2%%=*}" --arg v "${2#*=}" '(.result.snapshot.workspaces[] | select(.workspace_id == $id) | .tokens[$k]) = $v'; shift 2 ;;
                --clear-token) edit --arg id "$id" --arg k "$2" '(.result.snapshot.workspaces[] | select(.workspace_id == $id)) |= del(.tokens[$k])'; shift 2 ;;
                *)             shift ;;
            esac
        done ;;
    "pane report-metadata")
        id="$3"; shift 3
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --display-agent)       edit --arg id "$id" --arg v "$2" '(.result.snapshot.panes[] | select(.pane_id == $id) | .display_agent) = $v'; shift 2 ;;
                --clear-display-agent) edit --arg id "$id" '(.result.snapshot.panes[] | select(.pane_id == $id)) |= del(.display_agent)'; shift ;;
                --token)               edit --arg id "$id" --arg k "${2%%=*}" --arg v "${2#*=}" '(.result.snapshot.panes[] | select(.pane_id == $id) | .tokens[$k]) = $v'; shift 2 ;;
                --clear-token)         edit --arg id "$id" --arg k "$2" '(.result.snapshot.panes[] | select(.pane_id == $id)) |= del(.tokens[$k])'; shift 2 ;;
                *)                     shift ;;
            esac
        done ;;
esac
EOF
chmod +x "$tmp/herdr"
export HERDR_BIN_PATH="$tmp/herdr"

# shellcheck source=../../bin/agents disable=SC1091
. "$REPO_DIR/bin/agents"
_agents_hl_socket() { return 0; }   # no Herdr socket here
_AGENTS_HL_PAUSE=0

# A session: workspace w1 (proj) with a Claude Code tab (its task title), a
# shell tab, a tab of two Claude Code sessions and a shell, and a tab you
# named; w2 (other) with Codex, whose title is only its command line.
pane() {   # ID TAB WS AGENT CWD TITLE
    jq -n --arg id "$1" --arg tab "$2" --arg ws "$3" --arg agent "$4" --arg cwd "$5" --arg title "$6" \
        '{pane_id: $id, tab_id: $tab, workspace_id: $ws, cwd: $cwd, terminal_title: $title,
          terminal_title_stripped: ($title | sub("^[◐◑◒◓✳] "; ""))} + (if $agent == "" then {} else {agent: $agent} end)'
}
fixture() {
    {
        pane w1:p1 w1:t1 w1 claude /work/agentic "◐ API docs"
        pane w1:p2 w1:t2 w1 ""     /work/mactui_setup "user@box: ~/work/mactui_setup"
        pane w1:p3 w1:t3 w1 claude /work/agentic "✳ Fix login redirect and port proxying"
        pane w1:p4 w1:t3 w1 ""     /work/agentic ""
        pane w1:p5 w1:t3 w1 claude /work/agentic "✳ Claude Code"
        pane w1:p6 w1:t4 w1 ""     /work/notes ""
        pane w2:p1 w2:t1 w2 codex  "$HOME/src/api" "codex --yolo"
    } | jq -s --arg home "$HOME" '{id: "cli:api:snapshot", result: {type: "snapshot", snapshot: {
        workspaces: [{workspace_id: "w1", label: "proj", number: 1}, {workspace_id: "w2", label: "other", number: 2}],
        tabs: [{tab_id: "w1:t1", workspace_id: "w1", label: "1", number: 1},
               {tab_id: "w1:t2", workspace_id: "w1", label: "2", number: 2},
               {tab_id: "w1:t3", workspace_id: "w1", label: "3", number: 3},
               {tab_id: "w1:t4", workspace_id: "w1", label: "notes", number: 4},
               {tab_id: "w2:t1", workspace_id: "w2", label: "1", number: 1}],
        panes: .}}}' > "$FAKE/snap.json"
}
label() { jq -r --arg id "$1" '.result.snapshot.tabs[] | select(.tab_id == $id) | .label' "$FAKE/snap.json"; }
token() { jq -r --arg id "$1" '.result.snapshot.workspaces[] | select(.workspace_id == $id) | .tokens.tuidev_agents // ""' "$FAKE/snap.json"; }
shown() { jq -r --arg id "$1" '.result.snapshot.panes[] | select(.pane_id == $id) | .display_agent // ""' "$FAKE/snap.json"; }
wtok() { jq -r --arg id "$1" --arg k "$2" '.result.snapshot.workspaces[] | select(.workspace_id == $id) | .tokens[$k] // ""' "$FAKE/snap.json"; }
ptok() { jq -r --arg id "$1" --arg k "$2" '.result.snapshot.panes[] | select(.pane_id == $id) | .tokens[$k] // ""' "$FAKE/snap.json"; }
# status PANE STATE [SEQ] — Herdr's agent state for an agent pane, as the
# snapshot carries it: agent_status on the pane, state_change_seq in agents[].
status() { jq --arg id "$1" --arg s "$2" --arg q "${3:-}" '(.result.snapshot.panes[] | select(.pane_id == $id) | .agent_status) = $s
    | ((.result.snapshot.agents // []) | map({key: .pane_id, value: .state_change_seq}) | from_entries) as $was
    | .result.snapshot.agents = [.result.snapshot.panes[] | select(.agent) | {pane_id, agent, agent_status}
        + (if .pane_id == $id and $q != "" then {state_change_seq: ($q | tonumber)}
           elif $was[.pane_id] != null then {state_change_seq: $was[.pane_id]} else {} end)]' \
    "$FAKE/snap.json" > "$FAKE/s" && mv "$FAKE/s" "$FAKE/snap.json"; }
writes() { [[ -e "$FAKE/calls" ]] || { echo 0; return; }; grep -cxE 'rename|report-metadata' "$FAKE/calls" || true; }
calls() { [[ -e "$FAKE/calls" ]] || { echo 0; return; }; grep -cx -- '--' "$FAKE/calls" || true; }
fresh() { rm -f "$FAKE/calls"; }
title() { jq --arg id "$1" --arg t "$2" '(.result.snapshot.panes[] | select(.pane_id == $id)) |= (.terminal_title = $t | .terminal_title_stripped = $t)' \
    "$FAKE/snap.json" > "$FAKE/s" && mv "$FAKE/s" "$FAKE/snap.json"; }
user_rename() { "$tmp/herdr" tab rename "$1" "$2"; }

# --- 1. Naming --------------------------------------------------------------------------------
fixture; fresh
out="$(agents_herdr_sync)"
[[ "$(label w1:t1)" == "✳ API docs" ]] || fail "a session's task title: $(label w1:t1)"
[[ "$(label w1:t2)" == "❯ mactui_setup" ]] || fail "a shell is named by its directory, not its prompt: $(label w1:t2)"
[[ "$(label w1:t3)" == "✳ Fix login redirect … +1" ]] || fail "the first agent wins, cut at 20, +N: $(label w1:t3)"
[[ "$(label w1:t4)" == "notes" ]] || fail "a name you typed was changed: $(label w1:t4)"
[[ "$(label w2:t1)" == "⬡ api" ]] || fail "a command line is no task title: $(label w2:t1)"
[[ "$(token w1)" == "✳3 ❯3" && "$(token w2)" == "⬡1" ]] || fail "roll-ups: $(token w1) | $(token w2)"
[[ "$(shown w1:p1)" == "✳ claude" && "$(shown w2:p1)" == "⬡ codex" && -z "$(shown w1:p2)" ]] || fail "display names: $(shown w1:p1) $(shown w2:p1) $(shown w1:p2)"
[[ "$out" == *"tab w1:t1: ✳ API docs"* ]] || fail "sync said: $out"
grep -qx -- '--agent' "$FAKE/calls" || fail "a display name without its agent guard"
grep -qxF "tab${T:-	}w1:t4" "$AGENTS_RUN_DIR/herdr-labels.tsv" && fail "your tab was recorded as ours"
[[ "$(grep -c "^tab	" "$AGENTS_RUN_DIR/herdr-labels.tsv")" -eq 4 ]] || fail "state: $(cat "$AGENTS_RUN_DIR/herdr-labels.tsv")"
grep -qx "tab	w1:t1	ours	1	✳ API docs" "$AGENTS_RUN_DIR/herdr-labels.tsv" || fail "state keeps the number: $(cat "$AGENTS_RUN_DIR/herdr-labels.tsv")"
pass "naming: mark and task title, else the directory; the first agent wins with +N; cut at 20; roll-ups; display names"

# --- 2. Nothing changed, nothing written --------------------------------------------------------
fresh; before="$(cat "$AGENTS_RUN_DIR/herdr-labels.tsv")"
out="$(agents_herdr_sync)"
[[ "$(writes)" == 0 && "$(calls)" == 1 && -z "$out" ]] || fail "an unchanged sync wrote: $(cat "$FAKE/calls")"
[[ "$(cat "$AGENTS_RUN_DIR/herdr-labels.tsv")" == "$before" ]] || fail "an unchanged sync changed the state"
# A new task title renames a tab a sync named, and only that tab.
fresh; title w1:p1 "Ship the release"
agents_herdr_sync >/dev/null
[[ "$(label w1:t1)" == "✳ Ship the release" && "$(writes)" == 1 ]] || fail "a new title: $(label w1:t1), $(writes) writes"
pass "nothing changed: one read and no write; a new task title renames its tab only"

# --- 3. A name you typed is yours for good --------------------------------------------------------
user_rename w1:t1 "release"; fresh
agents_herdr_sync >/dev/null
[[ "$(label w1:t1)" == "release" ]] || fail "your rename was undone: $(label w1:t1)"
# The one write: the session's own name, which your tab's name no longer says.
[[ "$(writes)" == 1 && "$(ptok w1:p1 tuidev_session)" == "✳ Ship the release" ]] || fail "your rename: $(writes) writes, \$session $(ptok w1:p1 tuidev_session)"
! grep -qx rename "$FAKE/calls" || fail "a tab rename after your rename"
grep -qx "tab	w1:t1	user		" "$AGENTS_RUN_DIR/herdr-labels.tsv" || fail "your rename was not remembered: $(cat "$AGENTS_RUN_DIR/herdr-labels.tsv")"
user_rename w1:t1 "5"; title w1:p1 "Another task"
agents_herdr_sync >/dev/null
[[ "$(label w1:t1)" == "5" ]] || fail "a tab you renamed to a number was named again: $(label w1:t1)"
pass "a tab you renamed is never touched again, even renamed to a number"

# --- 4. The way back ---------------------------------------------------------------------------
fresh
out="$(agents_herdr_reset)"
[[ "$(label w1:t2)" == 2 && "$(label w1:t3)" == 3 && "$(label w2:t1)" == 1 ]] || fail "reset: $(label w1:t2) $(label w1:t3) $(label w2:t1)"
[[ "$(label w1:t1)" == 5 && "$(label w1:t4)" == notes ]] || fail "reset touched your tabs: $(label w1:t1) $(label w1:t4)"
[[ -z "$(token w1)" && -z "$(token w2)" && -z "$(shown w1:p1)" && -z "$(shown w2:p1)" ]] || fail "reset left metadata: $(token w1) $(shown w1:p1)"
{ grep -qx -- '--clear-display-agent' "$FAKE/calls" && grep -qx -- '--clear-token' "$FAKE/calls"; } || fail "reset did not clear: $(cat "$FAKE/calls")"
[[ ! -e "$AGENTS_RUN_DIR/herdr-labels.tsv" ]] || fail "reset kept the state"
[[ "$out" == *"next sync names them again"* ]] || fail "reset did not say the next sync renames: $out"
fresh; out="$(agents_herdr_reset)"
[[ "$(writes)" == 0 && "$out" == "nothing to reset"* ]] || fail "a second reset wrote: $out"
pass "reset: numbers back, roll-ups and display names cleared, your tabs untouched; twice is a no-op"

# --- 5. Labels that already say it are adopted ------------------------------------------------------
fixture; fresh
user_rename w1:t2 "❯ mactui_setup"; fresh
agents_herdr_sync >/dev/null
grep -qx "tab	w1:t2	ours	2	❯ mactui_setup" "$AGENTS_RUN_DIR/herdr-labels.tsv" || fail "a label equal to ours was not adopted: $(cat "$AGENTS_RUN_DIR/herdr-labels.tsv")"
grep -A1 -x rename "$FAKE/calls" | grep -qx 'w1:t2' && fail "an adopted label was rewritten"
agents_herdr_reset >/dev/null
[[ "$(label w1:t2)" == 2 ]] || fail "an adopted tab got its position back: $(label w1:t2)"
pass "a label that already reads what a sync would set is adopted, and reset gives it its position"

# --- 6. Glyphs off, and turned off -----------------------------------------------------------------
fixture; rm -f "$AGENTS_RUN_DIR/herdr-labels.tsv"
AGENTS_GLYPHS=off agents_herdr_sync >/dev/null
[[ "$(label w1:t1)" == "API docs" && "$(label w1:t2)" == mactui_setup ]] || fail "glyphs off: $(label w1:t1) | $(label w1:t2)"
[[ "$(token w1)" == "claude:3 shell:3" ]] || fail "glyphs off roll-up: $(token w1)"
[[ -z "$(shown w1:p1)" ]] || fail "glyphs off set a display name"
agents_herdr_sync >/dev/null
[[ "$(label w1:t1)" == "✳ API docs" && "$(shown w1:p1)" == "✳ claude" ]] || fail "glyphs back on: $(label w1:t1)"
AGENTS_GLYPHS=off agents_herdr_sync >/dev/null
[[ -z "$(shown w1:p1)" && "$(label w1:t1)" == "API docs" ]] || fail "glyphs off again: $(shown w1:p1) $(label w1:t1)"
fresh; out="$(AGENTS_HERDR_NAMES=0 agents_herdr_sync)"
[[ "$(calls)" == 0 && "$out" == *"left alone"* ]] || fail "AGENTS_HERDR_NAMES=0 still called herdr: $(cat "$FAKE/calls" 2>/dev/null)"
fresh; AGENTS_NO_HERDR=1 agents_herdr_sync >/dev/null
[[ "$(calls)" == 0 ]] || fail "AGENTS_NO_HERDR still called herdr"
pass "AGENTS_GLYPHS=off names without marks (and clears the display names); AGENTS_HERDR_NAMES=0 and AGENTS_NO_HERDR call nothing"

# --- 7. Hostile titles ------------------------------------------------------------------------
fixture; rm -f "$AGENTS_RUN_DIR/herdr-labels.tsv"
evil=$'\e]0;owned\a$(touch '"$tmp"$'/pwned) \xe2\x80\xae`id`; x\n--source evil\x1fR\tw1:t4\tgot'
title w1:p1 "$evil"
title w2:p1 $'\e[31m'"-rf"$'\t'"/"
fresh; agents_herdr_sync >/dev/null
[[ ! -e "$tmp/pwned" ]] || fail "a title ran a command"
l="$(label w1:t1)"
[[ "$l" != *[[:cntrl:]]* && "$l" == "✳ "* && ${#l} -le 30 ]] || fail "a hostile title's label: $(printf '%q' "$l")"
[[ "$(label w1:t4)" == notes ]] || fail "a title forged a record"
[[ "$(label w2:t1)" != *"-rf"* || "$(label w2:t1)" == "⬡ "* ]] || fail "a title starting with a dash: $(label w2:t1)"
# Each label reached herdr as one argument, after the tab id.
n="$(grep -A2 -x rename "$FAKE/calls" | grep -c -x 'w1:t1')"
[[ "$n" == 1 ]] || fail "the label was not one argument: $(cat "$FAKE/calls")"
pass "hostile titles: control and bidi characters stripped, capped, one argument, nothing run, no forged records"

# --- 8. One sync at a time; a throttle; Herdr down -----------------------------------------------
fixture; rm -f "$AGENTS_RUN_DIR/herdr-labels.tsv" "$AGENTS_RUN_DIR/herdr-labels.dirty"
_agents_lock "$AGENTS_RUN_DIR/herdr-labels.lock" || fail "could not take the lock"
fresh; ( agents_herdr_sync -q )
[[ "$(calls)" == 0 && -e "$AGENTS_RUN_DIR/herdr-labels.dirty" ]] || fail "a sync while another ran: $(calls) calls, no mark"
_agents_unlock "$AGENTS_RUN_DIR/herdr-labels.lock"
: > "$FAKE/poke"; fresh
agents_herdr_sync -q
[[ "$(grep -cx snapshot "$FAKE/calls")" == 2 && ! -e "$AGENTS_RUN_DIR/herdr-labels.dirty" ]] || fail "an event during a sync did not get one more pass: $(grep -cx snapshot "$FAKE/calls")"
[[ "$(label w1:t1)" == "✳ API docs" ]] || fail "the coalesced sync did not name"
fresh; agents_herdr_sync --throttle
[[ "$(calls)" == 0 ]] || fail "--throttle ran within 30 s"
AGENTS_NOW=$((AGENTS_NOW + 31)) agents_herdr_sync --throttle -q
[[ "$(calls)" == 1 ]] || fail "--throttle did not run after 30 s: $(calls)"
before="$(cat "$AGENTS_RUN_DIR/herdr-labels.tsv")"
: > "$FAKE/down"; fresh
agents_herdr_sync -q 2>/dev/null || fail "a sync failed when Herdr did not answer"
[[ "$(writes)" == 0 && "$(cat "$AGENTS_RUN_DIR/herdr-labels.tsv")" == "$before" ]] || fail "Herdr down changed something"
rm -f "$FAKE/down"
title w1:p1 "Dry run"; fresh
out="$(agents_herdr sync -n)"
[[ "$(writes)" == 0 && "$out" == *"would rename tab w1:t1: ✳ Dry run"* && "$(label w1:t1)" == "✳ API docs" ]] || fail "dry run: $out"
pass "one sync at a time (a mark, then one more pass); --throttle; Herdr down changes nothing; -n writes nothing"

# --- 9. Another source's display name wins -------------------------------------------------------
fixture; rm -f "$AGENTS_RUN_DIR/herdr-labels.tsv"
jq '(.result.snapshot.panes[] | select(.pane_id == "w2:p1") | .display_agent) = "Codex (work)"' "$FAKE/snap.json" > "$FAKE/s" && mv "$FAKE/s" "$FAKE/snap.json"
fresh; agents_herdr_sync -q
[[ "$(shown w2:p1)" == "Codex (work)" ]] || fail "another source's display name was replaced"
grep -A1 -x report-metadata "$FAKE/calls" | grep -qx 'w2:p1' && fail "wrote over another display name"
pass "a display name another tool set is left as it is"

# --- 10. status ----------------------------------------------------------------------------------
out="$(agents_herdr status)"
[[ "$out" == *"w1:t4"*"yours"*"notes"* && "$out" == *"w1:t1"*"agents"*"✳ API docs"* ]] || fail "status: $out"
[[ "$out" == *"proj"*"w1"*"✳3 ❯3"* ]] || fail "status roll-up: $out"
agents_herdr bogus >/dev/null 2>&1 && fail "an unknown subcommand succeeded"
pass "status: each tab's label and whose it is; each workspace's roll-up"

# --- 10b. One tab handed back: reset TAB_ID... ------------------------------------------------------
st() { cat "$AGENTS_RUN_DIR/herdr-labels.tsv" 2>/dev/null; }
fixture; rm -f "$AGENTS_RUN_DIR/herdr-labels.tsv"
agents_herdr_sync -q
user_rename w1:t1 "release"; agents_herdr_sync -q
grep -qx "tab	w1:t1	user		" "$AGENTS_RUN_DIR/herdr-labels.tsv" || fail "setup: w1:t1 is not yours: $(st)"
others="$(grep -v "^tab	w1:t1	" "$AGENTS_RUN_DIR/herdr-labels.tsv")"
snap_others() { jq -c '.result.snapshot | [(.tabs[] | select(.tab_id != "w1:t1")), .workspaces, (.panes | map(.display_agent))]' "$FAKE/snap.json"; }
before="$(snap_others)"
# A tab you renamed: named again as a sync would, and ours (its number as ORIG).
fresh; out="$(agents_herdr_reset w1:t1)"
[[ "$(label w1:t1)" == "✳ API docs" && "$out" == "tab w1:t1: ✳ API docs" ]] || fail "reset w1:t1: $(label w1:t1), said: $out"
grep -qx "tab	w1:t1	ours	1	✳ API docs" "$AGENTS_RUN_DIR/herdr-labels.tsv" || fail "reset w1:t1 state: $(st)"
[[ "$(writes)" == 1 && "$(snap_others)" == "$before" ]] || fail "reset w1:t1 touched more: $(writes) writes"
[[ "$(grep -v "^tab	w1:t1	" "$AGENTS_RUN_DIR/herdr-labels.tsv")" == "$others" ]] || fail "reset w1:t1 changed other state lines: $(st)"
# ... and the next sync keeps it named, as ours.
title w1:p1 "Ship it"; agents_herdr_sync -q
[[ "$(label w1:t1)" == "✳ Ship it" ]] || fail "a tab handed back is not named by the next sync: $(label w1:t1)"
# A tab that is ours already: a fresh name (a sync has not run since its title changed), ORIG kept.
title w1:p3 "New work"; fresh
out="$(agents_herdr_reset w1:t3)"
[[ "$(label w1:t3)" == "✳ New work +1" && "$out" == "tab w1:t3: ✳ New work +1" ]] || fail "reset of an ours tab: $(label w1:t3), said: $out"
grep -qx "tab	w1:t3	ours	3	✳ New work +1" "$AGENTS_RUN_DIR/herdr-labels.tsv" || fail "reset of an ours tab, state: $(st)"
# One that reads its name already: no write, said all the same.
fresh; out="$(agents_herdr_reset w1:t2)"
[[ "$(writes)" == 0 && "$out" == "tab w1:t2: ❯ mactui_setup" ]] || fail "reset of a tab that reads its name: $(writes) writes, said: $out"
grep -qx "tab	w1:t2	ours	2	❯ mactui_setup" "$AGENTS_RUN_DIR/herdr-labels.tsv" || fail "reset of a tab that reads its name, state: $(st)"
# A tab a sync has no name for (no agent, no directory): its number, and Herdr's again.
jq '(.result.snapshot.panes[] | select(.pane_id == "w1:p6") | .cwd) = ""' "$FAKE/snap.json" > "$FAKE/s" && mv "$FAKE/s" "$FAKE/snap.json"
user_rename w1:t4 "notes"; printf 'tab\tw1:t4\tuser\t\t\n' >> "$AGENTS_RUN_DIR/herdr-labels.tsv"
fresh; out="$(agents_herdr_reset w1:t4)"
[[ "$(label w1:t4)" == 4 && "$out" == "tab w1:t4: 4" ]] || fail "reset of a tab with no name to give: $(label w1:t4), said: $out"
! grep -q "^tab	w1:t4	" "$AGENTS_RUN_DIR/herdr-labels.tsv" || fail "reset of a tab with no name to give kept its state line: $(st)"
# Names off: its number, no state line, and it says so.
fresh; out="$(AGENTS_HERDR_NAMES=0 agents_herdr_reset w1:t1)"
[[ "$(label w1:t1)" == 1 && "$out" == *"tab w1:t1: 1"*"names are off"* ]] || fail "reset with names off: $(label w1:t1), said: $out"
! grep -q "^tab	w1:t1	" "$AGENTS_RUN_DIR/herdr-labels.tsv" || fail "reset with names off kept the state line: $(st)"
# -n: what it would do, nothing written.
user_rename w1:t1 "mine"; fresh
out="$(agents_herdr_reset -n w1:t1)"
[[ "$(writes)" == 0 && "$(label w1:t1)" == mine && "$out" == "would rename tab w1:t1: ✳ Ship it" ]] || fail "reset -n: $(writes) writes, said: $out"
# A malformed or unknown id: one line on stderr each, the valid ones done, exit 1.
fresh; rc=0; out="$(agents_herdr_reset 'w1:t1;rm' w9:t9 w1:t1 2>"$tmp/err")" || rc=$?
[[ $rc -eq 1 && "$(label w1:t1)" == "✳ Ship it" && "$out" == "tab w1:t1: ✳ Ship it" ]] || fail "bad ids: rc $rc, $(label w1:t1), said: $out"
{ [[ "$(wc -l < "$tmp/err" | tr -d ' ')" == 2 ]] && grep -q 'not a tab id' "$tmp/err" && grep -q 'no tab w9:t9' "$tmp/err"; } \
    || fail "bad ids, stderr: $(cat "$tmp/err")"
rc=0; agents_herdr_reset '-x' >/dev/null 2>&1 || rc=$?; [[ $rc -eq 2 ]] || fail "reset -x: rc $rc"
fresh; rc=0; agents_herdr_reset 'bad id' >/dev/null 2>&1 || rc=$?
[[ $rc -eq 1 && "$(calls)" == 0 ]] || fail "only a malformed id: rc $rc, $(calls) herdr calls"
pass "reset TAB_ID: a tab you renamed is named again and ours; ours gets a fresh name; no name gives its number and no state; names off; -n; bad ids said and skipped; nothing else touched"

# --- 10c. The sidebar's tokens: $tuidev_need, $tuidev_since, $tuidev_session ----------------------------------------------
fixture; rm -f "$AGENTS_RUN_DIR/herdr-labels.tsv"
status w1:p1 working 1; status w1:p3 idle 1; status w1:p5 idle 1; status w2:p1 working 1
fresh; agents_herdr_sync -q
# First sight: when a state began is not known, so no $tuidev_since; nobody is blocked.
[[ -z "$(ptok w1:p1 tuidev_since)" && -z "$(ptok w1:p3 tuidev_since)" && -z "$(wtok w1 tuidev_need)" ]] || fail "first sight: since $(ptok w1:p1 tuidev_since), need $(wtok w1 tuidev_need)"
grep -qx "seen	w1:p1	claude	working	1	-" "$AGENTS_RUN_DIR/herdr-labels.tsv" || fail "no seen line: $(st)"
# A tab named after its own session needs no $tuidev_session; a title that is only the CLI's name gives none.
[[ -z "$(ptok w1:p1 tuidev_session)" && -z "$(ptok w1:p3 tuidev_session)" && -z "$(ptok w1:p5 tuidev_session)" ]] || fail "session on first sight: $(ptok w1:p5 tuidev_session)"
# Blocked: the workspace says so, the pane says since when.
status w1:p1 blocked 2; fresh; agents_herdr_sync -q
[[ "$(wtok w1 tuidev_need)" == blocked && "$(ptok w1:p1 tuidev_since)" == "17:00" ]] || fail "blocked: need $(wtok w1 tuidev_need), since $(ptok w1:p1 tuidev_since)"
[[ -z "$(wtok w2 tuidev_need)" && "$(writes)" == 2 ]] || fail "blocked: need on w2 $(wtok w2 tuidev_need), $(writes) writes"
# Nothing changed, the clock moved on: no write, and the state file stays.
before="$(st)"; fresh
AGENTS_NOW=$((AGENTS_NOW + 120)) agents_herdr_sync -q
[[ "$(writes)" == 0 && "$(calls)" == 1 && "$(st)" == "$before" ]] || fail "an unchanged sync two minutes on wrote: $(writes)"
# Two blocked; then working again: $tuidev_since cleared (working waits on nobody), $tuidev_need down to one.
status w1:p3 blocked 2; AGENTS_NOW=$((AGENTS_NOW + 120)) agents_herdr_sync -q
[[ "$(wtok w1 tuidev_need)" == "2 blocked" && "$(ptok w1:p3 tuidev_since)" == "17:02" ]] || fail "two blocked: $(wtok w1 tuidev_need), $(ptok w1:p3 tuidev_since)"
status w1:p1 working 3; fresh; AGENTS_NOW=$((AGENTS_NOW + 180)) agents_herdr_sync -q
[[ "$(wtok w1 tuidev_need)" == blocked && -z "$(ptok w1:p1 tuidev_since)" && "$(writes)" == 2 ]] || fail "working again: $(wtok w1 tuidev_need), since $(ptok w1:p1 tuidev_since), $(writes) writes"
# Idle at a new time; the same state with a new state_change_seq began again.
status w1:p1 idle 4; AGENTS_NOW=$((AGENTS_NOW + 240)) agents_herdr_sync -q
[[ "$(ptok w1:p1 tuidev_since)" == "17:04" ]] || fail "idle: $(ptok w1:p1 tuidev_since)"
status w1:p1 idle 6; AGENTS_NOW=$((AGENTS_NOW + 300)) agents_herdr_sync -q
[[ "$(ptok w1:p1 tuidev_since)" == "17:05" ]] || fail "a new seq: $(ptok w1:p1 tuidev_since)"
# The day turns: the weekday, once; a week on: the date.
fresh; AGENTS_NOW=$((AGENTS_NOW + 86400)) agents_herdr_sync -q
[[ "$(ptok w1:p1 tuidev_since)" == Fri && "$(ptok w1:p3 tuidev_since)" == Fri ]] || fail "the next day: $(ptok w1:p1 tuidev_since)"
fresh; AGENTS_NOW=$((AGENTS_NOW + 86400 + 60)) agents_herdr_sync -q
[[ "$(writes)" == 0 ]] || fail "the next day, again: $(writes) writes"
AGENTS_NOW=$((AGENTS_NOW + 8 * 86400)) agents_herdr_sync -q
[[ "$(ptok w1:p1 tuidev_since)" == "Oct 16" ]] || fail "a week on: $(ptok w1:p1 tuidev_since)"
# Nobody blocked: $tuidev_need cleared, not left at zero.
status w1:p3 working 3; agents_herdr_sync -q
[[ -z "$(wtok w1 tuidev_need)" && -z "$(ptok w1:p3 tuidev_since)" ]] || fail "nobody blocked: need $(wtok w1 tuidev_need)"
# Another session in a tab with a task title of its own: $tuidev_session, with its mark; gone with the title.
title w1:p5 "Port proxying"; agents_herdr_sync -q
[[ "$(ptok w1:p5 tuidev_session)" == "✳ Port proxying" && "$(label w1:t3)" == "✳ Fix login redirect … +1" ]] || fail "a second session: $(ptok w1:p5 tuidev_session)"
title w1:p5 "✳ Claude Code"; agents_herdr_sync -q
[[ -z "$(ptok w1:p5 tuidev_session)" ]] || fail "\$session kept without a title: $(ptok w1:p5 tuidev_session)"
# An agent that exits: its tokens go with it.
title w1:p5 "Port proxying"; agents_herdr_sync -q
jq '(.result.snapshot.panes[] | select(.pane_id == "w1:p5")) |= del(.agent, .agent_status)' "$FAKE/snap.json" > "$FAKE/s" && mv "$FAKE/s" "$FAKE/snap.json"
fresh; agents_herdr_sync -q
[[ -z "$(ptok w1:p5 tuidev_session)" && -z "$(ptok w1:p5 tuidev_since)" ]] || fail "an exited agent kept its tokens"
! grep -q "^seen	w1:p5	" "$AGENTS_RUN_DIR/herdr-labels.tsv" || fail "an exited agent kept its seen line"
pass "tokens: \$tuidev_need counts the blocked; \$tuidev_since when a waiting state began (not while working), stable across syncs, by day and date later; \$tuidev_session only for a task title the tab does not show"

# Glyphs off: $tuidev_session without a mark. Dry run: said, not written.
title w1:p5 "Port proxying"
jq '(.result.snapshot.panes[] | select(.pane_id == "w1:p5")) |= (.agent = "claude" | .agent_status = "idle")' "$FAKE/snap.json" > "$FAKE/s" && mv "$FAKE/s" "$FAKE/snap.json"
fresh; out="$(agents_herdr sync -n)"
[[ "$(writes)" == 0 && "$out" == *'would set pane w1:p5: $tuidev_session ✳ Port proxying'* ]] || fail "dry run: $out"
AGENTS_GLYPHS=off agents_herdr_sync -q
[[ "$(ptok w1:p5 tuidev_session)" == "Port proxying" ]] || fail "glyphs off: $(ptok w1:p5 tuidev_session)"
agents_herdr_sync -q
# Hostile: a forged seen line, a hostile title, names and values the shell refuses.
printf 'seen\tw1:p2\tclaude\tblocked\t9\t$(touch %s/pwned)\nseen\tw9:p9;rm\tx\ty\tz\t1\n' "$tmp" >> "$AGENTS_RUN_DIR/herdr-labels.tsv"
title w1:p5 $'\e]0;x\a-rf \xe2\x80\xae`id`\x1fP\x1fw1:p1\x1fsince=pwned'
fresh; agents_herdr_sync -q
[[ ! -e "$tmp/pwned" ]] || fail "a seen line ran a command"
s="$(ptok w1:p5 tuidev_session)"
[[ "$s" != *[[:cntrl:]]* && "$s" != *$'\xe2\x80\xae'* && "$s" == "✳ "[[:alnum:]]* && ${#s} -le 26 ]] || fail "a hostile title's \$tuidev_session: $(printf '%q' "$s")"
[[ "$(ptok w1:p1 tuidev_since)" != pwned ]] || fail "a title forged a token"
! grep -q 'w9:p9' "$AGENTS_RUN_DIR/herdr-labels.tsv" || fail "a forged seen line was kept"
fresh
_agents_hl_tokens pane w1:p1 "evil=1" "tuidev_since=-x" "tuidev_need" >/dev/null && fail "unknown names and unfit values were sent"
[[ "$(calls)" == 0 ]] || fail "_agents_hl_tokens called herdr with nothing to send"
_agents_hl_tokens pane w1:p1 "tuidev_since=" "evil=1" >/dev/null
{ grep -qx -- '--clear-token' "$FAKE/calls" && ! grep -qx 'evil=1' "$FAKE/calls"; } || fail "one call with only our names: $(cat "$FAKE/calls")"
pass "tokens: glyphs off, dry run, forged state lines and hostile titles, and only our names with fit values reach herdr"

# Reset clears every token a sync set and leaves other sources' alone; names off writes nothing.
status w1:p1 blocked 9; agents_herdr_sync -q
jq '(.result.snapshot.panes[] | select(.pane_id == "w1:p1") | .tokens.ctx) = "42" | (.result.snapshot.workspaces[] | select(.workspace_id == "w1") | .tokens.jj) = "clean"' \
    "$FAKE/snap.json" > "$FAKE/s" && mv "$FAKE/s" "$FAKE/snap.json"
[[ -n "$(ptok w1:p1 tuidev_since)" && -n "$(wtok w1 tuidev_need)" && -n "$(ptok w1:p5 tuidev_session)" ]] || fail "setup: tokens to reset"
fresh; AGENTS_HERDR_NAMES=0 agents_herdr_sync -q
[[ "$(calls)" == 0 ]] || fail "names off called herdr"
agents_herdr_reset >/dev/null
for p in w1:p1 w1:p3 w1:p5 w2:p1; do [[ -z "$(ptok "$p" tuidev_since)" && -z "$(ptok "$p" tuidev_session)" ]] || fail "reset left a pane token on $p"; done
[[ -z "$(wtok w1 tuidev_need)" && -z "$(wtok w1 tuidev_agents)" ]] || fail "reset left a workspace token"
[[ "$(ptok w1:p1 ctx)" == 42 && "$(wtok w1 jj)" == clean ]] || fail "reset cleared another source's tokens"
fresh; out="$(agents_herdr_reset)"
[[ "$(writes)" == 0 && "$out" == "nothing to reset"* ]] || fail "a second reset wrote: $out"
pass "tokens: reset clears \$tuidev_need, \$tuidev_since and \$tuidev_session and nothing of another source's; AGENTS_HERDR_NAMES=0 writes nothing"

# Legacy names (3.22.0: agents; its successors: need, since, session) are cleared once, in the same
# write as the new values; a second sync finds nothing; other names are never touched. Reset clears both.
agents_herdr_reset >/dev/null
jq '(.result.snapshot.workspaces[] | select(.workspace_id == "w1") | .tokens) += {agents: "✳1", need: "blocked"}
    | (.result.snapshot.panes[] | select(.pane_id == "w1:p1") | .tokens) += {since: "17:00", session: "old", ctx: "42"}' \
    "$FAKE/snap.json" > "$FAKE/s" && mv "$FAKE/s" "$FAKE/snap.json"
fresh; agents_herdr_sync -q
[[ -z "$(wtok w1 agents)" && -z "$(wtok w1 need)" && -z "$(ptok w1:p1 since)" && -z "$(ptok w1:p1 session)" ]] || fail "legacy tokens kept"
[[ -n "$(wtok w1 tuidev_agents)" && "$(wtok w1 tuidev_need)" == blocked && "$(ptok w1:p1 ctx)" == 42 ]] || fail "legacy: new tokens not set with them, or another name touched"
[[ "$(grep -c -- '--clear-token' "$FAKE/calls")" -ge 4 ]] || fail "legacy: four clears expected: $(cat "$FAKE/calls")"
fresh; agents_herdr_sync -q
[[ "$(writes)" == 0 ]] || fail "legacy: a second sync wrote $(writes)"
jq '(.result.snapshot.workspaces[] | select(.workspace_id == "w1") | .tokens) += {agents: "x", need: "y"}
    | (.result.snapshot.panes[] | select(.pane_id == "w1:p1") | .tokens) += {since: "z", session: "t"}' "$FAKE/snap.json" > "$FAKE/s" && mv "$FAKE/s" "$FAKE/snap.json"
agents_herdr_reset >/dev/null
[[ -z "$(wtok w1 agents)$(wtok w1 need)$(wtok w1 tuidev_agents)$(ptok w1:p1 since)$(ptok w1:p1 session)$(ptok w1:p1 tuidev_since)" ]] || fail "reset left a legacy or new token"
pass "tokens: the pre-prefix names are cleared once with the new values set, never again, and by reset"

# --- 11. The plugin's hooks ------------------------------------------------------------------------
plugin="$REPO_DIR/configs/herdr/plugins/tuidev-link"
# The events Herdr 0.9.5 runs plugin hooks for (PLUGIN_HOOK_EVENT_KINDS): an
# unknown name is only a warning there, and the hook would never run.
known=" workspace.created workspace.updated workspace.closed workspace.renamed workspace.moved workspace.reordered workspace.focused worktree.created worktree.opened worktree.removed tab.created tab.closed tab.renamed tab.moved tab.focused pane.created pane.closed pane.focused pane.moved pane.exited pane.agent_detected pane.agent_status_changed "
evs="$(sed -n 's/^on = "\(.*\)"$/\1/p' "$plugin/herdr-plugin.toml")"
[[ -n "$evs" ]] || fail "the plugin has no event hooks"
for e in $evs; do [[ "$known" == *" $e "* ]] || fail "the plugin hooks $e, which Herdr does not run hooks for"; done
[[ "$evs" != *tab.renamed* ]] || fail "hooking tab.renamed would answer the sync's own renames"
[[ "$(grep -cE '^command = \["sh", "run.sh", "sync(-poke)?"\]$' "$plugin/herdr-plugin.toml")" -eq "$(printf '%s\n' "$evs" | wc -l)" ]] \
    || fail "every event hook runs run.sh sync or sync-poke"
# The startup hook syncs too, after the update check when it is due.
[[ "$(grep -A1 '^\[\[startup\]\]$' "$plugin/herdr-plugin.toml" | tail -1)" == 'command = ["sh", "run.sh", "startup"]' ]] \
    || fail "the startup hook runs run.sh startup"
grep -A6 '^    startup)$' "$plugin/run.sh" | grep -q 'herdr sync -q' || fail "run.sh startup does not sync"
# An agent's events refresh the menu bar too (sync-poke); the others don't.
pokes="$(awk '/^on = / { e = $3; gsub(/"/, "", e) } /^command = .*"sync-poke"/ { print e }' "$plugin/herdr-plugin.toml" | sort | tr '\n' ' ')"
[[ "$pokes" == "pane.agent_detected pane.agent_status_changed pane.closed pane.exited " ]] || fail "sync-poke runs on: $pokes"
printf '#!/bin/sh\necho "$*" > "%s/stub"\n' "$tmp" > "$tmp/agents-stub"; chmod +x "$tmp/agents-stub"
AGENTS_BIN="$tmp/agents-stub" sh "$plugin/run.sh" sync || fail "run.sh sync failed"
[[ "$(cat "$tmp/stub")" == "herdr sync -q" ]] || fail "run.sh sync ran: $(cat "$tmp/stub")"
AGENTS_BIN="$tmp/agents-stub" sh "$plugin/run.sh" sync-poke || fail "run.sh sync-poke failed"
[[ "$(cat "$tmp/stub")" == "herdr sync -q --poke" ]] || fail "run.sh sync-poke ran: $(cat "$tmp/stub")"
for v in sync sync-poke; do
    out="$(AGENTS_BIN="$tmp/nope" sh "$plugin/run.sh" "$v" 2>&1)" || fail "run.sh $v without agents failed (a hook error on every event)"
    [[ -z "$out" ]] || fail "run.sh $v without agents said: $out"
done
# startup: with agents, only its sync (which starts the due check itself); without it, tuidev's check.
printf '#!/bin/sh\necho "$*" >> "%s/tuidev.rec"\n' "$tmp" > "$tmp/tuidev-stub"; chmod +x "$tmp/tuidev-stub"
rm -f "$tmp/stub" "$tmp/tuidev.rec"
AGENTS_BIN="$tmp/agents-stub" TUIDEV_BIN="$tmp/tuidev-stub" sh "$plugin/run.sh" startup || fail "run.sh startup with agents failed"
sleep 0.3
[[ "$(cat "$tmp/stub")" == "herdr sync -q" && ! -e "$tmp/tuidev.rec" ]] || fail "startup with agents: sync='$(cat "$tmp/stub" 2>&1)' tuidev called: $(cat "$tmp/tuidev.rec" 2>&1)"
AGENTS_BIN="$tmp/nope" TUIDEV_BIN="$tmp/tuidev-stub" sh "$plugin/run.sh" startup || fail "run.sh startup without agents failed"
for _ in 1 2 3 4 5 6 7 8 9 10; do [[ -s "$tmp/tuidev.rec" ]] && break; sleep 0.1; done
[[ "$(cat "$tmp/tuidev.rec" 2>&1)" == "latest --if-due --notify" ]] || fail "startup without agents: $(cat "$tmp/tuidev.rec" 2>&1)"
rm -f "$tmp/stub" "$tmp/tuidev.rec"
pass "the plugin: hooks only events Herdr runs hooks for (not tab.renamed), each runs agents herdr sync -q, an agent's with --poke; quiet without agents"

# --poke: where the menu bar would refresh (bar.alive names a live SwiftBar),
# Herdr's agents are read again, then the bar is poked, in this one process;
# anywhere else neither. The label sync runs as before either way.
(
    export AGENTS_RUN_DIR="$tmp/pokerun"; mkdir -p "$AGENTS_RUN_DIR"
    : > "$tmp/pokes"
    _agents_herdr_refresh() { echo refresh >> "$tmp/pokes"; }
    agents_bar_poke() { echo poke >> "$tmp/pokes"; }
    _agents_hl_socket() { return 0; }
    _agents_hl_ready() { return 1; }    # the label sync itself: not here
    OSTYPE=darwin25
    agents_herdr_sync -q --poke
    [[ ! -s "$tmp/pokes" ]] || fail "--poke with no plugin running: $(cat "$tmp/pokes")"
    printf '%s %s agents -\n' "$AGENTS_NOW" "$$" > "$AGENTS_RUN_DIR/bar.alive"
    agents_herdr_sync -q --poke
    [[ "$(tr '\n' ' ' < "$tmp/pokes")" == "refresh poke " ]] || fail "--poke: $(cat "$tmp/pokes")"
    : > "$tmp/pokes"; agents_herdr_sync -q
    [[ ! -s "$tmp/pokes" ]] || fail "a sync without --poke poked: $(cat "$tmp/pokes")"
    : > "$tmp/pokes"; OSTYPE=linux-gnu agents_herdr_sync -q --poke
    [[ ! -s "$tmp/pokes" ]] || fail "--poke off macOS: $(cat "$tmp/pokes")"
) || exit 1
pass "herdr sync --poke: Herdr's agents read again and the menu bar poked, only where SwiftBar runs the plugin"

# --- 12. The herdr pack's sidebar block -----------------------------------------------------------------
(
    # shellcheck source=../install/packs/herdr.sh disable=SC1091
    . "$REPO_DIR/scripts/install/packs/herdr.sh"
    set +e
    c="$tmp/herdr-config.toml"
    printf '[ui]\nstatus_indicators = "symbols"\n' > "$c"
    herdr_has_own_sidebar "$c" && fail "a config without sidebar rows has them"
    printf '%s\n' "$(tuidev_block_begin tuidev-sidebar)" '[ui.sidebar.spaces]' 'rows = []' '[ui.sidebar.agents]' 'rows = []' "$(tuidev_block_end tuidev-sidebar)" >> "$c"
    herdr_has_own_sidebar "$c" && fail "tuidev's own block counted as yours"
    printf '# [ui.sidebar.spaces]\n# [ui.sidebar.agents]\n' >> "$c"
    herdr_has_own_sidebar "$c" && fail "a commented table counted"
    for t in spaces agents; do
        printf '[ ui.sidebar.%s ]\nrows = []\n' "$t" > "$c"
        herdr_has_own_sidebar "$c" || fail "your own [ui.sidebar.$t] was missed"
        printf '[ui.sidebar.%s.extra]\nx = 1\n' "$t" > "$c"
        herdr_has_own_sidebar "$c" || fail "a sub-table of sidebar.$t was missed"
        printf '[ui.sidebar]\n%s.rows = []\n' "$t" > "$c"
        herdr_has_own_sidebar "$c" || fail "$t under [ui.sidebar] was missed"
        printf '[ui]\nsidebar.%s.rows = []\n' "$t" > "$c"
        herdr_has_own_sidebar "$c" || fail "sidebar.$t under [ui] was missed"
    done
    src="$REPO_DIR/configs/herdr/sidebar.toml"
    grep -q '"\$tuidev_agents"' "$src" || fail "sidebar.toml has no \$tuidev_agents"
    [[ "$(grep -c '^\[' "$src")" -eq 2 ]] || fail "sidebar.toml must hold the spaces and the agents table"
    grep -qx '\[ui.sidebar.spaces\]' "$src" || fail "sidebar.toml has no spaces table"
    grep -qx '\[ui.sidebar.agents\]' "$src" || fail "sidebar.toml has no agents table"

    # Install: a fresh config gets the block; a second run changes nothing.
    ok="$tmp/herdr-ok.toml"
    printf '[ui]\nstatus_indicators = "symbols"\n' > "$ok"
    _herdr_install_sidebar "$ok" >/dev/null 2>&1
    grep -qxF "$(tuidev_block_begin tuidev-sidebar)" "$ok" || fail "a fresh config got no block"
    [[ "$(read_managed_block "$ok" tuidev-sidebar)" == "$(cat "$src")" ]] || fail "the block is not sidebar.toml"
    before="$(cat "$ok")"; _herdr_install_sidebar "$ok" >/dev/null 2>&1
    [[ "$(cat "$ok")" == "$before" ]] || fail "a second install changed the config"

    # Upgrade: the old block (one table) is replaced by the new content, and
    # what you wrote around it stays.
    up="$tmp/herdr-up.toml"
    printf '[ui]\nstatus_indicators = "symbols"\n\n' > "$up"
    old='[ui.sidebar.spaces]
rows = [["state_icon", "workspace", "$tuidev_agents"], ["branch", "git_status"]]'
    write_managed_block "$up" tuidev-sidebar "$old" >/dev/null 2>&1
    _herdr_install_sidebar "$up" >/dev/null 2>&1
    [[ "$(read_managed_block "$up" tuidev-sidebar)" == "$(cat "$src")" ]] || fail "the old block was not replaced"
    grep -q 'status_indicators = "symbols"' "$up" || fail "your own settings were lost"
    [[ "$(grep -c '^\[ui.sidebar.spaces\]' "$up")" -eq 1 ]] || fail "a duplicate spaces table after the upgrade"

    # Skip: your own spaces OR agents table, whether or not an old block is
    # there; nothing is added or rewritten, and the config keeps one of each.
    for t in spaces agents; do
        mine="$tmp/herdr-mine-$t.toml"
        printf '[ui.sidebar.%s]\nrows = [["agent"]]\n' "$t" > "$mine"
        _herdr_install_sidebar "$mine" >/dev/null 2>&1
        grep -qF "$(tuidev_block_begin tuidev-sidebar)" "$mine" && fail "a block was added beside your own $t rows"
        printf '\n' >> "$mine"; write_managed_block "$mine" tuidev-sidebar "$old" >/dev/null 2>&1
        before="$(cat "$mine")"; _herdr_install_sidebar "$mine" >/dev/null 2>&1
        [[ "$(cat "$mine")" == "$before" ]] || fail "the install rewrote an old block beside your own $t rows"
        out="$(_herdr_install_sidebar "$mine" 2>&1)"
        [[ "$out" == *'[ui.sidebar.agents]'* ]] || fail "no note that your own rows won: $out"
    done
)
pass "the pack's sidebar block: added and upgraded as a managed block, skipped while your config has space or agent rows of its own"

# update --configs: the same rule, through its drift check.
(
    # shellcheck source=../lib/config_write.sh disable=SC1091
    . "$REPO_DIR/scripts/lib/config_write.sh"
    # shellcheck source=../lib/herdr.sh disable=SC1091
    . "$REPO_DIR/scripts/lib/herdr.sh"
    eval "$(awk '/^managed_block_applies\(\) \{/,/^\}/' "$REPO_DIR/scripts/update.sh")"
    set +e
    c="$tmp/herdr-upd.toml"
    write_managed_block "$c" tuidev-sidebar '[ui.sidebar.spaces]
rows = []' >/dev/null 2>&1
    managed_block_applies "$c" tuidev-sidebar || fail "an update skipped a block of ours"
    printf '[ui.sidebar.agents]\nrows = []\n' >> "$c"
    managed_block_applies "$c" tuidev-sidebar && fail "an update would rewrite the block beside your own agent rows"
    exit 0
)
pass "update --configs refreshes the sidebar block, except beside your own space or agent rows"

# --- 13. The herdr pack's plugin: linked again only when it changed ---------------------------------------
(
    # shellcheck source=../install/packs/herdr.sh disable=SC1091
    . "$REPO_DIR/scripts/install/packs/herdr.sh"
    set +e
    export HERDR_INSTALL_DIR="$tmp/hbin" DRY_RUN=false
    unset TUIDEV_PLUGIN_PANE
    mkdir -p "$HERDR_INSTALL_DIR"
    hlog="$tmp/herdr.log" linked="$tmp/herdr.linked"
    # A stub herdr that remembers whether tuidev.link is linked.
    cat > "$HERDR_INSTALL_DIR/herdr" <<STUB
#!/bin/bash
echo "\$*" >> "$hlog"
case "\$1 \$2" in
    "plugin list") [[ ! -e "$linked" ]] || echo "tuidev.link  linked" ;;
    "plugin link") : > "$linked" ;;
    "plugin unlink") rm -f "$linked" ;;
esac
exit 0
STUB
    chmod +x "$HERDR_INSTALL_DIR/herdr"
    dest="$TUIDEV_LIB_DIR/herdr-plugins/tuidev-link"
    keys="$HOME/.config/herdr/config.toml"
    rm -rf "$dest" "$linked" "$keys"; : > "$hlog"
    relinks() { grep -cE '^plugin (un)?link' "$hlog"; }

    _herdr_install_plugin >/dev/null 2>&1
    [[ -e "$linked" && "$(grep -c '^plugin link ' "$hlog")" == 1 && -f "$dest/run.sh" && -f "$keys" ]] || fail "a first install did not link: $(cat "$hlog")"
    # Unchanged and already linked: no unlink, no link; the keys block is still refreshed.
    : > "$hlog"; rm -f "$keys"
    _herdr_install_plugin >/dev/null 2>&1
    [[ "$(relinks)" == 0 && -e "$linked" ]] || fail "an unchanged, linked plugin was linked again: $(cat "$hlog")"
    grep -q 'tuidev-keys' "$keys" 2>/dev/null || fail "the keys block was not refreshed for an unchanged plugin"
    # Changed, from a shell: unlinked and linked again.
    echo "# edited" >> "$dest/run.sh"; : > "$hlog"
    _herdr_install_plugin >/dev/null 2>&1
    [[ "$(grep -c '^plugin unlink' "$hlog")" == 1 && "$(grep -c '^plugin link ' "$hlog")" == 1 ]] || fail "a changed plugin was not linked again: $(cat "$hlog")"
    cmp -s "$dest/run.sh" "$REPO_DIR/configs/herdr/plugins/tuidev-link/run.sh" || fail "the changed plugin's files were not refreshed"
    # Changed, from inside the plugin's own popup: files copied, a warning, no unlink or link.
    echo "# edited" >> "$dest/run.sh"; : > "$hlog"
    out="$(TUIDEV_PLUGIN_PANE=1 _herdr_install_plugin 2>&1)"
    [[ "$(relinks)" == 0 ]] || fail "linked from inside the plugin's popup: $(cat "$hlog")"
    [[ "$out" == *"tuidev update --configs"* && "$out" == *"outside this popup"* ]] || fail "no warning to update outside the popup: $out"
    cmp -s "$dest/run.sh" "$REPO_DIR/configs/herdr/plugins/tuidev-link/run.sh" || fail "the popup run did not copy the files"
    [[ "$out" == *"plugin changed"* ]] || fail "a changed plugin's warning does not say it changed: $out"
    # Unchanged but not linked, from inside the popup: the warning says that, not "changed".
    rm -f "$linked"; : > "$hlog"
    out="$(TUIDEV_PLUGIN_PANE=1 _herdr_install_plugin 2>&1)"
    [[ "$(relinks)" == 0 && "$out" == *"plugin is not linked"*"to link it"* && "$out" != *"changed"* ]] \
        || fail "an unchanged, unlinked plugin from the popup: $out / $(cat "$hlog")"
    exit 0
) || exit 1
pass "the herdr pack's plugin: linked on first install or a change; an unchanged linked one is left alone; inside its own popup it copies and warns (changed, or not linked)"
