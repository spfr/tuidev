#!/bin/bash
# Unit tests for where a process lives and going there (lib/agents/where.sh:
# agents jump, agents peek), agents show (show.sh, activity.sh) and agents
# pick (pick.sh).
# Run: bash scripts/lib/test_agents_show.sh  -> exit 0 on pass.
#
# A fixture process table and stub tmux, herdr, osascript and fzf on PATH
# that record what they are asked: nothing real is focused, read or shown.

# Stubs are called indirectly; tests change settings inside ( … ).
# shellcheck disable=SC2016,SC2030,SC2031,SC2317,SC2329
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/tuidev-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home" NO_COLOR=1 CLAUDE_CONFIG_DIR="$tmp/claude"
unset CODEX_HOME TMUX HERDR_ENV
mkdir -p "$HOME" "$CLAUDE_CONFIG_DIR/sessions" "$tmp/bin" "$tmp/log"
export AGENTS_TESTING=1 AGENTS_SELF=99999 AGENTS_UID=501 AGENTS_CONF="$tmp/none.conf"
export AGENTS_RUN_DIR="$tmp/run" AGENTS_DATA_DIR="$tmp/data" AGENTS_NO_HERDR=1 AGENTS_HISTORY=0
export AGENTS_NOW=1792000000

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "PASS: $1"; }

# shellcheck source=../../bin/agents disable=SC1091
. "$REPO_DIR/bin/agents"

# --- The machine -------------------------------------------------------------------------
# Ghostty 500 runs claude 600 (a tool 601 in it) and a Herdr client 830;
# tmux's server 700 has a pane shell 710 with claude 720 (an MCP server 721);
# Herdr's server 800 has a pane shell 810 with claude 820; sshd 900 runs claude
# 920; iTerm 950 runs claude 960.
psl() { printf '%5s %5s   501 me    %5s %7s 0:10.00 %8s Wed Oct 14 08:00:00 2026     %s\n' "$@"; }
SNAP="$(
    psl 1 0 0.0 9000 10:00:00 /sbin/launchd
    psl 500 1 1.0 90000 10:00:00 /Applications/Ghostty.app/Contents/MacOS/ghostty
    psl 510 500 0.0 3000 09:00:00 -zsh
    psl 600 510 5.0 600000 01:00:00 claude
    psl 601 600 50.0 90000 02:00 "/bin/zsh -c source /h/.claude/shell-snapshots/s.sh 2>/dev/null || true && eval 'go test ./...' < /dev/null && pwd -P >| /tmp/c"
    psl 602 601 49.0 80000 01:59 "/tmp/go-build1/b001/x.test"
    psl 830 500 0.0 9000 09:00:00 "herdr"
    psl 700 1 0.0 5000 10:00:00 "tmux new -s work"
    psl 710 700 0.0 3000 05:00:00 -zsh
    psl 720 710 2.0 500000 04:00:00 claude
    psl 721 720 0.0 70000 04:00:00 "npm exec @playwright/mcp@latest"
    psl 800 1 0.0 9000 10:00:00 "herdr server"
    psl 810 800 0.0 3000 03:00:00 -zsh
    psl 820 810 1.0 300000 02:00:00 claude
    psl 900 1 0.0 3000 10:00:00 "sshd: me@ttys009"
    psl 910 900 0.0 3000 01:00:00 -zsh
    psl 920 910 1.0 300000 01:00:00 claude
    psl 950 1 1.0 90000 10:00:00 /Applications/iTerm.app/Contents/MacOS/iTerm2
    psl 955 950 0.0 3000 09:00:00 -zsh
    psl 960 955 1.0 300000 01:00:00 codex
)"
agents_snapshot() { printf '%s\n' "$SNAP"; }
_agents_listeners() { :; }
_agents_keep_pids() { :; }
_agents_cwds() {
    local p
    [[ "${1:-}" == --stdout ]] && shift
    for p in "$@"; do
        case "$p" in
            600|601) printf '%s\t%s\n' "$p" "$tmp/repo" ;;
            720) printf '%s\t%s\n' "$p" /work/web ;;
            820) printf '%s\t%s\n' "$p" /work/api ;;
            *)   printf '%s\t/\n' "$p" ;;
        esac
    done
}
_agents_start() { printf '%s\n' "$SNAP" | awk -v p="$1" '$1 == p { print $9 "_" $10 "_" $11 "_" $12 "_" $13; exit }'; }
_agents_tmux_up() { return 0; }
_agents_panes() { printf '710\twork:1.2\t%%15\n'; }
_agents_tty() { case "$1" in 830) echo /dev/ttys003 ;; 600|601) echo /dev/ttys001 ;; 960) echo /dev/ttys006 ;; esac; }
_agents_notify() { echo "notified: $1" >> "$tmp/log/notify"; }
kill() { [[ "${1:-}" == -0 ]] && return 0; echo "kill $*" >> "$tmp/log/kill"; }

