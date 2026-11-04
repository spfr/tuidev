#!/bin/bash
# A budget for one refresh. 3.18.0 shipped a 15-second `agents tsv` that every
# test passed: nothing measured it. Here agents_collect and the tsv's whole path
# run over a machine of about 1,000 processes with long arguments, hot enough to
# keep a hog streak, in the bash that runs in production. The budget is generous
# on purpose: the menu refreshes every 10 s, so this is the point past which it
# stops keeping up, not a target, and a loaded machine must not make it flake.
# Run: bash scripts/lib/test_agents_refresh.sh  -> exit 0 on pass.
#
# Nothing real is read: ps, lsof and friends are stubs.

# The stubs are called by the sourced functions.
# shellcheck disable=SC2317,SC2329
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/tuidev-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
for v in $(compgen -v AGENTS_) XDG_CONFIG_HOME XDG_STATE_HOME TUIDEV_STATE_DIR; do unset "$v"; done
export HOME="$tmp/home" NO_COLOR=1 AGENTS_TESTING=1 AGENTS_NO_HERDR=1
export AGENTS_CONF="$tmp/none.conf" AGENTS_RUN_DIR="$tmp/run" AGENTS_DATA_DIR="$tmp/data" AGENTS_UID=501 AGENTS_SELF=99999
mkdir -p "$HOME" "$AGENTS_DATA_DIR" "$AGENTS_RUN_DIR"

# shellcheck source=../../bin/agents disable=SC1091
. "$REPO_DIR/bin/agents"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "PASS: $1"; }

BUDGET=8

# Eight agent sessions, each with MCP servers and tool shells running children
# with arguments as long as real ones, and the rest of a busy Mac: its apps and
# helpers, some of them hot, so hog rows and their streak come out too.
SNAP="$tmp/ps"
LC_ALL=C awk 'BEGIN {
    pad = "--flag=/Users/NAME/workspace/some/long/path/to/a/project/node_modules/.bin/tool"
    while (length(pad) < 320) pad = pad " " pad
    pad = substr(pad, 1, 320)
    p = 1000
    row = "%6d %6d   501 me    %5.1f %7d   1:00.00 01:00:00 Wed Oct 14 08:00:00 2026     %s\n"
    for (s = 1; s <= 8; s++) {
        root = p++
        printf row, root, 1, 12.0, 700000, "claude --session-id " s " " pad
        for (m = 1; m <= 4; m++) printf row, p++, root, 0.1, 90000, "node /Users/NAME/.npm/_npx/abc/node_modules/some-mcp-" m "/build/index.js " pad
        for (t = 1; t <= 20; t++) {
            sh = p++
            printf row, sh, root, 0.0, 3000, "/bin/zsh -c source /Users/NAME/.claude/shell-snapshots/snapshot-zsh-1-x.sh 2>/dev/null || true && eval \047pnpm run test:" t " " pad "\047 < /dev/null && pwd -P >| /tmp/cwd-" sh
            for (k = 1; k <= 3; k++) printf row, p++, sh, 3.0, 120000, "node /Users/NAME/repo/node_modules/.bin/vitest run --pool=forks " k " " pad
        }
    }
    while (p < 2000) {
        printf row, p, 1, (p % 40 == 0 ? 120.0 : 0.2), 80000, "/Applications/Some App " (p % 17) ".app/Contents/Frameworks/Helper (Renderer) --type=renderer " pad
        p++
    }
}' > "$SNAP"
[[ "$(wc -l < "$SNAP" | tr -d ' ')" -ge 1000 ]] || fail "the fixture is small: $(wc -l < "$SNAP")"

agents_snapshot() { cat "$SNAP"; }
_agents_listeners() { :; }
_agents_keep_pids() { :; }
_agents_tmux_up() { return 1; }
_agents_cwds() { :; }
_agents_tsv_machine() { printf '1.0\t8\t50\tnormal\t-\t-\nthermal\t0\tnominal\npower\tautomatic\nlid\toff\t-\t0\t0\n\n'; }

# The streak: a hot row a first refresh leaves is what the next one reads.
recs="$(agents_collect)"
[[ "$recs" == *$'\nagent\t'* ]] || fail "no agents in the fixture"
[[ -s "$AGENTS_RUN_DIR/hog.state" ]] || fail "the fixture keeps no hog streak"
[[ "$(wc -c <<<"$recs" | tr -d ' ')" -ge 100000 ]] || fail "the records are small: $(wc -c <<<"$recs")"

took() {   # NAME COMMAND...
    local name="$1" t0 secs; shift
    t0="$SECONDS"
    "$@" > "$tmp/out" 2>&1 || fail "$name failed: $(tail -3 "$tmp/out")"
    secs=$((SECONDS - t0))
    [[ $secs -lt $BUDGET ]] || fail "$name took ${secs}s over about 1,000 processes (budget ${BUDGET}s)"
    pass "$name over $(wc -l < "$SNAP" | tr -d ' ') processes: ${secs}s (budget ${BUDGET}s)"
}
took agents_collect agents_collect
took "agents tsv" agents_tsv
_agents_colors
export AGENTS_WIDTH=80
took "the triage view" agents_triage

echo
echo "All agents refresh tests passed."
