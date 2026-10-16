# lib/agents/awk/enrich.awk — agents_enrich: cwds, Herdr status, projects,
# dev-server confirmation, the order of agent rows and the activity flags
# (classify.sh documents the columns). Needs lib_proc (projname) and
# lib_activity.

function project(c,   i) {
    if (c == "" || index(c, home "/Library/") == 1) return 0
    for (i = 1; i <= nr; i++) if (roots[i] != "" && index(c, roots[i]) == 1) return 1
    return 0
}
function origin(c,   i, w) {
    if (c == "" || c == "-") return "-"
    i = index(c, "/.claude/worktrees/")
    if (i == 0) return "main"
    w = substr(c, i + 19); sub(/\/.*/, "", w); w = printable(w); return w == "" ? "-" : w
}
function rank(kind, status) {
    if (kind == "daemon") return 4
    if (status == "blocked") return 0
    if (status == "working") return 1
    if (status == "idle" || status == "done") return 2
    return 3
}
# htitle(s, kind): a Herdr pane's task title as the menu shows it: printable,
# spaces collapsed, "-" for none or for only the agent's own name.
function htitle(s, kind,   l) {
    s = printable(s); gsub(/  +/, " ", s); sub(/^ /, "", s); sub(/ $/, "", s)
    l = tolower(s)
    return (s == "" || l == "-" || l == kind || l == "claude code") ? "-" : s
}
# herdr_match(): which of Herdr's agents (1..nh) each agent row (1..na) is,
# in hm[] (0: none): the one in its pane (its HERDR_PANE_ID, when Herdr
# reports pane ids); else, for a row with no pane to go by, the only
# unclaimed agent of its kind in its directory, when it is also the only
# such row. Never the codex daemon.
function herdr_match(   i, f, k) {
    for (i = 1; i <= na; i++) {
        split(arow[i], f, "\t"); hm[i] = 0
        if (f[3] == "daemon") continue
        if ((f[2] in epane) && npane) {
            if (epane[f[2]] in byp) { hm[i] = byp[epane[f[2]]]; claimed[hm[i]] = 1 }
            continue
        }
        if (f[13] != "-") { pend[i] = 1; acnt[f[3], f[13]]++ }
    }
    for (i = 1; i <= nh; i++) if (!(i in claimed)) { hcnt[hk[i], hc[i]]++; hone[hk[i], hc[i]] = i }
    for (i = 1; i <= na; i++) {
        if (!(i in pend)) continue
        split(arow[i], f, "\t"); k = f[3] SUBSEP f[13]
        if (acnt[k] == 1 && hcnt[k] == 1) hm[i] = hone[k]
    }
}
END {
    herdr_match()
    for (i = 1; i <= na; i++) {
        $0 = arow[i]; p = ""
        if (hm[i]) { $12 = hst[hm[i]]; p = hpn[hm[i]]; arow[i] = $0 }
        if (p == "" || p == "-") p = ($2 in epane) ? epane[$2] : "-"
        ti = hm[i] ? hti[hm[i]] : "-"
        if (p != "-" || ti != "-") hrec[i] = "herdr" OFS $2 OFS p OFS ti
        ar[i] = rank($3, $12)
    }
    for (r = 0; r <= 4; r++) for (i = 1; i <= na; i++) if (ar[i] == r) print arow[i]
    for (i = 1; i <= na; i++) if (i in hrec) print hrec[i]
    longs = 60 * ENVIRON["AGENTS_TOOL_LONG"]; hot = ENVIRON["AGENTS_HOG_NOW"] + 0
    stuck = 60 * ENVIRON["AGENTS_WAIT_STUCK"]
    for (i = 1; i <= nx; i++) {
        split(xrow[i], f, "\t")
        if (f[3] != "tool" || waits(f[14])) continue
        same[f[11], f[13], f[14]]++
        if (f[13] != "-") here[f[13], f[14]]++
    }
    for (i = 1; i <= nx; i++) {
        $0 = xrow[i]; d = 1; fl = ""
        # A polling loop is stuck once it has run AGENTS_WAIT_STUCK minutes,
        # unless the file it watches changed within that time (a long
        # build's log: the producer is alive).
        if ($3 == "tool" && waits($14)) {
            fl = "wait"; w = ($2 in wst) ? wst[$2] : ""
            if (stuck > 0 && $4 >= stuck && w != "fresh") fl = fl ",stuck"
        }
        else if ($3 == "tool") {
            d = same[$11, $13, $14]; if ($13 != "-" && here[$13, $14] > d) d = here[$13, $14]
            if (d > 1) fl = "dup"
            if ($4 >= longs) fl = fl (fl == "" ? "" : ",") "long"
        }
        if ($5 >= hot) fl = fl (fl == "" ? "" : ",") "hot"
        $16 = (fl == "" ? "-" : fl); $17 = d
        print
    }
    for (i = 1; i <= no; i++) print orow[i]
}
BEGIN {
    home = ENVIRON["HOME"]
    nr = split(ENVIRON["AGENTS_CWD_ROOTS"], roots, "\n")
    n = split(ENVIRON["AGENTS_CWDS"], t, "\n")
    for (i = 1; i <= n; i++) if ((m = split(t[i], f, "\t")) >= 2 && (m == 2 || f[3] == "cwd")) cwd[f[1]] = f[2]
    # Herdr's agents: kind, status, cwd, and (newer caches) pane and title.
    n = split(ENVIRON["AGENTS_HERDR"], t, "\n")
    for (i = 1; i <= n; i++) {
        if ((m = split(t[i], f, "\t")) < 3) continue
        nh++; hk[nh] = f[1]; hst[nh] = f[2]; hc[nh] = f[3]
        hpn[nh] = (m >= 4 && f[4] ~ /^[A-Za-z0-9:_-]+$/) ? f[4] : "-"
        hti[nh] = (m >= 5) ? htitle(f[5], f[1]) : "-"
        if (hpn[nh] != "-" && !(hpn[nh] in byp)) { byp[hpn[nh]] = nh; npane++ }
    }
    n = split(ENVIRON["AGENTS_HPANES"], t, "\n")
    for (i = 1; i <= n; i++) if (split(t[i], f, "\t") >= 2 && f[2] ~ /^[A-Za-z0-9:_-]+$/) epane[f[1]] = f[2]
    n = split(ENVIRON["AGENTS_WATCHED"], t, "\n")
    for (i = 1; i <= n; i++) if (split(t[i], f, "\t") >= 2) wst[f[1]] = f[2]
}
NF < 14 { next }
$1 == "cand" {
    if (!project(cwd[$2])) { dropped[$2] = 1; next }
    $1 = "stale"
}
$1 == "job" && ($2 in dropped) { next }
($2 in cwd) { $13 = cwd[$2] }
{
    if ($1 == "act") {
        if ($3 == "tool" && $12 ~ /^\//) $13 = $12       # cd target: the real cwd
        $15 = origin($13); xrow[++nx] = $0; next
    }
    $15 = projname($13)
    if ($1 == "agent") arow[++na] = $0; else orow[++no] = $0
}
