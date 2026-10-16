#!/bin/bash
# Unit tests for the usage limits (lib/agents/limits.sh, statusline.sh,
# grok.sh): limits.tsv's upsert and prune, `agents statusline` (Claude Code's
# status line JSON, with and without rate_limits, your own command, no jq),
# the Antigravity probe, Grok's tokens, `agents limits`, the tsv records and
# the menu's Usage section; and the session names of the CLIs they cover.
# Run: bash scripts/lib/test_agents_limits.sh  -> exit 0 on pass.
#
# Everything runs in temp dirs with a fixed clock (AGENTS_NOW; the statusline
# and the probe read it too) and stubs for agy and jq: nothing real is read,
# no CLI runs.

# Tests change variables inside ( … ) on purpose; the stubs are called by the
# sourced functions; the stub scripts' $0 and "$@" are theirs.
# shellcheck disable=SC2016,SC2030,SC2031,SC2034,SC2317,SC2329
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/tuidev-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
for v in XDG_CONFIG_HOME XDG_STATE_HOME TUIDEV_STATE_DIR AGENTS_HISTORY AGENTS_STATUSLINE_CMD GROK_HOME; do unset "$v"; done
export HOME="$tmp/home" NO_COLOR=1 TZ=UTC AGENTS_CONF="$tmp/none.conf" AGENTS_DATA_DIR="$tmp/data" AGENTS_RUN_DIR="$tmp/run"
export AGENTS_TESTING=1 AGENTS_NO_HERDR=1
NOW=1792170000   # Fri 2026-10-16 17:00:00 UTC
export AGENTS_NOW="$NOW"
mkdir -p "$HOME"

# shellcheck source=../../bin/agents disable=SC1091
. "$REPO_DIR/bin/agents"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "PASS: $1"; }
D="$AGENTS_DATA_DIR"
L="$D/limits.tsv"
T=$'\t'

# --- 1. limits.tsv: one line per cli and window -------------------------------------
mkdir -p "$D"
printf '%s\n' "100${T}codex${T}67${T}43200${T}200" "100${T}claude${T}10${T}300${T}150${T}-" "x${T}bad" > "$L"
_agents_limits_put "" "200${T}claude${T}20.5${T}300${T}500${T}-" || fail "put failed"
[[ "$(cat "$L")" == "100${T}codex${T}67${T}43200${T}200"$'\n'"200${T}claude${T}20.5${T}300${T}500${T}-" ]] \
    || fail "merge: $(cat "$L")"
_agents_limits_put "" "201${T}claude${T}40${T}10080${T}900${T}-" || fail "put failed"
[[ "$(wc -l < "$L" | tr -d ' ')" == 3 ]] || fail "a new window did not add a line: $(cat "$L")"
# A source that reports every window at once (FAMILY) drops its others.
_agents_limits_put codex "300${T}codex${T}12.5${T}300${T}700${T}-"$'\n'"300${T}codex${T}40${T}10080${T}800${T}-" || fail "put failed"
[[ "$(grep -c "${T}codex${T}" "$L")" == 2 && "$(grep -c "${T}43200${T}" "$L")" == 0 && "$(grep -c "${T}claude${T}" "$L")" == 2 ]] \
    || fail "family replace: $(cat "$L")"
