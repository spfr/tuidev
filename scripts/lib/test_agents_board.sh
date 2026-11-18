#!/bin/bash
# Unit tests for the board: lib/agents/board.sh (`agents board`), its awk
# programs, and the tuidev.link plugin's entries that open and poke it.
# Run: bash scripts/lib/test_agents_board.sh  -> exit 0 on pass.
#
# No fzf, no ssh, no Herdr and no processes: the rows and a transcript are
# fixtures (what awk/board_rows.awk prints, and what another machine might
# send instead), the keys are read as the fzf actions they print, and herdr,
# nc, curl and fzf are stand-ins that write down how they were called.

# Tests change variables inside ( … ) on purpose; the stand-ins are called by
# the code under test; $( ) in single quotes is text that must stay unexpanded.
# shellcheck disable=SC2030,SC2031,SC2034,SC2329,SC2317,SC2016
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/tuidev-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
for v in XDG_CONFIG_HOME XDG_STATE_HOME TUIDEV_STATE_DIR AGENTS_GLYPHS AGENTS_BOARD_UI AGENTS_BOARD_POPUP AGENTS_BOARD_FROM \
         FZF_COLUMNS FZF_INPUT_STATE FZF_CLICK_FOOTER_WORD FZF_PREVIEW_LINES FZF_PREVIEW_COLUMNS FZF_API_KEY \
         HERDR_ENV HERDR_PANE_ID HERDR_SOCKET_PATH HERDR_PLUGIN_STATE_DIR HERDR_BIN_PATH; do unset "$v"; done
export HOME="$tmp/home" NO_COLOR=1 TZ=UTC LC_ALL=C AGENTS_CONF="$tmp/none.conf" AGENTS_DATA_DIR="$tmp/data" AGENTS_RUN_DIR="$tmp/run"
export AGENTS_TESTING=1 AGENTS_NOW=1792170000 AGENTS_THEME=none AGENTS_WIDTH=120
mkdir -p "$HOME" "$AGENTS_RUN_DIR"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "PASS: $1"; }
has() { case "$1" in *"$2"*) return 0 ;; esac; return 1; }

# shellcheck source=../../bin/agents disable=SC1091
. "$REPO_DIR/bin/agents"
T=$'\t'
A="1@Mon_Jan_01_00:00:01_2026" B="2@Mon_Jan_01_00:00:02_2026" C="3@Mon_Jan_01_00:00:03_2026"
D="4@Mon_Jan_01_00:00:04_2026" E="5@Mon_Jan_01_00:00:05_2026"

# ---------------------------------------------------------------------------
# 1. This machine's rows, from the records.
# ---------------------------------------------------------------------------
rows="$({
    printf 'sub\t1\tabc123\tExplore\t12\trun\n'
    printf 'sub\t1\tdef456\treviewer\t400\tdone\n'
    printf 'triage\t1\tneed\t240\tpermission\n'
    printf 'triage\t2\trun\t900\ttests 12s\n'
    printf 'agent\t1\tclaude\t3000\t1.0\t1.0\t100\t2\tMon_Jan_01_00:00:01_2026\t-\tme\tblocked\t/w/myapp\tclaude\tmyapp\n'
    printf 'agent\t2\tcodex\t900\t1.0\t1.0\t100\t1\tMon_Jan_01_00:00:02_2026\t-\tme\tworking\t/w/api\tcodex\tapi\n'
    printf 'agent\t9\tdaemon\t900\t0\t0\t10\t0\tMon_Jan_01_00:00:09_2026\t-\tme\t-\t-\tcodex app-server\t-\n'
    printf 'herdr\t1\tw1:p1\tFix flaky cache test\n'
    printf 'herdr\t2\tw1:p2\t-\n'
    printf 'act\t50\ttool\t33\t2.0\t1.0\t10\t1\tMon_Jan_01_00:10:00_2026\t-\t2\t-\t/w/api\tpnpm test\tmain\twait\t1\n'
    printf 'act\t51\tmcp\t33\t0\t0\t10\t1\tMon_Jan_01_00:10:01_2026\t-\t2\tfs\t/w/api\tnode mcp.js\tmain\t-\t1\n'
    printf 'stale\t60\tserver\t99\t0\t0\t10\t0\tMon_Jan_01_00:00:06_2026\t3000\tme\t-\t/w/old\tnode server.js\told\n'
    printf 'hog\t70\tnode\t99\t10\t10\t9437184\t0\tMon_Jan_01_00:00:07_2026\t-\tme\t-\t/w/api\t/usr/bin/node big.js\tapi\n'
} | _agents_awk "lib_fmt board_rows" -F '\t' -v sys='cpu 4% · memory 50% free' -v warn_kib=8388608)"
want="sys${T}cpu 4% · memory 50% free
ses${T}$A${T}need${T}240${T}permission${T}claude${T}Fix flaky cache test${T}myapp
kid${T}$A${T}abc123${T}sub${T}run${T}12${T}Explore
kid${T}$A${T}def456${T}sub${T}done${T}400${T}reviewer
ses${T}$B${T}run${T}900${T}tests 12s${T}codex${T}-${T}api
kid${T}$B${T}50@Mon_Jan_01_00:10:00_2026${T}cmd${T}wait${T}33${T}pnpm test
warn${T}node holds 9.0G
warn${T}1 left behind"
[[ "$rows" == "$want" ]] || fail "rows: $rows"
pass "rows: a session's state and title, its sub-agents and commands, no daemon and no MCP server, what is wrong"

# ---------------------------------------------------------------------------
# 2. The list, from every machine's rows.
# ---------------------------------------------------------------------------
fixture() {
    printf 'local\tsys\tcpu 4%% · memory 50%% free\n'
    printf 'local\tses\t%s\tneed\t60\tpermission\tclaude\tFix flaky cache test\tmyapp\n' "$A"
    printf 'local\tkid\t%s\tabc123\tsub\trun\t12\tExplore\n' "$A"
    printf 'local\tkid\t%s\tdef456\tsub\tdone\t400\treviewer\n' "$A"
    printf 'local\tkid\t%s\t50@Mon_Jan_01_00:10:00_2026\tcmd\twait\t33\tpnpm test\n' "$A"
    printf 'local\tses\t%s\trun\t900\ttests 12s\tcodex\t-\tapi\n' "$B"
    printf 'local\tses\t%s\tparked\t7200\tidle\tclaude\tOld notes\tnotes\n' "$C"
    printf 'local\twarn\tnode holds 9.0G\n'
    printf 'devbox\tsys\tcpu 9%% · memory 20%% free\n'
    printf 'devbox\tses\t%s\tneed\t600\tblocked\tcodex\tReview auth diff\tapi\n' "$D"
    printf 'devbox\tses\t%s\treview\t120\tdone\tclaude\tAPI docs\tapi\n' "$E"
}
view() { fixture | _agents_board_view "$@"; }
_agents_colors

