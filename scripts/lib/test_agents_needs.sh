#!/bin/bash
# Unit tests for the Needs-you verdicts in bin/agents: agents_assess (evidence
# and a verdict per item), `agents why`, the json fields, auto-reap selection,
# cleanup events, and the SwiftBar menu built from them.
# Run: bash scripts/lib/test_agents_needs.sh  -> exit 0 on pass.
#
# Fixture `ps` text and files in a temp dir only: nothing real is signalled
# (the kill engine's signal step is a stub that records what it was asked).

# Tests change functions and PATH inside ( … ) on purpose, to stub one call.
# shellcheck disable=SC2030,SC2031,SC2317,SC2329
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/tuidev-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home" NO_COLOR=1 AGENTS_CONF="$tmp/none"
export AGENTS_RUN_DIR="$tmp/run" AGENTS_DATA_DIR="$tmp/data" AGENTS_TESTING=1   # AGENTS_NOW (below) is honored only so
mkdir -p "$HOME/.local/bin"

# shellcheck source=../../bin/agents disable=SC1091
. "$REPO_DIR/bin/agents"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "PASS: $1"; }

# --- Fixture: one claude session and what it runs, plus two orphans ---------------
# The files the polling loops watch, with modification times relative to a
# fixed "now" (09:00): done.output ended 5h ago with Claude Code's exit line,
# build.log has been quiet 1h30m mid-build, live.log changed 2m ago,
# fail.out ended 2h10m ago with a failed test, young.out ended 5m ago.
W="$tmp/w"; mkdir -p "$W"
printf 'building\nok\n[exited with code 0]\n\n' > "$W/done.output"
printf 'compiling 3/9\n' > "$W/build.log"
printf 'compiling...\n' > "$W/live.log"
printf '=== RUN TestX\n--- FAIL: TestX (0.01s)\n' > "$W/fail.out"
printf '[exited with code 1]\n' > "$W/young.out"
touch -t 202610140900 "$W/ref"
touch -t 202610140400 "$W/done.output"
touch -t 202610140730 "$W/build.log"
touch -t 202610140858 "$W/live.log"
touch -t 202610140650 "$W/fail.out"
touch -t 202610140855 "$W/young.out"
now="$(_agents_mtimes "$W/ref" | cut -f1)"
[[ "$now" =~ ^[0-9]+$ ]] || fail "_agents_mtimes: no mtime for a file: '$now'"
export AGENTS_NOW="$now"

snap_pre='/bin/zsh -c source /Users/NAME/.claude/shell-snapshots/s.sh 2>/dev/null || true && eval'
fixture="$(cat <<EOF
    1     0     0 root  0.0  20000 10:00.00 13-16:00:00 Wed Sep 30 16:57:15 2026     /sbin/launchd
 5000     1   501 me    1.0 300000  0:30.00 06:00:00 Wed Oct 14 03:00:00 2026     claude
 5010  5000   501 me    0.0   2000  0:00.10 05:10:00 Wed Oct 14 03:50:00 2026     $snap_pre 'F=$W/done.output; until tail -1 \$F | grep -qE "^(ok|FAIL)"; do sleep 5; done' < /dev/null && pwd -P >| /tmp/c1
 5011  5010   501 me    0.0    900  0:00.00 00:03 Wed Oct 14 08:59:57 2026     sleep 5
 5020  5000   501 me    0.0   2000  0:00.10 01:40:00 Wed Oct 14 07:20:00 2026     $snap_pre 'until grep -q "^built" $W/build.log; do sleep 10; done' < /dev/null && pwd -P >| /tmp/c2
 5030  5000   501 me    0.0   2000  0:00.10 03:00:00 Wed Oct 14 06:00:00 2026     $snap_pre 'while kill -0 4242 2>/dev/null; do sleep 5; done' < /dev/null && pwd -P >| /tmp/c3
 5040  5000   501 me    0.0   2000  0:00.10 02:00:00 Wed Oct 14 07:00:00 2026     $snap_pre 'until [ -s $W/missing.out ]; do sleep 5; done' < /dev/null && pwd -P >| /tmp/c4
 5050  5000   501 me    0.0   2000  0:00.10 05:00 Wed Oct 14 08:55:00 2026     $snap_pre 'until tail -1 $W/live.log | grep -q ready; do sleep 2; done' < /dev/null && pwd -P >| /tmp/c5
 5060  5000   501 me    0.3  80000  0:10.00 05:00:00 Wed Oct 14 04:00:00 2026     $snap_pre 'node dist/server.js' < /dev/null && pwd -P >| /tmp/c6
 5061  5060   501 me    0.3  80000  0:10.00 05:00:00 Wed Oct 14 04:00:00 2026     node dist/server.js
 5070  5000   501 me   12.0  50000  0:10.00 25:00 Wed Oct 14 08:35:00 2026     $snap_pre 'make test' < /dev/null && pwd -P >| /tmp/c7
 5080  5000   501 me    0.0   2000  0:00.10 02:30:00 Wed Oct 14 06:30:00 2026     $snap_pre 'until tail -1 $W/fail.out | grep -q PASS; do sleep 5; done' < /dev/null && pwd -P >| /tmp/c8
 5090  5000   501 me    0.0   2000  0:00.10 08:00 Wed Oct 14 08:52:00 2026     $snap_pre 'until tail -1 $W/young.out | grep -q ok; do sleep 5; done' < /dev/null && pwd -P >| /tmp/c9
 6000     1   501 me    0.0  97888  0:00.59 50:05 Wed Oct 14 08:10:00 2026     npm exec chrome-devtools-mcp@latest
 6001  6000   501 me    0.0 117280  0:00.43 50:04 Wed Oct 14 08:10:01 2026     chrome-devtools-mcp
 6100     1   501 me    0.5  80000  0:30.00 03:00:00 Wed Oct 14 06:00:00 2026     node /Users/NAME/work/app/node_modules/.bin/vite
EOF
)"
listen="$(printf '%s\n' '5061 3000' '6100 5173')"
# Read by the sourced functions.
# shellcheck disable=SC2034
AGENTS_UID=501 AGENTS_SELF=9999
recs="$(printf '%s\n' "$fixture" | agents_classify "$listen" "")"
# A sample saw the MCP helper 6000 under an agent before its session ended
# (sample.state: the provenance auto-reap needs); never the vite server 6100.
mkdir -p "$AGENTS_DATA_DIR"
printf '%s\n6000@Wed_Oct_14_08:10:00_2026\t1\t1\n6001@Wed_Oct_14_08:10:01_2026\t0\t1\n6100@Wed_Oct_14_06:00:00_2026\t30\t0\n' "$now" > "$AGENTS_DATA_DIR/sample.state"
watch="$(printf '%s\n' "$recs" | awk -F '\t' '$1 == "watch" { print $2 "\t" $3 }')"
[[ "$(printf '%s\n' "$watch" | cut -f1 | tr '\n' ' ')" == "5010 5020 5040 5050 5080 5090 " ]] || fail "watched loops: $(printf '%s\n' "$watch" | tr '\n' ' ')"

