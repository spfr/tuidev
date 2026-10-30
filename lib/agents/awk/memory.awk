# lib/agents/awk/memory.awk — the memory guard's candidates, from a snapshot
# on stdin: the processes holding the most memory, biggest first, at most
# -v max=N of them, one line each:
#   PID START RSS_KIB UID NAME LABEL ROOT ROOT_KIND
# A process qualifies at -v screen=KIB of RSS or more; with -v floor=KIB as
# well (memory pressure is up), the largest down to that floor do too. LABEL
# is the script an interpreter runs (node's clientFuelToday.test.js), ROOT
# the topmost agent above it and ROOT_KIND that agent's kind ("-" for both
# outside any agent tree). With -v pids=" PID PID ", exactly those qualify
# (`agents mem`, which has top's list). Never this process or its ancestors
# (-v self=PID). Needs lib_proc.

# label(a): the first argument after the program that names a file (has a /
# or a dot, no leading dash), as its basename: what tells one node from
# another. "-" when there is none, and for an app (its bundle path has
# spaces: pname already names it).
function label(a,   n, w, i, b) {
    if (index(a, ".app/Contents/")) return "-"
    n = split(a, w, " ")
    for (i = 2; i <= n && i <= 12; i++) {
        if (substr(w[i], 1, 1) == "-" || (index(w[i], "/") == 0 && index(w[i], ".") == 0)) continue
        b = w[i]; sub(/.*\//, "", b)
        if (b != "") return printable(b)
    }
    return "-"
}
NF >= 14 {
    p = $1 + 0
    if (p in pp) next
    ord[++n] = p
    pp[p] = $2 + 0; uid[p] = $3; rss[p] = $6 + 0; st[p] = lstart()
    s = argv($0); if (index(s, "\t")) gsub(/\t/, " ", s)
    av[p] = s
}
END {
    ancestors(self)
    screen += 0; floor += 0; max += 0
    lim = (floor > 0 && floor < screen) ? floor : screen
    nc = 0
    for (k = 1; k <= n; k++) {
        p = ord[k]
        if (p <= 1 || anc[p]) continue
        if (pids != "" ? !index(pids, " " p " ") : rss[p] < lim) continue
        c[++nc] = p
    }
    # Biggest first (a selection sort: only a few qualify).
    for (j = 1; j <= nc && j <= max; j++) {
        b = j
        for (i = j + 1; i <= nc; i++) if (rss[c[i]] > rss[c[b]]) b = i
        t = c[j]; c[j] = c[b]; c[b] = t
        p = c[j]
        # Under pressure the floor lets in the largest few; past screen only
        # the big ones.
        if (pids == "" && rss[p] < screen && j > 5) break
        top = ""; q = p; d = 0
        while (q > 1 && (q in pp) && d++ < 64) { if (agent_kind(av[q]) != "") top = q; q = pp[q] }
        printf "%d\t%s\t%d\t%s\t%s\t%s\t%s\t%s\n", p, st[p], rss[p], uid[p], printable(pname(av[p])), label(av[p]), \
            (top == "" ? "-" : top), (top == "" ? "-" : agent_kind(av[top]))
    }
}
