# lib/agents/awk/sample.awk — _agents_sample_rows: one history sample from
# enriched records and jp lines, against the previous sample.state
# (history.sh documents the files). Needs lib_sort.

BEGIN {
    last = 0; n = 0
    while ((getline line < sf) > 0) {
        if (n++ == 0) { last = line + 0; continue }
        if (split(line, f, "\t") >= 2) { prev[f[1]] = f[2] + 0; if (f[3] == 1) seen[f[1]] = 1 }
    }
    close(sf)
    tday = ""; ttot = 0
    while ((getline line < tf) > 0) {
        split(line, f, "\t")
        if (tday == "") { tday = f[1]; ttot = f[2] + 0 } else tj[f[1]] = f[2] + 0
    }
    close(tf)
    if (tday != day) { ttot = 0; split("", tj) }
}
($1 == "agent" || $1 == "stale") && NF >= 15 { proj[$2] = $15; sess[$2] = ($1 == "stale" ? "-" : ($3 == "daemon" ? "codex" : $3)) }
$1 == "jp" && NF >= 8 { np++; jk[np] = $2 "@" $3; jr[np] = $4; jj[np] = $5; jc[np] = $6 + 0; jm[np] = $7 + 0; ja[np] = $8 + 0 }
END {
    out = sf ".new"; print now > out
    for (i = 1; i <= np; i++) {
        k = jk[i]; c = jc[i]; r = jr[i]
        print k "\t" c "\t" ((k in seen) || ((r in sess) && sess[r] != "-") ? 1 : 0) > out
        if (k in prev) d = c - prev[k]
        else if (last > 0 && ja[i] <= now - last) d = c
        else d = 0
        if (d < 0) d = 0
        r = jr[i]; g = jj[i] SUBSEP (r in proj ? proj[r] : "-") SUBSEP (r in sess ? sess[r] : "-")
        if (!(g in gc)) go[++ng] = g
        gc[g] += d; gm[g] += jm[i]; gn[g]++
    }
    close(out)
    for (i = 1; i <= ng; i++) {
        g = go[i]
        if (gc[g] <= 0) continue
        split(g, f, SUBSEP)
        printf "%d\t%s\t%s\t%s\t%d\t%d\t%d\n", now, f[1], f[2], f[3], gc[g], gm[g], gn[g]
        if (!(f[1] in tj)) tj[f[1]] = 0
        tj[f[1]] += gc[g]; ttot += gc[g]
    }
    nj = 0
    for (j in tj) jo[++nj] = j
    sortk(tj, jo, nj)
    out = tf ".new"
    printf "%s\t%d\n", day, ttot > out
    for (i = 1; i <= nj; i++) printf "%s\t%d\n", jo[i], tj[jo[i]] > out
    close(out)
}