# The watched files' details: one stat, a tail per file, the last non-blank
# line, "-" for a file that is gone.
winfo="$(_agents_watch_info "$watch")"
wrow() { printf '%s\n' "$winfo" | awk -F '\t' -v p="$1" '$2 == p'; }
[[ "$(wrow 5010)" == "watched"$'\t'"5010"$'\t'"$W/done.output"$'\t'"$((now - 5 * 3600))"$'\t'"[exited with code 0]"$'\t'"read" ]] || fail "watched row: $(wrow 5010)"
[[ "$(wrow 5040)" == "watched"$'\t'"5040"$'\t'"$W/missing.out"$'\t-\t-\tread' ]] || fail "a missing file: $(wrow 5040)"
[[ "$(wrow 5080 | cut -f5)" == "--- FAIL: TestX (0.01s)" ]] || fail "last line of fail.out: $(wrow 5080)"
printf 'one\ttwo \033[32mok\033[0m\n   \n\n' > "$W/ctl.log"
[[ "$(_agents_last_line "$W/ctl.log")" == "one two  [32mok [0m" ]] || fail "control characters blanked, blank lines skipped: $(_agents_last_line "$W/ctl.log" | od -c | head -3)"
mkfifo "$W/fifo" 2>/dev/null && { [[ -z "$(_agents_last_line "$W/fifo")" ]] || fail "a FIFO was read"; }
pass "watched files: mtime from one stat, the last non-blank line from the file's tail, a gone file says so"

# Credential files are never read for a last line: by path, through a
# symlinked directory or file, in any case; their neighbours still are.
mkdir -p "$HOME/.ssh" "$HOME/.config/gh" "$HOME/.sshx"
printf 'PRIVATE KEY\n' > "$HOME/.ssh/id_x"; printf 'machine x password y\n' > "$HOME/.netrc"
printf 'oauth: t\n' > "$HOME/.config/gh/hosts.yml"; printf 'fine\n' > "$HOME/.sshx/log"; printf 'fine\n' > "$HOME/.netrc.log"
for f in "$HOME/.ssh/id_x" "$HOME/.netrc" "$HOME/.config/gh/hosts.yml"; do
    [[ -z "$(_agents_last_line "$f")" ]] || fail "a credential file was read: $f"
done
ln -s "$HOME/.ssh" "$W/sshdir"; ln -s "$HOME/.netrc" "$W/netrc-link"
[[ -z "$(_agents_last_line "$W/sshdir/id_x")" ]] || fail "a credential file read through a symlinked directory"
[[ -z "$(_agents_last_line "$W/netrc-link")" ]] || fail "a credential file read through a symlink"
_agents_cred_path "$HOME/.SSH/id_x" || fail "credential paths compared with case"
if _agents_cred_path "$HOME/.sshx/log" || _agents_cred_path "$HOME/.netrc.log"; then fail "a neighbour of a credential path refused"; fi
[[ "$(_agents_last_line "$HOME/.sshx/log")/$(_agents_last_line "$HOME/.netrc.log")" == "fine/fine" ]] || fail "a neighbour of a credential path not read"
[[ "$(_agents_watch_info "7001"$'\t'"$HOME/.ssh/id_x" | cut -f5)" == - ]] || fail "a watched credential file's last line reached the evidence"
pass "credential files (configs/sandbox/credential-paths.txt) are never read for a last line, even through symlinks"

# The enriched records, as agents_collect hands them on: the stuck flags come
# from the watched files' state relative to the same fixed now.
cwds="$(for p in 5000 5010 5020 5030 5040 5050 5060 5070 5080 5090; do printf '%s\t%s\n' "$p" "$HOME/work/myapp"; done; printf '6100\t%s\n' "$HOME/work/app")"
wstate="$(printf '%s\n' 5010 quiet 5020 quiet 5050 fresh 5080 quiet 5090 fresh | paste - -)"
herdr="$(printf 'claude\tworking\t%s\n' "$HOME/work/myapp")"
enr="$(printf '%s\n' "$recs" | agents_enrich "$cwds" "$herdr" "$wstate"; printf '%s\n' "$winfo")"
flags() { printf '%s\n' "$enr" | awk -F '\t' -v p="$1" '$1 == "act" && $2 == p { print $16 }'; }
[[ "$(flags 5010)/$(flags 5020)/$(flags 5030)/$(flags 5040)/$(flags 5050)/$(flags 5060)/$(flags 5070)/$(flags 5080)/$(flags 5090)" \
    == "wait,stuck/wait,stuck/wait,stuck/wait,stuck/wait/long/long/wait,stuck/wait" ]] || fail "fixture flags: $(for p in 5010 5020 5030 5040 5050 5060 5070 5080 5090; do printf '%s=%s ' "$p" "$(flags "$p")"; done)"

needs="$(printf '%s\n' "$enr" | agents_assess)"
nf() { printf '%s\n' "$needs" | awk -F '\t' -v p="$1" -v c="$2" '$1 == "need" && $2 == p { print $c }'; }
# FLAG ACTION CONF CODE AUTO
v() { printf '%s %s %s %s %s' "$(nf "$1" 4)" "$(nf "$1" 5)" "$(nf "$1" 6)" "$(nf "$1" 7)" "$(nf "$1" 8)"; }
ev() { printf '%s\n' "$needs" | awk -F '\t' -v p="$1" -v k="${2:-fact}" '$1 == "evid" && $2 == p && $3 == k { print $4 }'; }

[[ "$(printf '%s\n' "$needs" | awk -F '\t' '$1 == "need" { print $2 }' | sort -n | tr '\n' ' ')" == "5010 5020 5030 5040 5060 5070 5080 6000 6100 " ]] \
    || fail "items assessed: $(printf '%s\n' "$needs" | awk -F '\t' '$1 == "need" { print $2 }' | tr '\n' ' ')"
[[ "$(printf '%s\n' "$needs" | awk -F '\t' '$1 == "need" && NF != 20')" == "" ]] || fail "need rows have 20 columns"
[[ "$(printf '%s\n' "$needs" | awk -F '\t' '($1 == "need" || $1 == "evid") { for (i = 1; i <= NF; i++) if ($i == "") print }')" == "" ]] \
    || fail "an empty field (the menu reads tab-separated fields, which collapse)"
pass "assessed: stale trees and stuck, long or dup commands; plain waiting loops are not; no empty fields"

