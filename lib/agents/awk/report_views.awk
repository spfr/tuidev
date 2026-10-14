# lib/agents/awk/report_views.awk — the run ledger's views of `agents report`
# (--view runs, waste, trends, agents), as text or JSON. Part of report.awk's
# program; needs report_runs, report_fmt, lib_json and lib_sort.

# vhead VIEW — the title line of a view.
function vhead(v) {
    printf "%sagents report%s %s\302\267 %s \302\267 %s%s%s\n\n", b, e, dim, v, when, (v == "trends" ? " vs " pword() : ""), e
}
# jhead VIEW — the start of a view's JSON object (the caller closes it).
function jhead(v) {
    return sprintf("{\"schema_version\":1,\"view\":%s,\"since\":%d,\"until\":%d,\"window\":%s,\"ledger\":%s", js(v), start, now, js(label), jb(RL))
}
# th / tr: a dimmed header row and a row of the command tables.
function th(s) { printf "%s%s%s\n", dim, s, e }
function cmdcells(k) { gsplit(k); return "  " lc(cut(proj(G_P), 20), 20) " " lc(cut(G_C, 12), 12) " " lc(G_J, 7) }
function cmdhead() { return "  " lc("PROJECT", 20) " " lc("COMMAND", 12) " " lc("JOB", 7) }
# gstats — GMED, GP90, GMAX for every command.
function gstats(   i, k) {
    for (i = 1; i <= GC; i++) { k = GO[i]; dstats(Gd, k, Gn[k]); GMED[k] = D_MED; GP90[k] = D_P90; GMAX[k] = D_MAX }
}
function jcmd(k) {
    gsplit(k)
    return sprintf("{\"project\":%s,\"cmd\":%s,\"job\":%s,\"runs\":%d,\"cpu_s\":%s,\"median_s\":%s,\"p90_s\":%s,\"max_s\":%s,", \
        opt(G_P), js(G_C), js(G_J), Gn[k], jn(Gcpu[k]), jn(GMED[k]), jn(GP90[k]), jn(GMAX[k])) \
        sprintf("\"exit_known\":%d,\"failed\":%d,\"fail_pct\":%s,\"dups\":%d,\"dup_cpu_s\":%s,\"reruns\":%d,\"rerun_cpu_s\":%s}", \
        Gknown[k], Gfail[k], (Gknown[k] ? pc1(Gfail[k], Gknown[k]) : "null"), Gdup[k], jn(Gdupcpu[k]), Grer[k], jn(Grercpu[k]))
}
# jcmds KEYS N LIM — the commands KEYS[1..N] (at most LIM) as a JSON array.
function jcmds(keys, n, lim,   i, o) {
    o = ""
    for (i = 1; i <= n && i <= lim; i++) o = o (i > 1 ? "," : "") jcmd(keys[i])
    return "[" o "]"
}

