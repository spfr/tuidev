#!/bin/bash
# Unit tests for the token scanner (lib/agents/tokens.sh): tokens.tsv,
# compacts.tsv, denials.tsv, limits.tsv, tokens.today and tokens.state, from
# synthetic Claude Code and Codex transcripts.
# Run: bash scripts/lib/test_agents_tokens.sh  -> exit 0 on pass.
#
# Everything runs against fixture transcripts in temp dirs (CLAUDE_CONFIG_DIR,
# CODEX_HOME): nothing real is read. The clock is the real one (the scan
# compares it with the files' mtimes); fixture times are an hour before now.

# Tests change variables inside ( … ) on purpose; the stubs are called by the
# sourced functions.
# shellcheck disable=SC2030,SC2031,SC2034,SC2317,SC2329
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/tuidev-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home" NO_COLOR=1 TZ=UTC AGENTS_CONF="$tmp/none.conf" AGENTS_DATA_DIR="$tmp/data" AGENTS_RUN_DIR="$tmp/run"
export AGENTS_TESTING=1 AGENTS_NO_HERDR=1 CLAUDE_CONFIG_DIR="$tmp/claude" CODEX_HOME="$tmp/codex"
unset AGENTS_HISTORY AGENTS_HISTORY_DAYS
mkdir -p "$HOME"

# shellcheck source=../../bin/agents disable=SC1091
. "$REPO_DIR/bin/agents"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "PASS: $1"; }

# The fixtures set transcripts' mtimes back (old): every scan lists them all
# (19. tests the listing of what changed since the last scan).
_AGENTS_TOKENS_FULL=0

NOW="$(date +%s)" DAY="$(date +%Y-%m-%d)"
MID=$(( NOW - NOW % 86400 ))
B=$(( NOW - 3600 )); [[ $B -ge $MID ]] || B=$MID   # fixture times: today, before now
iso() { date -u -r "$1" +%Y-%m-%dT%H:%M:%S.000Z 2>/dev/null || date -u -d "@$1" +%Y-%m-%dT%H:%M:%S.000Z; }
# old FILE MINUTES — FILE's mtime MINUTES ago.
old() { touch -t "$(date -u -r $((NOW - $2 * 60)) +%Y%m%d%H%M 2>/dev/null || date -u -d "@$((NOW - $2 * 60))" +%Y%m%d%H%M)" "$1"; }
scan() { ( umask 077; _agents_data_dir; _agents_tokens_scan "$NOW" "$DAY" ); }
# state — the scan state as one: tokens.state (cold), then tokens.hot.
state() { cat "$D/tokens.state" "$D/tokens.hot" 2>/dev/null || true; }
D="$AGENTS_DATA_DIR"

# --- Claude Code fixtures -------------------------------------------------------
S=11111111-2222-3333-4444-555555555555
P="$CLAUDE_CONFIG_DIR/projects/-work-app"; main="$P/$S.jsonl"; subs="$P/$S/subagents"
mkdir -p "$subs"
# asst ID MODEL SECS IN CW CR OUT BLOCK [CWD] — one assistant line (one
# content block), at B + SECS, from Claude Code's CLI (EP: another
# entrypoint); W1H: of CW, those cached for an hour (usage.cache_creation).
asst() {
    local cc=""
    [[ -z "${W1H:-}" ]] || cc=',"cache_creation":{"ephemeral_1h_input_tokens":'"$W1H"',"ephemeral_5m_input_tokens":'"$(($5 - W1H))"'}'
    printf '{"parentUuid":"p-%s","isSidechain":false,"message":{"model":"%s","id":"%s","type":"message","role":"assistant","content":[%s],"stop_reason":null,"usage":{"input_tokens":%s,"cache_creation_input_tokens":%s,"cache_read_input_tokens":%s,"output_tokens":%s%s,"iterations":[{"input_tokens":9,"output_tokens":9,"cache_creation":{"ephemeral_1h_input_tokens":7}}]}},"requestId":"req_%s","type":"assistant","uuid":"u-%s-%s","timestamp":"%s","userType":"external","entrypoint":"%s","cwd":"%s","sessionId":"%s"}\n' \
        "$1" "$2" "$1" "$8" "$4" "$5" "$6" "$7" "$cc" "$1" "$1" "$RANDOM" "$(iso $((B + $3)))" "${EP:-cli}" "${9:-/work/app}" "$S"
}
think='{"type":"thinking","thinking":"","signature":"x"}'
text='{"type":"text","text":"Done: \"ok\" {\"type\":\"user\"}"}'
bash_tu() { printf '{"type":"tool_use","id":"%s","name":"Bash","input":{"command":"%s","description":"d"},"caller":{"type":"direct"}}' "$1" "$2"; }
tool_tu() { printf '{"type":"tool_use","id":"%s","name":"%s","input":%s}' "$1" "$2" "$3"; }
# user SECS RESULT_BLOCKS — a user line holding tool results.
user() {
    printf '{"parentUuid":"p","isSidechain":false,"promptId":"x","type":"user","message":{"role":"user","content":[%s]},"uuid":"uu-%s","timestamp":"%s","toolUseResult":"Error: x","cwd":"/work/app","sessionId":"%s"}\n' \
        "$2" "$RANDOM" "$(iso $((B + $1)))" "$S"
}
plain() { printf '{"type":"user","message":{"role":"user","content":"next"},"uuid":"up-%s","timestamp":"%s"}\n' "$RANDOM" "$(iso $((B + $1)))"; }
CLS='Permission for this action was denied by the Claude Code auto mode classifier. Reason: [Git Destructive]. If you have other tasks that don'"'"'t depend on this action, continue.'
SAF='Permission for this command was denied by a built-in Claude Code safety check, not by the user. The check stops removals.'
USR='The user doesn'"'"'t want to proceed with this tool use. The tool use was rejected (eg. if it was a file edit, the new_string was NOT written to the file).'
{
    plain 0
    # A: two lines, one message (thinking, then a sleep): counted once, a poll;
    # 60 of its 100 cache writes for an hour.
    W1H=60 asst msg_A claude-test-1 1 3 100 1000 50 "$think"
    W1H=60 asst msg_A claude-test-1 2 3 100 1000 50 "$(bash_tu toolu_A 'sleep 30')"
    user 3 '{"tool_use_id":"toolu_A","type":"tool_result","content":"","is_error":false}'
    # B: git push and a WebFetch (one line each); the classifier denies the
    # push (content first, id after), the user the fetch (text array, id first).
    asst msg_B claude-test-1 4 5 200 2000 60 "$(bash_tu toolu_B 'cd /work/app && git -C /work/app push --force origin main')"
    asst msg_B claude-test-1 5 5 200 2000 60 "$(tool_tu toolu_W WebFetch '{"url":"https://user:pw@Docs.Example.COM:8443/private/path?token=abc","prompt":"p"}')"
    user 6 '{"type":"tool_result","content":"'"$CLS"'","is_error":true,"tool_use_id":"toolu_B"}'
    user 7 '{"tool_use_id":"toolu_W","type":"tool_result","content":[{"type":"text","text":"'"$USR"'"}],"is_error":true}'
    # Quoting a denial is not one: not an error, or not at the start.
    user 8 '{"tool_use_id":"toolu_X","type":"tool_result","content":"# notes: '"$USR"'","is_error":false}'
    user 8 '{"tool_use_id":"toolu_Y","type":"tool_result","content":"Error: '"$SAF"'","is_error":true}'
    # C: synthetic, no API call.
    asst msg_C '<synthetic>' 9 0 0 0 0 "$text"
    # D: rm -rf, stopped by the safety check; an Edit with a polling Bash in
    # the same message: not a poll.
    asst msg_D claude-test-2 10 7 0 3000 70 "$(bash_tu toolu_D 'sudo -u root rm -rf /work/app/build')"
    asst msg_D claude-test-2 11 7 0 3000 70 "$(tool_tu toolu_E Edit '{"file_path":"/work/app/x","old_string":"a","new_string":"b"}')"
    user 12 '{"tool_use_id":"toolu_D","type":"tool_result","content":"'"$SAF"'","is_error":true}'
    printf '{"parentUuid":null,"logicalParentUuid":"x","isSidechain":false,"type":"system","subtype":"compact_boundary","content":"Conversation compacted","isMeta":false,"timestamp":"%s","uuid":"c1","level":"info","compactMetadata":{"trigger":"auto","preTokens":180000,"postTokens":12000,"durationMs":5},"cwd":"/work/app","sessionId":"%s"}\n' "$(iso $((B + 13)))" "$S"
    # E: a reply in a worktree, then the session goes on.
    asst msg_E claude-test-2 14 1 10 20 30 "$text" /work/app/.claude/worktrees/feat
    plain 15
} > "$main"
# Subagent abc (Explore): its first line copies main's message B (a fork's
# context); then its own message F, a poll of a task's output file.
{
    printf '{"parentUuid":null,"isSidechain":true,"agentId":"abc","message":{"model":"claude-test-1","id":"msg_B","type":"message","role":"assistant","content":[%s],"usage":{"input_tokens":5,"cache_creation_input_tokens":200,"cache_read_input_tokens":2000,"output_tokens":60}},"type":"assistant","uuid":"f1","timestamp":"%s","cwd":"/work/app","sessionId":"%s"}\n' "$(bash_tu toolu_B 'git push')" "$(iso $((B + 4)))" "$S"
    asst msg_F claude-test-3 20 11 0 500 5 "$(bash_tu toolu_F 'sleep 10 && tail -5 /tmp/claude-501/-work-app/'"$S"'/tasks/b1x.output | grep -c ok')"
    plain 21
} > "$subs/agent-abc.jsonl"
printf '{"agentType":"Explore"}' > "$subs/agent-abc.meta.json"
# Subagent def: customAgentType wins.
{ asst msg_G claude-test-3 22 13 0 0 1 "$text"; plain 23; } > "$subs/agent-def.jsonl"
printf '{"agentType":"general-purpose","customAgentType":"implementor-complex"}' > "$subs/agent-def.meta.json"
# Subagent ghi: no meta.json.
{ asst msg_H claude-test-3 24 17 0 0 1 "$text"; plain 25; } > "$subs/agent-ghi.jsonl"