# Stub programs: each logs its arguments.
stub() {   # NAME SCRIPT_BODY
    printf '#!/bin/bash\necho "$*" >> "%s/log/%s"\n%s\n' "$tmp" "$1" "$2" > "$tmp/bin/$1"
    chmod +x "$tmp/bin/$1"
}
stub tmux 'case "$1" in list-clients) echo "100 7000 /dev/ttys002" ;; capture-pane) echo "pane text" ;; esac; exit 0'
stub osascript 'echo ok'
stub open 'exit 0'
HERDR_AGENTS='{"result":{"agents":[
  {"pane_id":"w1:p1","agent":"claude","cwd":"/work/other","agent_session":{"value":"sess-820"}},
  {"pane_id":"w2:p1","agent":"claude","cwd":"/work/api","agent_session":{"value":"other"}}]}}'
stub herdr 'case "$1 $2" in
  "agent list") cat "'"$tmp"'/herdr.json" ;;
  "agent focus") echo "{}" ;;
  "pane process-info") [[ "$4" == w2:p1 ]] && echo "{\"result\":{\"process_info\":{\"shell_pid\":810,\"foreground_processes\":[{\"pid\":820}]}}}" || echo "{\"result\":{\"process_info\":{\"shell_pid\":1}}}" ;;
  "pane read") echo "herdr pane text" ;;
esac'
printf '%s\n' "$HERDR_AGENTS" > "$tmp/herdr.json"
export PATH="$tmp/bin:$PATH"
log() { cat "$tmp/log/$1" 2>/dev/null; }
clear_logs() { rm -f "$tmp/log/"*; }

# --- Where each process lives -----------------------------------------------------------
w() { agents_where "$1" "$SNAP" "$(_agents_panes)" | head -1; }
[[ "$(w 601)" == $'app\tGhostty\t600\tclaude\t-' ]]     || fail "a command in a Ghostty tab: $(w 601)"
[[ "$(w 721)" == $'tmux\twork:1.2\t720\tclaude\t%15' ]] || fail "an MCP server in a tmux pane: $(w 721)"
[[ "$(w 820)" == $'herdr\t-\t820\tclaude\t-' ]]         || fail "a Herdr pane: $(w 820)"
[[ "$(w 920)" == $'ssh\t-\t920\tclaude\t-' ]]           || fail "over ssh: $(w 920)"
[[ "$(w 960)" == $'app\tiTerm\t960\tcodex\t-' ]]        || fail "iTerm: $(w 960)"
[[ "$(agents_where 721 "$SNAP" $'710\twork:1.2' | head -1)" == $'tmux\twork:1.2\t720\tclaude\twork:1.2' ]] || fail "a pane map without ids: $(agents_where 721 "$SNAP" $'710\twork:1.2' | head -1)"
[[ "$(agents_where 820 "$SNAP" "" | grep '^client')" == $'client\t830\tGhostty' ]] || fail "the Herdr client's app"
[[ -z "$(agents_where 4242 "$SNAP" "")" ]]               || fail "a pid that is not running"
recs="$(printf '%s\n' "$SNAP" | agents_classify "" "" "$(_agents_panes)" | awk -F '\t' '$1 == "where"' | LC_ALL=C sort)"
[[ "$recs" == "$(printf 'where\t%s\t%s\t%s\n' 600 app Ghostty 720 tmux work:1.2 820 herdr - 920 ssh - 960 app iTerm | LC_ALL=C sort)" ]] \
    || fail "classify's where records:"$'\n'"$recs"
pass "where: tmux pane, Herdr, ssh, or the terminal app, from each process's ancestry; a where record per session"

