#!/bin/bash
# Write a made-up week of `agents` history into a demo home
# (docs/assets/tapes/README.md): demo-history.sh HOME. Idempotent: an existing
# history is kept. It fills what `agents sample` and the cleanups would have
# recorded (history.tsv, events.tsv, today.tsv, runs.tsv, sample.stamp), so
# `agents report` and the menu's Today line have numbers, then has the real
# `agents` code write the menu's top insight (insight.txt) from them. The rows
# follow a working day in the current time zone, with fixed noise (srand 7),
# ending now.
set -eo pipefail

home="${1:?usage: demo-history.sh HOME}"
dir="$home/.local/state/tuidev/agents"
[[ -s "$dir/history.tsv" ]] && exit 0
mkdir -p "$dir"
chmod 700 "$dir" "$home/.local/state/tuidev" 2>/dev/null || true

now="$(date +%s)"
day="$(date +%Y-%m-%d)"
# Seconds east of UTC (date +%z is +HHMM), and the epoch of local midnight.
z="$(date +%z)"
off=$(( (10#${z:1:2} * 3600 + 10#${z:3:2} * 60) * (${z:0:1}1) ))
midnight=$(( now - (now + off) % 86400 ))

LC_ALL=C awk -v now="$now" -v off="$off" -v midnight="$midnight" -v day="$day" \
    -v hf="$dir/history.tsv" -v ef="$dir/events.tsv" -v tf="$dir/today.tsv" '
BEGIN {
    srand(7)
    # Share of a working day by local hour: quiet nights, a lunch dip.
    split("0.05 0.04 0.04 0.04 0.04 0.05 0.08 0.2 0.45 0.8 1 1 0.55 0.85 1.15 1.3 1.1 0.85 0.5 0.3 0.2 0.15 0.1 0.06", act, " ")
    # job project session cores_at_peak rss_kib procs
    n = split("test myapp claude 1.25 460000 6|build myapp claude 0.45 260000 3|agent myapp claude 0.22 790000 1|mcp myapp claude 0.06 380000 4|browser myapp claude 0.1 410000 7|build api claude 0.35 210000 2|test api claude 0.3 180000 3|agent api claude 0.14 510000 1|mcp api claude 0.04 150000 2|server web codex 0.22 140000 2|agent web codex 0.1 150000 1|build web codex 0.12 120000 2|other myapp claude 0.01 2000 1", w, "|")
    step = 600
    for (t = now - 7 * 86400 + step; t <= now; t += step) {
        a = act[int(((t + off) % 86400) / 3600) + 1]
        for (i = 1; i <= n; i++) {
            split(w[i], f, " ")
            c = int(0.7 * f[4] * a * step * (0.5 + rand()) + 0.5)
            if (c <= 0) continue
            printf "%d\t%s\t%s\t%s\t%d\t%d\t%d\n", t, f[1], f[2], f[3], c, f[5], f[6] > hf
            if (t >= midnight) { tot += c; if (!(f[1] in jc)) jo[++nj] = f[1]; jc[f[1]] += c }
        }
        # Helpers a dead session left behind, until something stopped them.
        if (t > now - 86400 && t < now - 9 * 3600) printf "%d\tmcp\tmyapp\t-\t%d\t131000\t2\n", t, 2 + int(rand() * 3) > hf
    }
    # today.tsv: the day and its total, then each job, busiest first.
    printf "%s\t%d\n", day, tot > tf
    for (i = 1; i <= nj; i++) {
        b = i
        for (j = i + 1; j <= nj; j++) if (jc[jo[j]] > jc[jo[b]]) b = j
        x = jo[i]; jo[i] = jo[b]; jo[b] = x
        printf "%s\t%d\n", jo[i], jc[jo[i]] > tf
    }
    # Cleanups: hours ago, kind, reason, pid, name, project, session.
    m = split("30 auto stale 4410 npm myapp -|29.9 auto stale 4411 node myapp -|26 hook subagent-end 1440 node myapp claude:1201|22 reap stuck 2620 zsh api claude:2101|20 kill manual 3180 node web claude:3101|9 auto stale 1250 npx myapp -|9 auto stale 1300 caffeinate myapp -|7.5 hook subagent-end 1275 vitest myapp claude:1201|6 hook subagent-end 1282 go myapp claude:1201|5.2 hook session-end 2130 zsh api claude:2101|3 auto stuck 1295 zsh myapp claude:1201|1.5 hook subagent-end 1288 node myapp claude:1201", e, "|")
    for (i = 1; i <= m; i++) {
        split(e[i], f, " ")
        printf "%d\t%s\t%s\t%s\t%s\t%s\t%s\n", now - f[1] * 3600, f[2], f[3], f[4], f[5], f[6], f[7] > ef
    }
}'
# The run ledger (runs.tsv: end start job project session agent cmd duration
# cpu peak exit dup cleaned), a week of working days at the same hours. Today
# tells three stories for Top insights: Explore subagents left polling loops
# running until a hook stopped them, myapp's tests ran twice at once, and
# api's build got slower than yesterday's.
LC_ALL=C awk -v now="$now" -v midnight="$midnight" -v rf="$dir/runs.tsv" '
function run(st, d, job, p, sess, a, cmd, cpu, peak, ex, dup, cl) {
    if (st + d > now - 60) return
    printf "%d\t%d\t%s\t%s\t%s\t%s\t%s\t%d\t%d\t%d\t%s\t%d\t%d\n", st + d, st, job, p, sess, a, cmd, d, cpu, peak, ex, dup, cl > rf
}
BEGIN {
    srand(7)
    for (day = 6; day >= 0; day--) {
        b = midnight - day * 86400
        # myapp: vitest through pnpm, ten a day; one failure re-run at once.
        for (i = 0; i < 10; i++) {
            st = b + int((9.2 + i * 0.55) * 3600 + rand() * 300); d = 170 + int(rand() * 60)
            dup = (day == 0 ? (i == 2 || i == 3 || i == 6 || i == 7) : (i == 3))
            ex = (i == 5 ? 1 : 0)
            run(st, d, "test", "myapp", "claude:1201", (i % 2 ? "implementor-complex" : "main"), "pnpm", int(d * 1.5), 520000, ex, dup, 0)
            if (ex) run(st + d + 40, d, "test", "myapp", "claude:1201", "main", "pnpm", int(d * 1.5), 520000, 0, 0, 0)
        }
        # api: go build (slower and more often today) and go test.
        nb = (day == 0 ? 8 : 6)
        for (i = 0; i < nb; i++) {
            st = b + int((9.5 + i * (day == 0 ? 0.7 : 1)) * 3600 + rand() * 120)
            if (day == 0) run(st, 150 + int(rand() * 20), "build", "api", "claude:2101", "main", "go", 190, 310000, 0, 0, 0)
            else run(st, 55 + int(rand() * 15), "build", "api", "claude:2101", "main", "go", 55, 260000, 0, 0, 0)
        }
        for (i = 0; i < 4; i++)
            run(b + int((10 + i * 1.2) * 3600), 90 + int(rand() * 20), "test", "api", "claude:2101", "Explore", "go", 120, 210000, 0, 0, 0)
        # Polling loops: short ones in main; today three Explore ones that
        # waited hours, until the hook stopped them.
        for (i = 0; i < 2; i++)
            run(b + int((11 + i * 2) * 3600), 600, "wait", "api", "claude:2101", "main", "wait-loop", 1, 2000, "-", 0, 0)
        if (day == 0) {
            run(b + 9.5 * 3600, 9000, "wait", "api", "claude:2101", "Explore", "wait-loop", 2, 2000, "-", 0, 1)
            run(b + 10.5 * 3600, 9700, "wait", "api", "claude:2101", "Explore", "wait-loop", 2, 2000, "-", 0, 1)
            run(b + 11 * 3600, 9000, "wait", "api", "claude:2101", "Explore", "wait-loop", 2, 2000, "-", 0, 1)
        }
        # web: the dev server, a working day long, in the Codex session.
        run(b + 9 * 3600, 8 * 3600, "server", "web", "codex:3101", "-", "npm", 420, 180000, "-", 0, 0)
    }
}'
# Tokens, as the transcript scan records them (tokens.tsv: epoch cli project
# session agent model in cache_write cache_read out poll; and today's sums in
# tokens.today), with a few compactions and denials: a healthy week (a warm
# cache, little polling), so they add no insight of their own.
LC_ALL=C awk -v now="$now" -v midnight="$midnight" -v day="$day" -v dir="$dir" '
function call(t, cli, p, s, a, m, i, cw, cr, o, poll) {
    if (t > now - 30) return
    printf "%d\t%s\t%s\t%s\t%s\t%s\t%d\t%d\t%d\t%d\t%d\n", t, cli, p, s, a, m, i, cw, cr, o, poll > (dir "/tokens.tsv")
    if (t >= midnight) { n++; ti += i; tcw += cw; tcr += cr; to += o }
}
BEGIN {
    srand(11)
    for (d = 6; d >= 0; d--) {
        b = midnight - d * 86400
        for (h = 9; h < 18; h += 0.1) {
            t = b + int(h * 3600 + rand() * 300)
            call(t, "claude", "myapp", "11111111-aaaa", "main", "claude-opus-5-5", 40 + int(rand() * 400), 900 + int(rand() * 4000), 60000 + int(rand() * 60000), 300 + int(rand() * 1500), rand() < 0.015)
            if (rand() < 0.5) call(t + 40, "claude", "myapp", "11111111-aaaa", "implementor-complex", "claude-sonnet-5", 30 + int(rand() * 200), 2000 + int(rand() * 6000), 30000 + int(rand() * 30000), 400 + int(rand() * 2000), 0)
            if (rand() < 0.6) call(t + 90, "claude", "api", "22222222-bbbb", (rand() < 0.3 ? "Explore" : "main"), "claude-opus-5-5", 40 + int(rand() * 300), 700 + int(rand() * 3000), 50000 + int(rand() * 50000), 200 + int(rand() * 1200), rand() < 0.02)
            if (rand() < 0.3) call(t + 150, "codex", "web", "33333333-cccc", "main", "gpt-6-luna", 4000 + int(rand() * 8000), 0, 40000 + int(rand() * 30000), 500 + int(rand() * 2000), 0)
        }
        printf "%d\tclaude\tmyapp\t11111111-aaaa\tmain\tauto\t%d\t%d\n", b + 13 * 3600, 150000 + int(rand() * 20000), 18000 > (dir "/compacts.tsv")
        printf "%d\tclaude\tapi\t22222222-bbbb\tmain\tclassifier\tGit Destructive\tgit push\n", b + 16 * 3600 > (dir "/denials.tsv")
    }
    printf "%d\tclaude\tmyapp\t11111111-aaaa\timplementor-complex\tBash\tuser\t-\tnpm install\n", now - 7200 > (dir "/denials.tsv")
    printf "%d\tclaude\t46.5\t300\t%d\t-\n", now - 120, now + 8400 > (dir "/limits.tsv")
    printf "%d\tclaude\t83.0\t10080\t%d\t-\n", now - 120, now + 2 * 86400 + 5400 > (dir "/limits.tsv")
    printf "%d\tcodex\t31.0\t300\t%d\t-\n", now - 900, now + 7800 > (dir "/limits.tsv")
    printf "%s\t%d\t%d\t%d\t%d\t%d\n", day, ti + tcw + tcr + to, ti, tcw, tcr, to > (dir "/tokens.today")
}'
chmod 600 "$dir"/*.tsv "$dir/tokens.today"
echo "$now" > "$dir/sample.stamp"
# The menu's top insight, as `agents sample` writes it, by the real code.
(
    export HOME="$home" AGENTS_CONF=/dev/null AGENTS_DATA_DIR="$dir" AGENTS_HISTORY=1
    # shellcheck source=../../../bin/agents disable=SC1091
    . "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)/bin/agents"
    agents_insight_write
)