# --- Codex fixture ---------------------------------------------------------------
U=019f0000-aaaa-7bbb-8ccc-0123456789ab
CX="$CODEX_HOME/sessions/2026/10/14"; mkdir -p "$CX"; rollout="$CX/rollout-2026-10-14T09-00-00-$U.jsonl"
tc() {   # SECS TOTAL IN CACHED OUT USED_PCT — a token_count event
    printf '{"timestamp":"%s","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1,"cached_input_tokens":1,"output_tokens":1,"reasoning_output_tokens":0,"total_tokens":%s},"last_token_usage":{"input_tokens":%s,"cached_input_tokens":%s,"cache_write_input_tokens":0,"output_tokens":%s,"reasoning_output_tokens":4,"total_tokens":1},"model_context_window":1000},"rate_limits":{"limit_id":"codex","primary":{"used_percent":%s,"window_minutes":300,"resets_at":%s},"secondary":{"used_percent":40.0,"window_minutes":10080,"resets_at":1}}}}\n' \
        "$(iso $((B + $1)))" "$2" "$3" "$4" "$5" "$6" $((NOW + 7200))
}
{
    printf '{"timestamp":"%s","type":"session_meta","payload":{"session_id":"%s","id":"%s","cwd":"/work/svc","originator":"codex-tui"}}\n' "$(iso $((B + 30)))" "$U" "$U"
    printf '{"timestamp":"%s","type":"turn_context","payload":{"turn_id":"t1","cwd":"/work/svc","model":"gpt-test-1","effort":"high"}}\n' "$(iso $((B + 31)))"
    printf '{"timestamp":"%s","type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":{"primary":{"used_percent":10.0,"window_minutes":300,"resets_at":1}}}}\n' "$(iso $((B + 32)))"
    tc 33 1000 800 600 200 12.0
    tc 34 1000 800 600 200 12.0           # the same turn, logged twice
    printf '{"timestamp":"%s","type":"response_item","payload":{"type":"message","content":"token_count"}}\n' "$(iso $((B + 35)))"
    tc 36 1500 400 100 100 12.5
} > "$rollout"
old "$main" 10; old "$subs/agent-abc.jsonl" 10; old "$subs/agent-def.jsonl" 10; old "$subs/agent-ghi.jsonl" 10; old "$rollout" 10

mkdir -p "$tmp/orig"; cp -R "$CLAUDE_CONFIG_DIR" "$CODEX_HOME" "$tmp/orig/"   # for 7.

# 1. One scan of everything.
scan || fail "scan failed"
want_tokens="$(printf '%s\n' \
    "$((B + 1))	claude	app	$S	main	claude-test-1	3	100	1000	50	1	60	you" \
    "$((B + 4))	claude	app	$S	main	claude-test-1	5	200	2000	60	0	0	you" \
    "$((B + 10))	claude	app	$S	main	claude-test-2	7	0	3000	70	0	0	you" \
    "$((B + 14))	claude	app/feat	$S	main	claude-test-2	1	10	20	30	0	0	you" \
    "$((B + 20))	claude	app	$S	Explore	claude-test-3	11	0	500	5	1	0	subagent" \
    "$((B + 22))	claude	app	$S	implementor-complex	claude-test-3	13	0	0	1	0	0	subagent" \
    "$((B + 24))	claude	app	$S	-	claude-test-3	17	0	0	1	0	0	subagent" \
    "$((B + 33))	codex	svc	$U	main	gpt-test-1	200	0	600	200	0	0	you" \
    "$((B + 36))	codex	svc	$U	main	gpt-test-1	300	0	100	100	0	0	you")"
got="$(LC_ALL=C sort "$D/tokens.tsv")"
[[ "$got" == "$want_tokens" ]] || fail "tokens.tsv:"$'\n'"$got"$'\n'"want:"$'\n'"$want_tokens"
pass "tokens.tsv: one row per message id (duplicated lines once, a fork's copy and <synthetic> never), subagent types (customAgentType first, - without meta), Codex turns once with cached input as cache_read, polls"

got="$(cat "$D/compacts.tsv")"
[[ "$got" == "$((B + 13))	claude	app	$S	main	auto	180000	12000" ]] || fail "compacts.tsv: $got"
want="$(printf '%s\n' \
    "$((B + 6))	claude	app	$S	main	Bash	classifier	Git Destructive	git push" \
    "$((B + 7))	claude	app	$S	main	WebFetch	user	-	docs.example.com" \
    "$((B + 12))	claude	app	$S	main	Bash	safety	-	rm")"