list="$(view list -v lens=attention -v all=0 -v W=110 -v hf="$tmp/header")"
keys="$(printf '%s\n' "$list" | cut -f1-4)"
want="-${T}head${T}need${T}-
devbox${T}ses${T}$D${T}-
local${T}ses${T}$A${T}-
-${T}gap${T}2${T}-
-${T}head${T}review${T}-
devbox${T}ses${T}$E${T}-
-${T}gap${T}3${T}-
-${T}head${T}run${T}-
local${T}ses${T}$B${T}-
-${T}gap${T}4${T}-
-${T}head${T}parked${T}-"
[[ "$keys" == "$want" ]] || fail "the list's rows: $keys"
{ has "$list" "Review auth diff" && has "$list" "waiting on you" && has "$list" "wants permission"; } || fail "what a blocked session says: $list"
has "$(printf '%s\n' "$list" | sed -n 3p)" "+1 sub, 1 cmd" || fail "a session counts what runs under it, a finished sub-agent left out: $list"
has "$(printf '%s\n' "$list" | sed -n 9p)" "api" || fail "a session with no title goes by its project: $list"
has "$list" "devbox" || fail "with two machines a row names its own: $list"
has "$(printf '%s\n' "$list" | tail -n 1)" "press . to show" || fail "the folded parked line says which key shows them: $list"
[[ -z "$(printf '%s\n' "$list" | awk -F '\t' '$2 != "gap" && $5 !~ /^ [^ ]/')" ]] || fail "headings and rows share one left edge: $list"
pass "list: groups by what to do with an empty line between them, the longest wait first, parked folded into a line"

hdr="$(cat "$tmp/header")"
{ has "$hdr" "2 need you" && has "$hdr" "1 to review" && has "$hdr" "1 working" && has "$hdr" "1 parked"; } || fail "the header's counts: $hdr"
has "$hdr" "local: node holds 9.0G" || fail "the header's warning: $hdr"
[[ "$(printf '%s\n' "$hdr" | wc -l | tr -d ' ')" == 3 ]] || fail "the header has a line for limits only when some are known, and its warning stands apart: $hdr"
hdr="$(LIMITS='Claude 62% of 5h' view list -v lens=attention -v W=110 -v hf="$tmp/header" >/dev/null; cat "$tmp/header")"
has "$hdr" "Claude 62% of 5h" || fail "the header's limits: $hdr"
pass "header: the counts, the limits when known, the first warning"

all="$(view list -v lens=attention -v all=1 -v W=110 | cut -f1-3)"
has "$all" "local${T}ses${T}$C" || fail "all=1 lists the parked: $all"
solo="$(fixture | grep '^local' | _agents_board_view list -v lens=attention -v W=110)"
if has "$solo" "local  "; then fail "one machine: no machine column: $solo"; fi
none="$(printf 'local\tsys\tcpu 1%%\n' | _agents_board_view list -v lens=attention -v W=110 | cut -f2,3)"
[[ "$none" == "head${T}-" ]] || fail "no session: one line saying so: $none"
pass "list: the parked on demand, no machine column for one machine, a line when nothing runs"

