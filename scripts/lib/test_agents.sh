#!/bin/bash
# Unit tests for bin/agents (the monitoring pack's `agents` command).
# Run: bash scripts/lib/test_agents.sh  -> exit 0 on pass.
#
# Only the pure parsing and classification functions run, against fixture
# `ps` / listener text: nothing is signalled and no real process is read.

# Tests change PATH inside ( … ) on purpose, to stub tools for one call.
# shellcheck disable=SC2030,SC2031
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/tuidev-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home" NO_COLOR=1
mkdir -p "$HOME"

# shellcheck source=../../bin/agents disable=SC1091
. "$REPO_DIR/bin/agents"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "PASS: $1"; }

# 1. ps time / etime formats.
[[ "$(agents_secs 00:07)" == 7 ]]             || fail "MM:SS"
[[ "$(agents_secs 736:09.72)" == 44169 ]]     || fail "macOS cputime MMM:SS.cc"
[[ "$(agents_secs 18:15:27)" == 65727 ]]      || fail "HH:MM:SS"
[[ "$(agents_secs 05-13:56:45)" == 482205 ]]  || fail "DD-HH:MM:SS"
[[ "$(agents_secs 1-00:00:00)" == 86400 ]]    || fail "D-HH:MM:SS"
pass "ps time/etime parse, including DD-HH:MM:SS and fractional seconds"

# 2. Durations for `awake on`.
[[ "$(agents_parse_duration 30m)" == 1800 ]]   || fail "30m"
[[ "$(agents_parse_duration 2h)" == 7200 ]]    || fail "2h"
[[ "$(agents_parse_duration 1h30m)" == 5400 ]] || fail "1h30m"
[[ "$(agents_parse_duration 45s)" == 45 ]]     || fail "45s"
! agents_parse_duration 90 >/dev/null          || fail "a bare number is ambiguous and must be rejected"
! agents_parse_duration 0m >/dev/null          || fail "zero duration accepted"
! agents_parse_duration 2x >/dev/null          || fail "unknown unit accepted"
pass "durations parse (30m, 2h, 1h30m) and bad ones are rejected"

# 2b. The config file: read as KEY=value, never sourced; allowlisted keys,
#     validated values, quotes and trailing comments stripped, env wins.
conf="$tmp/agents.conf"
cat > "$conf" <<EOF
# a comment, then a blank line

AGENTS_HOG_PCT=70
AGENTS_BAR_TITLE="count cpu"
  AGENTS_BAR_ICON=brain   # trailing comment
AGENTS_BAR_TOP='2'
AGENTS_HOG_NOW=95
AGENTS_GRACE=abc
AGENTS_BAR_TITLES=count
AGENTS_NAMES=\$(touch "$tmp/pwned")
AGENTS_BAR_SECTIONS=agents bogus
PATH=/nowhere
not a setting
EOF
out="$(
    unset AGENTS_HOG_PCT AGENTS_BAR_TITLE AGENTS_BAR_ICON AGENTS_BAR_TOP AGENTS_GRACE AGENTS_NAMES AGENTS_BAR_SECTIONS
    AGENTS_HOG_NOW=80
    agents_conf_load "$conf" 2>"$tmp/conf.err"
    printf '%s|' "$AGENTS_HOG_PCT" "$AGENTS_BAR_TITLE" "$AGENTS_BAR_ICON" "$AGENTS_BAR_TOP" "$AGENTS_HOG_NOW" \
        "${AGENTS_GRACE-unset}" "${AGENTS_NAMES-unset}" "${AGENTS_BAR_SECTIONS-unset}" "$PATH"
)"
[[ "$out" == "70|count cpu|brain|2|80|unset|unset|unset|$PATH|" ]] || fail "config values: $out"
[[ ! -e "$tmp/pwned" ]] || fail "config file content was executed"
[[ "$(grep -c . "$tmp/conf.err")" == 6 ]] || fail "expected 6 config warnings: $(cat "$tmp/conf.err")"
grep -q "unknown key AGENTS_BAR_TITLES" "$tmp/conf.err" || fail "unknown key not reported"
grep -q "bad value for AGENTS_GRACE" "$tmp/conf.err" || fail "bad value not reported"
[[ "$(AGENTS_CONF="$conf" bash "$REPO_DIR/bin/agents" config 2>/dev/null | grep '^AGENTS_BAR_ICON=')" == AGENTS_BAR_ICON=brain ]] \
    || fail "agents config does not read AGENTS_CONF"
[[ "$(AGENTS_CONF="$tmp/none" bash "$REPO_DIR/bin/agents" config | grep '^AGENTS_BAR_TITLE=')" == "AGENTS_BAR_TITLE=count awake" ]] \
    || fail "defaults without a config file"
pass "config: allowlisted keys, validated values, nothing executed, environment wins"

# The shipped example is all comments, so installing it changes nothing.
! grep -qvE '^[[:space:]]*(#|$)' "$REPO_DIR/configs/agents/agents.conf" || fail "shipped agents.conf sets a value"
for key in $_AGENTS_CONF_KEYS; do
    grep -q "^# $key=" "$REPO_DIR/configs/agents/agents.conf" || fail "configs/agents/agents.conf does not document $key"
    grep -q "\`$key\`" "$REPO_DIR/docs/agent-workflows.md" || fail "docs/agent-workflows.md does not document $key"
done
AGENTS_CONF="$REPO_DIR/configs/agents/agents.conf" bash "$REPO_DIR/bin/agents" config 2>"$tmp/ship.err" >/dev/null
[[ ! -s "$tmp/ship.err" ]] || fail "the shipped config warns: $(cat "$tmp/ship.err")"
pass "shipped agents.conf documents every key, sets none, and parses cleanly"

# The monitoring pack names the plugin after AGENTS_BAR_REFRESH; a bad value
# falls back to the default.
plugin_name() {   # CONF_LINE
    mkdir -p "$tmp/xdg"; printf '%s\n' "$1" > "$tmp/xdg/agents.conf"
    ( unset AGENTS_BAR_REFRESH; export XDG_CONFIG_HOME="$tmp/xdg"
      # shellcheck source=../install/packs/monitoring.sh disable=SC1091
      . "$REPO_DIR/scripts/install/packs/monitoring.sh"; _monitoring_plugin_name )
}
[[ "$(plugin_name AGENTS_BAR_REFRESH=30s)" == agents.30s.sh ]] || fail "plugin name for 30s: $(plugin_name AGENTS_BAR_REFRESH=30s)"
[[ "$(plugin_name AGENTS_BAR_REFRESH=30)" == agents.10s.sh ]]  || fail "bad refresh not ignored"
[[ "$(plugin_name '# nothing')" == agents.10s.sh ]]            || fail "default plugin name"
pass "the pack names the plugin after AGENTS_BAR_REFRESH (agents.30s.sh)"

# 3. Classification. Fixture: uid 501 is "me"; the test's own process is 7000
#    (a child of 6999, a shell under the third claude session).
# Columns: pid ppid uid user %cpu rss time etime lstart(5) args
fixture="$(cat <<'EOF'
    1     0     0 root               0.0  20000  10:00.00 13-16:00:00 Wed Sep 30 16:57:15 2026     /sbin/launchd
  500     1   501 me                 0.0   9000   0:01.00 13-16:00:00 Wed Sep 30 16:57:15 2026     /Applications/Ghostty.app/Contents/MacOS/ghostty
  510   500   501 me                 0.0   3000   0:00.10 01:42:53 Wed Oct 14 07:31:08 2026     -zsh
90419   510   501 me                 0.3 688336   4:30.13 01:42:53 Wed Oct 14 07:31:08 2026     claude --continue
90466 90419   501 me                 0.0  91728   0:00.51 01:42:50 Wed Oct 14 07:31:11 2026     npm exec chrome-devtools-mcp@latest
90497 90466   501 me                 0.0 113360   0:00.44 01:42:49 Wed Oct 14 07:31:12 2026     chrome-devtools-mcp
26603 90419   501 me                 0.0   1920   0:00.00 01:32 Wed Oct 14 09:12:29 2026     caffeinate -i -t 300
22443 90419   501 me               102.1 185072   2:46.32 02:49 Wed Oct 14 09:11:12 2026     /tmp/go-build1/b001/web.test -test.count=1
61904     1   501 me                 0.0  22992   0:02.94 18:20:43 Tue Oct 13 14:53:18 2026     /Users/NAME/.codex/packages/app-server-daemon/releases/0.1/bin/codex app-server daemon pid-update-loop
  197 61904   501 me                 0.0  48896   0:07.38 18:15:27 Tue Oct 13 14:58:34 2026     /Users/NAME/.codex/packages/app-server-daemon/releases/0.1/bin/codex app-server --listen unix:// --managed-daemon
19212  3975   501 me                 0.0   8112   0:25.71 05-13:56:45 Thu Oct  8 19:17:16 2026     /Users/NAME/.local/bin/claude --chrome-native-host
 3975     1   501 me                 2.0 400000  90:00.00 05-13:56:45 Thu Oct  8 19:17:16 2026     /Applications/Google Chrome.app/Contents/MacOS/Google Chrome
60829     1   501 me                 0.0  97888   0:00.59 50:05 Wed Oct 14 08:23:56 2026     npm exec chrome-devtools-mcp@latest
60872 60829   501 me                 0.0 117280   0:00.43 50:04 Wed Oct 14 08:23:57 2026     chrome-devtools-mcp
60831     1   501 me                 0.0  56208   0:00.11 50:05 Wed Oct 14 08:23:56 2026     node /Users/NAME/.local/lib/example-agent-mcp.cjs
27681     1   501 me                 0.0   1920   0:00.00 00:42 Wed Oct 14 09:13:19 2026     caffeinate -i -t 300
 8800     1   501 me                 0.0   1920   0:00.00 00:42 Wed Oct 14 09:13:19 2026     caffeinate -di
 4100     1   501 me                 0.5  80000   0:30.00 03:00:00 Wed Oct 14 06:00:00 2026     node /Users/NAME/work/app/node_modules/.bin/vite
 4200     1   501 me                 0.0  20000   0:01.00 03:00:00 Wed Oct 14 06:00:00 2026     /Applications/Ollama.app/Contents/Resources/ollama serve
 4300     1   501 me                 0.0  10000   0:01.00 03:00:00 Wed Oct 14 06:00:00 2026     python3 -m http.server 8000
 4400     1   501 me                 0.0  28000   0:01.00 22:22:00 Tue Oct 13 11:00:00 2026     /opt/homebrew/Cellar/podman/6.1.3/libexec/podman/gvproxy -mtu 1500 -ssh-port 56916
84091 40160   501 me                 6.8 644704   1:00.25 33:39 Wed Oct 14 08:40:22 2026     claude
 6999 84091   501 me                 0.0   3000   0:00.01 00:05 Wed Oct 14 09:14:00 2026     /bin/zsh -c agents ls
 7000  6999   501 me                99.0   3000   0:00.01 00:01 Wed Oct 14 09:14:04 2026     bash agents ls