# agy:KEY rows are one family.
_agents_limits_put agy "300${T}agy:gemini${T}1${T}300${T}0${T}Gemini"$'\n'"300${T}agy:3p${T}0${T}300${T}0${T}Claude and GPT" || fail "put failed"
_agents_limits_put agy "310${T}agy:gemini${T}2${T}300${T}0${T}Gemini"
[[ "$(grep -c "${T}agy:" "$L")" == 1 && "$(grep "${T}agy:" "$L")" == "310${T}agy:gemini${T}2${T}300${T}0${T}Gemini" ]] || fail "agy family: $(cat "$L")"
# Malformed rows change nothing; no lock is left behind.
before="$(cat "$L")"
_agents_limits_put "" "x${T}claude${T}1${T}300${T}0" && fail "a put of only malformed rows succeeded"
_agents_limits_put "" "1${T}Claude Code${T}1${T}300${T}0" || true
_agents_limits_put "" "1${T}claude${T}1${T}0${T}0" || true
[[ "$(cat "$L")" == "$before" ]] || fail "a malformed row was written: $(cat "$L")"
[[ ! -e "$D/limits.lock" ]] || fail "limits.lock left behind"
# A held lock (a live holder) makes it give up rather than wait forever.
mkdir "$D/limits.lock"; echo "$$ $(_agents_start $$)" > "$D/limits.lock/holder"
_agents_limits_put "" "400${T}claude${T}99${T}300${T}0${T}-" && fail "put went ahead under someone else's lock"
rm -rf "$D/limits.lock"
( AGENTS_HISTORY=0 _agents_limits_put "" "400${T}claude${T}99${T}300${T}0${T}-" )
[[ "$(cat "$L")" == "$before" ]] || fail "AGENTS_HISTORY=0 wrote limits.tsv"
_agents_limits_prune 250
[[ "$(cut -f1 "$L" | sort -u | tr '\n' ' ')" == "300 310 " ]] || fail "prune: $(cat "$L")"
pass "limits.tsv: one line per cli and window, a reporting family replaces its own, malformed rows and AGENTS_HISTORY=0 change nothing, under a lock"

# --- 2. agents statusline ---------------------------------------------------------------
rm -f "$L"
sl_json() {   # FIVE_PCT FIVE_RESET SEVEN_PCT SEVEN_RESET (empty: absent)
    local rl="" w=""
    [[ -z "$1" ]] || w='"five_hour":{"used_percentage":'"$1"',"resets_at":'"$2"'}'
    [[ -z "$3" ]] || w="${w:+$w,}"'"seven_day":{"used_percentage":'"$3"',"resets_at":'"$4"'}'
    [[ -z "$w" ]] || rl=',"rate_limits":{'"$w"',"spend_limit":{"used_percentage":5,"resets_at":1}}'
    printf '{"session_id":"abc","session_name":"x \\"five_hour\\":{\\"used_percentage\\":99} }","model":{"id":"claude-opus-5-5","display_name":"Opus 5.5"},"workspace":{"current_dir":"/w"},"context_window":{"total_input_tokens":1,"current_usage":{"input_tokens":5},"used_percentage":42.4,"remaining_percentage":57.6}%s,"vim":{"mode":"NORMAL"}}\n' "$rl"
}
out="$(sl_json 23.5 1792180000 41.2 1792500000 | agents_statusline)"
[[ "$out" == "Opus 5.5 · ctx 42% · 5h 24% · wk 41%" ]] || fail "statusline output: $out"
[[ "$(cat "$L")" == "$NOW${T}claude${T}23.5${T}300${T}1792180000${T}-"$'\n'"$NOW${T}claude${T}41.2${T}10080${T}1792500000${T}-" ]] \
    || fail "statusline rows: $(cat "$L")"
# The same reading a minute later: nothing written. Five minutes on, or a change: written.
( AGENTS_NOW=$((NOW + 60)); sl_json 23.5 1792180000 41.2 1792500000 | agents_statusline >/dev/null )
[[ "$(cut -f1 "$L" | sort -u)" == "$NOW" ]] || fail "an unchanged reading was written again: $(cat "$L")"
( AGENTS_NOW=$((NOW + 120)); sl_json 30 1792180000 41.2 1792500000 | agents_statusline >/dev/null )
[[ "$(grep "${T}300${T}" "$L")" == "$((NOW + 120))${T}claude${T}30${T}300${T}1792180000${T}-" && "$(grep -c "^$NOW${T}" "$L")" == 1 ]] \
    || fail "a changed window: $(cat "$L")"
( AGENTS_NOW=$((NOW + 420)); sl_json 30 1792180000 41.2 1792500000 | agents_statusline >/dev/null )
[[ "$(cut -f1 "$L" | sort -u)" == "$((NOW + 420))" ]] || fail "a 5-minute-old reading was not refreshed: $(cat "$L")"
# One window absent: the other is kept as it was; rate_limits absent: nothing written.
before="$(cat "$L")"
( AGENTS_NOW=$((NOW + 900)); sl_json "" "" 50 1792500000 | agents_statusline >/dev/null )
[[ "$(grep "${T}300${T}" "$L")" == "$(printf '%s\n' "$before" | grep "${T}300${T}")" && "$(grep "${T}10080${T}" "$L" | cut -f3)" == 50 ]] \
    || fail "an absent window: $(cat "$L")"
