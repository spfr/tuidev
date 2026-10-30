# lib/agents/awk/render.awk — agents_render: the human table (sessions with
# what they run, stale processes, hogs). Needs lib_fmt.

function tilde(p) { return (p != "-" && index(p, home) == 1) ? "~" substr(p, length(home) + 1) : p }
function has(x) { return index(want, " " x " ") > 0 }
function flags(f,   o) {
    o = ""
    if (index("," f[16] ",", ",dup,")) o = o "  " ENVIRON["Y"] "x" f[17] " dup" e
    if (index("," f[16] ",", ",long,")) o = o "  " ENVIRON["Y"] "long" e
    if (index("," f[16] ",", ",hot,")) o = o "  " ENVIRON["R"] "hot" e
    if (index("," f[16] ",", ",wait,")) o = o "  " ENVIRON["DIM"] "wait" e
    if (index("," f[16] ",", ",stuck,")) o = o "  " ENVIRON["Y"] "stuck" e
    return o
}
# The activity lines under session r; full lists every unit with its pid.
function activity(r, full,   i, j, k, f, g, nm, mp, mr, nt, tl, ns, ss, no, oth, lim, t, names) {
    nm = 0; mp = 0; mr = 0; nt = 0; ns = 0; no = 0; names = ""
    split("", seen)
    for (i = 1; i <= nx; i++) {
        split(x[i], f, "\t")
        if (f[11] != r) continue
        if (f[3] == "mcp") { if (!(f[12] in seen)) { seen[f[12]] = 1; nm++; names = names (names == "" ? "" : ", ") f[12] } mp += f[8] + 1; mr += f[7] }
        else if (f[3] == "tool") tl[++nt] = x[i]
        else if (f[3] == "session") ss[++ns] = x[i]
        else oth[++no] = x[i]
    }
    if (nm) printf "%s      mcp: %d server%s · %d procs · %s%s%s\n", ENVIRON["DIM"], nm, (nm > 1 ? "s" : ""), mp, mem(mr), " (" names ")", e
    for (j = 1; j <= nt; j++) {          # busiest first
        k = j
        for (i = j + 1; i <= nt; i++) { split(tl[i], f, "\t"); split(tl[k], g, "\t"); if (f[5] + 0 > g[5] + 0) k = i }
        t = tl[j]; tl[j] = tl[k]; tl[k] = t
    }
    lim = full ? nt : ENVIRON["LS_TOOLS"] + 0
    for (j = 1; j <= nt && j <= lim; j++) {
        split(tl[j], f, "\t")
        printf "      %s %s · %s · %d%% · %s%s%s\n", (full ? sprintf("%-7s", f[2]) : "\342\224\224"), cut(f[14], w - 50), dur(f[4]), f[5] + 0.5, f[15], flags(f), (full ? "" : "")
    }
    if (nt > lim) printf "%s      ... %d more (agents ps %s)%s\n", ENVIRON["DIM"], nt - lim, r, e
    for (j = 1; j <= ns; j++) {
        split(ss[j], f, "\t")
        printf "      %s %s · %s · %d%% · %s session\n", (full ? sprintf("%-7s", f[2]) : "\342\206\263"), cut(f[14], w - 50), dur(f[4]), f[5] + 0.5, f[12]
    }
    if (full) for (j = 1; j <= no; j++) {
        split(oth[j], f, "\t")
        printf "%s      %-7s %s · %s · %d%% · %s%s\n", ENVIRON["DIM"], f[2], f[3], cut(f[14], w - 50), f[5] + 0.5, mem(f[7]), e
    }
}
BEGIN { home = ENVIRON["HOME"]; w = ENVIRON["W"] + 0; want = " " ENVIRON["AGENTS_SECTIONS"] " "; e = ENVIRON["N"] }
NF >= 14 {
    if ($1 == "act") x[++nx] = $0
    else if ($1 == "agent") { if (ENVIRON["FOCUS"] != "" && $2 != ENVIRON["FOCUS"]) next; if ($3 == "daemon") d[++nd] = $0; else a[++na] = $0 }
    else if ($1 == "stale") s[++ns] = $0
    else if ($1 == "hog") h[++nh] = $0
}
END {
    quiet = has("quiet"); printed = 0
    if (has("agents")) {
        printf "%sAGENTS (%d)%s%s\n", ENVIRON["B"], na, e, (nd ? ENVIRON["DIM"] " + codex daemon" e : "")
        if (na + nd) printf "%s  %-7s %-7s %-8s %7s %6s %6s %4s  %-11s %-22s %s%s\n", ENVIRON["DIM"], "PID", "KIND", "STATUS", "AGE", "CPU%", "MEM", "KIDS", "PORTS", "PROJECT", "CWD", e
        for (i = 1; i <= na + nd; i++) {
            split(i <= na ? a[i] : d[i - na], f, "\t")
            c = f[12] == "blocked" ? ENVIRON["Y"] ENVIRON["B"] : f[12] == "working" ? ENVIRON["G"] : ""
            pre = (i > na ? ENVIRON["DIM"] : "")
            line = sprintf("%s  %-7s %-7s %s%-8s%s%s %7s %6.1f %6s %4d  %-11s %-22s ", pre, f[2], f[3], c, f[12], (c == "" ? "" : e), pre, age(f[4]), f[5], mem(f[7]), f[8], cut(f[10], 11), cut(f[15], 22))
            print line cut(tilde(f[13]), w - 101) (pre == "" ? "" : e)
            if (i <= na) activity(f[2], has("detail"))
        }
        if (!na) print "  no claude or codex session is running"
        printed = 1
    }
    if (quiet && !ns && !nh && (has("stale") || has("hogs"))) { print ""; print ENVIRON["DIM"] "no stale processes · no hogs" e; exit }
    if (has("stale") && (ns || !quiet)) {
        if (printed) print ""
        printf "%sSTALE (%d)%s%s\n", (ns ? ENVIRON["Y"] ENVIRON["B"] : ENVIRON["B"]), ns, e, (ns ? ENVIRON["DIM"] "  orphaned agent helpers and dev servers: agents reap" e : "")
        if (ns) printf "%s  %-7s %-7s %7s %6s %6s %4s  %-11s %s%s\n", ENVIRON["DIM"], "PID", "WHY", "AGE", "CPU%", "MEM", "KIDS", "PORTS", "COMMAND", e
        for (i = 1; i <= ns; i++) {
            split(s[i], f, "\t")
            line = sprintf("  %-7s %-7s %7s %6.1f %6s %4d  %-11s ", f[2], f[3], age(f[4]), f[5], mem(f[7]), f[8], f[10])
            print line cut(f[14] (f[13] != "-" ? "  (in " tilde(f[13]) ")" : ""), w - 59)
        }
        if (!ns) print "  none"
        printed = 1
    }
    if (has("hogs") && (nh || !quiet)) {
        if (printed) print ""
        printf "%sHOGS (%d)%s%s\n", (nh ? ENVIRON["R"] ENVIRON["B"] : ENVIRON["B"]), nh, e, (nh ? ENVIRON["DIM"] "  CPU% now / lifetime average, or memory: agents term PID · agents mem" e : "")
        if (nh) printf "%s  %-7s %-12s %7s %6s %6s %6s  %s%s\n", ENVIRON["DIM"], "PID", "USER", "AGE", "NOW%", "AVG%", "MEM", "PROCESS", e
        for (i = 1; i <= nh; i++) {
            split(h[i], f, "\t")
            mw = (ENVIRON["MEMWARN"] + 0 > 0 && f[7] + 0 >= ENVIRON["MEMWARN"] + 0)
            line = sprintf("  %-7s %-12s %7s %6.1f %6.1f %s%6s%s  ", f[2], substr(f[11], 1, 12), age(f[4]), f[5], f[6], (mw ? ENVIRON["R"] ENVIRON["B"] : ""), mem(f[7]), (mw ? e : ""))
            print line cut(f[3] (mw ? " (memory)" : ""), w - 58)
        }
        if (!nh) print "  none"
    }
}
