#!/bin/bash
# Unit tests for `agents report --view tokens` and `--view denials`, the
# summary's Tokens and Denials lines, the token and denial insights, the price
# file, and the menu's tokens row (`agents tsv` and the SwiftBar plugin).
# Run: bash scripts/lib/test_agents_report_tokens.sh  -> exit 0 on pass.
#
# Everything runs against fixture files written here (the formats the scanner
# writes, docs/agent-workflows.md), a fixed clock (15:00 UTC, Tue 2025-10-14)
# and temp dirs. In the 24h before now:
#   app   S1 main     claude-opus-5-5  2 calls  in 1k cw 40k cr 900k out 9k each
#   app   S1 Explore  claude-haiku-5   in 20k cw 30k cr 50k out 5k
#   shop  S2 main     claude-opus-5-5  in 2k cr 100k out 3k, a call that only waited
#   web   C1 main     gpt-6-luna       in 100k cr 400k out 20k (codex)
#   shop  S2 -        claude-sonnet-5  in 5k out 1k, 16h ago (not today)
#   alpha, zeta       claude-opus-5-5  out 500 each (a tie: by name)
# and 30h ago (in 7d, not 24h) 1M tokens of `old`; a header, a short row and a
# row with a word for a number. app's session S1 compacted 3 times today.
# Denials: git push ×4 by the classifier [Git Destructive], npm install ×3 by
# you, Edit ×2 by you, example.com (WebFetch) by you, rm by a safety check.

# Tests change variables inside ( … ) on purpose, for one call; the stubs
# (date) are called by the sourced bin/agents; backticks in single quotes are
# the report's own, not command substitutions.
# shellcheck disable=SC2016,SC2030,SC2031,SC2034,SC2088,SC2329
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/tuidev-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
for v in XDG_CONFIG_HOME XDG_STATE_HOME TUIDEV_STATE_DIR AGENTS_PRICES AGENTS_HISTORY; do unset "$v"; done
export HOME="$tmp/home" NO_COLOR=1 AGENTS_CONF="$tmp/none.conf" AGENTS_DATA_DIR="$tmp/data" AGENTS_RUN_DIR="$tmp/run"
export AGENTS_TESTING=1 AGENTS_NO_HERDR=1 LC_ALL=C TZ=UTC
mkdir -p "$HOME"

# shellcheck source=../../bin/agents disable=SC1091
. "$REPO_DIR/bin/agents"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "PASS: $1"; }
has_jq() { command -v jq >/dev/null 2>&1; }
# jqt JSON FILTER WHAT — FILTER must hold for JSON (skipped without jq).
jqt() { ! has_jq || printf '%s' "$1" | jq -e "$2" >/dev/null || fail "$3: $(printf '%s' "$1" | jq -c "${4:-.}")"; }

# A fixed clock: 15:00 UTC on Tuesday 2025-10-14.
FAKE_NOW=1760454000
TODAY=2025-10-14
# shellcheck disable=SC2317,SC2329  # called by the functions under test
date() {
    case "$*" in
        '+%s %z') echo "$FAKE_NOW +0000" ;;
        +%s)      echo "$FAKE_NOW" ;;
        +%Y-%m-%d) echo "$TODAY" ;;
        *)        command date "$@" ;;
    esac
}

