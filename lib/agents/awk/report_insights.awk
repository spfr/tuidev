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
# Tokens (report_tokens) and denials (report_denials) are not CPU: each of
# these counts once past its own threshold, and ranks by the tokens at stake
# (TOKENS_PER_S of them weigh as a CPU second; a denial as DENY_S), never
# below INSIGHT_MIN:
#   cache       a CLI's cache hit rate below CACHE_LOW %, on TOKENS_MIN input
#               tokens or more: the tokens a CACHE_LOW % rate would have read
#               from the cache;
#   poll        model calls that only waited, above POLL_HIGH % of all
#               tokens, on TOKENS_MIN or more: those tokens;
#   compact     a session whose context filled up and compacted on its own
#               (trigger auto) COMPACT_MANY times or more: the tokens before
#               those compactions (a /compact you ran is not a finding);
#   denied      a command or tool you denied DENY_MANY times or more: DENY_S
#               a denial.

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
    CACHE_LOW = 70; POLL_HIGH = 5; TOKENS_MIN = 1000000; COMPACT_MANY = 3; DENY_MANY = 3
    TOKENS_PER_S = 1000; DENY_S = 60
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
    token_insights(dash, x2)
    for (i = 1; i <= IC; i++) if (II[i] >= INSIGHT_MIN) { IO[++IN] = i; IR[i] = II[i] + (IC - i) / (IC + 1) / 1000 }
    sortk(IR, IO, IN)
}

# token_insights DASH TIMES — the cache, poll, compact and denied findings.
function token_insights(dash, x2,   i, k, c, n, m, t, w, s) {
    for (i = 1; i <= DKN["cli"]; i++) {
        c = DK["cli", i]; k = "cli" SUBSEP c; t = Din[k] + Dcw[k] + Dcr[k]
        if (t >= TOKENS_MIN && Dcr[k] * 100 < CACHE_LOW * t)
            ins_add("cache", "tokens", tok_impact(CACHE_LOW * t / 100 - Dcr[k]), "-", "-", "-", "-", c ": " int(hitn(Dcr[k], Din[k], Dcw[k])) "% cache hits " \
                wword() " on " tk(t) " input tokens" dash "long sessions on one model, with stable instructions, keep the prompt cache warm")
    }
    if (Ttot >= TOKENS_MIN && Tpoll * 100 > POLL_HIGH * Ttot) {
        n = polling_sorted()
        ins_add("poll", "tokens", tok_impact(Tpoll), "-", PS[1], "-", "wait", pct(Tpoll, Ttot) " of tokens (" tk(Tpoll) ") went to polling " \
            wword() " (most: " (PS[1] == "-" ? "sessions of unknown type" : PS[1] == "main" ? "main sessions" : PS[1] " subagents") ")" dash "wait on a background task's notification instead of polling")
    }
    m = 0; t = 0
    for (i = 1; i <= CSC; i++) {
        c = CSO[i]
        if (CSauto[c] < COMPACT_MANY) continue
        m++; t += CSautopre[c]
        if (m == 1 || CSauto[c] > CSauto[k] || (CSauto[c] == CSauto[k] && (CSautopre[c] > CSautopre[k] || (CSautopre[c] == CSautopre[k] && c < k)))) k = c
    }
    if (m) {
        split(k, w, SUBSEP)
        s = cut(proj(w[1]), 32) ": a session filled its context and compacted " x2 CSauto[k] " " wword()
        if (m > 1) s = s ", and " (m - 1) " more " nouns(m - 1, "session") " " x2 COMPACT_MANY " or more"
        ins_add("compact", "tokens", tok_impact(t), w[1], "-", "-", "-", s dash "hand long work to subagents, or start a fresh session per task")
    }
    for (i = 1; i <= DSC; i++) {
        k = DSO[i]; n = DSb[k, "user"]
        if (n >= DENY_MANY) {
            dsplit(k)
            ins_add("denied", "denials", n * DENY_S < INSIGHT_MIN ? INSIGHT_MIN : n * DENY_S, "-", "-", D_S, "-", deny_hint(k, "user", n, " " wword()))
        }
    }
}
# tok_impact TOKENS — tokens at stake as an impact, at least INSIGHT_MIN.
function tok_impact(t) { t = t / TOKENS_PER_S; return t < INSIGHT_MIN ? INSIGHT_MIN : t }

# insights_text LIM — the summary's block: the top LIM, numbered.
function insights_text(lim,   i) {
    printf "%sTOP INSIGHTS%s\n", b, e
    if (!IN) { printf "  nothing stands out %s(agents report --view runs|waste|trends|agents|tokens|denials)%s\n\n", dim, e; return }
    for (i = 1; i <= IN && i <= lim; i++) printf "  %d. %s\n", i, IT[IO[i]]
    printf "  %smore: agents report --view runs|waste|trends|agents|tokens|denials%s\n\n", dim, e
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