got="$(LC_ALL=C sort "$D/denials.tsv")"
[[ "$got" == "$want" ]] || fail "denials.tsv:"$'\n'"$got"$'\n'"want:"$'\n'"$want"
! grep -qE 'force|origin|main$|private|token|pw|/work' <(cut -f9 "$D/denials.tsv") || fail "a denial's subject holds arguments: $(cut -f9 "$D/denials.tsv")"
pass "compacts.tsv; denials.tsv: classifier tag, safety, user; Bash program and subcommand, WebFetch host only, never arguments; a quoted denial is not one"

[[ "$(cat "$D/limits.tsv")" == "$((B + 36))	codex	12.5	300	$((NOW + 7200))" ]] || fail "limits.tsv: $(cat "$D/limits.tsv")"
sum="$(LC_ALL=C awk -F '\t' -v m="$MID" '$1 >= m { i += $7; w += $8; r += $9; o += $10 } END { printf "%d\t%d\t%d\t%d\t%d", i + w + r + o, i, w, r, o }' "$D/tokens.tsv")"
[[ "$(cat "$D/tokens.today")" == "$DAY	$sum" ]] || fail "tokens.today: $(cat "$D/tokens.today") want $DAY $sum"
pass "limits.tsv holds Codex's latest primary limit; tokens.today today's sums"

# 2. Nothing new: nothing added; the state stays.
st="$(state)"
scan; [[ "$(LC_ALL=C sort "$D/tokens.tsv")" == "$want_tokens" && "$(wc -l < "$D/denials.tsv")" -eq 3 ]] || fail "a second scan added rows"
[[ "$(state)" == "$st" ]] || fail "a second scan changed the state"
[[ "$(cat "$D/tokens.today")" == "$DAY	$sum" ]] || fail "tokens.today after a second scan: $(cat "$D/tokens.today")"
pass "a scan with nothing new adds nothing"

# 3. A message split across scans: its first line, in an active transcript,
# waits for the rest; then it counts once, a poll from both lines.
rows() { wc -l < "$D/tokens.tsv" | tr -d ' '; }
n0=$(rows)
asst msg_I claude-test-1 40 1 1 1 1 "$think" >> "$main"
scan; [[ $(rows) -eq $n0 ]] || fail "the first line of an active transcript's last message counted"
asst msg_I claude-test-1 41 1 1 1 1 "$(bash_tu toolu_I 'tail -20 /tmp/claude-501/-work-app/x/tasks/bq1.output')" >> "$main"
plain 42 >> "$main"
scan; [[ $(rows) -eq $((n0 + 1)) ]] || fail "msg_I: $(rows) rows, want $((n0 + 1))"
grep -q "^$((B + 40))	claude	app	$S	main	claude-test-1	1	1	1	1	1	0	you\$" "$D/tokens.tsv" || fail "msg_I row: $(tail -1 "$D/tokens.tsv")"
# A quiet transcript's last message counts as is; its late line does not again.
asst msg_J claude-test-1 43 2 2 2 2 "$text" >> "$main"; old "$main" 10
scan; [[ $(rows) -eq $((n0 + 2)) ]] || fail "a quiet transcript's last message did not count"
{ asst msg_J claude-test-1 44 2 2 2 2 "$text"; plain 45; } >> "$main"
scan; [[ $(rows) -eq $((n0 + 2)) ]] || fail "msg_J counted twice across scans"
pass "a message split across scans counts once (held back while active, deduped by id once counted)"

# 4. A line still being written is left for the next scan.
printf '%s' "$(asst msg_K claude-test-1 46 3 3 3 3 "$text")" >> "$main"
scan; [[ $(rows) -eq $((n0 + 2)) ]] || fail "a partial line counted"
{ printf '\n'; plain 47; } >> "$main"
scan; [[ $(rows) -eq $((n0 + 3)) ]] || fail "$(rows) rows, want $((n0 + 3))"; grep -q "^$((B + 46))	.*	3	3	3	3	0	0	you\$" "$D/tokens.tsv" || fail "msg_K after its line ended: $(tail -2 "$D/tokens.tsv")"
pass "a partial last line waits until it is whole"

# 5. A truncated or replaced transcript starts again from 0: only rows newer
# than the last one counted.
{ asst msg_A claude-test-1 1 3 100 1000 50 "$text"; asst msg_L claude-test-1 60 4 4 4 4 "$text"; plain 61; } > "$main"
scan; [[ $(rows) -eq $((n0 + 4)) ]] || fail "$(rows) rows, want $((n0 + 4))"; grep -q "^$((B + 60))	.*	4	4	4	4	0	0	you\$" "$D/tokens.tsv" || fail "truncated restart: $(tail -3 "$D/tokens.tsv")"
{ cat "$main"; asst msg_M claude-test-1 62 5 5 5 5 "$text"; plain 63; } > "$main.new"; mv "$main.new" "$main"
scan; [[ $(rows) -eq $((n0 + 5)) ]] || fail "$(rows) rows, want $((n0 + 5))"; grep -q "^$((B + 62))	.*	5	5	5	5	0	0	you\$" "$D/tokens.tsv" || fail "replaced restart: $(tail -3 "$D/tokens.tsv")"
pass "a truncated or replaced transcript is read again from 0, counting only what is newer"

# 6. Retention: a transcript unchanged for longer than AGENTS_HISTORY_DAYS is
# never read; a row older than that is never written.
P2="$CLAUDE_CONFIG_DIR/projects/-work-old"; mkdir -p "$P2"
{ asst msg_O claude-test-1 70 9 9 9 9 "$text"; plain 71; } > "$P2/22222222-0000-0000-0000-000000000000.jsonl"
old "$P2/22222222-0000-0000-0000-000000000000.jsonl" $((40 * 1440))
{ B=$((NOW - 40 * 86400)) asst msg_P claude-test-1 0 8 8 8 8 "$text"; plain 72; } > "$P2/33333333-0000-0000-0000-000000000000.jsonl"
old "$P2/33333333-0000-0000-0000-000000000000.jsonl" 10
scan
! grep -q 22222222 <(state) || fail "a transcript older than the window was read"
grep -q 33333333 <(state) || fail "a fresh transcript was not read"
! grep -qE '	(9|8)	(9|8)	(9|8)	(9|8)	0$' "$D/tokens.tsv" || fail "a row older than the window was written"
pass "retention: old transcripts are skipped, old rows never written"

# 7. The byte cap: a small budget reads a little per scan and resumes; the
# result is the same as one scan with the default budget.
(
    CLAUDE_CONFIG_DIR="$tmp/orig/claude" CODEX_HOME="$tmp/orig/codex"
    AGENTS_DATA_DIR="$tmp/full"; D="$tmp/full"; scan
    AGENTS_DATA_DIR="$tmp/capped"; D="$tmp/capped"; _AGENTS_TOKENS_BUDGET=2500
    n=0
    while [[ $n -lt 200 ]]; do
        scan; n=$((n + 1))
        left="$(_agents_tokens_list | _agents_awk tokens_plan -F '\t' -v OFS='\t' -v sf="$D/tokens.state" -v hf="$D/tokens.hot" | LC_ALL=C awk -F '\t' '$1 == 1' | wc -l | tr -d ' ')"
        [[ "$left" != 0 ]] || break
    done
    [[ $n -gt 3 ]] || fail "a 2500-byte budget read everything in $n scans"
    [[ "$(wc -l < "$tmp/full/tokens.tsv")" -eq 9 && -s "$tmp/full/denials.tsv" && -s "$tmp/full/compacts.tsv" ]] || fail "the uncapped scan: $(ls "$tmp/full")"
    for f in tokens.tsv compacts.tsv denials.tsv limits.tsv tokens.today; do
        [[ "$(LC_ALL=C sort "$tmp/capped/$f")" == "$(LC_ALL=C sort "$tmp/full/$f")" ]] \
            || fail "capped scans' $f differs:"$'\n'"$(diff <(LC_ALL=C sort "$tmp/capped/$f") <(LC_ALL=C sort "$tmp/full/$f"))"
    done
    echo "    (a 2500-byte budget: $n scans)"
)
pass "a byte budget resumes where it stopped, with the same rows"

