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
        pane w1:p1 w1:t1 w1 claude /work/agentic "◐ Fleet IA"
        pane w1:p2 w1:t2 w1 ""     /work/mactui_setup "user@box: ~/work/mactui_setup"
        pane w1:p3 w1:t3 w1 claude /work/agentic "✳ Remote runners and port proxying"
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
token() { jq -r --arg id "$1" '.result.snapshot.workspaces[] | select(.workspace_id == $id) | .tokens.agents // ""' "$FAKE/snap.json"; }
shown() { jq -r --arg id "$1" '.result.snapshot.panes[] | select(.pane_id == $id) | .display_agent // ""' "$FAKE/snap.json"; }
writes() { [[ -e "$FAKE/calls" ]] || { echo 0; return; }; grep -cxE 'rename|report-metadata' "$FAKE/calls" || true; }
calls() { [[ -e "$FAKE/calls" ]] || { echo 0; return; }; grep -cx -- '--' "$FAKE/calls" || true; }
fresh() { rm -f "$FAKE/calls"; }
title() { jq --arg id "$1" --arg t "$2" '(.result.snapshot.panes[] | select(.pane_id == $id)) |= (.terminal_title = $t | .terminal_title_stripped = $t)' \
    "$FAKE/snap.json" > "$FAKE/s" && mv "$FAKE/s" "$FAKE/snap.json"; }
user_rename() { "$tmp/herdr" tab rename "$1" "$2"; }

# --- 1. Naming --------------------------------------------------------------------------------
fixture; fresh
out="$(agents_herdr_sync)"
[[ "$(label w1:t1)" == "✳ Fleet IA" ]] || fail "a session's task title: $(label w1:t1)"
[[ "$(label w1:t2)" == "❯ mactui_setup" ]] || fail "a shell is named by its directory, not its prompt: $(label w1:t2)"
[[ "$(label w1:t3)" == "✳ Remote runners and … +1" ]] || fail "the first agent wins, cut at 20, +N: $(label w1:t3)"
[[ "$(label w1:t4)" == "notes" ]] || fail "a name you typed was changed: $(label w1:t4)"
[[ "$(label w2:t1)" == "⬡ api" ]] || fail "a command line is no task title: $(label w2:t1)"
[[ "$(token w1)" == "✳3 ❯3" && "$(token w2)" == "⬡1" ]] || fail "roll-ups: $(token w1) | $(token w2)"
[[ "$(shown w1:p1)" == "✳ claude" && "$(shown w2:p1)" == "⬡ codex" && -z "$(shown w1:p2)" ]] || fail "display names: $(shown w1:p1) $(shown w2:p1) $(shown w1:p2)"
[[ "$out" == *"tab w1:t1: ✳ Fleet IA"* ]] || fail "sync said: $out"
grep -qx -- '--agent' "$FAKE/calls" || fail "a display name without its agent guard"
grep -qxF "tab${T:-	}w1:t4" "$AGENTS_RUN_DIR/herdr-labels.tsv" && fail "your tab was recorded as ours"
[[ "$(grep -c "^tab	" "$AGENTS_RUN_DIR/herdr-labels.tsv")" -eq 4 ]] || fail "state: $(cat "$AGENTS_RUN_DIR/herdr-labels.tsv")"
grep -qx "tab	w1:t1	ours	1	✳ Fleet IA" "$AGENTS_RUN_DIR/herdr-labels.tsv" || fail "state keeps the number: $(cat "$AGENTS_RUN_DIR/herdr-labels.tsv")"
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
[[ "$(label w1:t1)" == "release" && "$(writes)" == 0 ]] || fail "your rename was undone: $(label w1:t1)"
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
[[ "$(label w1:t1)" == "Fleet IA" && "$(label w1:t2)" == mactui_setup ]] || fail "glyphs off: $(label w1:t1) | $(label w1:t2)"
[[ "$(token w1)" == "claude:3 shell:3" ]] || fail "glyphs off roll-up: $(token w1)"
[[ -z "$(shown w1:p1)" ]] || fail "glyphs off set a display name"
agents_herdr_sync >/dev/null
[[ "$(label w1:t1)" == "✳ Fleet IA" && "$(shown w1:p1)" == "✳ claude" ]] || fail "glyphs back on: $(label w1:t1)"
AGENTS_GLYPHS=off agents_herdr_sync >/dev/null
[[ -z "$(shown w1:p1)" && "$(label w1:t1)" == "Fleet IA" ]] || fail "glyphs off again: $(shown w1:p1) $(label w1:t1)"
fresh; out="$(AGENTS_HERDR_NAMES=0 agents_herdr_sync)"
[[ "$(calls)" == 0 && "$out" == *"left alone"* ]] || fail "AGENTS_HERDR_NAMES=0 still called herdr: $(cat "$FAKE/calls" 2>/dev/null)"
fresh; AGENTS_NO_HERDR=1 agents_herdr_sync >/dev/null
[[ "$(calls)" == 0 ]] || fail "AGENTS_NO_HERDR still called herdr"
pass "AGENTS_GLYPHS=off names without marks (and clears the display names); AGENTS_HERDR_NAMES=0 and AGENTS_NO_HERDR call nothing"

