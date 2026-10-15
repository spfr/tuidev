# lib/agents/awk/tokens_session.awk — agents_session_tokens: what each
# session in ids (space-separated) cost so far, from the tokens.tsv rows on
# stdin (message and day rows: tokens.sh). One line per session with tokens,
# in the order of ids:
#   session origin cli project model calls tokens usd unpriced
# usd: the cost of its priced rows ("-" when none is, or prices are off);
# unpriced: the tokens of rows no price names ("-" when prices are off).
# Its origin, CLI, project and model are those with the most of its tokens
# (the origin and model of its main conversation; ties: the first by name),
# so the rows' order, and the daily rollup, change none of them. Needs
# lib_price (pfs: the price files) and report_fmt (pfold), which needs
# lib_json and lib_fmt.

# pick ARR OUT — OUT[session]: of ARR[session, name], the name with the most.
function pick(arr, out,   k, w, bv) {
    for (k in arr) {
        split(k, w, SUBSEP)
        if (!(w[1] in bv) || arr[k] > bv[w[1]] || (arr[k] == bv[w[1]] && w[2] < out[w[1]])) { out[w[1]] = w[2]; bv[w[1]] = arr[k] }
    }
}
BEGIN {
    n = split(ids, w, " "); for (i = 1; i <= n; i++) want[w[i]] = i
    prices_load(pfs)
}
NF >= 11 && ($4 in want) && $1 ~ /^[0-9]+$/ && $7 ~ /^[0-9]+$/ && $8 ~ /^[0-9]+$/ && $9 ~ /^[0-9]+$/ && $10 ~ /^[0-9]+$/ {
    s = $4; t = $7 + $8 + $9 + $10
    calls[s] += NF >= 14 ? $14 + 0 : 1; tok[s] += t
    ct[s, $2] += t; pt[s, pfold($3)] += t; at[s, $6] += t
    if ($5 == "main") { mt[s, $6] += t; if (NF >= 13 && $13 != "" && $13 != "-") ot[s, $13] += t }
    if (PRICED && (p = price_of($6))) cost[s] += usd_of(p, $7, $8, NF >= 12 ? $12 + 0 : 0, $9, $10)
    else if (PRICED) unp[s] += t
}
END {
    pick(ct, cli); pick(pt, pj); pick(at, anym); pick(mt, mainm); pick(ot, org)
    for (i = 1; i <= n; i++) {
        s = w[i]
        if (!(s in calls) || (s in done)) continue
        done[s] = 1
        printf "%s\t%s\t%s\t%s\t%s\t%d\t%.0f\t%s\t%s\n", s, ((s in org) ? org[s] : "-"), cli[s], pj[s], ((s in mainm) ? mainm[s] : anym[s]), \
            calls[s], tok[s], (PRICED && (s in cost) ? sprintf("%.2f", cost[s]) : "-"), (PRICED ? sprintf("%.0f", unp[s]) : "-")
    }
}
