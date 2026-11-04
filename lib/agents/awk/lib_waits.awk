# lib/agents/awk/lib_waits.awk — stretches of waiting, shared by the sample's
# waits.now (waits_state.awk) and the waits report (report_waits.awk), so a
# session is parked in one the moment it is in the other.
#
# A session waits in stretches: rows of waits.tsv one sample apart, of one
# status. Most of the time sessions sit finished is in stretches past an hour,
# and summing it all makes a number larger than the day, so a done row counts
# as fresh for a stretch's first PARKED_S seconds and as parked from then on.

# wait_row TOKEN STATUS EPOCH SECS GAP — one row of waits.tsv: extends TOKEN's
# stretch, or starts one when its status changed or the last row is over GAP
# seconds old, in WSt[TOKEN] (status), WSi (its start), WLa (its last row).
# Returns the row's class: blocked, fresh or parked.
function wait_row(t, st, ep, secs, gap) {
    if (WSt[t] != st || ep - WLa[t] > gap) WSi[t] = ep - secs
    WSt[t] = st; WLa[t] = ep
    if (st == "blocked") return "blocked"
    return ep - WSi[t] >= PARKED_S ? "parked" : "fresh"
}
