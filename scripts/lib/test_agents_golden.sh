#!/bin/bash
# Golden-output tests for bin/agents: every read-only view and every dry run,
# over one fixture process table, fixed files and a fixed clock, compared
# byte for byte with scripts/lib/testdata/agents/*.golden.
# Run: bash scripts/lib/test_agents_golden.sh  -> exit 0 on pass.
#
# A change that means to alter output rewrites the goldens; review the diff:
#   UPDATE_GOLDEN=1 bash scripts/lib/test_agents_golden.sh
#
# Nothing real is read or signalled: ps, lsof, the cwds, Herdr, pmset,
# sysctl, notifyutil and kill are stubs, and every action runs with -n.

# The stubs are called by the sourced functions; settings change per case.
# shellcheck disable=SC2016,SC2030,SC2031,SC2034,SC2317,SC2329
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
GOLDEN="$SCRIPT_DIR/testdata/agents"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "PASS: $1"; }

# Every path the fixtures name starts with $tmp, and the views shorten paths
# longer than a menu line, so the outputs match the goldens only below that:
# $tmp is /tmp/agolden.XXXXXX, or the same under $TMPDIR where /tmp is not
# writable (a sandbox) and $TMPDIR is short, never macOS's long /var/folders.
tmp="$(mktemp -d /tmp/agolden.XXXXXX 2>/dev/null)" || tmp="$(mktemp -d "${TMPDIR:-/tmp}/agolden.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
[[ ${#tmp} -le 40 ]] || fail "$tmp: /tmp is not writable and TMPDIR is long; point TMPDIR at a short directory"

# A clean, fixed environment: no setting of yours leaks in, C locale, UTC.
for v in $(compgen -v AGENTS_) XDG_CONFIG_HOME XDG_STATE_HOME TUIDEV_STATE_DIR HERDR_SOCKET_PATH COLUMNS; do
    unset "$v"
done
export HOME="$tmp/home" TMPDIR="$tmp/t" LC_ALL=C TZ=UTC NO_COLOR=1
export AGENTS_TESTING=1 AGENTS_SELF=7000 AGENTS_UID=501 AGENTS_CONF="$tmp/none.conf"
export AGENTS_DATA_DIR="$tmp/data" AGENTS_RUN_DIR="$tmp/run"
unset CLAUDE_CONFIG_DIR CODEX_HOME   # the token scan reads only $HOME's transcripts (none)
mkdir -p "$HOME" "$TMPDIR" "$AGENTS_DATA_DIR" "$AGENTS_RUN_DIR" "$tmp/out"
# A 48 GB machine, whatever runs the test: the memory guard's stop size (half
# the RAM) is in the tsv.
echo 50331648 > "$AGENTS_RUN_DIR/memtotal"

# shellcheck source=../../bin/agents disable=SC1091
. "$REPO_DIR/bin/agents"

# --- The clock and the files polling loops watch ------------------------------------
# "Now" is 2020-01-01 09:00 UTC. done.output ended 5h ago with Claude Code's
# exit line, build.log has been quiet 1h30m, fail.out ended 2h10m ago with a
# failed test; live.log is dated in the future, so it is always fresh. Every
# other path a loop watches never exists: no golden depends on this machine.
W="$tmp/w"; mkdir -p "$W"
printf 'building\nok\n[exited with code 0]\n\n' > "$W/done.output"
printf 'compiling 3/9\n' > "$W/build.log"
printf 'compiling...\n' > "$W/live.log"
printf '=== RUN TestX\n--- FAIL: TestX (0.01s)\n' > "$W/fail.out"
touch -t 202001010900 "$W/ref"
touch -t 202001010400 "$W/done.output"
touch -t 202001010730 "$W/build.log"
touch -t 209901010000 "$W/live.log"
touch -t 202001010650 "$W/fail.out"
FAKE_NOW="$(_agents_mtimes "$W/ref" | cut -f1)"
[[ "$FAKE_NOW" == 1577869200 ]] || fail "the fixed clock: $FAKE_NOW"
FAKE_DAY=2020-01-01
export AGENTS_NOW="$FAKE_NOW"
date() {
    case "$*" in
        '+%s %Y-%m-%d') echo "$FAKE_NOW $FAKE_DAY" ;;
        '+%s %z')       echo "$FAKE_NOW +0000" ;;
        +%s)            echo "$FAKE_NOW" ;;
        *)              command date "$@" ;;
    esac
}

