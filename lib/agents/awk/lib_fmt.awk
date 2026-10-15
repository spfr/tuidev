# lib/agents/awk/lib_fmt.awk — numbers for people, shared by render.awk,
# runs_view.awk and report.awk:
#   age(s)   seconds as 42s, 7m, 3h05m, 2d04h;
#   dur(s)   a duration, rounded: 42s, 7m03s under an hour, else as age;
#   mem(k)   KiB as 900K, 512M, 1.2G;
#   cut(s,n) s in at most n characters, "..." marking a cut ("" below 8);
#   dayhm(e) epoch e as "Oct 14 18:42", at UTC offset off.

function age(s) {
    if (s < 60) return s "s"
    if (s < 3600) return int(s / 60) "m"
    if (s < 86400) return sprintf("%dh%02dm", s / 3600, (s % 3600) / 60)
    return sprintf("%dd%02dh", s / 86400, (s % 86400) / 3600)
}
function dur(s) { s = int(s + 0.5); return s < 60 ? s "s" : s < 3600 ? sprintf("%dm%02ds", s / 60, s % 60) : age(s) }
# dayhm(e): days from the civil calendar (Howard Hinnant's days_from_civil,
# inverted).
function dayhm(e,   z, era, doe, yoe, doy, mp, d, m, s) {
    e += off; s = e % 86400; z = int(e / 86400) + 719468
    era = int(z / 146097); doe = z - era * 146097
    yoe = int((doe - int(doe / 1460) + int(doe / 36524) - int(doe / 146096)) / 365)
    doy = doe - (365 * yoe + int(yoe / 4) - int(yoe / 100))
    mp = int((5 * doy + 2) / 153); d = doy - int((153 * mp + 2) / 5) + 1
    m = mp < 10 ? mp + 3 : mp - 9
    return sprintf("%s %2d %02d:%02d", substr("JanFebMarAprMayJunJulAugSepOctNovDec", m * 3 - 2, 3), d, int(s / 3600), int((s % 3600) / 60))
}
function mem(k) { return k >= 1048576 ? sprintf("%.1fG", k / 1048576) : k >= 1024 ? sprintf("%dM", k / 1024) : k "K" }
function cut(s, n) { return n < 8 ? "" : length(s) > n ? substr(s, 1, n - 3) "..." : s }