# runs: the most repeated commands, and the slowest tests and builds.
function view_runs(   i, k, ns, nf, nk, o) {
    gstats()
    for (i = 1; i <= GC; i++) { k = GO[i]; RK[i] = k; RC[k] = Gn[k] + Gcpu[k] / 1e9; nf += Gfail[k]; nk += Gknown[k] }
    sortk(RC, RK, GC)
    ns = 0
    for (i = 1; i <= GC; i++) { k = GO[i]; gsplit(k); if (G_J == "test" || G_J == "build") { SK[++ns] = k; SM[k] = GMED[k] } }
    sortk(SM, SK, ns)
    if (json) {
        o = jhead("runs") ",\"runs\":" RN ",\"cpu_s\":" jn(RCPU) ",\"exit_known\":" (nk + 0) ",\"failed\":" (nf + 0)
        print o ",\"commands\":" jcmds(RK, GC, GC) ",\"slowest\":" jcmds(SK, ns, 10) "}"
        return
    }
    vhead("runs")
    if (!RN) { print "no runs in this window"; return }
    printf "%sRUNS%s %d \302\267 %s CPU-h \302\267 %s failed\n\n", b, e, RN, ch(RCPU), pctn(nf, nk)
    printf "%sMOST REPEATED%s\n", b, e
    th(cmdhead() " " rc("RUNS", 5) " " rc("CPU-h", 7) " " rc("MEDIAN", 7) " " rc("P90", 7) " " rc("FAILED", 7))
    for (i = 1; i <= GC && i <= 10; i++) {
        k = RK[i]
        print cmdcells(k) " " rc(Gn[k], 5) " " rc(ch(Gcpu[k]), 7) " " rc(dur(GMED[k]), 7) " " rc(dur(GP90[k]), 7) " " rc(pctn(Gfail[k], Gknown[k]), 7)
    }
    if (GC > 10) th("  ... " (GC - 10) " more (agents report --view runs --json)")
    print ""
    printf "%sSLOWEST TESTS AND BUILDS%s %s(by median)%s\n", b, e, dim, e
    if (!ns) { print "  none in this window"; return }
    th(cmdhead() " " rc("RUNS", 5) " " rc("MEDIAN", 7) " " rc("P90", 7) " " rc("MAX", 7))
    for (i = 1; i <= ns && i <= 5; i++) {
        k = SK[i]
        print cmdcells(k) " " rc(Gn[k], 5) " " rc(dur(GMED[k]), 7) " " rc(dur(GP90[k]), 7) " " rc(dur(GMAX[k]), 7)
    }
}

