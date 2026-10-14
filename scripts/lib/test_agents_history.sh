#!/bin/bash
# Unit tests for bin/agents job types, history sampling, `agents report` and
# the menu's Where the CPU goes section.
# Run: bash scripts/lib/test_agents_history.sh  -> exit 0 on pass.
#
# Everything runs against fixture `ps` text, a fixed clock and temp dirs:
# nothing real is sampled, except one live smoke test where `ps` works.

# Tests change variables inside ( … ) on purpose, for one call; the settings
# they set are read by the sourced bin/agents, and the stubs (date,
# agents_snapshot…) are called by it.
# shellcheck disable=SC2030,SC2031,SC2034,SC2329
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/tuidev-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home" NO_COLOR=1 AGENTS_CONF="$tmp/none.conf" AGENTS_DATA_DIR="$tmp/data" AGENTS_RUN_DIR="$tmp/run"
export AGENTS_TESTING=1 AGENTS_NO_HERDR=1
mkdir -p "$HOME"

# shellcheck source=../../bin/agents disable=SC1091
. "$REPO_DIR/bin/agents"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "PASS: $1"; }
# The fixtures' user is uid 501 ("me"); this process is pid 9999, outside them.
AGENTS_UID=501 AGENTS_SELF=9999

# A fixed clock: `date` answers from FAKE_NOW / FAKE_DAY for the formats
# bin/agents asks for, and falls through to the real one otherwise.
FAKE_NOW=1760400000 FAKE_DAY=2026-10-14
date() {
    case "$*" in
        '+%s %Y-%m-%d') echo "$FAKE_NOW $FAKE_DAY" ;;
        '+%s %z')       echo "$FAKE_NOW +0000" ;;
        +%s)            echo "$FAKE_NOW" ;;
        *)              command date "$@" ;;
    esac
}

# psl PID PPID PCPU RSS CPUTIME ETIME HH:MM:SS ARGS — one `ps` fixture line.
psl() { printf '%5s %5s   501 me    %5s %7s %10s %11s Wed Oct 14 %s 2026     %s\n' "$@"; }
# cc CMD — a Claude Code tool shell running CMD.
cc() { printf "/bin/zsh -c source /Users/NAME/.claude/shell-snapshots/snapshot-zsh-1-x.sh 2>/dev/null || true && eval '%s' < /dev/null && pwd -P >| /tmp/cwd-1" "$1"; }

