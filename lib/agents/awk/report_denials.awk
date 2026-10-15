# lib/agents/awk/report_denials.awk — tool calls that were denied, for
# `agents report --view denials` and the insights: by who denied them, the
# classifier's reason, the command or tool, agent type and project, with a
# hint for the ones denied again and again. Part of report.awk's program;
# needs lib_json, lib_sort and report_fmt.
#
# denials.tsv, one row per denied tool call:
#   epoch cli project session agent tool by reason subject
# by: classifier (Claude Code's auto-mode classifier; reason is its tag),
# safety (a built-in safety check) or user (you said no); subject is never an
# argument: a command and its subcommand (git push, npm install), else the
# tool (Edit; a host for WebFetch). A subagent's worktree counts as its
# repository (pfold).

# denials_load FILE START — DL 1 when denials.tsv has any row at all; this
# window's DN denials, DB[by] of them by each; by subject (subject SUBSEP
# tool): DSO[1..DSC], DSn, DSb[k, by], DSr[k, reason] (the classifier's) with
# DSRO[k, 1..DSRC[k]]; reasons DRO[1..DRC], DRn; agents DAO[1..DAC], DAn;
# projects DPO[1..DPC], DPn.
function denials_load(df, start,   ln, f, k, by, r, a, p) {
    DL = 0; DN = 0; DSC = DRC = DAC = DPC = 0
    while ((getline ln < df) > 0) {
        if (split(ln, f, "\t") < 9 || f[1] !~ /^[0-9]+$/) continue
        by = f[7]
        if (by != "classifier" && by != "safety" && by != "user") continue
        DL = 1
        if (f[1] + 0 < start) continue
        DN++; DB[by]++
        r = f[8] == "" ? "-" : f[8]; a = f[5] == "" ? "-" : f[5]; p = f[3] == "" ? "-" : pfold(f[3])
        k = (f[9] == "" ? (f[6] == "" ? "-" : f[6]) : f[9]) SUBSEP (f[6] == "" ? "-" : f[6])
        if (!(k in DSn)) DSO[++DSC] = k
        DSn[k]++; DSb[k, by]++
        if (by == "classifier" && r != "-") {
            if (!(r in DRn)) DRO[++DRC] = r
            DRn[r]++
            if (!((k, r) in DSr)) DSRO[k, ++DSRC[k]] = r
            DSr[k, r]++
        }
        if (!(a in DAn)) DAO[++DAC] = a
        DAn[a]++
        if (!(p in DPn)) DPO[++DPC] = p
        DPn[p]++
    }
    close(df)
}

# dreason K — the classifier's most frequent reason for subject K, or "-".
function dreason(k,   i, r, best) {
    best = "-"
    for (i = 1; i <= DSRC[k]; i++) {
        r = DSRO[k, i]
        if (best == "-" || DSr[k, r] > DSr[k, best] || (DSr[k, r] == DSr[k, best] && r < best)) best = r
    }
    return best
}
function dsplit(k) { split(k, DW, SUBSEP); D_S = DW[1]; D_T = DW[2] }
# dsubj K — a subject as a sentence names it: `git push`, `WebFetch example.com`.
function dsubj(k) { dsplit(k); return "`" (D_T == "Bash" || D_T == "-" || D_T == D_S ? D_S : D_T " " D_S) "`" }
# deny_hint K BY N WW — what a subject denied N times by BY suggests.
function deny_hint(k, by, n, ww,   r) {
    if (by == "user") return dsubj(k) " denied \303\227" n " by you" ww " \342\200\224 consider an allow rule, or an instruction not to try it"
    r = dreason(k)
    return dsubj(k) " denied \303\227" n " by the classifier" (r != "-" ? " [" r "]" : "") ww \
        " \342\200\224 expected: auto mode holds it for you; run it yourself, or allow it if it is routine"
}
# denials_sorted — DS[1..DSC] subjects, most denied first; DH[1..n] the
# repeated user and classifier ones (subject SUBSEP tool SUBSEP by), at least
# DENY_HINT_MIN each, most first; returns n.
function denials_sorted(   i, k, n, v, hv, by, j) {
    DENY_HINT_MIN = 2
    split("", DS); split("", DH)
    for (i = 1; i <= DSC; i++) { DS[i] = DSO[i]; v[DS[i]] = DSn[DS[i]] }
    sortk(v, DS, DSC)
    n = 0; split("user classifier", by, " ")
    for (i = 1; i <= DSC; i++) for (j = 1; j <= 2; j++) {
        k = DSO[i]
        if (DSb[k, by[j]] >= DENY_HINT_MIN) { DH[++n] = k SUBSEP by[j]; hv[DH[n]] = DSb[k, by[j]] }
    }
    sortk(hv, DH, n)
    return n
}
# dhint_split H — DH_K (subject SUBSEP tool) and DH_B (who) of a hint key.
function dhint_split(hk,   w) { split(hk, w, SUBSEP); DH_K = w[1] SUBSEP w[2]; DH_B = w[3] }
# dby — who denied, in words, those that did.
function dby(   s) {
    s = ""
    if (DB["classifier"]) s = s " \302\267 " DB["classifier"] " by the classifier"
    if (DB["user"]) s = s " \302\267 " DB["user"] " by you"
    if (DB["safety"]) s = s " \302\267 " DB["safety"] " by a safety check"
    return s
}
# dline KEYS N COUNTS LIM WHAT — "a 3 · b 1", names as the tables show them.
function dline(keys, n, cnt, lim, what,   i, o) {
    o = ""
    for (i = 1; i <= n && i <= lim; i++) o = o (i > 1 ? " \302\267 " : "") (what == "agent" ? agentn(keys[i]) : what == "project" ? proj(keys[i]) : keys[i]) " " cnt[keys[i]]
    return o
}
function jdlist(keys, n, cnt, name, isopt,   i, o) {
    o = ""
    for (i = 1; i <= n; i++) o = o (i > 1 ? "," : "") "{\"" name "\":" (isopt ? opt(keys[i]) : js(keys[i])) ",\"count\":" cnt[keys[i]] "}"
    return "[" o "]"
}