# --- 7. Hostile titles ------------------------------------------------------------------------
fixture; rm -f "$AGENTS_RUN_DIR/herdr-labels.tsv"
evil=$'\e]0;owned\a$(touch '"$tmp"$'/pwned) ‮`id`; x\n--source evil\x1fR\tw1:t4\tgot'
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
[[ "$(label w1:t1)" == "✳ Fleet IA" ]] || fail "the coalesced sync did not name"
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
[[ "$(writes)" == 0 && "$out" == *"would rename tab w1:t1: ✳ Dry run"* && "$(label w1:t1)" == "✳ Fleet IA" ]] || fail "dry run: $out"
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
[[ "$out" == *"w1:t4"*"yours"*"notes"* && "$out" == *"w1:t1"*"agents"*"✳ Fleet IA"* ]] || fail "status: $out"
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
[[ "$(label w1:t1)" == "✳ Fleet IA" && "$out" == "tab w1:t1: ✳ Fleet IA" ]] || fail "reset w1:t1: $(label w1:t1), said: $out"
grep -qx "tab	w1:t1	ours	1	✳ Fleet IA" "$AGENTS_RUN_DIR/herdr-labels.tsv" || fail "reset w1:t1 state: $(st)"
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

# --- 11. The plugin's hooks ------------------------------------------------------------------------
plugin="$REPO_DIR/configs/herdr/plugins/tuidev-link"
# The events Herdr 0.9.5 runs plugin hooks for (PLUGIN_HOOK_EVENT_KINDS): an
# unknown name is only a warning there, and the hook would never run.
known=" workspace.created workspace.updated workspace.closed workspace.renamed workspace.moved workspace.reordered workspace.focused worktree.created worktree.opened worktree.removed tab.created tab.closed tab.renamed tab.moved tab.focused pane.created pane.closed pane.focused pane.moved pane.exited pane.agent_detected pane.agent_status_changed "
evs="$(sed -n 's/^on = "\(.*\)"$/\1/p' "$plugin/herdr-plugin.toml")"
[[ -n "$evs" ]] || fail "the plugin has no event hooks"
for e in $evs; do [[ "$known" == *" $e "* ]] || fail "the plugin hooks $e, which Herdr does not run hooks for"; done
[[ "$evs" != *tab.renamed* ]] || fail "hooking tab.renamed would answer the sync's own renames"
[[ "$(grep -cE '^command = \["sh", "run.sh", "sync(-poke)?"\]$' "$plugin/herdr-plugin.toml")" -eq $(( $(printf '%s\n' "$evs" | wc -l) + 1 )) ]] \
    || fail "every event hook and the startup hook run run.sh sync or sync-poke"
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
    _herdr_has_own_spaces "$c" && fail "a config without space rows has them"
    printf '%s\n' "$(tuidev_block_begin tuidev-sidebar)" '[ui.sidebar.spaces]' 'rows = []' "$(tuidev_block_end tuidev-sidebar)" >> "$c"
    _herdr_has_own_spaces "$c" && fail "tuidev's own block counted as yours"
    printf '# [ui.sidebar.spaces]\n' >> "$c"
    _herdr_has_own_spaces "$c" && fail "a commented table counted"
    printf '[ ui.sidebar.spaces ]\nrows = []\n' >> "$c"
    _herdr_has_own_spaces "$c" || fail "your own [ui.sidebar.spaces] was missed"
    printf '[ui.sidebar]\nspaces.rows = []\n' > "$c"
    _herdr_has_own_spaces "$c" || fail "spaces under [ui.sidebar] was missed"
    grep -q '"\$agents"' "$REPO_DIR/configs/herdr/sidebar.toml" || fail "sidebar.toml has no \$agents"
    [[ "$(grep -c '^\[' "$REPO_DIR/configs/herdr/sidebar.toml")" -eq 1 ]] || fail "sidebar.toml must hold one table"
)
pass "the pack's sidebar block: added only where your config has no space rows of its own"