# 1. Job classification.
fixture="$(
    psl 1 0 0.0 20000 10:00.00 13-16:00:00 08:00:00 /sbin/launchd
    psl 90 1 0.0 3000 0:00.10 05:00:00 04:00:00 -zsh
    psl 100 90 5.0 600000 1:00.00 01:00:00 08:00:00 claude
    psl 101 100 0.0 3000 0:00.10 02:00 08:58:00 "$(cc 'cd /Users/NAME/repo && go test ./... 2>&1 | tail -30')"
    psl 102 101 1.0 90000 0:01.00 02:00 08:58:00 "go test ./..."
    psl 103 102 99.0 180000 1:50.00 01:55 08:58:05 "/tmp/go-build1/b001/web.test -test.paniconexit0"
    psl 104 102 50.0 80000 0:20.00 00:30 08:59:30 "/usr/local/go/pkg/tool/darwin_arm64/compile -o /tmp/x.a"
    psl 110 100 0.0 3000 0:00.10 01:00 08:59:00 "$(cc 'uv run pytest -q tests/')"
    psl 111 100 0.0 3000 0:00.10 01:00 08:59:00 "$(cc 'pnpm test')"
    psl 112 111 30.0 90000 0:10.00 01:00 08:59:00 "node /Users/NAME/repo/node_modules/.bin/vitest run"
    psl 113 100 0.0 3000 0:00.10 01:00 08:59:00 "$(cc 'cargo test --workspace')"
    psl 114 100 0.0 3000 0:00.10 01:00 08:59:00 "$(cc 'make test')"
    psl 120 100 0.0 3000 0:00.10 01:00 08:59:00 "$(cc 'cargo build --release')"
    psl 121 100 0.0 3000 0:00.10 01:00 08:59:00 "$(cc 'GOOS=linux go build ./...')"
    psl 122 100 0.0 3000 0:00.10 01:00 08:59:00 "$(cc 'npx tsc --noEmit')"
    psl 123 100 0.0 3000 0:00.10 01:00 08:59:00 "$(cc 'npm run build')"
    psl 124 123 20.0 90000 0:05.00 01:00 08:59:00 "node /Users/NAME/repo/node_modules/.bin/vite build"
    psl 125 100 0.0 3000 0:00.10 01:00 08:59:00 "$(cc 'make -j8')"
    psl 126 100 0.0 3000 0:00.10 01:00 08:59:00 "$(cc 'next build')"
    psl 130 100 0.0 3000 0:00.10 30:00 08:30:00 "$(cc 'npm run dev')"
    psl 131 130 2.0 90000 0:05.00 30:00 08:30:00 "node /Users/NAME/repo/node_modules/.bin/vite"
    psl 132 131 0.5 20000 0:01.00 30:00 08:30:00 "/Users/NAME/repo/node_modules/@esbuild/darwin-arm64/bin/esbuild --service=0.21.5 --ping"
    psl 133 100 0.0 3000 0:00.10 30:00 08:30:00 "$(cc 'node dist/server.js')"
    psl 134 100 0.0 3000 0:00.10 30:00 08:30:00 "$(cc 'make serve')"
    psl 135 100 0.0 3000 0:00.10 30:00 08:30:00 "bash -lc 'next dev -p 3000'"
    psl 140 100 0.0 90000 0:00.50 01:00:00 08:00:01 "npm exec chrome-devtools-mcp@latest"
    psl 141 140 0.0 110000 0:00.40 01:00:00 08:00:02 "node /Users/NAME/.npm/_npx/abc/node_modules/chrome-devtools-mcp/build/index.js"
    psl 142 141 8.0 300000 0:30.00 01:00:00 08:00:03 "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome --remote-debugging-pipe --user-data-dir=/tmp/p"
    psl 143 142 4.0 200000 0:20.00 01:00:00 08:00:03 "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Versions/1/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer) --type=renderer"
    psl 144 100 0.0 3000 0:00.10 01:00 08:59:00 "$(cc 'npx playwright test')"
    psl 145 144 40.0 150000 0:20.00 01:00 08:59:00 "/Users/NAME/Library/Caches/ms-playwright/chromium_headless_shell-1187/chrome-mac/headless_shell --headless"
    psl 150 100 0.0 1900 0:00.00 01:00 08:59:00 "caffeinate -i -t 300"
    psl 151 100 0.0 2000 0:00.10 52:00 08:08:00 "$(cc 'until [ -s /tmp/x ]; do sleep 5; done')"
    psl 152 151 0.0 1000 0:00.00 00:02 08:59:58 "sleep 5"
    psl 153 100 0.0 2000 0:00.10 00:02 08:59:58 "$(cc 'git status')"
    psl 154 100 0.0 2000 0:00.10 03:00 08:57:00 "bash -lc 'claude -p hi'"
    psl 155 154 2.0 300000 0:03.00 03:00 08:57:00 "claude -p hi"
    psl 156 155 0.0 3000 0:00.10 01:00 08:59:00 "$(cc 'go vet ./...')"
    psl 157 100 0.0 50000 0:00.10 01:00:00 08:00:01 "node /Users/NAME/.local/lib/example-agent-mcp.cjs"
    psl 158 100 0.0 3000 0:00.10 01:00 08:59:00 "$(cc 'just test')"
    psl 200 1 0.0 90000 0:00.50 50:00 08:10:00 "npm exec @playwright/mcp@latest"
    psl 201 200 0.0 80000 0:00.40 50:00 08:10:00 "node /Users/NAME/.npm/_npx/def/node_modules/@playwright/mcp/cli.js"
    psl 202 201 3.0 150000 0:10.00 50:00 08:10:00 "/Users/NAME/Library/Caches/ms-playwright/chromium-1187/chrome-mac/chrome-headless-shell --headless"
)"
recs="$(printf '%s\n' "$fixture" | AGENTS_SELF=9999 AGENTS_UID=501 AGENTS_JOBS_PROC=1 agents_classify "" "")"
job_of() { printf '%s\n' "$recs" | awk -F '\t' -v p="$1" '$1 == "jp" && $2 == p { print $5 }'; }
for pair in 100:agent 101:test 102:test 103:test 104:test 110:test 111:test 112:test 113:test 114:test \
    120:build 121:build 122:build 123:build 124:build 125:build 126:build \
    130:server 131:server 132:server 133:server 134:server 135:server \
    140:mcp 141:mcp 142:browser 143:browser 144:test 145:browser 157:mcp \
    150:other 151:wait 152:wait 153:other 154:other 155:agent 156:build 158:other \
    200:mcp 201:mcp 202:browser; do
    got="$(job_of "${pair%%:*}")"
    [[ "$got" == "${pair#*:}" ]] || fail "job of pid ${pair%%:*}: '$got', want ${pair#*:}"
done
[[ -z "$(job_of 1)$(job_of 90)" ]] || fail "processes outside agent and stale trees got a job"
pass "jobs: test, build, server, browser, mcp, agent, wait, other from representative command lines"
pass "jobs: descendants share their command's job (go test's compile and test binary); browsers and agents keep their own"

# The job records: one per unit and job, with the root, its kind and the unit.
jrow() { printf '%s\n' "$recs" | awk -F '\t' -v u="$1" -v j="$2" '$1 == "job" && $11 == u && $3 == j'; }
row="$(jrow 101 test)"
[[ "$(cut -f2 <<<"$row")/$(cut -f5 <<<"$row")/$(cut -f8 <<<"$row")/$(cut -f10 <<<"$row")/$(cut -f12 <<<"$row")" == "100/150.0/4/own/claude" ]] \
    || fail "job record of go test's unit: $row"
row="$(jrow 140 browser)"
[[ "$(cut -f5 <<<"$row")/$(cut -f10 <<<"$row")" == "12.0/sub" ]] || fail "MCP's browser record: $row"
row="$(jrow 200 mcp)"
[[ "$(cut -f2 <<<"$row")/$(cut -f12 <<<"$row")/$(cut -f10 <<<"$row")" == "200/-/own" ]] || fail "stale tree's job record: $row"
[[ -z "$(printf '%s\n' "$fixture" | AGENTS_SELF=9999 AGENTS_UID=501 agents_classify "" "" | awk -F '\t' '$1 == "jp"')" ]] \
    || fail "per-process jp lines without AGENTS_JOBS_PROC"
