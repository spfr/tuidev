# lib/agents/awk/classify.awk — agents_classify's single pass over a
# snapshot: agent, stale, cand, hog, top, total, act, watch, where and job
# records (classify.sh documents the columns). Needs lib_proc, lib_activity,
# lib_jobs and lib_where.

function addports(q, list,   n, a, i) {
    n = split(list, a, ",")
    for (i = 1; i <= n; i++)
        if (index("," tp[q] ",", "," a[i] ",") == 0) tp[q] = (tp[q] == "" ? a[i] : tp[q] "," a[i])
}
function rec(type, p, kind, c, r, k, ports) {
    printf "%s\t%d\t%s\t%d\t%.1f\t%.1f\t%d\t%d\t%s\t%s\t%s\t-\t-\t%s\n", type, p, kind, et[p], c, avg(p), r, k, st[p], (ports == "" ? "-" : ports), usr[p], av[p]
}
function avg(p) { return et[p] > 0 ? 100 * ct[p] / et[p] : 0 }
function act(p, cls, r, label, cmd) {
    gsub(/\t/, " ", cmd)
    printf "act\t%d\t%s\t%d\t%.1f\t%.1f\t%d\t%d\t%s\t%s\t%d\t%s\t-\t%s\n", p, cls, et[p], tcpu[p], avg(p), trss[p], kids[p], st[p], (tp[p] == "" ? "-" : tp[p]), r, label, cmd
}
BEGIN {
    me = ENVIRON["AGENTS_UID"]; self = ENVIRON["AGENTS_SELF"] + 0
    np = split(ENVIRON["AGENTS_PATTERNS"], pat, "\n")
    n = split(ENVIRON["AGENTS_KEEP"], t, "[ \n]+"); for (i = 1; i <= n; i++) if (t[i] != "") keep[t[i] + 0] = 1
    n = split(ENVIRON["AGENTS_LISTEN"], t, "\n")
    for (i = 1; i <= n; i++) {
        if (split(t[i], f, " ") < 2) continue
        q = f[1] + 0
        if (index("," lp[q] ",", "," f[2] ",") == 0) lp[q] = (lp[q] == "" ? f[2] : lp[q] "," f[2])
    }
    daemon = ENVIRON["AGENTS_DAEMON"]; sysre = ENVIRON["AGENTS_SYSTEM"]
    hogpct = ENVIRON["AGENTS_HOG_PCT"] + 0; hogmin = 60 * ENVIRON["AGENTS_HOG_MIN"]
    hognow = ENVIRON["AGENTS_HOG_NOW"] + 0; hogtop = ENVIRON["AGENTS_HOG_TOP"] + 0; ntop = ENVIRON["AGENTS_BAR_TOP"] + 0
    n = 0
}
NF >= 14 {
    p = $1 + 0
    if (p in pp) next
    ord[++n] = p
    pp[p] = $2 + 0; uid[p] = $3; usr[p] = $4; cpu[p] = $5 + 0; rss[p] = $6 + 0
    ct[p] = secs($7); et[p] = secs($8); st[p] = lstart()
    s = argv($0); if (index(s, "\t")) gsub(/\t/, " ", s)
    av[p] = s
}
END {
    for (k = 1; k <= n; k++) {
        p = ord[k]
        isd[p] = (av[p] ~ daemon)
        kind[p] = isd[p] ? "daemon" : agent_kind(av[p])
    }
    # This process and its ancestors: never a hog, never stale, never killed.
    ancestors(self)
    # Walk up from every process: its topmost agent ancestor (the root of its
    # agent tree) and whether it runs under this process; then add it to every
    # ancestor subtree sums, leaving out the subtree of this process (ps, us).
    for (k = 1; k <= n; k++) {
        p = ord[k]; top = ""; under = 0; q = p; d = 0
        while (q > 1 && (q in pp) && d++ < 64) {
            if (kind[q] != "") top = q
            if (q == self) under = 1
            q = pp[q]
        }
        root[p] = top; mine[p] = under
        if (under) continue
        # A process that hosts a session (an agent, an interactive shell, a
        # tmux/screen/zellij/herdr/pm2 server) shelters every ancestor.
        host = (kind[p] != "" || interactive_shell(av[p]) || supervisor(av[p]))   # hosts(), kind[] known
        q = p; d = 0
        while (q > 1 && (q in pp) && d++ < 64) {
            tcpu[q] += cpu[p]; trss[q] += rss[p]
            if (q != p) kids[q]++
            if (p in lp) addports(q, lp[p])
            if (host) shelter[q] = 1
            q = pp[q]
        }
    }
    nh = 0
    for (k = 1; k <= n; k++) {
        p = ord[k]
        if (root[p] == p) {
            rec("agent", p, kind[p], tcpu[p], trss[p], kids[p], tp[p])
            printf "where\t%d\t%s\n", p, where_of(p)
        } else if (pp[p] == 1 && uid[p] == me && kind[p] == "" && !(p in keep) && !mine[p] && !anc[p] && !shelter[p]) {
            hit = 0
            for (i = 1; i <= np; i++) if (pat[i] != "" && av[p] ~ pat[i]) { hit = 1; break }
            if (hit) { rec("stale", p, "orphan", tcpu[p], trss[p], kids[p], tp[p]); sroot[p] = 1 }
            # A dev server listens itself or through its children (`npm run dev`
            # starting vite); a tree that hosts a session never gets here.
            else if (tp[p] != "" && av[p] !~ sysre) { rec("cand", p, "server", tcpu[p], trss[p], kids[p], tp[p]); sroot[p] = 1 }
        }
        if (p <= 1 || anc[p] || mine[p]) continue
        a = avg(p)
        if ((et[p] >= hogmin && a >= hogpct) || (cpu[p] >= hognow && root[p] == "")) {
            hp[++nh] = p; score[nh] = (a > cpu[p] ? a : cpu[p])
        }
    }
    for (j = 1; j <= hogtop && j <= nh; j++) {
        best = j
        for (i = j + 1; i <= nh; i++) if (score[i] > score[best]) best = i
        t1 = hp[j]; hp[j] = hp[best]; hp[best] = t1
        t2 = score[j]; score[j] = score[best]; score[best] = t2
        rec("hog", hp[j], pname(av[hp[j]]), cpu[hp[j]], rss[hp[j]], 0, "")
        ishog[hp[j]] = 1
    }
    # The busiest processes right now that are not already listed as hogs,
    # and the machine total (both leave out this process and its children).
    nt = 0; sum = 0
    for (k = 1; k <= n; k++) {
        p = ord[k]
        if (mine[p]) continue
        sum += cpu[p]
        if (p > 1 && !anc[p] && !ishog[p] && cpu[p] > 0) tq[++nt] = p
    }
    for (j = 1; j <= ntop && j <= nt; j++) {
        best = j
        for (i = j + 1; i <= nt; i++) if (cpu[tq[i]] > cpu[tq[best]]) best = i
        t1 = tq[j]; tq[j] = tq[best]; tq[best] = t1
        rec("top", tq[j], pname(av[tq[j]]), cpu[tq[j]], rss[tq[j]], 0, "")
    }
    printf "total\t0\t-\t0\t%.1f\t0\t0\t0\t-\t-\t-\t-\t-\t-\n", sum
    # Activity: every child of a session root is one unit (mcp, tool,
    # keepawake, session, other) with its subtree totals; agents nested deeper
    # (claude -p from a tool shell) are listed as nested sessions too.
    #   act PID CLASS AGE CPU AVG RSS KIDS START PORTS ROOT LABEL - CMD
    # LABEL: the MCP server name, the depth of a nested session, or the directory
    # a tool command cd's into first (where it really runs).
    for (k = 1; k <= n; k++) {
        p = ord[k]; r = root[p]
        if (r == "" || p == r || mine[p] || isd[r]) continue
        if (kind[p] != "" && !isd[p]) {
            act(p, "session", r, (pp[p] == r ? "direct" : "nested"), av[p]); continue
        }
        if (pp[p] != r) continue
        a = av[p]
        if (a ~ /(^|\/)caffeinate( |$)/) act(p, "keepawake", r, "-", a)
        else if (tool_shell(a)) {
            c = tool_cmd(a); act(p, "tool", r, (tool_cd == "" ? "-" : tool_cd), c)
            if (tool_watch != "" && waits(c)) { gsub(/\t/, " ", tool_watch); printf "watch\t%d\t%s\t%s\n", p, tool_watch, (watch_reads ? "read" : "exists") }
        }
        else if (is_mcp(a)) act(p, "mcp", r, mcp_name(a, kind[r]), a)
        else act(p, "other", r, "-", a)
    }
    jobs_emit()
}
