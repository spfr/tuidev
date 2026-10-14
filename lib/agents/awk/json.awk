# lib/agents/awk/json.awk — agents_json: the whole snapshot as one JSON
# object. The schema is a contract (docs/agent-workflows.md).

# jobrow, jobs_json: the job of each tool and MCP server, and the top-level
# "jobs" list (busiest first, each with its sessions).
function jobrow(   k) {
    if ($10 == "own") ujob[$11] = $3
    if (!($3 in jcpu)) jord[++njob] = $3
    jcpu[$3] += $5; jrss[$3] += $7; jproc[$3] += $8
    k = $3 SUBSEP $2
    if (!(k in jscpu)) { jsn[$3]++; jsr[$3, jsn[$3]] = $2; jsp[k] = $15; jsk[k] = $12 }
    jscpu[k] += $5; jsrss[k] += $7
}
function jobs_json(   i, j, b, t, out, ss, k, m, r) {
    for (i = 1; i <= njob; i++) {
        b = i
        for (j = i + 1; j <= njob; j++) if (jcpu[jord[j]] > jcpu[jord[b]]) b = j
        t = jord[i]; jord[i] = jord[b]; jord[b] = t
    }
    out = ""
    for (i = 1; i <= njob; i++) {
        j = jord[i]; ss = ""
        for (m = 1; m <= jsn[j]; m++) {
            r = jsr[j, m]; k = j SUBSEP r
            ss = ss (m > 1 ? "," : "") sprintf("{\"pid\":%d,\"project\":%s,\"kind\":%s,\"cpu\":%s,\"rss_kib\":%d}", r, opt(jsp[k]), opt(jsk[k]), c1(jscpu[k]), jsrss[k])
        }
        out = out (i > 1 ? "," : "") sprintf("{\"job\":%s,\"cpu\":%s,\"rss_kib\":%d,\"processes\":%d,\"sessions\":[", js(j), c1(jcpu[j]), jrss[j], jproc[j]) ss "]}"
    }
    return out
}
function js(s,   o, i, c, n) {
    n = length(s); o = ""
    for (i = 1; i <= n; i++) {
        c = substr(s, i, 1)
        if (c == "\\") o = o "\\\\"; else if (c == "\"") o = o "\\\""; else if (c == "\t") o = o "\\t"
        else if (c >= " ") o = o c
    }
    return "\"" o "\""
}
function opt(s) { return s == "-" || s == "" ? "null" : js(s) }
function ports(s,   n, a, i, o) { if (s == "-") return "[]"; n = split(s, a, ","); o = ""; for (i = 1; i <= n; i++) o = o (i > 1 ? "," : "") (a[i] + 0); return "[" o "]" }
function obj(r,   f) {
    split(r, f, "\t")
    return sprintf("{\"pid\":%d,\"kind\":%s,\"age_s\":%d,\"cpu\":%s,\"avg_cpu\":%s,\"rss_kib\":%d,\"children\":%d,\"start\":%s,\"start_epoch\":%d,\"ports\":%s,\"user\":%s,\"herdr\":%s,\"cwd\":%s,\"project\":%s,\"command\":%s",
        f[2], js(f[3]), f[4], f[5] + 0, f[6] + 0, f[7], f[8], js(f[9]), ENVIRON["NOW"] - f[4], ports(f[10]), js(f[11]), opt(f[12]), opt(f[13]), opt(f[15]), js(f[14])) (f[1] == "stale" ? vfields(f[2]) : "") "}"
}
function num(s) { return s == "-" || s == "" ? "null" : s + 0 }
# vfields(p) — ",verdict:{…},evidence:{…}" for an item agents_assess judged
# (its need/evid rows come first in the input), or nothing.
function vfields(p,   g) {
    if (!(p in nd)) return ""
    split(nd[p], g, "\t")
    return sprintf(",\"verdict\":{\"action\":%s,\"short\":%s,\"text\":%s,\"confidence\":%s,\"code\":%s,\"auto_reap\":%s,\"auto_reap_note\":%s},\"evidence\":{\"flag\":%s,\"session_ended\":%s,\"owner\":%s,\"age_s\":%d,\"cpu\":%s,\"ports\":%s,\"watched\":%s,\"watched_quiet_s\":%s,\"last_line\":%s,\"completion_marker\":%s,\"lines\":[%s],\"next\":[%s]}",
        js(g[5]), js(g[10]), js(g[11]), js(g[6]), js(g[7]), (g[8] == 1 ? "true" : "false"), opt(eva[p]),
        js(g[4]), (g[4] == "stale" ? "true" : "false"),
        (g[9] == "-" ? "null" : sprintf("{\"pid\":%d,\"kind\":%s,\"project\":%s}", g[9], opt(g[12]), opt(g[13]))),
        g[14], c1(g[15]), ports(g[16]), opt(g[17]), num(g[18]), opt(g[19]), (g[20] == "-" ? "null" : g[20] == 1 ? "true" : "false"), evf[p], evn[p])
}
function fl(s,   n, a, i, o) { if (s == "-" || s == "") return "[]"; n = split(s, a, ","); o = ""; for (i = 1; i <= n; i++) o = o (i > 1 ? "," : "") js(a[i]); return "[" o "]" }
function c1(v) { return sprintf("%.1f", v + 0) }
# What session r runs. Units are its direct children; nested sessions sit
# inside a unit, so they are listed but not added again.
function activity(r, tcpu, trss,   i, f, cs, ct, cm, co, rt, rm, ro, n, nm, mo, mn, mp, mr, mc, mj, tl, sl, k) {
    ct = cm = co = rt = rm = ro = 0; tl = ""; sl = ""; nm = 0
    split("", mp); split("", mr); split("", mc); split("", mj)
    for (i = 1; i <= nx; i++) {
        split(x[i], f, "\t")
        if (f[11] != r) continue
        if (f[3] == "session") {
            sl = sl (sl == "" ? "" : ",") sprintf("{\"pid\":%d,\"start\":%s,\"start_epoch\":%d,\"token\":%s,\"depth\":%s,\"age_s\":%d,\"cpu\":%s,\"rss_kib\":%d,\"command\":%s,\"job\":\"agent\"}",
                f[2], js(f[9]), ENVIRON["NOW"] - f[4], js(f[2] "@" f[9]), js(f[12]), f[4], c1(f[5]), f[7], js(f[14]))
            if (f[12] == "nested") continue
        }
        if (f[3] == "mcp") {
            cm += f[5]; rm += f[7]
            if (!(f[12] in mp)) { mo[++nm] = f[12]; mj[f[12]] = ujob[f[2]] }
            mp[f[12]] += f[8] + 1; mr[f[12]] += f[7]; mc[f[12]] += f[5]
        } else if (f[3] == "tool") {
            ct += f[5]; rt += f[7]
            tl = tl (tl == "" ? "" : ",") sprintf("{\"pid\":%d,\"start\":%s,\"start_epoch\":%d,\"token\":%s,\"cmd\":%s,\"origin\":%s,\"cwd\":%s,\"age_s\":%d,\"cpu\":%s,\"rss_kib\":%d,\"processes\":%d,\"ports\":%s,\"flags\":%s,\"dup_count\":%d,\"job\":%s%s}",
                f[2], js(f[9]), ENVIRON["NOW"] - f[4], js(f[2] "@" f[9]), js(f[14]), opt(f[15]), opt(f[13]), f[4], c1(f[5]), f[7], f[8] + 1, ports(f[10]), fl(f[16]), f[17], opt(ujob[f[2]]), vfields(f[2]))
        } else { co += f[5]; ro += f[7] }
    }
    mn = ""
    for (k = 1; k <= nm; k++) mn = mn (k > 1 ? "," : "") sprintf("{\"name\":%s,\"procs\":%d,\"cpu\":%s,\"rss_kib\":%d,\"job\":%s}", js(mo[k]), mp[mo[k]], c1(mc[mo[k]]), mr[mo[k]], opt(mj[mo[k]]))
    cs = tcpu - ct - cm - co; if (cs < 0) cs = 0
    return sprintf("{\"cpu\":{\"self\":%s,\"tools\":%s,\"mcp\":%s,\"other\":%s},\"rss_kib\":{\"self\":%d,\"tools\":%d,\"mcp\":%d,\"other\":%d},\"mcp\":[",
        c1(cs), c1(ct), c1(cm), c1(co), (trss - rt - rm - ro > 0 ? trss - rt - rm - ro : 0), rt, rm, ro) mn "],\"tools\":[" tl "],\"child_sessions\":[" sl "]}"
}
$1 == "need" { nd[$2] = $0; next }
$1 == "evid" {
    if ($3 == "fact") evf[$2] = evf[$2] (evf[$2] == "" ? "" : ",") js($4)
    else if ($3 == "next") evn[$2] = evn[$2] (evn[$2] == "" ? "" : ",") js($4)
    else eva[$2] = $4
    next
}
$1 == "total" { total = $5; next }
$1 == "act" { x[++nx] = $0; next }
$1 == "agent" && NF >= 14 { ag[++na] = $0; next }
$1 == "job" && NF >= 14 { jobrow(); next }
NF >= 14 { orw[++nor] = $0 }      # built at the end, once the job rows are in
END {
    for (i = 1; i <= nor; i++) {
        split(orw[i], f, "\t"); s = obj(orw[i])
        if (f[1] == "stale") s = substr(s, 1, length(s) - 1) ",\"job\":" opt(ujob[f[2]]) "}"
        o[f[1]] = o[f[1]] (o[f[1]] == "" ? "" : ",") s
    }
    aw = ENVIRON["AW_PID"] == "" ? "{\"active\":false}" : sprintf("{\"active\":true,\"pid\":%d,\"mode\":%s,\"until\":%d}", ENVIRON["AW_PID"], js(ENVIRON["AW_MODE"]), ENVIRON["AW_UNTIL"])
    split(ENVIRON["SYS"], y, "\t")
    sys = sprintf("{\"cpu_pct\":%s,\"load1\":%s,\"cores\":%s,\"mem_free_pct\":%s,\"mem_pressure\":%s,\"battery_pct\":%s,\"battery_state\":%s}",
        (total == "" ? "null" : int(total / (y[2] > 0 ? y[2] : 1) + 0.5)), num(y[1]), num(y[2]), num(y[3]), opt(y[4]), num(y[5]), opt(y[6]))
    for (i = 1; i <= na; i++) {
        split(ag[i], f, "\t"); s = obj(ag[i])
        o["agent"] = o["agent"] (i > 1 ? "," : "") substr(s, 1, length(s) - 1) ",\"activity\":" activity(f[2], f[5], f[7]) ",\"job\":\"agent\"}"
    }
    # Lists are joined, not passed through %s: mawk caps one sprintf/printf at 8 KiB.
    print "{\"schema_version\":1,\"agents\":[" o["agent"] "],\"stale\":[" o["stale"] "],\"hogs\":[" o["hog"] "],\"top\":[" o["top"] "],\"jobs\":[" jobs_json() "],\"system\":" sys ",\"awake\":" aw ",\"lid\":" ENVIRON["LID"] \
        sprintf(",\"thermal\":{\"level\":%s,\"name\":%s},\"powermode\":%s}", (ENVIRON["TH"] == "" ? "null" : ENVIRON["TH"] + 0), js(ENVIRON["TH_NAME"]), js(ENVIRON["PM"]))
}