40160   500   501 me                 0.0   3000   0:00.10 33:40 Wed Oct 14 08:40:21 2026     -zsh
41198     1   501 me               116.0  39248 23040:00.00 13-16:16:46 Wed Sep 30 16:57:15 2026     /System/Applications/Messages.app/Contents/MacOS/Messages
48170     1   200 _appstore         77.0  33728 8:00.00 07-14:01:11 Tue Oct  6 19:12:50 2026     /System/Library/PrivateFrameworks/AppStoreDaemon.framework/Support/appstoreagent
 9100     1   501 me                95.0  20000   0:30.00 00:40 Wed Oct 14 09:13:30 2026     /usr/bin/yes
 4500     1     0 root               0.0  20000   0:01.00 03:00:00 Wed Oct 14 06:00:00 2026     /opt/homebrew/bin/node /srv/app/server.js
  606     1   501 me                 0.0  90000   9:00.00 13-16:00:00 Wed Sep 30 16:57:15 2026     /System/Library/CoreServices/loginwindow.app/Contents/MacOS/loginwindow console
  700  4100   501 me                 0.0  30000   0:10.00 13-16:00:00 Wed Sep 30 16:57:15 2026     /Applications/Ghostty.app/Contents/MacOS/ghostty --login
  710     1   501 me                 0.0  30000   0:10.00 13-16:00:00 Wed Sep 30 16:57:15 2026     /System/Applications/Messages.app/Contents/MacOS/MessagesHelper
EOF
)"
listen="$(printf '%s\n' '4100 5173' '4200 11434' '4300 8000' '4400 56916' '22443 41234' '22443 41235')"

# Read by the sourced functions.
# shellcheck disable=SC2034
AGENTS_UID=501 AGENTS_SELF=7000
records="$(printf '%s\n' "$fixture" | agents_classify "$listen" "8800")"
field() { printf '%s\n' "$records" | awk -F '\t' -v t="$1" -v p="$2" -v c="$3" '$1 == t && $2 == p { print $c }'; }
has()   { [[ -n "$(field "$1" "$2" 2)" ]]; }

# Agent roots: both sessions and the daemon, nothing else.
[[ "$(printf '%s\n' "$records" | awk -F '\t' '$1 == "agent" { print $2 }' | sort -n | tr '\n' ' ')" == "61904 84091 90419 " ]] \
    || fail "agent roots: $(printf '%s\n' "$records" | awk -F '\t' '$1 == "agent" { print $2 }' | tr '\n' ' ')"
[[ "$(field agent 61904 3)" == daemon ]] || fail "codex app-server pid-update-loop is not tagged daemon"
[[ "$(field agent 90419 3)" == claude ]] || fail "claude root kind"
! has agent 19212 || fail "claude --chrome-native-host counted as an agent"
[[ "$(field agent 90419 8)" == 4 ]]      || fail "claude tree child count: $(field agent 90419 8)"
[[ "$(field agent 90419 7)" == $((688336 + 91728 + 113360 + 1920 + 185072)) ]] || fail "tree RSS: $(field agent 90419 7)"
[[ "$(field agent 90419 5)" == 102.4 ]]  || fail "tree CPU: $(field agent 90419 5)"
[[ "$(field agent 90419 10)" == 41234,41235 ]] || fail "ports owned by the tree: $(field agent 90419 10)"
[[ "$(field agent 90419 9)" == Wed_Oct_14_07:31:08_2026 ]] || fail "start token: $(field agent 90419 9)"
[[ "$(field agent 84091 5)" == 6.8 ]] || fail "the session running agents counts agents' own CPU: $(field agent 84091 5)"
pass "agent roots: claude sessions and the codex daemon, with tree CPU, RSS, kids and ports"

# Stale: orphaned MCP helpers and Claude's caffeinate; never the daemon, our
# own keep-awake holder, a live session's children, or an app.
for p in 60829 60831 27681; do
    [[ "$(field stale "$p" 3)" == orphan ]] || fail "orphan $p not flagged stale"
done
[[ "$(field stale 60829 8)" == 1 ]] || fail "orphan tree child count"
! has stale 60872 || fail "an orphan's child flagged separately (its tree is reaped with it)"
! has stale 61904 || fail "codex daemon flagged stale"
! has stale 197   || fail "codex app-server flagged stale"
! has stale 8800  || fail "our own awake caffeinate flagged stale"
! has stale 90466 || fail "a live session's MCP server flagged stale"
! has stale 26603 || fail "a live session's caffeinate flagged stale"
pass "orphaned MCP servers, npx helpers and caffeinate are stale; the codex daemon is not"

# Dev-server candidates: user-owned, ppid 1, listening, not an app bundle.
has cand 4100 || fail "orphaned vite not a dev-server candidate"
has cand 4300 || fail "orphaned http.server not a dev-server candidate"
! has cand 4200 || fail "an /Applications service treated as a dev server"
! has cand 4400 || fail "a Homebrew-packaged daemon (podman gvproxy) treated as a dev server"
cwds="$(printf '%s\t%s\n' 4100 "$HOME/work/app" 4300 / 90419 "$HOME/work/app")"
herdr="$(printf '%s\t%s\t%s\n' claude working "$HOME/work/app")"
enriched="$(printf '%s\n' "$records" | agents_enrich "$cwds" "$herdr")"
efield() { printf '%s\n' "$enriched" | awk -F '\t' -v t="$1" -v p="$2" -v c="$3" '$1 == t && $2 == p { print $c }'; }
[[ "$(efield stale 4100 3)" == server ]]   || fail "dev server under \$HOME not confirmed stale"
[[ -z "$(efield stale 4300 3)" ]]          || fail "a listener with cwd / flagged as a dev server"
[[ -z "$(printf '%s\n' "$enriched" | awk -F '\t' '$1 == "cand"')" ]] || fail "unconfirmed candidates leak out"
[[ "$(efield agent 90419 12)" == working ]] || fail "Herdr status not matched by kind and cwd"
[[ "$(efield agent 84091 12)" == - ]]       || fail "Herdr status attached to the wrong session"
pass "orphaned dev servers are stale only with a cwd under \$HOME; Herdr status matches by cwd"

# Hogs: lifetime average (Messages, any owner), current CPU outside agent
# trees; never a busy test inside an agent tree, never this process.
has hog 41198 || fail "Messages runaway (lifetime average) not a hog"
[[ "$(field hog 41198 3)" == Messages ]] || fail "hog name from the .app bundle: $(field hog 41198 3)"
[[ "$(field hog 41198 6)" == 117.0 ]] || fail "lifetime average (1382400s cpu over 1181806s): $(field hog 41198 6)"
has hog 9100   || fail "a 95% process outside agent trees not a hog"
! has hog 48170 || fail "appstoreagent at a 1% lifetime average flagged"
! has hog 22443 || fail "a busy test inside an agent tree flagged"
! has hog 7000  || fail "this process flagged as a hog"
[[ "$(printf '%s\n' "$records" | awk -F '\t' '$1 == "hog"' | head -1 | cut -f2)" == 41198 ]] || fail "hogs not sorted by CPU"
few="$(printf '%s\n' "$fixture" | AGENTS_HOG_TOP=1 agents_classify "" "" | awk -F '\t' '$1 == "hog"' | wc -l | tr -d ' ')"
[[ "$few" == 1 ]] || fail "AGENTS_HOG_TOP not honored ($few)"
pass "hogs: lifetime average and current CPU, any owner, top N"

# Top processes (for the menu bar) skip hogs, this process and its parents; the total
# leaves out this process's own subtree.
[[ "$(printf '%s\n' "$records" | awk -F '\t' '$1 == "top" { print $2 }' | tr '\n' ' ')" == "22443 48170 3975 " ]] \
    || fail "top processes: $(printf '%s\n' "$records" | awk -F '\t' '$1 == "top" { print $2 }' | tr '\n' ' ')"
[[ "$(printf '%s\n' "$records" | awk -F '\t' '$1 == "total" { print $5 }')" == 399.7 ]] || fail "total CPU"
[[ "$(_agents_cpu_pct 4 "$records")" == 100 ]] || fail "machine CPU% from the total"
pass "top processes exclude hogs and agents itself; machine CPU% from one snapshot"

# 4. Kill safety refusals.
agents_refusal 1 "$fixture" >/dev/null     || fail "pid 1 not refused"
agents_refusal 0 "$fixture" >/dev/null     || fail "pid 0 not refused"
agents_refusal 7000 "$fixture" >/dev/null  || fail "own pid not refused"
[[ "$(agents_refusal 84091 "$fixture")" == *parents* ]] || fail "own ancestor (the claude running us) not refused"
[[ "$(agents_refusal 4500 "$fixture")" == *"sudo kill 4500"* ]] || fail "another user's process: no sudo hint"
# Critical processes: refused even though they are yours, with no sudo hint.
for p in 606 700 48170; do
    [[ "$(agents_refusal "$p" "$fixture")" == *"system or session process"* ]] || fail "critical pid $p not refused: $(agents_refusal "$p" "$fixture")"
done
! agents_refusal 710 "$fixture" >/dev/null || fail "an app under /System/Applications (Messages) refused"
term_snap="$fixture"$'\n'"  720   500   501 me                 0.0  30000   0:10.00 01:00:00 Wed Oct 14 08:00:00 2026     /System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal session"
[[ "$(agents_refusal 720 "$term_snap")" == *"system or session process"* ]] || fail "Terminal with a non-flag argument not refused by name"
! agents_refusal 9100 "$fixture" >/dev/null || fail "/usr/bin/yes refused"
plan="$(_agents_plan 4100 "$fixture" true 2>"$tmp/plan.err")" || true
[[ "$(printf '%s\n' "$plan" | cut -f1 | tr '\n' ' ')" == "4100 " ]] || fail "critical tree member planned: $plan"
grep -q "skip 700 (ghostty): a system or session process" "$tmp/plan.err" || fail "critical tree member skipped silently"
pass "critical processes (loginwindow, the terminal, /System/Library) are refused; /System/Applications is not"
[[ "$(agents_refusal 99999 "$fixture")" == "no such process" ]] || fail "unknown pid not refused"
agents_refusal abc "$fixture" >/dev/null    || fail "non-numeric pid not refused"
! agents_refusal 60829 "$fixture" >/dev/null || fail "an orphan we own refused"
pass "kill refuses pid <= 1, itself and its ancestors, unknown pids, and other users"

# Trees are signalled deepest first; a changed start time is refused.
[[ "$(printf '%s\n' "$fixture" | agents_tree 90419 | cut -f1 | tr '\n' ' ')" == "90497 "* ]] || fail "tree order not deepest first"
[[ "$(printf '%s\n' "$fixture" | agents_tree 90419 | tail -1 | cut -f1)" == 90419 ]] || fail "tree root not last"
plan="$(_agents_plan 60829@Wed_Oct_14_08:23:56_2026 "$fixture" true 2>/dev/null)"
[[ "$(printf '%s\n' "$plan" | cut -f1 | tr '\n' ' ')" == "60872 60829 " ]] || fail "orphan plan: $plan"
! _agents_plan 60829@Mon_Jan_01_00:00:00_2024 "$fixture" true >/dev/null 2>&1 || fail "pid with a changed start time not refused"
_agents_plan 90419 "$fixture" true >/dev/null 2>&1 || fail "another session (not ours) refused"
! _agents_plan 84091 "$fixture" true >/dev/null 2>&1 || fail "the session this shell runs in not refused"
pass "trees go deepest first; a reused pid (start time changed) is refused"