# rows DIR FILE — stdin's rows into DIR/FILE, their first field (seconds ago)
# turned into an epoch; rows whose first field is not a number go as they are.
rows() { mkdir -p "$1"; awk -F '\t' -v OFS='\t' -v n="$FAKE_NOW" '$1 ~ /^[0-9]+$/ { $1 = n - $1 } { print }' > "$1/$2"; }
T=$'\t'
fixture() {   # DIR
    rows "$1" tokens.tsv <<EOF
epoch${T}cli${T}project${T}session${T}agent${T}model${T}in${T}cache_write${T}cache_read${T}out${T}poll
3600${T}claude${T}app${T}S1${T}main${T}claude-opus-5-5${T}1000${T}40000${T}900000${T}9000${T}0
3500${T}claude${T}app${T}S1${T}main${T}claude-opus-5-5${T}1000${T}40000${T}900000${T}9000${T}0
3400${T}claude${T}app${T}S1${T}Explore${T}claude-haiku-5${T}20000${T}30000${T}50000${T}5000${T}0
3300${T}claude${T}shop${T}S2${T}main${T}claude-opus-5-5${T}2000${T}0${T}100000${T}3000${T}1
3200${T}codex${T}web${T}C1${T}main${T}gpt-6-luna${T}100000${T}0${T}400000${T}20000${T}0
57600${T}claude${T}shop${T}S2${T}-${T}claude-sonnet-5${T}5000${T}0${T}0${T}1000${T}0
3000${T}claude${T}zeta${T}S3${T}main${T}claude-opus-5-5${T}0${T}0${T}0${T}500${T}0
2900${T}claude${T}alpha${T}S4${T}main${T}claude-opus-5-5${T}0${T}0${T}0${T}500${T}0
108000${T}claude${T}old${T}S0${T}main${T}claude-opus-5-5${T}1000000${T}0${T}0${T}0${T}0
100${T}claude${T}broken
200${T}claude${T}bad${T}S9${T}main${T}m${T}many${T}0${T}0${T}0${T}0
EOF
    rows "$1" compacts.tsv <<EOF
3000${T}claude${T}app${T}S1${T}main${T}auto${T}160000${T}20000
2000${T}claude${T}app${T}S1${T}main${T}auto${T}150000${T}20000
1000${T}claude${T}app${T}S1${T}main${T}manual${T}140000${T}20000
EOF
    rows "$1" denials.tsv <<EOF
900${T}claude${T}app${T}S1${T}main${T}Bash${T}classifier${T}Git Destructive${T}git push
800${T}claude${T}app${T}S1${T}main${T}Bash${T}classifier${T}Git Destructive${T}git push
700${T}claude${T}app${T}S1${T}main${T}Bash${T}classifier${T}Git Destructive${T}git push
600${T}claude${T}app${T}S1${T}main${T}Bash${T}classifier${T}Git Destructive${T}git push
500${T}claude${T}shop${T}S2${T}Explore${T}Bash${T}user${T}-${T}npm install
400${T}claude${T}shop${T}S2${T}Explore${T}Bash${T}user${T}-${T}npm install
300${T}claude${T}shop${T}S2${T}Explore${T}Bash${T}user${T}-${T}npm install
250${T}claude${T}app${T}S1${T}main${T}Edit${T}user${T}-${T}Edit
240${T}claude${T}app${T}S1${T}main${T}Edit${T}user${T}-${T}Edit
200${T}claude${T}app${T}S1${T}main${T}WebFetch${T}user${T}-${T}example.com
100${T}claude${T}app${T}S1${T}-${T}Bash${T}safety${T}-${T}rm
50${T}claude${T}app${T}S1${T}main${T}Bash${T}nobody${T}-${T}ls
EOF
    printf '%s\tcodex\t42.5\t300\t%s\n' $((FAKE_NOW - 600)) $((FAKE_NOW + 4800)) > "$1/limits.tsv"
}
d="$tmp/d"; fixture "$d"
rep() { AGENTS_DATA_DIR="$d" agents_report "$@"; }
prices="$tmp/agents-prices.tsv"
cat > "$prices" <<'EOF'
# USD per million tokens
claude-         2      2      2     2
claude-opus-5   10     12.5   1     50
claude-opus-5	15	18.75	1.5	75   # the later line wins
not enough fields
gpt-6           free   1      1     1   1
EOF

# 1. The tokens view: totals, cache hits, every breakdown, ties by name.
want="agents report · tokens · last 24h

TOKENS 2.6M in 8 model calls · 91% cache hits
  in 129k · cache write 110k · cache read 2.4M · out 48k

  MODEL                   TOKENS     %      IN  C.WRITE  C.READ     OUT   HIT
  claude-opus-5-5             2M   76%      4k      80k    1.9M     22k   96%
  gpt-6-luna                520k   20%    100k        0    400k     20k   80%
  claude-haiku-5            105k    4%     20k      30k     50k      5k   50%
  claude-sonnet-5             6k    0%      5k        0       0      1k    0%

  CLI                     TOKENS     %      IN  C.WRITE  C.READ     OUT   HIT
  claude                    2.1M   80%     29k     110k    1.9M     28k   93%
  codex                     520k   20%    100k        0    400k     20k   80%

  AGENT                   TOKENS     %      IN  C.WRITE  C.READ     OUT   HIT
  main                      2.5M   96%    104k      80k    2.3M     42k   93%
  Explore                   105k    4%     20k      30k     50k      5k   50%
  (unknown)                   6k    0%      5k        0       0      1k    0%

  PROJECT                 TOKENS     %      IN  C.WRITE  C.READ     OUT   HIT
  app                         2M   76%     22k     110k    1.9M     23k   93%
  web                       520k   20%    100k        0    400k     20k   80%
  shop                      111k    4%      7k        0    100k      4k   93%
  alpha                      500    0%       0        0       0     500     -
  zeta                       500    0%       0        0       0     500     -