# --- The process table ----------------------------------------------------------------
# uid 501 ("me") throughout; this process is 7000, a shell under claude 84091.
# Columns: pid ppid uid user %cpu rss time etime lstart(5) args
snap_pre='/bin/zsh -c source /Users/NAME/.claude/shell-snapshots/s.sh 2>/dev/null || true && eval'
cc() { printf "/bin/zsh -c source /Users/NAME/.claude/shell-snapshots/snapshot-zsh-1-x.sh 2>/dev/null || true && eval '%s' < /dev/null && pwd -P >| /tmp/cwd-1" "$1"; }
psl() { printf '%5s %5s   501 me    %5s %7s %10s %11s Wed Oct 14 %s 2026     %s\n' "$@"; }
FIX_PS="$(cat <<'EOF'
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
 1030  1000   501 me    0.0   2000  0:00.10 52:00 Wed Oct 14 08:08:00 2026     /bin/zsh -c source /Users/NAME/.claude/shell-snapshots/snapshot-zsh-1-x.sh 2>/dev/null || true && eval 'until [ -s /nonexistent/x ]; do sleep 5; done' < /dev/null && pwd -P >| /tmp/cwd-3
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
FIX_PS+=$'\n'"$(cat <<EOF
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
 5090  5000   501 me    0.0   2000  0:00.10 03:00:00 Wed Oct 14 06:00:00 2026     $snap_pre 'while [ -f $W/build.log ]; do sleep 5; done' < /dev/null && pwd -P >| /tmp/c9
 6000     1   501 me    0.0  97888  0:00.59 50:05 Wed Oct 14 08:10:00 2026     npm exec chrome-devtools-mcp@latest
 6001  6000   501 me    0.0 117280  0:00.43 50:04 Wed Oct 14 08:10:01 2026     chrome-devtools-mcp
 6100     1   501 me    0.5  80000  0:30.00 03:00:00 Wed Oct 14 06:00:00 2026     node /Users/NAME/work/app/node_modules/.bin/vite --port 5174
EOF
)"
FIX_PS+=$'\n'"$(
    psl 100 900 5.0 600000 1:00.00 01:00:00 08:00:00 "codex"
    psl 101 100 0.0 3000 0:00.10 02:00 08:58:00 "bash -lc 'cd /Users/NAME/repo && go test ./... 2>&1 | tail -30'"
    psl 102 101 1.0 90000 0:01.00 02:00 08:58:00 "go test ./..."
    psl 104 102 50.0 80000 0:20.00 00:30 08:59:30 "/usr/local/go/pkg/tool/darwin_arm64/compile -o /tmp/x.a"
    psl 111 100 0.0 3000 0:00.10 01:00 08:59:00 "bash -lc 'pnpm test'"
    psl 112 111 30.0 90000 0:10.00 01:00 08:59:00 "node /Users/NAME/repo/node_modules/.bin/vitest run"
    psl 123 100 0.0 3000 0:00.10 01:00 08:59:00 "bash -lc 'npm run build'"
    psl 124 123 20.0 90000 0:05.00 01:00 08:59:00 "node /Users/NAME/repo/node_modules/.bin/vite build"
    psl 144 100 0.0 3000 0:00.10 01:00 08:59:00 "bash -lc 'npx playwright test'"
    psl 145 144 40.0 150000 0:20.00 01:00 08:59:00 "/Users/NAME/Library/Caches/ms-playwright/chromium_headless_shell-1187/chrome-mac/headless_shell --headless"
    psl 200 1 0.0 90000 0:00.50 50:00 08:10:00 "npm exec @playwright/mcp@latest"
    psl 201 200 0.0 80000 0:00.40 50:00 08:10:00 "node /Users/NAME/.npm/_npx/def/node_modules/@playwright/mcp/cli.js"
    psl 202 201 3.0 150000 0:10.00 50:00 08:10:00 "/Users/NAME/Library/Caches/ms-playwright/chromium-1187/chrome-mac/chrome-headless-shell --headless"
)"
FIX_LISTEN="$(printf '%s\n' '4100 5173' '4200 11434' '4300 8000' '4400 56916' '22443 41234' '22443 41235' '5061 3000' '6100 5174')"
FIX_CWDS="$(
    printf '%s\t%s\n' 4100 "$HOME/work/app" 4300 / 90419 "$HOME/work/app" 84091 "$HOME/work/shop/.claude/worktrees/fix-cart" \
        1000 /Users/NAME/repo 1010 /Users/NAME/repo/.claude/worktrees/feat-a 1020 /Users/NAME/repo 1030 /Users/NAME/repo \
        2000 /Users/NAME/repo 2010 /Users/NAME/repo/.claude/worktrees/feat-a 6100 "$HOME/work/app" 6000 "$HOME" \
        100 /Users/NAME/repo 200 "$HOME/work/app" 60829 "$HOME" 60831 "$HOME" 27681 "$HOME"
    for p in 5000 5010 5020 5030 5040 5050 5060 5070 5080 5090; do printf '%s\t%s\n' "$p" "$HOME/work/myapp"; done
)"