# 4b. Supervisors (tmux, screen…), shells and agents shelter their ancestors:
#     a tmux server whose claude pane listens is not a stale dev server, and
#     a dev server must listen itself.
sup_fixture="$(cat <<'EOF'
    1     0     0 root  0.0  20000 10:00.00 13-16:00:00 Wed Sep 30 16:57:15 2026     /sbin/launchd
  100     1   501 me    0.0   5000  0:01.00 05:00:00 Wed Oct 14 04:00:00 2026     tmux new -s main
  101   100   501 me    0.0   3000  0:00.10 05:00:00 Wed Oct 14 04:00:00 2026     -zsh
  102   101   501 me    1.0 300000  0:10.00 04:00:00 Wed Oct 14 05:00:00 2026     claude
  200     1   501 me    0.0   5000  0:01.00 05:00:00 Wed Oct 14 04:00:00 2026     SCREEN -S work
  201   200   501 me    0.0   3000  0:00.10 05:00:00 Wed Oct 14 04:00:00 2026     /bin/zsh -l
  202   201   501 me    0.0  80000  0:01.00 05:00:00 Wed Oct 14 04:00:00 2026     node node_modules/.bin/vite
  300     1   501 me    0.0   5000  0:01.00 05:00:00 Wed Oct 14 04:00:00 2026     npm exec some-mcp
  301   300   501 me    0.0   3000  0:00.10 05:00:00 Wed Oct 14 04:00:00 2026     claude -p hello
  400     1   501 me    0.0   9000  0:01.00 05:00:00 Wed Oct 14 04:00:00 2026     node server.js
  401   400   501 me    0.0   9000  0:01.00 05:00:00 Wed Oct 14 04:00:00 2026     bash -c npm run build
  500     1   501 me    0.0   9000  0:01.00 05:00:00 Wed Oct 14 04:00:00 2026     node app.js
  501   500   501 me    0.0   9000  0:01.00 05:00:00 Wed Oct 14 04:00:00 2026     node worker.js
EOF
)"
sup_listen=$'102 5173\n202 3000\n400 8080\n501 9000'
sup_recs="$(printf '%s\n' "$sup_fixture" | AGENTS_SELF=9999 agents_classify "$sup_listen" "")"
sfield() { printf '%s\n' "$sup_recs" | awk -F '\t' -v t="$1" -v p="$2" '$1 == t && $2 == p { print $3 }'; }
[[ -z "$(sfield stale 100)$(sfield cand 100)" ]] || fail "a tmux server hosting a claude pane flagged"
[[ -z "$(sfield stale 200)$(sfield cand 200)" ]] || fail "a screen session hosting a shell flagged"
[[ -z "$(sfield stale 300)" ]] || fail "an orphan-pattern process hosting an agent flagged"
[[ "$(sfield agent 102)" == claude && "$(sfield agent 301)" == claude ]] || fail "hosted sessions not listed as agents"
[[ "$(sfield cand 400)" == server ]] || fail "a dev server listening itself (child: bash -c) not a candidate"
[[ "$(sfield cand 500)" == server ]] || fail "a dev server listening through its child (node worker.js) missed"
[[ "$(printf '%s\n' "$sup_recs" | awk -F '\t' '$1 == "cand" && $2 == 400 { print $10 }')" == 8080 ]] || fail "dev server ports"
# An orphaned `npm run dev` (zsh -c, not an interactive shell) whose vite
# child listens is a stale dev server.
dev_snap="$sup_fixture"$'\n'"  600     1   501 me    0.0   3000  0:00.10 05:00:00 Wed Oct 14 04:00:00 2026     zsh -c npm run dev"
dev_snap+=$'\n'"  601   600   501 me    0.0  90000  0:05.00 05:00:00 Wed Oct 14 04:00:00 2026     node /Users/NAME/proj/node_modules/.bin/vite"
dev_recs="$(printf '%s\n' "$dev_snap" | AGENTS_SELF=9999 agents_classify "$sup_listen"$'\n601 5174' "" \
    | agents_enrich "$(printf '600\t%s/proj\n' "$HOME")" "")"
[[ "$(printf '%s\n' "$dev_recs" | awk -F '\t' '$1 == "stale" && $2 == 600 { print $3 "/" $10 }')" == server/5174 ]] \
    || fail "orphaned npm run dev (vite child on 5174) not stale"
pass "tmux/screen/shell/agent hosts are never stale; an orphaned npm run dev is"

# Refusals: a process hosting shells or agents (a terminal app, an editor, tmux)
# is refused; an agent root may still be killed with its tree.
host_snap="$sup_fixture"$'\n'"  800     1   501 me    0.0  90000  0:05.00 05:00:00 Wed Oct 14 04:00:00 2026     /Applications/Warp.app/Contents/MacOS/stable"
host_snap+=$'\n'"  801   800   501 me    0.0   3000  0:00.10 05:00:00 Wed Oct 14 04:00:00 2026     -zsh"
host_snap+=$'\n'"  900     1   501 me    0.0  90000  0:05.00 05:00:00 Wed Oct 14 04:00:00 2026     /Applications/Cursor.app/Contents/Frameworks/Cursor Helper (Plugin).app/Contents/MacOS/Cursor Helper (Plugin) --type=utility"
host_snap+=$'\n'"  901   900   501 me    1.0 300000  0:05.00 05:00:00 Wed Oct 14 04:00:00 2026     claude"
for p in 800 900 100 101; do
    [[ "$(AGENTS_SELF=9999 agents_refusal "$p" "$host_snap")" == *"it hosts a session"* ]] \
        || fail "host pid $p not refused: $(AGENTS_SELF=9999 agents_refusal "$p" "$host_snap")"
done
! AGENTS_SELF=9999 agents_refusal 102 "$host_snap" >/dev/null || fail "an agent root refused"
! AGENTS_SELF=9999 agents_refusal 901 "$host_snap" >/dev/null || fail "an agent root under an editor refused"
! AGENTS_SELF=9999 agents_refusal 600 "$dev_snap" >/dev/null || fail "an npm run dev tree refused"
pass "kill/term refuse hosts of shells or agents (Warp, editor helpers, tmux); agent roots stay killable"

# launchd jobs (macOS) and systemd services (Linux) are never stale.
launchctl_out=$'PID\tStatus\tLabel\n-\t0\tcom.apple.example\n400\t0\tcom.example.devserver\n60831\t0\thomebrew.mxcl.example'
keep="$(printf '%s\n' "$launchctl_out" | _agents_launchd_pids | tr '\n' ' ')"
[[ "$keep" == "400 60831 " ]] || fail "launchctl list parse: $keep"
[[ -z "$(printf '%s\n' "$sup_fixture" | AGENTS_SELF=9999 agents_classify "$sup_listen" "$keep" | awk -F '\t' '$2 == 400 && $1 != "hog"')" ]] \
    || fail "a launchd job flagged as a dev server"
[[ -z "$(printf '%s\n' "$fixture" | agents_classify "" "$keep" | awk -F '\t' '$1 == "stale" && $2 == 60831')" ]] \
    || fail "a launchd job flagged as an orphan"
printf '0::/user.slice/user-1000.slice/user@1000.service/app.slice/vite.service\n' | _agents_cgroup_service || fail "user service not detected"
printf '1:name=systemd:/system.slice/nginx.service\n' | _agents_cgroup_service || fail "cgroup v1 service not detected"
! printf '0::/user.slice/user-1000.slice/user@1000.service/app.slice/app-gnome-terminal.slice/vte-spawn-1.scope\n' | _agents_cgroup_service \
    || fail "a terminal scope treated as a service"
pass "launchd jobs (launchctl list) and systemd .service units are kept out of stale"

# Dev servers left in $TMPDIR or a Claude scratchpad count too.
tmp_recs="$(printf '%s\n' "$sup_recs" | agents_enrich $'400\t/private/tmp/claude-501/scratch/app' "")"
[[ "$(printf '%s\n' "$tmp_recs" | awk -F '\t' '$1 == "stale" && $2 == 400 { print $3 }')" == server ]] || fail "dev server in a Claude scratchpad missed"
tmp_recs="$(printf '%s\n' "$sup_recs" | TMPDIR=/var/folders/xx/T/ agents_enrich $'400\t/private/var/folders/xx/T/build' "")"
[[ "$(printf '%s\n' "$tmp_recs" | awk -F '\t' '$1 == "stale" && $2 == 400 { print $3 }')" == server ]] || fail "dev server under \$TMPDIR missed"
tmp_recs="$(printf '%s\n' "$sup_recs" | agents_enrich $'400\t/var/empty' "")"
[[ -z "$(printf '%s\n' "$tmp_recs" | awk -F '\t' '$2 == 400 && $1 != "hog"')" ]] || fail "a listener in /var/empty flagged"
pass "dev-server cwd scope: \$HOME, \$TMPDIR and /private/tmp/claude-UID"

# Killing: no phantom entry from a trailing newline; processes that joined a
# targeted tree after the plan are found (start-time guarded).
[[ -z "$(_agents_alive $'\n\n')" ]] || fail "an empty plan line counted as alive"
snap2="$fixture"$'\n'"61000 60872   501 me                 0.0   1000   0:00.00 00:01 Wed Oct 14 09:14:00 2026     node new-child.js"
plan2=$'60872\tWed_Oct_14_08:23:57_2026\tchrome-devtools-mcp\n60829\tWed_Oct_14_08:23:56_2026\tnpm'
[[ "$(printf '%s\n' "$snap2" | _agents_new_members $'60829\tWed_Oct_14_08:23:56_2026' "$plan2" | cut -f1)" == 61000 ]] \
    || fail "a child spawned during the grace period is missed"
[[ -z "$(printf '%s\n' "$snap2" | _agents_new_members $'60829\tMon_Jan_01_00:00:00_2024' "$plan2")" ]] \
    || fail "new members of a reused root pid"
pass "kill: empty plan lines ignored; late children of a targeted tree are found"

# A real tree that honors SIGTERM: returns before the grace period, no SIGKILL.
if ps -o lstart= -p $$ >/dev/null 2>&1; then
    ( bash -c 'echo $$ > "$1"; sleep 300 & sleep 300 & wait' _ "$tmp/tree.pid" </dev/null >/dev/null 2>&1 & )
    for _ in 1 2 3 4 5 6 7 8 9 10; do [[ -s "$tmp/tree.pid" ]] && break; sleep 0.1; done
    root="$(cat "$tmp/tree.pid")"; sleep 0.2
    t0=$SECONDS
    out="$(AGENTS_SELF=$$ AGENTS_UID="$(id -u)" AGENTS_GRACE=3 AGENTS_YES=true AGENTS_DRY_RUN=false agents_kill_tokens true "$root" 2>&1)"
    took=$((SECONDS - t0))
    [[ "$out" != *SIGKILL* ]] || fail "SIGKILL printed for a tree that exited on SIGTERM: $out"
    [[ $took -lt 3 ]] || fail "waited the full grace period (${took}s) for a tree that was already gone"
    ! kill -0 "$root" 2>/dev/null || fail "tree root still running"
    pass "kill: a tree that exits on SIGTERM returns at once, with no SIGKILL line"
else
    echo "SKIP: ps unavailable here (sandbox?): live kill test not run"
fi

# Keep-awake: a second `on` replaces the first holder; off clears state and lock.
mkdir -p "$tmp/stubbin" "$tmp/empty"
printf '#!/bin/bash\nexec sleep 300\n' > "$tmp/stubbin/caffeinate"; chmod +x "$tmp/stubbin/caffeinate"
awake() { PATH="$tmp/stubbin:$PATH" AGENTS_RUN_DIR="$tmp/run" bash "$REPO_DIR/bin/agents" awake "$@"; }
# The live double-on check needs ps to verify holders (a sandbox blocks it).
if ps -o lstart= -p $$ >/dev/null 2>&1; then
    awake on >/dev/null || fail "awake on failed"
    p1="$(cut -d' ' -f1 "$tmp/run/awake")"
    awake on 1m >/dev/null || fail "second awake on failed"
    p2="$(cut -d' ' -f1 "$tmp/run/awake")"
    sleep 0.3
    [[ "$p1" != "$p2" ]] || fail "second awake on reused the holder"
    ! kill -0 "$p1" 2>/dev/null || { kill "$p1"; fail "second awake on orphaned the first holder"; }
    kill -0 "$p2" 2>/dev/null || fail "second holder not running"
    [[ "$(awake off)" == *"stopped pid $p2"* ]] || fail "awake off"
    sleep 0.3
    ! kill -0 "$p2" 2>/dev/null || { kill "$p2"; fail "awake off left the holder running"; }
    [[ ! -e "$tmp/run/awake" && ! -e "$tmp/run/awake.lock" ]] || fail "awake off left state or the lock behind"