# Stale trees: a helper whose session ended is safe to stop; a server it left
# behind needs a check (it may be the one you use).
[[ "$(v 6000)" == "stale stop high session-ended 1" ]] || fail "stale helper: $(v 6000)"
[[ "$(nf 6000 11)" == "safe to stop — its session ended" && "$(nf 6000 10)" == "safe to stop" ]] || fail "stale helper verdict: $(nf 6000 11)"
[[ "$(nf 6000 9)" == - ]] || fail "a stale tree has an owner"
[[ "$(ev 6000)" == *"owner: none, its session ended"* ]] || fail "stale owner evidence: $(ev 6000)"
[[ "$(v 6100)" == "stale check medium server-orphan 0" ]] || fail "stale server: $(v 6100)"
[[ "$(nf 6100 11)" == "check first — a server on :5173, left behind when its session ended" ]] || fail "stale server verdict: $(nf 6100 11)"
[[ "$(ev 6100)" == *"listens on :5173"*"in ~/work/app"* ]] || fail "stale server evidence: $(ev 6100)"
[[ "$(ev 6100 auto)" == "auto-reap never stops this: it listens on a port"* ]] || fail "listener auto note: $(ev 6100 auto)"
pass "stale: a helper of an ended session is safe to stop (auto); a server it left behind is check first (never auto)"

# Stuck loops: a completion marker in the watched file, a quiet file, no file,
# a gone file.
[[ "$(v 5010)" == "stuck stop high finished 1" ]] || fail "stuck on a finished task: $(v 5010)"
[[ "$(nf 5010 11)" == "safe to stop — what it waits for already finished ([exited with code 0], 5h0m ago)" ]] || fail "finished verdict: $(nf 5010 11)"
[[ "$(nf 5010 9)/$(nf 5010 12)/$(nf 5010 13)" == "5000/claude/myapp" ]] || fail "owner columns: $(nf 5010 9)/$(nf 5010 12)/$(nf 5010 13)"
[[ "$(nf 5010 18)/$(nf 5010 19)/$(nf 5010 20)" == "18000/[exited with code 0]/1" ]] || fail "quiet/last/marker: $(nf 5010 18)/$(nf 5010 19)/$(nf 5010 20)"
e="$(ev 5010)"
[[ "$e" == *"owner: claude 5000 in myapp (working)"* ]] || fail "owner evidence: $e"
[[ "$e" == *"waiting 5h10m · 0% CPU"* ]] || fail "age evidence: $e"
[[ "$e" == *"last line: [exited with code 0] (a completion marker)"* && "$e" == *"file quiet for 5h0m"* ]] || fail "file evidence: $e"
[[ "$(ev 5010 next)" == *"look at it: tail -5 "*"/done.output"*"stop it: agents kill 5010@Wed_Oct_14_03:50:00_2026"* ]] || fail "next steps: $(ev 5010 next)"
[[ "$(ev 5010 auto)" == "auto-reap (AGENTS_AUTO_REAP=1) would stop this on its own" ]] || fail "auto note, off: $(ev 5010 auto)"
[[ "$(printf '%s\n' "$enr" | AGENTS_AUTO_REAP=1 agents_assess | awk -F '\t' '$1 == "evid" && $2 == 5010 && $3 == "auto" { print $4 }')" == "auto-reap is on: it stops this within a minute" ]] \
    || fail "auto note, on"
[[ "$(v 5080)" == "stuck stop high finished 1" && "$(nf 5080 11)" == *"(--- FAIL: TestX (0.01s), 2h10m ago)" ]] || fail "--- FAIL marker: $(v 5080) $(nf 5080 11)"
[[ "$(v 5020)" == "stuck stop high quiet 0" ]] || fail "stuck on a quiet file: $(v 5020)"
[[ "$(nf 5020 11)" == "safe to stop — nothing has written to the file it watches for 1h30m" && "$(nf 5020 20)" == 0 ]] || fail "quiet verdict: $(nf 5020 11)"
[[ "$(ev 5020 auto)" == *"quiet less than 2h0m (2 x AGENTS_WAIT_STUCK)" ]] || fail "not quiet long enough for auto: $(ev 5020 auto)"
[[ "$(v 5030)" == "stuck check medium age-only 0" ]] || fail "age-only stuck: $(v 5030)"
[[ "$(nf 5030 11)" == "check first — waiting 3h0m, with no file to judge by (age only)" ]] || fail "age-only verdict: $(nf 5030 11)"
[[ "$(ev 5030)" == *"watches no file agents can check"* && "$(ev 5030 auto)" == *"nothing but its age"* ]] || fail "age-only evidence: $(ev 5030)"
[[ "$(v 5040)" == "stuck check medium gone 0" && "$(ev 5040)" == *"which no longer exists"* ]] || fail "gone file: $(v 5040)"
pass "stuck loops: finished (completion marker) and quiet files are safe to stop; age-only and gone files are check first"

# Long commands: a dev server of a live session is check first; anything else
# long is informational. Neither is ever auto-reaped.
[[ "$(v 5060)" == "long check medium server 0" ]] || fail "long server: $(v 5060)"
[[ "$(nf 5060 11)" == "check first — dev server on :3000, its session is still active" ]] || fail "long server verdict: $(nf 5060 11)"
[[ "$(v 5070)" == "long info high long 0" && "$(nf 5070 11)" == "informational — running 25m; its session is still active" ]] || fail "long info: $(v 5070) $(nf 5070 11)"
[[ "$(ev 5070 auto)" == "auto-reap never stops this: it belongs to a live session and is not stuck" ]] || fail "long auto note: $(ev 5070 auto)"
pass "long: a dev server is check first, other long commands informational; never auto"

# One item on demand (agents why): an unflagged loop whose file is being
# written, and a young loop whose file already says it finished.
one() { printf '%s\n' "$enr" | agents_assess "$1" | awk -F '\t' '$1 == "need" { print $4, $5, $6, $7, $8 }'; }
[[ "$(one 5050)" == "wait leave high file-active 0" ]] || fail "a loop on a live file: $(one 5050)"
[[ "$(printf '%s\n' "$enr" | agents_assess 5050 | awk -F '\t' '$1 == "need" { print $11 }')" == "leave it — the file it watches changed 2m ago: something still writes it" ]] \
    || fail "file-active verdict"
[[ "$(one 5090)" == "wait check medium finished-young 0" ]] || fail "a young loop on a finished file: $(one 5090)"
[[ "$(one 5000)" == "agent info high session 0" ]] || fail "a session: $(one 5000)"
[[ "$(one 5011)" == "" ]] || fail "a loop's sleep is not something agents lists: $(one 5011)"
[[ "$(printf '%s\n' "$enr" | agents_assess 5010 | grep -c '^need')" == 1 ]] || fail "a target is judged once"
pass "on demand: a loop on a file still written is leave it; a young loop on a finished file is check first"

# Completion markers: what the loop waits for already happened.
mk() {   # LAST_LINE — the marker column for a stuck loop whose file ends so
    local rec
    rec="$(printf 'act\t7000\ttool\t7200\t0.0\t0.0\t100\t1\tX\t-\t5000\t-\t/w\tuntil tail -1 /w/x | grep -q ok; do sleep 5; done\tmain\twait,stuck\t1')"
    printf '%s\nwatched\t7000\t/w/x\t%s\t%s\n' "$rec" "$((now - 7200))" "$1" | agents_assess | awk -F '\t' '$1 == "need" { print $20 }'
}
for l in '[exited with code 0]' '[exited with code 137]' 'exit 1' 'Exited with code 2' 'Process exited with code 0' 'ok' \
         'ok  	github.com/x/y	0.31s' 'FAIL' 'FAIL	github.com/x/y [build failed]' 'PASS' '--- FAIL: TestX (0.00s)' '--- PASS: TestY' \
         '===== 3 passed in 0.12s =====' 'test result: ok. 4 passed' 'Done in 3.20s.' 'error: build failed' 'finished'; do
    [[ "$(mk "$l")" == 1 ]] || fail "not a completion marker: '$l'"