tree="$(view list -v lens=tree -v W=110)"
want="devbox${T}ses${T}$D${T}-
local${T}ses${T}$A${T}-
local${T}kid${T}abc123${T}$A
local${T}kid${T}def456${T}$A
local${T}kid${T}50@Mon_Jan_01_00:10:00_2026${T}$A
devbox${T}ses${T}$E${T}-
local${T}ses${T}$B${T}-
-${T}gap${T}2${T}-
-${T}head${T}parked${T}-"
[[ "$(printf '%s\n' "$tree" | cut -f1-4)" == "$want" ]] || fail "the tree's rows: $(printf '%s\n' "$tree" | cut -f1-4)"
{ has "$tree" "Explore" && has "$tree" "running" && has "$tree" "pnpm test"; } || fail "the tree's lines: $tree"
mach="$(view list -v lens=machines -v W=110)"
[[ "$(printf '%s\n' "$mach" | cut -f1,2 | sed -n '1p;4p;5p')" == "local${T}mach
-${T}gap
devbox${T}mach" ]] || fail "the machines' headings: $mach"
has "$mach" "1 codex, 1 claude; 1 needs you, 1 to review" || fail "a machine's roll-up: $mach"
pass "lenses: Tree lists what runs under each session, Machines groups by machine with a roll-up"

# ---------------------------------------------------------------------------
# 3. What another machine sends is text: checked, never trusted.
# ---------------------------------------------------------------------------
esc=$'\033'
evil="$({
    printf 'local\tsys\tok\n'
    printf 'devbox\tsys\tfine%s[31m\n' "$esc"
    printf 'devbox\tses\t1; rm -rf ~\tneed\t5\tx\tclaude\tbad id\tp\n'
    printf 'devbox\tses\t7@Mon\tboom\t5\tx\tclaude\tbad state\tp\n'
    printf 'devbox\tses\t8@Mon\tneed\t5\tx\tCLAUDE$(id)\tbad kind\tp\n'
    printf 'devbox\tses\t9@Mon\tneed\tsoon\tper%s]0;owned%smission\tclaude\tti%s[2Jtle\tp\n' "$esc" $'\007' "$esc"
    printf 'devbox\tkid\t9@Mon\t$(id)\tsub\trun\t1\tx\n'
    printf 'devbox\tkid\t9@Mon\tok1\tsub\trun\t1\tfine\n'
    printf 'devbox\tkid\t404@Mon\tok2\tsub\trun\t1\tno such session\n'
} | _agents_board_view list -v lens=tree -v W=110)"
[[ "$(printf '%s\n' "$evil" | cut -f1-4)" == "devbox${T}ses${T}9@Mon${T}-
devbox${T}kid${T}ok1${T}9@Mon" ]] || fail "only rows of the right shape are rows: $evil"
if has "$evil" "$esc" || has "$evil" $'\007'; then fail "a control character reached the list"; fi
pass "untrusted rows: an id, a state and a kind must have their shape, and no control character gets through"

# ---------------------------------------------------------------------------
# 4. The right-hand side.
# ---------------------------------------------------------------------------
card="$(view card -v cm=local -v cid="$A")"
{ has "$card" "Fix flaky cache test" && has "$card" "myapp" && has "$card" "needs you" && has "$card" "wants permission"; } || fail "a card's top: $card"
{ has "$card" "RUNNING UNDER IT" && has "$card" "Explore" && has "$card" "reviewer" && has "$card" "pnpm test"; } || fail "a card lists what runs under it: $card"
has "$(view card -v cm=local -v cid="$B")" "RUNNING UNDER IT" && fail "nothing under a session: no such section"
has "$(view card -v cm=local -v cid="99@x")" "It is gone" || fail "a card for a session that ended"
has "$(view kid -v cm=local -v cid=abc123 -v cowner="$A")" "a sub-agent of Fix flaky cache test" || fail "a sub-agent's card"
has "$(view kid -v cm=local -v cid='50@Mon_Jan_01_00:10:00_2026' -v cowner="$A")" "a command of Fix flaky cache test" || fail "a command's card"
has "$(view group -v cid=parked)" "Old notes" || fail "the parked group's card lists them"
has "$(view mach -v cm=devbox)" "memory 20% free" || fail "a machine's card: its summary"
pass "card: why it waits and what runs under it; one for a kid, a group and a machine"

# The end of a pane is its output: the agent's input box and status lines,
# the rules and the line peek leads with are left out; a rule never wraps.
rule="$(printf '\342\224\200%.0s' 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40)"
pane_of() { _agents_awk "lib_fmt board_pane" -v n="${1:-14}" -v W="${2:-0}"; }
out="$(printf '%s\n' "$rule Herdr w1:p1 $rule" '  first line' '' '' '  the last line of output' '' "$rule" \
    "$(printf '\342\235\257') " "$rule" '  Model  ctx 15%' '  auto mode on' | sed "1s/.*/$(printf '\342\224\200\342\224\200') Herdr w1:p1 $(printf '\342\224\200\342\224\200')/" | pane_of)"
[[ "$out" == "  first line
  
  the last line of output" ]] || fail "a Claude Code pane ends at its output, its indent gone: $out"
out="$(printf '%s\n' 'output' "$rule my session $(printf '\342\224\200')" "$(printf '\342\235\257') typed" "$rule" 'status' | pane_of)"
[[ "$out" == "  output" ]] || fail "a rule that names the session is still the input box's: $out"
out="$(printf '%s\n' 'did a thing' '' "$(printf '\342\200\272') ask Codex anything" '  gpt-5 100% left' | pane_of)"
[[ "$out" == "  did a thing" ]] || fail "a Codex pane ends before its prompt: $out"
out="$(printf '%s\n' 'a table' "$rule" 'its rows' | pane_of 14 30)"
{ has "$out" "its rows" && [[ "$(printf '%s\n' "$out" | sed -n 2p | LC_ALL=C awk '{ print length($0) }')" -lt 90 ]]; } || fail "a rule in the output stays, cut to the width: $out"
out="$(printf '%s\n' "$rule" "$(printf '\342\235\257') " "$rule" | pane_of)"
has "$out" "$(printf '\342\235\257')" || fail "a pane that is only the input box is shown as it is: $out"
[[ "$(printf '%s\n' 1 2 3 4 5 | pane_of 2)" == "  4
  5" ]] || fail "the last n lines"
unset -f pane_of
pass "pane: the last lines of output, without the agent's input box, status lines and wrapping rules"

# The tabs: the active one stands out with color and without.
[[ "$(_agents_board_tabs Pane Card Trace Pane Details)" == "  Card  Trace [Pane] Details " ]] || fail "no color: the active tab in brackets: $(_agents_board_tabs Pane Card Trace Pane Details)"
out="$(NO_COLOR='' AGENTS_THEME=ansi TERM=xterm-256color; _agents_colors --always; _agents_board_tabs Pane Card Pane)"
has "$out" $'\033[7m Pane ' || fail "color: the active tab is a filled chip: $out"
_agents_colors
pass "tabs: the active one is a filled chip, or in brackets where there is no color"

# ---------------------------------------------------------------------------
# 5. The keys, as the fzf actions they print.
# ---------------------------------------------------------------------------
export AGENTS_BOARD_UI="$tmp/ui"
_agents_board_put lens attention
has "$(_agents_board_key lens-next)" "board --list" || fail "tab reloads the list"
[[ "$(_agents_board_get lens x)" == tree ]] || fail "tab: Attention to Tree"
_agents_board_key lens-next >/dev/null; [[ "$(_agents_board_get lens x)" == machines ]] || fail "tab: Tree to Machines"
_agents_board_key lens-next >/dev/null; [[ "$(_agents_board_get lens x)" == attention ]] || fail "tab: Machines to Attention"
_agents_board_key lens-prev >/dev/null; [[ "$(_agents_board_get lens x)" == machines ]] || fail "shift-tab goes the other way"
_agents_board_key lens-2 >/dev/null; [[ "$(_agents_board_get lens x)" == tree ]] || fail "2 picks Tree"
_agents_board_put view card
for v in trace pane details card; do
    _agents_board_key view-next >/dev/null; [[ "$(_agents_board_get view x)" == "$v" ]] || fail "right: on to $v, not $(_agents_board_get view x)"
done
for v in details pane trace card; do
    _agents_board_key view-prev >/dev/null; [[ "$(_agents_board_get view x)" == "$v" ]] || fail "left: back to $v, not $(_agents_board_get view x)"
done
_agents_board_key parked >/dev/null; [[ "$(_agents_board_get all x)" == 1 ]] || fail ". shows the parked"
_agents_board_put side 0; _agents_board_key view-next >/dev/null
[[ "$(_agents_board_get side x)" == 1 ]] || fail "a view shows the right-hand side, and says so for space"
_agents_board_put side 0; _agents_board_key help >/dev/null; _agents_board_key help >/dev/null
[[ "$(_agents_board_get side x)" == 1 ]] || fail "the keys show the right-hand side, and say so for space"
pass "keys: the lens and the view (Card, Trace, Pane, Details) cycle, the parked toggle, the side kept true"

go="$(_agents_board_key go local ses "$A" -)"
{ has "$go" "execute-silent(" && has "$go" "--act go {1} {2} {3} {4})"; } || fail "enter on a session here: $go"
if has "$go" "$A" || has "$go" abort; then fail "a row's fields reach the command as fzf's placeholders only, and a tab stays open: $go"; fi
has "$(AGENTS_BOARD_POPUP=1 _agents_board_key go local ses "$A" -)" "+abort" || fail "enter in a popup closes it"
[[ "$(_agents_board_key go devbox ses "$D" -)" == "execute("* ]] || fail "enter on another machine's session shows it"
[[ -z "$(_agents_board_key go - head need -)" ]] || fail "enter on a heading does nothing"
[[ -z "$(_agents_board_key stop - head need -)" ]] || fail "ctrl-k on a heading does nothing"
has "$(_agents_board_key stop local ses "$A" -)" "--act stop {1} {2} {3} {4}" || fail "ctrl-k stops through agents kill"
has "$(_agents_board_key stop local kid '50@Mon_Jan_01_00:10:00_2026' "$A")" "--act stop" || fail "ctrl-k stops a command"
[[ -z "$(_agents_board_key stop local kid abc123 "$A")" ]] || fail "ctrl-k on a sub-agent does nothing: no process of its own"
{ _agents_board_idok sub a12 && ! _agents_board_idok sub 4321; } || fail "a sub-agent id needs a letter: one of digits alone would read as a process id"
for k in lens-next parked side; do
    [[ "$(_agents_board_key "$k")" == *"board --list)"* ]] || fail "$k reloads the list, which keeps the board's machine"
done
pass "keys: enter goes (and closes a popup), ctrl-k stops (not a sub-agent), headings do nothing"

_agents_board_put help 1
[[ "$(_agents_board_key esc)" == refresh-preview && "$(_agents_board_get help x)" == 0 ]] || fail "esc closes the keys first"
has "$(FZF_INPUT_STATE=enabled _agents_board_key esc)" "hide-input+disable-search" || fail "esc ends find"
[[ -z "$(_agents_board_key esc)" ]] || fail "esc never closes a board left open"
[[ "$(AGENTS_BOARD_POPUP=1 _agents_board_key esc)" == abort ]] || fail "esc closes a popup"
has "$(FZF_CLICK_FOOTER_WORD=lens _agents_board_key footer local ses "$A" -)" "board --list" || fail "the footer's lens is a button"
has "$(FZF_CLICK_FOOTER_WORD=enter _agents_board_key footer local ses "$A" -)" "--act go" || fail "the footer's enter is a button"
[[ -z "$(FZF_CLICK_FOOTER_WORD=nothing _agents_board_key footer local ses "$A" -)" ]] || fail "a word that is no button"
pass "keys: esc closes the keys, then find, then a popup only; the footer's words are buttons"

# ---------------------------------------------------------------------------
# 6. Actions take an id only in its shape; back needs a pane to go to.
# ---------------------------------------------------------------------------
{ _agents_board_idok ses "$A" && _agents_board_idok sub abc123; } || fail "ids of the right shape"
if _agents_board_idok ses '1;id' || _agents_board_idok sub 'a b' || _agents_board_idok head x; then fail "an id of the wrong shape"; fi
out="$(_agents_board_act stop local ses '1; rm -rf ~' - 2>&1)" && fail "stop took a bad id"
has "$out" "not an id" || fail "a bad id is refused: $out"
_agents_board_act back - - - - 2>/dev/null && fail "back with no pane recorded"
: > "$tmp/calls"
_agents_map_act() { printf '%s\n' "$*" >> "$tmp/calls"; }
AGENTS_BOARD_FROM='w1:p7' _agents_board_act go local ses "$A" -
[[ "$(cat "$tmp/calls")" == "go local proc $A" && "$(cat "$AGENTS_RUN_DIR/board/back")" == "w1:p7" ]] || fail "go: through the map's action, the pane to come back to kept"
AGENTS_BOARD_FROM='w1;p7' _agents_board_act go local ses "$B" -
[[ "$(cat "$AGENTS_RUN_DIR/board/back")" == "w1:p7" ]] || fail "a pane id of the wrong shape is not kept"
: > "$tmp/calls"
_agents_board_act go devbox kid abc123 "$D"
[[ "$(cat "$tmp/calls")" == "go devbox proc $D" ]] || fail "enter on another machine's sub-agent looks at its session: $(cat "$tmp/calls")"
pass "actions: ids checked, go is the map's own, the pane you came from is remembered"

# ---------------------------------------------------------------------------
# 6b. Other machines: asked once at a time, a reason when they don't answer;
#     a board keeps its machine.
# ---------------------------------------------------------------------------
_agents_machines() { printf 'devbox\tdevbox\n'; }
fetches="$tmp/fetches"   # not $tmp: the fetch has a local of that name
_agents_ssh_mux() { printf 'x\n' >> "$fetches"; sleep 1; printf 'sys\tok\n'; }
key="$(printf '%s' devbox | cksum)"
mkdir -p "$AGENTS_RUN_DIR/board"
printf 'at\t%s\nsys\told\n' $((AGENTS_NOW - 100)) > "$AGENTS_RUN_DIR/board/m.${key%% *}"
: > "$tmp/fetches"
for _ in 1 2 3; do ( _agents_board_all devbox >/dev/null ); done
sleep 1.5
[[ "$(wc -l < "$tmp/fetches" | tr -d ' ')" == 1 ]] || fail "three reloads while one machine is asked: one ssh, not $(wc -l < "$tmp/fetches")"
rm -rf "$AGENTS_RUN_DIR/board/m.${key%% *}".lock
pass "machines: a reload that finds a machine being asked does not ask again (the fetcher holds the lock)"

mkdir -p "$tmp/rh/.local/bin"
remote() { HOME="$tmp/rh" sh -c "$_AGENTS_BOARD_REMOTE_CMD"; }
has "$(remote)" "no agents there (tuidev install --pack monitoring)" || fail "no agents there: $(remote)"
printf '#!/bin/sh\ncase "$1" in help) echo "usage: agents [status]" ;; *) exit 2 ;; esac\n' > "$tmp/rh/.local/bin/agents"; chmod +x "$tmp/rh/.local/bin/agents"
has "$(remote)" "needs a newer tuidev there" || fail "an agents with no board: $(remote)"
printf '#!/bin/sh\ncase "$1" in help) echo "  agents board [MACHINE|local]" ;; *) exit 1 ;; esac\n' > "$tmp/rh/.local/bin/agents"
has "$(remote)" "no answer from agents there" || fail "a board that failed: $(remote)"
pass "machines: why one sent no rows: no agents, an older tuidev, or no answer"

_agents_board_all() { printf 'only=%s\n' "${1:-}" >> "$tmp/only"; }
: > "$tmp/only"
( AGENTS_BOARD_ONLY=devbox _agents_board_list >/dev/null; _agents_board_list workbox >/dev/null )
[[ "$(cat "$tmp/only")" == "only=devbox
only=workbox" ]] || fail "a list keeps the board's machine: $(cat "$tmp/only")"
[[ -f "$tmp/ui.rows" && ! -e "$AGENTS_RUN_DIR/board/rows" ]] || fail "a board's rows are its own (ui.PID.rows), not shared"
pass "list: every reload keeps the board's machine; its rows are the board's own"

# ---------------------------------------------------------------------------
# 7. Without a terminal: the list as text. The limits line.
# ---------------------------------------------------------------------------
_agents_board_all() { fixture; }
_agents_limits_lines() { printf 'limit\tClaude\t5h\t62\t14:10\tclaude\t10\nlimit\tClaude\tweek\t30\tMon\tclaude\t10\nlimit\tCodex\tweek\t18\tMon\tcodex\t10\n'; }
unset AGENTS_BOARD_UI
out="$(agents_board 2>/dev/null)"
{ has "$out" "NEEDS YOU" && has "$out" "Review auth diff"; } || fail "no terminal: the list: $out"
has "$out" "+1 sub, 1 cmd" || fail "no terminal: the whole width, counts and all: $out"
[[ -z "$(find "$AGENTS_RUN_DIR/board" -name 'rows*' -o -name 'header*')" ]] || fail "no terminal: no file left"
if has "$out" "$T"; then fail "no terminal: only the text, no id columns"; fi
[[ "$(_agents_board_limits)" == "Claude 62% of 5h · Codex 18% of week" ]] || fail "limits: each CLI's fullest window: $(_agents_board_limits)"
out="$(agents_board --bogus 2>&1)" && fail "an unknown option"
has "$out" "usage: agents board" || fail "usage: $out"
pass "no terminal: the list as plain text; the limits line; usage"

# A board's header leads with the lens tabs, and what fzf reads from a board
# is in color though it is a pipe.
( export AGENTS_BOARD_UI="$tmp/uih"
  _agents_board_put lens tree; _agents_board_put side 1
  FZF_COLUMNS=200 _agents_board_list >/dev/null
  hdr="$(_agents_board_header)"
  [[ "$(printf '%s\n' "$hdr" | sed -n 1p)" == "  Attention [Tree] Machines " ]] || fail "the header's first line is the lens tabs: $hdr"
  [[ -z "$(printf '%s\n' "$hdr" | sed -n 2p)" ]] && has "$(printf '%s\n' "$hdr" | sed -n 3p)" "2 need you" || fail "then an empty line and the counts: $hdr"
  [[ "$(_agents_board_key lens-next)" != *change-list-label* ]] || fail "a lens change reloads the list; the header carries the tabs"
  NO_COLOR='' AGENTS_THEME=ansi TERM=xterm-256color
  has "$(_agents_board_list | head -n 1)" $'\033[' || fail "a board's list is in color through a pipe"
  unset AGENTS_BOARD_UI
  if has "$(_agents_board_list | head -n 1)" $'\033['; then fail "the plain list through a pipe has no color"; fi
) || exit 1
rm -f "$tmp"/uih.*
pass "header: the lens tabs lead it; a board's own output is in color"

# ---------------------------------------------------------------------------
# 8. The plugin opens it, and hands over the pane you were in.
# ---------------------------------------------------------------------------
plugin="$REPO_DIR/configs/herdr/plugins/tuidev-link"
{ grep -q 'id = "board"' "$plugin/herdr-plugin.toml" && grep -q 'command = \["sh", "run.sh", "board-pane"\]' "$plugin/herdr-plugin.toml"; } || fail "the plugin has no board"
{ grep -q 'key = "prefix+space"' "$REPO_DIR/configs/herdr/keys.toml" && grep -q 'command = "tuidev.link.board"' "$REPO_DIR/configs/herdr/keys.toml"; } || fail "no key for the board"
cat > "$tmp/herdr" <<'EOF'
#!/bin/sh
printf '%s\n' "$@" > "$CALLS"
EOF
cat > "$tmp/agents" <<'EOF'
#!/bin/sh
printf '%s\n' "$@" > "$CALLS"
EOF
chmod +x "$tmp/herdr" "$tmp/agents"
run() { ( cd "$plugin" && CALLS="$tmp/pcalls" AGENTS_BIN="$tmp/agents" HERDR_BIN_PATH="$tmp/herdr" HERDR_PLUGIN_ID=tuidev.link "$@" sh run.sh "${cmd[@]}" ); }
cmd=(board); run env HERDR_PANE_ID='w3:p1'
[[ "$(tr '\n' ' ' < "$tmp/pcalls")" == "plugin pane open --plugin tuidev.link --entrypoint board --env AGENTS_BOARD_FROM=w3:p1 " ]] || fail "board: $(cat "$tmp/pcalls")"
cmd=(board); run env HERDR_PANE_ID='w3 p1; id'
[[ "$(tr '\n' ' ' < "$tmp/pcalls")" == "plugin pane open --plugin tuidev.link --entrypoint board " ]] || fail "a pane id of the wrong shape is not passed on: $(cat "$tmp/pcalls")"
cmd=(board-pane); run env
[[ "$(tr '\n' ' ' < "$tmp/pcalls")" == "board --popup " ]] || fail "board-pane: $(cat "$tmp/pcalls")"
cmd=(board-tab-pane); run env
[[ "$(tr '\n' ' ' < "$tmp/pcalls")" == "board " ]] || fail "board-tab-pane: $(cat "$tmp/pcalls")"
pass "plugin: prefix+space opens the board over your pane and says which pane that was"

# ---------------------------------------------------------------------------
# 9. Trace: what a session did, from the end of its transcript.
# ---------------------------------------------------------------------------
txf="$tmp/tx.jsonl"
{
    printf '%s\n' '{"type":"a partial line that the tail cut"}'
    printf '%s\n' '{"type":"user","message":{"role":"user","content":"fix the flaky cache test\nwith more lines"},"timestamp":"2026-11-18T14:02:10.123Z"}'
    printf '%s\n' '{"type":"user","isMeta":true,"message":{"role":"user","content":"meta"},"timestamp":"2026-11-18T14:02:11Z"}'
    printf '%s\n' '{"type":"user","isCompactSummary":true,"message":{"role":"user","content":"This session is being continued"},"timestamp":"2026-11-18T14:02:12Z"}'
    printf '%s\n' '{"type":"user","message":{"role":"user","content":"<system-reminder>not yours</system-reminder>"},"timestamp":"2026-11-18T14:02:13Z"}'
    printf '%s\n' '{"type":"user","message":{"role":"user","content":"<command-name>/review</command-name>\n<command-args></command-args>"},"timestamp":"2026-11-18T14:03:00Z"}'
    printf '%s\n' '{"type":"api-request-blob","message":{"content":"x"},"note":"\"type\":\"user\""}'
    printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"r1","name":"Read","input":{"file_path":"/w/myapp/README.md"}},{"type":"tool_use","id":"e1","name":"Edit","input":{"file_path":"/w/myapp/src/cache.ts"}}]},"timestamp":"2026-11-18T14:04:00Z"}'
    printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"e2","name":"Write","input":{"file_path":"/w/myapp/src/cache.test.ts"}},{"type":"tool_use","id":"e3","name":"Edit","input":{"file_path":"/w/myapp/src/cache.ts"}}]},"timestamp":"2026-11-18T14:04:30Z"}'
    printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"b1","name":"Bash","input":{"command":"cd /w/myapp && FOO=1 pnpm test cache --run --reporter dot extra words"}}]},"timestamp":"2026-11-18T14:05:00Z"}'
    printf '%s\n' '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"b1","is_error":true,"content":"Exit code 1\nFAIL cache.test.ts"}]},"timestamp":"2026-11-18T14:05:20Z"}'
    printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"b2","name":"Bash","input":{"command":"pnpm lint"}},{"type":"tool_use","id":"b3","name":"Bash","input":{"command":"pnpm lint"}}]},"timestamp":"2026-11-18T14:06:00Z"}'
    printf '%s\n' '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"b2","content":"ok"}]},"timestamp":"2026-11-18T14:06:10Z"}'
    printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"a1","name":"Agent","input":{"subagent_type":"Explore","description":"find the cache tests","prompt":"long"}}]},"timestamp":"2026-11-18T14:07:00Z"}'
    printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"q1","name":"AskUserQuestion","input":{"questions":[{"question":"Which cache?\nmore"}]}}]},"timestamp":"2026-11-18T14:08:00Z"}'
    printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"b4","name":"Bash","input":{"command":"rm -rf build"}}]},"timestamp":"2026-11-18T14:09:00Z"}'
    printf '%s\n' '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"b4","is_error":true,"content":"Permission for this action was denied by the auto mode classifier."}]},"timestamp":"2026-11-18T14:09:05Z"}'
    printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"w1","name":"WebFetch","input":{"url":"https://example.com"}}]},"timestamp":"2026-11-18T14:10:00Z"}'
    printf '%s\n' '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"w1","is_error":true,"content":[{"type":"text","text":"The user doesn'"'"'t want to proceed with this tool use."}]}]},"timestamp":"2026-11-18T14:10:05Z"}'
    printf '%s\n' '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"[Request interrupted by user]"}]},"timestamp":"2026-11-18T14:11:00Z"}'
    printf '%s\n' '{"type":"user","message":{"role":"user","content":"now \u001b[31mred\u001b]0;owned\u0007 text"},"timestamp":"2026-11-18T14:12:00Z"}'
} > "$txf"
trace="$(sed 1d "$txf" | jq -Rnr --argjson n 40 "$_AGENTS_BOARD_TRACE_JQ")"
want="14:02${T}you${T}fix the flaky cache test${T}-${T}1
14:03${T}you${T}/review${T}-${T}1
14:04${T}edit${T}cache.ts, cache.test.ts${T}-${T}1
14:05${T}run${T}pnpm test cache --run --reporter dot${T}exit 1${T}1
14:06${T}run${T}pnpm lint${T}-${T}2
14:07${T}agent${T}Explore: find the cache tests${T}-${T}1
14:08${T}ask${T}Which cache?${T}-${T}1
14:09${T}run${T}rm -rf build${T}denied${T}1
14:10${T}denied${T}WebFetch${T}-${T}1
14:11${T}stop${T}you interrupted it${T}-${T}1
14:12${T}you${T}now [31mred ]0;owned text${T}-${T}1"
[[ "$trace" == "$want" ]] || fail "the trace's events: $trace"
pass "trace: prompts, a run of edits in one line, commands with their exit code, sub-agents, questions, denials; repeats counted"