else
    echo "SKIP: ps unavailable here (sandbox?): live double-on check not run"
fi
echo "A" > "$tmp/state"; _agents_rm_if_same "$tmp/state" "B"; [[ -f "$tmp/state" ]] || fail "removed a rewritten state file"
_agents_rm_if_same "$tmp/state" "A"; [[ ! -e "$tmp/state" ]] || fail "unchanged state file kept"
# shellcheck disable=SC2123  # an empty PATH is the point
err="$( (PATH="$tmp/empty"; agents_awake_on) 2>&1 )" && fail "awake on succeeded without an inhibitor"
[[ "$err" == *"keep-awake is unavailable"* ]] || fail "no message without an inhibitor: $err"
pass "keep-awake: double on leaves one holder; off cleans up; no inhibitor is an error"

# The recorded holder: cleared only when really gone (ESRCH), kept on EPERM,
# and a "-" start (unverifiable) never lets `off` kill the pid.
state_dir="$tmp/state-run"; mkdir -p "$state_dir"
( sleep 0 ) & dead=$!; wait "$dead" 2>/dev/null || true
printf '%s - on 0\n' "$dead" > "$state_dir/awake"
! AGENTS_RUN_DIR="$state_dir" agents_awake_state >/dev/null || fail "a dead holder reported as alive"
[[ ! -e "$state_dir/awake" ]] || fail "a dead holder's record was kept"
printf '1 - on 0\n' > "$state_dir/awake"       # pid 1: kill -0 gives EPERM, not ESRCH
[[ "$(AGENTS_RUN_DIR="$state_dir" agents_awake_state)" == "1 on 0 0" ]] || fail "EPERM treated as gone"
[[ -e "$state_dir/awake" ]] || fail "record cleared on EPERM"
sleep 30 & live=$!
printf '%s - on 0\n' "$live" > "$state_dir/awake"
out="$(AGENTS_RUN_DIR="$state_dir" agents_awake_off 2>&1)" && fail "awake off accepted an unverified holder"
kill -0 "$live" 2>/dev/null || fail "awake off killed a pid it could not verify"
[[ "$out" == *"can't verify"* && -e "$state_dir/awake" ]] || fail "unverified off: $out"
kill "$live" 2>/dev/null; wait "$live" 2>/dev/null || true
pass "keep-awake state: cleared only on ESRCH, kept on EPERM; an unverified pid is never killed"

# The lock is released even when the command exits early.
# shellcheck disable=SC2034,SC2329  # both are read by the sourced agents_awake
( AGENTS_RUN_DIR="$tmp/lock-run"; agents_awake_on() { exit 3; }; agents_awake on ) && fail "early exit not propagated"
[[ ! -e "$tmp/lock-run/awake.lock" ]] || fail "the awake lock survived an early exit"
pass "keep-awake lock is released by its EXIT trap"

# Root is refused; AGENTS_SELF is a test-only override.
out="$(AGENTS_TESTING=1 AGENTS_EUID=0 bash "$REPO_DIR/bin/agents" kill -n 123 2>&1)" && fail "kill ran as root"
[[ "$out" == *"refusing to kill as root"* ]] || fail "root refusal message: $out"
# shellcheck disable=SC2016  # $$ and $1 belong to the inner bash
AGENTS_SELF=123 bash -c '. "$1"; [[ "$AGENTS_SELF" == "$$" ]]' _ "$REPO_DIR/bin/agents" || fail "AGENTS_SELF honored outside tests"
# shellcheck disable=SC2016
AGENTS_TESTING=1 AGENTS_SELF=123 bash -c '. "$1"; [[ "$AGENTS_SELF" == 123 ]]' _ "$REPO_DIR/bin/agents" || fail "AGENTS_SELF ignored in tests"
pass "destructive commands refuse root; AGENTS_SELF/AGENTS_UID only under AGENTS_TESTING"

# 5. The table (colors off: stdout is not a terminal here).
_agents_colors
calm_enriched="$(printf '%s\n' "$enriched" | awk -F '\t' '$1 == "agent"')"
table="$(printf '%s\n' "$enriched" | AGENTS_WIDTH=140 agents_render "agents stale hogs quiet")"
[[ "$table" == *"AGENTS (2) + codex daemon"* && "$table" == *"STALE (4)"* && "$table" == *"HOGS (2)"* ]] || fail "table sections: $table"
[[ "$table" == *"PROJECT"*"CWD"* && "$table" == *" app "*"~/work/app"* ]] || fail "project column before the cwd"
[[ "$(printf '%s\n' "$table" | grep -E '^  [0-9]' | head -3 | awk '{ print $1 }' | tr '\n' ' ')" == "90419 84091 61904 " ]] \
    || fail "agent rows: working first, the daemon last"
[[ "$table" != *$'\033'* ]] || fail "colors written to a non-terminal"
[[ "$(printf '%s\n' "$enriched" | agents_render stale)" != *AGENTS* ]] || fail "agents stale prints more than stale"
quiet="$(printf '%s\n' "$calm_enriched" | agents_render "agents stale hogs quiet")"
[[ "$quiet" == *"no stale processes · no hogs"* && "$quiet" != *"STALE ("* && "$quiet" != *"HOGS ("* ]] || fail "empty stale/hogs not folded: $quiet"
[[ "$(printf '%s\n' "$calm_enriched" | agents_render stale)" == *"STALE (0)"*"none"* ]] || fail "agents stale hides its own empty section"
pass "the table: sessions counted without the daemon, project column, empty sections folded, plain off a terminal"

# Project names (bash and awk agree) and the needs-you ordering.
for c in "$HOME/work/app" "$HOME/code/shop/.claude/worktrees/fix-cart" "$HOME/code/shop/.claude/worktrees/fix-cart/sub" "$HOME" "/opt/x/" -; do
    want="$(agents_project "$c")"
    got="$(printf 'agent\t1\tclaude\t0\t0\t0\t0\t0\ts\t-\tme\t-\t%s\targs\n' "$c" | agents_enrich "" "" | cut -f15)"
    [[ "$want" == "$got" ]] || fail "project name for $c: bash '$want', awk '$got'"
done
[[ "$(agents_project "$HOME/code/shop/.claude/worktrees/fix-cart/sub")" == shop/fix-cart ]] || fail "worktree project name"
[[ "$(agents_project "$HOME")" == "~" && "$(agents_project /opt/x/)" == x ]] || fail "home and trailing-slash project names"
order="$(printf '%s\n' \
    $'agent\t1\tdaemon\t0\t0\t0\t0\t0\ts\t-\tme\t-\t-\ta' \
    $'agent\t2\tclaude\t0\t0\t0\t0\t0\ts\t-\tme\tidle\t/p/a\ta' \
    $'agent\t3\tclaude\t0\t0\t0\t0\t0\ts\t-\tme\t-\t/p/b\ta' \
    $'agent\t4\tcodex\t0\t0\t0\t0\t0\ts\t-\tme\tworking\t/p/c\ta' \
    $'agent\t5\tclaude\t0\t0\t0\t0\t0\ts\t-\tme\tblocked\t/p/d\ta' | agents_enrich "" "" | cut -f2 | tr '\n' ' ')"
[[ "$order" == "5 4 2 3 1 " ]] || fail "agent order (blocked, working, idle, unknown, daemon): $order"
pass "project names (worktrees as repo/name) agree in bash and awk; blocked sessions sort first"

# 6. Machine-readable output.
json="$(printf '%s\n' "$enriched" | agents_json)"
if command -v jq >/dev/null 2>&1; then
    printf '%s' "$json" | jq -e '.agents | length == 3' >/dev/null || fail "json agents: $json"
    printf '%s' "$json" | jq -e '.stale[] | select(.pid == 4100) | .ports == [5173]' >/dev/null || fail "json ports"
    printf '%s' "$json" | jq -e '.hogs[0].command | contains("Messages")' >/dev/null || fail "json hogs"
    printf '%s' "$json" | jq -e '.awake.active == false' >/dev/null || fail "json awake"
    pass "agents json is valid JSON (checked with jq)"
else
    [[ "$json" == '{"agents":['* ]] || fail "json shape"
    pass "agents json shape (jq not installed: not validated)"
fi
[[ "$(printf 'agent\t1\tclaude\t0\t0\t0\t0\t0\ts\t-\tme\t-\t-\ta "q" \\x\n' | agents_json | sed 's/.*\("command":".*"\),"activity".*/\1/')" == '"command":"a \"q\" \\x"' ]] \
    || fail "json escaping of quotes and backslashes"
pass "json escapes quotes and backslashes"

# 7. The SwiftBar plugin, against a stub `agents` that replays a snapshot.
mkdir -p "$HOME/.local/bin"
# shellcheck disable=SC2016  # $1 belongs to the stub
printf '#!/bin/bash\n[[ "$1" == tsv ]] && cat "%s"\n' "$tmp/tsv" > "$HOME/.local/bin/agents"
chmod +x "$HOME/.local/bin/agents"
calm="$(printf '%s\n' "$enriched" | awk -F '\t' '$1 == "agent"')"
sys_line=$'sys\t23\t7.8\t14\t66\tnormal\t85\tdischarging'
# plugin RECORDS EXTRA_LINES — the menu for that snapshot.
plugin() {
    { printf '%s\n' "$1"; printf '%s\n' "$2"; } > "$tmp/tsv"
    bash "$REPO_DIR/configs/swiftbar/agents.10s.sh"
}
line_no() { printf '%s\n' "$menu" | grep -n -m1 -e "$1" | cut -d: -f1; }

# The plugin offers Terminate only for hogs owned by the user running it.
mine_recs="$(printf '%s\n' "$enriched" | awk -F '\t' -v OFS='\t' -v u="$(id -un)" '$11 == "me" { $11 = u } { print }')"
menu="$(plugin "$mine_recs" "$sys_line"$'\nawake\tagents\t8800\t0\nthermal\t2\theavy\npower\tautomatic')"
title="$(printf '%s\n' "$menu" | head -1)"
[[ "$title" == ":terminal: 2 :cup.and.saucer.fill: | sfcolor=#FF453A" ]] || fail "default title, heavy thermal: $title"
[[ "$menu" == *"Agents (2) | size=12"* ]] || fail "Agents header does not count sessions only"
[[ "$menu" == *$'\n'"app · claude · working · 102.4% · 1.0G | sfimage=circle.fill sfconfig=eyJyZW5kZXJpbmdNb2RlIjoiUGFsZXR0ZSIsImNvbG9ycyI6WyIjMzBEMTU4Il19 bash="*" terminal=false param1=reveal param2=90419@Wed_Oct_14_07:31:08_2026 symbolize=false"* ]] \
    || fail "agent row: project · kind · status · CPU · MEM with a green dot"
[[ "$menu" == *$'\n'"codex daemon · 0.0% · 70M | sfimage=gearshape refresh=true symbolize=false"* ]] || fail "daemon not its own (enabled) row"
[[ "$menu" != *" color="* ]] || fail "menu text colored with a fixed color"
[[ "$menu" == *"--Kill session… | bash="*" param1=kill param2=--confirm-gui param3=--notify param4=90419@Wed_Oct_14_07:31:08_2026"* ]] \
    || fail "killing a live session does not ask in a dialog"
