# lib/agents/awk/report.awk — `agents report`, as text or JSON, from
# history.tsv (hf) and events.tsv (ef). Runs in BEGIN: it reads no input.

function jstr(s,   o, i, c, n) {
    n = length(s); o = ""
    for (i = 1; i <= n; i++) {
        c = substr(s, i, 1)
        if (c == "\\") o = o "\\\\"; else if (c == "\"") o = o "\\\""; else if (c >= " ") o = o c
    }
    return "\"" o "\""
}
function jopt(s) { return (s == "-" || s == "") ? "null" : jstr(s) }
# h: CPU seconds in the unit of the report (CPU-h, or CPU-min below an hour in all).
function h(s) { return sprintf("%.2f", s / unit) }
function pc1(a, b) { return sprintf("%.1f", b > 0 ? 100 * a / b : 0) }
function pct(a, b) { return sprintf("%d%%", b > 0 ? 100 * a / b + 0.5 : 0) }
function bar(p,   k, o) { k = int(p / 5 + 0.5); o = ""; while (k-- > 0) o = o "\342\226\210"; return o }
function sess(s) { return s == "-" ? "stale" : s }
function proj(s) { return s == "-" ? "(none)" : s }
# sortk ARR KEYS N — KEYS[1..N], busiest (largest ARR[key]) first.
# Busiest first; ties by name, so every awk (BSD, gawk, mawk, BusyBox) agrees.
function sortk(arr, keys, cnt,   i, j, b, t) {
    for (i = 1; i <= cnt; i++) {
        b = i
        for (j = i + 1; j <= cnt; j++) if (arr[keys[j]] > arr[keys[b]] || (arr[keys[j]] == arr[keys[b]] && keys[j] < keys[b])) b = j
        t = keys[i]; keys[i] = keys[b]; keys[b] = t
    }
}
# line KEYS N ARR FMT — "a 1.00 · b 0.50" (FMT "h": CPU-h, else counts).
function line(keys, cnt, arr, fmt, lim,   i, o) {
    o = ""
    for (i = 1; i <= cnt && i <= lim; i++) o = o (i > 1 ? " \302\267 " : "") keys[i] " " (fmt == "h" ? h(arr[keys[i]]) : arr[keys[i]])
    return o
}
function jlist(keys, cnt, arr, name, val,   i, o) {
    o = ""
    for (i = 1; i <= cnt; i++) o = o (i > 1 ? "," : "") sprintf("{\"%s\":%s,\"%s\":%d}", name, jopt(keys[i]), val, arr[keys[i]])
    return "[" o "]"
}
BEGIN {
    b = ENVIRON["B"]; dim = ENVIRON["DIM"]; e = ENVIRON["N"]
    while ((getline ln < hf) > 0) {
        if (split(ln, f, "\t") < 7) continue
        t = f[1] + 0; c = f[5] + 0; any++
        if (t < start || f[2] == "") continue
        rows++; tot += c
        if (!(f[2] in jc)) jo[++nj] = f[2]; jc[f[2]] += c
        if (!(f[3] in pc)) po[++np] = f[3]; pc[f[3]] += c; pj[f[3], f[2]] += c
        if (!(f[4] in sc)) so[++ns] = f[4]; sc[f[4]] += c
        hr = int(((t + off) % 86400) / 3600); hc[hr] += c
    }
    close(hf)
    while ((getline ln < ef) > 0) {
        if (split(ln, f, "\t") < 7) continue
        any++; if (f[1] + 0 < start) continue
        ev++
        if (!(f[3] in er)) ro[++nr] = f[3]; er[f[3]]++
        if (!(f[2] in ek)) ko[++nk] = f[2]; ek[f[2]]++
        if (f[3] != "manual" && f[6] != "-" && f[6] != "") { if (!(f[6] in ep)) eo[++ne] = f[6]; ep[f[6]]++ }
    }
    close(ef)
    sortk(jc, jo, nj); sortk(pc, po, np); sortk(sc, so, ns); sortk(er, ro, nr); sortk(ek, ko, nk); sortk(ep, eo, ne)
    for (i = 1; i <= np; i++) {
        p = po[i]; mj[p] = "-"; mv[p] = 0
        for (k = 1; k <= nj; k++) if (pj[p, jo[k]] > mv[p]) { mv[p] = pj[p, jo[k]]; mj[p] = jo[k] }
    }
    nh = 0
    for (i = 0; i < 24; i++) if (hc[i] > 0) ho[++nh] = i
    if (json) {
        o = sprintf("{\"schema_version\":1,\"since\":%d,\"until\":%d,\"window\":%s,\"history\":%s,\"cpu_s\":%d,\"jobs\":[", start, now, jstr(label), (hist == 1 ? "true" : "false"), tot)
        for (i = 1; i <= nj; i++) o = o (i > 1 ? "," : "") sprintf("{\"job\":%s,\"cpu_s\":%d,\"pct\":%s}", jstr(jo[i]), jc[jo[i]], pc1(jc[jo[i]], tot))
        o = o "],\"projects\":["
        for (i = 1; i <= np; i++) {
            p = po[i]; s = ""
            for (k = 1; k <= nj; k++) if (pj[p, jo[k]] > 0) s = s (s == "" ? "" : ",") sprintf("{\"job\":%s,\"cpu_s\":%d}", jstr(jo[k]), pj[p, jo[k]])
            o = o (i > 1 ? "," : "") sprintf("{\"project\":%s,\"cpu_s\":%d,\"pct\":%s,\"main_job\":%s,\"main_job_pct\":%s,\"jobs\":[", jopt(p), pc[p], pc1(pc[p], tot), jopt(mj[p]), pc1(mv[p], pc[p])) s "]}"
        }
        o = o "],\"sessions\":["
        for (i = 1; i <= ns; i++) o = o (i > 1 ? "," : "") sprintf("{\"session\":%s,\"cpu_s\":%d,\"pct\":%s}", jopt(so[i]), sc[so[i]], pc1(sc[so[i]], tot))
        o = o "],\"hours\":["
        for (i = 1; i <= nh; i++) o = o (i > 1 ? "," : "") sprintf("{\"hour\":%d,\"cpu_s\":%d}", ho[i], hc[ho[i]])
        o = o sprintf("],\"cleanups\":{\"total\":%d,\"by_reason\":", ev) jlist(ro, nr, er, "reason", "count") ",\"by_kind\":" jlist(ko, nk, ek, "kind", "count") ",\"projects\":" jlist(eo, ne, ep, "project", "count") "}}"
        print o
        exit
    }
    when = (label == "today" ? "today" : "last " label)
    if (!any) {
        if (hist != 1) print "agents report: history is off (AGENTS_HISTORY=0 in agents.conf); nothing is recorded"
        else print "agents report: no history yet; it starts within a minute of the menu running (or of agents watch; agents sample takes one now)"
        exit
    }
    printf "%sagents report%s %s\302\267 %s%s\n", b, e, dim, when, e
    if (hist != 1) printf "%shistory is off (AGENTS_HISTORY=0): this is what was recorded before%s\n", dim, e
    print ""
    unit = (tot >= 3600 ? 3600 : 60); un = (unit == 3600 ? "CPU-h" : "CPU-min")
    if (rows) {
        printf "%sCPU%s %s %s of agent work\n\n", b, e, h(tot), un
        printf "%s  %-16s %8s %6s%s\n", dim, "JOB", un, "%", e
        for (i = 1; i <= nj; i++) printf "  %-16s %8s %6s  %s\n", jo[i], h(jc[jo[i]]), pct(jc[jo[i]], tot), bar(tot > 0 ? 100 * jc[jo[i]] / tot : 0)
        print ""
        printf "%s  %-24s %8s %6s  %s%s\n", dim, "PROJECT", un, "%", "MAIN JOB", e
        for (i = 1; i <= np && i <= 8; i++) {
            p = po[i]; nm = proj(p); if (length(nm) > 24) nm = substr(nm, 1, 21) "..."
            printf "  %-24s %8s %6s  %s %s\n", nm, h(pc[p]), pct(pc[p], tot), mj[p], pct(mv[p], pc[p])
        }
        if (np > 8) printf "%s  ... %d more (agents report --json)%s\n", dim, np - 8, e
        print ""
        for (i = 1; i <= ns; i++) { sk[i] = sess(so[i]); scs[sk[i]] = sc[so[i]] }
        printf "%sSESSIONS%s       %s %s%s%s\n", b, e, line(sk, ns, scs, "h", 8), dim, un, e
        for (i = 1; i <= nh; i++) hk[i] = sprintf("%02d:00", ho[i])
        for (i = 1; i <= nh; i++) hcs[hk[i]] = hc[ho[i]]
        sortk(hcs, hk, nh)
        printf "%sBUSIEST HOURS%s  %s %s%s%s\n", b, e, line(hk, nh, hcs, "h", 3), dim, un, e
    } else print "no CPU samples in this window"
    print ""
    printf "%sCLEANUPS (%d)%s\n", b, ev, e
    if (ev) {
        printf "  why          %s\n", line(ro, nr, er, "n", 8)
        printf "  how          %s\n", line(ko, nk, ek, "n", 8)
        if (ne) printf "  left behind  %s\n", line(eo, ne, ep, "n", 5)
    } else print "  none"
}