agents_snapshot() { printf '%s\n' "$FIX_PS"; }
# The MCP inventory (mcp.sh's srv rows), as its cache would hold it: no
# config is read (that is test_agents_mcp.sh's), so no golden needs jq.
# chrome-devtools at user scope (one copy per session), example-agent at
# local scope in /Users/NAME/repo, playwright in ~/work/app's .mcp.json, and
# an http server, which runs no process.
FIX_MCP="$(printf 'srv\tclaude\t%s\t%s\t%s\t%s\t%s\t%s\t1\n' \
    local example-agent "$HOME/.claude.json:/Users/NAME/repo" /Users/NAME/repo stdio /Users/NAME/.local/lib/example-agent-mcp.cjs \
    user chrome-devtools "$HOME/.claude.json" - stdio chrome-devtools-mcp \
    project playwright "$HOME/work/app/.mcp.json" "$HOME/work/app" stdio @playwright/mcp \
    user docs "$HOME/.claude.json" - http -)"
_agents_mcp_load() { _AGENTS_MCP_ROWS="$FIX_MCP"$'\n'; }
_agents_listeners() { printf '%s\n' "$FIX_LISTEN"; }
_agents_cwds() {
    [[ $# -gt 0 ]] || return 0
    local want="," p
    for p in "$@"; do want+="$p,"; done
    printf '%s\n' "$FIX_CWDS" | awk -F '\t' -v want="$want" 'index(want, "," $1 ",") { print $1 "\t" $2 }'
}
# Herdr knows 90419 (by its directory) and its session id; no pane or title.
_agents_herdr() { printf 'claude\tworking\t%s\t-\t-\tsess-90419-herdr\n' "$HOME/work/app"; }
# Claude Code's own records: 5000's (its start: 6h before the clock, 03:00
# UTC), and one a crash left for an earlier process with 84091's pid.
mkdir -p "$HOME/.claude/sessions"
printf '{"pid":5000,"sessionId":"5e550000-0000-4000-8000-000000005000","procStart":"Wed Jan  1 03:00:00 2020"}\n' > "$HOME/.claude/sessions/5000.json"
printf '{"pid":84091,"sessionId":"0ld00000-0000-4000-8000-000000084091","procStart":"Tue Dec 31 10:00:00 2019"}\n' > "$HOME/.claude/sessions/84091.json"
_agents_start() { printf '%s\n' "$FIX_PS" | awk -v p="$1" '$1 == p { print $9 "_" $10 "_" $11 "_" $12 "_" $13; exit }'; }
_agents_keep_pids() { _agents_awake_pid; return 0; }
# tmux: two panes, the shells that started claude 90419 and the sessions under 900.
_agents_tmux_up() { return 0; }
_agents_panes() { printf '510\tmain:2.1\n900\twork:1.0\n'; }
_agents_hook_stdouts() {
    local p
    for p in "$@"; do printf '%s\n' "${FIX_OUTS:-}" | awk -F '\t' -v p="$p" '$1 == p'; done
}
# The machine: an 8-core Mac on battery, nominal thermal pressure. Commands
# on PATH, not functions: bash 3.2 drops a function's output inside a nested
# process substitution, which is how agents_system reads pmset.
mkdir -p "$tmp/bin"
cat > "$tmp/bin/sysctl" <<'EOF'
#!/bin/sh
printf '8\n1\n{ 1.50 1.20 1.00 }\n'
EOF
cat > "$tmp/bin/memory_pressure" <<'EOF'
#!/bin/sh
printf 'The system has 17179869184 (1048576 pages with a page size of 16384).\nSystem-wide memory free percentage: 42%%\n'
EOF
cat > "$tmp/bin/notifyutil" <<'EOF'
#!/bin/sh
echo "com.apple.system.thermalpressurelevel 0"
EOF
cat > "$tmp/bin/pmset" <<'EOF'
#!/bin/sh
case "$*" in
    "-g batt") printf "Now drawing from 'Battery Power'\n -InternalBattery-0 (id=1234)\t87%%; discharging; 4:10 remaining present: true\n" ;;
    "-g") printf 'System-wide power settings:\nCurrently in use:\n standby              1\n powermode            0\n' ;;
    "-g assertions") printf 'Assertion status system-wide:\n   PreventUserIdleSystemSleep     1\nListed by owning process:\n   pid 8800(caffeinate): [0x0001] 00:00:42 PreventUserIdleSystemSleep named: "caffeinate command-line tool"\n   pid 3975(Google Chrome): [0x0002] 01:00:00 PreventUserIdleDisplaySleep named: "Video Wake Lock"\n' ;;