pass "job records: per unit and job, own vs. sub, root kind (- for a stale tree)"

# Your own patterns are appended to the built-in ones, and validated.
(
    AGENTS_JOB_TEST='(^| )just test( |$)'; _agents_job_env
    got="$(printf '%s\n' "$fixture" | AGENTS_SELF=9999 AGENTS_UID=501 AGENTS_JOBS_PROC=1 agents_classify "" "" | awk -F '\t' '$1 == "jp" && $2 == 158 { print $5 }')"
    [[ "$got" == test ]] || fail "AGENTS_JOB_TEST not applied: $got"
)
_agents_conf_valid AGENTS_JOB_BUILD '(^| )just build( |$)' || fail "a good job pattern rejected"
_agents_conf_valid AGENTS_JOB_BUILD '' || fail "an empty job pattern rejected"
! _agents_conf_valid AGENTS_JOB_BUILD '(unclosed' || fail "a pattern that does not compile accepted"
! _agents_conf_valid AGENTS_JOB_BUILD $'tab\there' || fail "a pattern with a tab accepted"
# Checked by the awk that uses it: bash's regcomp may take [[:<:]] (macOS),
# while awk only warns about it on stderr and exits 0.
! _agents_conf_valid AGENTS_JOB_BUILD '[[:<:]]foo' || fail "a pattern awk can't compile ([[:<:]]) accepted"
_agents_conf_valid AGENTS_JOB_TEST '(^| )(just|task) test( |$)|[.]spec[.]ts$' || fail "a normal ERE rejected"
[[ "$(AGENTS_JOB_TEST='[[:<:]]foo' bash "$REPO_DIR/bin/agents" config 2>&1 | grep -c 'bad AGENTS_JOB_TEST')" == 1 ]] \
    || fail "a bad AGENTS_JOB_TEST in the environment is not reported"
printf 'AGENTS_JOB_SERVER="(^| )foreman start( |$)"\nAGENTS_JOB_MCP=(broken\n' > "$tmp/jobs.conf"
out="$(AGENTS_CONF="$tmp/jobs.conf" bash "$REPO_DIR/bin/agents" config 2>"$tmp/jobs.err")"
[[ "$out" == *'AGENTS_JOB_SERVER=(^| )foreman start( |$)'* ]] || fail "job pattern from the config file: $out"
grep -q 'bad value for AGENTS_JOB_MCP' "$tmp/jobs.err" || fail "a broken job pattern in the config file is not reported"
pass "AGENTS_JOB_<JOB> patterns extend the defaults; broken ones are reported and ignored"

# agents json: each entry's job, and the jobs summary.
cwds="$(printf '%s\t%s\n' 100 /Users/NAME/repo 200 "$HOME/repo" 101 /Users/NAME/repo)"
enr="$(printf '%s\n' "$recs" | agents_enrich "$cwds" "")"
[[ -n "$(printf '%s\n' "$enr" | awk -F '\t' '$1 == "job" && $2 == 100 && $15 == "repo"')" ]] || fail "job records do not carry the root's project"
json="$(printf '%s\n' "$enr" | agents_json)"
if command -v jq >/dev/null 2>&1; then
    printf '%s' "$json" | jq -e '.agents[0].job == "agent"' >/dev/null || fail "json: agent job"
    printf '%s' "$json" | jq -e '[.agents[0].activity.tools[] | select(.pid == 101) | .job] == ["test"]' >/dev/null || fail "json: tool job"
    printf '%s' "$json" | jq -e '[.agents[0].activity.mcp[] | select(.name == "chrome-devtools-mcp") | .job] == ["mcp"]' >/dev/null || fail "json: mcp job"
    printf '%s' "$json" | jq -e '.agents[0].activity.child_sessions[0].job == "agent"' >/dev/null || fail "json: nested session job"
    printf '%s' "$json" | jq -e '.stale[0].job == "mcp"' >/dev/null || fail "json: stale job"
    printf '%s' "$json" | jq -e '.jobs[0].job == "test" and (.jobs[0].sessions[0].project == "repo") and (.jobs | map(.job) | index("browser") != null)' >/dev/null \
        || fail "json: jobs summary $(printf '%s' "$json" | jq -c .jobs)"
    printf '%s' "$json" | jq -e '[.jobs[] | select(.job == "mcp") | .sessions[] | select(.kind == null)] | length == 1' >/dev/null || fail "json: a stale tree's kind is not null"
    pass "agents json: job on agents, tools, MCP servers, nested sessions and stale trees; jobs summary (checked with jq)"
else
    [[ "$json" == *'"jobs":[{"job":"test"'* ]] || fail "json jobs summary: $json"
    pass "agents json: jobs summary (jq not installed: shape only)"
fi