[[ -z "$(_agents_board_transcript "$$@Mon_Jan_01_00:00:00_1990")" ]] || fail "a process that is not the one the row named has no transcript"
export AGENTS_BOARD_UI="$tmp/ui"
fixture > "$tmp/ui.rows"
_agents_board_transcript() { [[ "$1" == "$A" ]] && printf '%s\n' "$txf"; }
out="$(FZF_PREVIEW_COLUMNS=70 _agents_board_trace local "$A" 40)"
{ has "$out" "14:05  run     pnpm test cache --run --reporter dot" && has "$out" "exit 1" && has "$out" "pnpm lint x2"; } || fail "the trace's lines: $out"
[[ "$(printf '%s\n' "$out" | tail -1)" == *"14:12  you"* ]] || fail "the newest is at the bottom: $out"
if has "$out" "$esc" || has "$out" $'\007'; then fail "a control character in a transcript reached the trace"; fi
[[ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" == 11 ]] || fail "one line an event: $out"
out="$(_agents_board_trace local "$A" 5)"
[[ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" == 3 && "$out" == *"14:10"*"14:11"*"14:12"* ]] || fail "as many as fit, the newest: $out"
has "$(_agents_board_trace local "$B" 40)" "for Claude Code sessions (this one is codex)" || fail "a Codex session's trace says what it is for"
has "$(_agents_board_trace devbox "$D" 40)" "read on devbox" || fail "another machine's session: read there, enter looks"
has "$(_agents_board_trace local "$C" 40)" "can be found" || fail "a session whose transcript is not found"
_agents_board_put view trace; _agents_board_put help 0
out="$(FZF_PREVIEW_LINES=20 _agents_board_peek local ses "$A" -)"
{ has "$out" "Trace" && has "$out" "pnpm lint"; } || fail "the right-hand side's Trace view: $out"
mkdir -p "${txf%.jsonl}/subagents"
{ printf '{"x":1}\n'
  printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"text","text":"done \u009b31m and \u202eevil\u2028 here"}]}}'
} > "${txf%.jsonl}/subagents/agent-abc123.jsonl"
said="$(_agents_board_sub_said "$A" abc123)"
has "$said" "done" || fail "a sub-agent's last lines: $said"
if has "$said" $'\302\233' || has "$said" $'\342\200\256' || has "$said" $'\342\200\250'; then fail "a C1 control or a bidi override reached a sub-agent's lines"; fi
printf '%s\n' '{"type":"user","message":{"role":"user","content":"why \u009b31m \u202eevil"},"timestamp":"2026-11-18T14:13:00Z"}' >> "$txf"
out="$(_agents_board_trace local "$A" 40)"
if has "$out" $'\302\233' || has "$out" $'\342\200\256'; then fail "a C1 control or a bidi override reached the trace"; fi
unset AGENTS_BOARD_UI
pass "trace: as text that fits, newest at the bottom, no control character; Codex, another machine and no transcript say so"

