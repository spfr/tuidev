# lib/agents/awk/tokens_rollup.awk — _agents_tokens_prune: tokens.tsv
# (stdin; tokens.sh documents both shapes of its rows) rolled up into out.
# A message row before raw (local midnight yesterday) becomes part of its
# local day's row (off: the UTC offset): one per day and cli project session
# agent model poll origin, the tokens summed and calls counted, merged into
# the day rows already there. A day that ended by cut goes, whole. Day rows
# come first, oldest first, then the rows from raw on, as they were. A line
# in neither shape is kept from cut on, as history.tsv's are. Prints how
# many lines it read, so the caller can carry over any appended since.
# Needs lib_sort (sorti).

function dash(s) { return s == "" ? "-" : s }
function num(s) { return s ~ /^[0-9]+$/ }
# add(DAY, CALLS) — the current row into its day's sums.
function add(day, calls,   k, i) {
    if (day + 86400 <= cut + 0) return
    k = day SUBSEP dash($2) SUBSEP dash($3) SUBSEP dash($4) SUBSEP dash($5) SUBSEP dash($6) SUBSEP ($11 == "1" ? 1 : 0) SUBSEP (NF >= 13 ? dash($13) : "-")
    if (!(k in calls_)) { ko[++kn] = k; kd[kn] = day }
    calls_[k] += calls; tin[k] += $7; tcw[k] += $8; tcr[k] += $9; tout[k] += $10; tcw1[k] += (NF >= 12 && num($12)) ? $12 : 0
}
NF >= 11 && num($1) && num($7) && num($8) && num($9) && num($10) && (NF < 14 || num($14)) {
    if (NF >= 14) { add($1 + 0, $14 + 0); next }
    if ($1 + 0 < raw + 0) { add($1 - ($1 + off) % 86400, 1); next }
    keep[++rn] = $0; next
}
# Any other line is pruned as history.tsv's are: kept from cut on.
$1 + 0 >= cut + 0 { keep[++rn] = $0 }
END {
    # Oldest day first; a day's rows in the order first seen.
    for (i = 1; i <= kn; i++) ix[i] = i
    sorti(kd, ix, kn)
    printf "" > out
    for (i = 1; i <= kn; i++) {
        k = ko[ix[i]]; split(k, w, SUBSEP)
        print w[1], w[2], w[3], w[4], w[5], w[6], sprintf("%.0f", tin[k]), sprintf("%.0f", tcw[k]), sprintf("%.0f", tcr[k]), \
            sprintf("%.0f", tout[k]), w[7], sprintf("%.0f", tcw1[k]), w[8], sprintf("%.0f", calls_[k]) > out
    }
    for (i = 1; i <= rn; i++) print keep[i] > out
    close(out)
    print NR + 0
}