# 2. Sampling: cputime deltas across samples, keyed by pid@start.
agents_snapshot() { cat "$tmp/snap"; }
_agents_keep_pids() { :; }
_agents_cwds() { local p; for p in "$@"; do case "$p" in 300|500) printf '%s\t%s\n' "$p" /Users/NAME/code/app ;; 400) printf '%s\t%s\n' "$p" /Users/NAME/code/svc ;; esac; done; }
{
    psl 1 0 0.0 20000 10:00.00 13-16:00:00 08:00:00 /sbin/launchd
    psl 290 1 0.0 3000 0:00.10 05:00:00 04:00:00 -zsh
    psl 300 290 5.0 600000 1:00.00 01:00:00 08:00:00 claude
    psl 301 300 0.0 3000 0:00.10 05:00 08:55:00 "$(cc 'go test ./...')"
    psl 302 301 99.0 180000 0:10.00 04:00 08:56:00 "/tmp/go-build1/b001/app.test -test.v"
    psl 303 300 0.0 90000 0:05.00 01:00:00 08:00:01 "npm exec x-mcp@latest"
    psl 400 290 1.0 300000 0:30.00 30:00 08:30:00 codex
    psl 401 400 0.0 3000 0:02.00 01:00 08:59:00 "bash -lc 'cargo build'"
    psl 500 1 0.0 50000 0:01.00 50:00 08:10:00 "npx -y some-mcp"
} > "$tmp/snap"
agents_sample || fail "first sample failed"
[[ ! -s "$AGENTS_DATA_DIR/history.tsv" ]] || fail "the first sample (the baseline) wrote rows: $(cat "$AGENTS_DATA_DIR/history.tsv")"
[[ "$(head -1 "$AGENTS_DATA_DIR/sample.state")" == "$FAKE_NOW" ]] || fail "sample.state has no epoch header"
grep -q $'^302@Wed_Oct_14_08:56:00_2026\t10\t1$' "$AGENTS_DATA_DIR/sample.state" || fail "sample.state does not key cputime by pid@start (agent 1)"
grep -q $'^500@Wed_Oct_14_08:10:00_2026\t1\t0$' "$AGENTS_DATA_DIR/sample.state" || fail "a stale tree never seen under an agent is marked as seen"
[[ "$(cat "$AGENTS_DATA_DIR/sample.stamp")" == "$FAKE_NOW" ]] || fail "sample.stamp"
[[ ! -e "$AGENTS_DATA_DIR/sample.lock" ]] || fail "sample left its lock behind"

FAKE_NOW=$((FAKE_NOW + 60))
{
    psl 1 0 0.0 20000 10:00.00 13-16:00:00 08:00:00 /sbin/launchd
    psl 290 1 0.0 3000 0:00.10 05:00:00 04:00:00 -zsh
    psl 300 290 5.0 600000 1:12.00 01:01:00 08:00:00 claude
    psl 301 300 0.0 3000 0:00.10 06:00 08:55:00 "$(cc 'go test ./...')"
    psl 302 301 99.0 180000 0:50.00 05:00 08:56:00 "/tmp/go-build1/b001/app.test -test.v"
    psl 303 300 3.0 90000 0:02.00 00:10 09:00:50 "$(cc 'npm run dev')"
    psl 304 300 0.0 90000 5:00.00 01:00:00 08:01:00 "$(cc 'tsc --watch')"
    psl 400 290 1.0 300000 0:33.00 31:00 08:30:00 codex
    psl 402 400 50.0 300000 0:15.00 00:20 09:00:40 "bash -lc 'cargo build'"
    psl 500 1 0.0 50000 0:04.00 51:00 08:10:00 "npx -y some-mcp"
} > "$tmp/snap"
agents_sample || fail "second sample failed"
hist_rows="$(cut -f2- "$AGENTS_DATA_DIR/history.tsv" | sort)"
want="$(printf '%s\n' \
    $'agent\tapp\tclaude\t12\t600000\t1' \
    $'agent\tsvc\tcodex\t3\t300000\t1' \
    $'build\tsvc\tcodex\t15\t300000\t1' \
    $'mcp\tapp\t-\t3\t50000\t1' \
    $'server\tapp\tclaude\t2\t90000\t1' \
    $'test\tapp\tclaude\t40\t183000\t2' | sort)"
[[ "$hist_rows" == "$want" ]] || fail "history rows:"$'\n'"$hist_rows"$'\n'"want:"$'\n'"$want"
[[ "$(cut -f1 "$AGENTS_DATA_DIR/history.tsv" | sort -u)" == "$FAKE_NOW" ]] || fail "history rows carry the sample's epoch"
pass "sample: CPU since the last sample per job, project and session; new processes count whole, first-seen old ones from now on"
pass "sample: a reused pid (new start time) starts afresh; ended processes drop out; rows without CPU are left out"
[[ "$(cat "$AGENTS_DATA_DIR/today.tsv")" == "$FAKE_DAY"$'\t75\ntest\t40\nbuild\t15\nagent\t15\nmcp\t3\nserver\t2' ]] \
    || fail "today.tsv: $(cat "$AGENTS_DATA_DIR/today.tsv")"
FAKE_NOW=$((FAKE_NOW + 60)) FAKE_DAY=2026-10-15
agents_sample || fail "third sample failed"
[[ "$(head -1 "$AGENTS_DATA_DIR/today.tsv")" == "2026-10-15"$'\t0' ]] || fail "today.tsv not reset on a new day: $(head -1 "$AGENTS_DATA_DIR/today.tsv")"
pass "today.tsv: today's totals, busiest job first, reset at midnight"

