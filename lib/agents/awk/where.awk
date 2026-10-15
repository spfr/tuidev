# lib/agents/awk/where.awk — agents_where, from a snapshot on stdin: for
# process -v t=PID one line
#   HOW PLACE ROOT KIND
# (lib_where.awk's where_of; ROOT: the agent session it is or runs under, KIND
# its agent kind, "-" for none), then a "client PID APP" line for every Herdr
# client a terminal app runs (where a Herdr pane is seen). Nothing when the
# snapshot does not have PID. Needs lib_proc and lib_where.
NF >= 14 { p = $1 + 0; pp[p] = $2 + 0; av[p] = argv($0); ord[++n] = p }
END {
    t += 0
    if (!(t in pp)) exit
    q = t; d = 0; root = "-"; kind = "-"
    while (q > 1 && (q in pp) && d++ < 64) { if ((k = agent_kind(av[q])) != "") { root = q; kind = k } q = pp[q] }
    print where_of(t) "\t" root "\t" kind
    for (i = 1; i <= n; i++) {
        p = ord[i]
        if (base(av[p]) != "herdr") continue
        split(where_of(p), w, "\t")
        if (w[1] == "herdr" && w[2] != "-") print "client\t" p "\t" w[2]
    }
}