done
for l in 'compiling 3/9' 'waiting for server' 'okay so far' 'exiting soon' 'Listening on :3000' 'errors so far: 0' 'building'; do
    [[ "$(mk "$l")" == 0 ]] || fail "a completion marker: '$l'"
done
pass "completion markers: [exited with code N], exit N, ok/FAIL/PASS/--- FAIL, pytest/cargo summaries; not mid-run lines"

# A long or hostile last line: colors stripped, 80 characters, one line.
long_line="$(printf 'x%.0s' $(seq 1 200))"
lrow="$(printf 'act\t7000\ttool\t7200\t0.0\t0.0\t100\t1\tX\t-\t5000\t-\t/w\tuntil tail -1 /w/x | grep -q ok; do sleep 5; done\tmain\twait,stuck\t1\nwatched\t7000\t/w/x\t%s\t%s\n' "$((now - 7200))" "$long_line" | agents_assess)"
[[ "$(printf '%s\n' "$lrow" | awk -F '\t' '$1 == "need" { print length($19) }')" == 80 ]] || fail "last line not cut to 80"
crow="$(printf 'act\t7000\ttool\t7200\t0.0\t0.0\t100\t1\tX\t-\t5000\t-\t/w\tuntil tail -1 /w/x | grep -q ok; do sleep 5; done\tmain\twait,stuck\t1\nwatched\t7000\t/w/x\t%s\t%s\n' "$((now - 7200))" ' [32mok [0m ' | agents_assess)"
[[ "$(printf '%s\n' "$crow" | awk -F '\t' '$1 == "need" { print $19 "/" $20 }')" == "ok/1" ]] || fail "colored ok: $(printf '%s\n' "$crow" | awk -F '\t' '$1 == "need" { print $19 "/" $20 }')"
pass "last lines are tidied: terminal colors stripped, 80 characters"

# AGENTS_WAIT_STUCK=0: nothing is stuck, so nothing is auto-reaped as a loop.
[[ -z "$(printf '%s\n' "$enr" | AGENTS_WAIT_STUCK=0 agents_assess | awk -F '\t' '$1 == "need" && $4 == "stuck" && $8 == 1')" ]] \
    || fail "AGENTS_WAIT_STUCK=0 still auto-reaps loops"

# A loop that only tests whether a file exists (while [ -f lock ]) is not
# judged by how long the file has been quiet: check first, never auto. Its
# last line is not read.
printf 'secret\n' > "$W/lock"; touch -t 202610140300 "$W/lock"
pfix="$(printf '%s\n' \
    " 5000     1   501 me    1.0 300000  0:30.00 06:00:00 Wed Oct 14 03:00:00 2026     claude" \
    " 5500  5000   501 me    0.0   2000  0:00.10 05:30:00 Wed Oct 14 03:30:00 2026     $snap_pre 'while [ -f $W/lock ]; do sleep 5; done' < /dev/null && pwd -P >| /tmp/c1" \
    " 5510  5000   501 me    0.0   2000  0:00.10 05:30:00 Wed Oct 14 03:30:00 2026     $snap_pre 'until grep -q ok $W/lock; do sleep 5; done' < /dev/null && pwd -P >| /tmp/c2")"
precs="$(printf '%s\n' "$pfix" | agents_classify "" "")"
pwatch="$(printf '%s\n' "$precs" | awk -F '\t' '$1 == "watch" { print $2 "\t" $3 "\t" $4 }')"
[[ "$pwatch" == "5500"$'\t'"$W/lock"$'\t'"exists"$'\n'"5510"$'\t'"$W/lock"$'\t'"read" ]] || fail "watch modes: $pwatch"
pinfo="$(_agents_watch_info "$pwatch")"
[[ "$(printf '%s\n' "$pinfo" | awk -F '\t' '$2 == 5500 { print $5 "/" $6 }')" == "-/exists" ]] || fail "an exists-only loop's file was read: $pinfo"
pneeds="$( { printf '%s\n' "$precs" | agents_enrich "" "" "$(printf '5500\tquiet\n5510\tquiet')"; printf '%s\n' "$pinfo"; } | agents_assess)"
pv() { printf '%s\n' "$pneeds" | awk -F '\t' -v p="$1" '$1 == "need" && $2 == p { print $4, $5, $6, $7, $8 }'; }
[[ "$(pv 5500)" == "stuck check medium exists-only 0" ]] || fail "an exists-only stuck loop: $(pv 5500)"
[[ "$(printf '%s\n' "$pneeds" | awk -F '\t' '$1 == "evid" && $2 == 5500 && $3 == "auto" { print $4 }')" == *"only tests whether its file exists"* ]] \
    || fail "exists-only auto note: $pneeds"
[[ "$(printf '%s\n' "$pneeds" | awk -F '\t' '$1 == "evid" && $2 == 5500 && $4 ~ /^last line/')" == "" ]] || fail "an exists-only loop shows a last line"
[[ "$(pv 5510)" == "stuck stop high quiet 1" ]] || fail "a loop reading the same quiet file: $(pv 5510)"
pass "a loop that only tests a file's existence is check first and never auto; one that reads the file is judged by it"

# Auto-reap needs provenance: a stale tree no sample saw under an agent (your
# own nohup npx or caffeinate) is only probably safe, and never auto; nor is
# a caffeinate without -t; one with -t, seen under an agent, is.
srow() { printf 'stale\t%s\torphan\t3000\t0.0\t0.0\t9000\t0\t%s\t-\tme\t-\t-\t%s\t-\n' "$1" "$2" "$3"; }
(
    AGENTS_DATA_DIR="$tmp/prov"; mkdir -p "$AGENTS_DATA_DIR"
    printf '%s\n7200@S2\t0\t1\n7300@S3\t0\t1\n7400@S4\t0\t0\n' "$now" > "$AGENTS_DATA_DIR/sample.state"
    sn="$( { srow 7100 S1 'npx -y some-tool'; srow 7200 S2 'caffeinate -dims'; srow 7300 S3 'caffeinate -i -t 300'; srow 7400 S4 'npm exec x-mcp'; } | agents_assess)"
    sv() { printf '%s\n' "$sn" | awk -F '\t' -v p="$1" '$1 == "need" && $2 == p { print $4, $5, $6, $7, $8 }'; }
    sa() { printf '%s\n' "$sn" | awk -F '\t' -v p="$1" '$1 == "evid" && $2 == p && $3 == "auto" { print $4 }'; }
    [[ "$(sv 7100)" == "stale stop medium session-ended 0" ]] || fail "unproven stale: $(sv 7100)"
    [[ "$(printf '%s\n' "$sn" | awk -F '\t' '$1 == "need" && $2 == 7100 { print $11 }')" == "safe to stop — probably left by an agent session that ended" ]] \
        || fail "unproven stale verdict"
    [[ "$(sa 7100)" == *"no sample saw it under an agent"* && "$(sv 7400)" == "stale stop medium session-ended 0" ]] || fail "unproven auto note: $(sa 7100) / $(sv 7400)"
    [[ "$(sv 7200)" == "stale stop high session-ended 0" && "$(sa 7200)" == *"caffeinate without -t"* ]] || fail "caffeinate without -t: $(sv 7200) $(sa 7200)"
    [[ "$(sv 7300)" == "stale stop high session-ended 1" ]] || fail "proven caffeinate -t: $(sv 7300)"
    rm -f "$AGENTS_DATA_DIR/sample.state"
    [[ "$( { srow 7300 S3 'caffeinate -i -t 300'; } | AGENTS_HISTORY=0 agents_assess | awk -F '\t' '$1 == "evid" && $3 == "auto" { print $4 }')" == *"AGENTS_HISTORY=0"* ]] \
        || fail "no provenance without history"
)
pass "auto-reap provenance: unproven stale trees are probably safe, never auto; caffeinate without -t never auto"