POLLING  105k tokens (4%) in 1 model call that only waited
  by agent    main 105k
COMPACTIONS  3 · 2 auto, 1 manual · 150k tokens before, on average
  most        app 3 (claude S1)
CODEX PLAN  43% of the 5h window used · resets 16:20 (as of 14:50)"
out="$(rep --view tokens)"
[[ "$out" == "$want" ]] || fail "tokens view:"$'\n'"$out"$'\n'"--- want:"$'\n'"$want"
pass "tokens: totals, cache hit rate, by model, CLI, agent and project (ties by name), polling, compactions, Codex plan"

json="$(rep --view tokens --json)"
jqt "$json" '.schema_version == 1 and .view == "tokens" and .window == "24h" and .data and (.priced | not)' "tokens json header"
jqt "$json" '.totals == {"calls":8,"in":129000,"cache_write":110000,"cache_read":2350000,"out":48000,"total":2637000,"cache_hit_pct":90.8,"est_usd":null,"unpriced_tokens":null}' "tokens json totals" '.totals'
jqt "$json" '[.models[].model] == ["claude-opus-5-5","gpt-6-luna","claude-haiku-5","claude-sonnet-5"] and .models[0].total == 2006000 and .models[0].calls == 5' "tokens json models" '.models'
jqt "$json" '[.projects[].project] == ["app","web","shop","alpha","zeta"] and [.agents[].agent] == ["main","Explore",null] and [.clis[].cli] == ["claude","codex"]' "tokens json names" '[.projects, .agents]'
jqt "$json" '.polling == {"calls":1,"tokens":105000,"pct":4.0,"agents":[{"agent":"main","tokens":105000}]}' "tokens json polling" '.polling'
jqt "$json" '.compactions == {"count":3,"auto":2,"manual":1,"avg_pre_tokens":150000,"sessions":[{"cli":"claude","project":"app","session":"S1","count":3,"auto":2,"pre_tokens":450000}]}' "tokens json compactions" '.compactions'
jqt "$json" '.codex_limits == {"as_of":1760453400,"used_percent":42.5,"window_minutes":300,"resets_at":1760458800}' "tokens json limits" '.codex_limits'
pass "tokens --json: the same numbers, every name, stable keys"

# The report sums what the scanner wrote: the same rows in another order (and
# a repeated row counts twice: deduplication is the scanner's job).
r="$tmp/rev"; mkdir -p "$r"; cp "$d"/*.tsv "$r/"
awk '{ l[NR] = $0 } END { for (i = NR; i > 0; i--) print l[i] }' "$d/tokens.tsv" > "$r/tokens.tsv"
[[ "$(AGENTS_DATA_DIR="$r" agents_report --view tokens --json)" == "$json" ]] || fail "tokens: the order of the rows changes the sums"
sed -n 2p "$d/tokens.tsv" >> "$r/tokens.tsv"
jqt "$(AGENTS_DATA_DIR="$r" agents_report --view tokens --json)" '.totals.total == 2637000 + 950000 and .totals.calls == 9' "tokens: a repeated row" '.totals'
pass "tokens: sums independent of row order; the report never deduplicates on its own"

# 2. --since windows: 7d takes in the old row; today drops the 16h-old one.
jqt "$(rep --view tokens --since 7d --json)" '.window == "7d" and .totals.total == 3637000 and ([.projects[].project] | index("old")) != null' "tokens --since 7d" '.totals'
jqt "$(rep --view tokens --since today --json)" '.window == "today" and .totals.total == 2631000 and ([.models[].model] | index("claude-sonnet-5")) == null' "tokens --since today" '.totals'
jqt "$(rep --view tokens --since 1h --json)" '.totals.calls == 7 and .compactions.count == 3' "tokens --since 1h" '.totals'
[[ "$(rep --view tokens --since 30m)" == *$'\n\n'"no tokens in this window"$'\n'"COMPACTIONS  1 · 0 auto, 1 manual · 140k tokens before, on average"* ]] || fail "tokens: nothing in the window:"$'\n'"$(rep --view tokens --since 30m)"
pass "tokens: --since 24h (default), 7d, today, 1h; an empty window says so"

# 3. The price file: longest prefix wins, a later line wins a tie, bad lines
# reported, models without a price show "-", no file means no $ at all.
out="$(AGENTS_PRICES="$prices" rep --view tokens 2>"$tmp/err")"
[[ "$out" == *"TOKENS 2.6M in 8 model calls · 91% cache hits · est. \$6.28"$'\n'* ]] || fail "prices: the total:"$'\n'"$out"
[[ "$out" == *"   HIT     EST \$"$'\n'"  claude-opus-5-5 "*" 96%     \$6.06"$'\n'"  gpt-6-luna "*" 80%         -"$'\n'"  claude-haiku-5 "*" 50%     \$0.21"$'\n'"  claude-sonnet-5 "*"  0%     \$0.01"$'\n'* ]] \
    || fail "prices: per model (opus at its own price, not claude-'s):"$'\n'"$out"
[[ "$out" == *$'\n\n'"est. \$: an estimate from agents-prices.tsv (USD per million tokens); 1 model without a price (-) left out" ]] || fail "prices: the note:"$'\n'"$out"
err="$(sed 's|.*/||' "$tmp/err")"
[[ "$err" == "agents-prices.tsv:5: not MODEL_PREFIX IN CACHE_WRITE CACHE_READ OUT (USD per million tokens), ignored"$'\n'"agents-prices.tsv:6: not MODEL_PREFIX"* \
   && "$(wc -l < "$tmp/err")" -eq 2 ]] || fail "prices: bad lines: $(cat "$tmp/err")"