# ---------------------------------------------------------------------------
# 10. Back: to any pane, an agent's or not.
# ---------------------------------------------------------------------------
mkdir -p "$tmp/bin"
cat > "$tmp/bin/herdr" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$HCALLS"
case "$1 $2" in
    "agent focus") [ "${HAGENT:-}" = ok ] ;;
    "pane get") printf '{"id":"x","result":{"pane":{"pane_id":"%s","tab_id":"w1:t2","label":"zsh"}}}\n' "$3" ;;
    "tab focus") exit 0 ;;
esac
EOF
cat > "$tmp/bin/nc" <<'EOF'
#!/bin/sh
cat > "$NCIN"
printf '%s\n' "${NCREPLY:-}"
EOF
chmod +x "$tmp/bin/herdr" "$tmp/bin/nc"
# NAME=VALUE... for one call (env runs no function).
with() { local kv; for kv in "$@"; do export "${kv?}"; done; }
back() { ( export PATH="$tmp/bin:$PATH" HCALLS="$tmp/hcalls" NCIN="$tmp/ncin"; with "$@"; _agents_board_act back - - - - ); }
: > "$tmp/hcalls"; rm -f "$tmp/ncin"
printf 'w1:p7\n' > "$AGENTS_RUN_DIR/board/back"
back HAGENT=ok
[[ "$(cat "$tmp/hcalls")" == "agent focus w1:p7" && ! -e "$tmp/ncin" ]] || fail "back to an agent's pane: herdr agent focus: $(cat "$tmp/hcalls")"
: > "$tmp/hcalls"
back NCREPLY='{"id":"agents:board","result":{"type":"pane_info"}}'
[[ "$(cat "$tmp/ncin")" == '{"id":"agents:board","method":"pane.focus","params":{"pane_id":"w1:p7"}}' ]] || fail "a plain pane: the socket's pane.focus: $(cat "$tmp/ncin")"
has "$(cat "$tmp/hcalls")" "tab focus" && fail "pane.focus did it: no tab focus"
: > "$tmp/hcalls"
back NCREPLY='{"error":{"code":"unknown_method"}}'
[[ "$(tail -1 "$tmp/hcalls")" == "tab focus w1:t2" ]] || fail "no pane.focus: its tab: $(cat "$tmp/hcalls")"
rm -f "$AGENTS_RUN_DIR/board/back"; : > "$tmp/hcalls"
back HAGENT=ok AGENTS_BOARD_FROM='w1:p3'
[[ "$(cat "$tmp/hcalls")" == "agent focus w1:p3" ]] || fail "no go yet: back to the pane the board was opened over: $(cat "$tmp/hcalls")"
pass "back: an agent's pane by agent focus, any other by the socket's pane.focus, else its tab; before a go, the pane it was opened over"