# Ports that could not be listed: "no ports found" is not "no ports".
pf="$( { printf '%s\n' "$enr"; printf 'probe\tlisten\tfail\n'; } | agents_assess)"
[[ "$(printf '%s\n' "$pf" | awk -F '\t' '$1 == "need" && $2 == 6000 { print $4, $5, $6, $7, $8 }')" == "stale check medium ports-unknown 0" ]] \
    || fail "stale with the port check unavailable: $(printf '%s\n' "$pf" | awk -F '\t' '$1 == "need" && $2 == 6000')"
[[ "$(printf '%s\n' "$pf" | awk -F '\t' '$1 == "need" && $2 == 6000 { print $11 }')" == *"the port check was unavailable"* ]] || fail "ports-unknown verdict text"
[[ "$(printf '%s\n' "$pf" | agents_auto_tokens | cut -f1 | tr '\n' ' ')" == "5010@Wed_Oct_14_03:50:00_2026 5080@Wed_Oct_14_06:30:00_2026 " ]] \
    || fail "auto-reap with no port check: $(printf '%s\n' "$pf" | agents_auto_tokens)"
[[ "$( { printf '%s\n' "$enr"; printf 'probe\tlisten\tok\n'; } | agents_assess | agents_auto_tokens | grep -c '^6000@')" == 1 ]] || fail "probe ok lost the stale helper"
( _agents_listeners() { return 1; }; agents_snapshot() { printf '%s\n' "$fixture"; }; _agents_cwds() { :; }
  [[ "$(agents_collect | tail -1)" == "probe"$'\t'"listen"$'\t'"fail" ]] || fail "agents_collect: no probe fail row" )
( mkdir -p "$tmp/nolsof"; for b in awk cat; do ln -sf "$(command -v "$b")" "$tmp/nolsof/$b"; done
  if PATH="$tmp/nolsof" _agents_listeners >/dev/null; then fail "_agents_listeners succeeded with no lsof or ss"; fi )
pass "when listening ports can't be listed, stale trees are check first and auto-reap leaves them"

# --- Auto-reap: what it would and would not stop -----------------------------------
auto="$(printf '%s\n' "$needs" | agents_auto_tokens)"
[[ "$auto" == "5010@Wed_Oct_14_03:50:00_2026"$'\t'"stuck"$'\t'"claude:5000"$'\n'"5080@Wed_Oct_14_06:30:00_2026"$'\t'"stuck"$'\t'"claude:5000"$'\n'"6000@Wed_Oct_14_08:10:00_2026"$'\t'"stale"$'\t'"-" ]] \
    || fail "auto-reap tokens: $auto"
for p in 5020 5030 5040 5060 5070 6100 5050 5090; do
    [[ "$auto" != *"$p@"* ]] || fail "auto-reap would stop $p"
done
pass "auto-reap picks a stale helper and loops stuck on a file quiet 2 x AGENTS_WAIT_STUCK; never a listener, a long command, age-only or young"

# `agents reap --auto -n`: the plan, and nothing signalled.
plan_out="$(
    agents_collect() { printf '%s\n' "$enr"; }
    agents_snapshot() { printf '%s\n' "$fixture"; }
    _agents_cwds() { :; }
    _agents_signal() { echo "SIGNAL $*" >> "$tmp/signals"; }
    AGENTS_SELF=9999 AGENTS_UID=501 agents_main reap --auto -n 2>&1
)"
[[ "$plan_out" == *"5011"*"5010"*"5080"*"6001"*"6000"*"would send SIGTERM to 5 process(es)"* ]] || fail "reap --auto -n: $plan_out"
[[ "$plan_out" != *5020* && "$plan_out" != *5060* && "$plan_out" != *6100* ]] || fail "reap --auto -n plans too much: $plan_out"
[[ ! -e "$tmp/signals" && ! -e "$AGENTS_DATA_DIR/events.tsv" ]] || fail "a dry run signalled or logged"
pass "reap --auto -n plans only the auto-safe trees and signals nothing"

# A real auto run, against stubs: the signals go to a file, the trees count as
# gone at once, events are logged as auto with their reason, one notification.
mkdir -p "$tmp/osa"
# shellcheck disable=SC2016  # the stub's own $*
printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s"\n' "$tmp/osa.log" > "$tmp/osa/osascript"; chmod +x "$tmp/osa/osascript"
kill_env() {   # ARGS... — agents_main against the fixture, signals stubbed
    agents_collect() { echo x >> "$tmp/collects"; printf '%s\n' "$enr"; }
    agents_snapshot() { printf '%s\n' "$fixture"; }
    _agents_cwds() { local p; for p in "$@"; do [[ "$p" == 6000 ]] || printf '%s\t%s\n' "$p" "$HOME/work/myapp"; done; }
    _agents_signal() { echo "$1 $2" >> "$tmp/signals"; }
    _agents_alive() { :; }
    PATH="$tmp/osa:$PATH" AGENTS_SELF=9999 AGENTS_UID=501 agents_main "$@"
}
( kill_env reap --auto --notify >/dev/null 2>&1 )
[[ "$(sort "$tmp/signals" | tr '\n' ' ')" == "TERM 5010 TERM 5011 TERM 5080 TERM 6000 TERM 6001 " ]] || fail "auto-reap signals: $(tr '\n' ' ' < "$tmp/signals")"
evs="$(cut -f2- "$AGENTS_DATA_DIR/events.tsv" | sort)"
[[ "$evs" == "auto"$'\t'"stale"$'\t'"6000"$'\t'"npm"$'\t'"-"$'\t'"-"$'\n'"auto"$'\t'"stuck"$'\t'"5010"$'\t'"zsh"$'\t'"myapp"$'\t'"claude:5000"$'\n'"auto"$'\t'"stuck"$'\t'"5080"$'\t'"zsh"$'\t'"myapp"$'\t'"claude:5000" ]] \
    || fail "auto events: $evs"
