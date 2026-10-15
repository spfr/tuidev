#!/bin/bash
# Unit tests for `agents report --view tokens` and `--view denials`, the
# summary's Tokens and Denials lines, the token and denial insights, the price
# file, and the menu's tokens row (`agents tsv` and the SwiftBar plugin).
# Run: bash scripts/lib/test_agents_report_tokens.sh  -> exit 0 on pass.
#
# Everything runs against fixture files written here (the formats the scanner
# writes, docs/agent-workflows.md), a fixed clock (15:00 UTC, Tue 2025-10-14)
# and temp dirs. In the 24h before now:
#   app   S1 main     claude-opus-5-5  2 calls  in 1k cw 40k (1h 30k) cr 900k out 9k each, you
#   app   S1 Explore  claude-haiku-5   in 20k cw 30k cr 50k out 5k, a subagent
#   shop  S2 main     claude-opus-5-5  in 2k cr 100k out 3k, a call that only waited, headless
#   web   C1 main     gpt-6-luna       in 100k cr 400k out 20k (codex), you
#   shop  S2 -        claude-sonnet-5  in 5k out 1k, 16h ago (not today)
#   alpha, zeta       claude-opus-5-5  out 500 each (a tie: by name)
# and 30h ago (in 7d, not 24h) 1M tokens of `old`; a header, a short row and a
# row with a word for a number. The last four are rows as written before 1h
# cache writes and origins were recorded (11 columns). app's session S1
# compacted 3 times today (2 of them auto: below the insight's 3).
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
export AGENTS_PRICES=off   # no cost unless a test asks for one (3.)
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
3600${T}claude${T}app${T}S1${T}main${T}claude-opus-5-5${T}1000${T}40000${T}900000${T}9000${T}0${T}30000${T}you
3500${T}claude${T}app${T}S1${T}main${T}claude-opus-5-5${T}1000${T}40000${T}900000${T}9000${T}0${T}30000${T}you
3400${T}claude${T}app${T}S1${T}Explore${T}claude-haiku-5${T}20000${T}30000${T}50000${T}5000${T}0${T}0${T}subagent
3300${T}claude${T}shop${T}S2${T}main${T}claude-opus-5-5${T}2000${T}0${T}100000${T}3000${T}1${T}0${T}headless
3200${T}codex${T}web${T}C1${T}main${T}gpt-6-luna${T}100000${T}0${T}400000${T}20000${T}0${T}0${T}you
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
# Yours: USD per million tokens, some lines as written before 1h cache writes (5 columns)
claude-          2      2      2     2           # a family: any claude- model no closer line names
claude-opus-5    10     12.5   1     50          # claude-opus-5 and its dated forms, never claude-opus-5-5
claude-sonnet-5  1      1      1     1     1
claude-sonnet-5	3	3.75	6	0.3	15   # the later line wins
not enough fields
gpt-6-luna       free   1      1     1     1
EOF

# 1. The tokens view: totals, cache hits, every breakdown, ties by name.
want="agents report · tokens · last 24h

TOKENS 2.6M in 8 model calls · 91% cache hits
  in 129k · cache write 110k (1h 60k) · cache read 2.4M · out 48k

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

  SESSION                 TOKENS     %      IN  C.WRITE  C.READ     OUT   HIT
  app S1                      2M   76%     22k     110k    1.9M     23k   93%
  web C1                    520k   20%    100k        0    400k     20k   80%
  shop S2                   111k    4%      7k        0    100k      4k   93%
  zeta S3                    500    0%       0        0       0     500     -
  alpha S4                   500    0%       0        0       0     500     -

  ORIGIN                 SESSIONS  TOKENS     %
  you                           2    2.4M   92%
  headless                      1    105k    4%
  subagent                      1    105k    4%
  (unknown)                     3      7k    0%

POLLING  105k tokens (4%) in 1 model call that only waited
  by agent    main 105k
COMPACTIONS  3 · 2 auto, 1 manual · 150k tokens before, on average
  most        app 3 (claude S1)
CODEX PLAN  43% of the 5h window used · resets 16:20 (as of 14:50)"
out="$(rep --view tokens)"
[[ "$out" == "$want" ]] || fail "tokens view:"$'\n'"$out"$'\n'"--- want:"$'\n'"$want"
pass "tokens: totals (1h cache writes apart), cache hit rate, by model, CLI, agent, project and session (ties by name), by origin, polling, compactions, Codex plan"

json="$(rep --view tokens --json)"
jqt "$json" '.schema_version == 1 and .view == "tokens" and .window == "24h" and .data and (.priced | not) and .prices == null' "tokens json header"
jqt "$json" '.totals == {"calls":8,"in":129000,"cache_write":110000,"cache_write_1h":60000,"cache_read":2350000,"out":48000,"total":2637000,"cache_hit_pct":90.8,"est_usd":null,"unpriced_tokens":null}' "tokens json totals" '.totals'
jqt "$json" '[.sessions[] | [.session, .project, .cli, .origin, .total]] == [["S1","app","claude","you",2005000],["C1","web","codex","you",520000],["S2","shop","claude","headless",111000],["S3","zeta","claude",null,500],["S4","alpha","claude",null,500]]' "tokens json sessions" '.sessions'
jqt "$json" '[.origins[] | [.origin, .sessions, .total]] == [["you",2,2420000],["headless",1,105000],["subagent",1,105000],[null,3,7000]]' "tokens json origins" '.origins'
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