# 8. Pruning goes with history.tsv; AGENTS_HISTORY=0 reads and writes nothing.
pd="$tmp/prune"; mkdir -p "$pd"
for f in tokens compacts denials limits; do printf '%s\tx\n%s\tx\n' $((NOW - 31 * 86400)) $((NOW - 60)) > "$pd/$f.tsv"; done
( AGENTS_DATA_DIR="$pd"; _agents_history_prune "$NOW" "$DAY" )
for f in tokens compacts denials limits; do [[ "$(cut -f1 "$pd/$f.tsv")" == $((NOW - 60)) ]] || fail "$f.tsv not pruned: $(cat "$pd/$f.tsv")"; done
( AGENTS_HISTORY=0; AGENTS_DATA_DIR="$tmp/off"; _agents_tokens_scan "$NOW" "$DAY" ) || fail "scan with history off failed"
[[ ! -e "$tmp/off" ]] || fail "AGENTS_HISTORY=0 wrote $(ls "$tmp/off")"
perm() { if [[ "$(uname)" == Darwin ]]; then stat -f %Lp "$1"; else stat -c %a "$1"; fi; }
for f in tokens.tsv compacts.tsv denials.tsv limits.tsv tokens.today tokens.hot; do
    [[ "$(perm "$D/$f")" == 600 ]] || fail "$f mode $(perm "$D/$f")"