json="$(AGENTS_PRICES="$prices" rep --view tokens --json 2>/dev/null)"
jqt "$json" '.priced and .totals.est_usd == 6.28 and .totals.unpriced_tokens == 520000 and ([.models[] | .est_usd] == [6.06, null, 0.21, 0.01])' "prices json" '[.totals, [.models[] | .est_usd]]'
jqt "$json" '(.projects[] | select(.project == "web") | .est_usd) == null and (.projects[] | select(.project == "app") | .est_usd) == 5.79' "prices json: projects" '.projects'
( HOME="$tmp/ph"; mkdir -p "$HOME"; cp "$prices" "$HOME/p.tsv"; AGENTS_PRICES="~/p.tsv"
  [[ "$(rep --view tokens 2>/dev/null)" == *"est. \$6.28"* ]] ) || fail "prices: a ~/ path"
out="$(rep --view tokens)"
[[ "$out" != *'$'* && "$out" != *"EST"* && "$out" != *estimate* ]] || fail "no price file, still a \$:"$'\n'"$out"
[[ "$(AGENTS_PRICES="$tmp/nonexistent.tsv" rep --view tokens)" == "$out" ]] || fail "a missing price file changes the report"
printf '# only comments\n' > "$tmp/empty-prices.tsv"
[[ "$(AGENTS_PRICES="$tmp/empty-prices.tsv" rep --view tokens)" == "$out" ]] || fail "a price file without prices shows \$"
jqt "$(rep --json)" '.tokens.est_usd == null' "summary json without prices"
jqt "$(AGENTS_PRICES="$prices" rep --json 2>/dev/null)" '.tokens.est_usd == 6.28' "summary json with prices"
pass "prices: longest prefix, later line on a tie, bad lines reported, '-' without a price, nothing without the file"

# AGENTS_PRICES is a setting: a path (absolute or ~/), checked like the others.
for good in /x/p.tsv '~/p.tsv' ''; do _agents_conf_valid AGENTS_PRICES "$good" || fail "AGENTS_PRICES '$good' refused"; done
for bad in relative.tsv '~user/p.tsv' $'/a\tb'; do ! _agents_conf_valid AGENTS_PRICES "$bad" || fail "AGENTS_PRICES '$bad' accepted"; done
[[ "$(AGENTS_PRICES=relative bash "$REPO_DIR/bin/agents" config 2>&1 | grep -c 'AGENTS_PRICES')" -ge 1 ]] || fail "agents config without AGENTS_PRICES"
( out="$(AGENTS_PRICES=relative bash "$REPO_DIR/bin/agents" config 2>&1)"
  [[ "$out" == *"bad AGENTS_PRICES ('relative') in the environment"* && "$out" == *"AGENTS_PRICES=$HOME/.config/tuidev/agents-prices.tsv"* ]] ) \
    || fail "a bad AGENTS_PRICES falls back to the default"
pass "AGENTS_PRICES: an absolute or ~/ path, else the default with a warning"

# 4. The denials view: by who, reason, subject, agent and project, and hints.
want="agents report · denials · last 24h

DENIED 11 · 4 by the classifier · 6 by you · 1 by a safety check

  SUBJECT                TOOL        DENIED  CLASSIFIER   YOU SAFETY  REASON
  git push               Bash             4           4     0      0  Git Destructive
  npm install            Bash             3           0     3      0  -
  Edit                   Edit             2           0     2      0  -
  example.com            WebFetch         1           0     1      0  -
  rm                     Bash             1           0     0      1  -