before="$(cat "$L")"
out="$( (AGENTS_NOW=$((NOW + 2000)); sl_json "" "" "" "" | agents_statusline) )"
[[ "$out" == "Opus 5.5 · ctx 42%" && "$(cat "$L")" == "$before" ]] || fail "no rate_limits: '$out' $(cat "$L")"
[[ "$(printf '{"model":{"display_name":"Son\\"net\\u00e9\\n"}}' | agents_statusline)" == 'Son"net' ]] || fail "a bare JSON"
[[ "$(printf 'not json' | agents_statusline; echo "rc=$?")" == $'\nrc=0' ]] || fail "garbage stdin"
[[ "$(agents_statusline </dev/null; echo "rc=$?")" == $'\nrc=0' ]] || fail "empty stdin"
# Your own command: the same JSON on its stdin, its output and status as they are.
out="$(sl_json 60 1792180000 41.2 1792500000 | AGENTS_STATUSLINE_CMD='tr -d "\n" | wc -c | tr -d " "; printf "\033[1mmine\033[0m\n"; exit 3' agents_statusline; echo "rc=$?")"
[[ "$out" == "$(sl_json 60 1792180000 41.2 1792500000 | tr -d '\n' | wc -c | tr -d ' ')"$'\n\033[1mmine\033[0m\nrc=3' ]] || fail "your command: $out"
[[ "$(grep "${T}300${T}" "$L" | cut -f3)" == 60 ]] || fail "your command: the limits were not recorded first"
# A command that calls agents statusline again doesn't loop.
out="$(sl_json 60 1792180000 41.2 1792500000 | AGENTS_STATUSLINE_CMD="bash -c '. \"$REPO_DIR/bin/agents\"; agents_statusline'" agents_statusline)"
[[ "$out" == "Opus 5.5 · ctx 42% · 5h 60% · wk 41%" ]] || fail "a command calling agents statusline: $out"
# No jq anywhere: a jq that fails changes nothing.
mkdir -p "$tmp/nojq"; printf '#!/bin/sh\nexit 127\n' > "$tmp/nojq/jq"; chmod +x "$tmp/nojq/jq"
out="$(sl_json 61 1792180000 41.2 1792500000 | PATH="$tmp/nojq:$PATH" agents_statusline)"
[[ "$out" == "Opus 5.5 · ctx 42% · 5h 61% · wk 41%" && "$(grep "${T}300${T}" "$L" | cut -f3)" == 61 ]] || fail "without jq: $out"
# History off: printed, never written.
before="$(cat "$L")"
out="$(sl_json 70 1792180000 41.2 1792500000 | AGENTS_HISTORY=0 agents_statusline)"
[[ "$out" == "Opus 5.5 · ctx 42% · 5h 70% · wk 41%" && "$(cat "$L")" == "$before" ]] || fail "AGENTS_HISTORY=0: $out"
# Through the command line, as Claude Code runs it.
out="$(sl_json 61 1792180000 41.2 1792500000 | "$REPO_DIR/bin/agents" statusline)"
[[ "$out" == "Opus 5.5 · ctx 42% · 5h 61% · wk 41%" ]] || fail "agents statusline: $out"
pass "agents statusline: Claude's 5h and weekly windows recorded when they change (or every 5 min), a forged key in a string ignored, your command's output and status untouched, no loop, no jq needed"

# --- 3. agents limits, the tsv records ---------------------------------------------------
printf '%s\n' \
    "$((NOW - 120))${T}claude${T}83.4${T}300${T}$((NOW + 3900))${T}-" \
    "$((NOW - 120))${T}claude${T}41${T}10080${T}$((NOW + 3 * 86400 + 600))${T}-" \
    "$((NOW - 7200))${T}codex${T}96${T}43200${T}$((NOW + 12 * 86400))" \
    "$((NOW - 7200))${T}codex${T}10${T}300${T}$((NOW - 60))${T}-" \
    "$((NOW - 600))${T}agy:gemini${T}2${T}300${T}0${T}Gemini" \
    "$((NOW - 90000))${T}agy:3p${T}0${T}10080${T}0${T}Claude and GPT" > "$L"
printf '%s\n' "$((NOW - 100))${T}claude${T}app${T}s${T}main${T}Bash${T}classifier${T}Production Deploy${T}git push" \
    "$((NOW - 90))${T}claude${T}app${T}s${T}main${T}Bash${T}classifier${T}Production Deploy${T}git push" \
    "$((NOW - 80))${T}claude${T}app${T}s${T}main${T}Bash${T}user${T}-${T}rm" \
    "$((NOW - 86400))${T}claude${T}app${T}s${T}main${T}Bash${T}classifier${T}Old${T}rm" > "$D/denials.tsv"
printf '%s\n' "$((NOW - 100))${T}claude${T}app${T}s${T}main${T}auto${T}1${T}1" > "$D/compacts.tsv"
want="limit${T}Claude${T}5h${T}83${T}18:05${T}claude${T}120
limit${T}Claude${T}week${T}41${T}Mon 17:10${T}claude${T}120
limit${T}Codex${T}month${T}96${T}Oct 28${T}codex${T}7200
limit${T}Antigravity · Gemini${T}5h${T}2${T}-${T}agy:gemini${T}600
denials${T}3${T}Production Deploy
compacts${T}1"
got="$(_agents_limits_lines)"
[[ "$got" == "$want" ]] || fail "tsv records:"$'\n'"$got"$'\n'"want:"$'\n'"$want"
[[ "$(agents_tsv 2>/dev/null | grep -c '^limit	')" == 4 ]] || fail "agents tsv has no limit records"
[[ -z "$(AGENTS_HISTORY=0 _agents_limits_lines)" ]] || fail "records with history off"
pass "agents tsv: a limit record per window not reset yet (stale ones and day-old unknown resets hidden), today's denials with the top reason, compactions"

view="$(agents_limits)"
[[ "$view" == *$'\n'"$(printf '%-28s' Claude)  5h       83%  18:05 (1h05m)      2m ago"$'\n'* ]] || fail "limits view, Claude 5h:"$'\n'"$view"
[[ "$view" == *$'\n'"$(printf '%-28s' Codex)  5h       10%  reset 1m ago       2h00m ago"$'\n'* ]] || fail "limits view, a reset window:"$'\n'"$view"
[[ "$view" == *$'\n'"Antigravity · Gemini          5h        2%  -                  10m ago"$'\n'* ]] || fail "limits view, no reset time:"$'\n'"$view"
[[ "$view" != *"Claude Code: no reading yet"* ]] || fail "the Claude hint with a Claude reading"
json="$(agents_limits --json)"
if command -v jq >/dev/null 2>&1; then
    jq -e '.limits | length == 6 and .[0] == {"cli":"claude","name":"Claude","label":null,"window_minutes":300,"used_percent":83.4,"resets_at":1792173900,"as_of":1792169880,"stale":false}
        and ([.[] | select(.stale)] | length) == 2 and .[4].resets_at == null' <<<"$json" >/dev/null || fail "limits json: $json"
fi
[[ "$(AGENTS_DATA_DIR="$tmp/none" agents_limits)" == *"no readings yet"*"Claude Code: no reading yet"* ]] || fail "limits view without data"
[[ "$(agents_limits --bogus 2>&1; echo "rc=$?")" == *"usage: agents limits [--json]"*"rc=2" ]] || fail "bad option"
pass "agents limits: every reading with its reset (local time and how long) and its age, a reset one dimmed; --json"

# --- 4. The Antigravity probe ------------------------------------------------------------
mkdir -p "$tmp/bin"
cat > "$tmp/bin/agy" <<EOF
#!/bin/bash
echo run >> "$tmp/agy.runs"
[[ "\$*" == "-p /quota --output-format json" ]] || exit 9
cat "$REPO_DIR/scripts/lib/testdata/agy-quota.json"
EOF
chmod +x "$tmp/bin/agy"
rm -f "$L"
( PATH="$tmp/bin:$PATH"; _agents_limits_probe "$NOW" )
[[ ! -f "$tmp/agy.runs" ]] || fail "a probe ran under the test harness without AGENTS_TEST_PROBES"
if command -v jq >/dev/null 2>&1; then
    ( export PATH="$tmp/bin:$PATH" AGENTS_TEST_PROBES=1; _agents_limits_probe "$NOW" )
    want="$NOW${T}agy:gemini${T}1${T}10080${T}1792771833${T}Gemini
$NOW${T}agy:gemini${T}81${T}300${T}1792185033${T}Gemini
$NOW${T}agy:3p${T}0${T}10080${T}0${T}Claude and GPT
$NOW${T}agy:3p${T}50${T}300${T}1792185836${T}Claude and GPT
$NOW${T}agy:gemini-argon-wtu${T}2${T}10080${T}1792738849${T}Gemini 4 Argon"
    [[ "$(cat "$L")" == "$want" ]] || fail "agy rows:"$'\n'"$(cat "$L")"$'\n'"want:"$'\n'"$want"
    # Within 10 minutes it doesn't run again; after, it does.
    ( export PATH="$tmp/bin:$PATH" AGENTS_TEST_PROBES=1; _agents_limits_probe "$((NOW + 300))"; _agents_limits_probe "$((NOW + 700))" )
    [[ "$(wc -l < "$tmp/agy.runs" | tr -d ' ')" == 2 ]] || fail "the probe's throttle: $(wc -l < "$tmp/agy.runs") runs"
    # A failing or hanging agy writes nothing and never holds up the sample.
    printf '#!/bin/bash\nsleep 30\n' > "$tmp/bin/agy"
    before="$(cat "$L")"; t0=$(date +%s)
    ( export PATH="$tmp/bin:$PATH" AGENTS_TEST_PROBES=1 _AGENTS_LIMITS_TIMEOUT=1; _agents_limits_probe "$((NOW + 2000))" )
    [[ $(( $(date +%s) - t0 )) -lt 10 && "$(cat "$L")" == "$before" ]] || fail "a hanging agy"
    pass "agy -p /quota: a row per bucket (agy:GROUP, used %, 5h or weekly, reset epoch from Z or an offset, none at 0% used), every 10 minutes, bounded"
else
    echo "SKIP: no jq: the Antigravity probe needs it"
fi

# --- 5. Grok's tokens ----------------------------------------------------------------------
if command -v jq >/dev/null 2>&1; then
    G="$HOME/.grok/sessions/%2Fwork%2Fgrokapp/01aa-sess"; mkdir -p "$G"
    turn() {   # N ENDED MODEL IN CACHED OUT
        printf '{"turnNumber":%s,"endedAt":"%s","inputTokens":%s,"cachedReadTokens":%s,"cacheCreationTokens":0,"outputTokens":%s,"modelUsage":{"%s":{"inputTokens":%s,"outputTokens":%s,"cachedReadTokens":%s,"cacheCreationTokens":0}}}' \
            "$1" "$2" "$4" "$5" "$6" "$3" "$4" "$6" "$5"
    }
    printf '{"sessionId":"01aa-sess","turns":[%s,%s]}\n' "$(turn 1 2026-10-16T12:00:00.5+00:00 grok-4.7-build 1000 400 50)" \
        "$(turn 2 2026-10-16T14:30:00+02:00 grok-4.7-build 2000 1500 70)" > "$G/usage.json"
    mkdir -p "$D"; printf '2026-10-16\t100\t10\t20\t30\t40\n' > "$D/tokens.today"; : > "$D/tokens.tsv"
    ( umask 077; _agents_grok_scan "$NOW" 2026-10-16 $((NOW - 13 * 3600)) ) || fail "grok scan failed"
    want="1792152000${T}grok${T}grokapp${T}01aa-sess${T}main${T}grok-4.7-build${T}600${T}0${T}400${T}50${T}0${T}0${T}-
1792153800${T}grok${T}grokapp${T}01aa-sess${T}main${T}grok-4.7-build${T}500${T}0${T}1500${T}70${T}0${T}0${T}-"
    [[ "$(cat "$D/tokens.tsv")" == "$want" ]] || fail "grok rows:"$'\n'"$(cat "$D/tokens.tsv")"$'\n'"want:"$'\n'"$want"
    [[ "$(cat "$D/tokens.today")" == "2026-10-16${T}3220${T}1110${T}20${T}1930${T}160" ]] || fail "tokens.today: $(cat "$D/tokens.today")"
    # Nothing new: nothing added. A third turn: one row.
    ( umask 077; _agents_grok_scan "$((NOW + 60))" 2026-10-16 $((NOW - 13 * 3600)) )
    [[ "$(wc -l < "$D/tokens.tsv" | tr -d ' ')" == 2 ]] || fail "a second grok scan added rows"
    printf '{"sessionId":"01aa-sess","turns":[%s,%s,%s]}\n' "$(turn 1 2026-10-16T12:00:00Z grok-4.7-build 1000 400 50)" \
        "$(turn 2 2026-10-16T12:30:00Z grok-4.7-build 2000 1500 70)" "$(turn 3 2026-10-16T12:50:00Z grok-5 10 0 1)" > "$G/usage.json"
    # Changed after the last scan began (its stamp: the fixed clock, not the real one).
    touch -t "$(date -u -r $((NOW + 600)) +%Y%m%d%H%M.%S 2>/dev/null || date -u -d "@$((NOW + 600))" +%Y%m%d%H%M.%S)" "$G/usage.json"
    ( umask 077; _agents_grok_scan "$((NOW + 900))" 2026-10-16 $((NOW - 13 * 3600)) )
    [[ "$(wc -l < "$D/tokens.tsv" | tr -d ' ')" == 3 && "$(tail -1 "$D/tokens.tsv" | cut -f6,7)" == "grok-5${T}10" ]] || fail "a new grok turn: $(cat "$D/tokens.tsv")"
    # A broken file doesn't stop the others.
    mkdir -p "$HOME/.grok/sessions/%2Fwork%2Fb/s2"; echo '{"turns":[{"turnNumber":1,' > "$HOME/.grok/sessions/%2Fwork%2Fb/s2/usage.json"
    [[ "$(_agents_grok_turns "$NOW" "$HOME/.grok/sessions/%2Fwork%2Fb/s2/usage.json" "$G/usage.json" | wc -l | tr -d ' ')" == 3 ]] || fail "a broken usage.json stopped the rest"
    pass "Grok: each turn and model of usage.json into tokens.tsv once (in less cached reads), today's share into tokens.today, a broken file skipped"
else
    echo "SKIP: no jq: Grok's tokens need it"
fi

# --- 6. Session names ----------------------------------------------------------------------
kind() { AGENTS_NAMES="$AGENTS_NAMES" _agents_awk_eval lib_proc 'BEGIN { print agent_kind(ENVIRON["A"]) }' </dev/null; }
[[ "$(A='agy' kind)" == agy && "$(A='/Users/NAME/.local/bin/agy --bg-updater --app_data_dir=x' kind)" == "" ]] || fail "agy, and its updater"
[[ "$(A='/Users/NAME/.grok/bin/grok' kind)" == grok && "$(A='/Applications/Grok Bot.app/Contents/MacOS/Grok Bot' kind)" == "" ]] || fail "grok, not the Grok Bot app"
[[ "$(A='cursor-agent --use-system-ca /Users/NAME/.local/share/cursor-agent/versions/1/index.js' kind)" == cursor-agent ]] || fail "cursor-agent"
[[ "$(A='agent --use-system-ca /Users/NAME/.local/share/cursor-agent/versions/1/index.js' kind)" == cursor-agent ]] || fail "Cursor as agent"
[[ "$(A='/Users/NAME/.grok/bin/agent' kind)" == "" && "$(A='agent run' kind)" == "" ]] || fail "a generic agent counted"
[[ "$(A='agents-probe-agy -p /quota' kind)" == "" ]] || fail "the probe counted as a session"
pass "sessions: agy (not its --bg-updater), grok (not the Grok Bot app), cursor-agent (and agent only from Cursor's install); the probe is none"

# --- 7. The menu's Usage section ------------------------------------------------------------
cat > "$tmp/agents-stub" <<EOF
#!/bin/bash
case "\$1" in tsv) cat "$tmp/tsv" ;; esac
EOF
chmod +x "$tmp/agents-stub"
menu() { AGENTS_BIN="$tmp/agents-stub" bash "$REPO_DIR/configs/swiftbar/agents.10s.sh"; }
usage_rows="limit${T}Claude${T}5h${T}23${T}14:05${T}claude${T}60
limit${T}Claude${T}week${T}81${T}Mon 09:00${T}claude${T}60
limit${T}Antigravity · Gemini${T}5h${T}2${T}-${T}agy:gemini${T}600"
printf '%s\ntokens\t2637000\t91\ndenials\t12\tProduction Deploy\ncompacts\t3\n' "$usage_rows" > "$tmp/tsv"
m="$(menu)"
sec="$(printf '%s\n' "$m" | awk '/^Usage \|/ { on = 1 } on && /^---$/ { exit } on')"
A="bash=\"$tmp/agents-stub\" param1=open-term terminal=false param2=--hold"
orange="sfconfig=eyJyZW5kZXJpbmdNb2RlIjoiUGFsZXR0ZSIsImNvbG9ycyI6WyIjRkY5RjBBIl19"
want="Usage | size=12
Claude · 5h 23% · resets 14:05 | sfimage=gauge.with.needle $A param3=limits symbolize=false
Claude · week 81% · resets Mon 09:00 | sfimage=gauge.with.needle $orange $A param3=limits symbolize=false
Antigravity · Gemini · 5h 2% | sfimage=gauge.with.needle $A param3=limits symbolize=false
2.6M tokens today · 91% cached | $A param3=report param4=--view param5=tokens param6=--since param7=today sfimage=text.bubble symbolize=false
Denials today: 12 (top: Production Deploy) | $A param3=report param4=--view param5=denials param6=--since param7=today sfimage=hand.raised symbolize=false
Compactions today: 3 | $A param3=report param4=--view param5=tokens param6=--since param7=today sfimage=arrow.down.right.and.arrow.up.left symbolize=false"
[[ "$sec" == "$want" ]] || fail "Usage section:"$'\n'"$sec"$'\n'"want:"$'\n'"$want"
[[ "$(printf '%s\n' "$m" | head -1)" == ":terminal:" ]] || fail "81% tinted the icon: $(printf '%s\n' "$m" | head -1)"
[[ $(printf '%s\n' "$m" | grep -n '^Agents (' | cut -d: -f1) -lt $(printf '%s\n' "$m" | grep -n '^Usage |' | cut -d: -f1) ]] || fail "Usage before Agents"
# 95%: a red dot and an orange icon; the limit title token.
printf 'limit\tCodex\tweek\t96\tFri 10:00\tcodex\t60\nconf\tAGENTS_BAR_TITLE\tcount limit\n' > "$tmp/tsv"
m="$(menu)"
[[ "$(printf '%s\n' "$m" | head -1)" == ":terminal: :gauge.with.needle: 96% | sfcolor=#FF9F0A" ]] || fail "95% title: $(printf '%s\n' "$m" | head -1)"
[[ "$m" == *$'\n'"Codex · week 96% · resets Fri 10:00 | sfimage=gauge.with.needle sfconfig=eyJyZW5kZXJpbmdNb2RlIjoiUGFsZXR0ZSIsImNvbG9ycyI6WyIjRkY0NTNBIl19 "* ]] || fail "95%: no red dot"
# Nothing to say: no section; hostile text stays text.
printf 'denials\t0\t-\n' > "$tmp/tsv"
[[ "$(menu)" != *"Usage |"* ]] || fail "an empty Usage section"
printf 'limit\t---Evil | bash=/bin/rm\t5h\t1\t-\tclaude\t1\ncompacts\t2\n' > "$tmp/tsv"
m="$(menu)"
[[ "$m" == *$'\n'"Evil ¦ bash=/bin/rm · 5h 1% | sfimage="* && "$m" == *$'\n'"Compactions today: 2 | "* ]] || fail "hostile limit name: $(printf '%s\n' "$m" | grep -i evil)"
printf 'conf\tAGENTS_BAR_SECTIONS\tagents\nlimit\tClaude\t5h\t1\t-\tclaude\t1\n' > "$tmp/tsv"
[[ "$(menu)" != *"Usage |"* ]] || fail "Usage shown though AGENTS_BAR_SECTIONS leaves it out"
pass "menu: Usage lists each window (orange from 80%, red and an orange icon from 95%), then today's tokens, denials (top reason) and compactions, each opening its view; the limit title token"
grep -q '^        limits)' "$REPO_DIR/lib/agents/cli.sh" || fail "the menu opens agents limits, which the CLI lacks"

echo
echo "All agents limits tests passed."
