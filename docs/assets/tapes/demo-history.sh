#!/bin/bash
# Write a made-up week of `agents` history into a demo home
# (docs/assets/tapes/README.md): demo-history.sh HOME. Idempotent: an existing
# history is kept. It fills what `agents sample` and the cleanups would have
# recorded (history.tsv, events.tsv, today.tsv, sample.stamp), so `agents
# report` and the menu's Today line have numbers. The rows follow a working
# day in the current time zone, with fixed noise (srand 7), ending now.
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
chmod 600 "$dir"/*.tsv
echo "$now" > "$dir/sample.stamp"