# --- agents root-of: the session a notification jumps to --------------------------------
ro() { agents_root_of "$1" "${2:-$SNAP}"; }
T=Wed_Oct_14_08:00:00_2026
[[ "$(ro 600)" == "600@$T"$'\tGhostty\tcom.mitchellh.ghostty' ]] || fail "root-of a session in Ghostty: $(ro 600)"
[[ "$(ro 602)" == "600@$T"$'\tGhostty\tcom.mitchellh.ghostty' ]] || fail "root-of through its tool shells: $(ro 602)"
[[ "$(ro 820)" == "820@$T"$'\tGhostty\tcom.mitchellh.ghostty' ]] || fail "root-of in Herdr: the app its client runs in: $(ro 820)"
[[ "$(ro 960)" == "960@$T"$'\tiTerm\tcom.googlecode.iterm2' ]]   || fail "root-of in iTerm: $(ro 960)"
[[ "$(ro 920)" == "920@$T"$'\t-\t-' ]]                            || fail "root-of over ssh: $(ro 920)"
# tmux: its server is no app's; the clients' app, when they all run in one.
[[ "$(ro 721)" == "720@$T"$'\t-\t-' ]]                            || fail "root-of in tmux with no client: $(ro 721)"
SNAP_T="$SNAP"$'\n'"$(psl 520 510 0.0 3000 09:00:00 "tmux attach -t work")"
[[ "$(ro 721 "$SNAP_T")" == "720@$T"$'\tGhostty\tcom.mitchellh.ghostty' ]] || fail "root-of in tmux, its client in Ghostty: $(ro 721 "$SNAP_T")"
SNAP_T="$SNAP_T"$'\n'"$(psl 956 955 0.0 3000 09:00:00 "tmux: client")"
[[ "$(ro 721 "$SNAP_T")" == "720@$T"$'\t-\t-' ]]                  || fail "root-of in tmux, clients in two apps: $(ro 721 "$SNAP_T")"
# The outermost agent is the session: a codex a claude runs is part of it.
SNAP_T="$SNAP"$'\n'"$(psl 603 601 0.0 3000 00:10 "codex exec x")"$'\n'"$(psl 604 603 0.0 3000 00:10 "/bin/sh -c notify.sh")"
[[ "$(ro 604 "$SNAP_T")" == "600@$T"$'\tGhostty\tcom.mitchellh.ghostty' ]] || fail "root-of a nested agent: $(ro 604 "$SNAP_T")"
if out="$(ro 510)" || [[ -n "$out" ]]; then fail "root-of a shell no agent runs under: $out"; fi
if out="$(ro 830)" || [[ -n "$out" ]]; then fail "root-of the Herdr client: $out"; fi
if out="$(ro 4242)" || [[ -n "$out" ]]; then fail "root-of a pid that is gone: $out"; fi
[[ "$(agents_root_of x 2>&1)" == "usage: agents root-of PID" ]] || fail "root-of usage"
[[ "$(agents_main root-of 602)" == "600@$T"$'\tGhostty\tcom.mitchellh.ghostty' ]] || fail "agents root-of: $(agents_main root-of 602)"
pass "root-of: the outermost agent above a pid as PID@START, its terminal app (tmux and Herdr: their clients') and bundle id; nothing for no agent"

# --- agents jump ------------------------------------------------------------------------
clear_logs
out="$(agents_jump 721)" || fail "jump to a tmux pane failed: $out"
[[ "$out" == "pid 721: tmux pane work:1.2" ]] || fail "jump output: $out"
[[ "$(log tmux)" == *"select-window -t %15"*"select-pane -t %15"*"switch-client -t %15"* ]] || fail "tmux calls: $(log tmux)"
pass "jump: a tmux pane is selected by its id (shown by its place) and the last client switched to it"