[[ "$(grep -c 'display notification' "$tmp/osa.log")" == 1 ]] || fail "auto-reap: one notification: $(cat "$tmp/osa.log")"
grep -q 'Auto-reap stopped 3: ' "$tmp/osa.log" || fail "auto-reap notification text: $(cat "$tmp/osa.log")"
pass "auto-reap: PID@START kills of exactly those trees, an 'auto' event each with its reason, one notification"

# --throttle: at most once a minute.
rm -f "$tmp/signals"; : > "$tmp/collects"
throttled() { ( kill_env reap --auto --throttle >/dev/null 2>&1 ) || true; }
rm -f "$AGENTS_RUN_DIR/auto-reap"
throttled; throttled
[[ "$(grep -c . "$tmp/collects")" == 1 ]] || fail "--throttle ran twice within a minute: $(grep -c . "$tmp/collects")"
printf '%s\n' "$(( $(date +%s) - 61 ))" > "$AGENTS_RUN_DIR/auto-reap"
throttled
[[ "$(grep -c . "$tmp/collects")" == 2 ]] || fail "--throttle never ran again after a minute"
# Overlapping menu runs: while one holds the lock, another never starts.
printf '%s\n' "$(( $(date +%s) - 61 ))" > "$AGENTS_RUN_DIR/auto-reap"
mkdir "$AGENTS_RUN_DIR/auto-reap.lock"
throttled
[[ "$(grep -c . "$tmp/collects")" == 2 ]] || fail "--throttle ran while another run held the lock"
touch -t 202001010000 "$AGENTS_RUN_DIR/auto-reap.lock"
throttled
[[ "$(grep -c . "$tmp/collects")" == 3 && ! -e "$AGENTS_RUN_DIR/auto-reap.lock" ]] || fail "a leftover auto-reap lock was not cleared"
pass "reap --auto --throttle runs at most once a minute, one run at a time (lock)"

# Manual cleanups are logged too: kill (manual), reap (stale, stuck).
rm -f "$AGENTS_DATA_DIR/events.tsv" "$tmp/signals"
( kill_env kill -y 5070@Wed_Oct_14_08:35:00_2026 >/dev/null 2>&1 )
[[ "$(cut -f2-4 "$AGENTS_DATA_DIR/events.tsv")" == "kill"$'\t'"manual"$'\t'"5070" ]] || fail "kill event: $(cat "$AGENTS_DATA_DIR/events.tsv")"
rm -f "$AGENTS_DATA_DIR/events.tsv"
( kill_env reap -y --stuck >/dev/null 2>&1 )
[[ "$(cut -f2,3,4 "$AGENTS_DATA_DIR/events.tsv" | sort | tr '\n' ' ')" == "reap"$'\t'"stale"$'\t'"6000 reap"$'\t'"stale"$'\t'"6100 reap"$'\t'"stuck"$'\t'"5010 reap"$'\t'"stuck"$'\t'"5020 reap"$'\t'"stuck"$'\t'"5030 reap"$'\t'"stuck"$'\t'"5040 reap"$'\t'"stuck"$'\t'"5080 " ]] \
    || fail "reap events: $(cut -f2-4 "$AGENTS_DATA_DIR/events.tsv" | tr '\n' ' ')"
rm -f "$AGENTS_DATA_DIR/events.tsv"
( kill_env kill -n 5070 >/dev/null 2>&1 )
[[ ! -e "$AGENTS_DATA_DIR/events.tsv" ]] || fail "a dry-run kill logged an event"
_AGENTS_EV_KIND="" _agents_log_cleanups $'1\tx\t0\tp'
[[ ! -e "$AGENTS_DATA_DIR/events.tsv" ]] || fail "a caller that names no kind logs an event"
pass "events: kill manual, reap stale/stuck; dry runs and unnamed callers log nothing"

# --- agents why ------------------------------------------------------------------------
why() { ( agents_collect() { printf '%s\n' "$enr"; }; agents_main why "$@" ); }
out="$(why 5010@Wed_Oct_14_03:50:00_2026)"
[[ "$out" == "stuck polling loop · pid 5010@Wed_Oct_14_03:50:00_2026"$'\n'"  until tail -1 \$F | grep -qE \"^(ok|FAIL)\"; do sleep 5; done"* ]] || fail "why header: $out"
[[ "$out" == *$'\n'"verdict: safe to stop — what it waits for already finished ([exited with code 0], 5h0m ago)"$'\n'"confidence: high"$'\n'* ]] || fail "why verdict: $out"
[[ "$out" == *$'\n'"evidence:"$'\n'"  owner: claude 5000 in myapp (working)"$'\n'* ]] || fail "why evidence: $out"
[[ "$out" == *$'\n'"next:"$'\n'*"  stop it: agents kill 5010@Wed_Oct_14_03:50:00_2026"$'\n'"  auto-reap (AGENTS_AUTO_REAP=1) would stop this on its own" ]] || fail "why next: $out"
[[ "$(why 6100)" == "stale process (its session ended) · pid 6100@"*"verdict: check first"* ]] || fail "why by pid: $(why 6100)"
rc=0; why 5010@Mon_Jan_01_00:00:00_2024 >/dev/null 2>&1 || rc=$?; [[ $rc -eq 1 ]] || fail "why ignored a changed start time (rc $rc)"
rc=0; why 5011 >/dev/null 2>&1 || rc=$?; [[ $rc -eq 1 ]] || fail "why explained a process agents does not list (rc $rc)"
for bad in '' abc '5010@a b' '5010@x;y' -x; do
    rc=0; why "$bad" >/dev/null 2>&1 || rc=$?; [[ $rc -eq 2 ]] || fail "why accepted '$bad' (rc $rc)"
done
mkdir -p "$tmp/clip"; printf '#!/bin/bash\ncat > "%s"\n' "$tmp/clip.txt" > "$tmp/clip/pbcopy"; chmod +x "$tmp/clip/pbcopy"
( PATH="$tmp/clip:$PATH"; why --copy 5060 >/dev/null )
[[ "$(head -1 "$tmp/clip.txt")" == "long-running command · pid 5060@Wed_Oct_14_04:00:00_2026" ]] || fail "why --copy: $(cat "$tmp/clip.txt")"
pass "agents why: the item, the verdict and confidence, the evidence, next steps; refuses reused pids and bad tokens; --copy"