[[ "$menu" == *"--Copy path | bash="*" terminal=false param1=copy-path param2=90419@Wed_Oct_14_07:31:08_2026 "* \
   && "$menu" == *"--Open in Finder | bash="*" terminal=false param1=reveal param2=90419@Wed_Oct_14_07:31:08_2026 "* ]] \
    || fail "Copy path / Open in Finder do not resolve the path from PID@START"
[[ "$menu" != *"param2=\"$HOME"* ]] || fail "a path is passed as a menu parameter"

# Hostile cwds and Herdr text: whatever a process controls stays out of the
# params. After removing the two trusted quoted paths, every param must be
# key=value with a plain value (fixed words, numbers, colors, PID@START).
# shellcheck disable=SC2016,SC1003  # literal attack strings, nothing to expand
hostile=(
    '/Users/me/a\" bash=/bin/sh param1=-c param2=open${IFS}-a${IFS}Calculator z=\"/w'
    '/Users/me/pipe | bash=/bin/sh param1=-c param2=id'
    '/Users/me/trailing\'
    '/Users/me/new\nline" param1=x'
)
for h in "${hostile[@]}"; do
    rec=$'agent\t90419\tclaude\t60\t1.0\t1.0\t1000\t0\tWed_Oct_14_07:31:08_2026\t-\tme\t'"blocked\" bash=/bin/sh"$'\t'"$h"$'\tclaude --continue\t'"x\" param1=y"
    hmenu="$(plugin "$rec" "")"
    bad="$(printf '%s\n' "$hmenu" | awk -v a="\"$HOME/.local/bin/agents\"" -v s="\"$REPO_DIR/configs/swiftbar/agents.10s.sh\"" '
        { n = gsub(/\|/, "|") }
        n > 1 { print "two separators: " $0; next }
        n == 1 {
            p = substr($0, index($0, "|") + 1)
            gsub(a, "AGENTS", p); gsub(s, "SELF", p)
            if (p !~ /^( +[a-z0-9]+=[A-Za-z0-9.#,_:@+-]+)+ *$/) print "unsafe params: " $0
        }')"
    [[ -z "$bad" ]] || fail "hostile cwd leaked into params ($h): $bad"
done
pass "a hostile cwd or Herdr text never reaches a menu parameter; paths resolve from PID@START at click time"

# Every action in every menu variant maps to a real command with valid
# arguments: `agents` subcommands (present in its dispatcher) or the plugin's
# own callbacks, nothing else.
check_actions() {   # MENU
    local target args sub a n=0
    while IFS=$'\t' read -r target args; do
        n=$((n + 1))
        # shellcheck disable=SC2086  # params are single words by construction
        set -- $args
        sub="${1:-}"; shift || true
        case "$target" in
            "$HOME/.local/bin/agents")
                grep -qE "^        $sub\)" "$REPO_DIR/bin/agents" || fail "menu calls unknown agents subcommand '$sub'"
                case "$sub" in
                    kill|term)
                        [[ $# -ge 1 ]] || fail "$sub without arguments"
                        for a in "$@"; do
                            [[ "$a" =~ ^(-y|--notify|--confirm-gui)$ || "$a" =~ ^[0-9]+@[A-Za-z0-9_:]+$ ]] || fail "$sub: bad argument '$a'"
                        done ;;
                    awake)
                        [[ "${1:-}" =~ ^(on|off|agents)$ ]] || fail "awake: bad mode '${1:-}'"
                        [[ $# -lt 2 ]] || agents_parse_duration "$2" >/dev/null || fail "awake on: bad duration '$2'" ;;
                    open-term)
                        [[ "${1:-}" != --hold ]] || shift
                        [[ "$*" == watch || "$*" == "awake status" ]] || fail "open-term: unexpected command '$*'" ;;
                    copy-path|reveal)
                        [[ $# -eq 1 && "$1" =~ ^[0-9]+@[A-Za-z0-9_:]+$ ]] || fail "$sub: expects one PID@START, got '$*'" ;;
                    config) [[ "$*" == --edit ]] || fail "config: unexpected '$*'" ;;
                    *) fail "menu runs agents $sub, which the test does not know" ;;
                esac ;;
            "$REPO_DIR/configs/swiftbar/agents.10s.sh")
                case "$sub" in
                    copy) [[ $# -eq 1 && "$1" =~ ^[0-9]+$ ]] || fail "copy: expects a pid, got '$*'" ;;
                    battery-settings|activity-monitor) [[ $# -eq 0 ]] || fail "$sub takes no arguments" ;;
                    *) fail "unknown plugin callback '$sub'" ;;
                esac
                grep -qE "^    $sub\)" "$REPO_DIR/configs/swiftbar/agents.10s.sh" || fail "plugin has no '$sub' callback" ;;
            *) fail "menu runs an unexpected program: $target" ;;
        esac
    done < <(printf '%s\n' "$1" | awk '
        /bash="/ {
            t = $0; sub(/.*bash="/, "", t); sub(/".*/, "", t)
            n = 0; delete v
            s = $0
            while (match(s, /param[0-9]+=[^ ]+/)) {
                kv = substr(s, RSTART, RLENGTH); s = substr(s, RSTART + RLENGTH)
                k = kv; sub(/=.*/, "", k); sub(/^param/, "", k); val = kv; sub(/^[^=]*=/, "", val)
                v[k + 0] = val; if (k + 0 > n) n = k + 0
            }
            out = ""; for (i = 1; i <= n; i++) out = out (i > 1 ? " " : "") v[i]
            print t "\t" out
        }')
    [[ $n -gt 0 ]] || fail "no actions found in the menu"
}
check_actions "$(plugin "$mine_recs" "$sys_line"$'\nawake\tagents\t8800\t0\nthermal\t2\theavy\npower\tautomatic\nconf\tAGENTS_CONF\t'"$conf")"
pass "every menu action maps to an agents subcommand or plugin callback with valid arguments"
[[ "$(printf '%s\n' "$menu" | grep -c 'Open agents watch')" == 1 ]] || fail "Open agents watch repeated per session"
[[ "$menu" != *"terminal=true"* ]] || fail "the menu relies on SwiftBar's terminal=true"
[[ "$menu" == *"Open agents watch | bash="*" param1=open-term terminal=false param2=watch"* ]] || fail "Open agents watch does not use open-term"
[[ "$menu" == *"--Who holds the Mac awake? | bash="*" param1=open-term terminal=false param2=--hold param3=awake param4=status"* ]] \
    || fail "Who holds the Mac awake? does not hold its window open"
[[ "$menu" == *"--Kill tree | bash="*" param1=kill param2=-y param3=--notify param4=60829@Wed_Oct_14_08:23:56_2026"* ]] \
    || fail "a stale kill is not one click with a notification"
reap_line="$(printf '%s\n' "$menu" | grep '^Reap all stale')"
[[ "$reap_line" == *"param1=kill param2=-y param3=--notify param4=60829@Wed_Oct_14_08:23:56_2026 param5=60831@Wed_Oct_14_08:23:56_2026 param6=27681@"*" param7=4100@"* ]] \
    || fail "Reap all stale does not pass the listed PID@START tokens: $reap_line"
[[ "$menu" != *"param1=reap"* ]] || fail "Reap all stale re-collects at click time"
[[ "$(printf '%s\n' "$menu" | grep -A2 '^yes · ' | grep -c 'Terminate (SIGTERM) | .*param3=--notify')" == 1 ]] || fail "a hog lost Terminate"
# System: two lines, the busiest processes as plain lines in the CPU submenu.
[[ "$menu" == *$'\n'"CPU 23% · Mem 34% · Load 7.8/14 | sfimage=cpu bash="*" param1=open-term terminal=false param2=watch"$'\n'"--Busiest processes | size=11"$'\n'"--web.test · 102.1% · 180M | bash="*" terminal=false param1=activity-monitor symbolize=false"* ]] \
    || fail "system CPU line with busiest processes in its submenu"
[[ "$menu" == *$'\n'"Battery 85% · Thermal heavy · Energy automatic | sfimage=battery.75percent sfconfig=eyJyZW5kZXJpbmdNb2RlIjoiUGFsZXR0ZSIsImNvbG9ycyI6WyIjRkY0NTNBIl19 bash="*" terminal=false param1=battery-settings"* ]] || fail "system battery/thermal line"
[[ "$(printf '%s\n' "$menu" | grep -A3 '^--web.test · ' | grep -c Terminate)" == 0 ]] || fail "a top process offers Terminate"
# Awake: state in the header, a check on the active choice.
[[ "$menu" == *$'\n'"Awake: while agents run | sfimage=cup.and.saucer refresh=true"* ]] || fail "awake header"
[[ "$menu" == *"--While agents run | "*"param2=agents checked=true"* && "$menu" != *"param2=off checked=true"* ]] || fail "awake check mark"
# Default order: agents, stale, hogs, awake, system.
[[ $(line_no '^Agents (') -lt $(line_no '^Stale (') && $(line_no '^Stale (') -lt $(line_no '^Hogs (') \
   && $(line_no '^Hogs (') -lt $(line_no '^Awake:') && $(line_no '^Awake:') -lt $(line_no '^CPU ') ]] || fail "default section order"
pass "SwiftBar menu: sessions first (project rows, dialog-confirmed kill), then stale, hogs, awake, compact system"

# A process named "---evil" must not become a separator or a submenu.
evil=$'hog\t9200\t---evil\t60\t95.0\t95.0\t1000\t0\tWed_Oct_14_09:13:30_2026\t-\tme\t-\t-\t---evil'
menu_evil="$(plugin "$evil" "")"
printf '%s\n' "$menu_evil" | grep -q '^evil · 95.0% now' || fail "leading dashes not stripped from a process name"
! printf '%s\n' "$menu_evil" | grep -qE '^-+evil' || fail "a process name starts a menu line with dashes"

# Needs you: a blocked session leads the title and the menu.
blocked_recs="$(printf '%s\n' "$records" | agents_enrich "$(printf '84091\t%s/code/shop/.claude/worktrees/fix-cart\n90419\t%s/work/app\n' "$HOME" "$HOME")" \
    "$(printf 'claude\tworking\t%s/work/app\nclaude\tblocked\t%s/code/shop/.claude/worktrees/fix-cart\n' "$HOME" "$HOME")" | awk -F '\t' '$1 == "agent"')"
menu="$(plugin "$blocked_recs" $'awake\toff\t-\t0\nthermal\t0\tnominal')"
title="$(printf '%s\n' "$menu" | head -1)"
[[ "$title" == ":terminal: 2 · 1 blocked | sfcolor=#FF9F0A" ]] || fail "blocked title: $title"
[[ "$(printf '%s\n' "$menu" | sed -n 3p)" == "Needs you (1) | size=12" ]] || fail "Needs you is not the first section"
[[ "$(printf '%s\n' "$menu" | sed -n 4p)" == "shop/fix-cart · claude · waiting for you | sfimage=exclamationmark.circle.fill sfconfig=eyJyZW5kZXJpbmdNb2RlIjoiUGFsZXR0ZSIsImNvbG9ycyI6WyIjRkY5RjBBIl19 bash=\"$HOME/.local/bin/agents\" terminal=false param1=reveal param2=84091@Wed_Oct_14_08:40:22_2026 symbolize=false" ]] \
    || fail "blocked session line: $(printf '%s\n' "$menu" | sed -n 4p)"
[[ $(line_no '^shop/fix-cart · claude · blocked') -lt $(line_no '^app · claude · working') ]] || fail "blocked session not first among agents"
check_actions "$(plugin "$blocked_recs" "$sys_line"$'\nawake\ttimed\t8800\t9999999999')"
pass "SwiftBar: blocked sessions lead (title count, Needs you section, first in Agents)"

# A calm machine: icon and count, and no empty sections.
menu="$(plugin "$calm" "$sys_line"$'\nawake\toff\t-\t0\nthermal\t0\tnominal')"
[[ "$(printf '%s\n' "$menu" | head -1)" == ":terminal: 2" ]] || fail "calm title: $(printf '%s\n' "$menu" | head -1)"
[[ "$menu" != *"Needs you"* && "$menu" != *"Stale ("* && "$menu" != *"Hogs ("* ]] || fail "empty sections shown"
[[ "$menu" == *$'\n'"Awake: off | sfimage=cup.and.saucer refresh=true"* && "$menu" == *"param2=off checked=true"* ]] || fail "awake off state"
[[ "$menu" == *$'\n'"Battery 85% · Thermal nominal · Energy unknown | sfimage=battery.75percent bash="*" terminal=false param1=battery-settings"$'\n'* ]] || fail "calm battery line"
until_epoch=$(( $(date +%s) + 2900 ))
menu="$(plugin "$calm" "awake"$'\t'"timed"$'\t'"8800"$'\t'"$until_epoch")"
[[ "$menu" == *$'\n'"Awake: 48m left | sfimage=cup.and.saucer"* || "$menu" == *$'\n'"Awake: 47m left | sfimage=cup.and.saucer"* ]] || fail "awake time left"
title="$(plugin "$enriched" $'awake\toff\t-\t0\nthermal\t0\tnominal' | head -1)"
[[ "$title" == ":terminal: 2 | sfcolor=#FF9F0A" ]] || fail "stale/hogs tint: $title"
title="$(plugin "$calm" $'sys\t5\t1.0\t14\t9\twarn\t-\t-\nthermal\t0\tnominal' | head -1)"
[[ "$title" == ":terminal: 2 | sfcolor=#FF9F0A" ]] || fail "memory-pressure tint: $title"
pass "SwiftBar: a calm machine shows icon and count only, no empty sections; tints when something needs a look"

# AGENTS_BAR_TITLE tokens, AGENTS_BAR_ICON, and an empty title.
title="$(plugin "$calm" "$sys_line"$'\nthermal\t1\tmoderate\nconf\tAGENTS_BAR_TITLE\tcount cpu mem load battery thermal warn\nconf\tAGENTS_BAR_ICON\tbrain' | head -1)"
[[ "$title" == ":brain: 2 :cpu: 23% :memorychip: 34% :gauge.medium: 7.8 :battery.75percent: 85% :thermometer.medium: moderate" ]] \
    || fail "title tokens: $title"
title="$(plugin "$calm" $'conf\tAGENTS_BAR_TITLE\t-' | head -1)"
[[ "$title" == ":terminal:" ]] || fail "empty AGENTS_BAR_TITLE: $title"
pass "SwiftBar title follows AGENTS_BAR_TITLE and AGENTS_BAR_ICON"

# AGENTS_BAR_SECTIONS picks and orders the sections.
menu="$(plugin "$enriched" $'conf\tAGENTS_BAR_SECTIONS\thogs agents')"
[[ "$menu" != *"Awake:"* && "$menu" != *"CPU "* && "$menu" != *"Stale ("* ]] || fail "unlisted sections shown"
[[ $(line_no '^Hogs (') -lt $(line_no '^Agents (') ]] || fail "sections not in AGENTS_BAR_SECTIONS order"
menu="$(plugin "$enriched" "$sys_line")"
[[ "$(printf '%s\n' "$menu" | grep -c '^Messages · ')" == 1 && "$menu" != *"--Messages · "* ]] || fail "a hog listed twice (hogs and top)"
pass "SwiftBar sections follow AGENTS_BAR_SECTIONS; top processes skip the hogs"

# 9. What sessions run: activity classification, flags, JSON, ls and menu.
act_fixture="$(cat <<'EOF'
    1     0     0 root  0.0  20000 10:00.00 13-16:00:00 Wed Sep 30 16:57:15 2026     /sbin/launchd
  900     1   501 me    0.0   3000  0:00.10 05:00:00 Wed Oct 14 04:00:00 2026     -zsh
 1000   900   501 me    5.0 600000  1:00.00 01:00:00 Wed Oct 14 08:00:00 2026     claude
 1001  1000   501 me    0.0  90000  0:00.50 01:00:00 Wed Oct 14 08:00:01 2026     npm exec chrome-devtools-mcp@latest
 1002  1001   501 me    0.0 110000  0:00.40 01:00:00 Wed Oct 14 08:00:02 2026     chrome-devtools-mcp
 1003  1002   501 me    0.0  60000  0:00.40 01:00:00 Wed Oct 14 08:00:02 2026     node /Users/NAME/.npm/_npx/abc/node_modules/chrome-devtools-mcp/build/index.js
 1004  1000   501 me    0.0  50000  0:00.10 01:00:00 Wed Oct 14 08:00:01 2026     node /Users/NAME/.local/lib/example-agent-mcp.cjs
 1005  1000   501 me    0.0   1900  0:00.00 01:00 Wed Oct 14 08:59:00 2026     caffeinate -i -t 300
 1010  1000   501 me    0.0   3000  0:00.10 02:00 Wed Oct 14 08:58:00 2026     /bin/zsh -c source /Users/NAME/.claude/shell-snapshots/snapshot-zsh-1-x.sh 2>/dev/null || true && eval 'cd /Users/NAME/repo/.claude/worktrees/feat-a && GOFLAGS=-mod=mod go test -race ./internal/web 2>&1 | tail -30' < /dev/null && pwd -P >| /tmp/cwd-1
 1011  1010   501 me    1.0  90000  0:01.00 02:00 Wed Oct 14 08:58:00 2026     go test -race ./internal/web
 1012  1011   501 me   99.0 180000  1:50.00 01:55 Wed Oct 14 08:58:05 2026     /tmp/go-build1/b001/web.test -test.paniconexit0
 1013  1010   501 me    0.0   1000  0:00.00 02:00 Wed Oct 14 08:58:00 2026     tail -30
 1020  1000   501 me    0.0   3000  0:00.10 04:00 Wed Oct 14 08:56:00 2026     /bin/zsh -c source /Users/NAME/.claude/shell-snapshots/snapshot-zsh-1-x.sh 2>/dev/null || true && eval 'cd /Users/NAME/repo/.claude/worktrees/feat-a && go test -race ./internal/web/ 2>&1 | tail -30' < /dev/null && pwd -P >| /tmp/cwd-2
 1030  1000   501 me    0.0   2000  0:00.10 52:00 Wed Oct 14 08:08:00 2026     /bin/zsh -c source /Users/NAME/.claude/shell-snapshots/snapshot-zsh-1-x.sh 2>/dev/null || true && eval 'until [ -s /tmp/x ]; do sleep 5; done' < /dev/null && pwd -P >| /tmp/cwd-3
 1040  1000   501 me    0.0   2000  0:00.10 03:00 Wed Oct 14 08:57:00 2026     bash -lc claude -p hello
 1041  1040   501 me    2.0 300000  0:03.00 03:00 Wed Oct 14 08:57:00 2026     claude -p hello
 1050  1000   501 me    0.0   2000  0:00.10 03:00 Wed Oct 14 08:57:00 2026     /usr/local/bin/some-helper --serve
 1060  1000   501 me    0.0   2000  0:00.10 00:30 Wed Oct 14 08:59:30 2026     /bin/zsh -c source /Users/NAME/.claude/shell-snapshots/snapshot-zsh-1-x.sh 2>/dev/null || true && eval 'GOPRIVATE='"'"'x/*'"'"' go vet ./...' < /dev/null && pwd -P >| /tmp/cwd-4
 1080  1000   501 me    0.0   9000  0:01.00 45:00 Wed Oct 14 08:15:00 2026     /bin/zsh -c source /Users/NAME/.claude/shell-snapshots/snapshot-zsh-1-x.sh 2>/dev/null || true && eval 'make serve' < /dev/null && pwd -P >| /tmp/cwd-5
 2000   900   501 me    1.0 300000  0:30.00 30:00 Wed Oct 14 08:30:00 2026     codex
 2010  2000   501 me    0.0   3000  0:00.10 01:00 Wed Oct 14 08:59:00 2026     bash -lc 'go test -race ./internal/web'
 2020  2000   501 me    0.0   3000  0:00.10 01:00 Wed Oct 14 08:59:00 2026     sandbox-exec -p (version 1)(allow default) bash -lc 'npm test'
EOF
)"
act_recs="$(printf '%s\n' "$act_fixture" | AGENTS_SELF=9999 agents_classify "" "")"
afield() { printf '%s\n' "$act_recs" | awk -F '\t' -v p="$1" -v c="$2" '$1 == "act" && $2 == p { print $c }'; }
for pair in 1001:mcp 1004:mcp 1005:keepawake 1010:tool 1020:tool 1030:tool 1040:tool 1041:session 1050:other 1060:tool 1080:tool 2010:tool 2020:tool; do
    [[ "$(afield "${pair%%:*}" 3)" == "${pair#*:}" ]] || fail "activity class of ${pair%%:*}: $(afield "${pair%%:*}" 3), want ${pair#*:}"
