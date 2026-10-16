#!/bin/bash
# Unit tests for bin/agents (the monitoring pack's `agents` command).
# Run: bash scripts/lib/test_agents.sh  -> exit 0 on pass.
#
# Only the pure parsing and classification functions run, against fixture
# `ps` / listener text: nothing is signalled and no real process is read.

# Tests change PATH inside ( … ) on purpose, to stub tools for one call.
# shellcheck disable=SC2016,SC2030,SC2031  # literal $(…) and backticks in the notification tests
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/tuidev-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home" NO_COLOR=1
export TUIDEV_TERMINAL_NOTIFIER=""   # never this machine's: notifications go to the osascript stubs
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

# Herdr: each session is the agent in its own pane (HERDR_PANE_ID), so two in
# one directory get their own status and title; by directory only when the
# pair is unique; never the pane another session claimed.
hrec() { printf 'agent\t%s\t%s\t60\t1.0\t1.0\t1000\t0\tWed_Oct_14_07:31:08_2026\t-\tme\t-\t-\t%s\n' "$1" "$2" "$2"; }
hrecs="$(hrec 501 claude; hrec 502 claude; hrec 503 codex)"
hcwds=$'501\t/w/app\n502\t/w/app\n503\t/w/app'
hlist=$'claude\tworking\t/w/app\tw1:p1\tFix the login\nclaude\tdone\t/w/app\tw2:p1\tWrite \033[1mdocs\033[0m\ncodex\tidle\t/w/app\tw3:p1\tcodex'
henr() { printf '%s\n' "$hrecs" | agents_enrich "$hcwds" "$hlist" "" "$1"; }
hf() { printf '%s\n' "$2" | awk -F '\t' -v t="$1" -v p="$3" -v c="$4" '$1 == t && $2 == p { print $c }'; }
out="$(henr $'501\tw2:p1\n502\tw1:p1')"
[[ "$(hf agent "$out" 501 12)/$(hf agent "$out" 502 12)/$(hf agent "$out" 503 12)" == done/working/idle ]] \
    || fail "Herdr status by pane: $(printf '%s\n' "$out" | cut -f1-3,12)"
[[ "$(printf '%s\n' "$out" | grep '^herdr')" == $'herdr\t501\tw2:p1\tWrite [1mdocs[0m\nherdr\t502\tw1:p1\tFix the login\nherdr\t503\tw3:p1\t-' ]] \
    || fail "herdr records (pane, printable title, '-' for the agent's own name): $(printf '%s\n' "$out" | grep '^herdr' | cat -v)"
[[ "$(printf '%s\n' "$out" | awk -F '\t' '$1 == "agent" { printf "%s ", $2 }')" == "502 501 503 " ]] || fail "agent order after Herdr status: working first"
out="$(henr "")"
[[ "$(hf agent "$out" 501 12)/$(hf agent "$out" 502 12)/$(hf agent "$out" 503 12)" == -/-/idle ]] \
    || fail "two claude sessions in one directory and no panes: a guess: $(printf '%s\n' "$out" | cut -f1-3,12)"
[[ -z "$(printf '%s\n' "$out" | awk -F '\t' '$1 == "herdr" && $2 != 503')" ]] || fail "herdr records for unmatched sessions"
hrecs="$(hrec 501 claude)"
[[ "$(hf agent "$(henr "")" 501 12)" == - ]] || fail "one session, two Herdr agents in its directory: a guess"
[[ "$(hf agent "$(henr $'501\tw9:p9')" 501 12)" == - ]] || fail "a pane Herdr no longer lists fell back to the directory"
hrecs="$(hrec 501 claude; hrec 502 claude)"
hlist=$'claude\tworking\t/w/app\tw1:p1\tFix the login'
out="$(henr $'501\tw1:p1')"
[[ "$(hf agent "$out" 501 12)/$(hf agent "$out" 502 12)" == working/- ]] || fail "a pane claimed by one session went to another: $(printf '%s\n' "$out" | cut -f1-3,12)"
pass "Herdr: status and task title by the session's own pane; by directory only when unique and unclaimed"

# HERDR_PANE_ID from a process's environment (one ps -E, or /proc on Linux).
[[ "$(printf '%s\n' "  42 /usr/bin/claude --x HERDR_PANE_ID=fake HOME=/h HERDR_PANE_ID=w1R:p1 TERM=x" "43 claude" "44 node HERDR_PANE_ID=bad\$id" | _agents_pane_env_parse)" == $'42\tw1R:p1' ]] \
    || fail "pane id parse: $(printf '%s\n' "  42 claude HERDR_PANE_ID=w1R:p1" | _agents_pane_env_parse)"
# Asked only for the sessions running in Herdr, and only when Herdr lists agents.
hp_recs=$'agent\t501\tclaude\nwhere\t501\therdr\t-\nwhere\t502\ttmux\tw:1.0\nwhere\t503\therdr\tGhostty'
# shellcheck disable=SC2317,SC2329  # replaces the real lookup, called by _agents_herdr_panes
hp_ask() { ( _agents_pane_env() { echo "asked: $*"; }; _agents_herdr_panes "$@" ); }
[[ "$(hp_ask $'claude\tworking\t/w' "$hp_recs")" == "asked: 501 503" ]] || fail "_agents_herdr_panes asks about the wrong sessions"
[[ -z "$(hp_ask "" "$hp_recs")" ]] || fail "_agents_herdr_panes asked with no Herdr agents"
[[ -z "$(AGENTS_TESTING=1 _agents_pane_env $$)" ]] || fail "_agents_pane_env read this machine's processes under AGENTS_TESTING"
if ps -o pid= -p $$ >/dev/null 2>&1; then
    HERDR_PANE_ID=wT:p9 bash -c 'sleep 30; :' &
    hp=$!
    sleep 0.3
    got="$(_agents_pane_env "$hp" 1)"
    kill "$hp" 2>/dev/null; wait "$hp" 2>/dev/null || true
    [[ "$got" == "$hp"$'\t'"wT:p9" ]] || fail "pane id of a live process: '$got'"
    pass "HERDR_PANE_ID is read from a process's environment, for the processes asked about only"
else
    echo "SKIP: ps unavailable here (sandbox?): the live pane-id test not run"
fi

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
    [[ -z "$(_agents_start "$root")" ]] || fail "tree root still running"
    pass "kill: a tree that exits on SIGTERM returns at once, with no SIGKILL line"
    # A zombie (exited, unreaped: a container's init may reap late) is gone.
    if command -v perl >/dev/null 2>&1; then
        perl -e '$| = 1; my $c = fork; exit 0 unless $c; print "$c\n"; sleep 10' > "$tmp/zombie.pid" &
        zparent=$!
        for _ in 1 2 3 4 5 6 7 8 9 10; do [[ -s "$tmp/zombie.pid" ]] && break; sleep 0.1; done
        zpid="$(cat "$tmp/zombie.pid")"; sleep 0.3
        zstart="$(LC_ALL=C ps -o lstart= -p "$zpid" | awk 'NF >= 5 { print $1 "_" $2 "_" $3 "_" $4 "_" $5 }')"
        [[ -n "$zstart" ]] || fail "zombie fixture: ps does not list the unreaped child"
        _agents_zombie "$zpid" || fail "a zombie not recognized"
        ! _agents_zombie "$zparent" || fail "a live process taken for a zombie"
        [[ -z "$(_agents_start "$zpid")" ]] || fail "a zombie has a start time"
        [[ -z "$(_agents_alive "$zpid"$'\t'"$zstart"$'\t'"z")" ]] || fail "a zombie counted as alive"
        echo "$zpid $zstart" > "$tmp/zombie.lock"
        rc=0; _agents_holder_check "$tmp/zombie.lock" "$zpid $zstart" "$zpid" "$zstart" || rc=$?
        [[ $rc -eq 1 && ! -e "$tmp/zombie.lock" ]] || fail "a zombie lock holder not treated as gone (rc $rc)"
        kill "$zparent" 2>/dev/null; wait "$zparent" 2>/dev/null || true
        pass "a zombie counts as gone: no start time, not alive, its lock freed"
    fi
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
    [[ -z "$(_agents_start "$p1")" ]] || { kill "$p1"; fail "second awake on orphaned the first holder"; }
    [[ -n "$(_agents_start "$p2")" ]] || fail "second holder not running"
    [[ "$(awake off)" == *"stopped pid $p2"* ]] || fail "awake off"
    sleep 0.3
    [[ -z "$(_agents_start "$p2")" ]] || { kill "$p2"; fail "awake off left the holder running"; }
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
# shellcheck disable=SC2034,SC2317,SC2329  # both are read by the sourced agents_awake
( AGENTS_RUN_DIR="$tmp/lock-run"; agents_awake_on() { exit 3; }; agents_awake on ) && fail "early exit not propagated"
[[ ! -e "$tmp/lock-run/awake.lock" ]] || fail "the awake lock survived an early exit"
pass "keep-awake lock is released by its EXIT trap"

# Keep-awake with the lid closed. Nothing here runs as root: osascript, pmset,
# notifyutil and ps are stubs, the guard runs only with its absolute paths
# rewritten to the stubs, and lid()/sd() point agents at the stub osascript
# (AGENTS_OSASCRIPT, honored only under AGENTS_TESTING). agents runs osascript
# with an empty environment, so its stub is steered by files: osa.cancel and
# osa.fail make it fail like Cancel and like a failed root command, osa.pid
# is the guard pid it answers with. It records its argv, environment, and the
# command and prompt it was handed. The ps stub answers from PS_TABLE
# ("pid<TAB>lstart<TAB>ruid<TAB>args" lines).
lidbin="$tmp/lidbin"; mkdir -p "$lidbin"
# shellcheck disable=SC2016  # the stubs expand their own variables
{
    printf '#!/bin/bash\nd=%q\ncase "$4" in *"display notification"*) printf "%%s\\n" "$7" >> "$d/notify.log"; exit 0 ;; esac\nprintf "%%s" "$7" > "$d/lid.cmd"; printf "%%s" "$8" > "$d/lid.prompt"\nprintf "%%s\\n" "$0" "$@" > "$d/osa.argv"; /usr/bin/env > "$d/osa.env"\n[[ ! -e "$d/osa.cancel" ]] || { echo "execution error: User canceled. (-128)" >&2; exit 1; }\n[[ ! -e "$d/osa.fail" ]] || { echo "execution error: pmset: failed (1)" >&2; exit 1; }\n[[ ! -e "$d/osa.nostart" ]] || { echo "execution error: agents-lid: the guard did not start; sleep restored (1)" >&2; exit 1; }\ncase "$7" in *"disablesleep 1"*) cat "$d/osa.pid" ;; esac\nexit 0\n' "$tmp" > "$lidbin/osascript"
    printf '#!/bin/bash\ncase "$*" in\n  -g) echo "System-wide power settings:"; [[ "$PMSET_SD" == 1 ]] && printf " SleepDisabled\\t\\t1\\n"; echo "Currently in use:"; echo " powermode            0" ;;\n  "-g batt") printf "%%b\\n" "$PMSET_BATT" ;;\n  -a\\ *) echo "$*" >> "$PMSET_LOG" ;;\nesac\nexit 0\n' > "$lidbin/pmset"
    printf '#!/bin/bash\necho "com.apple.system.thermalpressurelevel ${THERMAL:-0}"\n' > "$lidbin/notifyutil"
    printf '#!/bin/bash\nfields="" pid=""\nwhile [[ $# -gt 0 ]]; do case "$1" in -o) fields="$2"; shift 2 ;; -p) pid="$2"; shift 2 ;; *) shift ;; esac; done\n[[ -n "$pid" && -r "$PS_TABLE" ]] || exit 1\nwhile IFS=$'"'"'\\t'"'"' read -r p lst ru args; do\n    [[ "$p" == "$pid" ]] || continue\n    out=""; IFS=, read -r -a fs <<<"$fields"\n    for f in "${fs[@]}"; do case "$f" in pid=) v="$p" ;; lstart=) v="$lst" ;; ruid=|uid=) v="$ru" ;; args=) v="$args" ;; *) v="" ;; esac; out+="${out:+ }$v"; done\n    echo "$out"; exit 0\ndone < "$PS_TABLE"\nexit 1\n' > "$lidbin/ps"
}
# A caffeinate on PATH so the Linux container gets past the inhibitor probe.
printf '#!/bin/bash\nexit 0\n' > "$lidbin/caffeinate"
chmod +x "$lidbin/osascript" "$lidbin/pmset" "$lidbin/notifyutil" "$lidbin/ps" "$lidbin/caffeinate"
export LID_LOG="$tmp/lid" PMSET_LOG="$tmp/pmset.log" PMSET_SD=0 PMSET_BATT="" THERMAL=0 PS_TABLE="$tmp/ps.table"
# This shell's own row: ps works, so a pid it doesn't list is gone.
self_row() { printf '%s\tWed Oct 14 08:00:00 2026\t501\tbash test\n' "$$" >> "$PS_TABLE"; }
: > "$PS_TABLE"; self_row
guard_row() { printf '%s\tWed Oct 14 09:00:00 2026\t0\t/bin/bash -c restore agents-lid-guard 3600 20\n' "$1" >> "$PS_TABLE"; }