# --- agents json -----------------------------------------------------------------------
if command -v jq >/dev/null 2>&1; then
    j="$(_agents_with_needs "$enr" | agents_json)"
    printf '%s' "$j" | jq -e '.schema_version == 1' >/dev/null || fail "json does not parse: $j"
    printf '%s' "$j" | jq -e '
        (.stale[] | select(.pid == 6000) | .verdict.action == "stop" and .verdict.auto_reap == true and .evidence.session_ended == true and .evidence.owner == null)
        and (.stale[] | select(.pid == 6100) | .verdict.code == "server-orphan" and .evidence.ports == [5173] and .verdict.auto_reap == false)
        and (.agents[0].activity.tools[] | select(.pid == 5010) | .verdict.text == "safe to stop — what it waits for already finished ([exited with code 0], 5h0m ago)"
             and .verdict.confidence == "high" and .evidence.completion_marker == true and .evidence.watched_quiet_s == 18000
             and .evidence.last_line == "[exited with code 0]" and (.evidence.watched | endswith("/w/done.output"))
             and .evidence.owner == {"pid": 5000, "kind": "claude", "project": "myapp"} and (.evidence.lines | length) >= 4
             and (.evidence.next | map(select(startswith("stop it"))) | length) == 1)
        and (.agents[0].activity.tools[] | select(.pid == 5030) | .evidence.watched == null and .evidence.completion_marker == null and .verdict.code == "age-only")
        and (.agents[0].activity.tools[] | select(.pid == 5050) | has("verdict") | not)' >/dev/null \
        || fail "json verdict/evidence: $(printf '%s' "$j" | jq -c '[.stale[], .agents[0].activity.tools[]] | map({pid, verdict, evidence})')"
    pass "agents json: verdict and evidence on flagged stale trees and commands only (additive, schema 1)"
else
    echo "SKIP: jq not installed: json fields not checked"
fi

# agents tsv: verdict rows first (the menu needs them before the items), the
# auto-reap setting among the conf rows.
tsv_out="$( agents_collect() { printf '%s\n' "$enr"; }; AGENTS_AUTO_REAP=1 agents_tsv 2>/dev/null )"
[[ "$(printf '%s\n' "$tsv_out" | head -1 | cut -f1)" == need ]] || fail "tsv does not start with verdict rows: $(printf '%s\n' "$tsv_out" | head -1)"
[[ "$(printf '%s\n' "$tsv_out" | awk -F '\t' '$1 == "need" { n = NR } $1 == "agent" && !a { a = NR } END { print (n < a) }')" == 1 ]] || fail "tsv: verdicts after the records"
[[ "$tsv_out" == *$'\n'"conf"$'\t'"AGENTS_AUTO_REAP"$'\t'"1"* ]] || fail "tsv lacks conf AGENTS_AUTO_REAP"
pass "agents tsv: verdict rows first, then the records; conf carries AGENTS_AUTO_REAP"

# --- The SwiftBar menu -----------------------------------------------------------------
# A stub `agents` replays a tsv (verdict rows first, as agents_tsv prints them)
# and logs any other call.
# shellcheck disable=SC2016  # $1 and $* belong to the stub
printf '#!/bin/bash\nif [[ "$1" == tsv ]]; then cat "%s"; else printf "%%s\\n" "$*" >> "%s"; fi\n' "$tmp/tsv" "$tmp/calls" > "$HOME/.local/bin/agents"
chmod +x "$HOME/.local/bin/agents"
plugin() {   # RECORDS EXTRA — the menu for that snapshot
    { _agents_with_needs "$1"; printf '%s\n' "$2"; } > "$tmp/tsv"
    bash "$REPO_DIR/configs/swiftbar/agents.10s.sh"
}
T5010="5010@Wed_Oct_14_03:50:00_2026"
ORANGE_DOT="sfconfig=eyJyZW5kZXJpbmdNb2RlIjoiUGFsZXR0ZSIsImNvbG9ycyI6WyIjRkY5RjBBIl19"
GRAY_DOT="sfconfig=eyJyZW5kZXJpbmdNb2RlIjoiUGFsZXR0ZSIsImNvbG9ycyI6WyIjOEU4RTkzIl19"
menu="$(plugin "$enr" $'conf\tAGENTS_AUTO_REAP\t0')"
[[ "$menu" == *$'\n'"Needs you (7) | size=12"$'\n'* ]] || fail "Needs you count: $(printf '%s\n' "$menu" | grep 'Needs you')"
[[ "$menu" == *$'\n'"myapp: until tail -1 \$F ¦ grep -qE \"^(ok¦FAIL)\"; do sleep 5; done · stuck 5h10m · safe to stop | sfimage=hourglass $ORANGE_DOT refresh=true symbolize=false"$'\n'* ]] \
    || fail "stuck item line: $(printf '%s\n' "$menu" | grep 'stuck 5h10m')"
sub="$(printf '%s\n' "$menu" | awk '/stuck 5h10m · safe to stop/ { on = 1; next } on && /^--/ { print; next } on { exit }')"
[[ "$sub" == "--Jump to session | bash=\""*"\" terminal=false param1=jump param2=--notify param3=$T5010 sfimage=arrow.up.forward.app"$'\n'"--safe to stop — what it waits for already finished ([exited with code 0], 5h0m ago) | refresh=true sfimage=checkmark.circle symbolize=false"$'\n'* ]] \
    || fail "Jump to session, then the verdict, first in the submenu: $sub"
[[ "$sub" == *$'\n'"--owner: claude 5000 in myapp (working) | symbolize=false"$'\n'* && "$sub" == *$'\n'"--last line: [exited with code 0] (a completion marker) | symbolize=false"$'\n'* ]] \
    || fail "evidence in the submenu: $sub"
[[ "$sub" == *$'\n'"--auto-reap (AGENTS_AUTO_REAP=1) would stop this on its own | symbolize=false"$'\n'"-----"$'\n'* ]] || fail "auto note, then a separator: $sub"
[[ "$sub" == *$'\n'"--Stop command… | bash=\""*"\" terminal=false refresh=true param1=kill param2=--confirm-gui param3=--notify param4=$T5010 sfimage=xmark.octagon"$'\n'* ]] \
    || fail "Stop command… still asks first: $sub"
[[ "$sub" == *$'\n'"--Copy details | bash=\""*"\" terminal=false param1=why param2=--copy param3=$T5010 sfimage=doc.on.doc"$'\n'* ]] || fail "Copy details: $sub"
[[ "$sub" == *$'\n'"--Show session | bash=\""*"\" param1=open-term terminal=false param2=--hold param3=ps param4=5000 sfimage=terminal"$'\n'"--Details | "*"param2=show param3=--watch param4=$T5010 sfimage=info.circle" ]] || fail "Show session, Details: $sub"
[[ "$sub" != *"look at it"* && "$sub" != *"stop it:"* ]] || fail "next steps (why only) leaked into the menu: $sub"
[[ "$menu" == *$'\n'"myapp: node dist/server.js · running 5h0m · check first | sfimage=clock $ORANGE_DOT refresh=true symbolize=false"$'\n'"--Jump to session | "*$'\n'"--check first — dev server on :3000, its session is still active | refresh=true sfimage=questionmark.circle"* ]] \
    || fail "long server: $(printf '%s\n' "$menu" | grep -A1 'server.js · running')"