done
[[ -z "$(afield 1002 3)$(afield 1011 3)$(afield 1012 3)" ]] || fail "grandchildren listed as their own units"
[[ "$(afield 1001 12)/$(afield 1001 8)" == "chrome-devtools-mcp/2" && "$(afield 1004 12)" == example-agent-mcp ]] || fail "MCP names and process counts"
[[ "$(afield 1010 14)" == "go test -race ./internal/web" ]] || fail "Claude tool command: '$(afield 1010 14)'"
[[ "$(afield 1020 14)" == "go test -race ./internal/web" ]] || fail "trailing slash makes a different command: '$(afield 1020 14)'"
[[ "$(afield 1030 14)" == "until [ -s /tmp/x ]; do sleep 5; done" ]] || fail "loop command: '$(afield 1030 14)'"
[[ "$(afield 1060 14)" == "go vet ./..." ]] || fail "quoted env assignment not stripped: '$(afield 1060 14)'"
[[ "$(afield 2010 14)" == "go test -race ./internal/web" ]] || fail "Codex bash -lc command: '$(afield 2010 14)'"
[[ "$(afield 2020 14)" == "npm test" ]] || fail "Codex sandbox-exec … bash -lc command: '$(afield 2020 14)'"
[[ "$(afield 1010 12)" == /Users/NAME/repo/.claude/worktrees/feat-a ]] || fail "the cd target of a command is not recorded"
[[ "$(afield 1041 12)" == nested && "$(afield 1041 11)" == 1000 ]] || fail "nested session under a tool shell"
[[ "$(afield 1010 11)" == 1000 && "$(afield 2010 11)" == 2000 ]] || fail "units attributed to the wrong session"
[[ "$(afield 1010 5)" == 100.0 ]] || fail "tool subtree CPU: $(afield 1010 5)"
pass "activity: MCP servers by name, tool commands (Claude eval, Codex -lc and sandbox-exec), keep-awake, nested sessions, other"

act_cwds="$(printf '%s\t%s\n' 1000 /Users/NAME/repo 1010 /Users/NAME/repo/.claude/worktrees/feat-a 1020 /Users/NAME/repo \
    1030 /Users/NAME/repo 2000 /Users/NAME/repo 2010 /Users/NAME/repo/.claude/worktrees/feat-a)"