# waste: duplicates, runs left running until a cleanup, polling loops, and
# failed runs re-run at once.
function view_waste(   i, k, a, j, nd, dc, nr, rcpu, nc, ccpu, cdur, nw, wdur, wcpu, o, s, ak, ad, jk, wk, wa) {
    for (i = 1; i <= GC; i++) {
        k = GO[i]
        if (Gdup[k]) { DK[++nd] = k; DV[k] = Gdupcpu[k]; dc += Gdupcpu[k] }
        if (Grer[k]) { EK[++nr] = k; EV[k] = Grercpu[k]; rcpu += Grercpu[k] }
    }
    sortk(DV, DK, nd); sortk(EV, EK, nr)
    for (i = 1; i <= AC; i++) {
        a = AO[i]
        if (Acln[a]) { ak[++nc] = a; ad[a] = Aclndur[a] }
        if (Aw[a]) { wk[++wa] = a; WV[a] = Awdur[a]; nw += Aw[a]; wdur += Awdur[a]; wcpu += Awcpu[a] }
        ccpu += Aclncpu[a]; cdur += Aclndur[a]
    }
    sortk(ad, ak, nc); sortk(WV, wk, wa)
    for (i = 1; i <= CJC; i++) { jk[i] = CJO[i]; JV[CJO[i]] = CJdur[CJO[i]] }
    sortk(JV, jk, CJC)
    nd = nd + 0; nr = nr + 0; nc = nc + 0; wa = wa + 0
    if (json) {
        o = jhead("waste") ",\"run_cpu_s\":" jn(RCPU) ",\"duplicates\":{\"runs\":" sumn(Gdup, DK, nd) ",\"cpu_s\":" jn(dc) ",\"commands\":" jsub(DK, nd, Gdup, Gdupcpu)
        o = o "},\"cleaned\":{\"runs\":" sumn(Acln, ak, nc) ",\"cpu_s\":" jn(ccpu) ",\"wall_s\":" jn(cdur) ",\"agents\":["
        for (i = 1; i <= nc; i++) { a = ak[i]; o = o (i > 1 ? "," : "") "{\"agent\":" opt(a) ",\"runs\":" Acln[a] ",\"cpu_s\":" jn(Aclncpu[a]) ",\"wall_s\":" jn(Aclndur[a]) ",\"wait_runs\":" (Aclnw[a] + 0) "}" }
        o = o "],\"jobs\":["
        for (i = 1; i <= CJC; i++) { j = jk[i]; o = o (i > 1 ? "," : "") "{\"job\":" js(j) ",\"runs\":" CJn[j] ",\"cpu_s\":" jn(CJcpu[j]) ",\"wall_s\":" jn(CJdur[j]) "}" }
        o = o "]},\"wait\":{\"runs\":" (nw + 0) ",\"wall_s\":" jn(wdur) ",\"cpu_s\":" jn(wcpu) ",\"agents\":["
        for (i = 1; i <= wa; i++) { a = wk[i]; o = o (i > 1 ? "," : "") "{\"agent\":" opt(a) ",\"runs\":" Aw[a] ",\"wall_s\":" jn(Awdur[a]) "}" }
        print o "]},\"reruns\":{\"runs\":" sumn(Grer, EK, nr) ",\"cpu_s\":" jn(rcpu) ",\"commands\":" jsub(EK, nr, Grer, Grercpu) "}}"
        return
    }
    vhead("waste")
    if (!RN) { print "no runs in this window"; return }
    printf "%sDUPLICATES%s  %s\n", b, e, (nd ? nruns(sumn(Gdup, DK, nd)) " \302\267 " ch(dc) " CPU-h (" pct(dc, RCPU) " of the runs' CPU)" : "none")
    subtable(DK, nd, Gdup, Gdupcpu)
    printf "%sLEFT RUNNING%s  %s\n", b, e, (nc ? nruns(sumn(Acln, ak, nc)) ", until a cleanup stopped them \302\267 " hrs(cdur) " \302\267 " ch(ccpu) " CPU-h" : "none")
    if (nc) {
        s = ""; for (i = 1; i <= nc && i <= 5; i++) { a = ak[i]; s = s (i > 1 ? " \302\267 " : "") agentn(a) " " Acln[a] " (" hrs(Aclndur[a]) ")" }
        print "  by agent    " s
        s = ""; for (i = 1; i <= CJC && i <= 5; i++) { j = jk[i]; s = s (i > 1 ? " \302\267 " : "") j " " CJn[j] " (" hrs(CJdur[j]) ")" }
        print "  by job      " s
    }
    print ""
    printf "%sPOLLING LOOPS%s  %s\n", b, e, (nw ? nw " \302\267 " hrs(wdur) " waiting" : "none")
    if (wa) {
        s = ""; for (i = 1; i <= wa && i <= 5; i++) { a = wk[i]; s = s (i > 1 ? " \302\267 " : "") agentn(a) " " Aw[a] " (" hrs(Awdur[a]) ")" }
        print "  by agent    " s
    }
    print ""
    printf "%sFAILED, RE-RUN AT ONCE%s  %s\n", b, e, (nr ? nruns(sumn(Grer, EK, nr)) " \302\267 " ch(rcpu) " CPU-h" : "none")
    subtable(EK, nr, Grer, Grercpu)
}
# sumn ARR KEYS N — the sum of ARR over KEYS[1..N].
function sumn(arr, keys, n,   i, t) { t = 0; for (i = 1; i <= n; i++) t += arr[keys[i]]; return t }
# subtable KEYS N COUNT CPU — up to 5 commands with a count and its CPU-h.
function subtable(keys, n, cnt, cpu,   i) {
    if (n) {
        th(cmdhead() " " rc("RUNS", 5) " " rc("CPU-h", 7))
        for (i = 1; i <= n && i <= 5; i++) print cmdcells(keys[i]) " " rc(cnt[keys[i]], 5) " " rc(ch(cpu[keys[i]]), 7)
    }
    print ""
}
function jsub(keys, n, cnt, cpu,   i, o) {
    o = ""
    for (i = 1; i <= n; i++) { gsplit(keys[i]); o = o (i > 1 ? "," : "") "{\"project\":" opt(G_P) ",\"cmd\":" js(G_C) ",\"job\":" js(G_J) ",\"runs\":" cnt[keys[i]] ",\"cpu_s\":" jn(cpu[keys[i]]) "}" }
    return "[" o "]"
}