# 3. Costs: API list prices ship (lib/agents/prices.tsv), your file changes
# or adds prices (a later line wins a tie), the longest prefix that names a
# model wins (up to a version boundary: never a shorter version's), bad
# lines are reported, a model without a price is unpriced (never $0), and
# AGENTS_PRICES=off shows no cost at all. 1h cache writes cost their own
# price; a 5-column line prices them as its one cache-write price.
shipped="$(AGENTS_PRICES="" rep --view tokens 2>"$tmp/err")"
[[ ! -s "$tmp/err" ]] || fail "the shipped prices: $(cat "$tmp/err")"
[[ "$shipped" == *"TOKENS 2.6M in 8 model calls · 91% cache hits · \$1.46 API-equivalent"$'\n'* ]] || fail "shipped prices: the total:"$'\n'"$shipped"
[[ "$shipped" == *"   HIT     API \$"$'\n'"  claude-opus-5-5 "*" 96%     \$1.42"$'\n'"  gpt-6-luna "*" 80%     \$0.02"$'\n'"  claude-haiku-5 "*" 50%  unpriced"$'\n'"  claude-sonnet-5 "*"  0%     \$0.02"$'\n'* ]] \
    || fail "shipped prices: per model (opus 1h writes at 8, 5m at 5):"$'\n'"$shipped"
[[ "$shipped" == *$'\n\n'"API \$: what these tokens would cost at API list prices (as of 2026-10-15), not what a subscription charges; 1 model unpriced, left out" ]] \
    || fail "shipped prices: the note:"$'\n'"$shipped"
json="$(AGENTS_PRICES="" rep --view tokens --json)"
jqt "$json" '.priced and .prices == {"basis":"api_list","as_of":"2026-10-15"} and .totals.est_usd == 1.46 and .totals.unpriced_tokens == 105000 and ([.models[] | .est_usd] == [1.42, 0.02, null, 0.02])' \
    "shipped prices json" '[.prices, .totals, [.models[] | .est_usd]]'
jqt "$json" '(.projects[] | select(.project == "app") | .est_usd) == 1.31 and (.sessions[] | select(.session == "S1") | .est_usd) == 1.31 and ([.origins[] | .est_usd] == [1.33, 0.09, null, 0.04])' \
    "shipped prices json: projects, sessions and origins" '[.projects, .sessions, .origins]'
out="$(AGENTS_PRICES="$prices" rep --view tokens 2>"$tmp/err")"
[[ "$out" == *"· \$1.68 API-equivalent"$'\n'* && "$out" == *"  claude-opus-5-5 "*" 96%     \$1.42"$'\n'"  gpt-6-luna "*" 80%     \$0.02"$'\n'"  claude-haiku-5 "*" 50%     \$0.21"$'\n'"  claude-sonnet-5 "*"  0%     \$0.03"$'\n'* ]] \
    || fail "your prices: opus-5-5 not at claude-opus-5's, haiku-5 at the claude- family's, sonnet-5 at your later line's:"$'\n'"$out"
err="$(sed 's|.*/||' "$tmp/err")"
[[ "$err" == "agents-prices.tsv:6: not MODEL_PREFIX IN CACHE_WRITE_5M CACHE_WRITE_1H CACHE_READ OUT (USD per million tokens), ignored"$'\n'"agents-prices.tsv:7: not MODEL_PREFIX"* \
   && "$(wc -l < "$tmp/err")" -eq 2 ]] || fail "prices: bad lines: $(cat "$tmp/err")"
( HOME="$tmp/ph"; mkdir -p "$HOME"; cp "$prices" "$HOME/p.tsv"; AGENTS_PRICES="~/p.tsv"
  [[ "$(rep --view tokens 2>/dev/null)" == *"\$1.68 API-equivalent"* ]] ) || fail "prices: a ~/ path"
[[ "$(AGENTS_PRICES="$tmp/nonexistent.tsv" rep --view tokens)" == "$shipped" ]] || fail "a missing price file of yours changes the report"
printf '# only comments\n' > "$tmp/empty-prices.tsv"
[[ "$(AGENTS_PRICES="$tmp/empty-prices.tsv" rep --view tokens)" == "$shipped" ]] || fail "a price file of yours without prices changes the report"
out="$(AGENTS_PRICES=off rep --view tokens)"
[[ "$out" != *'$'* && "$out" != *"API"* && "$out" != *unpriced* ]] || fail "AGENTS_PRICES=off, still a cost:"$'\n'"$out"
jqt "$(AGENTS_PRICES=off rep --view tokens --json)" '(.priced | not) and .prices == null and .totals.est_usd == null and ([.models[] | .est_usd] | unique) == [null]' "off json" '.totals'
jqt "$(AGENTS_PRICES=off rep --json)" '.tokens.est_usd == null' "summary json without prices"
jqt "$(AGENTS_PRICES="$prices" rep --json 2>/dev/null)" '.tokens.est_usd == 1.68' "summary json with prices"
# Which line names a model: price MODEL — the prefix of the line that prices it, or "-".
price() {
    _agents_awk_eval "lib_price" 'BEGIN { prices_load(pfs); p = price_of(m); print (p ? PP[p] " " Pin[p] " " P5[p] " " P1[p] " " Pcr[p] " " Pout[p] : "-") }' \
        -v pfs="$(AGENTS_PRICES="" _agents_prices_files)" -v m="$1" < /dev/null
}
while IFS='%' read -r m want; do
    [[ "$(price "$m")" == "$want" ]] || fail "price of $m: '$(price "$m")', want '$want'"
