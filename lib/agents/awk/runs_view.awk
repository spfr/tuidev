# lib/agents/awk/runs_view.awk — agents_runs: the runs that ended between
# start and now, from runs.tsv lines sorted newest first (runs.sh documents
# the columns): a table, or JSON with json=1. Needs lib_fmt and lib_json.

# when(e): "Oct 14 18:42" for epoch e, at UTC offset off (days from the
# civil calendar: Howard Hinnant's days_from_civil, inverted).
function when(e,   z, era, doe, yoe, doy, mp, d, m, s) {
    e += off; s = e % 86400; z = int(e / 86400) + 719468
    era = int(z / 146097); doe = z - era * 146097
    yoe = int((doe - int(doe / 1460) + int(doe / 36524) - int(doe / 146096)) / 365)
    doy = doe - (365 * yoe + int(yoe / 4) - int(yoe / 100))
    mp = int((5 * doy + 2) / 153); d = doy - int((153 * mp + 2) / 5) + 1
    m = mp < 10 ? mp + 3 : mp - 9
    return sprintf("%s %2d %02d:%02d", mon[m], d, int(s / 3600), int((s % 3600) / 60))
}
function took(s) { return s < 60 ? s "s" : dur(s) }
function num(s) { return s ~ /^-?[0-9]+$/ ? s + 0 : "null" }
function flags(dup, cl,   o) { o = (dup == 1 ? "dup" : ""); if (cl == 1) o = o (o == "" ? "" : ",") "cleaned"; return o == "" ? "-" : o }
function cell(i, c, v) { cv[i, c] = v; if (length(v) > w[c]) w[c] = length(v) }
BEGIN {
    split("Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec", mon, " ")
    split("ENDED TOOK CPU PEAK EXIT PROJECT SESSION AGENT CMD JOB FLAGS", hd, " ")
    nc = 11; for (c = 1; c <= nc; c++) w[c] = length(hd[c])
    B = ENVIRON["B"]; DIM = ENVIRON["DIM"]; R = ENVIRON["R"]; N = ENVIRON["N"]
    win = (label == "today" ? "today" : "in the last " label)
}
NF >= 13 && $1 ~ /^[0-9]+$/ {
    if ($1 + 0 < start) exit                 # sorted newest first: the rest is older
    if ($1 + 0 > now + 60) next
    n++; row[n] = $0; cpu += $9; if ($13 == 1) ncl++
}
END {
    if (json) {
        printf "{\"schema_version\":1,\"since\":%d,\"until\":%d,\"window\":%s,\"history\":%s,\"runs\":[", start, now, js(label), (hist == 1 ? "true" : "false")
        for (i = 1; i <= n; i++) {
            split(row[i], f, "\t")
            printf "%s{\"end\":%d,\"start\":%d,\"job\":%s,\"project\":%s,\"session\":%s,\"agent\":%s,\"cmd\":%s,\"duration_s\":%d,\"cpu_s\":%d,\"peak_rss_kib\":%d,\"exit\":%s,\"dup\":%s,\"cleaned\":%s}",
                (i > 1 ? "," : ""), f[1], f[2], opt(f[3]), opt(f[4]), opt(f[5]), opt(f[6]), opt(f[7]), f[8], f[9], f[10], num(f[11]),
                (f[12] == 1 ? "true" : "false"), (f[13] == 1 ? "true" : "false")
        }
        print "]}"
        exit
    }
    if (n == 0) {
        if (!have && hist != 1) print "history is off (AGENTS_HISTORY=0): no runs are recorded"
        else if (!have) print "no runs recorded yet: they start within a minute or two of the menu running (or a cron'd agents sample)"
        else printf "no runs ended %s\n", win
        exit
    }
    printf "%sRuns ended %s: %d · %s CPU%s · newest first%s\n\n", B, win, n, took(int(cpu)),
        (ncl > 0 ? " · " ncl " stopped by agents" : ""), N
    for (i = 1; i <= n; i++) {
        split(row[i], f, "\t")
        cell(i, 1, when(f[1])); cell(i, 2, took(f[8])); cell(i, 3, took(f[9])); cell(i, 4, mem(f[10])); cell(i, 5, f[11])
        cell(i, 6, cut(f[4], 32)); cell(i, 7, f[5]); cell(i, 8, cut(f[6], 24)); cell(i, 9, f[7]); cell(i, 10, f[3]); cell(i, 11, flags(f[12], f[13]))
        bad[i] = (f[11] ~ /^-?[0-9]+$/ && f[11] != 0)
    }
    # Numbers (TOOK to EXIT) right-aligned, words left-aligned.
    for (c = 1; c <= nc; c++) fmt[c] = "%" ((c >= 2 && c <= 5) ? "" : "-") w[c] "s"
    line = ""
    for (c = 1; c <= nc; c++) line = line sprintf(fmt[c], hd[c]) (c < nc ? "  " : "")
    sub(/ +$/, "", line); print DIM line N
    for (i = 1; i <= n; i++) {
        line = ""
        for (c = 1; c <= nc; c++) {
            v = sprintf(fmt[c], cv[i, c])
            if (c == 5 && bad[i]) v = R v N
            line = line v (c < nc ? "  " : "")
        }
        sub(/ +$/, "", line); print line
    }
}