clear_logs
out="$(agents_jump 820)" || fail "jump to Herdr failed: $out"
[[ "$out" == "pid 820: Herdr pane w2:p1" && "$(log herdr)" == *"agent focus w2:p1"* ]] || fail "Herdr by its directory: $out / $(log herdr)"
[[ "$(log osascript)" == *"Ghostty"*"/dev/ttys003"* ]] || fail "the Herdr client's Ghostty tab is not focused: $(log osascript)"
# By the session id Claude Code recorded for the pid (preferred over the directory).
printf '{"sessionId":"sess-820","name":"api-1","status":"busy","version":"2.1.0"}\n' > "$CLAUDE_CONFIG_DIR/sessions/820.json"
clear_logs; agents_jump 820 >/dev/null
[[ "$(log herdr)" == *"agent focus w1:p1"* ]] || fail "Herdr by session id: $(log herdr)"
rm -f "$CLAUDE_CONFIG_DIR/sessions/820.json"
# Neither: the pane whose processes include it.
printf '%s\n' '{"result":{"agents":[{"pane_id":"w3:p1","agent":"claude","cwd":"/x"},{"pane_id":"w2:p1","agent":"claude","cwd":"/y"}]}}' > "$tmp/herdr.json"
clear_logs; agents_jump 820 >/dev/null
[[ "$(log herdr)" == *"pane process-info --pane w3:p1"*"agent focus w2:p1"* ]] || fail "Herdr by process-info: $(log herdr)"
printf '%s\n' "$HERDR_AGENTS" > "$tmp/herdr.json"
# Its processes come before a guess by its directory: another agent alone in
# that directory is not it. The guess is a jump's last resort, and only for
# a session whose id is known.
printf '%s\n' '{"result":{"agents":[{"pane_id":"w9:p9","agent":"claude","cwd":"/work/api","agent_session":{"value":"zzz"}},{"pane_id":"w2:p1","agent":"claude","cwd":"/x"}]}}' > "$tmp/herdr.json"
clear_logs; agents_jump 820 >/dev/null
[[ "$(log herdr)" == *"agent focus w2:p1"* ]] || fail "Herdr: a guess by directory came before the exact process check: $(log herdr)"
printf '%s\n' '{"result":{"agents":[{"pane_id":"w9:p9","agent":"claude","cwd":"/work/api","agent_session":{"value":"zzz"}}]}}' > "$tmp/herdr.json"
clear_logs; out="$(agents_jump 820)"
[[ "$out" == "pid 820: Herdr (its pane not found)" && "$(log herdr)" != *"agent focus"* ]] || fail "Herdr: a guess without a session id: $out / $(log herdr)"
printf '{"sessionId":"sess-820"}\n' > "$CLAUDE_CONFIG_DIR/sessions/820.json"
clear_logs; agents_jump 820 >/dev/null
[[ "$(log herdr)" == *"agent focus w9:p9"* ]] || fail "Herdr: no last-resort guess for a known session: $(log herdr)"
rm -f "$CLAUDE_CONFIG_DIR/sessions/820.json"
printf '%s\n' "$HERDR_AGENTS" > "$tmp/herdr.json"
pass "jump: a Herdr pane by session id, else its processes, else (a known session) its directory; then the Herdr client's terminal tab"

clear_logs
out="$(agents_jump 601)" || fail "jump to Ghostty failed: $out"
[[ "$out" == "pid 601: Ghostty" ]] || fail "jump to Ghostty: $out"
[[ "$(log osascript)" == *'tell application "Ghostty"'*"/dev/ttys001"* ]] || fail "Ghostty's terminal by tty: $(log osascript)"
clear_logs; agents_jump 960 >/dev/null
[[ "$(log osascript)" == *'tell application "iTerm"'*"/dev/ttys006"* ]] || fail "iTerm's session by tty: $(log osascript)"
clear_logs
! agents_jump --notify 920 2>/dev/null || fail "jump to an ssh session succeeded"
[[ "$(log notify)" == *"ssh session"* ]] || fail "a failed menu jump does not notify"
! agents_jump 4242 2>/dev/null || fail "jump to a pid that is gone"
! agents_jump "601@Mon_Jan_01_00:00:00_2024" 2>/dev/null || fail "jump to a reused pid"
[[ "$(agents_jump x 2>&1)" == usage:* ]] || fail "jump usage"
pass "jump: a terminal tab by tty (Ghostty, iTerm, Terminal); ssh and gone pids fail, the menu gets a notification"