# The lock: a sample while another one runs returns at once, writing nothing.
mkdir "$AGENTS_DATA_DIR/sample.lock"
before="$(cat "$AGENTS_DATA_DIR/sample.stamp")"
FAKE_NOW=$((FAKE_NOW + 60))
agents_sample || fail "a locked-out sample failed"
[[ "$(cat "$AGENTS_DATA_DIR/sample.stamp")" == "$before" ]] || fail "a second sample ran while one held the lock"
rmdir "$AGENTS_DATA_DIR/sample.lock"
pass "sample: one at a time (lock dir)"

# Provenance for auto-reap: a process seen under an agent keeps that mark
# once its session ends and it is orphaned; one never seen there has none.
(
    AGENTS_DATA_DIR="$tmp/prov"
    agents_snapshot() { cat "$tmp/snap.prov"; }
    {
        psl 1 0 0.0 20000 10:00.00 13-16:00:00 08:00:00 /sbin/launchd
        psl 300 1 5.0 600000 1:00.00 01:00:00 08:00:00 claude
        psl 303 300 0.0 90000 0:05.00 01:00:00 08:00:01 "npm exec x-mcp@latest"
        psl 500 1 0.0 50000 0:01.00 50:00 08:10:00 "caffeinate -dims"
    } > "$tmp/snap.prov"
    agents_sample || fail "provenance: first sample"
    {
        psl 1 0 0.0 20000 10:00.00 13-16:00:00 08:00:00 /sbin/launchd
        psl 303 1 0.0 90000 0:05.00 01:01:00 08:00:01 "npm exec x-mcp@latest"
        psl 500 1 0.0 50000 0:01.00 51:00 08:10:00 "caffeinate -dims"
    } > "$tmp/snap.prov"
    FAKE_NOW=$((FAKE_NOW + 60)); agents_sample || fail "provenance: second sample"
    FAKE_NOW=$((FAKE_NOW + 60)); agents_sample || fail "provenance: third sample"
    st="$AGENTS_DATA_DIR/sample.state"
    grep -q $'^303@Wed_Oct_14_08:00:01_2026\t5\t1$' "$st" || fail "an orphan lost its agent provenance: $(cat "$st")"
    grep -q $'^500@Wed_Oct_14_08:10:00_2026\t1\t0$' "$st" || fail "a user's own orphan got agent provenance: $(cat "$st")"
)
pass "sample.state: pid@start seen under an agent stays marked after it is orphaned; your own orphan is never marked"

# Private: the data dir is 700 and its files 600, and an older, open one is
# made private on the next write.
perm() { if [[ "$(uname)" == Darwin ]]; then stat -f %Lp "$1"; else stat -c %a "$1"; fi; }
[[ "$(perm "$AGENTS_DATA_DIR")" == 700 ]] || fail "data dir mode $(perm "$AGENTS_DATA_DIR")"
for f in history.tsv sample.state today.tsv sample.stamp; do
    [[ "$(perm "$AGENTS_DATA_DIR/$f")" == 600 ]] || fail "$f mode $(perm "$AGENTS_DATA_DIR/$f")"
done
(
    AGENTS_DATA_DIR="$tmp/open"; mkdir -p "$AGENTS_DATA_DIR"; chmod 755 "$AGENTS_DATA_DIR"
    printf 'x\n' > "$AGENTS_DATA_DIR/events.tsv"; chmod 644 "$AGENTS_DATA_DIR/events.tsv"
    agents_event kill manual 1 x app -
    [[ "$(perm "$AGENTS_DATA_DIR")/$(perm "$AGENTS_DATA_DIR/events.tsv")" == 700/600 ]] \
        || fail "an open data dir not made private: $(perm "$AGENTS_DATA_DIR")/$(perm "$AGENTS_DATA_DIR/events.tsv")"
    rm -rf "$AGENTS_DATA_DIR"; agents_event kill manual 1 x app -
    [[ "$(perm "$AGENTS_DATA_DIR")/$(perm "$AGENTS_DATA_DIR/events.tsv")" == 700/600 ]] || fail "a new data dir is not private"
)
pass "history is private: data dir 700, files 600; an open one is fixed on the next write"