REASONS      Git Destructive 4
BY AGENT     main 7 · Explore 3 · (unknown) 1
BY PROJECT   app 8 · shop 3

REPEATED
  \`git push\` denied ×4 by the classifier [Git Destructive] — expected: auto mode holds it for you; run it yourself, or allow it if it is routine
  \`npm install\` denied ×3 by you — consider an allow rule, or an instruction not to try it
  \`Edit\` denied ×2 by you — consider an allow rule, or an instruction not to try it"
out="$(rep --view denials)"
[[ "$out" == "$want" ]] || fail "denials view:"$'\n'"$out"$'\n'"--- want:"$'\n'"$want"
json="$(rep --view denials --json)"
jqt "$json" '.view == "denials" and .data and .denials == 11 and .by == {"classifier":4,"user":6,"safety":1} and .reasons == [{"reason":"Git Destructive","count":4}]' "denials json" '.'
jqt "$json" '.subjects[0] == {"subject":"git push","tool":"Bash","count":4,"classifier":4,"user":0,"safety":0,"reason":"Git Destructive"} and ([.subjects[].subject] == ["git push","npm install","Edit","example.com","rm"])' "denials json subjects" '.subjects'
jqt "$json" '.agents == [{"agent":"main","count":7},{"agent":"Explore","count":3},{"agent":null,"count":1}] and ([.hints[] | [.subject, .by, .count]] == [["git push","classifier",4],["npm install","user",3],["Edit","user",2]])' "denials json agents and hints" '[.agents, .hints]'
jqt "$(rep --view denials --since 5m --json)" '.denials == 5 and .by == {"classifier":0,"user":4,"safety":1}' "denials --since 5m" '.by'
[[ "$(rep --view denials)" != *" ls "* ]] || fail "denials counts a row with an unknown 'by'"
pass "denials: who denied what, the classifier's reasons, by agent and project, and a hint per repeated subject"

# 5. Without data, or nothing in the window: no invented numbers.
e="$tmp/empty"; mkdir -p "$e"
[[ "$(AGENTS_DATA_DIR="$e" agents_report --view tokens)" == *$'\n\n'"no token data yet (tokens.tsv): each agents sample adds what the Claude Code and Codex transcripts logged since the last" ]] \
    || fail "tokens without data"
[[ "$(AGENTS_DATA_DIR="$e" agents_report --view denials)" == *$'\n\n'"no denials recorded yet (denials.tsv): each agents sample adds the tool calls the Claude Code transcripts show denied" ]] \
    || fail "denials without data"
[[ "$(AGENTS_HISTORY=0 AGENTS_DATA_DIR="$e" agents_report --view tokens)" == *"history is off (AGENTS_HISTORY=0): no tokens are recorded" ]] || fail "tokens with history off"
jqt "$(AGENTS_DATA_DIR="$e" agents_report --view tokens --json)" '(.data | not) and .totals.total == 0 and .models == [] and .codex_limits == null' "tokens json without data"
jqt "$(AGENTS_DATA_DIR="$e" agents_report --view denials --json)" '(.data | not) and .denials == 0 and .subjects == [] and .hints == []' "denials json without data"
jqt "$(AGENTS_DATA_DIR="$e" agents_report --json)" '.tokens == null and .denials == null' "summary json without token data"
[[ "$(rep --view denials --since 30s)" == *$'\n\n'"no denials in this window" ]] || fail "denials: nothing in the window"
pass "no data: one line saying so (JSON: data false, empty lists, nulls)"

# 6. The summary: a Tokens and a Denials line; nothing without their data.
out="$(rep)"
[[ "$out" == *$'\n'"TOKENS  2.6M · 91% cache hits · 4% polling · 3 compactions"$'\n'"  by model, agent and project: agents report --view tokens"$'\n\n'"DENIALS  11 · 4 by the classifier · 6 by you · 1 by a safety check"$'\n'"  by command and what to try: agents report --view denials"$'\n\n'"CLEANUPS (0)"* ]] \
    || fail "summary: tokens and denials:"$'\n'"$out"
[[ "$(AGENTS_PRICES="$prices" rep 2>/dev/null)" == *"TOKENS  2.6M · 91% cache hits · 4% polling · est. \$6.28 · 3 compactions"$'\n'* ]] || fail "summary: est. \$"
[[ "$(AGENTS_DATA_DIR="$e" agents_report)" != *TOKENS* ]] || fail "summary: a Tokens line without token data"
jqt "$(rep --json)" '.tokens == {"calls":8,"total":2637000,"in":129000,"cache_write":110000,"cache_read":2350000,"out":48000,"cache_hit_pct":90.8,"poll_tokens":105000,"poll_pct":4.0,"est_usd":null,"compactions":3} and .denials == {"count":11,"classifier":4,"user":6,"safety":1}' "summary json tokens" '[.tokens, .denials]'
pass "summary: Tokens (total, cache hits, polling, est. \$ when priced, compactions) and Denials lines"

# 7. The insights: past their thresholds, each naming its view; not below.
ins="$(printf '%s\n' "$out" | sed -n '/^TOP INSIGHTS$/,/^$/p')"
want="TOP INSIGHTS
  1. app: a session compacted its context ×3 in 24h (2 auto) — hand long work to subagents, or start a fresh session per task
  2. \`npm install\` denied ×3 by you in 24h — consider an allow rule, or an instruction not to try it
  more: agents report --view runs|waste|trends|agents|tokens|denials"
[[ "$ins" == "$want" ]] || fail "insights:"$'\n'"$ins"
jqt "$(rep --json)" '[.insights[] | [.kind, .view, .impact_s]] == [["compact","tokens",450],["denied","denials",300]] and .insights[1].cmd == "npm install"' "insights json" '.insights'
w="$tmp/w"; fixture "$w"
AGENTS_DATA_DIR="$w" agents_insight_write
[[ "$(AGENTS_DATA_DIR="$w" _agents_insight_line)" == "insight"$'\t'"tokens"$'\t'"app: a session compacted its context ×3 today (2 auto) — "* ]] \
    || fail "insight.txt: $(cat "$w/insight.txt")"
# One run of the summary's insights over a fixture made of rows "SECS CLI
# PROJECT AGENT IN CW CR OUT POLL" (tokens) or "SECS TRIGGER" (S1's compactions)
# or "SECS BY SUBJECT" (denials); prints the kinds found.
kinds() {   # DIR
    AGENTS_DATA_DIR="$1" agents_report --json | jq -r '[.insights[].kind] | join(" ")'
}
th_case() {   # NAME TOKENS_ROWS COMPACT_ROWS DENIAL_ROWS
    local x="$tmp/th-$1"; rm -rf "$x"
    printf '%s' "$2" | awk -v OFS='\t' '{ print $1, $2, $3, "S1", $4, "m-1", $5, $6, $7, $8, $9 }' | rows "$x" tokens.tsv
    printf '%s' "$3" | awk -v OFS='\t' '{ print $1, "claude", "app", "S1", "main", $2, 100000, 1000 }' | rows "$x" compacts.tsv
    printf '%s' "$4" | awk -v OFS='\t' '{ print $1, "claude", "app", "S1", "main", "Bash", $2, "-", $3 }' | rows "$x" denials.tsv
    printf '%s' "$x"
}
if has_jq; then
    [[ "$(kinds "$(th_case c70 '60 claude app main 300000 0 700000 0 0'$'\n' '' '')")" == "" ]] || fail "cache at 70% fires"
    [[ "$(kinds "$(th_case c69 '60 claude app main 300001 0 699999 0 0'$'\n' '' '')")" == "cache" ]] || fail "cache below 70% on 1M does not fire"
    [[ "$(kinds "$(th_case cvol '60 claude app main 400000 0 599999 0 0'$'\n' '' '')")" == "" ]] || fail "cache fires below 1M input tokens"
    [[ "$(kinds "$(th_case p5 '60 claude app main 0 0 950000 0 0'$'\n''50 claude app main 0 0 50000 0 1'$'\n' '' '')")" == "" ]] || fail "polling at 5% fires"
    [[ "$(kinds "$(th_case p51 '60 claude app main 0 0 949999 0 0'$'\n''50 claude app main 0 0 50001 0 1'$'\n' '' '')")" == "poll" ]] || fail "polling above 5% does not fire"
    [[ "$(kinds "$(th_case pvol '60 claude app main 0 0 899999 0 0'$'\n''50 claude app main 0 0 100000 0 1'$'\n' '' '')")" == "" ]] || fail "polling fires below 1M tokens"
    [[ "$(kinds "$(th_case k2 '' '30 auto'$'\n''20 manual'$'\n' '')")" == "" ]] || fail "2 compactions fire"
    [[ "$(kinds "$(th_case k3 '' '30 auto'$'\n''20 manual'$'\n''10 auto'$'\n' '')")" == "compact" ]] || fail "3 compactions do not fire"
    [[ "$(kinds "$(th_case u2 '' '' '30 user rm'$'\n''20 user rm'$'\n''10 classifier rm'$'\n')")" == "" ]] || fail "2 user denials fire"
    [[ "$(kinds "$(th_case u3 '' '' '30 user rm'$'\n''20 user rm'$'\n''10 user rm'$'\n')")" == "denied" ]] || fail "3 user denials do not fire"
    out="$(AGENTS_DATA_DIR="$tmp/th-c69" agents_report)"
    [[ "$out" == *"  1. claude: 69% cache hits in 24h on 1M input tokens — long sessions on one model, with stable instructions, keep the prompt cache warm"$'\n'* ]] || fail "cache insight:"$'\n'"$out"
    out="$(AGENTS_DATA_DIR="$tmp/th-p51" agents_report)"
    [[ "$out" == *"  1. 5% of tokens (50k) went to polling in 24h (most: main sessions) — wait on a background task's notification instead of polling"$'\n'* ]] || fail "polling insight:"$'\n'"$out"
    pass "insights: cache <70% on 1M+, polling >5% of 1M+, compactions ≥3 in a session, a subject you denied ≥3×; none below"
else
    echo "SKIP: insight thresholds (no jq)"
fi

# 8. A month of tokens: thousands of names, JSON far past mawk's 8 KiB sprintf
# limit, every number in place; the text cut at its row limits.
big="$tmp/big"; mkdir -p "$big"
awk -v n="$FAKE_NOW" 'BEGIN {
    OFS = "\t"
    for (i = 0; i < 20000; i++)
        print n - (i * 97) % (28 * 86400), (i % 4 ? "claude" : "codex"), "project-" (i % 1500), "s" (i % 300), (i % 3 ? "main" : "agent-type-" (i % 40)), \
            "model-" (i % 60), 1000, 2000, 30000 + i % 7, 500, (i % 50 ? 0 : 1)
    for (i = 0; i < 3000; i++) printf "%d\tclaude\tp%d\ts%d\tmain\tBash\t%s\t-\tcmd%d sub\n", n - i * 600, i % 900, i % 50, (i % 2 ? "user" : "classifier"), i % 700 > "'"$big"'/denials.tsv"
}' > "$big/tokens.tsv"
for v in tokens denials; do
    json="$(AGENTS_DATA_DIR="$big" agents_report --view "$v" --since 30d --json)"
    [[ ${#json} -gt 8192 ]] || fail "--view $v --json is small (${#json} bytes): the fixture is too"
    jqt "$json" '.schema_version == 1' "--view $v --json on a month"
done
jqt "$(AGENTS_DATA_DIR="$big" agents_report --view tokens --since 30d --json)" '(.projects | length) == 1500 and (.models | length) == 60 and .totals.calls == 20000 and .totals.total == 670059997' "a month: every name and the sum" '.totals'
out="$(AGENTS_DATA_DIR="$big" agents_report --view tokens --since 30d)"
[[ "$out" == *"... 1492 more (agents report --view tokens --json)"* && "$out" == *"... 50 more (agents report --view tokens --json)"* ]] || fail "a month: the text is cut"
jqt "$(AGENTS_DATA_DIR="$big" agents_report --view denials --since 30d --json)" '(.subjects | length) == 700 and .denials == 3000' "a month of denials" '.denials'
pass "a month of tokens (20000 calls, 1500 projects): JSON valid past 8 KiB, text cut at 10 or 8 rows"

# 9. Options: the views are known, --since checked.
[[ "$(rep --view=tokens --since=today)" == "agents report · tokens · today"* ]] || fail "--view=tokens --since=today"
for bad in "--view token" "--view tokens --since 2x" "--view denials --since"; do
    rc=0
    # shellcheck disable=SC2086  # one argument per word
    rep $bad >/dev/null 2>&1 || rc=$?
    [[ $rc == 2 ]] || fail "agents report $bad: rc $rc"
done
pass "report: tokens and denials views, bad options refused (rc 2)"

# 10. The menu feed: `tokens TOTAL CACHE_PCT` from tokens.today, today's only.
m="$tmp/m"; mkdir -p "$m"
printf '%s\t2637000\t129000\t110000\t2350000\t48000\n' "$TODAY" > "$m/tokens.today"
[[ "$(AGENTS_DATA_DIR="$m" _agents_tokens_line)" == "tokens"$'\t'"2637000"$'\t'"91" ]] || fail "tokens row: $(AGENTS_DATA_DIR="$m" _agents_tokens_line)"
printf '2025-10-13\t2637000\t129000\t110000\t2350000\t48000\n' > "$m/tokens.today"
[[ -z "$(AGENTS_DATA_DIR="$m" _agents_tokens_line)" ]] || fail "a tokens row from yesterday"
printf '%s\t0\t0\t0\t0\t0\n' "$TODAY" > "$m/tokens.today"
[[ "$(AGENTS_DATA_DIR="$m" _agents_tokens_line)" == "tokens"$'\t'"0"$'\t'"0" ]] || fail "tokens row with nothing yet"
for bad in "$TODAY"$'\tlots\t1\t1\t1\t1' "$TODAY"$'\t1\t1' "$TODAY"$'\t-1\t1\t1\t1\t1'; do
    printf '%s\n' "$bad" > "$m/tokens.today"
    [[ -z "$(AGENTS_DATA_DIR="$m" _agents_tokens_line)" ]] || fail "a tokens row from '$bad'"
done
printf '%s\t08\t09\t0\t010\t1\n' "$TODAY" > "$m/tokens.today"
[[ "$(AGENTS_DATA_DIR="$m" _agents_tokens_line)" == "tokens"$'\t'"8"$'\t'"53" ]] || fail "leading zeros: $(AGENTS_DATA_DIR="$m" _agents_tokens_line)"
printf '%s\t2637000\t129000\t110000\t2350000\t48000\n' "$TODAY" > "$m/tokens.today"
[[ -z "$(AGENTS_HISTORY=0 AGENTS_DATA_DIR="$m" _agents_tokens_line)" ]] || fail "a tokens row with history off"
[[ -z "$(AGENTS_DATA_DIR="$tmp/none" _agents_tokens_line)" ]] || fail "a tokens row without tokens.today"
pass "agents tsv: tokens TOTAL CACHE_PCT from tokens.today, only today's, only numbers"

# The plugin: one row under Today, humanized, opening today's tokens view.
printf 'hist\tok\t3600\ttest\t1800\ntokens\t2637000\t91\ninsight\ttokens\tapp: a session compacted ×3 — x\n' > "$tmp/tsv"
printf '#!/bin/bash\ncase "$1" in tsv) cat "%s" ;; esac\n' "$tmp/tsv" > "$tmp/agents-stub"
chmod +x "$tmp/agents-stub"
menu="$(AGENTS_BIN="$tmp/agents-stub" bash "$REPO_DIR/configs/swiftbar/agents.10s.sh")"
section="$(printf '%s\n' "$menu" | awk '/^Where the CPU goes/ { on = 1 } on && /^---$/ { exit } on')"
want="Today: 1.0 CPU-h · tests 50% | sfimage=chart.bar.xaxis refresh=true symbolize=false
2.6M tokens today · 91% cached | bash=\"$tmp/agents-stub\" param1=open-term terminal=false param2=--hold param3=report param4=--view param5=tokens param6=--since param7=today sfimage=text.bubble symbolize=false
app: a session compacted ×3 | bash=\"$tmp/agents-stub\" param1=open-term terminal=false param2=--hold param3=report param4=--view param5=tokens "
[[ "$section" == *"$want"* ]] || fail "menu tokens row:"$'\n'"$section"
for n in 0 950:950 64249:64.2k 99949:99.9k 99950:100k 640000:640k 999499:999k 999500:1M 12449999:12.4M 99950000:100M 1234567890:1.2B; do
    printf 'hist\tok\t0\t-\t0\ntokens\t%s\t90\n' "${n%%:*}" > "$tmp/tsv"
    line="$(AGENTS_BIN="$tmp/agents-stub" bash "$REPO_DIR/configs/swiftbar/agents.10s.sh" | grep 'tokens today' || true)"
    if [[ "$n" == 0 ]]; then [[ -z "$line" ]] || fail "a tokens row for 0 tokens"; continue; fi
    [[ "$line" == "${n#*:} tokens today · 90% cached | "* ]] || fail "menu: ${n%%:*} tokens as '${n#*:}': $line"
    [[ "$(_agents_awk_eval "lib_json lib_sort lib_fmt report_fmt report_runs report_tokens report_denials report_insights report_views" 'BEGIN { print tk(x) }' -v x="${n%%:*}")" == "${n#*:}" ]] \
        || fail "report and menu disagree on ${n%%:*}"
done
printf 'hist\toff\t0\t-\t0\n' > "$tmp/tsv"
[[ "$(AGENTS_BIN="$tmp/agents-stub" bash "$REPO_DIR/configs/swiftbar/agents.10s.sh")" != *"tokens today"* ]] || fail "a tokens row without the tsv line"
pass "menu: '2.6M tokens today · 91% cached' under Today (k/M/B as the report writes them), opening today's tokens view"

echo "All agents report tokens tests passed."