# --- agents peek ------------------------------------------------------------------------
clear_logs
out="$(agents_peek 721 60)"; [[ "$out" == *"tmux work:1.2"*"pane text" && "$(log tmux)" == *"capture-pane -p -J -S -60 -t %15"* ]] || fail "peek tmux: $out / $(log tmux)"
out="$(agents_peek 820)"; [[ "$out" == *"Herdr w2:p1"*"herdr pane text" && "$(log herdr)" == *"pane read w2:p1 --lines 40 --format text"* ]] || fail "peek Herdr: $out / $(log herdr)"
# Peek never guesses: a pane it cannot tell is not read, even with another
# agent alone in the directory (and a session id it knows).
printf '%s\n' '{"result":{"agents":[{"pane_id":"w9:p9","agent":"claude","cwd":"/work/api","agent_session":{"value":"zzz"}}]}}' > "$tmp/herdr.json"
printf '{"sessionId":"sess-820"}\n' > "$CLAUDE_CONFIG_DIR/sessions/820.json"
clear_logs
if out="$(agents_peek 820 2>&1)"; then fail "peek guessed a Herdr pane: $out"; fi
[[ "$out" == *"its pane was not found"* && "$(log herdr)" != *"pane read"* ]] || fail "peek guessed a Herdr pane: $out / $(log herdr)"
printf '%s\n' '{"result":{"agents":[{"pane_id":"w9:p9","agent":"claude","cwd":"/work/api"},{"pane_id":"w8:p1","agent":"claude","cwd":"/y","agent_session":{"value":"sess-820"}}]}}' > "$tmp/herdr.json"
clear_logs; out="$(agents_peek 820)"; [[ "$(log herdr)" == *"pane read w8:p1"* ]] || fail "peek by session id: $out / $(log herdr)"
rm -f "$CLAUDE_CONFIG_DIR/sessions/820.json"; printf '%s\n' "$HERDR_AGENTS" > "$tmp/herdr.json"
[[ "$(agents_peek 601 2>&1)" == *"not in a tmux or Herdr pane (it runs in Ghostty)"* ]] || fail "peek a Ghostty tab"
[[ "$(agents_peek 721 0 2>&1)" == usage:* && "$(agents_peek 721 3000 2>&1)" == usage:* ]] || fail "peek LINES bounds"
pass "peek: a tmux pane's last lines, a Herdr pane's through herdr pane read; nothing else"

# --- agents show ------------------------------------------------------------------------
_agents_show_proc() { printf 'f\tfiles\t12\nf\tthreads\t9\n'; }
mkdir -p "$tmp/repo/.git" "$CLAUDE_CONFIG_DIR/projects/-repo"
echo "ref: refs/heads/feat-x" > "$tmp/repo/.git/HEAD"
printf '{"sessionId":"sess-600","name":"repo-1","status":"busy","version":"2.1.300"}\n' > "$CLAUDE_CONFIG_DIR/sessions/600.json"
tx="$CLAUDE_CONFIG_DIR/projects/-repo/sess-600.jsonl"
{
    # A long first part that must not be read, then the end.
    head -c 300000 /dev/zero | tr '\0' 'x'; echo
    jq -nc '{type: "assistant", timestamp: "2026-10-14T08:59:00.000Z", message: {model: "claude-test-1", content: [{type: "text", text: "Looking at it.\nRunning the tests now."}]}}'
    jq -nc '{type: "assistant", timestamp: "2026-10-14T08:59:30.000Z", message: {model: "claude-test-1", content: [{type: "tool_use", name: "Bash", input: {command: "go test ./...", description: "run"}}]}}'
} > "$tx"
agents_session_tokens() { [[ "$1" == sess-600 ]] && printf 'sess-600\tyou\tclaude\trepo\tclaude-test-1\t42\t1234567\t3.40\t0\n'; }
out="$(agents_show 601)" || fail "show failed: $out"
for want in "command · go test ./..." "in claude 600" "session   repo-1 · sess-600" "model     claude-test-1 · claude 2.1.300" \
            "tokens    1.2M · 42 calls" "cost      \$3.40 API-equivalent" "origin    you" "project   repo · branch feat-x" "where     Ghostty" \
            "cpu       50.0% now" "9 threads" "files     12 open" "doing     Bash: go test ./..." 'said      "Running the tests now."' \
            "children (1)" "x.test"; do
    [[ "$out" == *"$want"* ]] || fail "show 601 lacks '$want':"$'\n'"$out"
done
out="$(agents_show 721)"
[[ "$out" == "MCP server playwright"* && "$out" == *"where     tmux pane work:1.2"* && "$out" == *"named by its package"* ]] || fail "show an MCP server:"$'\n'"$out"
json="$(agents_show --json 601)"
printf '%s' "$json" | jq -e '.schema_version == 1 and .class == "tool" and .session.id == "sess-600" and .session.model == "claude-test-1"
    and .activity.tool == "Bash" and .activity.target == "go test ./..." and .where.kind == "app" and .where.place == "Ghostty"
    and .threads == 9 and .open_files == 12 and .branch == "feat-x" and (.children | length) == 1 and .info.tokens == "1.2M · 42 calls" and .info.origin == "you"' >/dev/null \
    || fail "show --json: $json"