# trends: this window against the one before, by project and by job.
function view_trends(   i, o) {
    tstats(TPO, TPC, TPn, TPcpu, TPd, "P"); tstats(TJO, TJC, TJn, TJcpu, TJd, "J")
    if (json) {
        o = jhead("trends") sprintf(",\"previous\":{\"since\":%d,\"until\":%d}", pstart, pend)
        print o ",\"projects\":" jtrend(TPO, TPC, "P", "project") ",\"jobs\":" jtrend(TJO, TJC, "J", "job") "}"
        return
    }
    vhead("trends")
    if (!TPC) { print "no runs in this window or the one before"; return }
    ttable("PROJECT", TPO, TPC, "P", 10)
    ttable("JOB", TJO, TJC, "J", 10)
    th("more CPU: up by half and 0.25 CPU-h or more \302\267 slower: the median run up by half and 30s or more (5+ runs in each)")
}
# tstats NAMES N CNT CPU DUR TAG — for TAG (P, J): TC[TAG, name, w] runs,
# TU[TAG, name, w] CPU, TM[TAG, name, w] median; NAMES sorted by this
# window's CPU.
function tstats(names, n, cnt, cpu, d, tag,   i, w, x, sv) {
    for (i = 1; i <= n; i++) {
        x = names[i]
        for (w = 1; w <= 2; w++) {
            TC[tag, x, w] = cnt[w, x] + 0; TU[tag, x, w] = cpu[w, x] + 0
            dstats(d, w SUBSEP x, TC[tag, x, w]); TM[tag, x, w] = D_MED
        }
        sv[x] = TU[tag, x, 1] + TU[tag, x, 2] / 1e9
    }
    sortk(sv, names, n)
}
function tflags(tag, x,   s) {
    s = cpu_regressed(TU[tag, x, 1], TU[tag, x, 2]) ? "more CPU" : ""
    if (slower(TM[tag, x, 1], TM[tag, x, 2], TC[tag, x, 1], TC[tag, x, 2])) s = s (s != "" ? ", " : "") "slower"
    return s
}
function ttable(title, names, n, tag, lim,   i, x, f) {
    th("  " lc(title, 20) " " rc("CPU-h", 7) " " rc("BEFORE", 7) " " rc("CHANGE", 7) "  " rc("RUNS", 5) " " rc("CHANGE", 7) "  " rc("MEDIAN", 7) " " rc("CHANGE", 7))
    for (i = 1; i <= n && i <= lim; i++) {
        x = names[i]; f = tflags(tag, x)
        print "  " lc(cut(tag == "P" ? proj(x) : x, 20), 20) " " rc(ch(TU[tag, x, 1]), 7) " " rc(ch(TU[tag, x, 2]), 7) " " rc(chg(TU[tag, x, 1], TU[tag, x, 2]), 7) \
            "  " rc(TC[tag, x, 1], 5) " " rc(chg(TC[tag, x, 1], TC[tag, x, 2]), 7) "  " rc(TC[tag, x, 1] ? dur(TM[tag, x, 1]) : "-", 7) " " \
            rc(chg(TM[tag, x, 1], TM[tag, x, 2]), 7) (f != "" ? "  " b f e : "")
    }
    if (n > lim) th("  ... " (n - lim) " more (agents report --view trends --json)")
    print ""
}
function jtrend(names, n, tag, key,   i, x, o) {
    o = ""
    for (i = 1; i <= n; i++) {
        x = names[i]
        o = o (i > 1 ? "," : "") "{\"" key "\":" (tag == "P" ? opt(x) : js(x)) ",\"cpu_s\":" jn(TU[tag, x, 1]) ",\"prev_cpu_s\":" jn(TU[tag, x, 2]) \
            ",\"runs\":" TC[tag, x, 1] ",\"prev_runs\":" TC[tag, x, 2] ",\"median_s\":" jn(TM[tag, x, 1]) ",\"prev_median_s\":" jn(TM[tag, x, 2]) \
            ",\"more_cpu\":" jb(cpu_regressed(TU[tag, x, 1], TU[tag, x, 2])) ",\"slower\":" jb(slower(TM[tag, x, 1], TM[tag, x, 2], TC[tag, x, 1], TC[tag, x, 2])) "}"
    }
    return "[" o "]"
}

