# lib/agents/awk/tree.awk — agents_tree: pid t and its descendants, each
# with its depth (the caller sorts deepest first). Needs lib_proc.

NF >= 14 {
    p = $1 + 0; pp[p] = $2 + 0; uid[p] = $3; st[p] = $9 "_" $10 "_" $11 "_" $12 "_" $13
    s = argv($0); nm[p] = pname(s); cr[p] = critical(s); kids[pp[p]] = kids[pp[p]] " " p
}
END {
    t += 0; if (!(t in pp)) exit
    q[1] = t; dep[t] = 0; h = 1; n = 1
    while (h <= n) { p = q[h++]; m = split(kids[p], c, " "); for (i = 1; i <= m; i++) { q[++n] = c[i] + 0; dep[c[i] + 0] = dep[p] + 1 } }
    for (i = 1; i <= n; i++) printf "%d\t%s\t%s\t%s\t%s\t%d\n", dep[q[i]], q[i], st[q[i]], uid[q[i]], nm[q[i]], cr[q[i]]
}
