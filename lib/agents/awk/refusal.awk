# lib/agents/awk/refusal.awk — agents_refusal: why pid t must not be
# signalled, or nothing. Needs lib_proc.

NF >= 14 { p = $1 + 0; pp[p] = $2 + 0; uid[p] = $3; usr[p] = $4; av[p] = argv($0); ord[++n] = p }
END {
    ancestors(self)
    if ((t + 0) in anc) { print "this shell or one of its parents"; exit }
    if (!(t in pp)) { print "no such process"; exit }
    if (critical(av[t])) { print "a system or session process (" pname(av[t]) "): quit it yourself if you mean it"; exit }
    # A terminal, editor or multiplexer hosting shells or agents (Warp,
    # VS Code, tmux…). An agent root itself may be killed with its tree.
    if (agent_kind(av[t]) == "" && av[t] !~ ENVIRON["AGENTS_DAEMON_PATTERN"]) {
        for (k = 1; k <= n; k++) {
            p = ord[k]; if (p == t || !hosts(av[p])) continue
            q = pp[p]; d = 0
            while (q > 1 && (q in pp) && d++ < 64) { if (q == t) { print "it hosts a session (" pname(av[p]) ", pid " p "): close that first"; exit } q = pp[q] }
        }
    }
    if (uid[t] != ENVIRON["AGENTS_UID"]) print "owned by " usr[t] ": run `sudo kill " t "` yourself if you mean it"
}