done
for f in "$D"/tokens.add.* "$D"/*.new; do [[ ! -e "$f" ]] || fail "scratch file left: $f"; done
pass "the token files are pruned with history, private (600), and absent with AGENTS_HISTORY=0"

# 9. In agents sample: a scan runs after the ledger, and a scan that fails
# (even one that exits) never stops the sample.
pl() { printf '%5s %5s   501 me      1.0 %7s %4d:%02d.00 %8d:%02d Wed Oct 14 %s 2026     %s\n' \
    "$1" "$2" "$5" $(($3 / 60)) $(($3 % 60)) $(($4 / 60)) $(($4 % 60)) "$6" "$7"; }
agents_snapshot() { pl 1 0 0 99999 20000 08:00:00 /sbin/launchd; pl 290 1 0 9999 3000 04:00:00 -zsh; }
_agents_keep_pids() { :; }; _agents_listeners() { :; }; _agents_cwds() { :; }
AGENTS_UID=501 AGENTS_SELF=9999
(
    AGENTS_DATA_DIR="$tmp/sample"
    agents_sample || fail "agents sample failed"
    [[ -s "$tmp/sample/tokens.tsv" && -f "$tmp/sample/runs.state" && -f "$tmp/sample/tokens.today" ]] || fail "agents sample did not scan: $(ls "$tmp/sample")"
    _agents_tokens_scan() { exit 7; }
    rm -f "$tmp/sample/prune.stamp"
    err="$(agents_sample 2>&1)" || fail "a failing scan failed the sample: $err"
    [[ "$err" == *"token scan failed"* ]] || fail "a failing scan was silent: $err"
    [[ -f "$tmp/sample/prune.stamp" ]] || fail "the sample stopped at the failing scan"
)
pass "agents sample scans tokens, and a failing scan never stops it"

# 10. A transcript not listed in one sample (a CLAUDE_CONFIG_DIR or
# CODEX_HOME not set for it, a file gone for a while) keeps its state: listed
# again, it goes on from its offset, never counting a row twice. A state line
# whose last row is older than the window is dropped.
(
    src="$tmp/f1src"; mkdir -p "$src"; cp -R "$tmp/orig/claude" "$tmp/orig/codex" "$src/"
    CLAUDE_CONFIG_DIR="$src/claude" CODEX_HOME="$src/codex" AGENTS_DATA_DIR="$tmp/f1"; D="$tmp/f1"
    scan; n=$(rows)
    [[ $n -eq 9 ]] || fail "F1: the first scan: $n rows"
    st="$(state)"
    ( CLAUDE_CONFIG_DIR="$tmp/f1empty" CODEX_HOME="$tmp/f1empty"; mkdir -p "$tmp/f1empty"; scan )
    [[ "$(state)" == "$st" ]] || fail "F1: a sample that listed nothing changed the state:"$'\n'"$(state)"
    scan; [[ $(rows) -eq $n ]] || fail "F1: a transcript listed again was counted again: $(rows) rows, want $n"
    m="$src/claude/projects/-work-app/$S.jsonl"
    ( CLAUDE_CONFIG_DIR="$tmp/f1empty"; scan )
    { asst msg_N claude-test-1 80 6 6 6 6 "$text"; plain 81; } >> "$m"; old "$m" 10
    scan; [[ $(rows) -eq $((n + 1)) ]] || fail "F1: after an unlisted sample, $(rows) rows, want $((n + 1))"
    grep -q "^$((B + 80))	.*	6	6	6	6	0	0	you\$" "$D/tokens.tsv" || fail "F1: the new message: $(tail -1 "$D/tokens.tsv")"
    # Carried while its last row is in the window, then dropped: a hot line
    # by the next scan, a cold one (an older agents' line, 12 fields) by the
    # daily compaction.
    printf '%s\tclaude\t1\t10\t%s\tmsg_x\t-\t-\tmain\t-\t-\t-\n' /gone/recent.jsonl $((NOW - 86400)) /gone/old.jsonl $((NOW - 31 * 86400)) >> "$D/tokens.hot"
    printf '%s\tclaude\t1\t10\t%s\tmsg_x\t-\t-\tmain\t-\t-\t-\n' /gone/recent2.jsonl $((NOW - 86400)) /gone/old2.jsonl $((NOW - 31 * 86400)) >> "$D/tokens.state"
    scan
    grep -q '^/gone/recent.jsonl	' "$D/tokens.hot" || fail "F1: a recent unlisted transcript's hot state was dropped"
    ! grep -q '^/gone/old.jsonl	' "$D/tokens.hot" || fail "F1: an unlisted transcript's hot state older than the window was kept"
    grep -q '^/gone/old2.jsonl	' "$D/tokens.state" || fail "F1: a scan rewrote tokens.state"
    _agents_tokens_compact "$NOW" $((NOW - 30 * 86400))
    grep -q '^/gone/recent2.jsonl	' "$D/tokens.state" || fail "F1: the compaction dropped a recent unlisted transcript's state"
    ! grep -q '^/gone/old2\?.jsonl	' <(state) || fail "F1: the compaction kept a state older than the window"
    scan; [[ $(rows) -eq $((n + 1)) ]] || fail "F1: after a compaction, $(rows) rows, want $((n + 1))"
)
pass "a transcript missing from one sample keeps its state and goes on from its offset; one older than the window is forgotten"

# 11. A fork a subagent spawned starts with a copy of that subagent's
# history (the same message ids and times, its own agentId): only its own
# messages count, and the copied denials not again. A session rewound or
# resumed writes earlier messages again: they do not count twice.
(
    fx="$tmp/fork"; S="99999999-2222-3333-4444-555555555555"
    CLAUDE_CONFIG_DIR="$fx/claude" CODEX_HOME="$fx/codex" AGENTS_DATA_DIR="$tmp/forkd"; D="$tmp/forkd"
    fp="$fx/claude/projects/-work-app"; fs="$fp/$S/subagents"; mkdir -p "$fs"
    parent() {
        plain 100
        asst msg_P1 claude-test-1 101 1 10 100 5 "$(bash_tu toolu_P1 'git push')"
        user 102 '{"tool_use_id":"toolu_P1","type":"tool_result","content":"'"$USR"'","is_error":true}'
        asst msg_P2 claude-test-1 103 2 20 200 6 "$(tool_tu toolu_T Task '{"subagent_type":"fork"}')"
    }
    { parent; asst msg_P3 claude-test-1 110 3 30 300 7 "$text"; plain 111; } > "$fs/agent-par.jsonl"
    printf '{"agentType":"implementor-complex","spawnDepth":1}' > "$fs/agent-par.meta.json"
    { parent | sed 's/"isSidechain":false/"isSidechain":true,"agentId":"frk"/'
      asst msg_K1 claude-test-1 105 4 40 400 8 "$text"
      asst msg_K2 claude-test-1 106 5 50 500 9 "$text"; plain 107; } > "$fs/agent-frk.jsonl"
    printf '{"agentType":"fork","isFork":true,"description":"d","parentAgentId":"par","spawnDepth":2}' > "$fs/agent-frk.meta.json"
    # The main session: msg_M1, msg_M2, then msg_M1 again as it was (a
    # rewind), then msg_M3.
    { asst msg_M1 claude-test-2 0 1 1 1 1 "$text"; asst msg_M2 claude-test-2 200 2 2 2 2 "$text"
      asst msg_M1 claude-test-2 0 1 1 1 1 "$text"; asst msg_M3 claude-test-2 210 3 3 3 3 "$text"; plain 211; } > "$fp/$S.jsonl"
    for f in "$fp/$S.jsonl" "$fs"/agent-*.jsonl; do old "$f" 10; done
    mkdir -p "$tmp/forkorig"; cp -R "$fx/claude" "$tmp/forkorig/"
    scan
    want="$(printf '%s\n' \
        "$B	claude	app	$S	main	claude-test-2	1	1	1	1	0	0	you" \
        "$((B + 101))	claude	app	$S	implementor-complex	claude-test-1	1	10	100	5	0	0	subagent" \
        "$((B + 103))	claude	app	$S	implementor-complex	claude-test-1	2	20	200	6	0	0	subagent" \
        "$((B + 105))	claude	app	$S	fork	claude-test-1	4	40	400	8	0	0	fork" \
        "$((B + 106))	claude	app	$S	fork	claude-test-1	5	50	500	9	0	0	fork" \
        "$((B + 110))	claude	app	$S	implementor-complex	claude-test-1	3	30	300	7	0	0	subagent" \
        "$((B + 200))	claude	app	$S	main	claude-test-2	2	2	2	2	0	0	you" \
        "$((B + 210))	claude	app	$S	main	claude-test-2	3	3	3	3	0	0	you")"
    got="$(LC_ALL=C sort "$D/tokens.tsv")"
    [[ "$got" == "$want" ]] || fail "F2: tokens.tsv:"$'\n'"$got"$'\n'"want:"$'\n'"$want"
    [[ "$(wc -l < "$D/denials.tsv" | tr -d ' ')" == 1 ]] || fail "F2: the fork's copy of a denial counted: $(cat "$D/denials.tsv")"
    awk -F '\t' '$1 ~ /agent-frk/ && $12 != "-" { exit 1 }' <(state) || fail "F2: the fork's copied history is not marked done: $(state | grep agent-frk)"
    # Once past its copy, the parent is not read for it again.
    { asst msg_K3 claude-test-1 120 6 60 600 1 "$text"; plain 121; } >> "$fs/agent-frk.jsonl"; old "$fs/agent-frk.jsonl" 10
    ( _agents_tokens_forks() { echo "F	$fs/agent-frk.jsonl	par"; echo "I	$fs/agent-par.jsonl	msg_K3"; }; scan )
    grep -q "^$((B + 120))	.*	fork	claude-test-1	6	60	600	1	0	0	fork\$" "$D/tokens.tsv" || fail "F2: the fork's next message: $(tail -2 "$D/tokens.tsv")"
    # A budget that cuts the fork's copy in two: the same rows.
    _AGENTS_TOKENS_BUDGET=700; CLAUDE_CONFIG_DIR="$tmp/forkorig/claude"; AGENTS_DATA_DIR="$tmp/forkcap"; D="$tmp/forkcap"; n=0
    while [[ $n -lt 100 ]]; do
        scan; n=$((n + 1))
        [[ "$(_agents_tokens_list | _agents_awk tokens_plan -F '\t' -v OFS='\t' -v sf="$D/tokens.state" -v hf="$D/tokens.hot" | LC_ALL=C awk -F '\t' '$1 == 1' | wc -l | tr -d ' ')" != 0 ]] || break
    done
    [[ $n -gt 3 ]] || fail "F2: a 700-byte budget read everything in $n scans"
    [[ "$(LC_ALL=C sort "$D/tokens.tsv")" == "$want" ]] || fail "F2: in $n capped scans:"$'\n'"$(LC_ALL=C sort "$D/tokens.tsv")"
)
pass "a fork of a subagent counts only its own messages (its copied history, and the denials in it, not again); a rewound session's repeated messages count once"

# 12. A denial's subject: the program that acts (the last; past cd, echo and
# filters: cat, grep, sed, jq…, which count only when nothing else runs) and a
# known subcommand, never an option's value or another argument.
# subj CMD — CMD's subject ("\n" in it a newline).
subj() {
    C="$1" _agents_awk_eval "lib_proc lib_activity tokens" 'BEGIN { c = ENVIRON["C"]; gsub(/\\n/, "\n", c); print "S\t" bashsubj(c) }' \
        -v d="$tmp/nowhere" -v tyf=/dev/null -v frf=/dev/null < /dev/null | sed -n 's/^S	//p'
}
while IFS='%' read -r c want; do
    got="$(subj "$c")"
    [[ "$got" == "$want" ]] || fail "subject of '$c': '$got', want '$want'"
done <<'CASES'
kubectl -n prod-cluster delete pod web-1%kubectl
kubectl delete pod web-1%kubectl delete
aws --profile acme-prod s3 rm s3://bucket/key%aws
aws s3 rm s3://bucket/key%aws s3
gcloud --project acme-prod compute instances delete vm%gcloud
docker --context acme-prod run --rm img%docker
helm -n acme-prod uninstall web%helm
helm uninstall web%helm uninstall
git -C /work/app push --force origin main%git push
git frobnicate-acme%git
make deploy-acme-prod%make
cd /work/app && make deploy%make deploy
npm install left-pad%npm install
npm acme-prod%npm
cat /work/app/.env | grep KEY%cat
grep -r token . | head -5%grep
sed -n 1p x && kubectl apply -f k.yaml%kubectl apply
cat k.yaml | kubectl apply -f -%kubectl apply
git add . && git commit -m wip && git push origin main%git push
ls | xargs rm -f%rm
find . -name x | xargs%find
echo hi%echo
cd /x && ls%ls
FOO=1 sudo -u root rm -rf /work/app/build%rm
sleep 5 && curl -X POST https://acme.example/deploy%curl
grep -n "content-preview\|content-draft" Makefile | head%grep
cd /work && rg 'a|exit|b' src; make test%make test
python3 -c 'import json;print(json.dumps(1))'%python3
python3 - <<'EOF'\np='x'; s=open(p).read()\nos.remove(p)\nEOF%python3
G=~/Library/Group\ Containers; du -sh "$G" | tail -1%du
"$HOME/bin/acme-tool" --apply | tee log%tee
git commit -m "fix: a; b | c" && git push%git push
git "push" origin%git
call() { curl -s "$1"; }; call https://acme.example/x%curl
/usr/bin/time -p make build%make build
command -v acmectl >/dev/null && echo yes%command
for b in a b; do echo $b; done; exit 0%for
$(which acme) --x | grep y%grep
CASES
pass "denial subjects: the acting program, a known subcommand only when nothing comes before it, never an option's value"

# 13. grep without line byte offsets (BusyBox has no -b): the probe falls
# back to awk counting bytes, with the same rows.
(
    CLAUDE_CONFIG_DIR="$tmp/orig/claude" CODEX_HOME="$tmp/orig/codex" AGENTS_DATA_DIR="$tmp/nob"; D="$tmp/nob"
    grep() { case "$1" in -*b*) echo "grep: unrecognized option: b" >&2; return 2 ;; esac; command grep "$@"; }
    unset _AGENTS_TOKENS_GREPB
    _agents_tokens_probe; [[ "$_AGENTS_TOKENS_GREPB" == 0 ]] || fail "F4: the probe took a grep without -b"
    scan
    for f in tokens.tsv compacts.tsv denials.tsv limits.tsv tokens.today; do
        [[ "$(LC_ALL=C sort "$tmp/nob/$f")" == "$(LC_ALL=C sort "$tmp/full/$f")" ]] || fail "F4: without grep -b, $f differs:"$'\n'"$(diff <(LC_ALL=C sort "$tmp/nob/$f") <(LC_ALL=C sort "$tmp/full/$f"))"
    done
    # And a budget that cuts reads, through awk too.
    _AGENTS_TOKENS_BUDGET=2500; AGENTS_DATA_DIR="$tmp/nobcap"; D="$tmp/nobcap"; n=0
    while [[ $n -lt 200 ]]; do
        scan; n=$((n + 1))
        [[ "$(_agents_tokens_list | _agents_awk tokens_plan -F '\t' -v OFS='\t' -v sf="$D/tokens.state" -v hf="$D/tokens.hot" | LC_ALL=C awk -F '\t' '$1 == 1' | wc -l | tr -d ' ')" != 0 ]] || break
    done
    [[ "$(LC_ALL=C sort "$D/tokens.tsv")" == "$(LC_ALL=C sort "$tmp/full/tokens.tsv")" ]] || fail "F4: capped scans without grep -b differ"
)
pass "without grep -b (BusyBox), awk counts the bytes: the same rows"

# 14. Today is the sample's: a scan at 23:59:30 whose clock reads midnight
# when it runs sums the day it was given, not the next one.
(
    AGENTS_DATA_DIR="$tmp/mid"; D="$tmp/mid"
    CLAUDE_CONFIG_DIR="$tmp/orig/claude" CODEX_HOME="$tmp/orig/codex"
    N2=$((MID - 30)); D2="$(date -u -r "$N2" +%Y-%m-%d 2>/dev/null || date -u -d "@$N2" +%Y-%m-%d)"
    ( umask 077; _agents_data_dir; _agents_tokens_scan "$N2" "$D2" ) || fail "F5: the scan failed"
    [[ "$(cat "$D/tokens.today")" == "$D2	0	0	0	0	0" ]] || fail "F5: tokens.today for $D2 holds another day's sums: $(cat "$D/tokens.today")"
)
pass "tokens.today sums the sample's own day, even when the scan runs past midnight"

# 15. A NUL byte in a transcript does not hide the lines after it.
(
    AGENTS_DATA_DIR="$tmp/nul"; D="$tmp/nul"; CLAUDE_CONFIG_DIR="$tmp/nulc"; CODEX_HOME="$tmp/nulc"
    np="$tmp/nulc/projects/-work-app"; mkdir -p "$np"
    { printf '{"type":"progress","data":"a\0b"}\n'; asst msg_Z claude-test-1 5 1 2 3 4 "$text"; plain 6; } > "$np/$S.jsonl"; old "$np/$S.jsonl" 10
    scan; [[ "$(rows)" == 1 ]] || fail "F6: a NUL byte hid the rows after it: $(cat "$D/tokens.tsv" 2>&1)"
)
pass "a NUL byte in a transcript hides nothing"

# 16. A transcript read again from 0 (replaced): a message in the same second
# as the last one counted, but another, counts; the last one does not again.
(
    AGENTS_DATA_DIR="$tmp/same"; D="$tmp/same"; CLAUDE_CONFIG_DIR="$tmp/samec"; CODEX_HOME="$tmp/samec"
    sp="$tmp/samec/projects/-work-app"; mkdir -p "$sp"; f="$sp/$S.jsonl"
    { asst msg_A claude-test-1 5 1 1 1 1 "$text"; plain 6; } > "$f"; old "$f" 10
    scan; [[ "$(rows)" == 1 ]] || fail "F8: the first scan: $(rows) rows"
    { asst msg_A claude-test-1 5 1 1 1 1 "$text"; asst msg_Q claude-test-1 5 2 2 2 2 "$text"; asst msg_R claude-test-1 9 3 3 3 3 "$text"; plain 10; } > "$f.new"
    mv "$f.new" "$f"; old "$f" 10
    scan
    got="$(cut -f1,7-10 "$D/tokens.tsv" | LC_ALL=C sort)"
    want="$(printf '%s\n' "$((B + 5))	1	1	1	1" "$((B + 5))	2	2	2	2" "$((B + 9))	3	3	3	3")"
    [[ "$got" == "$want" ]] || fail "F8: after a restart:"$'\n'"$got"$'\n'"want:"$'\n'"$want"
)
pass "a transcript read again from 0 counts a message in the last one's second, not the last one again"

# 17. Who drove a session, and what its tools used: a session from the SDK
# (entrypoint sdk-cli) is headless; its subagents' rows are subagent's, a
# fork's fork's; codex exec is headless. A counted message's calls of MCP
# tools, skills and subagents go to uses.tsv by name (never their input; a
# fork's copy, a <synthetic> message: not at all), and so do the MCP tools a
# deferred tool list names; Codex's MCP function calls too. Every
# background task a transcript names goes to tasks.idx (an escaped mention
# in a string does not).
(
    AGENTS_DATA_DIR="$tmp/uses"; D="$AGENTS_DATA_DIR"; CLAUDE_CONFIG_DIR="$tmp/usesc"; CODEX_HOME="$tmp/usesx"
    S=77777777-2222-3333-4444-555555555555
    up="$CLAUDE_CONFIG_DIR/projects/-work-app"; us="$up/$S/subagents"; mkdir -p "$us"
    tl() { printf '{"type":"user","message":{"role":"user","content":[{"tool_use_id":"t","type":"tool_result","content":"%s"}]},"uuid":"t-%s","timestamp":"%s","toolUseResult":{"stdout":"","backgroundTaskId":"%s"}}\n' "$3" "$RANDOM" "$(iso $((B + $1)))" "$2"; }
    deferred() { printf '{"attachment":{"type":"deferred_tools_delta","addedNames":[%s]},"type":"attachment","uuid":"a-%s","timestamp":"%s","entrypoint":"sdk-cli"}\n' "$2" "$RANDOM" "$(iso $((B + $1)))"; }
    {
        deferred 1 '"WebFetch","mcp__claude-in-chrome__tabs","mcp__claude-in-chrome__click","mcp__plugin_alpha_db__query","mcp__claude_ai_Docs__search","mcp__x"'
        EP=sdk-cli asst msg_U1 claude-test-1 2 1 0 0 1 "$(tool_tu toolu_U1 mcp__claude-in-chrome__tabs '{"tabId":"secret-tab"}'),$(tool_tu toolu_U2 Skill '{"skill":"frontend-design:frontend-design","args":"--secret"}')"
        tl 3 bmain01 'see \"backgroundTaskId\":\"bescaped\" in a log'
        EP=sdk-cli asst msg_U2 claude-test-1 4 1 0 0 1 "$(tool_tu toolu_U3 Agent '{"subagent_type":"Explore","prompt":"p"}'),$(tool_tu toolu_U4 Task '{"prompt":"q"}'),$(tool_tu toolu_U5 mcp__claude-in-chrome__click '{}')"
        EP=sdk-cli asst msg_U3 '<synthetic>' 5 0 0 0 0 "$(tool_tu toolu_U6 mcp__never__x '{}')"
        plain 6
    } > "$up/$S.jsonl"
    { tl 7 bsub01 ok; asst msg_U4 claude-test-3 8 1 0 0 1 "$(tool_tu toolu_U7 Skill '{"skill":"update-config"}')"; plain 9; } > "$us/agent-xyz.jsonl"
    printf '{"agentType":"Explore"}' > "$us/agent-xyz.meta.json"
    { asst msg_U4 claude-test-3 8 1 0 0 1 "$(tool_tu toolu_U7 Skill '{"skill":"update-config"}')" | sed 's/"isSidechain":false/"isSidechain":true,"agentId":"frk"/'
      tl 7 bsub01 ok; asst msg_U5 claude-test-3 10 1 0 0 1 "$text"; plain 11; } > "$us/agent-frk.jsonl"
    printf '{"agentType":"fork","parentAgentId":"xyz"}' > "$us/agent-frk.meta.json"
    ux="$CODEX_HOME/sessions/2026/10/14"; mkdir -p "$ux"; UX=019f0000-bbbb-7bbb-8ccc-0123456789ab
    {
        printf '{"timestamp":"%s","type":"session_meta","payload":{"id":"%s","cwd":"/work/svc","originator":"codex_exec","source":"exec"}}\n' "$(iso $((B + 20)))" "$UX"
        printf '{"timestamp":"%s","type":"turn_context","payload":{"cwd":"/work/svc","model":"gpt-test-1"}}\n' "$(iso $((B + 21)))"
        printf '{"timestamp":"%s","type":"response_item","payload":{"type":"function_call","name":"mcp__playwright__browser_click","arguments":"{\\"secret\\":1}","call_id":"c1"}}\n' "$(iso $((B + 22)))"
        printf '{"timestamp":"%s","type":"response_item","payload":{"type":"function_call","name":"shell","arguments":"{}","call_id":"c2"}}\n' "$(iso $((B + 23)))"
        tc 24 500 100 0 10 1.0
    } > "$ux/rollout-2026-10-14T10-00-00-$UX.jsonl"
    for f in "$up/$S.jsonl" "$us"/agent-*.jsonl "$ux"/rollout-*.jsonl; do old "$f" 10; done
    scan
    got="$(cut -f2,4,5,13 "$D/tokens.tsv" | LC_ALL=C sort)"
    want="$(printf '%s\n' "claude	$S	Explore	subagent" "claude	$S	fork	fork" "claude	$S	main	headless" "claude	$S	main	headless" "codex	$UX	main	headless")"
    [[ "$got" == "$want" ]] || fail "U1: origins:"$'\n'"$got"$'\n'"want:"$'\n'"$want"
    want="$(printf '%s\n' \
        "claude	$S	Explore	skill	update-config	1" \
        "claude	$S	main	agent	Explore	1" \
        "claude	$S	main	agent	general-purpose	1" \
        "claude	$S	main	listed	claude-in-chrome	2" \
        "claude	$S	main	listed	claude_ai_Docs	1" \
        "claude	$S	main	listed	plugin_alpha_db	1" \
        "claude	$S	main	listed	x	1" \
        "claude	$S	main	mcp	claude-in-chrome	2" \
        "claude	$S	main	skill	frontend-design:frontend-design	1" \
        "codex	$UX	main	mcp	playwright	1")"
    # (Summed: the rows are per hour, and the fixture may straddle one.)
    got="$(LC_ALL=C awk -F '\t' -v OFS='\t' '{ k = $2 OFS $4 OFS $5 OFS $6 OFS $7; if (!(k in c)) o[++n] = k; c[k] += $8 } END { for (i = 1; i <= n; i++) print o[i], c[o[i]] }' "$D/uses.tsv" | LC_ALL=C sort)"
    [[ "$got" == "$want" ]] || fail "U1: uses.tsv:"$'\n'"$got"$'\n'"want:"$'\n'"$want"
    ! grep -qE 'secret|never|prompt' "$D/uses.tsv" || fail "U1: uses.tsv holds an input: $(cat "$D/uses.tsv")"
    got="$(cut -f2- "$D/tasks.idx" | LC_ALL=C sort)"
    want="$(printf '%s\n' "$S	bmain01	main	main" "$S	bsub01	frk	fork" "$S	bsub01	xyz	Explore")"
    [[ "$got" == "$want" ]] || fail "U1: tasks.idx:"$'\n'"$got"$'\n'"want:"$'\n'"$want"
    [[ "$(perm "$D/uses.tsv") $(perm "$D/tasks.idx")" == "600 600" ]] || fail "U1: uses.tsv, tasks.idx not private"
    # Nothing new: nothing added (a task line or a tool list read again is
    # not one); the index answers the ledger.
    n="$(cat "$D/uses.tsv" "$D/tasks.idx" | wc -l)"; scan
    [[ "$(cat "$D/uses.tsv" "$D/tasks.idx" | wc -l)" == "$n" ]] || fail "U1: a second scan added uses or tasks"
    [[ "$(_agents_tokens_task_sources "$up/$S.jsonl" bsub01 bmain01 bnone | LC_ALL=C sort)" == \
       "bmain01	$up/$S.jsonl	main"$'\n'"bsub01	$us/agent-frk.jsonl	fork"$'\n'"bsub01	$us/agent-xyz.jsonl	Explore" ]] \
        || fail "U1: task sources: $(_agents_tokens_task_sources "$up/$S.jsonl" bsub01 bmain01 bnone)"
)
pass "origins (you, headless, subagent, fork); uses.tsv: MCP servers, skills and subagents used, MCP tools listed, names only; tasks.idx: every task a transcript names"

# 18. The state, hot and cold: a scan writes only tokens.hot, only when it
# changed; a compaction moves the lines gone cold into tokens.state, every
# count as it was; an older agents' tokens.state alone (all cold, 12
# fields) goes on from its offsets.
(
    AGENTS_DATA_DIR="$tmp/hot"; D="$AGENTS_DATA_DIR"; CLAUDE_CONFIG_DIR="$tmp/orig/claude" CODEX_HOME="$tmp/orig/codex"
    scan; n="$(rows)"
    [[ ! -e "$D/tokens.state" && -s "$D/tokens.hot" ]] || fail "H1: the first scan wrote $(cd "$D" && echo *)"
    cp "$D/tokens.hot" "$tmp/hot.before"; touch -t 202001010000 "$D/tokens.hot"
    scan
    cmp -s "$D/tokens.hot" "$tmp/hot.before" || fail "H1: a scan with nothing new changed tokens.hot"
    [[ -n "$(find "$D/tokens.hot" -mtime +1 2>/dev/null)" ]] || fail "H1: a scan with nothing new rewrote tokens.hot"
    all="$(state | LC_ALL=C sort)"
    _AGENTS_TOKENS_HOT=1 _agents_tokens_compact "$((NOW + 7200))" 0
    [[ ! -s "$D/tokens.hot" && "$(LC_ALL=C sort "$D/tokens.state")" == "$all" ]] || fail "H1: the compaction:"$'\n'"$(state)"
    scan; [[ "$(rows)" == "$n" && ! -s "$D/tokens.hot" ]] || fail "H1: after a compaction, $(rows) rows (want $n); hot: $(cat "$D/tokens.hot")"
    # Cold lines that turn hot again, then enough of them gone cold: the
    # scan compacts on its own.
    m="$tmp/orig/claude/projects/-work-app/$S.jsonl"; cp "$m" "$tmp/hot.m"
    { asst msg_H1 claude-test-1 90 1 1 1 1 "$text"; plain 91; } >> "$m"; old "$m" 10
    ( _AGENTS_TOKENS_COLD_BATCH=1 _AGENTS_TOKENS_HOT=0 scan )
    [[ "$(rows)" == $((n + 1)) && ! -s "$D/tokens.hot" ]] || fail "H1: the scan did not compact its cold lines: $(rows) rows; hot: $(cat "$D/tokens.hot")"
    cp "$tmp/hot.m" "$m"; old "$m" 10
    # An older state: tokens.state alone, without the origin field.
    AGENTS_DATA_DIR="$tmp/hot07"; D="$AGENTS_DATA_DIR"; mkdir -p "$D"
    ( AGENTS_DATA_DIR="$tmp/hot"; D="$tmp/hot"; cut -f1-12 <(state) ) > "$D/tokens.state"
    scan; [[ ! -s "$D/tokens.tsv" ]] || fail "H1: an older state's transcripts were counted again: $(cat "$D/tokens.tsv")"
)
pass "the scan state: a scan writes only tokens.hot, only when it changed; a compaction moves cold lines to tokens.state; an older tokens.state goes on"

# 19. A scan lists only the transcripts changed since the last one began
# (tokens.stamp) and the hot ones; once _AGENTS_TOKENS_FULL has passed it
# lists them all again, which finds one whose mtime went back.
(
    _AGENTS_TOKENS_FULL=3600
    AGENTS_DATA_DIR="$tmp/inc"; D="$AGENTS_DATA_DIR"; CLAUDE_CONFIG_DIR="$tmp/incc"; CODEX_HOME="$tmp/incx"
    ip="$CLAUDE_CONFIG_DIR/projects/-work-app"; mkdir -p "$ip"
    a="$ip/$S.jsonl"; b="$ip/88888888-2222-3333-4444-555555555555.jsonl"
    { asst msg_L1 claude-test-1 1 1 1 1 1 "$text"; plain 2; } > "$a"
    { asst msg_L2 claude-test-1 3 2 2 2 2 "$text"; plain 4; } > "$b"
    scan; [[ "$(rows)" == 2 && -f "$D/tokens.stamp" && "$(cat "$D/tokens.full")" == "$NOW" ]] || fail "L1: the first, full scan: $(rows) rows; $(cd "$D" && echo *)"
    listed() { _agents_tokens_list "$D/tokens.stamp" | grep '^[0-9]' | cut -f4 | LC_ALL=C sort -u | wc -l | tr -d ' '; }
    old "$a" 10; old "$b" 10   # unchanged since the scan (whose stamp is NOW - 2)
    [[ "$(listed)" == 2 ]] || fail "L1: the hot transcripts are not listed: $(listed)"
    _AGENTS_TOKENS_HOT=0 _agents_tokens_compact "$NOW" 0
    [[ "$(listed)" == 0 ]] || fail "L1: unchanged cold transcripts listed: $(listed)"
    { asst msg_L3 claude-test-1 5 3 3 3 3 "$text"; plain 6; } >> "$a"
    { asst msg_L4 claude-test-1 7 4 4 4 4 "$text"; plain 8; } >> "$b"; old "$b" 10
    [[ "$(listed)" == 1 ]] || fail "L1: a changed transcript is not listed, or one whose mtime went back is: $(listed)"
    scan; [[ "$(rows)" == 3 ]] || fail "L1: the changed transcript: $(rows) rows, want 3"
    printf '%s\n' "$((NOW - 3600))" > "$D/tokens.full"
    scan; [[ "$(rows)" == 4 && "$(cat "$D/tokens.full")" == "$NOW" ]] || fail "L1: the hourly full listing: $(rows) rows, want 4"
    scan; [[ "$(rows)" == 4 ]] || fail "L1: a scan after it counted again: $(rows) rows"
)
pass "a scan lists the transcripts changed since the last one and the hot ones; every hour, all of them"

# 20. A catch-up never stalls: a hundred old transcripts and a small budget;
# every scan reads more (the transcripts the budget left are listed again,
# changed or not, and never compacted away as cold) until all are read; then
# the scans go back to listing only what changed.
(
    _AGENTS_TOKENS_FULL=3600 _AGENTS_TOKENS_BUDGET=3000
    AGENTS_DATA_DIR="$tmp/catch"; D="$AGENTS_DATA_DIR"; CLAUDE_CONFIG_DIR="$tmp/catchc"; CODEX_HOME="$tmp/catchx"
    cp="$CLAUDE_CONFIG_DIR/projects/-work-app"; mkdir -p "$cp"
    i=0
    while [[ $i -lt 100 ]]; do
        f="$cp/$(printf '%08d' $i)-2222-3333-4444-555555555555.jsonl"
        { B=$((NOW - 2 * 86400)) asst "msg_C$i" claude-test-1 "$i" 1 1 1 1 "$text"; B=$((NOW - 2 * 86400)) plain $((i + 1)); } > "$f"
        old "$f" $((2 * 1440)); i=$((i + 1))
    done
    n=0 last=0
    while [[ $n -lt 100 ]]; do
        scan; n=$((n + 1)); r="$(rows 2>/dev/null || echo 0)"
        [[ $r -gt $last ]] || fail "C1: scan $n read nothing new ($r rows of 100)"
        last=$r; [[ $r -lt 100 ]] || break
    done
    [[ $last -eq 100 ]] || fail "C1: $last rows of 100 after $n scans"
    [[ $n -gt 5 ]] || fail "C1: a 3000-byte budget read 100 transcripts in $n scans"
    [[ "$(cat "$D/tokens.full")" == "$NOW" ]] || fail "C1: caught up, the full listing is not stamped: $(cat "$D/tokens.full")"
    scan; [[ "$(rows)" == 100 ]] || fail "C1: a scan after the catch-up counted again: $(rows)"
    echo "    (100 transcripts, a 3000-byte budget: $n scans)"
)
pass "a catch-up reads more every scan, however many transcripts it holds, until it is done"

echo "All agents tokens tests passed."
