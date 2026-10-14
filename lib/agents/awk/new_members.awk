# lib/agents/awk/new_members.awk — _agents_new_members: processes that joined
# a targeted tree after the kill plan was made. Needs lib_proc.

BEGIN {
    n = split(ENVIRON["AGENTS_ROOTS"], r, "\n"); for (i = 1; i <= n; i++) if (split(r[i], f, "\t") >= 2) want[f[1] + 0] = f[2]
    n = split(ENVIRON["AGENTS_PLAN"], r, "\n"); for (i = 1; i <= n; i++) if (split(r[i], f, "\t") >= 1) have[f[1] + 0] = 1
}
NF >= 14 {
    p = $1 + 0; pp[p] = $2 + 0; uid[p] = $3; st[p] = lstart()
    s = argv($0); nm[p] = pname(s); cr[p] = critical(s); kids[pp[p]] = kids[pp[p]] " " p
}
END {
    for (r0 in want) {
        if (!(r0 in pp) || st[r0] != want[r0]) continue
        h = 1; n = 1; q[1] = r0 + 0
        while (h <= n) {
            p = q[h++]; m = split(kids[p], c, " ")
            for (i = 1; i <= m; i++) {
                x = c[i] + 0; q[++n] = x
                if (!have[x] && uid[x] == me && !cr[x] && x != self + 0 && !seen[x]++) print x "\t" st[x] "\t" nm[x]
            }
        }
    }
}