[[ "$menu" == *$'\n'"myapp: make test · running 25m · informational | sfimage=clock $GRAY_DOT refresh=true symbolize=false"$'\n'* ]] || fail "informational long is gray: $(printf '%s\n' "$menu" | grep 'make test · running')"
[[ "$menu" == *$'\n'"myapp: while kill -0 4242 2>/dev/null; do sleep 5; done · stuck 3h0m · check first | "* ]] || fail "age-only stuck: $(printf '%s\n' "$menu" | grep 'kill -0')"
[[ "$menu" == *$'\n'"npm exec chrome-devtools-mcp@latest · 50m · 210M · safe to stop | "*$'\n'"--orphan · pid 6000 | symbolize=false"$'\n'"--safe to stop — its session ended | "* ]] \
    || fail "stale helper with its verdict: $(printf '%s\n' "$menu" | grep -A2 '^npm exec')"
[[ "$menu" == *$'\n'"--Kill tree | bash="*" param1=kill param2=-y param3=--notify param4=6000@Wed_Oct_14_08:10:00_2026 sfimage=xmark.octagon"$'\n'"--Copy details | "*"param3=6000@Wed_Oct_14_08:10:00_2026 "* ]] \
    || fail "stale: Kill tree, then Copy details"
[[ "$menu" == *"node /Users/NAME/work/app/node_modules/.bin/vite · 3h0m · 78M · check first | "* ]] || fail "stale server: $(printf '%s\n' "$menu" | grep 'vite')"
[[ "$(printf '%s\n' "$menu" | grep -c 'Show session')" == 7 ]] || fail "Show session on each live-session item (and never on a stale one): $(printf '%s\n' "$menu" | grep -c 'Show session')"
pass "menu: each Needs-you item shows its verdict; its submenu the evidence, then Stop, Copy details, Show session"

# Every action is a known command with plain arguments; no process text ever
# reaches a param (a hostile last line included).
check_params() {   # MENU
    printf '%s\n' "$1" | awk -v a="\"$HOME/.local/bin/agents\"" -v s="\"$REPO_DIR/configs/swiftbar/agents.10s.sh\"" '
        { n = gsub(/\|/, "|") }
        n > 1 { print "two separators: " $0; next }
        n == 1 {
            p = substr($0, index($0, "|") + 1)
            gsub(a, "AGENTS", p); gsub(s, "SELF", p)
            if (p !~ /^( +[a-z0-9]+=[A-Za-z0-9.#,_:@+-]+)+ *$/) print "unsafe params: " $0
            if (p ~ /bash=AGENTS/) {
                q = p; sub(/.*param1=/, "", q); sub(/ .*/, "", q)
                if (q !~ /^(kill|term|reap|why|open-term|copy-path|reveal|awake|config|jump)$/) print "unknown subcommand: " $0
                if (q == "why" && p !~ / param2=--copy param3=[0-9]+@[A-Za-z0-9_:]+( |$)/) print "bad why: " $0
                if (q == "open-term" && p ~ /param3=ps/ && p !~ / param4=[0-9]+( |$)/) print "bad Show session: " $0
            }
        }'
}
[[ -z "$(check_params "$menu")" ]] || fail "menu params: $(check_params "$menu")"
hostile='-- | bash=/bin/sh param1=-c param2=id "x\" ¦ :skull: --- FAIL'
hrec="$(printf 'agent\t5000\tclaude\t21600\t1.0\t1.0\t300000\t3\tWed_Oct_14_03:00:00_2026\t-\tme\t-\t/w\tclaude\tmyapp\nact\t7000\ttool\t7200\t0.0\t0.0\t100\t1\tWed_Oct_14_07:00:00_2026\t-\t5000\t-\t/w\tuntil tail -1 /w/x | grep -q ok; do sleep 5; done\tmain\twait,stuck\t1\nwatched\t7000\t/w/x | bash=/bin/sh\t%s\t%s' "$((now - 9000))" "$hostile")"
hmenu="$(plugin "$hrec" "")"
[[ -z "$(check_params "$hmenu")" ]] || fail "a hostile last line or path reached a param: $(check_params "$hmenu")"
[[ "$hmenu" == *$'\n'"--last line: -- ¦ bash=/bin/sh param1=-c param2=id \"x\\\" ¦ :skull: --- FAIL (a completion marker) | symbolize=false"* || \
   "$hmenu" == *$'\n'"--last line: -- ¦ bash=/bin/sh param1=-c param2=id \"x\\\" ¦ :skull: --- FAIL | symbolize=false"* ]] \
    || fail "hostile last line shown as text: $(printf '%s\n' "$hmenu" | grep 'last line')"
pass "menu actions are known commands with plain PID@START/pid arguments; a hostile last line stays text"

# Auto-reap from the menu: only with AGENTS_AUTO_REAP=1 and something it may
# stop, in the background, throttled by agents.
rm -f "$tmp/calls"
plugin "$enr" $'conf\tAGENTS_AUTO_REAP\t0' >/dev/null
sleep 0.3; [[ ! -e "$tmp/calls" ]] || fail "auto-reap ran with AGENTS_AUTO_REAP=0: $(cat "$tmp/calls")"
plugin "$enr" $'conf\tAGENTS_AUTO_REAP\t1' >/dev/null
for _ in 1 2 3 4 5 6 7 8 9 10; do [[ -s "$tmp/calls" ]] && break; sleep 0.1; done
[[ "$(cat "$tmp/calls" 2>/dev/null)" == "reap --auto --throttle --notify" ]] || fail "menu auto-reap call: $(cat "$tmp/calls" 2>/dev/null)"
rm -f "$tmp/calls"
calm="$(printf '%s\n' "$enr" | awk -F '\t' '$1 == "agent" || ($1 == "act" && $2 == 5070)')"
plugin "$calm" $'conf\tAGENTS_AUTO_REAP\t1' >/dev/null
sleep 0.3; [[ ! -e "$tmp/calls" ]] || fail "auto-reap ran with nothing safe to stop: $(cat "$tmp/calls")"
pass "menu: auto-reap runs in the background only with AGENTS_AUTO_REAP=1 and something safe to stop"

# An older agents without verdict rows: the plain menu, unchanged.
{ printf '%s\n' "$enr"; } > "$tmp/tsv"
old="$(bash "$REPO_DIR/configs/swiftbar/agents.10s.sh")"
[[ "$old" == *$'\n'"myapp: until tail -1 \$F ¦ grep -qE \"^(ok¦FAIL)\"; do sleep 5; done · stuck 5h10m | sfimage=hourglass $ORANGE_DOT refresh=true symbolize=false"$'\n'"--Stop command… | "* ]] \
    || fail "menu without verdicts: $(printf '%s\n' "$old" | grep -A1 'stuck 5h10m')"
[[ "$old" != *"Copy details"* ]] || fail "Copy details without a verdict"
pass "menu without verdict rows (an older agents) keeps the plain Needs-you lines"

# The menu's budget: verdicts cost one awk pass, nothing per item.
t0="$(date +%s)"
for _ in 1 2 3 4 5; do plugin "$enr" "" >/dev/null; done
[[ $(( $(date +%s) - t0 )) -le 10 ]] || fail "five menu renders took more than 10 s"
pass "five menu renders with verdicts within budget"

echo "All agents needs tests passed."