done <<'CASES'
claude-opus-4-8%claude-opus-4-8 5 6.25 10 0.5 25
claude-opus-4-9%-
claude-opus-4%claude-opus-4 15 18.75 30 1.5 75
claude-opus-4-1-20250805%claude-opus-4-1 15 18.75 30 1.5 75
claude-opus-4-1@20250805%claude-opus-4-1 15 18.75 30 1.5 75
claude-opus-4-6[1m]%claude-opus-4-6 5 6.25 10 0.5 25
us.anthropic.claude-sonnet-4-5-20250929-v1:0%claude-sonnet-4-5 3 3.75 6 0.3 15
anthropic.claude-3-5-haiku-20241022-v1:0%claude-3-5-haiku 0.8 1 1.6 0.08 4
claude-haiku-4-5-20251001%claude-haiku-4-5 1 1.25 2 0.1 5
claude-haiku-5-5%claude-haiku-5-5 0.1 0.125 0.2 0.01 0.5
claude-haiku-5%-
claude-sonnet-5-5%claude-sonnet-5-5 2 2.5 4 0.1 10
claude-fable-5-1%claude-fable-5-1 10 12.5 20 0.25 50
claude-fable-5%claude-fable-5 10 12.5 20 1 50
gpt-5%gpt-5 1.25 1.25 1.25 0.125 10
gpt-5-2025-08-07%gpt-5 1.25 1.25 1.25 0.125 10
gpt-5.7%-
gpt-5-codex%-
gpt-5.4-mini%gpt-5.4-mini 0.75 0.75 0.75 0.075 4.5
openai/gpt-5.4-mini%gpt-5.4-mini 0.75 0.75 0.75 0.075 4.5
gpt-6-luna%gpt-6-luna 0.1 0.125 0.125 0.01 0.5
<synthetic>%-
CASES
[[ "$(_agents_awk_eval "lib_price" 'BEGIN { prices_load(pfs); printf "%.4f", usd_of(price_of("claude-opus-5-5"), 1000000, 1000000, 600000, 1000000, 1000000) }' \
    -v pfs="$(AGENTS_PRICES="" _agents_prices_files)" < /dev/null)" == 31.0000 ]] || fail "a million of each: 4 + 0.4 x 5 + 0.6 x 8 + 0.2 + 20 = 31"
pass "costs: API list prices ship; yours change or add them; the longest prefix up to a version boundary (opus-4-8 never at opus-4's, gpt-5.7 never at gpt-5's); 1h writes at their price; unpriced, never \$0; off: no cost"

# AGENTS_PRICES is a setting: a path (absolute or ~/) or off, checked like the others.
for good in /x/p.tsv '~/p.tsv' '' off; do _agents_conf_valid AGENTS_PRICES "$good" || fail "AGENTS_PRICES '$good' refused"; done
for bad in relative.tsv '~user/p.tsv' $'/a\tb' OFF; do ! _agents_conf_valid AGENTS_PRICES "$bad" || fail "AGENTS_PRICES '$bad' accepted"; done
[[ "$(AGENTS_PRICES=relative bash "$REPO_DIR/bin/agents" config 2>&1 | grep -c 'AGENTS_PRICES')" -ge 1 ]] || fail "agents config without AGENTS_PRICES"
( out="$(AGENTS_PRICES=relative bash "$REPO_DIR/bin/agents" config 2>&1)"
  [[ "$out" == *"bad AGENTS_PRICES ('relative') in the environment"* && "$out" == *"AGENTS_PRICES=$HOME/.config/tuidev/agents-prices.tsv"* ]] ) \
    || fail "a bad AGENTS_PRICES falls back to the default"
pass "AGENTS_PRICES: an absolute or ~/ path, or off; else the default with a warning"

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
[[ "$out" == *$'\n'"TOKENS  2.6M · 91% cache hits · 4% polling · 3 compactions"$'\n'"  by model, agent, session and origin: agents report --view tokens"$'\n\n'"DENIALS  11 · 4 by the classifier · 6 by you · 1 by a safety check"$'\n'"  by command and what to try: agents report --view denials"$'\n\n'"CLEANUPS (0)"* ]] \
    || fail "summary: tokens and denials:"$'\n'"$out"
[[ "$(AGENTS_PRICES="$prices" rep 2>/dev/null)" == *"TOKENS  2.6M · 91% cache hits · 4% polling · \$1.68 API-equivalent · 3 compactions"$'\n'* ]] || fail "summary: API-equivalent \$"
[[ "$(AGENTS_DATA_DIR="$e" agents_report)" != *TOKENS* ]] || fail "summary: a Tokens line without token data"
jqt "$(rep --json)" '.tokens == {"calls":8,"total":2637000,"in":129000,"cache_write":110000,"cache_write_1h":60000,"cache_read":2350000,"out":48000,"cache_hit_pct":90.8,"poll_tokens":105000,"poll_pct":4.0,"est_usd":null,"compactions":3} and .denials == {"count":11,"classifier":4,"user":6,"safety":1}' "summary json tokens" '[.tokens, .denials]'
pass "summary: Tokens (total, cache hits, polling, API-equivalent \$ when priced, compactions) and Denials lines"