# The root command: fixed text around checked numbers only, every command an
# absolute path (no echo, [ or exit an inherited function could replace).
guard_q="'$_AGENTS_LID_GUARD'"
[[ "$_AGENTS_LID_GUARD" != *"'"* ]] || fail "the guard body holds a single quote"
# shellcheck disable=SC2016  # the literal root command, expanded by root's sh
start_cmd() {
    printf '%s' "if /usr/bin/pmset -a disablesleep 1; then /usr/bin/perl -MPOSIX -e 'POSIX::setsid() >= 0 or die \"setsid: \$!\"; exec @ARGV; die \"exec: \$!\"' /usr/bin/env -i /bin/bash -c $guard_q agents-lid-guard $1 $2 </dev/null >/dev/null 2>&1 & g=\$!; /bin/sleep 2; if /bin/test \"\$(/bin/ps -o ruid= -p \$g 2>/dev/null)\" -eq 0 2>/dev/null && /bin/ps -ww -o args= -p \$g 2>/dev/null | /usr/bin/grep -q \" agents-lid-guard \"; then /bin/echo \$g; else /usr/bin/pmset -a disablesleep 0; /bin/echo \"agents-lid: the guard did not start; sleep restored\" >&2; /usr/bin/false; fi; else /bin/echo \"agents-lid: pmset failed; nothing changed\" >&2; /usr/bin/false; fi"
}
[[ "$(_agents_lid_cmd start 10800 20)" == "$(start_cmd 10800 20)" ]] || fail "lid start command: $(_agents_lid_cmd start 10800 20)"
# shellcheck disable=SC2016  # the literal root command, expanded by root's sh
retire='if /bin/test "$(/bin/ps -o ruid= -p 777 2>/dev/null)" -eq 0 2>/dev/null && /bin/ps -ww -o args= -p 777 2>/dev/null | /usr/bin/grep -q " agents-lid-guard "; then /bin/kill -USR1 777; fi'
[[ "$(_agents_lid_cmd start 60 5 777)" == "$retire; $(start_cmd 60 5)" ]] || fail "lid start command replacing a guard: $(_agents_lid_cmd start 60 5 777)"
[[ "$(_agents_lid_cmd stop)" == "/usr/bin/pmset -a disablesleep 0" ]] || fail "lid stop command"
[[ "$(_agents_lid_cmd stop 777)" == "/usr/bin/pmset -a disablesleep 0; $retire" ]] || fail "lid stop command with a guard: $(_agents_lid_cmd stop 777)"
for c in "$(_agents_lid_cmd start 60 5 777)" "$(_agents_lid_cmd stop 777)"; do
    sh -n -c "$c" || fail "the root command does not parse: $c"
    o="${c/"$guard_q"/GUARD}"   # the guard runs in a fresh env -i bash
    [[ "$o" != *" echo "* && "$o" != *" [ "* && "$o" != *"exit"* ]] || fail "the root command relies on a shell builtin: $o"
done
bad_lid_cmd() { ! _agents_lid_cmd "$@" >/dev/null || fail "lid command built from bad input: $*"; }
bad_lid_cmd start '10;id' 20
bad_lid_cmd start 60 '20;id'
bad_lid_cmd start 0 20
bad_lid_cmd start 60 101
bad_lid_cmd start 60 '2 0'
bad_lid_cmd start 60 20 7x
bad_lid_cmd stop '1;id'
bad_lid_cmd stop -1
bad_lid_cmd go 60 20
pass "lid: the root command is fixed text around checked numbers, with absolute paths only"

# The root step's own fail-safe: a guard that is gone two seconds later means
# sleep is turned back on in the same command, which then fails. Run as
# yourself with the pmset writes logged (and the uid check made yours).
sub_all() {   # TEXT FROM TO — every FROM replaced (variables: the same in bash 3.2)
    local t="$1" from="$2" to="$3"
    printf '%s' "${t//"$from"/$to}"
}
lid_test_cmd() {   # LOG CMD — the root command, made harmless and runnable as you
    local c="$2"
    c="$(sub_all "$c" "/usr/bin/pmset -a disablesleep 1" "/usr/bin/true")"
    c="$(sub_all "$c" "/usr/bin/pmset -a disablesleep 0" "/bin/echo restored >> $1")"
    c="$(sub_all "$c" "-eq 0 2>/dev/null" "-eq $(id -u) 2>/dev/null")"
    c="$(sub_all "$c" "/bin/sleep 60" "/bin/sleep 1")"
    [[ "$c" != *"pmset -a"* ]] || fail "a pmset write is left in the test command"
    printf '%s' "$c"
}
# The command uses macOS's absolute paths (/usr/bin/true, /usr/bin/false), so
# these live runs are macOS-only.
if [[ "$(uname -s)" == Darwin && -x /usr/bin/perl ]]; then
    : > "$tmp/nostart.log"
    c="$(lid_test_cmd "$tmp/nostart.log" "$(_agents_lid_cmd start 600 20)")"
    c="$(sub_all "$c" "'end=" "'exit 3; end=")"; c="$(sub_all "$c" "/bin/sleep 2" "/bin/sleep 0.3")"
    rc=0; /bin/sh -c "$c" >"$tmp/nostart.out" 2>"$tmp/nostart.err" || rc=$?
    [[ $rc -ne 0 && ! -s "$tmp/nostart.out" && "$(cat "$tmp/nostart.err")" == "$_AGENTS_LID_NOSTART" && "$(cat "$tmp/nostart.log")" == restored ]] \
        || fail "fail-safe: rc $rc, out '$(cat "$tmp/nostart.out")', err '$(cat "$tmp/nostart.err")', log '$(cat "$tmp/nostart.log")'"
    pass "lid: when the guard is gone after two seconds, the root step restores sleep itself and fails"
else
    echo "SKIP: not macOS: lid fail-safe test not run"
fi

# The real detach: the guard starts in a session of its own, so killing the
# group that launched it (what ending a privileged dialog can do) leaves it
# running. Needs perl and a usable ps (not in a sandbox).
if [[ "$(uname -s)" == Darwin && -x /usr/bin/perl ]] && /bin/ps -o pid= -p $$ >/dev/null 2>&1; then
    : > "$tmp/detach.log"
    c="$(lid_test_cmd "$tmp/detach.log" "$(_agents_lid_cmd start 600 20)")"
    ( set -m; /bin/sh -c "$c" >"$tmp/detach.out" 2>"$tmp/detach.err" & l=$!; wait "$l"; echo "$l" > "$tmp/detach.leader" )
    g="$(cat "$tmp/detach.out")"
    [[ "$g" =~ ^[0-9]+$ ]] || fail "detach: the launch reported no guard: $(cat "$tmp/detach.err")"
    kill -KILL -- "-$(cat "$tmp/detach.leader")" 2>/dev/null || true
    sleep 0.5
    kill -0 "$g" 2>/dev/null || fail "detach: the guard died with the group that launched it"
    [[ "$(/bin/ps -o pgid= -p "$g" | tr -d ' ')" == "$g" ]] || fail "detach: the guard does not lead its own group"
    /bin/ps -ww -o args= -p "$g" | grep -q " agents-lid-guard 600 20" || fail "detach: the guard is not named agents-lid-guard"
    kill -TERM "$g"; sleep 1
    [[ "$(cat "$tmp/detach.log")" == restored ]] || fail "detach: SIGTERM did not restore: $(cat "$tmp/detach.log")"
    pass "lid: the guard runs in its own session, survives its launcher's group being killed, restores on SIGTERM"
else
    echo "SKIP: no perl or ps here (sandbox?): live lid detach test not run"
fi

# The guard itself: valid, shellcheck-clean bash; restores on low battery off
# AC, on heavy thermal pressure (not moderate) and when the time is up;
# SIGUSR1 retires it quietly.
printf '%s\n' "$_AGENTS_LID_GUARD" > "$tmp/guard.sh"
bash -n "$tmp/guard.sh" || fail "guard body does not parse"
if command -v shellcheck >/dev/null 2>&1; then
    shellcheck -s bash -e SC2148 "$tmp/guard.sh" || fail "guard body is not shellcheck-clean"
fi
guard_test="$(printf '%s\n' "$_AGENTS_LID_GUARD" | sed -e "s#/usr/bin/pmset#$lidbin/pmset#g" -e "s#/usr/bin/notifyutil#$lidbin/notifyutil#g" -e 's#/bin/sleep 60#/bin/sleep 0.2#')"
[[ "$guard_test" != */usr/bin/pmset* && "$guard_test" != */usr/bin/notifyutil* ]] || fail "guard under test could reach the real pmset"
guard() { : > "$PMSET_LOG"; bash -c "$guard_test" agents-lid-guard "$@"; cat "$PMSET_LOG"; }
[[ "$(PMSET_BATT=$'Now drawing from \'Battery Power\'\n -InternalBattery-0 (id=1)\t15%; discharging; 1:00 remaining present: true' guard 600 20)" == "-a disablesleep 0" ]] \
    || fail "guard: low battery off AC does not restore"
[[ "$(PMSET_BATT=$'Now drawing from \'AC Power\'\n -InternalBattery-0 (id=1)\t15%; charging; present: true' THERMAL=2 guard 600 20)" == "-a disablesleep 0" ]] \
    || fail "guard: heat does not restore"
[[ "$(PMSET_BATT=$'Now drawing from \'AC Power\'\n -InternalBattery-0 (id=1)\t15%; charging; present: true' guard 1 20)" == "-a disablesleep 0" ]] \
    || fail "guard: the end of the duration does not restore"
: > "$PMSET_LOG"
( PMSET_BATT="Now drawing from 'AC Power'" bash -c "$guard_test" agents-lid-guard 600 20 ) & gp=$!
sleep 0.5; kill -USR1 "$gp"; wait "$gp" 2>/dev/null || true
[[ ! -s "$PMSET_LOG" ]] || fail "guard: SIGUSR1 (a replacement guard) restored sleep"
: > "$PMSET_LOG"
( PMSET_BATT="Now drawing from 'AC Power'" THERMAL=1 bash -c "$guard_test" agents-lid-guard 600 20 ) & gp=$!
sleep 0.5; kill -USR1 "$gp"; wait "$gp" 2>/dev/null || true
[[ ! -s "$PMSET_LOG" ]] || fail "guard: moderate thermal pressure restored sleep"
( PMSET_BATT="Now drawing from 'AC Power'" bash -c "$guard_test" agents-lid-guard 600 20 ) & gp=$!
sleep 0.5; kill -TERM "$gp"; wait "$gp" 2>/dev/null || true
[[ "$(cat "$PMSET_LOG")" == "-a disablesleep 0" ]] || fail "guard: SIGTERM does not restore"
pass "lid guard: bash -n and shellcheck clean; restores on low battery, heavy (not moderate) heat, timeout and SIGTERM; SIGUSR1 retires it"

