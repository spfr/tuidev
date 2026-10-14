# lib/agents/awk/runs.awk — _agents_runs_update: the run ledger, from the
# previous runs.state and the observations on stdin (awk/runs_obs.awk: the
# menu's, oldest first, then this sample's, at epoch now). Writes sf.new and
# prints one line per run that has ended:
#   KEY START JOB PROJECT SESSION CMD LAST GONE CPU_S PEAK_RSS DUP ORIGIN OUT CLEANED STOPPED
# LAST: the last observation that saw it; GONE: the first one after that did
# not (now at the latest); CLEANED 1 when events.tsv (ef) holds a stop of its
# pid, or of its session's, between LAST - 5 and GONE + 10 s, the epoch of
# that stop in STOPPED (else "-"). CPU_S: the sum, over every process ever
# seen in the run, of the largest CPU time seen for it.
# runs.state (runs.sh documents it): run, proc and done lines.

function newrun(k, start, job, proj, sess, cmd, peak, dup, last, orig, out) {
    if (k in rs) return
    nr++; ro[nr] = k
    rs[k] = start; rj[k] = job; rp[k] = proj; rx[k] = sess; rc[k] = cmd
    rm[k] = peak + 0; rd[k] = dup + 0; rl[k] = last + 0; rg[k] = orig; rf[k] = out
}
function seen(k, e, pk) {
    if (e > rl[k]) rl[k] = e
    if (pk > rm[k]) rm[k] = pk
}
function proc(rk, pk, c,   x) {
    x = rk SUBSEP pk
    if (!(x in pc)) { np++; po[np] = x; pr[np] = rk; pp[np] = pk; pc[x] = c + 0 }
    else if (c + 0 > pc[x]) pc[x] = c + 0
}
function pidof(s) { sub(/@.*/, "", s); return s }
BEGIN {
    keep = 3600
    while ((getline line < sf) > 0) {
        n = split(line, f, "\t")
        if (f[1] == "run" && n >= 12) newrun(f[2], f[3], f[4], f[5], f[6], f[7], f[8], f[9], f[10], f[11], f[12])
        else if (f[1] == "proc" && n >= 4) proc(f[2], f[3], f[4])
        else if (f[1] == "done" && n >= 3 && f[3] + 0 >= now - keep) { if (!(f[2] in dn)) dk[++nd] = f[2]; dn[f[2]] = f[3] + 0 }
    }
    close(sf)
    while ((getline line < ef) > 0) {
        if (split(line, f, "\t") < 4 || f[1] + 0 < now - 86400) continue
        ev[f[4]] = ev[f[4]] " " f[1]
    }
    close(ef)
    ne = 0
}
($1 == "run" || $1 == "runp") && ($3 in dn) { next }
$1 == "run" && NF >= 12 {
    e = $2 + 0
    if (ne == 0 || e != ep[ne]) ep[++ne] = e
    newrun($3, $4, $5, $6, $7, $8, $9, $10, e, $11, $12)
    seen($3, e, $9 + 0)
    if ($10 == 1) rd[$3] = 1
    if (rf[$3] == "-") rf[$3] = $12
    if (rg[$3] == "-") rg[$3] = $11
    if (rp[$3] == "-") rp[$3] = $6
    if (rj[$3] == "-") rj[$3] = $5
    if (e == now) alive[$3] = 1
}
$1 == "runp" && NF >= 5 { proc($3, $4, $5) }
END {
    out = sf ".new"
    printf "" > out          # written even when no run is alive: the caller moves it in place
    for (i = 1; i <= np; i++) cpu[pr[i]] += pc[po[i]]
    for (i = 1; i <= nr; i++) {
        k = ro[i]
        line = k "\t" rs[k] "\t" rj[k] "\t" rp[k] "\t" rx[k] "\t" rc[k] "\t" rm[k] "\t" rd[k] "\t" rl[k] "\t" rg[k] "\t" rf[k]
        if (k in alive) { print "run\t" line > out; continue }
        gone = now
        for (j = 1; j <= ne; j++) if (ep[j] > rl[k]) { gone = ep[j]; break }
        stop = "-"
        s = rx[k]; sub(/^[a-z]+:/, "", s)
        nn = split(ev[pidof(k)] (s ~ /^[0-9]+$/ ? ev[s] : ""), t, " ")
        for (j = 1; j <= nn; j++) if (t[j] + 0 >= rl[k] - 5 && t[j] + 0 <= gone + 10 && (stop == "-" || t[j] + 0 < stop)) stop = t[j] + 0
        printf "%s\t%s\t%s\t%d\t%d\t%d\t%s\t%s\t%d\t%s\n", k "\t" rs[k] "\t" rj[k] "\t" rp[k] "\t" rx[k] "\t" rc[k], rl[k], gone, cpu[k], rm[k], rd[k], rg[k], rf[k], (stop == "-" ? 0 : 1), stop
        dn[k] = now; dk[++nd] = k
    }
    for (i = 1; i <= np; i++) if (pr[i] in alive) print "proc\t" pr[i] "\t" pp[i] "\t" pc[po[i]] > out
    for (i = 1; i <= nd; i++) if (!(dk[i] in printed)) { printed[dk[i]] = 1; print "done\t" dk[i] "\t" dn[dk[i]] > out }
    close(out)
}
