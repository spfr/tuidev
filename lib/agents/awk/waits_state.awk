# lib/agents/awk/waits_state.awk — how long each live session has waited, and
# today's waits by class: what lets a view tell fresh from parked without
# reading all of waits.tsv on every refresh. Run by each `agents sample`
# (triage.sh documents the two files it rewrites). Needs lib_waits.
#
# Input: the enriched records (agent and hstate rows), then waits.tsv rows (this
# sample's; on the first run, every row there is, so sessions already parked are
# parked from the start and today's numbers come from the file alone).
# Variables: sf (waits.now), tf (waits.today), now, day, mid (local midnight),
# PARKED_S, first (no waits.now yet), gap (the seconds between rows that end a
# stretch on the first run, whose rows are all there is to go by), fresh (the
# age past which a record without Herdr's sequence number says nothing).

# stretches — before the rows: what changed since the last sample. Herdr numbers
# every state change, so a number that differs is a new stretch however briefly
# the session worked, and one that holds is the same stretch across a night
# asleep. Done to idle is you looking at it: it has sat since it finished. With
# no number to go by, a record too old to vouch for what happened since keeps
# only a lower bound ("~").
function stretches(   i, t, h, c) {
    if (seen++) return
    for (i = 1; i <= na; i++) {
        t = at[i]; h = ah[i]; c = (ap[i] in HQ) ? HQ[ap[i]] : ""
        if (!(t in WSt)) continue
        if (c != "" && WSq[t] ~ /^[0-9]+$/) {
            if (WSq[t] != c && !(h == "idle" && WSt[t] == "done")) { delete WSt[t]; delete WSi[t]; delete WLa[t]; WSq[t] = "-" }
        } else if (c == "" && WSt[t] == h && now - WLa[t] > fresh) {
            WSi[t] = now; WLa[t] = now; WSq[t] = "~"
        }
    }
}
BEGIN {
    FS = "\t"
    while ((getline ln < sf) > 0)
        if (split(ln, f, "\t") >= 4) { WSt[f[1]] = f[2]; WSi[f[1]] = f[3] + 0; WLa[f[1]] = f[4] + 0; WSq[f[1]] = f[5] == "" ? "-" : f[5] }
    close(sf)
    if (!first && (getline ln < tf) > 0 && split(ln, f, "\t") >= 4 && f[1] == day) { T["blocked"] = f[2] + 0; T["fresh"] = f[3] + 0; T["parked"] = f[4] + 0 }
    close(tf)
}
$1 == "hstate" { HQ[$2] = $3; next }
$1 == "agent" && NF >= 15 && $3 != "daemon" { ++na; at[na] = $2 "@" $9; ah[na] = $12; ap[na] = $2; next }
$1 ~ /^[0-9]+$/ && NF >= 6 {
    stretches()
    if ($4 != "blocked" && $4 != "done") next
    if (WSt[$5] != $4) WSq[$5] = "-"
    c = wait_row($5, $4, $1 + 0, $6 + 0, gap)
    if ($1 + 0 >= mid) T[c] += $6
    next
}
END {
    stretches()
    for (i = 1; i <= na; i++) {
        t = at[i]; h = ah[i]; q = (ap[i] in HQ) ? HQ[ap[i]] : ""
        if (h == "idle") {
            if (WSt[t] != "done" && WSt[t] != "idle") { WSi[t] = now; WSq[t] = "-" }
            WSt[t] = "idle"; WLa[t] = now
        } else if (h == "blocked" || h == "done") {
            if (WSt[t] != h) { WSi[t] = now; WSq[t] = "-" }
            WSt[t] = h; WLa[t] = now
        } else if (WLa[t] != now) continue     # working, or nothing known and no row now
        if (q != "") WSq[t] = q
        keep[++nk] = t
    }
    # A sample that sees no agent (a ps a sandbox limits) can't tell, so the file
    # stays; but the first one leaves a file, or the next would count the history
    # all over again.
    if (na || first) {
        out = sf ".new"
        printf "" > out
        for (i = 1; i <= nk; i++) print keep[i] "\t" WSt[keep[i]] "\t" WSi[keep[i]] "\t" WLa[keep[i]] "\t" (WSq[keep[i]] == "" ? "-" : WSq[keep[i]]) > out
        close(out)
    }
    out = tf ".new"
    print day "\t" (T["blocked"] + 0) "\t" (T["fresh"] + 0) "\t" (T["parked"] + 0) > out
    close(out)
}