esac
EOF
cat > "$tmp/bin/pbcopy" <<'EOF'
#!/bin/sh
echo "[clipboard]"; cat
EOF
chmod +x "$tmp/bin"/*
export PATH="$tmp/bin:$PATH"
# Nothing is ever signalled or shown.
kill() { [[ "${1:-}" == -0 ]] && return 0; echo "golden: kill $*" >&2; return 0; }
_agents_signal() { echo "golden: signal $*" >&2; }
osascript() { echo "golden: osascript" >&2; return 1; }
open() { echo "golden: open $*" >&2; }

# --- State: keep-awake, history, provenance -------------------------------------------
printf '8800 Wed_Oct_14_09:13:19_2026 timed %s\n' "$((FAKE_NOW + 3600))" > "$AGENTS_RUN_DIR/awake"
printf '%s\n6000@Wed_Oct_14_08:10:00_2026\t1\t1\n6001@Wed_Oct_14_08:10:01_2026\t0\t1\n6100@Wed_Oct_14_06:00:00_2026\t30\t0\n' \
    "$FAKE_NOW" > "$AGENTS_DATA_DIR/sample.state"
printf '%s\n' "$((FAKE_NOW - 30))" > "$AGENTS_DATA_DIR/sample.stamp"
printf '%s\t5400\ntest\t3000\nbuild\t1800\nmcp\t600\n' "$FAKE_DAY" > "$AGENTS_DATA_DIR/today.tsv"
{
    h=1
    for row in "test app claude 1800 90000 4" "build app claude 900 80000 2" "mcp app claude 300 200000 3" \
               "server shop codex 1200 70000 1" "agent shop codex 600 300000 1" "browser - - 400 150000 2" \
               "test api claude 2400 90000 5" "other api claude 60 3000 1" "wait app claude 30 2000 2"; do
        # shellcheck disable=SC2086  # one field per word
        set -- $row
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$((FAKE_NOW - h * 3700))" "$1" "$2" "$3" "$4" "$5" "$6"
        h=$((h + 2))
    done
    printf '%s\ttest\told\tclaude\t9999\t1\t1\n' "$((FAKE_NOW - 40 * 86400))"
} > "$AGENTS_DATA_DIR/history.tsv"
printf '%s\treap\tstale\t60829\tnpm\tapp\t-\n%s\tauto\tstuck\t5010\tzsh\tmyapp\tclaude:5000\n%s\tkill\tmanual\t41198\tMessages\t-\t-\n%s\thook\tsubagent-end\t5200\twait-loop\tmyapp\tclaude:5000\n' \
    "$((FAKE_NOW - 3600))" "$((FAKE_NOW - 7200))" "$((FAKE_NOW - 600))" "$((FAKE_NOW - 900))" > "$AGENTS_DATA_DIR/events.tsv"
# Finished runs: end start job project session agent cmd duration cpu peak exit dup cleaned.
{
    for row in "600 900 test myapp claude:5000 implementor-complex go 245 270000 1 0 0" \
               "1200 1230 build myapp claude:5000 main make 41 74000 0 1 0" \
               "3000 10000 server shop codex:2000 - pnpm 120 90000 - 0 1" \
               "5000 9000 mcp app - - npx 3 50000 - 0 1" \
               "90000 90060 test old claude:1 - pytest 50 1000 0 0 0"; do
        # shellcheck disable=SC2086  # one field per word
        set -- $row
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$((FAKE_NOW - $1))" "$((FAKE_NOW - $2))" "$3" "$4" "$5" "$6" "$7" \
            "$(($2 - $1))" "$8" "$9" "${10}" "${11}" "${12}"
    done
} > "$AGENTS_DATA_DIR/runs.tsv"

# --- Hook fixtures: one subagent that handed back with two live tasks -------------------
if command -v jq >/dev/null 2>&1; then
    proj="$tmp/projects/-work-myapp"; sess=11111111-2222-3333-4444-555555555555
    main="$proj/$sess.jsonl"; subs="$proj/$sess/subagents"; tasks_dir="/private/tmp/claude-501/-work-myapp/$sess/tasks"
    mkdir -p "$subs"
    bg() {
        jq -nc --arg id "$1" --arg cmd "$3" \
            '{type: "assistant", message: {content: [{type: "tool_use", id: $id, name: "Bash",
              input: {command: $cmd, description: "x", run_in_background: true}}]}}'
        jq -nc --arg id "$1" --arg t "$2" --arg dir "$tasks_dir" \
            '{type: "user", toolUseResult: {stdout: "", stderr: "", interrupted: false, backgroundTaskId: $t},
              message: {content: [{type: "tool_result", tool_use_id: $id,
                content: ("Command running in background with ID: " + $t + ". Output is being written to: " + $dir + "/" + $t + ".output.")}]}}'
    }
    handback() {
        jq -nc '{type: "assistant", message: {content: [{type: "tool_use", id: "toolu_hb", name: "SubagentHandback", input: {message: "report"}}]}}'
        jq -nc '{type: "user", toolUseResult: {success: true}, message: {content: [{type: "tool_result", tool_use_id: "toolu_hb", content: "ok"}]}}'
    }
    { bg tu1 a1task001 'F=/tmp/x.log; until grep -q ok $F; do sleep 5; done'; bg tu2 a2task002 'npm run dev'; handback; } > "$subs/agent-aaa.jsonl"
    { bg tu3 m1task001 'until [ -s /tmp/done ]; do sleep 2; done'; } > "$main"
    hook_json() {   # EVENT AGENT_ID [REASON]
        jq -nc --arg ev "$1" --arg main "$main" --arg sub "$subs/agent-$2.jsonl" --arg r "${3:-}" \
            '{session_id: "s", transcript_path: $main, cwd: "/work/myapp", hook_event_name: $ev}
             + (if $ev == "SubagentStop" then {agent_id: "aaa", agent_type: "general-purpose", agent_transcript_path: $sub} else {reason: $r} end)'
    }
    proc() { printf '%s %s   501 me  0.0 1000 0:00.00 10:00 Wed Oct 14 09:00:00 2026     %s\n' "$1" "$2" "$3"; }
    shell() { proc "$1" "$2" "/bin/zsh -c source /h/.claude/shell-snapshots/s.sh 2>/dev/null || true && eval '$3' < /dev/null && pwd -P >| /tmp/claude-501/cwd-x"; }
    HOOK_PS="$(
        proc 4000 1 "-zsh"
        proc 5000 4000 "claude --continue"
        proc 5100 5000 "/bin/sh -c agents hook subagent-stop"
        proc 5101 5100 "bash /h/.local/bin/agents hook subagent-stop"
        shell 5200 5000 'F=/tmp/x.log; until grep -q ok $F; do sleep 5; done'
        proc 5201 5200 "sleep 5"
        shell 5300 5000 'npm run dev'
        proc 5301 5300 "node /w/node_modules/.bin/vite"
        shell 5550 5000 'until [ -s /tmp/done ]; do sleep 2; done'
    )"
    HOOK_OUTS="$(printf '%s\t%s\n' 5200 "$tasks_dir/a1task001.output" 5300 "$tasks_dir/a2task002.output" 5550 "$tasks_dir/m1task001.output")"
fi

# --- The cases --------------------------------------------------------------------------
# case_ NAME ARGS... — `agents ARGS` into $tmp/out/NAME: stdout and stderr
# together, then the exit status; HOME, temp and repo paths become @HOME@,
# @TMP@ and @REPO@.
norm() { sed -e "s|$HOME|@HOME@|g" -e "s|$tmp|@TMP@|g" -e "s|$REPO_DIR|@REPO@|g"; }
case_() {
    local name="$1" rc=0; shift
    ( agents_main "$@" ) > "$tmp/raw" 2>&1 < "${CASE_STDIN:-/dev/null}" || rc=$?
    { cat "$tmp/raw"; echo "[rc=$rc]"; } | norm > "$tmp/out/$name"
}

case_ ls
case_ ls-list list
case_ ps ps
case_ ps-1000 ps 1000
case_ ps-bad ps x
case_ stale stale
case_ hogs hogs
case_ json json
case_ tsv tsv
case_ mcp mcp
# The menu: the SwiftBar plugin over that same tsv, which a stub agents
# replays (the plugin runs in its own bash, so it sees none of the functions
# stubbed here; its one clock read, awake's time left, is long past). The menu
# shortens long lines, so $tmp becomes one fixed path first: the golden does
# not depend on how long $tmp is.
menu_case() {   # NAME TSV_FILE
    local fixed=/tmp/agents-fixture
    sed "s|$tmp|$fixed|g" "$2" > "$tmp/menu.tsv"
    printf '#!/bin/sh\n[ "$1" = tsv ] && cat "%s"\nexit 0\n' "$tmp/menu.tsv" > "$tmp/menu-agents"
    chmod +x "$tmp/menu-agents"
    ( USER=me HOME="$fixed/home" AGENTS_BIN="$tmp/menu-agents" bash "$REPO_DIR/configs/swiftbar/agents.10s.sh" ) 2>&1 \
        | sed -e "s|$tmp|@TMP@|g" -e "s|$fixed|@TMP@|g" -e "s|$REPO_DIR|@REPO@|g" > "$tmp/out/$1"
}
( agents_main tsv ) > "$tmp/tsv.raw" 2>/dev/null || true
menu_case menu "$tmp/tsv.raw"
# The same with the Usage section (two Claude accounts, a CLI by model, a
# window past 80%) and Herdr's maintenance (a session works: no restart).
{ cat "$tmp/tsv.raw"; printf '%s\n' \
    $'limit\tClaude\t5h\t86\t14:05\tclaude\t60' $'limit\tClaude\tweek\t41\tMon 09:00\tclaude\t60' \
    $'limit\tClaude · work\t5h\t12\t15:40\tclaude:work\t300' $'limit\tCodex\tweek\t0\t-\tcodex\t5400' \
    $'limit\tAntigravity · Claude and GPT\tweek\t3\t-\tagy:3p\t900' $'limit\tAntigravity · Gemini\t5h\t9\t21:10\tagy:gemini\t900' \
    $'tokens\t12400000\t94' $'denials\t12\tProduction Deploy' $'compacts\t3' \
    $'hhealth\tserver\tstale\t0.9.4\t0.9.5' $'hhealth\toutdated\tclaude codex'; } > "$tmp/tsv-usage.raw"
menu_case menu-usage "$tmp/tsv-usage.raw"
# agents show: the process's own files and threads come from lsof and ps -M,
# so they are fixed here; no session transcripts exist in this HOME.
_agents_show_proc() { printf 'f\tfiles\t17\nf\tthreads\t%s\n' "$(( $1 % 7 + 1 ))"; }
case_ show-1000 show 1000
case_ show-1001 show 1001
case_ show-1012 show 1012
case_ show-6000 show 6000
case_ show-json-90419 show --json 90419
case_ show-gone show 4242
case_ pick-list pick --list
case_ peek-app peek 84091
case_ thermal thermal
case_ awake-status awake
case_ awake-bad awake sideways
case_ config config
case_ help --help
case_ unknown frobnicate
for p in 6000 6100 60829 5010 5020 5030 5040 5050 5060 5070 5080 5090 1010 1030 90419 41198 1001 1041; do
    case_ "why-$p" why "$p"
done
case_ why-token why 6000@Wed_Oct_14_08:10:00_2026
case_ why-moved why 6000@Mon_Jan_01_00:00:00_2024
case_ why-none why 900
case_ why-copy why --copy 5010
case_ why-usage why
case_ report report
case_ report-7d report --since 7d
case_ report-today report --since today
case_ report-json report --json
case_ report-bad report --since yesterday
# The run ledger's views: the same history and events, without a ledger and
# with scripts/lib/testdata/agents-runs.tsv counted back from now.
mkdir -p "$tmp/noledger" "$tmp/runs"
cp "$AGENTS_DATA_DIR/history.tsv" "$AGENTS_DATA_DIR/events.tsv" "$tmp/noledger/"
cp "$AGENTS_DATA_DIR/history.tsv" "$AGENTS_DATA_DIR/events.tsv" "$tmp/runs/"
( AGENTS_DATA_DIR="$tmp/noledger" case_ report-runs-noledger report --view runs )
awk -F '\t' -v OFS='\t' -v n="$FAKE_NOW" '$1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+$/ { $1 = n - $1; $2 = n - $2 } { print }' \
    "$SCRIPT_DIR/testdata/agents-runs.tsv" > "$tmp/runs/runs.tsv"
( AGENTS_DATA_DIR="$tmp/runs"
  case_ report-insights report
  case_ report-insights-json report --json
  for v in runs waste agents; do
      case_ "report-$v" report --view "$v"
      case_ "report-$v-json" report --view "$v" --json
  done
  case_ report-trends report --view trends --since 24h
  case_ report-trends-json report --view trends --since 24h --json
  case_ report-view-bad report --view everything )
# The waits view: sessions Herdr showed blocked or done (waits.tsv) and the
# notifications notify.sh logged (notify.tsv), counted back from now.
mkdir -p "$tmp/waits"
awk -v n="$FAKE_NOW" 'BEGIN {
    OFS = "\t"
    for (i = 1; i <= 25; i++) print n - i * 60, "billing", "claude", "blocked", "4100@Wed_Oct_14_08:00:00_2026", 60
    for (i = 1; i <= 4; i++) print n - i * 300, "billing", "claude", "done", "4100@Wed_Oct_14_08:00:00_2026", 300
    for (i = 1; i <= 9; i++) print n - i * 120, "app/agent-a1", "codex", "blocked", "4200@Wed_Oct_14_09:00:00_2026", 120
    print n - 3 * 86400, "old", "claude", "blocked", "4300@Mon_Oct_12_09:00:00_2026", 300
    print n - 60, "app", "claude", "working", "4400@Wed_Oct_14_09:00:00_2026", 60
}' > "$tmp/waits/waits.tsv"
awk -v n="$FAKE_NOW" 'BEGIN {
    OFS = "\t"
    for (i = 1; i <= 7; i++) print n - i * 200, "4100@Wed_Oct_14_08:00:00_2026", "billing", "Permission", "herdr", (i <= 5 ? "present" : "-")
    print n - 90, "4100@Wed_Oct_14_08:00:00_2026", "billing", "Idle", "herdr,banner", "-"
    print n - 80, "-", "app", "Permission", "tmux", "remote"
    print n - 70, "-", "notes", "-", "banner", "-"
    print n - 2 * 86400, "-", "old", "Idle", "banner", "-"
}' > "$tmp/waits/notify.tsv"
( AGENTS_DATA_DIR="$tmp/waits"
  case_ report-waits report --view waits
  case_ report-waits-json report --view waits --json
  case_ report-waits-summary report --since today )
case_ runs runs
case_ runs-json runs --json
case_ runs-7d runs --since 7d
case_ reap-n reap -n
case_ reap-stuck-n reap --stuck -n
case_ reap-auto-n reap --auto -n
case_ kill-n kill -n 90419
case_ kill-token-n kill -n 60829@Wed_Oct_14_08:23:56_2026
case_ kill-moved-n kill -n 60829@Mon_Jan_01_00:00:00_2024
case_ kill-refused-n kill -n 1 7000 500 48170 606 99999
case_ term-n term -n 41198
case_ term-bad-option term --stuck 41198
case_ cwd-usage cwd 90419
( PATH=/usr/bin:/bin AGENTS_APP_DIRS="$tmp/apps" case_ open-term-n open-term -n --hold report )
# A sample after one a minute ago: CPU used since then, by job and project.
mkdir -p "$tmp/sample"
printf '%s\n1012@Wed_Oct_14_08:58:05_2026\t50\t1\n22443@Wed_Oct_14_09:11:12_2026\t100\t1\n6001@Wed_Oct_14_08:10:01_2026\t0\t1\n' \
    "$((FAKE_NOW - 60))" > "$tmp/sample/sample.state"
( AGENTS_DATA_DIR="$tmp/sample" case_ sample sample
  for f in history.tsv today.tsv sample.state sample.stamp runs.state runs.tsv insight.txt; do printf '== %s\n' "$f"; cat "$tmp/sample/$f" 2>/dev/null || true; done | norm >> "$tmp/out/sample" )
if [[ -n "${HOOK_PS:-}" ]]; then
    hook_case() {   # NAME EVENT HOOK_JSON
        printf '%s\n' "$3" > "$tmp/hook.json"
        ( FIX_PS="$HOOK_PS" FIX_OUTS="$HOOK_OUTS" AGENTS_SELF=5101 CASE_STDIN="$tmp/hook.json" case_ "$1" hook "$2" -n )
    }
    hook_case hook-subagent-stop subagent-stop "$(hook_json SubagentStop aaa)"
    hook_case hook-session-clear session-end "$(hook_json SessionEnd aaa clear)"
    hook_case hook-session-exit session-end "$(hook_json SessionEnd aaa prompt_input_exit)"
else
    echo "SKIP: jq not installed: the hook goldens are not compared"
    for n in hook-subagent-stop hook-session-clear hook-session-exit; do cp "$GOLDEN/$n.golden" "$tmp/out/$n"; done
fi

# --- Compare --------------------------------------------------------------------------
cases=()
for f in "$tmp/out"/*; do cases+=("${f##*/}"); done
if [[ -n "${UPDATE_GOLDEN:-}" ]]; then
    rm -rf "$GOLDEN"; mkdir -p "$GOLDEN"
    for n in "${cases[@]}"; do cp "$tmp/out/$n" "$GOLDEN/$n.golden"; done
    echo "rewrote ${#cases[@]} goldens in ${GOLDEN#"$REPO_DIR"/}: review the diff"
    exit 0
fi
bad=""
for n in "${cases[@]}"; do
    [[ -f "$GOLDEN/$n.golden" ]] || { bad+=" $n(missing)"; continue; }
    cmp -s "$GOLDEN/$n.golden" "$tmp/out/$n" || { diff -u "$GOLDEN/$n.golden" "$tmp/out/$n" | head -40 >&2; bad+=" $n"; }
done
for g in "$GOLDEN"/*.golden; do
    [[ -e "$g" ]] || continue; n="${g##*/}"; n="${n%.golden}"
    [[ -f "$tmp/out/$n" ]] || bad+=" $n(stale golden)"
done
[[ -z "$bad" ]] || fail "output differs from the golden:$bad"
pass "${#cases[@]} views and dry runs match their goldens byte for byte"
echo "All agents golden tests passed."
