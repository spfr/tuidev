# lib/agents/awk/lib_fmt.awk — numbers and cells for people, shared by the
# views:
#   age(s)    seconds as 42s, 7m, 3h05m, 2d04h;
#   dur(s)    a duration, rounded: 42s, 7m03s under an hour, else as age;
#   rough(s)  a long stretch at a glance: 12 m, 39 h, 3 d;
#   mem(k)    KiB as 900K, 512M, 1.2G;
#   cut(s,n)  s in at most n characters, "..." marking a cut ("" below 8);
#   dw(s), lc(s,w), rc(s,w), dcut(s,n)  width on screen, and cells by it;
#   gauge(...) a bar of block glyphs, with a marker;
#   gl(n)     a state's shape or a small mark, in what the locale can show;
#   dayhm(e)  epoch e as "Oct 14 18:42", at UTC offset off.
#
# Every awk here runs under LC_ALL=C, where length() and printf's %-Ns count
# bytes: a glyph is three of them. So a cell is padded by dw, before any color
# goes in, never with a printf width.

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
# rough(s): minutes, hours past two (or on the hour), days past three.
function rough(s) {
    if (s % 3600 == 0 && s >= 3600 && s < 259200) return (s / 3600) " h"
    if (s < 7200) return int(s / 60 + 0.5) " m"
    return s < 259200 ? int(s / 3600 + 0.5) " h" : int(s / 86400 + 0.5) " d"
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
# dcut: S in at most N columns, an ellipsis marking a cut, never inside a glyph.
function dcut(s, n,   i, l, c, w) {
    if (dw(s) <= n) return s
    if (n < 1) return ""
    l = length(s); w = 0
    for (i = 1; i <= l; i++) {
        c = substr(s, i, 1)
        if ((c < "\200" || c >= "\300") && ++w > n - 1) break
    }
    return substr(s, 1, i - 1) gl("more")
}
# gl NAME — a state's shape or a small mark. Under a locale with no such glyphs
# (AGENTS_ASCII) the states keep a shape each, so they still read apart.
function gl(n) {
    if (ENVIRON["AGENTS_ASCII"] != "")
        return n == "need" ? "^" : n == "review" ? "*" : n == "run" ? "o" : n == "parked" ? "." : n == "unknown" ? "?" : \
            n == "dot" ? "-" : n == "more" ? "~" : n == "mark" ? "|" : n == "full" ? "#" : n == "half" ? "+" : n == "light" ? "-" : n == "none" ? "." : n
    return n == "need" ? "\342\226\262" : n == "review" ? "\342\227\206" : n == "run" ? "\342\227\217" : n == "parked" ? "\342\227\213" : n == "unknown" ? "?" : \
        n == "dot" ? "\302\267" : n == "more" ? "\342\200\246" : n == "mark" ? "\342\224\202" : n == "full" ? "\342\226\210" : n == "half" ? "\342\226\222" : \
        n == "light" ? "\342\226\221" : n == "none" ? "\302\267" : n
}
# gauge P CELLS MARK CF CD CM — P percent of CELLS cells in block glyphs, to the
# eighth of a cell, with a marker drawn between the cells at MARK percent (-1:
# none; one column more). CF, CD and CM color the fill, the rest and the marker;
# the reset is ENVIRON["N"]. "#", "-" and "|" where the locale has no blocks
# (AGENTS_ASCII).
function gauge(p, cells, mark, cf, cd, cm,   ascii, eighths, full, frac, m, i, o, cur, c, g) {
    ascii = ENVIRON["AGENTS_ASCII"] != ""
    if (p < 0) p = 0
    if (p > 100) p = 100
    eighths = int(p * cells * 8 / 100 + 0.5)
    if (ascii) eighths = int((eighths + 4) / 8) * 8
    full = int(eighths / 8); frac = eighths % 8
    m = mark < 0 ? -1 : int(mark * cells / 100 + 0.5)
    o = ""; cur = ""
    for (i = 0; i <= cells; i++) {
        if (i == m) {
            if (cur != cm) { o = o cm; cur = cm }
            o = o gl("mark")
        }
        if (i == cells) break
        if (i < full) { c = cf; g = gl("full") }
        else if (i == full && frac) { c = cf; g = substr("\342\226\217\342\226\216\342\226\215\342\226\214\342\226\213\342\226\212\342\226\211", (frac - 1) * 3 + 1, 3) }
        else { c = cd; g = gl("light") }
        if (cur != c) { o = o c; cur = c }
        o = o g
    }
    return o ((cf cd cm) == "" ? "" : ENVIRON["N"])
}