# The command: a required, capped duration; one dialog; state recorded.
lid() {   # ARGS... — agents awake, with the stubs, in its own run dir
    ( PATH="$lidbin:$PATH" AGENTS_RUN_DIR="$tmp/lidrun" AGENTS_TESTING=1 AGENTS_OSASCRIPT="$lidbin/osascript"
      # shellcheck disable=SC2317,SC2329  # no real caffeinate holder
      _agents_hold() { :; }
      agents_awake "$@" )
}
[[ "$(AGENTS_TESTING=1 AGENTS_OSASCRIPT="$lidbin/osascript" _agents_osascript)" == "$lidbin/osascript" ]] || fail "test osascript override"
[[ "$(AGENTS_OSASCRIPT="$lidbin/osascript" _agents_osascript)" == /usr/bin/osascript ]] || fail "AGENTS_OSASCRIPT honored outside tests"
for bad in "" 2x 0m 9h; do
    rc=0; out="$(lid lid $bad 2>&1)" || rc=$?
    [[ $rc -eq 2 && ! -e "$LID_LOG.cmd" ]] || fail "awake lid '$bad' not refused before any dialog (rc $rc): $out"
done
[[ "$(lid lid 9h 2>&1)" == *"longer than AGENTS_LID_MAX (8h)"* ]] || fail "the cap is not explained"
rc=0; AGENTS_LID_MIN_BATTERY=abc lid lid 1h >/dev/null 2>&1 || rc=$?
[[ $rc -eq 2 && ! -e "$LID_LOG.cmd" ]] || fail "a bad battery floor from the environment reached the root command"
# shellcheck disable=SC2123  # an empty PATH is the point: no pmset
out="$( (PATH="$tmp/empty"; agents_awake_lid 1h) 2>&1)" && fail "awake lid ran without pmset"
[[ "$out" == *"macOS only"* ]] || fail "unsupported platform message: $out"
sleep 60 & fake_guard=$!
guard_row "$fake_guard"; printf '%s\n' "$fake_guard" > "$tmp/osa.pid"
# Cancel runs nothing; any other failure says it may have run partly.
touch "$tmp/osa.cancel"
rc=0; out="$(lid lid 1h 2>&1)" || rc=$?
rm -f "$tmp/osa.cancel"
[[ $rc -eq 1 && "$out" == *"cancelled in the password dialog"*"nothing ran as root"* && ! -e "$tmp/lidrun/lid" && ! -e "$tmp/lidrun/awake" ]] \
    || fail "a cancelled dialog: $out"
touch "$tmp/osa.fail"
rc=0; out="$(lid lid 1h 2>&1)" || rc=$?
rm -f "$tmp/osa.fail"
[[ $rc -eq 1 && "$out" == *"pmset: failed (1)"*"may have run"*"agents awake restore"* && "$out" != *"nothing changed"* ]] \
    || fail "a failed root step: $out"
touch "$tmp/osa.nostart"
rc=0; out="$(AGENTS_NOTIFY=true lid lid 1h 2>&1)" || rc=$?
rm -f "$tmp/osa.nostart"
[[ $rc -eq 1 && "$out" == *"lid mode failed to start: its guard did not start; sleep restored"* && ! -e "$tmp/lidrun/lid" ]] \
    || fail "the root step's fail-safe: $out"
grep -q "Lid mode failed to start (no guard); sleep restored" "$tmp/notify.log" || fail "no notification for a failed start: $(cat "$tmp/notify.log" 2>/dev/null)"
# A guard that dies as the dialog ends: lid sleep is restored at once (one more
# dialog), and the record never stays.
sleep 60 & doomed=$!
printf '%s\n' "$doomed" > "$tmp/osa.pid"
rm -f "$LID_LOG.cmd"
rc=0; out="$(lid lid 1h 2>&1)" || rc=$?
[[ $rc -eq 1 && "$out" == *"stopped when the dialog ended"*"lid mode failed to start; sleep restored"* ]] || fail "a guard that died on return: $out"
[[ "$(cat "$LID_LOG.cmd")" == "/usr/bin/pmset -a disablesleep 0" && ! -e "$tmp/lidrun/lid" ]] || fail "a dead guard left lid mode on: $(cat "$LID_LOG.cmd")"
kill "$doomed" 2>/dev/null; wait "$doomed" 2>/dev/null || true
printf '%s\n' "$fake_guard" > "$tmp/osa.pid"
: > "$tmp/notify.log"
out="$(AGENTS_NOTIFY=true AGENTS_LID_MAX=10h lid lid 9h)" || fail "awake lid 9h under AGENTS_LID_MAX=10h: $out"
grep -q "Awake with the lid closed until" "$tmp/notify.log" || fail "no notification for lid mode on"
[[ "$(cat "$LID_LOG.cmd")" == "$(_agents_lid_cmd start 32400 20)" ]] || fail "the dialog ran something else: $(cat "$LID_LOG.cmd")"
[[ "$(cat "$LID_LOG.prompt")" == *"lid closed for 9h"*"below 20% battery"* ]] || fail "dialog prompt: $(cat "$LID_LOG.prompt")"
# Exactly: /usr/bin/env -i <osascript> -e … -e … -e … COMMAND PROMPT, nothing inherited.
want_argv="$(printf '%s\n' "$lidbin/osascript" -e 'on run argv' -e 'do shell script (item 1 of argv) with prompt (item 2 of argv) with administrator privileges' -e 'end run' "$(cat "$LID_LOG.cmd")" "$(cat "$LID_LOG.prompt")")"
[[ "$(cat "$tmp/osa.argv")" == "$want_argv" ]] || fail "osascript invocation: $(cat "$tmp/osa.argv")"
! grep -qvE '^(PWD|OLDPWD|SHLVL|_)=' "$tmp/osa.env" || fail "osascript inherited an environment: $(cat "$tmp/osa.env")"
[[ "$(cut -d' ' -f1 "$tmp/lidrun/lid")" == "$fake_guard" && "$(cut -d' ' -f3 "$tmp/lidrun/awake")" == lid ]] || fail "lid state not recorded"
[[ "$out" == "awake: on with the lid closed until "*"(guard pid $fake_guard)"* ]] || fail "awake lid output: $out"
[[ "$(PATH="$lidbin:$PATH" AGENTS_RUN_DIR="$tmp/lidrun" agents_awake_line)" == "awake: lid closed"*", until "*"(guard pid $fake_guard)" ]] || fail "awake line in lid mode"
# awake on (and awake agents) replace only the caffeinate holder: no dialog,
# and lid mode keeps running.
rm -f "$LID_LOG.cmd"
lid on 1h >/dev/null || fail "awake on during lid mode failed"
[[ ! -e "$LID_LOG.cmd" && -e "$tmp/lidrun/lid" ]] || fail "awake on during lid mode touched lid mode"
[[ "$(PATH="$lidbin:$PATH" AGENTS_RUN_DIR="$tmp/lidrun" agents_lid_state)" == "$fake_guard "*" 1" ]] || fail "lid mode not live after awake on"
# A second lid replaces the guard (retired by SIGUSR1 in the same dialog).
lid lid 1h >/dev/null || fail "a second awake lid failed"
[[ "$(cat "$LID_LOG.cmd")" == "$(_agents_lid_cmd start 3600 20 "$fake_guard")" ]] || fail "replacing a guard: $(cat "$LID_LOG.cmd")"
# off ends lid mode in one more dialog: restore, then retire the guard.
rm -f "$LID_LOG.cmd"
out="$(lid off 2>&1)"
[[ "$(cat "$LID_LOG.cmd" 2>/dev/null)" == "$(_agents_lid_cmd stop "$fake_guard")" ]] || fail "awake off did not restore lid sleep: $(cat "$LID_LOG.cmd" 2>/dev/null)"
[[ "$out" == *"lid sleep restored"* && ! -e "$tmp/lidrun/lid" ]] || fail "awake off output/state: $out"
rm -f "$LID_LOG.cmd"
out="$(lid off 2>&1)"
[[ ! -e "$LID_LOG.cmd" ]] || fail "awake off asked for a password with lid mode off"
kill "$fake_guard" 2>/dev/null; wait "$fake_guard" 2>/dev/null || true
pass "awake lid: capped duration, one env -i osascript running exactly the built command; on keeps lid mode; off restores"

# Sleep disabled with nothing to restore it: after a reboot killed the guard.
# shellcheck disable=SC2034  # read by the sourced functions in the subshell
sd() { ( PATH="$lidbin:$PATH" AGENTS_RUN_DIR="$tmp/sdrun" AGENTS_TESTING=1 AGENTS_OSASCRIPT="$lidbin/osascript"
         rm -f "$AGENTS_RUN_DIR/powermode"; "$@" ); }
mkdir -p "$tmp/sdrun"
[[ "$(PMSET_SD=1 sd _agents_powermode_probe)" == "automatic 1" && "$(PMSET_SD=0 sd _agents_powermode_probe)" == "automatic 0" ]] \
    || fail "pmset -g SleepDisabled parse: $(PMSET_SD=1 sd _agents_powermode_probe)"
PMSET_SD=1 sd agents_lid_stale || fail "SleepDisabled 1 without a guard not stale"
[[ "$(PMSET_SD=1 sd _agents_lid_warning)" == *"lid sleep is disabled and nothing will restore it. Fix: agents awake restore"* ]] || fail "stale warning text"
! PMSET_SD=0 sd agents_lid_stale || fail "sleep enabled reported stale"
# A record without a start time: live only while ps shows root's agents-lid-guard.
sleep 60 & live_guard=$!
printf '%s - %s\n' "$live_guard" "$(( $(date +%s) + 600 ))" > "$tmp/sdrun/lid"
: > "$PS_TABLE"   # ps answers nothing at all
! PMSET_SD=1 sd agents_lid_state >/dev/null || fail "a guard ps can't see counted as live"
[[ -e "$tmp/sdrun/lid" ]] || fail "a record dropped when ps answered nothing"
self_row; guard_row "$live_guard"
[[ "$(PMSET_SD=1 sd agents_lid_state)" == "$live_guard "*" 1" ]] || fail "root's agents-lid-guard without a start time not live"
! PMSET_SD=1 sd agents_lid_stale || fail "a live guard reported stale"
: > "$PS_TABLE"; self_row; printf '%s\tWed Oct 14 09:00:00 2026\t501\tsleep 60\n' "$live_guard" >> "$PS_TABLE"
! PMSET_SD=1 sd agents_lid_state >/dev/null || fail "a pid that names another process counted as the guard"
[[ ! -e "$tmp/sdrun/lid" ]] || fail "the record of a reused pid was kept"
printf '%s - %s\n' "$live_guard" "$(( $(date +%s) + 600 ))" > "$tmp/sdrun/lid"
kill "$live_guard"; wait "$live_guard" 2>/dev/null || true
PMSET_SD=1 sd agents_lid_stale || fail "a dead guard's record still counts"
[[ ! -e "$tmp/sdrun/lid" ]] || fail "a dead guard's record was kept"
[[ "$(PMSET_SD=1 sd _agents_lid_json)" == '{"active":false,"sleep_disabled":true,"stale":true}' ]] || fail "lid json: $(PMSET_SD=1 sd _agents_lid_json)"
rm -f "$LID_LOG.cmd"
PMSET_SD=1 sd agents_awake restore >/dev/null || fail "awake restore"
[[ "$(cat "$LID_LOG.cmd")" == "/usr/bin/pmset -a disablesleep 0" ]] || fail "awake restore ran: $(cat "$LID_LOG.cmd")"
# awake off restores too when sleep is disabled with no guard and no record.
rm -f "$LID_LOG.cmd" "$tmp/sdrun/lid"
PMSET_SD=1 sd agents_awake off >/dev/null || fail "awake off with stale lid sleep"
[[ "$(cat "$LID_LOG.cmd" 2>/dev/null)" == "/usr/bin/pmset -a disablesleep 0" ]] || fail "awake off left stale lid sleep alone"
rm -f "$LID_LOG.cmd"
PMSET_SD=0 sd agents_awake off >/dev/null || fail "awake off with sleep enabled failed"
[[ ! -e "$LID_LOG.cmd" ]] || fail "awake off asked for a password with sleep enabled"
# Status: a lid holder whose guard is gone while sleep stays disabled is a
# failure, not "lid mode ended".
sleep 60 & holder=$!
printf '%s\tWed Oct 14 09:30:00 2026\t501\tsleep 60\n' "$holder" >> "$PS_TABLE"
printf '%s Wed_Oct_14_09:30:00_2026 lid %s\n' "$holder" "$(( $(date +%s) + 600 ))" > "$tmp/sdrun/awake"
[[ "$(PMSET_SD=1 sd agents_awake_line)" == *"lid sleep is disabled and nothing will restore it"* ]] || fail "status for a dead guard: $(PMSET_SD=1 sd agents_awake_line)"
[[ "$(PMSET_SD=0 sd agents_awake_line)" == *"lid mode ended, a closed lid sleeps again"* ]] || fail "status after lid mode ended: $(PMSET_SD=0 sd agents_awake_line)"
kill "$holder" 2>/dev/null; wait "$holder" 2>/dev/null || true; rm -f "$tmp/sdrun/awake"
pass "stale SleepDisabled is detected and named a failure; awake off and awake restore turn lid sleep back on"