# view_denials — who denied what, and what the repeated ones suggest.
function view_denials(   n, i, k, o, ak, pk, rk) {
    n = denials_sorted()
    for (i = 1; i <= DAC; i++) ak[i] = DAO[i]
    for (i = 1; i <= DPC; i++) pk[i] = DPO[i]
    for (i = 1; i <= DRC; i++) rk[i] = DRO[i]
    sortk(DAn, ak, DAC); sortk(DPn, pk, DPC); sortk(DRn, rk, DRC)
    if (json) {
        o = jhead("denials") ",\"data\":" jb(DL) ",\"denials\":" DN ",\"by\":{\"classifier\":" (DB["classifier"] + 0) ",\"user\":" (DB["user"] + 0) ",\"safety\":" (DB["safety"] + 0) "}"
        o = o ",\"reasons\":" jdlist(rk, DRC, DRn, "reason", 0) ",\"subjects\":["
        for (i = 1; i <= DSC; i++) {
            k = DS[i]; dsplit(k)
            o = o (i > 1 ? "," : "") "{\"subject\":" js(D_S) ",\"tool\":" opt(D_T) ",\"count\":" DSn[k] ",\"classifier\":" (DSb[k, "classifier"] + 0) \
                ",\"user\":" (DSb[k, "user"] + 0) ",\"safety\":" (DSb[k, "safety"] + 0) ",\"reason\":" opt(dreason(k)) "}"
        }
        o = o "],\"agents\":" jdlist(ak, DAC, DAn, "agent", 1) ",\"projects\":" jdlist(pk, DPC, DPn, "project", 1) ",\"hints\":["
        for (i = 1; i <= n; i++) {
            dhint_split(DH[i]); dsplit(DH_K)
            o = o (i > 1 ? "," : "") "{\"subject\":" js(D_S) ",\"tool\":" opt(D_T) ",\"by\":" js(DH_B) ",\"count\":" DSb[DH_K, DH_B] \
                ",\"reason\":" (DH_B == "classifier" ? opt(dreason(DH_K)) : "null") ",\"text\":" js(deny_hint(DH_K, DH_B, DSb[DH_K, DH_B], "")) "}"
        }
        print o "]}"
        return
    }
    vhead("denials")
    if (!DL) {
        if (hist != 1) print "history is off (AGENTS_HISTORY=0): no denials are recorded"
        else print "no denials recorded yet (denials.tsv): each agents sample adds the tool calls the Claude Code transcripts show denied"
        return
    }
    if (!DN) { print "no denials in this window"; return }
    printf "%sDENIED%s %d%s\n\n", b, e, DN, dby()
    th("  " lc("SUBJECT", 22) " " lc("TOOL", 10) " " rc("DENIED", 7) " " rc("CLASSIFIER", 11) " " rc("YOU", 5) " " rc("SAFETY", 6) "  REASON")
    for (i = 1; i <= DSC && i <= 10; i++) {
        k = DS[i]; dsplit(k)
        print "  " lc(cut(D_S, 22), 22) " " lc(cut(D_T, 10), 10) " " rc(DSn[k], 7) " " rc(DSb[k, "classifier"] + 0, 11) " " rc(DSb[k, "user"] + 0, 5) \
            " " rc(DSb[k, "safety"] + 0, 6) "  " dreason(k)
    }
    if (DSC > 10) th("  ... " (DSC - 10) " more (agents report --view denials --json)")
    print ""
    if (DRC) printf "%sREASONS%s      %s\n", b, e, dline(rk, DRC, DRn, 5, "reason")
    printf "%sBY AGENT%s     %s\n", b, e, dline(ak, DAC, DAn, 5, "agent")
    printf "%sBY PROJECT%s   %s\n", b, e, dline(pk, DPC, DPn, 5, "project")
    if (!n) return
    print ""
    printf "%sREPEATED%s\n", b, e
    for (i = 1; i <= n && i <= 5; i++) { dhint_split(DH[i]); print "  " deny_hint(DH_K, DH_B, DSb[DH_K, DH_B], "") }
}

# denials_text — the summary's Denials line (nothing without denial data).
function denials_text() {
    if (!DL) return
    printf "%sDENIALS%s  %s\n", b, e, (DN ? DN dby() : "none in this window")
    printf "%s  by command and what to try: agents report --view denials%s\n\n", dim, e
}
function denials_json() {
    if (!DL) return "null"
    return "{\"count\":" DN ",\"classifier\":" (DB["classifier"] + 0) ",\"user\":" (DB["user"] + 0) ",\"safety\":" (DB["safety"] + 0) "}"
}