# ---------------------------------------------------------------------------
# 11. Live: a board listens, and a poke reloads it.
# ---------------------------------------------------------------------------
cat > "$tmp/bin/fzf" <<'EOF'
#!/bin/sh
for a in "$@"; do case "$a" in --listen=*.sock) [ -z "${FZF_NOSOCK:-}" ] || exit 2 ;; esac; done
exit 1
EOF
cat > "$tmp/bin/curl" <<'EOF'
#!/bin/sh
printf 'argv %s\n' "$*" >> "$CCALLS"
EOF
chmod +x "$tmp/bin/fzf" "$tmp/bin/curl"
bd="$AGENTS_RUN_DIR/board"
# A start time for a process that runs (ps is not for the tests).
_agents_start() { kill -0 "$1" 2>/dev/null && echo T1; return 0; }
listen() { ( export PATH="$tmp/bin:$PATH" AGENTS_FZF="$tmp/bin/fzf" AGENTS_BOARD_UI="$bd/ui.$$"; with "$@"; _agents_board_listen L && printf '%s|%s\n' "$L" "${FZF_API_KEY:-}" ); }
out="$(listen FZF_API_KEY=mine)"
[[ "$out" == "--listen=$bd/ui.$$.sock|" && "$(cat "$bd/ui.$$.listen")" == "T1${T}sock" ]] || fail "a socket where fzf takes one, and no key: $out"
[[ -n "$(find "$bd/ui.$$.listen" -perm 600)" ]] || fail "only you can read the record"
cp "$bd/ui.$$.listen" "$tmp/listen.kept"; rm -f "$bd/ui.$$.listen"
listen FZF_NOSOCK=1 >/dev/null && fail "an fzf with no socket: no listening (never a port)"
listen PATH="$tmp/nocurl" >/dev/null && fail "no curl: no listening"
listen AGENTS_BOARD_UI="$bd/$(printf '%090d' 0)/ui.1" >/dev/null && fail "a path too long for a socket: no listening"
[[ ! -e "$bd/ui.$$.listen" && -z "$(find "$bd" -name '*.port' -o -name '*key*')" ]] || fail "no record, and never a port or a key file, where it can't listen"
[[ "$(_agents_board_every 1)" == 15 && "$(_agents_board_every 0)" == 5 && "$(AGENTS_BOARD_EVERY=7 _agents_board_every 1)" == 7 ]] || fail "the timer: 15 s while listening, 5 s on its own, or AGENTS_BOARD_EVERY"
cp "$tmp/listen.kept" "$bd/ui.$$.listen"
pass "listen: a Unix socket only you can open, else no listening and the 5 s timer; never a port or a key"