# Root is refused; AGENTS_SELF is a test-only override.
out="$(AGENTS_TESTING=1 AGENTS_EUID=0 bash "$REPO_DIR/bin/agents" kill -n 123 2>&1)" && fail "kill ran as root"
[[ "$out" == *"refusing to kill as root"* ]] || fail "root refusal message: $out"
# shellcheck disable=SC2016  # $$ and $1 belong to the inner bash
AGENTS_SELF=123 bash -c '. "$1"; [[ "$AGENTS_SELF" == "$$" ]]' _ "$REPO_DIR/bin/agents" || fail "AGENTS_SELF honored outside tests"
# shellcheck disable=SC2016
AGENTS_TESTING=1 AGENTS_SELF=123 bash -c '. "$1"; [[ "$AGENTS_SELF" == 123 ]]' _ "$REPO_DIR/bin/agents" || fail "AGENTS_SELF ignored in tests"
# The clock: AGENTS_NOW only under AGENTS_TESTING; _AGENTS_CLOCK never from the environment.
# shellcheck disable=SC2016  # expanded by the inner bash
clk() { env "$@" bash -c '. "$1"; _agents_now n; printf "%s\n" "$n"' _ "$REPO_DIR/bin/agents"; }
[[ "$(clk -u AGENTS_TESTING AGENTS_NOW=1000)" =~ ^[0-9]{10}$ ]] || fail "AGENTS_NOW honored without AGENTS_TESTING"
[[ "$(clk -u AGENTS_TESTING _AGENTS_CLOCK=1000)" != 1000 && "$(clk AGENTS_TESTING=1 _AGENTS_CLOCK=1000)" != 1000 ]] \
    || fail "_AGENTS_CLOCK taken from the environment"
[[ "$(clk AGENTS_TESTING=1 AGENTS_NOW=1000)" == 1000 ]] || fail "AGENTS_NOW ignored in tests"
pass "destructive commands refuse root; AGENTS_SELF/AGENTS_UID/AGENTS_NOW only under AGENTS_TESTING"

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
# Control characters (ESC, BEL, a tab, ^A) never reach a project or origin name.
c=$'/Users/NAME/code/ev\033[2Jil\007' w=$'/Users/NAME/re\033po/.claude/worktrees/agent-\tab1'
[[ "$(agents_project "$c")" == "ev[2Jil" && "$(agents_project "$w")" == repo/agent-ab1 && "$(agents_project $'/x/\033')" == - ]] \
    || fail "control characters in project names: $(agents_project "$c" | od -c | head -2)"
