# lib/agents/awk/lib_fmt.awk — numbers for people, shared by render.awk,
# runs_view.awk and report.awk:
#   age(s)   seconds as 42s, 7m, 3h05m, 2d04h;
#   dur(s)   a duration, rounded: 42s, 7m03s under an hour, else as age;
#   mem(k)   KiB as 900K, 512M, 1.2G;
#   cut(s,n) s in at most n characters, "..." marking a cut ("" below 8).

function age(s) {
    if (s < 60) return s "s"
    if (s < 3600) return int(s / 60) "m"
    if (s < 86400) return sprintf("%dh%02dm", s / 3600, (s % 3600) / 60)
    return sprintf("%dd%02dh", s / 86400, (s % 86400) / 3600)
}
function dur(s) { s = int(s + 0.5); return s < 60 ? s "s" : s < 3600 ? sprintf("%dm%02ds", s / 60, s % 60) : age(s) }
function mem(k) { return k >= 1048576 ? sprintf("%.1fG", k / 1048576) : k >= 1024 ? sprintf("%dM", k / 1024) : k "K" }
function cut(s, n) { return n < 8 ? "" : length(s) > n ? substr(s, 1, n - 3) "..." : s }