act_enr="$(printf '%s\n' "$act_recs" | AGENTS_TOOL_LONG=20 AGENTS_HOG_NOW=90 agents_enrich "$act_cwds" "")"
efld() { printf '%s\n' "$act_enr" | awk -F '\t' -v p="$1" -v c="$2" '$1 == "act" && $2 == p { print $c }'; }
[[ "$(efld 1010 15)/$(efld 1020 15)/$(efld 1030 15)" == "feat-a/feat-a/main" ]] || fail "worktree origin (a cd target beats the shell's cwd): $(efld 1010 15)/$(efld 1020 15)/$(efld 1030 15)"
[[ "$(efld 1010 16)" == "dup,hot" && "$(efld 1010 17)" == 3 ]] || fail "1010 flags: $(efld 1010 16) x$(efld 1010 17)"
[[ "$(efld 1020 16)" == dup ]] || fail "same command in the same session not dup: $(efld 1020 16)"
[[ "$(efld 2010 16)" == dup && "$(efld 2010 17)" == 3 ]] || fail "same command in the same directory across sessions not dup"
[[ "$(efld 1030 16)" == wait ]] || fail "a 52-minute polling loop is not a wait: $(efld 1030 16)"
[[ "$(efld 1080 16)" == long ]] || fail "a 45-minute command not long: $(efld 1080 16)"
[[ "$(efld 1060 16)" == - ]] || fail "a fresh, idle, unique command flagged: $(efld 1060 16)"
pass "activity flags: dup (same command, same directory), long, hot, wait; origin is the worktree"

# The reviewer's case: parallel worktree subagents running the same command
# from the main checkout (cd …/worktrees/X && …) are not duplicates; the same
# command twice in one directory is.
wt_fixture="$(cat <<'EOF'
    1     0     0 root  0.0  20000 10:00.00 13-16:00:00 Wed Sep 30 16:57:15 2026     /sbin/launchd
 3000     1   501 me    1.0 300000  0:30.00 30:00 Wed Oct 14 08:30:00 2026     claude
 3010  3000   501 me    0.0   3000  0:00.10 01:00 Wed Oct 14 08:59:00 2026     /bin/zsh -c source /Users/NAME/.claude/shell-snapshots/s.sh 2>/dev/null || true && eval 'cd /Users/NAME/r/.claude/worktrees/a && go test ./...' < /dev/null && pwd -P >| /tmp/c1
 3020  3000   501 me    0.0   3000  0:00.10 01:00 Wed Oct 14 08:59:00 2026     /bin/zsh -c source /Users/NAME/.claude/shell-snapshots/s.sh 2>/dev/null || true && eval 'cd /Users/NAME/r/.claude/worktrees/b && go test ./...' < /dev/null && pwd -P >| /tmp/c2
 3030  3000   501 me    0.0   3000  0:00.10 01:00 Wed Oct 14 08:59:00 2026     /bin/zsh -c source /Users/NAME/.claude/shell-snapshots/s.sh 2>/dev/null || true && eval 'make lint' < /dev/null && pwd -P >| /tmp/c3
 3040  3000   501 me    0.0   3000  0:00.10 00:30 Wed Oct 14 08:59:30 2026     /bin/zsh -c source /Users/NAME/.claude/shell-snapshots/s.sh 2>/dev/null || true && eval 'make lint' < /dev/null && pwd -P >| /tmp/c4
EOF
)"
wt_enr="$(printf '%s\n' "$wt_fixture" | AGENTS_SELF=9999 agents_classify "" "" \
    | agents_enrich "$(printf '%s\t%s\n' 3000 /Users/NAME/r 3010 /Users/NAME/r 3020 /Users/NAME/r 3030 /Users/NAME/r 3040 /Users/NAME/r)" "")"
wflags() { printf '%s\n' "$wt_enr" | awk -F '\t' -v p="$1" '$1 == "act" && $2 == p { print $16 "/" $15 }'; }
[[ "$(wflags 3010)" == "-/a" && "$(wflags 3020)" == "-/b" ]] || fail "worktree subagents flagged dup: $(wflags 3010) $(wflags 3020)"
[[ "$(wflags 3030)" == "dup/main" && "$(wflags 3040)" == "dup/main" ]] || fail "same command, same directory not dup: $(wflags 3030) $(wflags 3040)"
pass "parallel worktree subagents running the same command are not duplicates; the same command twice in one directory is"

if command -v jq >/dev/null 2>&1; then
    aj="$(printf '%s\n' "$act_enr" | agents_json)"
    printf '%s' "$aj" | jq -e '.schema_version == 1' >/dev/null || fail "schema_version"
    printf '%s' "$aj" | jq -e '.agents[] | (.start_epoch | type) == "number"' >/dev/null || fail "session start_epoch"
    printf '%s' "$aj" | jq -e '.agents[] | select(.pid == 1000) | .activity
        | (.mcp | map(.name) | sort) == ["chrome-devtools-mcp", "example-agent-mcp"]
        and (.mcp[] | select(.name == "chrome-devtools-mcp") | .procs) == 3
        and (.tools | length) == 6
        and (.tools[] | select(.pid == 1010) | .token == "1010@Wed_Oct_14_08:58:00_2026" and .origin == "feat-a" and .flags == ["dup","hot"] and .dup_count == 3)
        and (.tools[] | select(.pid == 1010) | (.start_epoch | type) == "number" and .start_epoch > 1700000000)
        and (.child_sessions[0].start_epoch | type) == "number"
        and (.child_sessions | length) == 1 and .child_sessions[0].depth == "nested"
        and .cpu.tools == 102.0 and .cpu.self == 5.0' >/dev/null \
        || fail "json activity: $(printf '%s' "$aj" | jq -c '.agents[] | select(.pid == 1000) | .activity')"
    pass "agents json: schema_version 1 and a per-session activity object"
fi

_agents_colors
act_table="$(printf '%s\n' "$act_enr" | AGENTS_WIDTH=160 AGENTS_LS_TOOLS=2 agents_render "agents stale hogs quiet")"
[[ "$act_table" == *"      mcp: 2 servers · 4 procs · 302M"* ]] || fail "ls mcp line: $act_table"
[[ "$act_table" == *"└ go test -race ./internal/web · 2m00s · 100% · feat-a  x3 dup  hot"* ]] || fail "ls tool line: $act_table"
[[ "$act_table" == *"... 4 more (agents ps 1000)"* ]] || fail "ls does not cap tool lines"
[[ "$act_table" == *"↳ claude -p hello · 3m00s · 2% · nested session"* ]] || fail "ls nested session line"
detail="$(printf '%s\n' "$act_enr" | AGENTS_FOCUS=1000 AGENTS_WIDTH=160 agents_render "agents detail")"
[[ "$detail" == *"AGENTS (1)"* && "$detail" == *"1030    until [ -s /tmp/x ]; do sleep 5; done · 52m00s · 0% · main  wait"* && "$detail" == *keepawake* ]] \
    || fail "agents ps detail: $detail"
pass "agents ls shows each session's MCP line and busiest commands; agents ps lists everything"

! agents_refusal 1010 "$act_fixture" >/dev/null || fail "a tool shell (zsh -c) refused as a session host"
[[ "$(printf '%s\n' "$act_fixture" | agents_tree 1010 | cut -f1 | tr '\n' ' ')" == "1012 1011 1013 1010 " ]] || fail "tool shell tree"
pass "a tool shell can be stopped: zsh -c is not an interactive shell"

# The menu: CPU split hint, Running list with Stop command…, duplicates.
act_menu_recs="$(printf '%s\n' "$act_enr" | awk -F '\t' '$1 == "agent" || $1 == "act"')"
menu="$(plugin "$act_menu_recs" "")"
[[ "$(printf '%s\n' "$menu" | head -1)" == *"sfcolor=#FF9F0A" ]] || fail "duplicate/long commands do not tint the title"
[[ "$menu" == *$'\n'"repo · claude · 107.0% (tools 102%) · 1.4G | "* ]] || fail "session row CPU split hint: $(printf '%s\n' "$menu" | grep "^repo")"
[[ "$menu" == *$'\n'"--Running (6) | size=11"$'\n'* ]] || fail "Running list"
[[ "$menu" == *$'\n'"--until [ -s /tmp/x ]; do sleep 5; done · 52m · 0% · main · waiting | refresh=true sfimage=hourglass "* ]] \
    || fail "a polling loop is not marked as waiting"
[[ "$menu" == *$'\n'"--go test -race ./internal/web · 2m · 100% · feat-a · 3× dup · hot | refresh=true symbolize=false"$'\n'"----Stop command… | bash="*" param1=kill param2=--confirm-gui param3=--notify param4=1010@Wed_Oct_14_08:58:00_2026 sfimage=xmark.octagon"* ]] \
    || fail "tool line with Stop command…"
[[ "$menu" == *"Stop duplicates: 2× go test -race ./internal/web (keep newest)… | "*"param4=1020@Wed_Oct_14_08:56:00_2026 sfimage"* ]] \
    || fail "Stop duplicates keeps the newest (1010) and stops the older (1020)"
[[ "$menu" == *$'\n'"repo: 2× go test -race ./internal/web running | "* && "$menu" == *$'\n'"repo: make serve · running 45m | "* ]] \
    || fail "Needs you: duplicates and long-running commands"
[[ "$menu" != *"repo: until [ -s"* ]] || fail "a polling loop counted as needing attention"
[[ "$menu" == *$'\n'"--MCP: 2 servers · 4 procs · 302M | size=11"* ]] || fail "MCP collapsed to one line"
check_actions "$menu"
pass "menu: tools CPU hint, Running list with Stop command…, Stop duplicates (keep newest), Needs you"

rm "$HOME/.local/bin/agents"
[[ "$(PATH=/usr/bin:/bin bash "$REPO_DIR/configs/swiftbar/agents.10s.sh" | head -1)" == ":exclamationmark.triangle: | sfcolor=#FF9F0A" ]] \
    || fail "plugin without the agents command"
pass "SwiftBar plugin degrades to a warning when agents is missing"

# 8. Terminal windows: AGENTS_TERMINAL=auto picks the first installed app;
#    each terminal gets the right launch command with agents' absolute path.
apps="$tmp/apps"; mkdir -p "$apps/A" "$apps/B"
pick() { AGENTS_TESTING=1 AGENTS_APP_DIRS="$apps/A $apps/B" AGENTS_TERMINAL="${1:-auto}" agents_terminal; }
[[ "$(pick)" == terminal ]] || fail "no app installed: expected Terminal"
mkdir -p "$apps/B/kitty.app";   [[ "$(pick)" == kitty ]]   || fail "auto: kitty"
mkdir -p "$apps/A/WezTerm.app"; [[ "$(pick)" == wezterm ]] || fail "auto: WezTerm before kitty"
mkdir -p "$apps/B/iTerm.app";   [[ "$(pick)" == iterm ]]   || fail "auto: iTerm before WezTerm"
mkdir -p "$apps/B/Ghostty.app/Contents/MacOS"
printf '#!/bin/bash\necho "Ghostty 1.1.3"\n' > "$apps/B/Ghostty.app/Contents/MacOS/ghostty"; chmod +x "$apps/B/Ghostty.app/Contents/MacOS/ghostty"
[[ "$(pick)" == iterm ]] || fail "auto: Ghostty older than 1.2 chosen"
printf '#!/bin/bash\necho "error: SentryInitFailed" >&2\necho "Ghostty 1.3.2-main+f523504ea"\n' > "$apps/B/Ghostty.app/Contents/MacOS/ghostty"
[[ "$(pick)" == ghostty ]] || fail "auto: Ghostty first (in ~/Applications too)"
[[ "$(pick terminal)" == terminal ]] || fail "AGENTS_TERMINAL=terminal ignored"
argv() { _agents_term_argv "$@" | tr '\n' '|'; }
[[ "$(argv ghostty watch)" == "open|-na|Ghostty|--args|-e|/usr/bin/env|PATH=$PATH|/bin/bash|-c|$(printf '%q ' "$AGENTS_PATH" watch)|" ]] \
    || fail "ghostty command: $(argv ghostty watch)"