# agents: runs, CPU, failures, duplicates, leaks and polling by agent type.
function view_agents(   i, a, o, ak, av, lk, lv, dk, dv, nl, nd, s) {
    for (i = 1; i <= AC; i++) {
        a = AO[i]; ak[i] = a; av[a] = Acpu[a]
        if (Acln[a]) { lk[++nl] = a; lv[a] = Acln[a] + Aclndur[a] / 1e9 }
        if (Adup[a]) { dk[++nd] = a; dv[a] = Adup[a] + Adupcpu[a] / 1e9 }
    }
    sortk(av, ak, AC); sortk(lv, lk, nl); sortk(dv, dk, nd)
    if (json) {
        o = jhead("agents") ",\"runs\":" RN ",\"cpu_s\":" jn(RCPU) ",\"agents\":["
        for (i = 1; i <= AC; i++) {
            a = ak[i]
            o = o (i > 1 ? "," : "") "{\"agent\":" opt(a) ",\"runs\":" An[a] ",\"cpu_s\":" jn(Acpu[a]) ",\"pct\":" pc1(Acpu[a], RCPU) \
                ",\"exit_known\":" (Aknown[a] + 0) ",\"failed\":" (Afail[a] + 0) ",\"dups\":" (Adup[a] + 0) ",\"dup_cpu_s\":" jn(Adupcpu[a]) \
                ",\"cleaned\":" (Acln[a] + 0) ",\"cleaned_cpu_s\":" jn(Aclncpu[a]) ",\"cleaned_s\":" jn(Aclndur[a]) \
                ",\"wait_runs\":" (Aw[a] + 0) ",\"wait_s\":" jn(Awdur[a]) "}"
        }
        print o "]}"
        return
    }
    vhead("agents")
    if (!RN) { print "no runs in this window"; return }
    th("  " lc("AGENT", 20) " " rc("RUNS", 5) " " rc("CPU-h", 7) " " rc("%", 5) " " rc("FAILED", 7) " " rc("DUPS", 5) " " rc("DUP CPU-h", 9) " " rc("LEFT", 5) " " rc("LEFT h", 7) " " rc("WAIT h", 7))
    for (i = 1; i <= AC; i++) {
        a = ak[i]
        print "  " lc(cut(agentn(a), 20), 20) " " rc(An[a], 5) " " rc(ch(Acpu[a]), 7) " " rc(pct(Acpu[a], RCPU), 5) " " rc(pctn(Afail[a], Aknown[a]), 7) \
            " " rc(Adup[a] + 0, 5) " " rc(ch(Adupcpu[a]), 9) " " rc(Acln[a] + 0, 5) " " rc(sprintf("%.1f", Aclndur[a] / 3600), 7) " " rc(sprintf("%.1f", Awdur[a] / 3600), 7)
    }
    print ""
    s = ""; for (i = 1; i <= nl && i <= 5; i++) { a = lk[i]; s = s (i > 1 ? " \302\267 " : "") agentn(a) " " Acln[a] " (" hrs(Aclndur[a]) ")" }
    printf "%sLEAKS MOST%s       %s\n", b, e, (s != "" ? s : "none")
    s = ""; for (i = 1; i <= nd && i <= 5; i++) { a = dk[i]; s = s (i > 1 ? " \302\267 " : "") agentn(a) " " Adup[a] " (" ch(Adupcpu[a]) " CPU-h)" }
    printf "%sDUPLICATES MOST%s  %s\n", b, e, (s != "" ? s : "none")
}
