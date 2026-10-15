# lib/agents/awk/show_tree.awk — `agents show`'s part of a snapshot: process
# -v t=PID and its descendants, depth first (children by pid), then its
# ancestors, nearest first:
#   proc PID PPID DEPTH USER CPU RSS_KIB CPUTIME_S AGE_S START ARGS
#   up PID ARGS
# Nothing when the snapshot does not have PID. Needs lib_proc.
NF >= 14 {
    p = $1 + 0
    if (p in pp) next
    pp[p] = $2 + 0; usr[p] = $4; cpu[p] = $5 + 0; rss[p] = $6 + 0
    ct[p] = secs($7); et[p] = secs($8); st[p] = lstart()
    av[p] = argv($0); gsub(/\t/, " ", av[p])
    nk[pp[p]]++; kid[pp[p], nk[pp[p]]] = p
}
function emit(p, d,   i, j, n, b, c) {
    printf "proc\t%d\t%d\t%d\t%s\t%.1f\t%d\t%d\t%d\t%s\t%s\n", p, pp[p], d, usr[p], cpu[p], rss[p], ct[p], et[p], st[p], av[p]
    if (d >= 32) return
    n = nk[p]
    for (i = 1; i <= n; i++) c[i] = kid[p, i]
    for (i = 1; i <= n; i++) { b = i; for (j = i + 1; j <= n; j++) if (c[j] < c[b]) b = j; j = c[i]; c[i] = c[b]; c[b] = j }
    for (i = 1; i <= n; i++) emit(c[i], d + 1)
}
END {
    t += 0
    if (!(t in pp)) exit
    emit(t, 0)
    q = pp[t]; d = 0
    while (q > 1 && (q in pp) && d++ < 64) { printf "up\t%d\t%s\n", q, av[q]; q = pp[q] }
}