got="$(printf 'agent\t1\tclaude\t0\t0\t0\t0\t0\ts\t-\tme\t-\t%s\targs\n' "$c" | agents_enrich "" "" | cut -f15)"
[[ "$got" == "ev[2Jil" ]] || fail "control characters in enrich's project name: $(printf '%s' "$got" | od -c | head -2)"
got="$(printf 'act\t5\ttool\t1\t0\t0\t0\t0\ts\t-\t1\t-\t%s/x\tmake\n' "${w//$'\t'/$'\001'}" | agents_enrich "" "" | cut -f15)"
[[ "$got" == agent-ab1 ]] || fail "control characters in an origin: $(printf '%s' "$got" | od -c | head -2)"
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
    [[ "$json" == '{"schema_version":1,"agents":['* ]] || fail "json shape: ${json:0:80}"
    pass "agents json shape (jq not installed: not validated)"
fi
[[ "$(printf 'agent\t1\tclaude\t0\t0\t0\t0\t0\ts\t-\tme\t-\t-\ta "q" \\x\n' | agents_json | sed 's/.*\("command":".*"\),"activity".*/\1/')" == '"command":"a \"q\" \\x"' ]] \
    || fail "json escaping of quotes and backslashes"
pass "json escapes quotes and backslashes"

# Terminal width: a number, 120 without a terminal (never tput's blind 80).
[[ "$(_agents_term_cols)" =~ ^[1-9][0-9]*$ ]] || fail "terminal width: $(_agents_term_cols)"
if ! (: </dev/tty) 2>/dev/null; then
    [[ "$(_agents_term_cols)" == 120 ]] || fail "no terminal: width $(_agents_term_cols), not 120"
fi
pass "terminal width is read from the tty"

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
    '/Users/NAME/a\" bash=/bin/sh param1=-c param2=open${IFS}-a${IFS}Calculator z=\"/w'
    '/Users/NAME/pipe | bash=/bin/sh param1=-c param2=id'
    '/Users/NAME/trailing\'
    '/Users/NAME/new\nline" param1=x'
)
for h in "${hostile[@]}"; do
    rec=$'agent\t90419\tclaude\t60\t1.0\t1.0\t1000\t0\tWed_Oct_14_07:31:08_2026\t-\tme\t'"blocked\" bash=/bin/sh"$'\t'"$h"$'\tclaude --continue\t'"x\" param1=y"
    hmenu="$(plugin "$rec"$'\n'"herdr"$'\t'"90419"$'\t'"w1:p1"$'\t'"-- $h | color=red" "")"
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
                grep -qE "^        $sub\)" "$REPO_DIR/lib/agents/cli.sh" || fail "menu calls unknown agents subcommand '$sub'"
                case "$sub" in
                    kill|term)
                        [[ $# -ge 1 ]] || fail "$sub without arguments"
                        for a in "$@"; do
                            [[ "$a" =~ ^(-y|--notify|--confirm-gui)$ || "$a" =~ ^[0-9]+@[A-Za-z0-9_:]+$ ]] || fail "$sub: bad argument '$a'"
                        done ;;
                    awake)
                        local aw=() x
                        for x in "$@"; do [[ "$x" == --notify ]] || aw+=("$x"); done
                        set -- ${aw[@]+"${aw[@]}"}
                        [[ "${1:-}" =~ ^(on|off|agents|lid|restore)$ ]] || fail "awake: bad mode '${1:-}'"
                        [[ "${1:-}" != lid || $# -eq 2 ]] || fail "awake lid without a duration"
                        [[ $# -lt 2 ]] || agents_parse_duration "$2" >/dev/null || fail "awake $1: bad duration '$2'" ;;
                    open-term)
                        [[ "${1:-}" != --hold ]] || shift
                        [[ "$*" == watch || "$*" == "awake status" || "$*" =~ ^(show\ --watch|peek)\ [0-9]+@[A-Za-z0-9_:]+( 60)?$ ]] \
                            || fail "open-term: unexpected command '$*'" ;;
                    jump)
                        [[ $# -eq 2 && "$1" == --notify && "$2" =~ ^[0-9]+@[A-Za-z0-9_:]+$ ]] || fail "jump: expects --notify PID@START, got '$*'" ;;
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

# Finished sessions (Herdr's done, not yet looked at) and Herdr's health:
# calm items in Needs you, after the blocked ones, counted in its header,
# never tinting the icon; Herdr's task title names the session.
done_recs="$(printf '%s\n' "$records" | agents_enrich "$(printf '84091\t%s/code/shop\n90419\t%s/work/app\n' "$HOME" "$HOME")" \
    "$(printf 'claude\tdone\t%s/work/app\tw1:p1\tHerdr fleet smart notifications\nclaude\tblocked\t%s/code/shop\tw2:p1\t-\n' "$HOME" "$HOME")" \
    "" $'90419\tw1:p1\n84091\tw2:p1' | awk -F '\t' '$1 == "agent" || $1 == "herdr"')"
menu="$(plugin "$done_recs" $'awake\toff\t-\t0\nthermal\t0\tnominal')"
[[ "$(printf '%s\n' "$menu" | head -1)" == ":terminal: 2 · 1 blocked · 1 done | sfcolor=#FF9F0A" ]] || fail "title with done: $(printf '%s\n' "$menu" | head -1)"
[[ "$menu" == *$'\n'"Needs you (2) | size=12"$'\n'"shop · claude · waiting for you | "* ]] || fail "Needs you header counts the done session; blocked first"
[[ "$menu" == *$'\n'"Herdr fleet smart notifications · claude · finished, to review | sfimage=checkmark.circle.fill sfconfig=eyJyZW5kZXJpbmdNb2RlIjoiUGFsZXR0ZSIsImNvbG9ycyI6WyIjMEE4NEZGIl19 bash="*" param1=reveal param2=90419@Wed_Oct_14_07:31:08_2026 symbolize=false"$'\n'"--Jump to session | "* ]] \
    || fail "done item: $(printf '%s\n' "$menu" | grep 'finished, to review')"
[[ "$menu" == *$'\n'"Herdr fleet smart notifications · app · claude · done · 102.4% · "* ]] || fail "session row led by Herdr's title: $(printf '%s\n' "$menu" | grep '· done ·')"
[[ $(line_no '· waiting for you') -lt $(line_no 'finished, to review') ]] || fail "done before blocked in Needs you"
check_actions "$menu"
done_only="$(printf '%s\n' "$done_recs" | awk -F '\t' -v OFS='\t' '$1 == "agent" && $12 == "blocked" { $12 = "working" } { print }')"
menu="$(plugin "$done_only" $'awake\toff\t-\t0\nthermal\t0\tnominal')"
[[ "$(printf '%s\n' "$menu" | head -1)" == ":terminal: 2 · 1 done" ]] || fail "a done session tinted the icon: $(printf '%s\n' "$menu" | head -1)"
[[ "$menu" == *$'\n'"Needs you (1) | size=12"$'\n'"Herdr fleet smart notifications · claude · finished, to review | "* ]] || fail "Needs you with only a done session"
# Herdr's health: calm items whose submenus give the commands.
menu="$(plugin "$calm" $'awake\toff\t-\t0\nthermal\t0\tnominal\nhhealth\tserver\tstale\nhhealth\toutdated\tclaude letta bad$(x)')"
[[ "$(printf '%s\n' "$menu" | head -1)" == ":terminal: 2" ]] || fail "Herdr's health tinted the icon: $(printf '%s\n' "$menu" | head -1)"
[[ "$menu" == *$'\n'"Needs you (2) | size=12"$'\n'"Herdr server is older than the client · restart when idle | sfimage=arrow.triangle.2.circlepath "*$'\n'"--Once its agents are idle, in a terminal outside Herdr: | size=11"$'\n'"--herdr server stop | "*$'\n'"--then: herdr | "* ]] \
    || fail "stale Herdr server item: $(printf '%s\n' "$menu" | grep -A4 'Herdr server')"
[[ "$menu" == *$'\n'"Herdr integrations outdated: claude letta | "*$'\n'"--Reinstall each, in a terminal: | size=11"$'\n'"--herdr integration install claude | "*$'\n'"--herdr integration install letta | "* ]] \
    || fail "outdated integrations item: $(printf '%s\n' "$menu" | grep -A4 'integrations outdated')"
[[ "$menu" != *'$(x)'* ]] || fail "an odd integration name reached the menu"
[[ "$menu" != *"eyJyZW5kZXJpbmdNb2RlIjoiUGFsZXR0ZSIsImNvbG9ycyI6WyIjRkY5RjBBIl19"* ]] || fail "Herdr's health shown in orange"
check_actions "$menu"
pass "SwiftBar: finished sessions and Herdr's health are calm Needs-you items (counted, untinted); Herdr's title names a session"

# An MCP server in several sessions, every copy an mcp-lazy proxy whose
# server never started: proxies, not copies.
lz_job() { printf 'job\t%s\tmcp\t0\t0.0\t0\t9000\t1\tWed_Oct_14_07:31:08_2026\town\t%s\tclaude\t/w/%s\tchrome-devtools\t%s\t%s\n' "$1" "$2" "$3" "$3" "$4"; }
menu="$(plugin "$(lz_job 90419 90466 app lazy-idle; lz_job 84091 90500 shop lazy-idle)" "")"
[[ "$menu" == *$'\n'"--chrome-devtools · 2 lazy proxies · server not started · 0% · 17M | "* ]] \
    || fail "lazy proxies: $(printf '%s\n' "$menu" | grep 'chrome-devtools ·')"
menu="$(plugin "$(lz_job 90419 90466 app lazy-idle; lz_job 84091 90500 shop lazy)" "")"
[[ "$menu" == *$'\n'"--chrome-devtools · 2 copies · 0% · 17M | "* ]] || fail "lazy copies, one started: $(printf '%s\n' "$menu" | grep 'chrome-devtools ·')"
pass "SwiftBar: an MCP server whose copies are all idle mcp-lazy proxies reads as proxies, its server not started"

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

# Lid mode in the menu: the group by default, hidden with AGENTS_LID=0
# (choices up to AGENTS_LID_MAX, each reporting by notification); the time
# left and End lid mode now… while on; a red restore item when stale.
lid_off=$'awake\toff\t-\t0\nlid\toff\t-\t0\t28800'
menu="$(plugin "$calm" "$lid_off"$'\nconf\tAGENTS_LID\t0')"
[[ "$menu" != *"Lid closed"* && "$menu" != *"param2=lid"* ]] || fail "lid group shown with AGENTS_LID=0"
menu="$(plugin "$calm" "$lid_off")"
[[ "$menu" == *$'\n'"--Lid closed too… | sfimage=laptopcomputer refresh=true"$'\n'"----For 1 hour | bash="*" param1=awake param2=lid param3=1h param4=--notify"$'\n'"----For 3 hours | "*"param3=3h param4=--notify"$'\n'"----For 8 hours | "*"param3=8h param4=--notify"$'\n'"----Asks for your password; restores on timeout or low battery | size=11"$'\n'"--Off | "* ]] \
    || fail "lid group: $(printf '%s\n' "$menu" | grep -A5 'Lid closed')"
check_actions "$menu"
menu="$(plugin "$calm" $'awake\toff\t-\t0\nlid\toff\t-\t0\t10800')"
[[ "$menu" == *"param3=3h"* && "$menu" != *"----For 8 hours"* ]] || fail "lid choices above AGENTS_LID_MAX offered"
lid_end=$(( $(date +%s) + 9700 ))
menu="$(plugin "$calm" "awake"$'\t'"lid"$'\t'"8800"$'\t'"$lid_end"$'\n'"lid"$'\t'"on"$'\t'"4242"$'\t'"$lid_end"$'\t'"28800")"
[[ "$menu" == *$'\n'"Awake: lid closed · 2h41m left | sfimage=laptopcomputer refresh=true"* || "$menu" == *$'\n'"Awake: lid closed · 2h42m left | sfimage=laptopcomputer refresh=true"* ]] \
    || fail "lid awake line: $(printf '%s\n' "$menu" | grep '^Awake')"
[[ "$(printf '%s\n' "$menu" | head -1)" == ":terminal: 2 :cup.and.saucer.fill:" ]] || fail "lid on is not a calm title"
[[ "$menu" == *$'\n'"End lid mode now… | bash="*" param1=awake param2=off param3=--notify sfimage=laptopcomputer.slash"* ]] || fail "no End lid mode now… while on"
check_actions "$menu"
[[ "$(plugin "$calm" "$lid_off")" != *"End lid mode now"* ]] || fail "End lid mode now… shown with lid mode off"
menu="$(plugin "$calm" $'awake\toff\t-\t0\nlid\tstale\t-\t0\t28800')"
[[ "$(printf '%s\n' "$menu" | head -1)" == ":terminal: 2 | sfcolor=#FF453A" ]] || fail "stale lid sleep does not turn the icon red"
[[ "$(printf '%s\n' "$menu" | sed -n 3,4p)" == "Needs you (1) | size=12"$'\n'"Restore lid sleep (disabled, nothing restores it)… | sfimage=exclamationmark.triangle.fill sfconfig=eyJyZW5kZXJpbmdNb2RlIjoiUGFsZXR0ZSIsImNvbG9ycyI6WyIjRkY0NTNBIl19 bash="*" param1=awake param2=restore param3=--notify symbolize=false" ]] \
    || fail "Restore lid sleep does not lead Needs you: $(printf '%s\n' "$menu" | sed -n 3,4p)"
[[ "$menu" == *$'\n'"Restore lid sleep… | bash="*" param1=awake param2=restore param3=--notify sfimage=lock.open"* ]] || fail "Restore lid sleep missing from Awake"
check_actions "$menu"
pass "SwiftBar lid mode: the group by default (AGENTS_LID=0 hides it), End lid mode now… while on, a red restore item when stale"

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
[[ "$(afield 1001 12)/$(afield 1001 8)" == "chrome-devtools/2" && "$(afield 1004 12)" == example-agent ]] || fail "MCP names and process counts"
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

# Stuck polling loops: one waiting 3h27m on a task output that will never end
# with "ok" (Claude Code appends "[exited with code N]"), one young loop whose
# watched file has been quiet for years, one young loop on a fresh file, one
# without a file to watch, a 2h loop on a log still being written (the
# producer is alive: not stuck, whatever its age), and a 1h30m loop on the
# quiet file. A loop is stuck only once it has run AGENTS_WAIT_STUCK minutes:
# the young loop on the quiet file is not.
mkdir -p "$tmp/w"; : > "$tmp/w/fresh.log"; : > "$tmp/w/quiet.out"; touch -t 202001010000 "$tmp/w/quiet.out"
snap_pre='/bin/zsh -c source /Users/NAME/.claude/shell-snapshots/s.sh 2>/dev/null || true && eval'
st_fixture="$(cat <<EOF
    1     0     0 root  0.0  20000 10:00.00 13-16:00:00 Wed Sep 30 16:57:15 2026     /sbin/launchd
 5000     1   501 me    1.0 300000  0:30.00 04:00:00 Wed Oct 14 05:00:00 2026     claude
 5010  5000   501 me    0.0   2000  0:00.10 03:27:00 Wed Oct 14 05:33:00 2026     $snap_pre 'F=/private/tmp/claude-501/myapp/tasks/b1.output; until tail -1 \$F | grep -qE "^(ok|FAIL)"; do sleep 5; done; tail -5 \$F' < /dev/null && pwd -P >| /tmp/c1
 5011  5010   501 me    0.0    900  0:00.00 00:03 Wed Oct 14 08:59:57 2026     sleep 5
 5020  5000   501 me    0.0   2000  0:00.10 05:00 Wed Oct 14 08:55:00 2026     $snap_pre 'until [ -s "$tmp/w/quiet.out" ] 2>/dev/null; do sleep 5; done' < /dev/null && pwd -P >| /tmp/c2
 5030  5000   501 me    0.0   2000  0:00.10 05:00 Wed Oct 14 08:55:00 2026     $snap_pre 'L=$tmp/w/fresh.log; while ! grep -q done \${L}; do sleep 5; done' < /dev/null && pwd -P >| /tmp/c3
 5040  5000   501 me    0.0   2000  0:00.10 05:00 Wed Oct 14 08:55:00 2026     $snap_pre 'while kill -0 4242 2>/dev/null; do sleep 5; done' < /dev/null && pwd -P >| /tmp/c4
 5050  5000   501 me    0.0   2000  0:00.10 03:00:00 Wed Oct 14 06:00:00 2026     $snap_pre 'make serve > /tmp/serve.log' < /dev/null && pwd -P >| /tmp/c5
 5060  5000   501 me    0.0   2000  0:00.10 02:00:00 Wed Oct 14 07:00:00 2026     $snap_pre 'until grep -q "^done" $tmp/w/fresh.log; do sleep 30; done' < /dev/null && pwd -P >| /tmp/c6
 5070  5000   501 me    0.0   2000  0:00.10 01:30:00 Wed Oct 14 07:30:00 2026     $snap_pre 'Q=$tmp/w/quiet.out; until tail -1 "\$Q" | grep -q ok; do sleep 10; done' < /dev/null && pwd -P >| /tmp/c7
EOF
)"
st_recs="$(printf '%s\n' "$st_fixture" | AGENTS_SELF=9999 agents_classify "" "")"
st_watch="$(printf '%s\n' "$st_recs" | awk -F '\t' '$1 == "watch" { print $2 "\t" $3 }')"
[[ "$st_watch" == "5010"$'\t'"/private/tmp/claude-501/myapp/tasks/b1.output"$'\n'"5020"$'\t'"$tmp/w/quiet.out"$'\n'"5030"$'\t'"$tmp/w/fresh.log"$'\n'"5060"$'\t'"$tmp/w/fresh.log"$'\n'"5070"$'\t'"$tmp/w/quiet.out" ]] \
    || fail "watched files of polling loops: $st_watch"
[[ "$(_agents_watched "$st_watch")" == "5020"$'\t'"quiet"$'\n'"5030"$'\t'"fresh"$'\n'"5060"$'\t'"fresh"$'\n'"5070"$'\t'"quiet" ]] \
    || fail "watched files: quiet or fresh; a missing one says nothing: $(_agents_watched "$st_watch")"
[[ -z "$(AGENTS_WAIT_STUCK=0 _agents_watched "$st_watch")" ]] || fail "AGENTS_WAIT_STUCK=0 still checks files"
st_cwds="$(for p in 5000 5010 5020 5030 5040 5050 5060 5070; do printf "%s\t/Users/NAME/myapp\n" "$p"; done)"
st_enr="$(printf '%s\n' "$st_recs" | agents_enrich "$st_cwds" "" "$(_agents_watched "$st_watch")")"
[[ -z "$(printf '%s\n' "$st_enr" | awk -F '\t' '$1 == "watch"')" ]] || fail "watch records leak out of agents_enrich"
stflags() { printf '%s\n' "$st_enr" | awk -F '\t' -v p="$1" '$1 == "act" && $2 == p { print $16 }'; }
[[ "$(stflags 5010)" == wait,stuck ]] || fail "a 3h27m polling loop is not stuck: $(stflags 5010)"
[[ "$(stflags 5020)" == wait ]] || fail "a 5-minute loop stuck (it can't have waited an hour): $(stflags 5020)"
[[ "$(stflags 5070)" == wait,stuck ]] || fail "a 1h30m loop on a quiet file is not stuck: $(stflags 5070)"
[[ "$(stflags 5030)" == wait ]] || fail "a young loop on a fresh file flagged: $(stflags 5030)"
[[ "$(stflags 5040)" == wait ]] || fail "a young loop without a file flagged: $(stflags 5040)"
[[ "$(stflags 5050)" == long ]] || fail "an ordinary long command: $(stflags 5050)"
[[ "$(stflags 5060)" == wait ]] || fail "a 2h loop on a log still being written flagged: $(stflags 5060)"
[[ "$(printf '%s\n' "$st_recs" | agents_enrich "$st_cwds" "" "" | awk -F '\t' '$1 == "act" && $2 == 5060 { print $16 }')" == wait,stuck ]] \
    || fail "a 2h loop whose file was not checked is not stuck by age"
st_late="$(printf '%s\n' "$st_recs" | AGENTS_WAIT_STUCK=300 agents_enrich "$st_cwds" "" "")"
[[ "$(printf '%s\n' "$st_late" | awk -F '\t' '$1 == "act" && $2 == 5010 { print $16 }')" == wait ]] || fail "AGENTS_WAIT_STUCK=300 not honored"
[[ -z "$(printf '%s\n' "$st_recs" | AGENTS_WAIT_STUCK=0 agents_enrich "$st_cwds" "" "5020"$'\t'"quiet" | awk -F '\t' '$16 ~ /stuck/')" ]] \
    || fail "AGENTS_WAIT_STUCK=0 still flags stuck loops"
[[ "$(cd "$tmp" && unset AGENTS_WAIT_STUCK && printf 'AGENTS_WAIT_STUCK=90\n' > "$tmp/stuck.conf" \
    && AGENTS_CONF="$tmp/stuck.conf" bash "$REPO_DIR/bin/agents" config | grep '^AGENTS_WAIT_STUCK=')" == AGENTS_WAIT_STUCK=90 ]] \
    || fail "AGENTS_WAIT_STUCK from the config file"
! _agents_conf_valid AGENTS_WAIT_STUCK 1h || fail "AGENTS_WAIT_STUCK=1h accepted (minutes only)"
# Bad values from the environment fall back to the default, with one warning.
out="$(AGENTS_CONF="$tmp/none" AGENTS_WAIT_STUCK=1h AGENTS_LID_MIN_BATTERY=abc AGENTS_LID_MAX=forever AGENTS_LID=yes \
    bash "$REPO_DIR/bin/agents" config 2>"$tmp/env.err")"
[[ "$out" == *$'\nAGENTS_WAIT_STUCK=60\n'* && "$out" == *$'\nAGENTS_LID=1\n'* && "$out" == *$'\nAGENTS_LID_MAX=8h\n'* && "$out" == *$'\nAGENTS_LID_MIN_BATTERY=20'* ]] \
    || fail "bad environment values not replaced by defaults: $out"
[[ "$(grep -c 'in the environment; using' "$tmp/env.err")" == 4 ]] || fail "one warning per bad environment value: $(cat "$tmp/env.err")"
pass "stuck polling loops: AGENTS_WAIT_STUCK of age, unless the watched file is fresh; young loops stay wait; 0 disables"

# watched(): only a path given to tail, head, grep, cat, test, [ or [[ (or
# through VAR=/path) is a watched file; quoted paths with spaces are whole.
# shellcheck disable=SC2016  # awk source
wprobe() { printf '%s\n' "$1" | _agents_awk_eval "lib_proc lib_activity" '{ print watched($0) }'; }
[[ "$(wprobe 'until docker exec db /usr/bin/pg_isready; do sleep 2; done')" == "" ]] || fail "watched: docker exec's program taken as the file"
[[ "$(wprobe 'until curl --unix-socket /var/run/x.sock http://x/health; do sleep 2; done')" == "" ]] || fail "watched: curl's socket taken as the file"
[[ "$(wprobe 'until [ -f "/tmp/my dir/done" ]; do sleep 2; done')" == "/tmp/my dir/done" ]] || fail "watched: quoted path with a space: $(wprobe 'until [ -f "/tmp/my dir/done" ]; do sleep 2; done')"
[[ "$(wprobe 'until [ ! -s /tmp/q ]; do sleep 2; done')" == /tmp/q ]] || fail "watched: [ ! -s PATH ]"
[[ "$(wprobe 'while ! /usr/bin/grep -q ok /tmp/log 2>/dev/null; do sleep 2; done')" == /tmp/log ]] || fail "watched: grep by absolute path"
# shellcheck disable=SC2016  # a literal command line, $F included
[[ "$(wprobe 'F="/tmp/a b"; until tail -1 $F | grep -q ok; do sleep 2; done')" == "" ]] || fail "watched: a quoted assignment with a space half-read"
[[ "$(wprobe 'until grep -q ok /tmp/x > /tmp/out; do sleep 2; done')" == /tmp/x ]] || fail "watched: a redirect target taken first"
pass "watched(): only tail/head/grep/cat/test/[ arguments; docker exec, curl --unix-socket ignored; quoted paths with spaces whole"

_agents_colors
st_detail="$(printf '%s\n' "$st_enr" | AGENTS_WIDTH=200 agents_render "agents detail")"
[[ "$st_detail" == *"5010    until tail -1 \$F | grep -qE \"^(ok|FAIL)\"; do sleep 5; done; tail -5 \$F · 3h27m · 0% · main  wait  stuck"* ]] \
    || fail "agents ps stuck flag: $st_detail"
[[ "$st_detail" == *"5040    while kill -0 4242 2>/dev/null; do sleep 5; done · 5m00s · 0% · main  wait"$'\n'* ]] || fail "agents ps plain wait: $st_detail"
if command -v jq >/dev/null 2>&1; then
    sj="$(printf '%s\n' "$st_enr" | agents_json)"
    printf '%s' "$sj" | jq -e '.schema_version == 1 and ([.agents[0].activity.tools[] | select(.flags | index("stuck")) | .pid] | sort) == [5010, 5070]
        and (.agents[0].activity.tools[] | select(.pid == 5030) | .flags) == ["wait"]' >/dev/null \
        || fail "json stuck flags: $(printf '%s' "$sj" | jq -c '[.agents[0].activity.tools[] | {pid, flags}]')"
fi
[[ "$(printf '%s\n' "$st_enr" | agents_reap_tokens true | tr '\n' ' ')" == "5010@Wed_Oct_14_05:33:00_2026 5070@Wed_Oct_14_07:30:00_2026 " ]] \
    || fail "reap --stuck tokens: $(printf '%s\n' "$st_enr" | agents_reap_tokens true | tr '\n' ' ')"
[[ -z "$(printf '%s\n' "$st_enr" | agents_reap_tokens false)" ]] || fail "plain reap picks polling loops"
[[ "$(printf '%s\n' "$enriched" | agents_reap_tokens true | wc -l | tr -d ' ')" == 4 ]] || fail "reap --stuck lost the stale trees"
# shellcheck disable=SC2317,SC2329  # stubs for the sourced agents_main
reap_out="$(
    agents_collect() { printf '%s\n' "$st_enr"; }
    agents_snapshot() { printf '%s\n' "$st_fixture"; }
    _agents_cwds() { :; }
    AGENTS_SELF=9999 AGENTS_UID=501 agents_main reap -n --stuck 2>&1
)"
[[ "$reap_out" == *"  5011    sleep"*"  5010    zsh"*"  5070    zsh"*"would send SIGTERM to 3 process(es)"* ]] || fail "reap -n --stuck: $reap_out"
[[ "$reap_out" != *5020* && "$reap_out" != *5030* && "$reap_out" != *5040* && "$reap_out" != *5050* && "$reap_out" != *5060* ]] || fail "reap --stuck picked a loop that is not stuck: $reap_out"
# shellcheck disable=SC2317,SC2329
[[ "$(agents_collect() { printf '%s\n' "$st_enr"; }; agents_main reap -n 2>&1)" == "no stale processes" ]] || fail "plain reap stops polling loops"
rc=0; agents_main kill -n --stuck 5010 >/dev/null 2>&1 || rc=$?
[[ $rc -eq 2 ]] || fail "--stuck accepted by kill"
pass "stuck loops: ps shows stuck, json flags it (schema 1), reap -n --stuck plans only stuck loops and stale trees"

st_menu_recs="$(printf '%s\n' "$st_enr" | awk -F '\t' '($1 == "agent" || $1 == "act") && $2 != 5050')"
menu="$(plugin "$st_menu_recs" "")"
[[ "$(printf '%s\n' "$menu" | head -1)" == ":terminal: 1 | sfcolor=#FF9F0A" ]] || fail "a stuck loop does not tint the title (or counts as blocked): $(printf '%s\n' "$menu" | head -1)"
[[ "$menu" == *$'\n'"Needs you (2) | size=12"$'\n'* ]] || fail "stuck loops not in Needs you"
[[ "$menu" == *$'\n'"myapp: until tail -1 \$F ¦ grep -qE \"^(ok¦FAIL)\"; do sleep 5; don... · stuck 3h27m | sfimage=hourglass sfconfig=eyJyZW5kZXJpbmdNb2RlIjoiUGFsZXR0ZSIsImNvbG9ycyI6WyIjRkY5RjBBIl19 refresh=true symbolize=false"$'\n'"--Stop command… | bash="*" param1=kill param2=--confirm-gui param3=--notify param4=5010@Wed_Oct_14_05:33:00_2026 sfimage=xmark.octagon"* ]] \
    || fail "Needs you stuck line: $(printf '%s\n' "$menu" | grep -A1 'stuck')"
[[ "$menu" == *$'\n'"--until tail -1 \$F ¦ grep -qE \"^(ok¦FAIL)\"; do sleep 5; don... · 3h27m · 0% · main · stuck | refresh=true sfimage=hourglass sfconfig=eyJyZW5kZXJpbmdNb2RlIjoiUGFsZXR0ZSIsImNvbG9ycyI6WyIjRkY5RjBBIl19 symbolize=false"* ]] \
    || fail "Running line of a stuck loop: $(printf '%s\n' "$menu" | grep 'tail -1')"
[[ "$menu" == *" · main · waiting | refresh=true sfimage=hourglass sfconfig=eyJyZW5kZXJpbmdNb2RlIjoiUGFsZXR0ZSIsImNvbG9ycyI6WyIjOEU4RTkzIl19 "* ]] || fail "a young loop is not a gray waiting"
[[ "$menu" != *"myapp: while"* ]] || fail "a loop that is not stuck needs you"
check_actions "$menu"
pass "menu: a stuck loop is an orange hourglass in Needs you with Stop command…; young loops stay gray"

if command -v jq >/dev/null 2>&1; then
    aj="$(printf '%s\n' "$act_enr" | agents_json)"
    printf '%s' "$aj" | jq -e '.schema_version == 1' >/dev/null || fail "schema_version"
    printf '%s' "$aj" | jq -e '.agents[] | (.start_epoch | type) == "number"' >/dev/null || fail "session start_epoch"
    printf '%s' "$aj" | jq -e '.agents[] | select(.pid == 1000) | .activity
        | (.mcp | map(.name) | sort) == ["chrome-devtools", "example-agent"]
        and (.mcp[] | select(.name == "chrome-devtools") | .procs) == 3
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

# bash 3.2 can read a UTF-8 byte as part of a variable name: "$n×" printed
# "\x97" on macOS CI. Every variable before a non-ASCII character is braced.
bad="$(LC_ALL=C grep -nE '\$[A-Za-z_][A-Za-z0-9_]*[^ -~]' "$REPO_DIR/bin/agents" "$REPO_DIR"/lib/agents/*.sh "$REPO_DIR"/lib/agents/awk/*.awk "$REPO_DIR/configs/swiftbar/agents.10s.sh" || true)"
[[ -z "$bad" ]] || fail "unbraced variable before a non-ASCII character: $bad"
pass "variables before non-ASCII text are braced (bash 3.2)"

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
    || fail "Stop duplicates keeps the newest (1010) and stops the older (1020): $(printf '%s\n' "$menu" | grep -E 'Stop duplicates|internal/web')"
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

# Ghostty 1.3+ (it ships Ghostty.sdef): a window of the running instance
# through AppleScript, and `open -na` (a second instance) only when that
# opened no window. Stubs log what osascript and open were given.
mkdir -p "$apps/C/Ghostty.app/Contents/Resources"
cp -R "$apps/B/Ghostty.app/Contents/MacOS" "$apps/C/Ghostty.app/Contents/"
gbin="$tmp/ghostbin"; mkdir -p "$gbin"
printf '#!/bin/bash\nd=%q\nprintf "%%s\\0" "$@" > "$d/osa.args"\ncase "$(cat "$d/osa.mode")" in\n  ok) echo ok ;; down) echo down ;;\n  fail) echo "execution error: Not authorized to send Apple events to Ghostty. (-1743)" >&2; exit 1 ;;\n  killed) kill -TERM $$ ;;\nesac\n' "$tmp" > "$gbin/osascript"
printf '#!/bin/bash\nprintf "%%s\\n" "$@" > %q/open.args\n' "$tmp" > "$gbin/open"
printf '#!/bin/bash\nprintf "%%s\\0" "$@" > %q/stub.args\n' "$tmp" > "$gbin/agents-argstub"
chmod +x "$gbin/osascript" "$gbin/open" "$gbin/agents-argstub"
ot() {   # MODE ARGS... — open-term with osascript answering MODE
    rm -f "$tmp/osa.args" "$tmp/open.args"; echo "$1" > "$tmp/osa.mode"; shift
    ( PATH="$gbin:$PATH" AGENTS_TESTING=1 AGENTS_APP_DIRS="$apps/C" AGENTS_TERMINAL=auto agents_open_term "$@" )
}
! AGENTS_TESTING=1 AGENTS_APP_DIRS="$apps/C" _agents_ghostty_scriptable || fail "Ghostty without a dictionary counted as scriptable"
: > "$apps/C/Ghostty.app/Contents/Resources/Ghostty.sdef"
AGENTS_TESTING=1 AGENTS_APP_DIRS="$apps/C" _agents_ghostty_scriptable || fail "Ghostty 1.3's dictionary not found"
ot ok watch || fail "open-term: Ghostty window failed"
[[ -f "$tmp/osa.args" && ! -e "$tmp/open.args" ]] || fail "open-term: AppleScript window, then no second instance"
osa="$(tr '\0' '\n' < "$tmp/osa.args")"
[[ "$osa" == *$'\nif application "Ghostty" is not running then return "down"\n'*$'\nnew window with configuration cfg\n'* ]] \
    || fail "ghostty-window script: $osa"
[[ "$osa" == *"set command of cfg to (item 1 of argv)"* ]] || fail "the command travels only as an argument: $osa"
ot down watch || fail "open-term: Ghostty not running"
[[ "$(head -2 "$tmp/open.args" | tr '\n' ' ')" == "-na Ghostty " ]] || fail "no Ghostty running: open -na starts the one instance"
ot fail watch || fail "open-term: AppleScript refused"
[[ -f "$tmp/open.args" ]] || fail "AppleScript refused: open -na is the fallback"
! ot killed watch || fail "open-term: a timed-out AppleScript reported success"
[[ ! -e "$tmp/open.args" ]] || fail "a timed-out AppleScript (a window may still come) fell back to a second instance"
# Hostile words reach agents exactly, through /bin/sh and bash -c: no quote,
# $(…), backtick or newline escapes either layer, or the AppleScript source.
hostile=("it's" "\$(touch $tmp/pwned)" "\`touch $tmp/pwned\`" "\"; touch $tmp/pwned; \"" "'; touch $tmp/pwned; '" $'line\nbreak' 'a\b' '*' '')
AGENTS_PATH="$gbin/agents-argstub" ot ok "${hostile[@]}" || fail "open-term with hostile words"
script=""; last=""
while IFS= read -r -d '' w; do [[ "$w" == -e ]] || { [[ -z "$last" ]] || script+="$last"$'\n'; last="$w"; }; done < "$tmp/osa.args"
[[ "$script" != *"$tmp"* && "$script" != *touch* ]] || fail "command text inside the AppleScript source: $script"
[[ "$last" != *$'\n'* ]] || fail "a raw newline in the Ghostty command"
( cd "$tmp" && /bin/sh -c "$last" ) </dev/null || fail "Ghostty's command did not run: $last"
[[ ! -e "$tmp/pwned" ]] || fail "hostile text ran in the Ghostty command"
cmp -s "$tmp/stub.args" <(printf '%s\0' "${hostile[@]}") || fail "hostile words changed on the way: $(tr '\0' '|' < "$tmp/stub.args")"
AGENTS_PATH="$gbin/agents-argstub" ot ok --hold awake status || fail "open-term --hold"
last=""; while IFS= read -r -d '' w; do last="$w"; done < "$tmp/osa.args"
[[ "$last" == *"awake status '" && "$(tr '\0' '\n' < "$tmp/osa.args")" == *$'\nset wait after command of cfg to true\n'* ]] \
    || fail "Ghostty itself keeps its window for a key (no second prompt of ours): $last"
dry="$(PATH="$gbin:$PATH" AGENTS_TESTING=1 AGENTS_APP_DIRS="$apps/C" AGENTS_TERMINAL=ghostty bash "$REPO_DIR/bin/agents" open-term -n watch)"
[[ "$dry" == "osascript -e on\\ run\\ argv "*$'\n'"open -na Ghostty --args -e /usr/bin/env "* ]] || fail "open-term -n with Ghostty 1.3: $dry"
pass "open-term: Ghostty 1.3+ opens a window of the running instance; open -na only when none runs or AppleScript fails; hostile words arrive intact"

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
# terminal-notifier (a stub that logs one argument per line): a notification
# about a session jumps there when clicked; nothing else reaches the shell.
mkdir -p "$tmp/tn" "$tmp/odd'dir \$(touch $tmp/pwned)"
printf '#!/bin/bash\nprintf "%%s\\n" "$@" > "%s"\n[[ -z "$TN_FAIL" ]]\n' "$tmp/tn.argv" > "$tmp/tn/terminal-notifier"
printf '#!/bin/bash\nprintf "%%s\\n" "$@" > "%s"\n' "$tmp/jump.argv" > "$tmp/odd'dir \$(touch $tmp/pwned)/agents"
chmod +x "$tmp/tn/terminal-notifier" "$tmp/odd'dir \$(touch $tmp/pwned)/agents"
tn() { ( PATH="$tmp/osa:$PATH"; TUIDEV_TERMINAL_NOTIFIER="$tmp/tn/terminal-notifier" AGENTS_NOTIFY=true _agents_notify "$@" ); }
# tg TOKEN BUNDLE — a TARGET as agents_root_of prints it.
tg() { printf '%s\tGhostty\t%s\t-\n' "$1" "$2"; }
: > "$tmp/osa.log"
tn "Nothing to reap"
[[ "$(cat "$tmp/tn.argv")" == $'-title\nagents\n-message\nNothing to reap' && ! -s "$tmp/osa.log" ]] \
    || fail "terminal-notifier, no session: $(cat "$tmp/tn.argv")"
tok="4242@Wed_Oct_14_08:00:00_2026"
( AGENTS_PATH="$tmp/odd'dir \$(touch $tmp/pwned)/agents"; tn 'Stopped 1 in "x" $(touch '"$tmp"'/pwned) `id`' "$(tg "$tok" com.mitchellh.ghostty)" agents-reap )
argv="$(cat "$tmp/tn.argv")"
[[ "$(sed -n 1,4p "$tmp/tn.argv")" == $'-title\nagents\n-message\nStopped 1 in "x" $(touch '"$tmp"'/pwned) `id`' ]] || fail "the message is not one argument: $argv"
[[ "$argv" == *$'\n-group\nagents-reap-'"$tok"$'\n'* && "$argv" == *$'\n-activate\ncom.mitchellh.ghostty' ]] || fail "group or activate: $argv"
cmd="$(sed -n '/^-execute$/{n;p;}' "$tmp/tn.argv")"
[[ "$cmd" == "PATH='"*"' '$tmp/odd'\''dir \$(touch $tmp/pwned)/agents' jump --notify $tok" ]] || fail "execute: $cmd"
[[ "$cmd" != *Stopped* && "$cmd" != *'`id`'* ]] || fail "the message reached the execute string: $cmd"
/bin/sh -c "$cmd"
[[ "$(cat "$tmp/jump.argv")" == $'jump\n--notify\n'"$tok" && ! -e "$tmp/pwned" ]] || fail "the click: $(cat "$tmp/jump.argv")"
( AGENTS_PATH="$tmp/odd'dir \$(touch $tmp/pwned)/agents"; tn "x" "$(tg '4242@x; touch y' 'com.x;touch')" agents-reap )
[[ "$(cat "$tmp/tn.argv")" != *-execute* && "$(cat "$tmp/tn.argv")" != *-activate* && "$(cat "$tmp/tn.argv")" != *-group* ]] \
    || fail "an unchecked token or bundle id: $(cat "$tmp/tn.argv")"
for b in 'a b' - '-x.y' 'com.x;touch'; do
    ( AGENTS_PATH="$tmp/odd'dir \$(touch $tmp/pwned)/agents"; tn "x" "$(tg "$tok" "$b")" )
    [[ "$(cat "$tmp/tn.argv")" == *-execute* && "$(cat "$tmp/tn.argv")" != *-activate* && "$(cat "$tmp/tn.argv")" != *-group* ]] \
        || fail "bundle id '$b' (or a group without GROUP): $(cat "$tmp/tn.argv")"
done
# terminal-notifier reads a value starting with [ ( { < or a quote as a
# property list and drops the notification; one starting with - as an option.
for m in '[x] y' '(x' '{x' '<x' '"x"' "'x'" '-x'; do
    tn "$m"
    want="\\$m"; [[ "$m" != -* ]] || want=" $m"
    [[ "$(sed -n 4p "$tmp/tn.argv")" == "$want" ]] || fail "not escaped for terminal-notifier: $m -> $(sed -n 4p "$tmp/tn.argv")"
done
tn 'x [y]'; [[ "$(sed -n 4p "$tmp/tn.argv")" == 'x [y]' ]] || fail "escaped past the first character"
: > "$tmp/osa.log"
TN_FAIL=1 tn "fell back"
grep -q 'fell back' "$tmp/osa.log" || fail "no osascript when terminal-notifier fails"
: > "$tmp/osa.log"
# shellcheck disable=SC2317,SC2329  # called by _agents_notify (0.9 and 0.10 name it differently)
( _agents_timeout() { shift; "$@"; return 124; }; tn "cut off" )
[[ "$(sed -n 4p "$tmp/tn.argv")" == "cut off" && ! -s "$tmp/osa.log" ]] || fail "osascript after terminal-notifier timed out (a second banner)"
[[ "$(_agents_kill_message $'60712\tclaude\t26\tmyapp')" == "Kill claude in myapp (pid 60712, 26 child processes)?" ]] \
    || fail "dialog text: $(_agents_kill_message $'60712\tclaude\t26\tmyapp')"
[[ "$(_agents_kill_message $'29046\tnode\t0\t-')" == "Kill node (pid 29046)?" ]] || fail "dialog text without project or children"
[[ "$(_agents_kill_message $'1\ta\t1\tp\n2\tb\t0\tq')" == "Kill 2 process trees?"* ]] || fail "dialog text for two trees"
pass "kill dialog: Cancel is the default and no GUI means no; notifications only with --notify, clickable to the session with terminal-notifier (checked token and bundle id, escaped text, osascript only when it failed, not timed out)"

# Live: --confirm-gui with Cancel leaves the process alone (needs ps).
if ps -o lstart= -p $$ >/dev/null 2>&1; then
    ( bash -c 'echo $$ > "$1"; sleep 300 & wait' _ "$tmp/gui.pid" </dev/null >/dev/null 2>&1 & )
    for _ in 1 2 3 4 5 6 7 8 9 10; do [[ -s "$tmp/gui.pid" ]] && break; sleep 0.1; done
    root="$(cat "$tmp/gui.pid")"; sleep 0.2
    out="$(PATH="$tmp/osa:$PATH" OSA_ANSWER=Cancel AGENTS_SELF=$$ AGENTS_UID="$(id -u)" AGENTS_CONFIRM_GUI=true \
        AGENTS_YES=false AGENTS_DRY_RUN=false agents_kill_tokens true "$root" 2>&1)" && fail "kill went ahead after Cancel"
    [[ -n "$(_agents_start "$root")" ]] || fail "Cancel still killed the session"
    [[ "$out" == *cancelled* ]] || fail "Cancel not reported: $out"
    : > "$tmp/osa.log"
    out="$(PATH="$tmp/osa:$PATH" OSA_ANSWER=Kill AGENTS_SELF=$$ AGENTS_UID="$(id -u)" AGENTS_CONFIRM_GUI=true AGENTS_NOTIFY=true \
        AGENTS_YES=false AGENTS_DRY_RUN=false AGENTS_GRACE=3 agents_kill_tokens true "$root" 2>&1)" || fail "kill after Kill failed: $out"
    [[ -z "$(_agents_start "$root")" ]] || fail "Kill did not kill"
    grep -q "Killed bash (pid $root) and 1 child processes" "$tmp/osa.log" || fail "result notification: $(cat "$tmp/osa.log")"
    pass "live: Cancel in the dialog kills nothing; Kill kills and notifies"
else
    echo "SKIP: ps unavailable here (sandbox?): live dialog test not run"
fi

# The Herdr cache: fresh answers are reused; a stale one is refreshed first
# (the menu, async, waits at most a second for it), and only when Herdr is
# slow does the menu get the cache (under a minute old) while a background
# refresh catches up. $tmp/herdr.sleep is how slow the stub Herdr is.
cache_dir="$tmp/hrun"; mkdir -p "$cache_dir"
# shellcheck disable=SC2317,SC2329  # replaces the real query, called by the cache
_agents_herdr_query() {
    echo "query" >> "$tmp/herdr.calls"; sleep "$(cat "$tmp/herdr.sleep")"
    printf 'claude\tworking\t/p\tw1:p1\tFix it\n'
}
echo 0 > "$tmp/herdr.sleep"
printf '%s\nclaude\tblocked\t/p\n' "$(date +%s)" > "$cache_dir/herdr.tsv"
[[ "$(AGENTS_RUN_DIR="$cache_dir" _agents_herdr_cached sync)" == $'claude\tblocked\t/p' && ! -e "$tmp/herdr.calls" ]] \
    || fail "a fresh cache was not reused"
# A 30s-old cache and a quick Herdr: the menu shows Herdr's answer now.
printf '%s\nclaude\tblocked\t/p\n' "$(( $(date +%s) - 30 ))" > "$cache_dir/herdr.tsv"
got="$(AGENTS_RUN_DIR="$cache_dir" _agents_herdr_cached async)"
[[ "$got" == $'claude\tworking\t/p\tw1:p1\tFix it' ]] || fail "async served a 30s-old cache although Herdr answers at once: $got"
grep -q working "$cache_dir/herdr.tsv" || fail "the synchronous refresh did not rewrite the cache"
# A slow Herdr: the menu waits at most about a second, serves the cache,
# and a background refresh (2s to answer) updates it.
echo 1.5 > "$tmp/herdr.sleep"
printf '%s\nclaude\tblocked\t/p\n' "$(( $(date +%s) - 30 ))" > "$cache_dir/herdr.tsv"
t0=$SECONDS
got="$(AGENTS_RUN_DIR="$cache_dir" _agents_herdr_cached async)"
[[ $((SECONDS - t0)) -lt 3 ]] || fail "the async (menu) path waited for a slow Herdr"
[[ "$got" == $'claude\tblocked\t/p' ]] || fail "async did not serve the recent cache when Herdr was slow: $got"
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30; do
    grep -q working "$cache_dir/herdr.tsv" 2>/dev/null && break; sleep 0.2
done
grep -q working "$cache_dir/herdr.tsv" || fail "the background refresh did not update the cache"
# Over a minute old and Herdr slow: nothing rather than an old answer.
printf '%s\nclaude\tblocked\t/p\n' "$(( $(date +%s) - 90 ))" > "$cache_dir/herdr.tsv"
echo 5 > "$tmp/herdr.sleep"
[[ -z "$(AGENTS_RUN_DIR="$cache_dir" _agents_herdr_cached async)" ]] || fail "async served a cache over a minute old"
# One refresh at a time: with the lock held, the menu serves the cache.
# (First the background refresh the last call started gives up: 2s.)
sleep 0.3
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25; do
    [[ -d "$cache_dir/herdr.lock" ]] || break; sleep 0.2
done
echo 0 > "$tmp/herdr.sleep"
printf '%s\nclaude\tblocked\t/p\n' "$(( $(date +%s) - 30 ))" > "$cache_dir/herdr.tsv"
mkdir "$cache_dir/herdr.lock"; printf '%s %s\n' "$$" "$(_agents_start $$)" > "$cache_dir/herdr.lock/holder"
[[ "$(AGENTS_RUN_DIR="$cache_dir" _agents_herdr_cached async)" == $'claude\tblocked\t/p' ]] || fail "a held refresh lock was not respected"
rm -rf "$cache_dir/herdr.lock"
unset -f _agents_herdr_query
pass "Herdr cache: reused for 10s; a stale one is refreshed first (the menu waits at most 1s), else served under a minute old"

# Herdr's health: an hourly background check (herdr status, herdr
# integration status) into a cache the menu reads, never waited on.
hh_dir="$tmp/hhealth"; mkdir -p "$hh_dir/bin"
cat > "$hh_dir/bin/herdr" <<'EOF'
#!/bin/sh
echo "herdr $*" >> "${HH_LOG:?}"
case "$1 $2" in
    "status ") printf 'server:\n  status: running\n\nupdate:\n  restart_needed: no\n  server_binary_stale: yes\n' ;;
    "integration status")
        printf 'pi: not installed (/h/.pi/x.ts)\nclaude: outdated (v10 < v11) (/h/.claude/hooks/x.sh)\ncodex: current (v10) (/h/.codex/x.sh)\n'
        printf 'letta (experimental): outdated (v1 < v2) (/h/.letta/x.sh)\n' ;;
esac
EOF
chmod +x "$hh_dir/bin/herdr"
export HH_LOG="$hh_dir/log"
recs="$(PATH="$hh_dir/bin:$PATH" _agents_herdr_health_check)"
[[ "$recs" == $'hhealth\tserver\tstale\nhhealth\toutdated\tclaude letta' ]] || fail "health check records: $recs"
# Under the harness the menu path is silent and asks nobody.
[[ -z "$(AGENTS_TESTING=1 AGENTS_RUN_DIR="$hh_dir/run" PATH="$hh_dir/bin:$PATH" _agents_herdr_health)" && ! -e "$hh_dir/run" ]] \
    || fail "Herdr's health was checked under AGENTS_TESTING"
# Outside it: the first call answers nothing and starts the check; the
# next serves its records; within the hour no check runs again.
( unset AGENTS_TESTING
  export AGENTS_RUN_DIR="$hh_dir/run" PATH="$hh_dir/bin:$PATH"
  [[ -z "$(_agents_herdr_health)" ]] || fail "the first health call waited for the check"
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25; do
      [[ -s "$AGENTS_RUN_DIR/herdr.health" ]] && break; sleep 0.2
  done
  [[ "$(_agents_herdr_health)" == $'hhealth\tserver\tstale\nhhealth\toutdated\tclaude letta' ]] || fail "health records from the cache: $(_agents_herdr_health)"
  : > "$HH_LOG"; _agents_herdr_health >/dev/null; sleep 0.5
  [[ ! -s "$HH_LOG" ]] || fail "Herdr's health was checked again within the hour: $(cat "$HH_LOG")"
  [[ -z "$(AGENTS_NO_HERDR=1 _agents_herdr_health)" ]] || fail "AGENTS_NO_HERDR=1 still reports Herdr's health"
  [[ -z "$(PATH=/usr/bin:/bin _agents_herdr_health)" ]] || fail "Herdr's health reported without herdr installed" ) || exit 1
pass "Herdr health: server_binary_stale and outdated integrations, from an hourly background check; silent without herdr"

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
# Events: one sanitized TSV line per cleanup; nothing with history off.
ev="$tmp/events"
AGENTS_DATA_DIR="$ev" agents_event kill manual 42 $'a\tb\nc' proj ""
IFS=$'\t' read -r e_t e_kind e_reason e_pid e_name e_proj e_sess < "$ev/events.tsv"
[[ "$e_t" =~ ^[0-9]+$ && "$e_kind/$e_reason/$e_pid/$e_name/$e_proj/$e_sess" == "kill/manual/42/a b c/proj/-" ]] \
    || fail "events: $(cat "$ev/events.tsv")"
rm -rf "$ev"; AGENTS_HISTORY=0 AGENTS_DATA_DIR="$ev" agents_event kill manual 1 x - -
[[ ! -e "$ev" ]] || fail "events: written with AGENTS_HISTORY=0"
pass "events: one sanitized line per cleanup; AGENTS_HISTORY=0 writes nothing"

# The state-file helpers every lock and stamp goes through (util.sh).
lk="$tmp/locks" age=""; mkdir -p "$lk"
_agents_lock "$lk/a" || fail "lock: a free lock not taken"
! _agents_lock "$lk/a" || fail "lock: a held lock taken twice"
! _agents_lock "$lk/a" 3 0.05 || fail "lock: a held lock taken on a retry"
_agents_unlock "$lk/a"; [[ ! -e "$lk/a" ]] || fail "unlock left the lock"
mkdir "$lk/old"; touch -t 202001010000 "$lk/old"
_agents_lock "$lk/old" || fail "lock: a leftover lock (older than a minute) not taken over"
# The holder: taken over when it is gone, never by age alone while it runs (a
# slow sample); unlock removes only a lock still ours. ps is stubbed: T1 is the
# start time of every live pid.
# shellcheck disable=SC2154,SC2317,SC2329  # _agents_mypid sets me and sub; the stub is called by _agents_lock
(
    _agents_start() { kill -0 "$1" 2>/dev/null && echo T1; return 0; }
    sleep 0 & dead=$!; wait "$dead"
    hold() { mkdir "$lk/$1"; printf '%s\n' "$2" > "$lk/$1/holder"; touch -t 202001010000 "$lk/$1"; }
    _agents_lock "$lk/mine" || fail "lock: a free lock not taken"
    [[ "$(cat "$lk/mine/holder")" =~ ^[0-9]+\ T1$ ]] || fail "lock: holder not recorded: $(cat "$lk/mine/holder")"
    _agents_mypid me; [[ "$(cat "$lk/mine/holder")" == "$me T1" ]] || fail "lock: the holder is not this shell ($me)"
    _agents_unlock "$lk/mine"; [[ ! -e "$lk/mine" ]] || fail "unlock left a lock it holds"
    hold live "$$ T1"
    ! _agents_lock "$lk/live" || fail "lock: a live holder's lock, older than a minute, taken over"
    hold dead "$dead T1"
    _agents_lock "$lk/dead" || fail "lock: a dead holder's lock not taken over"
    [[ "$(cat "$lk/dead/holder")" == "$me T1" ]] || fail "lock: a taken-over lock does not name its new holder"
    hold reused "$$ T0"
    _agents_lock "$lk/reused" || fail "lock: a holder whose pid names another process now not taken over"
    hold unknown "$$ -"
    _agents_lock "$lk/unknown" || fail "lock: a holder with no start time, older than a minute, not taken over"
    hold fresh "$$ -"; touch "$lk/fresh"
    ! _agents_lock "$lk/fresh" || fail "lock: a fresh lock whose holder can't be checked taken over"
    _agents_lock "$lk/stolen" || fail "lock: stolen"
    printf '%s\n' "$$ T1" > "$lk/stolen/holder"   # another run took it over meanwhile
    _agents_unlock "$lk/stolen"; [[ -d "$lk/stolen" ]] || fail "unlock removed a lock another run holds"
    ( _agents_lock "$lk/sub" && _agents_mypid sub && [[ "$(cut -d' ' -f1 "$lk/sub/holder")" == "$sub" && "$sub" != "$me" ]] ) \
        || fail "lock: a subshell's lock names its parent"
)
_agents_stamp_age age "$lk/none" 1000; [[ "$age" == 1000 ]] || fail "stamp: a missing file is not long ago: $age"
printf 'junk\n' > "$lk/s"; _agents_stamp_age age "$lk/s" 1000; [[ "$age" == 1000 ]] || fail "stamp: a damaged file is not long ago: $age"
_agents_replace "$lk/s" 940 || fail "replace failed"
_agents_stamp_age age "$lk/s" 1000
[[ "$age" == 60 && "$(cat "$lk/s")" == 940 && ! -e "$lk/s.$$" ]] || fail "replace + stamp age: $age, $(cat "$lk/s")"
! _agents_replace "$lk/nodir/x" 1 || fail "replace into a missing directory succeeded"
pass "state files: one lock holder (pid and start in the lock), retries; a lock taken over only once its holder is gone (by age only when unknown), unlock only our own; epoch stamps; whole-file replace"

echo "All agents tests passed."
