# lib/agents/awk/statusline.awk — `agents statusline`: Claude Code's status
# line JSON (stdin) read for the few fields it needs, and its limits
# compared with what limits.tsv holds (statusline.sh documents both).
#
# Variables: lf (limits.tsv), hist (AGENTS_HISTORY), now (empty: the clock,
# read here rather than by a fork of date).
# Prints the default status line, "Opus 5.5 · ctx 42% · 5h 23% · wk 41%"
# (whole percents; a field absent or null is left out), then a limits.tsv
# row for each window that changed, or was read 5 minutes ago or more (none
# with hist other than 1):
#   NOW claude USED WINDOW RESETS -
# Reads at most a MiB of JSON.
#
# JSON is not parsed whole: an object is found by its key, followed by
# its braces (strings skipped, so a brace in a value never ends it), and
# a number or string by its key inside it. A key can't be forged from a
# string value: inside one, a quote is escaped (\"), and "key" never
# matches there.

# obj S K — the object that key K holds in S ("{...}"), the first one; "".
function obj(s, k,   i, j, n, d, c, q) {
    if (!match(s, "\"" k "\"[ \t\r\n]*:[ \t\r\n]*[{]")) return ""
    i = RSTART + RLENGTH - 1; n = length(s); d = 0; q = 0
    for (j = i; j <= n; j++) {
        c = substr(s, j, 1)
        if (q) { if (c == "\\") j++; else if (c == "\"") q = 0; continue }
        if (c == "\"") q = 1
        else if (c == "{") d++
        else if (c == "}" && --d == 0) return substr(s, i, j - i + 1)
    }
    return ""
}
# num S K — the number key K holds in S, as text; "" when it has none
# (absent, null or not a number).
function num(s, k,   t) {
    if (!match(s, "\"" k "\"[ \t\r\n]*:[ \t\r\n]*-?[0-9]+([.][0-9]+)?([eE][-+]?[0-9]+)?")) return ""
    t = substr(s, RSTART, RLENGTH); sub(/^[^:]*:[ \t\r\n]*/, "", t)
    return t
}
# str S K — the string key K holds in S, unescaped, printable, at most 40
# characters; "".
function str(s, k,   t, o, i, c, n) {
    if (!match(s, "\"" k "\"[ \t\r\n]*:[ \t\r\n]*\"([^\"\\\\]|\\\\.)*\"")) return ""
    t = substr(s, RSTART, RLENGTH); sub(/^[^:]*:[ \t\r\n]*"/, "", t); t = substr(t, 1, length(t) - 1)
    o = ""; n = length(t)
    for (i = 1; i <= n; i++) {
        c = substr(t, i, 1)
        if (c == "\\") { i++; c = substr(t, i, 1); if (c == "u") { i += 4; continue } if (c == "n" || c == "t" || c == "r") c = " " }
        if (c ~ /[[:cntrl:]]/) continue
        o = o c
    }
    sub(/^ +/, "", o); sub(/ +$/, "", o)
    return substr(o, 1, 40)
}
function whole(p) { return p == "" ? "-" : int(p + 0.5) }
# window W OBJ — this reading of window W (minutes) from its object: a row
# when it differs from limits.tsv's, or that one is 5 minutes old.
function window(w, o,   p, r) {
    p = num(o, "used_percentage"); r = num(o, "resets_at")
    if (p == "" || p + 0 < 0) return ""
    if (r == "" || r + 0 < 0) r = 0
    p = p + 0; r = sprintf("%.0f", r)
    if ((w in old) && old[w] == p "\t" r && now - oldt[w] < 300) return ""
    rows = rows now "\tclaude\t" p "\t" w "\t" r "\t-\n"
    return p
}
length(s) < 1048576 { s = s $0 "\n" }
END {
    # srand() returns the seed before it, which the first call set to the clock.
    if (now !~ /^[0-9]+$/) { srand(); now = srand() }
    if (hist == 1) {
        while ((getline ln < lf) > 0)
            if (split(ln, f, "\t") >= 5 && f[2] == "claude" && f[1] ~ /^[0-9]+$/) { old[f[4]] = (f[3] + 0) "\t" f[5]; oldt[f[4]] = f[1] + 0 }
        close(lf)
    }
    rl = obj(s, "rate_limits")
    p5 = num(obj(rl, "five_hour"), "used_percentage"); p7 = num(obj(rl, "seven_day"), "used_percentage")
    rows = ""
    if (rl != "") { window(300, obj(rl, "five_hour")); window(10080, obj(rl, "seven_day")) }
    o = str(obj(s, "model"), "display_name")
    gsub(/\t/, " ", o)
    o = part(o, "ctx ", whole(num(obj(s, "context_window"), "used_percentage")))
    o = part(part(o, "5h ", whole(p5)), "wk ", whole(p7))
    print o
    if (hist == 1) printf "%s", rows
}
# part LINE WHAT PCT — LINE, then " · WHAT PCT%" when PCT is one.
function part(l, w, p) {
    if (p == "-") return l
    return l (l == "" ? "" : " \302\267 ") w p "%"
}
