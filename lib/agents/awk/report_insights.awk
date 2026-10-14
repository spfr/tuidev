# lib/agents/awk/report_insights.awk — the findings worth acting on, from the
# run ledger, for the summary's Top insights and the menu (insight.txt). Part
# of report.awk's program; needs report_runs and report_fmt.
#
# Each finding has an impact, in CPU seconds, and the findings are ranked by
# it (ties: the order they were found in). Only those of INSIGHT_MIN or more
# count: below 5 CPU-min nothing is worth a line.
#   dup         a command run as a duplicate twice or more: the duplicates' CPU;
#   rerun       a command failed and re-run at once twice or more: the failed
#               runs' CPU;
#   leak        an agent type's runs a cleanup stopped: their CPU, plus a tenth
#               of the hours they were left running (an hour = 6 CPU-min);
#   wait        an agent type's polling loops (not cleaned up) waiting an hour
#               or more: a tenth of those hours;
#   regression  a project's CPU up by half or more, and by 0.25 CPU-h or more,
#               on the window before: the CPU it went up by.

# wword / pword: this window and the one before it, in a sentence.
function wword() { return label == "today" ? "today" : "in " label }
function pword() { return label == "today" ? "yesterday by this hour" : "the " label " before" }

function dup_advice(j) {
    if (j == "test" || j == "build") return "consider a shared " j " cache or serializing them"
    if (j == "server") return "reuse the running server instead of starting another"
    return "run it once and share the result"
}

function ins_add(kind, view, impact, p, a, c, j, text) {
    IC++; IK[IC] = kind; IV[IC] = view; II[IC] = impact
    IP[IC] = p; IA[IC] = a; ICM[IC] = c; IJ[IC] = j; IT[IC] = text
}

# insights — IO[1..IN]: the findings at INSIGHT_MIN or more, the largest
# impact first (indexes into IK IV II IP IA ICM IJ IT).
function insights(   i, k, a, p, j, n, wd, wn, c, q, bj, bd, x, dash, x2) {
    INSIGHT_MIN = 300
    IC = 0; IN = 0; dash = " \342\200\224 "; x2 = "\303\227"
    for (i = 1; i <= GC; i++) {
        k = GO[i]; gsplit(k)
        if (Gdup[k] >= 2) {
            dstats(Gd, k, Gn[k])
            ins_add("dup", "waste", Gdupcpu[k], G_P, "-", G_C, G_J, cut(proj(G_P), 32) ": `" G_C "` " G_J " runs " x2 Gn[k] " " wword() ", " \
                dur(D_MED) " median, " Gdup[k] " duplicates (" cpuw(Gdupcpu[k]) ")" dash dup_advice(G_J))
        }
        if (Grer[k] >= 2)
            ins_add("rerun", "waste", Grercpu[k], G_P, "-", G_C, G_J, cut(proj(G_P), 32) ": `" G_C "` " G_J " failed and was re-run at once " \
                x2 Grer[k] " " wword() " (" cpuw(Grercpu[k]) ")" dash "find the flaky failure, or re-run only what failed")
    }
    for (i = 1; i <= AC; i++) {
        a = AO[i]; n = Acln[a]
        if (n >= 1)
            ins_add("leak", "agents", Aclncpu[a] + Aclndur[a] / 10, "-", a, "-", "-", who(cut(a, 32)) " left " n " " \
                nouns(n, Aclnw[a] == n ? "polling loop" : "run") " running " wword() " (" hrs(Aclndur[a]) \
                (Aclncpu[a] >= 30 ? ", " cpuw(Aclncpu[a]) : "") ")" dash "have them stop what they start, or set AGENTS_AUTO_REAP=1")
        wd = Awdur[a] - Aclnwdur[a]; wn = Aw[a] - Aclnw[a]
        if (wd >= 3600)
            ins_add("wait", "waste", wd / 10, "-", a, "-", "wait", who(cut(a, 32)) " spent " hrs(wd) " in " wn " " nouns(wn, "polling loop") " " \
                wword() dash "wait on a background task's notification instead of a sleep loop")
    }
    for (i = 1; i <= TPC; i++) {
        p = TPO[i]; c = TPcpu[1, p]; q = TPcpu[2, p]
        if (!cpu_regressed(c, q)) continue
        bj = "-"; bd = 0
        for (k = 1; k <= TJC; k++) {
            j = TJO[k]; x = TPJcpu[1, p, j] - TPJcpu[2, p, j]
            if (x > bd) { bd = x; bj = j }
        }
        ins_add("regression", "trends", c - q, p, "-", "-", bj, cut(proj(p), 32) ": " cpuw(c) " " wword() ", " chg(c, q) " on " pword() \
            (bj != "-" ? " (" bj " +" cpuw(bd) ")" : "") dash "see what changed: agents report --view trends")
    }
    for (i = 1; i <= IC; i++) if (II[i] >= INSIGHT_MIN) { IO[++IN] = i; IR[i] = II[i] + (IC - i) / (IC + 1) / 1000 }
    sortk(IR, IO, IN)
}

# insights_text LIM — the summary's block: the top LIM, numbered.
function insights_text(lim,   i) {
    printf "%sTOP INSIGHTS%s\n", b, e
    if (!IN) { printf "  nothing stands out %s(agents report --view runs|waste|trends|agents)%s\n\n", dim, e; return }
    for (i = 1; i <= IN && i <= lim; i++) printf "  %d. %s\n", i, IT[IO[i]]
    printf "  %smore: agents report --view runs|waste|trends|agents%s\n\n", dim, e
}

# insights_json LIM — the top LIM as a JSON array.
function insights_json(lim,   i, k, o) {
    o = ""
    for (i = 1; i <= IN && i <= lim; i++) {
        k = IO[i]
        o = o (i > 1 ? "," : "") sprintf("{\"kind\":%s,\"view\":%s,\"impact_s\":%s,\"project\":%s,\"agent\":%s,\"cmd\":%s,\"job\":%s,\"text\":", \
            js(IK[k]), js(IV[k]), jn(II[k]), opt(IP[k]), opt(IA[k]), opt(ICM[k]), opt(IJ[k])) js(IT[k]) "}"
    }
    return "[" o "]"
}