# Events and prune share a lock: an event waits for a prune (never lost), a
# prune skips the day when it can't have the lock, a leftover lock is taken.
(
    AGENTS_DATA_DIR="$tmp/elock"; mkdir -p "$AGENTS_DATA_DIR"
    mkdir "$AGENTS_DATA_DIR/events.lock"
    ( sleep 0.3; printf '%s\treap\tstale\t9\tz\tapp\t-\n' "$FAKE_NOW" >> "$AGENTS_DATA_DIR/events.tsv"; rmdir "$AGENTS_DATA_DIR/events.lock" ) &
    agents_event kill manual 1 x app -
    wait
    [[ "$(cut -f4 "$AGENTS_DATA_DIR/events.tsv" | tr '\n' ' ')" == "9 1 " ]] || fail "an event did not wait for the lock: $(cat "$AGENTS_DATA_DIR/events.tsv")"
    [[ ! -e "$AGENTS_DATA_DIR/events.lock" ]] || fail "agents_event left its lock"
    old=$((FAKE_NOW - 31 * 86400))
    printf '%s\tkill\tmanual\t2\tx\tapp\t-\n' "$old" >> "$AGENTS_DATA_DIR/events.tsv"
    mkdir "$AGENTS_DATA_DIR/events.lock"
    _agents_history_prune "$FAKE_NOW" 2026-10-20
    [[ "$(grep -c . "$AGENTS_DATA_DIR/events.tsv")" == 3 && -d "$AGENTS_DATA_DIR/events.lock" ]] || fail "prune rewrote events.tsv without the lock"
    touch -t 202001010000 "$AGENTS_DATA_DIR/events.lock"
    agents_event kill manual 3 y app -
    [[ "$(cut -f4 "$AGENTS_DATA_DIR/events.tsv" | tail -1)" == 3 && ! -e "$AGENTS_DATA_DIR/events.lock" ]] || fail "a leftover lock was not taken over"
    _agents_history_prune "$FAKE_NOW" 2026-10-21
    [[ "$(cut -f4 "$AGENTS_DATA_DIR/events.tsv" | tr '\n' ' ')" == "9 1 3 " ]] || fail "prune under the lock: $(cat "$AGENTS_DATA_DIR/events.tsv")"
)
pass "events and prune share a lock: an event waits, a prune without the lock leaves events.tsv, a leftover lock is taken over"

# hist line and the due check.
[[ "$(_agents_hist_line)" == $'hist\tdue\t0\t-\t0' ]] || fail "hist line on a new day, a minute after: $(_agents_hist_line)"
agents_sample
[[ "$(_agents_hist_line | cut -f2)" == ok ]] || fail "hist line right after a sample"
pass "tsv hist line: due a minute after the last sample, then ok"

