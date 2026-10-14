# lib/agents/awk/report_fmt.awk — numbers, words and table cells for
# `agents report`. Part of report.awk's program; needs lib_json.

# h: CPU seconds in the unit of the summary (CPU-h, or CPU-min below an hour in all).
function h(s) { return sprintf("%.2f", s / unit) }
# ch: CPU seconds as CPU-h, for the tables of the other views.
function ch(s) { return sprintf("%.2f", s / 3600) }
function pc1(a, b) { return sprintf("%.1f", b > 0 ? 100 * a / b : 0) }
function pct(a, b) { return sprintf("%d%%", b > 0 ? 100 * a / b + 0.5 : 0) }
# pctn: a share, or "-" when there is nothing to take it of (no exit codes).
function pctn(a, b) { return b > 0 ? pct(a, b) : "-" }
function bar(p,   k, o) { k = int(p / 5 + 0.5); o = ""; while (k-- > 0) o = o "\342\226\210"; return o }
function sess(s) { return s == "-" ? "stale" : s }
function proj(s) { return s == "-" ? "(none)" : s }
function agentn(s) { return s == "-" ? "(unknown)" : s }
# who: an agent type as the subject of a sentence.
function who(s) { return s == "-" ? "Sessions of unknown type" : s == "main" ? "Main sessions" : s " subagents" }
# cpuw: CPU seconds in words, in the unit that reads best.
function cpuw(s) {
    if (s >= 3600) return sprintf("%.1f CPU-h", s / 3600)
    return s >= 30 ? sprintf("%d CPU-min", s / 60 + 0.5) : "<1 CPU-min"
}
# nouns: S, plural unless N is 1; nruns: "1 run", "3 runs".
function nouns(n, s) { return n == 1 ? s : s "s" }
function nruns(n) { return n " " nouns(n, "run") }
# hrs: wall-clock seconds as hours.
function hrs(s) { return sprintf("%.1f h", s / 3600) }
# dur: a duration: 42s 6m30s 12m 1h05m.
function dur(s,   m) {
    s = int(s + 0.5)
    if (s < 60) return s "s"
    if (s < 600) { m = int(s / 60); return (s % 60) ? sprintf("%dm%02ds", m, s % 60) : m "m" }
    if (s < 3600) return int(s / 60) "m"
    return sprintf("%dh%02dm", int(s / 3600), int((s % 3600) / 60))
}
# chg CUR PREV — the change: ↑85% ↓12% 0%; "new" from nothing, "-" for neither.
function chg(c, p,   r) {
    if (p <= 0) return c > 0 ? "new" : "-"
    r = int((c > p ? c - p : p - c) * 100 / p + 0.5)
    if (!r) return "0%"
    return (c > p ? "\342\206\221" : "\342\206\223") r "%"
}
# dw: display width in a UTF-8 terminal (continuation bytes take no column).
function dw(s,   i, n, c, w) {
    n = length(s); w = 0
    for (i = 1; i <= n; i++) { c = substr(s, i, 1); if (c < "\200" || c >= "\300") w++ }
    return w
}
# lc / rc: S left- or right-aligned in W columns.
function lc(s, w,   k) { k = w - dw(s); while (k-- > 0) s = s " "; return s }
function rc(s, w,   k, o) { k = w - dw(s); o = ""; while (k-- > 0) o = o " "; return o s }
# cut: at most W bytes, "..." marking a cut.
function cut(s, w) { return length(s) > w ? substr(s, 1, w - 3) "..." : s }
# line KEYS N ARR FMT LIM — "a 1.00 · b 0.50" (FMT "h": CPU-h, else counts).
function line(keys, cnt, arr, fmt, lim,   i, o) {
    o = ""
    for (i = 1; i <= cnt && i <= lim; i++) o = o (i > 1 ? " \302\267 " : "") keys[i] " " (fmt == "h" ? h(arr[keys[i]]) : arr[keys[i]])
    return o
}
function jlist(keys, cnt, arr, name, val,   i, o) {
    o = ""
    for (i = 1; i <= cnt; i++) o = o (i > 1 ? "," : "") sprintf("{\"%s\":%s,\"%s\":%d}", name, opt(keys[i]), val, arr[keys[i]])
    return "[" o "]"
}
# jn: a JSON number, rounded to a whole one; jb: a JSON boolean.
function jn(x) { return sprintf("%d", x + 0.5) }
function jb(x) { return x ? "true" : "false" }