# 7. The insights: past their thresholds, each naming its view; not below.
ins="$(printf '%s\n' "$out" | sed -n '/^TOP INSIGHTS$/,/^$/p')"
want="TOP INSIGHTS
  1. \`npm install\` denied ×3 by you in 24h — consider an allow rule, or an instruction not to try it
  more: agents report --view runs|waste|trends|agents|tokens|denials"
[[ "$ins" == "$want" ]] || fail "insights:"$'\n'"$ins"
jqt "$(rep --json)" '[.insights[] | [.kind, .view, .impact_s]] == [["denied","denials",300]] and .insights[0].cmd == "npm install"' "insights json" '.insights'
w="$tmp/w"; fixture "$w"
printf '%s\tclaude\tapp/agent-a1b2\tS1\tmain\tauto\t170000\t20000\n' $((FAKE_NOW - 500)) >> "$w/compacts.tsv"
AGENTS_DATA_DIR="$w" agents_insight_write
[[ "$(AGENTS_DATA_DIR="$w" _agents_insight_line)" == "insight"$'\t'"tokens"$'\t'"app: a session filled its context and compacted ×3 today — "* ]] \
    || fail "insight.txt (a subagent's worktree counts as its repository): $(cat "$w/insight.txt")"
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
    [[ "$(kinds "$(th_case k3 '' '30 auto'$'\n''20 manual'$'\n''10 auto'$'\n' '')")" == "" ]] || fail "a /compact you ran counts toward the compaction insight"
    [[ "$(kinds "$(th_case k3a '' '30 auto'$'\n''20 auto'$'\n''15 manual'$'\n''10 auto'$'\n' '')")" == "compact" ]] || fail "3 auto compactions do not fire"
    [[ "$(kinds "$(th_case u2 '' '' '30 user rm'$'\n''20 user rm'$'\n''10 classifier rm'$'\n')")" == "" ]] || fail "2 user denials fire"
    [[ "$(kinds "$(th_case u3 '' '' '30 user rm'$'\n''20 user rm'$'\n''10 user rm'$'\n')")" == "denied" ]] || fail "3 user denials do not fire"
    out="$(AGENTS_DATA_DIR="$tmp/th-c69" agents_report)"
    [[ "$out" == *"  1. claude: 69% cache hits in 24h on 1M input tokens — long sessions on one model, with stable instructions, keep the prompt cache warm"$'\n'* ]] || fail "cache insight:"$'\n'"$out"
    out="$(AGENTS_DATA_DIR="$tmp/th-p51" agents_report)"
    [[ "$out" == *"  1. 5% of tokens (50k) went to polling in 24h (most: main sessions) — wait on a background task's notification instead of polling"$'\n'* ]] || fail "polling insight:"$'\n'"$out"
    out="$(AGENTS_DATA_DIR="$tmp/th-k3a" agents_report --json | jq -r '.insights[0].text')"
    [[ "$out" == "app: a session filled its context and compacted ×3 in 24h — hand long work to subagents, or start a fresh session per task" ]] || fail "compaction insight: $out"
    pass "insights: cache <70% on 1M+, polling >5% of 1M+, auto compactions ≥3 in a session (a /compact you ran is not one), a subject you denied ≥3×; none below"
else
    echo "SKIP: insight thresholds (no jq)"
fi

# 7b. A subagent's worktree (REPO/agent-ID, as runs.tsv names it) counts as
# its repository in the token and denial tables; a worktree you named stays
# its own; the files keep the raw name.
f="$tmp/fold"
rows "$f" tokens.tsv <<EOF
600${T}claude${T}app${T}S1${T}main${T}m-1${T}100${T}0${T}0${T}0${T}0
500${T}claude${T}app/agent-a1b2c3d4${T}S1${T}Explore${T}m-1${T}200${T}0${T}0${T}0${T}0
400${T}claude${T}app/agent-ffff0000${T}S1${T}fork${T}m-1${T}300${T}0${T}0${T}0${T}0
300${T}claude${T}app/feat${T}S1${T}main${T}m-1${T}50${T}0${T}0${T}0${T}0
EOF
rows "$f" denials.tsv <<EOF
600${T}claude${T}app/agent-a1b2c3d4${T}S1${T}Explore${T}Bash${T}user${T}-${T}rm
500${T}claude${T}app${T}S1${T}main${T}Bash${T}user${T}-${T}rm
400${T}claude${T}app/feat${T}S1${T}main${T}Bash${T}user${T}-${T}rm
EOF
out="$(AGENTS_DATA_DIR="$f" agents_report --view tokens)"
[[ "$out" == *"  PROJECT  "*$'\n'"  app                        600   92% "*$'\n'"  app/feat                    50    8% "* && "$out" != *agent-* ]] || fail "tokens: worktrees not folded:"$'\n'"$out"
[[ "$(AGENTS_DATA_DIR="$f" agents_report --view denials)" == *"BY PROJECT   app 2 · app/feat 1"* ]] || fail "denials: worktrees not folded:"$'\n'"$(AGENTS_DATA_DIR="$f" agents_report --view denials)"
jqt "$(AGENTS_DATA_DIR="$f" agents_report --view tokens --json)" '[.projects[] | [.project, .total]] == [["app",600],["app/feat",50]]' "tokens json: folded projects" '.projects'
pass "a subagent's worktree (REPO/agent-ID) counts as its repository; a named worktree stays its own"

# 7c. A Codex reading 6 days old or more shows its date, not a weekday that
# would name the wrong week.
o="$tmp/oldlim"; mkdir -p "$o"; cp "$d/tokens.tsv" "$o/"
printf '%s\tcodex\t42.5\t300\t%s\n' $((FAKE_NOW - 8 * 86400)) $((FAKE_NOW - 8 * 86400 + 4800)) > "$o/limits.tsv"
[[ "$(AGENTS_DATA_DIR="$o" agents_report --view tokens)" == *"CODEX PLAN  the 5h window has reset since the last reading (43% used at Oct  6 15:00)" ]] \
    || fail "an old Codex reading:"$'\n'"$(AGENTS_DATA_DIR="$o" agents_report --view tokens | tail -1)"
printf '%s\tcodex\t42.5\t300\t%s\n' $((FAKE_NOW - 2 * 86400)) $((FAKE_NOW - 2 * 86400 + 4800)) > "$o/limits.tsv"
[[ "$(AGENTS_DATA_DIR="$o" agents_report --view tokens)" == *"(43% used at Sun 15:00)" ]] || fail "a 2-day-old Codex reading: $(AGENTS_DATA_DIR="$o" agents_report --view tokens | tail -1)"
pass "the Codex plan: a weekday within the week, the date for an older reading"

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
    [[ "$(_agents_awk_eval "lib_json lib_sort lib_fmt lib_price report_fmt report_runs report_tokens report_denials report_insights report_views" 'BEGIN { print tk(x) }' -v x="${n%%:*}")" == "${n#*:}" ]] \
        || fail "report and menu disagree on ${n%%:*}"
done
printf 'hist\toff\t0\t-\t0\n' > "$tmp/tsv"
[[ "$(AGENTS_BIN="$tmp/agents-stub" bash "$REPO_DIR/configs/swiftbar/agents.10s.sh")" != *"tokens today"* ]] || fail "a tokens row without the tsv line"
pass "menu: '2.6M tokens today · 91% cached' under Today (k/M/B as the report writes them), opening today's tokens view"

# 11. The daily rollup (the prune, once a day): tokens.tsv's rows before
# local midnight yesterday become one row per day and name, and every
# report reads the same before and after it. A window that reaches before
# yesterday counts whole days there, so it is the same either way; one
# within the last two days counts each row by its time.
r="$tmp/roll"; mkdir -p "$r"
# A month of rows (from 29d 23h ago to now): messages of 4 models, 2 CLIs, 2
# projects, 3 sessions, 2 agent types, polls, 1h writes and origins, some in
# the 11 columns of rows written before those were recorded.
awk -v n="$FAKE_NOW" 'BEGIN {
    OFS = "\t"; split("claude-opus-5-5 claude-sonnet-4-5-20250929 gpt-5.4 model-unpriced", m, " "); split("you headless subagent fork", o, " ")
    for (i = 0; i < 12000; i++) {
        t = n - (i * 7919) % (29 * 86400 + 82800); a = (i % 5 == 0) ? "Explore" : "main"
        w = 100 + i % 900
        row = t OFS (i % 4 ? "claude" : "codex") OFS "proj-" (i % 2) OFS "s" (i % 3) OFS a OFS m[i % 4 + 1] OFS (10 + i % 50) OFS w OFS (1000 + i % 5000) OFS (50 + i % 300) OFS (i % 17 == 0)
        print (i % 3 ? row OFS int(w * (i % 4) / 4) OFS o[i % 4 + 1] : row)
    }
}' > "$r/tokens.tsv"
cp "$d/compacts.tsv" "$d/denials.tsv" "$d/limits.tsv" "$r/"
views() {   # every report that reads tokens.tsv, with costs
    local s
    for s in 30d 7d 48h 24h today 2h; do
        AGENTS_PRICES="" AGENTS_DATA_DIR="$r" agents_report --view tokens --since "$s" --json
        AGENTS_PRICES="" AGENTS_DATA_DIR="$r" agents_report --since "$s" --json
    done
    AGENTS_PRICES="" AGENTS_DATA_DIR="$r" agents_report --view tokens --since 30d
    AGENTS_PRICES="" AGENTS_DATA_DIR="$r" agents_report
    AGENTS_PRICES="" AGENTS_DATA_DIR="$r" agents_session_tokens s0 s1 s9
}
before="$(views)"
# The old way of counting a window, every row by its time: the same total
# for 30d (every row is in it) and 24h (all within the last two days).
for s in 30 1; do
    sum="$(awk -F '\t' -v c="$((FAKE_NOW - s * 86400))" '$1 >= c { t += $7 + $8 + $9 + $10; n++ } END { printf "%d %d", n, t }' "$r/tokens.tsv")"
    jqt "$(AGENTS_DATA_DIR="$r" agents_report --view tokens --since "${s}d" --json)" ".totals.calls == ${sum% *} and .totals.total == ${sum#* }" "rollup: ${s}d against every row by its time" '.totals'
done
lines="$(wc -l < "$r/tokens.tsv")"
( AGENTS_DATA_DIR="$r"; _agents_tokens_prune "$FAKE_NOW" "$((FAKE_NOW - 30 * 86400))" )
raw="$(_agents_tokens_raw_since "$FAKE_NOW" 0)"
[[ "$(awk -F '\t' 'NF >= 14' "$r/tokens.tsv" | wc -l)" -gt 0 && "$(wc -l < "$r/tokens.tsv")" -lt $((lines / 2)) ]] \
    || fail "rollup: $lines rows became $(wc -l < "$r/tokens.tsv")"
awk -F '\t' -v r="$raw" 'NF >= 14 && ($1 + 0 >= r || ($1 + 0) % 86400) { exit 1 } NF < 14 && $1 + 0 < r { exit 1 }' "$r/tokens.tsv" \
    || fail "rollup: a day row at or after midnight yesterday, or not at a midnight; or a message row before it"
[[ "$(awk -F '\t' 'NF >= 14 { c += $14 } NF < 14 { c++ } END { print c }' "$r/tokens.tsv")" == 12000 ]] || fail "rollup: the calls do not add up"
after="$(views)"
printf '%s\n' "$before" > "$tmp/roll.before"; printf '%s\n' "$after" > "$tmp/roll.after"
[[ "$after" == "$before" ]] || fail "rollup: the reports changed:"$'\n'"$(tr ',' '\n' < "$tmp/roll.before" > "$tmp/rb"; tr ',' '\n' < "$tmp/roll.after" > "$tmp/ra"; diff "$tmp/rb" "$tmp/ra" | head -20)"
cp "$r/tokens.tsv" "$tmp/roll.once"
( AGENTS_DATA_DIR="$r"; _agents_tokens_prune "$FAKE_NOW" "$((FAKE_NOW - 30 * 86400))" )
cmp -s "$r/tokens.tsv" "$tmp/roll.once" || fail "rollup: a second run changed tokens.tsv"
# A late row (a catch-up scan writes 10-day-old messages) joins its day.
printf '%s\tclaude\tproj-1\ts1\tmain\tclaude-opus-5-5\t1\t2\t3\t4\t0\t1\tyou\n' $((FAKE_NOW - 10 * 86400)) >> "$r/tokens.tsv"
before="$(views)"
( AGENTS_DATA_DIR="$r"; _agents_tokens_prune "$FAKE_NOW" "$((FAKE_NOW - 30 * 86400))" )
[[ "$(views)" == "$before" && -z "$(awk -F '\t' -v t=$((FAKE_NOW - 10 * 86400)) '$1 == t' "$r/tokens.tsv")" ]] || fail "rollup: a late row did not join its day"
# A day that ended a retention ago goes, whole; a malformed line in reach stays.
printf '%s\tclaude\tp\ts\tmain\tm\t1\t1\t1\t1\t0\t0\t-\t9\n' $((raw - 40 * 86400)) >> "$r/tokens.tsv"
printf '%s\tnot a row\n' "$FAKE_NOW" >> "$r/tokens.tsv"
( AGENTS_DATA_DIR="$r"; _agents_tokens_prune "$FAKE_NOW" "$((FAKE_NOW - 30 * 86400))" )
[[ "$(awk -F '\t' -v c="$((raw - 40 * 86400))" '$1 == c' "$r/tokens.tsv")" == "" && "$(tail -1 "$r/tokens.tsv")" == "$FAKE_NOW	not a row" ]] \
    || fail "rollup: retention: $(tail -2 "$r/tokens.tsv")"
jqt "$(AGENTS_DATA_DIR="$r" agents_report --view tokens --since 7d --json)" ".tokens_since == $(( FAKE_NOW - 7 * 86400 - (FAKE_NOW - 7 * 86400) % 86400 ))" "rollup: 7d counts from midnight" '.tokens_since'
[[ "$(AGENTS_DATA_DIR="$r" agents_report --view tokens --since 7d)" == *$'\n'"tokens before yesterday are kept by day: this window counts them from Oct  7 00:00" ]] \
    || fail "rollup: the note on whole days: $(AGENTS_DATA_DIR="$r" agents_report --view tokens --since 7d | tail -2)"
[[ "$(rep --view tokens)" != *"kept by day"* ]] || fail "rollup: a 24h window says it counts whole days"
pass "the daily rollup: a month of rows to a day each (calls kept), the same reports before and after (30d, 7d, 48h, 24h, today, 2h, the summary, a session), idempotent, late rows join their day, retention by whole day"

# 12. One session's tokens for another view (agents show): origin, CLI,
# project, its main conversation's latest model, calls, tokens, cost.
want="S1	you	claude	app	claude-opus-5-5	3	2005000	1.31	105000
C1	you	codex	web	gpt-6-luna	1	520000	0.02	0
S2	headless	claude	shop	claude-opus-5-5	2	111000	0.11	0"
[[ "$(AGENTS_PRICES="" AGENTS_DATA_DIR="$d" agents_session_tokens S1 C1 nope S2 S1 'bad;id')" == "$want" ]] \
    || fail "session tokens:"$'\n'"$(AGENTS_PRICES="" AGENTS_DATA_DIR="$d" agents_session_tokens S1 C1 nope S2 S1 'bad;id')"
[[ "$(AGENTS_DATA_DIR="$d" agents_session_tokens S2)" == "S2	headless	claude	shop	claude-opus-5-5	2	111000	-	-" ]] || fail "session tokens with AGENTS_PRICES=off"
[[ -z "$(AGENTS_DATA_DIR="$tmp/none" agents_session_tokens S1)" && -z "$(AGENTS_DATA_DIR="$d" agents_session_tokens)" ]] || fail "session tokens without data"
pass "agents_session_tokens: a session's origin, CLI, project, model, calls, tokens, API-equivalent cost and its unpriced tokens; nothing for one without tokens"

# 13. The context view: the MCP servers sessions call and list, skills,
# subagent types, the plugins enabled and what each brings, Codex's MCP
# servers, and what is loaded or enabled but unused. Names and counts only:
# no value from a config reaches it.
cc="$tmp/ctx/claude"; cx="$tmp/ctx/codex"; pl="$cc/plugins/cache/mkt"
mkdir -p "$pl/alpha/1.0/skills/a1" "$pl/alpha/1.0/skills/a2" "$pl/alpha/1.0/agents" "$pl/alpha/1.0/commands" "$pl/alpha/1.0/hooks" "$pl/beta/1.0/skills/b1" "$pl/delta/1.0/skills/d1" "$cx"
touch "$pl/alpha/1.0/skills/a1/SKILL.md" "$pl/alpha/1.0/skills/a2/SKILL.md" "$pl/alpha/1.0/agents/x.md" "$pl/alpha/1.0/commands/c.md" "$pl/beta/1.0/skills/b1/SKILL.md"
printf '{"mcpServers":{"alphadb":{"command":"npx","args":["--token","sk-arg-456"],"env":{"API_KEY":"sk-env-789"}}}}' > "$pl/alpha/1.0/.mcp.json"
printf '{"hooks":{"PreToolUse":[{"hooks":[{"type":"command","command":"sk-hook-1"}]}],"SessionStart":[]}}' > "$pl/alpha/1.0/hooks/hooks.json"
printf '{"env":{"SECRET":"sk-live-123"},"enabledPlugins":{"alpha@mkt":true,"beta@mkt":true,"gamma@mkt":false,"delta@mkt":false,"bad name@x":true}}' > "$cc/settings.json"
printf '{"version":2,"plugins":{"alpha@mkt":[{"installPath":"%s"}],"beta@mkt":[{"installPath":"%s"}],"gamma@mkt":[{"installPath":"/etc"}],"delta@mkt":[{"installPath":"%s"}]}}' \
    "$pl/alpha/1.0" "$pl/beta/1.0" "$pl/delta/1.0" > "$cc/plugins/installed_plugins.json"
cat > "$cx/config.toml" <<'EOF'
model = "gpt-5.4"
[mcp_servers.playwright]
command = "npx"
args = ["@playwright/mcp", "--secret", "sk-toml-111"]
[mcp_servers.playwright.env]
TOKEN = "sk-toml-222"
[mcp_servers."docs.server"]
url = "https://example.invalid/mcp"
enabled = false
[mcp_servers.used]
command = "sk-toml-333"
EOF
# Claude Code's own servers: user, local and project scope (mcp.sh reads them).
cproj="$tmp/ctx/proj"; mkdir -p "$cproj"
printf '{"mcpServers":{"github":{"command":"npx","args":["-y","gh-mcp","--token","sk-user-1"],"env":{"T":"sk-user-2"}},"figma":{"type":"http","url":"https://figma.example.invalid/mcp?k=sk-user-3","headers":{"Authorization":"sk-user-4"}}},"projects":{"%s":{"mcpServers":{"localdb":{"command":"sk-local-1","args":["sk-local-2"]}}}}}' "$cproj" > "$cc/.claude.json"
printf '{"mcpServers":{"filesys":{"command":"npx","args":["sk-proj-1"]}}}' > "$cproj/.mcp.json"
c="$tmp/ctxd"; mkdir -p "$c"; cp "$d/tokens.tsv" "$c/"
rows "$c" uses.tsv <<EOF
600${T}claude${T}app${T}S1${T}main${T}mcp${T}claude-in-chrome${T}5
600${T}claude${T}app${T}S1${T}main${T}listed${T}claude-in-chrome${T}20
500${T}claude${T}shop${T}S2${T}main${T}listed${T}claude-in-chrome${T}18
400${T}claude${T}shop${T}S2${T}main${T}listed${T}claude-in-chrome${T}22
600${T}claude${T}app${T}S1${T}main${T}listed${T}github${T}40
500${T}claude${T}shop${T}S2${T}main${T}listed${T}github${T}40
691200${T}claude${T}app${T}S1${T}main${T}mcp${T}github${T}9
300${T}claude${T}app${T}S1${T}main${T}mcp${T}plugin_alpha_alphadb${T}3
300${T}claude${T}app${T}S1${T}main${T}listed${T}plugin_alpha_alphadb${T}7
200${T}claude${T}app${T}S1${T}main${T}skill${T}update-config${T}2
200${T}claude${T}shop${T}S2${T}main${T}skill${T}update-config${T}1
200${T}claude${T}app${T}S1${T}main${T}agent${T}Explore${T}3
200${T}claude${T}app${T}S1${T}main${T}agent${T}implementor-complex${T}1
100${T}codex${T}web${T}C1${T}main${T}mcp${T}used${T}4
EOF
ctx() { CLAUDE_CONFIG_DIR="$cc" CODEX_HOME="$cx" AGENTS_DATA_DIR="$c" AGENTS_RUN_DIR="$tmp/ctx/run" agents_report --view context "$@"; }
out="$(ctx)"
want="agents report · context · last 7d

MCP SERVERS
  SERVER                 CLI     CALLS  USED IN LISTED IN TOOLS  FROM
  claude-in-chrome       claude      5        1         2    21  -
  used                   codex       4        1         0     -  config
  alphadb                claude      3        1         1     7  plugin alpha
  github                 claude      0        0         2    40  user
  figma                  claude      0        0         0     -  user
  filesys                claude      0        0         0     -  project
  localdb                claude      0        0         0     -  local
  docs.server            codex       0        0         0     -  config (off)
  playwright             codex       0        0         0     -  config

SKILLS
  SKILL                           CALLS SESSIONS
  update-config                       3        2

SUBAGENTS
  TYPE                           STARTED  TOKENS     %
  Explore                              3    105k    3%
  (unknown)                            0      6k    0%
  implementor-complex                  1       0    0%

PLUGINS  2 of 4 enabled (Claude Code)
  alpha                  2 skills, 1 agent, 1 command, 1 MCP server, 2 hook events · 3 calls
  beta                   1 skill, 0 agents, 0 commands, 0 MCP servers, 0 hook events · 0 calls

CLEANUP CANDIDATES  loaded or enabled, unused in 7d
  github: 40 tools listed in 2 sessions, never called — remove it with \`claude mcp remove github -s user\`
  figma: never called — remove it with \`claude mcp remove figma -s user\`
  filesys: never called — remove it with \`claude mcp remove filesys -s project\`
  localdb: never called — remove it with \`claude mcp remove localdb -s local\`
  playwright (Codex MCP server): never called — remove it from ~/.codex/config.toml, or set enabled = false
  beta (plugin): 1 skill, 0 agents, 0 commands, 0 MCP servers, 0 hook events, none used — disable it (/plugin) to load less into every session"
printf '%s\n' "$out" > "$tmp/ctx.got"; printf '%s\n' "$want" > "$tmp/ctx.want"
[[ "$out" == "$want" ]] || fail "context view:"$'\n'"$(diff "$tmp/ctx.want" "$tmp/ctx.got")"
json="$(ctx --json)"
jqt "$json" '.view == "context" and .window == "7d" and ([.mcp_servers[] | [.server, .cli, .source, .plugin, .calls, .sessions_used, .sessions_listed, .tools_listed]] == [["claude-in-chrome","claude",null,null,5,1,2,21],["used","codex","config",null,4,1,0,null],["alphadb","claude","plugin","alpha",3,1,1,7],["github","claude","user",null,0,0,2,40],["figma","claude","user",null,0,0,0,null],["filesys","claude","project",null,0,0,0,null],["localdb","claude","local",null,0,0,0,null],["docs.server","codex","config",null,0,0,0,null],["playwright","codex","config",null,0,0,0,null]]) and ([.mcp_servers[] | [.server, .configured, .enabled]] | map(select(.[0] == "docs.server" or .[0] == "claude-in-chrome" or .[0] == "alphadb")) == [["claude-in-chrome",false,null],["alphadb",true,true],["docs.server",true,false]]) and (has("codex_mcp_servers") | not)' "context json: servers" '.mcp_servers'
jqt "$json" '[.plugins[] | [.plugin, .enabled, .installed, .skills, .agents, .commands, .mcp_servers, .hooks, .calls]] == [["alpha",true,true,2,1,1,1,2,3],["beta",true,true,1,0,0,0,0,0],["gamma",false,false,null,null,null,null,null,0],["delta",false,true,null,null,null,null,null,0]]' "context json: plugins" '.plugins'
jqt "$json" '[.cleanup[] | [.kind, .name]] == [["mcp","github"],["mcp","figma"],["mcp","filesys"],["mcp","localdb"],["codex_mcp","playwright"],["plugin","beta"]]' "context json: cleanup" '.cleanup'
jqt "$json" '.skills == [{"skill":"update-config","plugin":null,"calls":3,"sessions":2}] and ([.subagents[] | [.agent, .started]] == [["Explore",3],[null,0],["implementor-complex",1]])' "context json: skills, subagents" '[.skills, .subagents]'
[[ "$out$json" != *sk-* && "$out$json" != *npx* && "$out$json" != *example.invalid* && "$out$json" != *gh-mcp* && "$out$json" != *"bad name"* ]] || fail "context: a config value reached the report"
[[ "$(CLAUDE_CONFIG_DIR="$tmp/none" CODEX_HOME="$tmp/none" AGENTS_DATA_DIR="$tmp/none" AGENTS_RUN_DIR="$tmp/none-run" agents_report --view context)" == *"  none configured, called or listed in this window"*"PLUGINS  none in Claude Code's settings"*"CLEANUP CANDIDATES  none: everything loaded was used in 7d" ]] \
    || fail "context without data: $(CLAUDE_CONFIG_DIR="$tmp/none" CODEX_HOME="$tmp/none" AGENTS_DATA_DIR="$tmp/none" AGENTS_RUN_DIR="$tmp/none-run" agents_report --view context)"
pass "context: every configured MCP server (Claude user/local/project/plugin, Codex) with its calls, listed tools, skills, subagent types, plugins, cleanup candidates; never a config value"

echo "All agents report tokens tests passed."