[[ "$out" != *"part unpriced"* ]] || fail "a session priced whole says part of it is unpriced"
# Some of its tokens (a subagent's model) have no price: the cost says so.
agents_session_tokens() { [[ "$1" == sess-600 ]] && printf 'sess-600\tyou\tclaude\trepo\tclaude-test-1\t42\t1234567\t3.40\t105000\n'; }
[[ "$(agents_show 601)" == *"cost      \$3.40 API-equivalent (part unpriced)"* ]] || fail "a session priced in part: $(agents_show 601 | grep cost)"
agents_session_tokens() { :; }
[[ "$(agents_show 601)" != *tokens* ]] || fail "a session the scanner has not seen shows no tokens"
! agents_show 4242 2>/dev/null || fail "show a pid that is gone"
[[ "$(agents_show 2>&1)" == usage:* && "$(agents_show --watch --json 601 2>&1)" == *"not JSON"* ]] || fail "show usage"
# Claude Code's record of a pid is checked against the process's start.
printf '{"sessionId":"sess-x","procStart":"Mon Jan  1 00:00:00 2024"}\n' > "$CLAUDE_CONFIG_DIR/sessions/600.json"
[[ "$(agents_show 601)" != *sess-x* ]] || fail "a stale session record names a new process"
pass "show: what it is, its session (id, name, model, version; origin, tokens and API-equivalent cost once the scanner has seen it), where, cpu, threads, files, activity, children; JSON"

# _agents_activity reads only the end of a transcript.
big="$tmp/big.jsonl"
{ jq -nc '{type: "assistant", message: {content: [{type: "tool_use", name: "Early", input: {}}]}}'; head -c 400000 /dev/zero | tr '\0' 'y'; echo; } > "$big"
[[ "$(_agents_activity "$big")" != *Early* ]] || fail "activity read past the last $_AGENTS_ACTIVITY_TAIL bytes"
pass "activity: only the transcript's last bytes are read"

# Git branches without git.
mkdir -p "$tmp/wt/sub" "$tmp/gitdir"; echo "gitdir: $tmp/gitdir" > "$tmp/wt/.git"; echo "ref: refs/heads/topic" > "$tmp/gitdir/HEAD"
[[ "$(_agents_git_branch "$tmp/wt/sub")" == topic ]] || fail "a worktree's branch"
echo 0123456789abcdef > "$tmp/gitdir/HEAD"
[[ "$(_agents_git_branch "$tmp/wt")" == "detached at 01234567" ]] || fail "a detached HEAD"
[[ -z "$(_agents_git_branch /)" ]] || fail "no repository"
pass "git branch from .git/HEAD (worktrees too), no git command"

# --- agents pick ------------------------------------------------------------------------
list="$(agents_pick --list)"
[[ "$(printf '%s\n' "$list" | head -1)" == $'PID\t-\tTYPE'* ]] || fail "pick list header: $list"
printf '%s\n' "$list" | grep -q $'^721\t721@Wed_Oct_14_08:00:00_2026\t  mcp .*playwright' || fail "pick list: an MCP server under its session:"$'\n'"$list"
printf '%s\n' "$list" | awk -F '\t' 'NR > 1 && ($1 !~ /^[0-9]+$/ || $2 !~ /^[0-9]+@[A-Za-z0-9_:]+$/) { bad = 1 } END { exit bad }' || fail "pick list fields"
stub fzf 'exit 1'
argv="$(_agents_pick_argv)"
for want in "--preview" "show {1}" "enter:execute-silent(" "jump {2})" "ctrl-p:execute(" "peek {2}" "ctrl-d:execute(" "show --watch {2})" \
            "ctrl-k:execute(" "kill {2}" "ctrl-r:reload-sync(" "every(2):reload-sync(" "--id-nth"; do
    [[ "$argv" == *"$want"* ]] || fail "pick's fzf lacks '$want':"$'\n'"$argv"
done
stub fzf 'exit 2'
[[ "$(_agents_pick_argv)" != *"every("* ]] || fail "an older fzf gets every()"
rm -f "$tmp/bin/fzf"
out="$(AGENTS_FZF=fzf-not-installed agents_pick 2>&1)" || true
[[ "$out" == *"pick needs fzf"*"AGENTS ("* ]] || fail "pick without fzf: $out"
pass "pick: the list (pid, PID@START, line), fzf's preview and keys, every() only where fzf has it; agents ls without fzf"

echo "All agents show tests passed."