# 3. Prune: at most once a day, history and events older than AGENTS_HISTORY_DAYS.
pd="$tmp/prune"; mkdir -p "$pd"
old=$((FAKE_NOW - 31 * 86400)) new=$((FAKE_NOW - 86400))
printf '%s\ttest\tapp\tclaude\t5\t1\t1\n%s\ttest\tapp\tclaude\t7\t1\t1\n' "$old" "$new" > "$pd/history.tsv"
printf '%s\treap\tstale\t1\tnpx\tapp\t-\n%s\treap\tstale\t2\tnpx\tapp\t-\n' "$old" "$new" > "$pd/events.tsv"
(
    AGENTS_DATA_DIR="$pd"
    _agents_history_prune "$FAKE_NOW" 2026-10-15
    [[ "$(cut -f1 "$pd/history.tsv")" == "$new" && "$(cut -f1 "$pd/events.tsv")" == "$new" ]] || fail "prune: $(cat "$pd/history.tsv" "$pd/events.tsv")"
    [[ "$(cat "$pd/prune.stamp")" == 2026-10-15 ]] || fail "prune stamp"
    printf '%s\tkill\tmanual\t3\tx\tapp\t-\n' "$old" >> "$pd/events.tsv"
    _agents_history_prune "$FAKE_NOW" 2026-10-15
    [[ "$(grep -c . "$pd/events.tsv")" == 2 ]] || fail "pruned twice in one day"
    AGENTS_HISTORY_DAYS=60 _agents_history_prune "$FAKE_NOW" 2026-10-16
    [[ "$(grep -c . "$pd/events.tsv")" == 2 ]] || fail "AGENTS_HISTORY_DAYS=60 dropped a 31-day-old line"
)
for f in "$pd"/*.prune.*; do [[ ! -e "$f" ]] || fail "prune left a temp file: $f"; done
pass "prune: once a day, older than AGENTS_HISTORY_DAYS, atomic rewrite"

# 4. AGENTS_HISTORY=0 records nothing.
(
    AGENTS_HISTORY=0 AGENTS_DATA_DIR="$tmp/off"
    agents_sample; agents_event kill manual 1 x app claude
    [[ ! -e "$tmp/off" ]] || fail "AGENTS_HISTORY=0 created the data dir"
    [[ "$(_agents_hist_line)" == $'hist\toff\t0\t-\t0' ]] || fail "hist line with history off"
    ! _agents_sample_due || fail "a sample is due with history off"
    [[ "$(agents_report)" == *"history is off"* ]] || fail "report with history off and no data"
)
pass "AGENTS_HISTORY=0: no sample, no event, menu line off, report says so"

# 5. agents report, human and JSON, on fixture data.
rd="$tmp/report"; mkdir -p "$rd"
now=1760400000   # a midnight, UTC (the fake clock's offset is +0000)
{
    printf '%s\ttest\tapp\tclaude\t3600\t100\t2\n' $((now - 3600 * 2))        # 22:00
    printf '%s\tbuild\tapp\tclaude\t1800\t100\t1\n' $((now - 3600 * 2))
    printf '%s\tagent\tsvc\tcodex\t1800\t100\t1\n' $((now - 3600 * 5))        # 19:00
    printf '%s\tmcp\tapp\t-\t180\t100\t1\n' $((now - 600))                    # 23:50
    printf '%s\ttest\told\tclaude\t9999\t100\t1\n' $((now - 3 * 86400))       # outside 24h
} > "$rd/history.tsv"
{
    printf '%s\treap\tstale\t11\tnpx\tapp\t-\n' $((now - 100))
    printf '%s\tauto\tstale\t12\tnpx\tapp\t-\n' $((now - 200))
    printf '%s\thook\tsession-end\t13\tchrome-devtools-mcp\tsvc\tcodex\n' $((now - 300))
    printf '%s\tkill\tmanual\t14\tclaude\tapp\tclaude\n' $((now - 400))
    printf '%s\treap\tstale\t15\tnpx\told\t-\n' $((now - 3 * 86400))
} > "$rd/events.tsv"
FAKE_NOW=$now
out="$(AGENTS_DATA_DIR="$rd" agents_report)"
[[ "$out" == *"CPU 2.05 CPU-h of agent work"* ]] || fail "report total:"$'\n'"$out"
[[ "$out" == *$'\n'"  test                 1.00    49%  "* ]] || fail "report job line:"$'\n'"$out"
[[ "$out" == *$'\n'"  app                          1.55    76%  test 65%"* ]] || fail "report project line:"$'\n'"$out"
[[ "$out" != *old* ]] || fail "report counts rows outside the window"
[[ "$out" == *"SESSIONS       claude 1.50 · codex 0.50 · stale 0.05"* ]] || fail "report sessions:"$'\n'"$out"
[[ "$out" == *"BUSIEST HOURS  22:00 1.50 · 19:00 0.50 · 23:00 0.05"* ]] || fail "report hours:"$'\n'"$out"
[[ "$out" == *"CLEANUPS (4)"* && "$out" == *"why          stale 2 · session-end 1 · manual 1"* ]] || fail "report cleanups:"$'\n'"$out"
[[ "$out" == *"how          "*"reap 1"*"auto 1"* && "$out" == *"left behind  app 2 · svc 1"* ]] || fail "report cleanup kinds and projects:"$'\n'"$out"
pass "report: CPU-h by job with %, projects with their main job, sessions, busiest hours, cleanups"
json="$(AGENTS_DATA_DIR="$rd" agents_report --since 7d --json)"
if command -v jq >/dev/null 2>&1; then
    printf '%s' "$json" | jq -e '.schema_version == 1 and .window == "7d" and .cpu_s == 17379' >/dev/null || fail "report json totals: $json"
    printf '%s' "$json" | jq -e '.jobs[0] == {"job":"test","cpu_s":13599,"pct":78.2}' >/dev/null || fail "report json jobs: $(printf '%s' "$json" | jq -c .jobs)"
    printf '%s' "$json" | jq -e '(.projects[] | select(.project == "app") | .main_job) == "test"' >/dev/null || fail "report json projects"
    printf '%s' "$json" | jq -e '(.sessions[] | select(.session == null) | .cpu_s) == 180' >/dev/null || fail "report json: stale session not null"
    printf '%s' "$json" | jq -e '.cleanups.total == 5 and (.cleanups.projects[0] == {"project":"app","count":2})' >/dev/null || fail "report json cleanups: $(printf '%s' "$json" | jq -c .cleanups)"
    pass "report --json: the same data as one object (checked with jq)"
else
    [[ "$json" == '{"schema_version":1,'*'"cpu_s":17379,'* ]] || fail "report json: $json"
    pass "report --json (jq not installed: shape only)"
fi
out="$(AGENTS_DATA_DIR="$rd" agents_report --since today)"
[[ "$out" == *"today"* && "$out" == *"no CPU samples in this window"* ]] || fail "report --since today (midnight UTC):"$'\n'"$out"
rc=0; agents_report --since 3x 2>/dev/null || rc=$?
[[ $rc == 2 ]] || fail "bad --since accepted"
rc=0; agents_report --bogus 2>/dev/null || rc=$?
[[ $rc == 2 ]] || fail "unknown report option accepted"
[[ "$(AGENTS_DATA_DIR="$tmp/empty" agents_report)" == *"no history yet; it starts within a minute of the menu running"* ]] || fail "report without history"
pass "report: --since today, bad options refused, a friendly line without history"

# 6. The menu's Where the CPU goes section, from a fixture `agents tsv`.
FAKE_NOW=1760400000
enr2="$(agents_snapshot | AGENTS_SELF=9999 AGENTS_UID=501 agents_classify "" "" | agents_enrich "$(_agents_cwds 300 400 500)" "")"
printf '%s\n' "$enr2" > "$tmp/tsv"
printf 'hist\tdue\t3600\ttest\t1800\n' >> "$tmp/tsv"
# shellcheck disable=SC2016  # $1 belongs to the stub
printf '#!/bin/bash\ncase "$1" in tsv) cat "%s" ;; sample) echo sampled >> "%s" ;; esac\n' "$tmp/tsv" "$tmp/sampled" > "$tmp/agents-stub"
chmod +x "$tmp/agents-stub"
menu="$(AGENTS_BIN="$tmp/agents-stub" bash "$REPO_DIR/configs/swiftbar/agents.10s.sh")"
section="$(printf '%s\n' "$menu" | awk '/^Where the CPU goes/ { on = 1 } on && /^---$/ { exit } on')"
[[ -n "$section" ]] || fail "no Where the CPU goes section:"$'\n'"$menu"
[[ "$(printf '%s\n' "$menu" | grep -n -m1 '^Agents (' | cut -d: -f1)" -lt "$(printf '%s\n' "$menu" | grep -n -m1 '^Where the CPU goes' | cut -d: -f1)" ]] \
    || fail "jobs section is not after agents"
first="$(printf '%s\n' "$section" | sed -n 2p)"
[[ "$first" == "tests · 99% · 178M | sfimage=checkmark.seal refresh=true symbolize=false" ]] || fail "busiest job line: $first"
[[ "$section" == *$'\n'"--app · claude · 99% · 178M | bash=\"$tmp/agents-stub\" terminal=false param1=reveal param2=300@Wed_Oct_14_08:00:00_2026 symbolize=false"* ]] \
    || fail "session under a job:"$'\n'"$section"
[[ "$section" == *$'\n'"builds · 50% · 380M | sfimage=hammer "* ]] || fail "builds line:"$'\n'"$section"
[[ "$section" == *$'\n'"--app · stale · 0% · 48M | bash="*"param1=reveal param2=500@Wed_Oct_14_08:10:00_2026 symbolize=false"* ]] || fail "stale tree under MCP servers:"$'\n'"$section"
[[ "$section" == *$'\n'"Today: 1.0 CPU-h · tests 50% | sfimage=chart.bar.xaxis refresh=true symbolize=false"* ]] || fail "today line:"$'\n'"$section"
[[ "$section" == *$'\n'"Open report | bash=\"$tmp/agents-stub\" param1=open-term terminal=false param2=--hold param3=report sfimage="* ]] || fail "Open report:"$'\n'"$section"
for _ in 1 2 3 4 5 6 7 8 9 10; do [[ -s "$tmp/sampled" ]] && break; sleep 0.2; done
[[ -s "$tmp/sampled" ]] || fail "the menu did not start agents sample when one was due"
pass "menu: Where the CPU goes lists jobs busiest first with their sessions, today's CPU-h and Open report"
pass "menu: a due sample starts agents sample in the background"
# Params carry only fixed words and PID@START tokens.
bad="$(printf '%s\n' "$section" | grep 'param' | grep -vE 'param1=(reveal|open-term) ' || true)"
[[ -z "$bad" ]] || fail "unexpected actions: $bad"
bad="$(printf '%s\n' "$section" | grep -oE 'param2=[^ ]+' | grep -vE '^param2=([0-9]+@[A-Za-z0-9_:]+|--hold)$' || true)"
[[ -z "$bad" ]] || fail "a param that is not a token: $bad"
pass "menu: job actions are reveal PID@START and open-term report only"

rm -f "$tmp/sampled"
printf '%s\n' "$enr2" | awk -F '\t' '$1 != "job"' > "$tmp/tsv"
printf 'hist\toff\t0\t-\t0\n' >> "$tmp/tsv"
menu="$(AGENTS_BIN="$tmp/agents-stub" bash "$REPO_DIR/configs/swiftbar/agents.10s.sh")"
[[ "$menu" != *"Where the CPU goes"* ]] || fail "jobs section shown with nothing to show"
printf 'hist\tok\t0\t-\t0\n' >> "$tmp/tsv"
menu="$(AGENTS_BIN="$tmp/agents-stub" bash "$REPO_DIR/configs/swiftbar/agents.10s.sh")"
[[ "$menu" == *"Today: nothing recorded yet"* ]] || fail "today line before the first numbers"
printf 'hist\tok\t300\tbuild\t240\n' >> "$tmp/tsv"
menu="$(AGENTS_BIN="$tmp/agents-stub" bash "$REPO_DIR/configs/swiftbar/agents.10s.sh")"
[[ "$menu" == *"Today: 5 CPU-min · builds 80% |"* ]] || fail "today line under an hour: $(printf '%s\n' "$menu" | grep Today)"
sleep 0.3
[[ ! -e "$tmp/sampled" ]] || fail "sample started while not due"
printf '%s\n' "$enr2" > "$tmp/tsv"; printf 'conf\tAGENTS_BAR_SECTIONS\tagents\n' >> "$tmp/tsv"
menu="$(AGENTS_BIN="$tmp/agents-stub" bash "$REPO_DIR/configs/swiftbar/agents.10s.sh")"
[[ "$menu" != *"Where the CPU goes"* ]] || fail "jobs section shown although AGENTS_BAR_SECTIONS leaves it out"
pass "menu: no section without jobs or history; AGENTS_BAR_SECTIONS can leave it out"

# 7. Live smoke test: one real sample into a temp dir, where ps works.
unset -f agents_snapshot _agents_keep_pids _agents_cwds date
if ps -o lstart= -p $$ >/dev/null 2>&1; then
    AGENTS_DATA_DIR="$tmp/live" bash "$REPO_DIR/bin/agents" sample || fail "live agents sample failed"
    [[ -s "$tmp/live/sample.state" && -s "$tmp/live/sample.stamp" ]] || fail "live sample wrote no state"
    AGENTS_DATA_DIR="$tmp/live" bash "$REPO_DIR/bin/agents" report >/dev/null || fail "live report failed"
    pass "live: agents sample and report run against this machine"
else
    echo "SKIP: ps unavailable here (sandbox?): live sample not run"
fi

echo "All agents history tests passed."
