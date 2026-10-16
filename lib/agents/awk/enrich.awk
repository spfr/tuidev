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
# hkind(s): Herdr's name for an agent's CLI as ours (agent_kind): lowercase,
# with the names Herdr gives Cursor's and Antigravity's CLIs mapped to their
# commands'; "-" for none.
function hkind(s) {
    s = tolower(s)
    if (s == "cursor") return "cursor-agent"
    if (s == "antigravity") return "agy"
    if (s == "claude code" || s == "claude-code") return "claude"
    return s == "" ? "-" : s
}
# builtin(k): a kind both Herdr and agents know by that name (the default
# AGENTS_NAMES), so a mismatch between two of them is another CLI.
function builtin(k) { return k == "claude" || k == "codex" || k == "agy" || k == "grok" || k == "cursor-agent" }
# herdr_match(): which of Herdr's agents (1..nh) each agent row (1..na) is,
# in hm[] (0: none). By pane first: the Herdr agent in a row's pane (its
# HERDR_PANE_ID, when Herdr reports pane ids) is the one row there of the
# kind Herdr names, so another CLI in the same pane (a codex started from
# the pane's shell beside claude) never takes its status, and two of that
# kind leave it unmatched. With no row of that kind there, the pane's only
# row is it unless both kinds are built-in ones that differ: Herdr names no
# kind, one agents doesn't know, or the row is a kind of your own
# (AGENTS_NAMES). Else, for a row with no pane to go by, the only unclaimed
# agent of its kind in its directory, when it is also the only such row.
# Never the codex daemon.
function herdr_match(   i, f, k, h, pn) {
    for (i = 1; i <= na; i++) {
        split(arow[i], f, "\t"); hm[i] = 0
        if (f[3] == "daemon") continue
        if ((f[2] in epane) && npane) {
            pn = epane[f[2]]; prow[pn]++; prone[pn] = i; pk1[pn] = f[3]
            pkind[pn, f[3]]++; pkone[pn, f[3]] = i
            continue
        }
        if (f[13] != "-") { pend[i] = 1; acnt[f[3], f[13]]++ }
    }
    for (pn in byp) {
        h = byp[pn]; i = 0
        if (hk[h] != "-" && pkind[pn, hk[h]] >= 1) { if (pkind[pn, hk[h]] == 1) i = pkone[pn, hk[h]] }
        else if (prow[pn] == 1 && !(builtin(hk[h]) && builtin(pk1[pn]))) i = prone[pn]
        if (i) { hm[i] = h; claimed[h] = 1 }
    }
    for (i = 1; i <= nh; i++) if (!(i in claimed)) { hcnt[hk[i], hc[i]]++; hone[hk[i], hc[i]] = i }
    for (i = 1; i <= na; i++) {
        if (!(i in pend)) continue
        split(arow[i], f, "\t"); k = f[3] SUBSEP f[13]
        if (acnt[k] == 1 && hcnt[k] == 1) hm[i] = hone[k]
    }
}
# civil(s): Unix seconds of a UTC "Fri Oct 16 18:13:16 2026" (ctime's
# layout, Claude Code's procStart), -1 when it is not one. Days from the
# civil date by H. Hinnant's formula: POSIX awk has no mktime.
function civil(s,   a, m, t, y, d, era, yoe, doe) {
    if (split(s, a, " ") != 5 || split(a[4], t, ":") != 3 || length(a[2]) != 3) return -1
    m = index("JanFebMarAprMayJunJulAugSepOctNovDec", a[2])
    if (m == 0 || (m - 1) % 3) return -1
    m = (m - 1) / 3 + 1; d = a[3] + 0; y = a[5] - (m <= 2)
    if (a[5] < 1970 || d < 1 || d > 31) return -1
    era = int(y / 400); yoe = y - era * 400
    doe = yoe * 365 + int(yoe / 4) - int(yoe / 100) + int((153 * ((m + 9) % 12) + 2) / 5) + d - 1
    return (era * 146097 + doe - 719468) * 86400 + t[1] * 3600 + t[2] * 60 + t[3]
}
# sid_ok(s): a session id passed on: 1 to 128 of A-Z a-z 0-9 _ -.
function sid_ok(s) { return s != "" && length(s) <= 128 && s !~ /[^A-Za-z0-9_-]/ }
# jstr(j, key): the string value of key in a flat JSON text, "" for none
# (or one with an escape in it).
function jstr(j, key,   v) {
    if (!match(j, "\"" key "\" *: *\"[^\"\\\\]*\"")) return ""
    v = substr(j, RSTART, RLENGTH); sub(/^[^:]*: *"/, "", v); sub(/"$/, "", v)
    return v
}
# claude_sid(pid, age): the session id Claude Code recorded for pid in
# $CLAUDE_CONFIG_DIR/sessions/PID.json (activity.sh's _agents_session_of
# reads the same), only when its procStart parses and is this process's
# start (within 5s: a record a crash left never names a reused pid); ""
# otherwise.
function claude_sid(pid, age,   file, line, j, ps, sid) {
    if (cdir == "" || now <= 0) return ""
    file = cdir "/sessions/" pid ".json"; j = ""
    while ((getline line < file) > 0) { j = j line; if (length(j) > 65536) break }
    close(file)
    sid = jstr(j, "sessionId"); ps = civil(jstr(j, "procStart"))
    if (ps < 0 || (now - age - ps) * (now - age - ps) > 25) return ""
    return sid_ok(sid) ? sid : ""
}
# arg_sid(args): the UUID a command line resumes or names, "" for none: the
# word after claude's --resume, -r or --session-id (or --resume=ID,
# --session-id=ID), or after codex's resume subcommand, the word right after
# the codex executable. Words, split on spaces: a prompt that says "resume
# ID" names nothing.
function arg_sid(args,   n, a, i, v, b, u) {
    u = "^[0-9a-fA-F]+-[0-9a-fA-F]+-[0-9a-fA-F]+-[0-9a-fA-F]+-[0-9a-fA-F]+$"
    n = split(args, a, " ")
    for (i = 1; i <= n; i++) {
        if ((a[i] == "--resume" || a[i] == "-r" || a[i] == "--session-id") && a[i + 1] ~ u) return a[i + 1]
        if (a[i] ~ /^--(resume|session-id)=/) { v = a[i]; sub(/^[^=]*=/, "", v); if (v ~ u) return v }
    }
    for (i = 1; i <= n; i++) { b = a[i]; sub(/.*\//, "", b); if (b == "codex" || b == "codex.js") break }
    return (a[i + 1] == "resume" && a[i + 2] ~ u) ? a[i + 2] : ""
}
# session_id(i): the CLI session agent row i runs, "-" when unknown: Claude
# Code's own record, else the session Herdr reports for the row's Herdr
# agent, else the one its command line resumes (last: a /clear starts
# another session in the same process).
function session_id(i,   f, s) {
    split(arow[i], f, "\t"); s = ""
    if (f[3] == "daemon") return "-"
    if (f[3] == "claude") s = claude_sid(f[2], f[4])
    if (s == "" && hm[i]) s = hsid[hm[i]]
    if (s == "" && (f[3] == "claude" || f[3] == "codex")) s = arg_sid(f[14])
    return s == "" ? "-" : s
}
END {
    herdr_match()
    for (i = 1; i <= na; i++) {
        $0 = arow[i]; p = ""
        if (hm[i]) { $12 = hst[hm[i]]; p = hpn[hm[i]]; arow[i] = $0 }
        if (p == "" || p == "-") p = ($2 in epane) ? epane[$2] : "-"
        ti = hm[i] ? hti[hm[i]] : "-"
        if (p != "-" || ti != "-") hrec[i] = "herdr" OFS $2 OFS p OFS ti
        irec[i] = "ident" OFS $2 OFS p OFS session_id(i)
        ar[i] = rank($3, $12)
    }
    for (r = 0; r <= 4; r++) for (i = 1; i <= na; i++) if (ar[i] == r) print arow[i]
    for (i = 1; i <= na; i++) if (i in hrec) print hrec[i]
    for (i = 1; i <= na; i++) print irec[i]
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
    home = ENVIRON["HOME"]; cdir = ENVIRON["AGENTS_CLAUDE_DIR"]; now = ENVIRON["AGENTS_ENRICH_NOW"] + 0
    nr = split(ENVIRON["AGENTS_CWD_ROOTS"], roots, "\n")
    n = split(ENVIRON["AGENTS_CWDS"], t, "\n")
    for (i = 1; i <= n; i++) if ((m = split(t[i], f, "\t")) >= 2 && (m == 2 || f[3] == "cwd")) cwd[f[1]] = f[2]
    # Herdr's agents: kind, status, cwd, and (newer caches) pane, title and
    # the agent's session id.
    n = split(ENVIRON["AGENTS_HERDR"], t, "\n")
    for (i = 1; i <= n; i++) {
        if ((m = split(t[i], f, "\t")) < 3) continue
        nh++; hk[nh] = hkind(f[1]); hst[nh] = f[2]; hc[nh] = f[3]
        hpn[nh] = (m >= 4 && f[4] ~ /^[A-Za-z0-9:_-]+$/) ? f[4] : "-"
        hti[nh] = (m >= 5) ? htitle(f[5], f[1]) : "-"
        hsid[nh] = (m >= 6 && sid_ok(f[6]) && f[6] != "-") ? f[6] : ""
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