: > "$tmp/ccalls"
printf 'T0\tsock\n' > "$bd/ui.999999.listen"; : > "$bd/ui.999999.lens"
poke() { ( PATH="$tmp/bin:$PATH" CCALLS="$tmp/ccalls" _agents_board_poke ); }
poke
[[ "$(cat "$tmp/ccalls")" == "argv -s -m 1 -o /dev/null --unix-socket $bd/ui.$$.sock --data-raw trigger(ctrl-r) http://localhost" ]] || fail "a poke posts ctrl-r to each live board: $(cat "$tmp/ccalls")"
[[ ! -e "$bd/ui.999999.listen" && ! -e "$bd/ui.999999.lens" ]] || fail "a dead board's record and files are removed"
printf 'T0\tsock\n' > "$bd/ui.$$.listen"; : > "$bd/ui.$$.lens"; : > "$tmp/ccalls"
poke
[[ ! -e "$bd/ui.$$.listen" && -e "$bd/ui.$$.lens" && ! -s "$tmp/ccalls" ]] || fail "a pid that is another process now: its record goes, nothing else, no post"
rm -f "$bd"/ui.*; : > "$tmp/ccalls"
poke
[[ ! -s "$tmp/ccalls" && ! -e "$bd/poke.lock" ]] || fail "no board: no post and no lock"
: > "$bd/ui.$$.listen"; mkdir "$bd/poke.lock"; printf '%s T1\n' "$$" > "$bd/poke.lock/holder"
poke
[[ -e "$bd/poke.dirty" && ! -s "$tmp/ccalls" ]] || fail "a poke while one runs leaves a mark for it"
rm -rf "$bd/poke.lock" "$bd/poke.dirty" "$bd"/ui.*
pass "poke: ctrl-r posted to each board's socket, a dead board's files swept, a reused pid's record only, a burst is one"

cat > "$tmp/bin/ps" <<'EOF'
#!/bin/sh
[ -n "${LIVE:-}" ] || exit 1
printf '%s\n' $LIVE
EOF
chmod +x "$tmp/bin/ps"
leftovers="ui.999999.lens ui.999999.header.999998 rows.999999 machines.999999 list.999999 m.42.999999"
for f in $leftovers ui.$$.lens m.42; do : > "$bd/$f"; done; mkdir -p "$bd/m.42.lock"
( PATH="$tmp/bin:$PATH" _agents_board_sweep )
[[ -e "$bd/ui.999999.lens" ]] || fail "ps can't list the pids (a sandbox): nothing swept"
( PATH="$tmp/bin:$PATH" LIVE="1 $$" _agents_board_sweep )
for f in $leftovers; do [[ ! -e "$bd/$f" ]] || fail "a gone board's or list's file is swept: $f"; done
[[ -e "$bd/ui.$$.lens" && -e "$bd/m.42" && -d "$bd/m.42.lock" ]] || fail "a live board's files, a machine's answer and its lock stay"
rm -rf "$bd"/ui.* "$bd"/m.42*
pass "sweep: what gone boards and lists left, never a live board's, nothing when ps can't tell"