[[ "$(argv kitty watch)" == "open|-na|kitty|--args|/usr/bin/env|"* ]] || fail "kitty command"
[[ "$(argv wezterm watch)" == "open|-na|WezTerm|--args|start|--|/usr/bin/env|"* ]] || fail "wezterm command"
[[ "$(argv terminal watch)" == "osascript|"*"do script (item 1 of argv)"*"/usr/bin/env PATH="* ]] || fail "Terminal command"
[[ "$(argv iterm watch)" == "osascript|"*"create window with default profile command"* ]] || fail "iTerm command"
[[ "$(argv ghostty --hold awake status)" == *"awake status ; printf"*"read -r -s -n 1|" ]] || fail "--hold keeps the window for a key"
! _agents_term_argv nope watch >/dev/null 2>&1 || fail "unknown terminal accepted"
[[ "$(AGENTS_TESTING=1 AGENTS_APP_DIRS="$apps/B" AGENTS_TERMINAL=auto bash "$REPO_DIR/bin/agents" open-term -n watch)" == "open -na Ghostty --args -e /usr/bin/env "* ]] \
    || fail "agents open-term -n"
_agents_conf_valid AGENTS_TERMINAL ghostty || fail "AGENTS_TERMINAL=ghostty rejected"
! _agents_conf_valid AGENTS_TERMINAL xterm || fail "AGENTS_TERMINAL=xterm accepted"
pass "open-term: auto picks Ghostty > iTerm > WezTerm > kitty > Terminal; per-terminal commands carry agents' path and PATH"

# agents cwd/copy-path/reveal take only PID@START and check the start time.
for bad in 123 '123@x y' '123@a"b' 'abc@Wed' ''; do
    rc=0; agents_token_cwd "$bad" >/dev/null 2>&1 || rc=$?
    [[ $rc -eq 2 ]] || fail "agents cwd accepted a malformed token '$bad' (rc $rc)"
done
if ps -o lstart= -p $$ >/dev/null 2>&1; then
    mkdir -p "$tmp/proj dir"
    ( cd "$tmp/proj dir" && exec sleep 30 ) & cpid=$!
    sleep 0.3
    ctok="$cpid@$(_agents_start "$cpid")"
    [[ "$(bash "$REPO_DIR/bin/agents" cwd "$ctok")" == "$(cd "$tmp/proj dir" && pwd -P)" ]] || fail "agents cwd: $(bash "$REPO_DIR/bin/agents" cwd "$ctok" 2>&1)"
    ! bash "$REPO_DIR/bin/agents" cwd "$cpid@Mon_Jan_01_00:00:00_2024" >/dev/null 2>&1 || fail "agents cwd ignored a changed start time"
    kill "$cpid" 2>/dev/null; wait "$cpid" 2>/dev/null || true
    pass "agents cwd resolves PID@START at click time and refuses a reused pid"
else
    echo "SKIP: ps unavailable here (sandbox?): live agents cwd test not run"
fi

# Dialog confirmation and notifications, through a stub osascript.
mkdir -p "$tmp/osa"
# shellcheck disable=SC2016  # the stub's own $* and $OSA_ANSWER
printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s"\n[[ -n "$OSA_ANSWER" ]] && { echo "button returned:$OSA_ANSWER"; [[ "$OSA_ANSWER" == Kill ]]; exit; }\nexit 0\n' "$tmp/osa.log" > "$tmp/osa/osascript"
chmod +x "$tmp/osa/osascript"
( PATH="$tmp/osa:$PATH"; OSA_ANSWER=Kill _agents_gui_confirm "Kill it?" ) || fail "dialog: Kill not accepted"
! ( PATH="$tmp/osa:$PATH"; OSA_ANSWER=Cancel _agents_gui_confirm "Kill it?" ) || fail "dialog: Cancel accepted"
grep -q 'default button "Cancel"' "$tmp/osa.log" || fail "dialog default button is not Cancel"
# shellcheck disable=SC2123  # an empty PATH is the point
! ( PATH="$tmp/empty"; _agents_gui_confirm "Kill it?" 2>/dev/null ) || fail "no osascript treated as yes"
: > "$tmp/osa.log"
( PATH="$tmp/osa:$PATH"; AGENTS_NOTIFY=true _agents_notify "Killed node (pid 1)" )
grep -q 'display notification' "$tmp/osa.log" || fail "notification not sent"
grep -q 'Killed node (pid 1)' "$tmp/osa.log" || fail "notification text"
: > "$tmp/osa.log"
( PATH="$tmp/osa:$PATH"; AGENTS_NOTIFY=false _agents_notify "quiet" )
[[ ! -s "$tmp/osa.log" ]] || fail "notification sent without --notify"
[[ "$(_agents_kill_message $'60712\tclaude\t26\tmyapp')" == "Kill claude in myapp (pid 60712, 26 child processes)?" ]] \
    || fail "dialog text: $(_agents_kill_message $'60712\tclaude\t26\tmyapp')"
[[ "$(_agents_kill_message $'29046\tnode\t0\t-')" == "Kill node (pid 29046)?" ]] || fail "dialog text without project or children"
[[ "$(_agents_kill_message $'1\ta\t1\tp\n2\tb\t0\tq')" == "Kill 2 process trees?"* ]] || fail "dialog text for two trees"
pass "kill dialog: Cancel is the default and no GUI means no; notifications only with --notify"

# Live: --confirm-gui with Cancel leaves the process alone (needs ps).
if ps -o lstart= -p $$ >/dev/null 2>&1; then
    ( bash -c 'echo $$ > "$1"; sleep 300 & wait' _ "$tmp/gui.pid" </dev/null >/dev/null 2>&1 & )
    for _ in 1 2 3 4 5 6 7 8 9 10; do [[ -s "$tmp/gui.pid" ]] && break; sleep 0.1; done
    root="$(cat "$tmp/gui.pid")"; sleep 0.2
    out="$(PATH="$tmp/osa:$PATH" OSA_ANSWER=Cancel AGENTS_SELF=$$ AGENTS_UID="$(id -u)" AGENTS_CONFIRM_GUI=true \
        AGENTS_YES=false AGENTS_DRY_RUN=false agents_kill_tokens true "$root" 2>&1)" && fail "kill went ahead after Cancel"
    kill -0 "$root" 2>/dev/null || fail "Cancel still killed the session"
    [[ "$out" == *cancelled* ]] || fail "Cancel not reported: $out"
    : > "$tmp/osa.log"
    out="$(PATH="$tmp/osa:$PATH" OSA_ANSWER=Kill AGENTS_SELF=$$ AGENTS_UID="$(id -u)" AGENTS_CONFIRM_GUI=true AGENTS_NOTIFY=true \
        AGENTS_YES=false AGENTS_DRY_RUN=false AGENTS_GRACE=3 agents_kill_tokens true "$root" 2>&1)" || fail "kill after Kill failed: $out"
    ! kill -0 "$root" 2>/dev/null || fail "Kill did not kill"
    grep -q "Killed bash (pid $root) and 1 child processes" "$tmp/osa.log" || fail "result notification: $(cat "$tmp/osa.log")"
    pass "live: Cancel in the dialog kills nothing; Kill kills and notifies"
else
    echo "SKIP: ps unavailable here (sandbox?): live dialog test not run"
fi

# The Herdr cache: fresh answers are reused; the menu (async) never waits.
cache_dir="$tmp/hrun"; mkdir -p "$cache_dir"
# shellcheck disable=SC2329  # replaces the real query, called by the cache
_agents_herdr_query() { echo "query" >> "$tmp/herdr.calls"; sleep 2; printf 'claude\tworking\t/p\n'; }
printf '%s\nclaude\tblocked\t/p\n' "$(date +%s)" > "$cache_dir/herdr.tsv"
[[ "$(AGENTS_RUN_DIR="$cache_dir" _agents_herdr_cached sync)" == $'claude\tblocked\t/p' && ! -e "$tmp/herdr.calls" ]] \
    || fail "a fresh cache was not reused"
printf '%s\nclaude\tblocked\t/p\n' "$(( $(date +%s) - 30 ))" > "$cache_dir/herdr.tsv"
t0=$SECONDS
got="$(AGENTS_RUN_DIR="$cache_dir" _agents_herdr_cached async)"
[[ $((SECONDS - t0)) -lt 2 ]] || fail "the async (menu) path waited for Herdr"
[[ "$got" == $'claude\tblocked\t/p' ]] || fail "async did not serve the recent cache"
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30; do
    grep -q working "$cache_dir/herdr.tsv" 2>/dev/null && break; sleep 0.2
done
grep -q working "$cache_dir/herdr.tsv" || fail "the background refresh did not update the cache"
unset -f _agents_herdr_query
pass "Herdr cache: reused for 10s; the menu path serves it and refreshes in the background"

# Probe parsers (one sysctl, memory_pressure, pmset -g batt), without forks.
cores="" level="" load=""
_agents_parse_sysctl <<<$'14\n2\n{ 9.61 8.20 7.05 }'
[[ "$cores/$level/$load" == "14/2/9.61" ]] || fail "sysctl parse: $cores/$level/$load"
[[ "$(_agents_parse_memfree <<<$'The system has 51539607552 (3145728 pages with a page size of 16384).\nSystem-wide memory free percentage: 66%')" == 66 ]] \
    || fail "memory_pressure parse"
[[ "$(_agents_parse_batt <<<$'Now drawing from \'AC Power\'\n -InternalBattery-0 (id=1)\t100%; charged; 0:00 remaining present: true')" == $'100\tcharged' ]] \
    || fail "pmset batt parse"
[[ "$(_agents_parse_batt <<<$' -InternalBattery-0 (id=1)\t85%; AC attached; not charging present: true')" == $'85\tAC attached' ]] || fail "pmset batt: AC attached"
[[ -z "$(_agents_parse_batt <<<$'Now drawing from \'AC Power\'')" ]] || fail "a Mac without a battery"
pass "system probes parse sysctl, memory_pressure and pmset batt in bash"

# Under a comma-decimal locale the probes still read numbers: every command
# whose output is parsed runs with LC_ALL=C. The stubs answer like a German
# Mac unless they see LC_ALL=C.
mkdir -p "$tmp/loc"
# shellcheck disable=SC2016  # the stubs expand their own variables
{
    printf '#!/bin/bash\nif [[ "$LC_ALL" == C ]]; then printf "14\\n1\\n{ 20.22 18.00 17.00 }\\n"; else printf "14\\n1\\n{ 20,22 18,00 17,00 }\\n"; fi\n' > "$tmp/loc/sysctl"
    printf '#!/bin/bash\necho "System-wide memory free percentage: 66%%"\n' > "$tmp/loc/memory_pressure"
    printf '#!/bin/bash\n[[ "$2" == batt ]] && printf " -InternalBattery-0 (id=1)\\t85%%%%; charging; 1:00 remaining present: true\\n"\nexit 0\n' > "$tmp/loc/pmset"
}
chmod +x "$tmp/loc/sysctl" "$tmp/loc/memory_pressure" "$tmp/loc/pmset"
loc_sys="$(PATH="$tmp/loc:$PATH" LC_ALL=de_DE.UTF-8 agents_system 2>/dev/null)"
[[ "$loc_sys" == $'20.22\t14\t66\tnormal\t85\tcharging' ]] || fail "system probe under de_DE: $(printf '%s' "$loc_sys" | tr '\t' '|')"
pass "under LC_ALL=de_DE.UTF-8 the load still reads 20.22 (probes run with LC_ALL=C)"

echo ""
echo "All agents tests passed."