# ---------------------------------------------------------------------------
# 12. The plugin: hooks poke an open board; one board tab.
# ---------------------------------------------------------------------------
cat > "$tmp/agents" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$CALLS.agents"
EOF
chmod +x "$tmp/agents"
hook() { rm -f "$tmp/pcalls.agents"; ( cd "$plugin" && CALLS="$tmp/pcalls" AGENTS_BIN="$tmp/agents" AGENTS_RUN_DIR="$AGENTS_RUN_DIR" sh run.sh "$@" ); }
hook sync
[[ "$(cat "$tmp/pcalls.agents")" == "herdr sync -q" ]] || fail "no board: the sync alone: $(cat "$tmp/pcalls.agents")"
: > "$bd/ui.123.listen"
hook sync-poke
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do grep -q 'board --poke' "$tmp/pcalls.agents" && break; sleep 0.1; done
{ grep -qx 'board --poke' "$tmp/pcalls.agents" && grep -qx 'herdr sync -q --poke' "$tmp/pcalls.agents"; } || fail "a board listens: the hook pokes it: $(cat "$tmp/pcalls.agents")"
rm -f "$bd/ui.123.listen"
pass "plugin: an event hook pokes an open board, and costs nothing more when none is"

state="$tmp/pstate"; mkdir -p "$state"
cat > "$tmp/herdr" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$CALLS"
case "$1 $2" in
    "pane get") [ "$3" = w1:p4 ] && printf '{"id":"x","result":{"pane":{"pane_id":"w1:p4","label":"%s"}}}\n' "${LABEL:-Board}" ;;
    "plugin pane") [ "$3" != focus ] || [ "$4" = w1:p4 ] ;;
esac
EOF
chmod +x "$tmp/herdr"
cmd=(board-tab-pane); : > "$tmp/pcalls"; run env HERDR_PANE_ID='w1:p4' HERDR_PLUGIN_STATE_DIR="$state"
[[ "$(cat "$state/board-tab")" == "w1:p4" ]] || fail "the board tab's pane is kept"
cmd=(board-tab); : > "$tmp/pcalls"; run env HERDR_PANE_ID='w1:p1' HERDR_PLUGIN_STATE_DIR="$state"
[[ "$(tail -1 "$tmp/pcalls")" == "plugin pane focus w1:p4" ]] || fail "the open board tab is focused, not a second opened: $(cat "$tmp/pcalls")"
: > "$tmp/pcalls"; run env HERDR_PANE_ID='w1:p1' HERDR_PLUGIN_STATE_DIR="$state" LABEL=zsh
[[ "$(tail -1 "$tmp/pcalls")" == "plugin pane open --plugin tuidev.link --entrypoint board-tab --env AGENTS_BOARD_FROM=w1:p1" ]] || fail "a pane that is no board now: a new tab: $(cat "$tmp/pcalls")"
printf 'w1:p9\n' > "$state/board-tab"; : > "$tmp/pcalls"; run env HERDR_PLUGIN_STATE_DIR="$state"
[[ "$(tail -1 "$tmp/pcalls")" == "plugin pane open --plugin tuidev.link --entrypoint board-tab" ]] || fail "a board tab that closed: a new one: $(cat "$tmp/pcalls")"
cmd=(board); : > "$tmp/pcalls"; run env HERDR_PANE_ID='w1:p1' HERDR_PLUGIN_STATE_DIR="$state"
has "$(cat "$tmp/pcalls")" "pane get" && fail "the popup opens fresh each time"
pass "plugin: prefix+shift+space focuses the board tab that is open, else opens one"

# ---------------------------------------------------------------------------
# 13. A machine's rows are bounded, parked follows `all` in every lens, and a
#     machine is listed once it sent any valid row.
# ---------------------------------------------------------------------------
flood() { # flood MACHINE COUNT — COUNT need rows, each with its own id
    awk -v m="$1" -v n="$2" 'BEGIN { for (i = 1; i <= n; i++) printf "%s\tses\t%d@Mon_Jan_01_00:00:01_2026\tneed\t%d\tblocked\tcodex\tTask %d\tp\n", m, i, i, i }'
}
SECONDS=0
big="$({ printf 'local\tsys\tok\n'; flood devbox 5000; } | _agents_board_view list -v lens=attention -v W=110)"
[[ $SECONDS -le 10 ]] || fail "5,000 rows from one machine took ${SECONDS}s to render"
n="$(printf '%s\n' "$big" | cut -f1,2 | grep -c "^devbox${T}ses$")"
{ [[ "$n" == 200 ]] && has "$big" "+4800 sessions not shown"; } || fail "a machine's sessions are capped and the rest said: $n"
SECONDS=0
many="$({ for m in m1 m2 m3 m4 m5; do printf '%s\tsys\tok\n' "$m"; flood "$m" 1000; done; } | _agents_board_view list -v lens=machines -v W=110)"
[[ $SECONDS -le 10 ]] || fail "5 machines of 1,000 rows took ${SECONDS}s to render"
[[ "$(printf '%s\n' "$many" | cut -f2 | grep -c '^ses$')" == 1000 ]] || fail "5 machines keep 200 each"
pass "bounds: one machine shows at most 200 sessions, says how many it left out, and stays fast"

pk="$(fixture | _agents_board_view list -v lens=tree -v all=0 -v W=110 | cut -f1-3)"
if has "$pk" "local${T}ses${T}$C"; then fail "tree: parked hidden without all: $pk"; fi
has "$pk" "-${T}head${T}parked" || fail "tree: a parked line without all: $pk"
pk="$(fixture | _agents_board_view list -v lens=tree -v all=1 -v W=110 | cut -f1-3)"
has "$pk" "local${T}ses${T}$C" || fail "tree: all=1 lists the parked: $pk"
pk="$(fixture | _agents_board_view list -v lens=machines -v all=0 -v W=110)"
if has "$(printf '%s\n' "$pk" | cut -f1-3)" "local${T}ses${T}$C"; then fail "machines: parked hidden without all: $pk"; fi
has "$pk" "1 parked, hidden" || fail "machines: the roll-up says the parked are hidden: $pk"
pk="$(fixture | _agents_board_view list -v lens=machines -v all=1 -v W=110)"
has "$(printf '%s\n' "$pk" | cut -f1-3)" "local${T}ses${T}$C" || fail "machines: all=1 lists the parked: $pk"
if has "$pk" "hidden"; then fail "machines: nothing is hidden with all=1: $pk"; fi
pass "lenses: parked sessions follow all in Tree and Machines, and the roll-up says when they are hidden"

nosys="$({ printf 'local\tsys\tok\n'; printf 'quiet\tses\t%s\trun\t5\tx\tcodex\tNo summary\tp\n' "$A"; } | _agents_board_view list -v lens=machines -v W=110 | cut -f1,2)"
has "$nosys" "quiet${T}mach" || fail "a machine with no sys line is listed: $nosys"
pass "machines: one that sent a session but no summary still appears"

echo "ALL PASS"
