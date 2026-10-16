# lib/agents/awk/report_tokens.awk — where agent tokens went, for `agents
# report` (--view tokens, the summary's Tokens line, the token insights and
# the context view's subagents): tokens.tsv, compacts.tsv, limits.tsv and
# the price files. Part of report.awk's program; needs lib_json, lib_sort,
# lib_price and report_fmt.
#
# tokens.tsv (tokens.sh documents it): one row per API message (Claude
# Code; the scanner counts each message id once) or per Codex turn,
#   epoch cli project session agent model in cache_write cache_read out poll cache_write_1h origin
# (11 columns in rows written before 1h cache writes and origins were
# recorded), and before them, for the days before yesterday, one row per
# day and name: the same, then calls (14 columns, epoch the local midnight).
# compacts.tsv: epoch cli project session agent trigger pre_tokens post_tokens
# limits.tsv (limits.sh), whose Codex rows say the plan: epoch cli used_percent window_minutes
#   resets_at [label]
#
# A row counts in the window it was written in (epoch >= start); a window
# that starts before rawb (local midnight yesterday: before it, rows are
# kept per day) counts from the local midnight of its first day (TSTART),
# whole days, so it says the same whether the day rows are rolled up yet or
# not. A total counts every token, cache reads included; the cache hit rate
# is cache_read over the input side (in + cache_write + cache_read). Costs
# are API-equivalent: what the tokens would cost at the price files' list
# prices (lib_price), never what a subscription charges; a model without a
# price is unpriced, never $0. A subagent's worktree counts as its
# repository (pfold); the files keep the name as runs.tsv does.

# --- Reading ----------------------------------------------------------------------

# tokens_load TOKENS COMPACTS LIMITS PRICE_FILES START DIMS — read the files:
#   TL 1 when tokens.tsv has any row at all; TSTART where this window's
#     tokens start; this window's TN model calls, Tin Tcw Tcw1 Tcr Tout Ttot,
#     Tusd (the priced ones' cost), Tunp (tokens of models without a price),
#     Tpoll/TpollN (calls that only waited);
#   by each dimension D in DIMS (of model, cli, agent, project, session,
#     origin: TDIMS[1..TDN]), keyed D SUBSEP name: Dn Din Dcw Dcw1 Dcr Dout
#     Dtot Dusd Dunp, Dss (origin: its sessions); DKN[D] names, DK[D,
#     1..DKN[D]]; with session, a session's project, CLI and origin: SPj SCl
#     SOr; polling by agent: PAt[agent], PAO[1..PAC];
#   compactions (compacts_load) and the Codex plan (limits_load).
# The rows are summed by name first (one key per model, cli, agent,
# project, session, poll and origin), then folded into the dimensions a
# view needs: a month of rows costs one split each.
function tokens_load(tf, cf, lf, pfs, start, dims,   t, w, k, i, kp, ks, ko) {
    prices_load(pfs)
    TL = 0; TN = 0; Tin = Tcw = Tcw1 = Tcr = Tout = Ttot = Tusd = Tunp = Tpoll = TpollN = 0; PAC = 0; KN = 0
    TSTART = start + 0 < rawb + 0 ? start - (start + off) % 86400 : start + 0
    TDN = split(dims, TDIMS, " "); split("", TDON)
    for (i = 1; i <= TDN; i++) TDON[TDIMS[i]] = 1
    ks = ("session" in TDON) || ("origin" in TDON); kp = ks || ("project" in TDON); ko = ("origin" in TDON)
    # Into $0 (FS is a tab): fields split as they are read, the fastest way
    # through a month of rows; the numbers checked in one match.
    while ((getline < tf) > 0) {
        if (NF < 11 || ($1 "," $7 "," $8 "," $9 "," $10 "," (NF >= 14 ? $14 : 0)) !~ /^[0-9]+,[0-9]+,[0-9]+,[0-9]+,[0-9]+,[0-9]+$/) continue
        TL = 1; t = $1 + 0
        if (NF >= 14) { if (t + 43200 < TSTART) continue; w = $14 + 0 }   # a day row: its day is in
        else { if (t < TSTART) continue; w = 1 }
        for (i = 2; i <= 6; i++) if ($i == "") $i = "-"
        # The names no dimension of this view shows are left out of the key
        # (the model prices, the agent tells the polling apart).
        k = $6 SUBSEP $2 SUBSEP $5 SUBSEP (kp ? $3 : "-") SUBSEP (ks ? $4 : "-") SUBSEP ($11 == "1" ? 1 : 0) SUBSEP (ko && NF >= 13 && $13 != "" ? $13 : "-")
        if (!(k in Kn)) KO[++KN] = k
        Kn[k] += w; Ki[k] += $7; Kw[k] += $8; Kr[k] += $9; Ko[k] += $10
        if (NF >= 12 && $12 ~ /^[0-9]+$/) Kh[k] += $12
    }
    close(tf)
    for (i = 1; i <= KN; i++) tokens_fold(KO[i])
    most(SPt, SPj); most(SCt, SCl); most(SOt, SOr)
    compacts_load(cf, start)
    limits_load(lf)
}
# most ARR OUT — OUT[session]: of ARR[session, name] (tokens), the name with
# the most (ties: the first by name): a session's project, CLI and origin,
# whatever order the rows came in ("-" for a session with none).
function most(arr, out,   k, w, bv) {
    for (k in SPj) out[k] = "-"
    for (k in arr) {
        split(k, w, SUBSEP)
        if (!(w[1] in bv) || arr[k] > bv[w[1]] || (arr[k] == bv[w[1]] && w[2] < out[w[1]])) { out[w[1]] = w[2]; bv[w[1]] = arr[k] }
    }
}
# tokens_fold KEY — one summed key into the totals and every dimension.
function tokens_fold(k,   q, kn, ki, kw, kh, kr, ko, t, u, p, d, nm, dk, s, pj) {
    split(k, q, SUBSEP)
    kn = Kn[k]; ki = Ki[k]; kw = Kw[k]; kh = Kh[k] + 0; kr = Kr[k]; ko = Ko[k]; t = ki + kw + kr + ko
    TN += kn; Tin += ki; Tcw += kw; Tcw1 += kh; Tcr += kr; Tout += ko; Ttot += t
    u = -1
    if (PRICED && (p = price_of(q[1]))) u = usd_of(p, ki, kw, kh, kr, ko)
    if (u >= 0) Tusd += u; else Tunp += t
    if (q[6]) {
        Tpoll += t; TpollN += kn
        if (!(q[3] in PAt)) PAO[++PAC] = q[3]
        PAt[q[3]] += t
    }
    if (!(q[4] in PFc)) PFc[q[4]] = pfold(q[4])
    s = q[5]; pj = PFc[q[4]]
    TRow["model"] = q[1]; TRow["cli"] = q[2]; TRow["agent"] = q[3]; TRow["project"] = pj; TRow["session"] = s; TRow["origin"] = q[7]
    for (d = 1; d <= TDN; d++) {
        nm = TRow[TDIMS[d]]; dk = TDIMS[d] SUBSEP nm
        if (!(dk in Dn)) DK[TDIMS[d], ++DKN[TDIMS[d]]] = nm
        Dn[dk] += kn; Din[dk] += ki; Dcw[dk] += kw; Dcw1[dk] += kh; Dcr[dk] += kr; Dout[dk] += ko; Dtot[dk] += t
        if (u >= 0) Dusd[dk] += u; else Dunp[dk] += t
    }
    if ("session" in TDON) {
        SPj[s] = ""; SPt[s, pj] += t; SCt[s, q[2]] += t
        if (q[3] == "main" && q[7] != "-") SOt[s, q[7]] += t
    }
    dk = q[7] SUBSEP s
    if (("origin" in TDON) && !(dk in Dssn)) { Dssn[dk] = 1; Dss["origin" SUBSEP q[7]]++ }
}

# compacts_load FILE START — this window's CN compactions, CAUTO and CMAN of
# them auto and manual, CPRE their tokens before; by session (project SUBSEP
# session SUBSEP cli): CSO[1..CSC], CSn CSauto CSpre, CSautopre (the auto
# ones' tokens before).
function compacts_load(cf, start,   ln, f, k) {
    CN = CAUTO = CMAN = CPRE = 0; CSC = 0
    while ((getline ln < cf) > 0) {
        if (split(ln, f, "\t") < 8 || f[1] !~ /^[0-9]+$/ || f[1] + 0 < start) continue
        if (f[7] !~ /^[0-9]+$/) f[7] = 0
        CN++; CPRE += f[7]
        if (f[6] == "auto") CAUTO++; else if (f[6] == "manual") CMAN++
        k = (f[3] == "" ? "-" : pfold(f[3])) SUBSEP (f[4] == "" ? "-" : f[4]) SUBSEP f[2]
        if (!(k in CSn)) CSO[++CSC] = k
        CSn[k]++; CSpre[k] += f[7]
        if (f[6] == "auto") { CSauto[k]++; CSautopre[k] += f[7] }
    }
    close(cf)
}

# limits_load FILE — LIM 1 with the latest Codex reading (its shortest window): Lat (when it was
# read), Lused (%), Lwin (minutes), Lreset (epoch).
function limits_load(lf,   ln, f) {
    LIM = 0
    while ((getline ln < lf) > 0) {
        if (split(ln, f, "\t") < 5 || f[1] !~ /^[0-9]+$/ || f[2] != "codex" || f[3] !~ /^[0-9]+([.][0-9]+)?$/) continue
        if (f[4] !~ /^[0-9]+$/ || f[5] !~ /^[0-9]+$/) continue
        # The newest reading; of its windows, the shortest (Codex's primary).
        if (LIM && (f[1] + 0 < Lat || (f[1] + 0 == Lat && f[4] + 0 >= Lwin))) continue
        LIM = 1; Lat = f[1] + 0; Lused = f[3] + 0; Lwin = f[4] + 0; Lreset = f[5] + 0
    }
    close(lf)
}

# --- Numbers for people ---------------------------------------------------------

# tk N — a token count: 950, 64.2k, 640k, 12.4M, 1.2B (whole above 100 of a unit).
function tk(n,   u, s, v) {
    if (n < 1000) return sprintf("%d", n)
    if (n < 999500) { u = 1e3; s = "k" } else if (n < 999500000) { u = 1e6; s = "M" } else { u = 1e9; s = "B" }
    v = n / u
    if (v < 99.95) { v = sprintf("%.1f", v); sub(/[.]0$/, "", v); return v s }
    return sprintf("%d", v + 0.5) s
}
# hitp CR IN CW — the cache hit rate as "94%", or "-" with no input.
function hitp(cr, i, cw) { return pctn(cr, i + cw + cr) }
function hitn(cr, i, cw) { return i + cw + cr > 0 ? 100 * cr / (i + cw + cr) : 0 }
# usd X — dollars: $18.20, <$0.01.
function usd(x) { return x > 0 && x < 0.005 ? "<$0.01" : sprintf("$%.2f", x) }
# jbig / jusd: a JSON integer of any size, a JSON amount (null below 0).
function jbig(x) { return sprintf("%.0f", x) }
function jusd(x) { return x < 0 ? "null" : sprintf("%.2f", x) }
# hm T — the local clock time of epoch T, with the weekday when it is not
# today, and the date instead when it is 6 days or more away (a weekday
# would then name the wrong week).
function hm(t,   s, d, n) {
    d = int((t + off) / 86400); n = int((now + off) / 86400)
    if (d - n >= 6 || n - d >= 6) return dayhm(t)
    s = sprintf("%02d:%02d", int(((t + off) % 86400) / 3600), int(((t + off) % 3600) / 60))
    if (d != n) s = substr("ThuFriSatSunMonTueWed", (d % 7) * 3 + 1, 3) " " s
    return s
}
# wmin M — a window in minutes as 5h, 7d, 90m.
function wmin(m) { return m > 0 && m % 1440 == 0 ? (m / 1440) "d" : m > 0 && m % 60 == 0 ? (m / 60) "h" : m "m" }

# tsorted D — TS[1..n] the names of dimension D, the most tokens first (ties
# by name); returns n.
function tsorted(d,   i, n) {
    split("", TS); split("", TSV)
    n = DKN[d] + 0
    for (i = 1; i <= n; i++) { TS[i] = DK[d, i]; TSV[TS[i]] = Dtot[d SUBSEP TS[i]] }
    sortk(TSV, TS, n)
    return n
}
# dusd K — a row's cost: "unpriced" when none of its tokens has a price.
function dusd(k) { return Dtot[k] > Dunp[k] ? usd(Dusd[k]) : "unpriced" }
# tname D NAME — a name as the tables show it: a session as its project
# and the start of its id.
function tname(d, s) {
    if (d == "session") return (s in SPj ? proj(SPj[s]) " " : "") substr(s, 1, 8)
    return d == "project" ? proj(s) : d == "agent" ? agentn(s) : d == "origin" ? (s == "-" ? "(unknown)" : s) : s
}
# unpriced_models — how many models have no price at all.
function unpriced_models(   i, k, n) {
    n = 0
    for (i = 1; i <= DKN["model"]; i++) { k = "model" SUBSEP DK["model", i]; if (Dtot[k] == Dunp[k]) n++ }
    return n
}
# costed — show costs: there are prices, and some of this window's tokens have one.
function costed() { return PRICED && Ttot > Tunp }

# --- The view -----------------------------------------------------------------------

# view_tokens — totals, then by model, CLI, agent type, project, session and
# origin; polling, compactions and the Codex plan's headroom.
function view_tokens(   o, d, i, n, s, a, w) {
    if (json) {
        o = jhead("tokens") ",\"data\":" jb(TL) ",\"priced\":" jb(PRICED) ",\"tokens_since\":" TSTART \
            ",\"prices\":" (PRICED ? "{\"basis\":\"api_list\",\"as_of\":" opt(PASOF) "}" : "null") \
            ",\"totals\":" jtrow(Ttot, TN, Tin, Tcw, Tcw1, Tcr, Tout, costed() ? Tusd : -1, Tunp)
        for (d = 1; d <= TDN; d++) o = o ",\"" TDIMS[d] "s\":" jtdim(TDIMS[d])
        o = o ",\"polling\":{\"calls\":" TpollN ",\"tokens\":" jbig(Tpoll) ",\"pct\":" pc1(Tpoll, Ttot) ",\"agents\":["
        n = polling_sorted()
        for (i = 1; i <= n; i++) o = o (i > 1 ? "," : "") "{\"agent\":" opt(PS[i]) ",\"tokens\":" jbig(PAt[PS[i]]) "}"
        o = o "]},\"compactions\":{\"count\":" CN ",\"auto\":" CAUTO ",\"manual\":" CMAN ",\"avg_pre_tokens\":" jbig(CN ? CPRE / CN : 0) ",\"sessions\":["
        n = compacts_sorted()
        for (i = 1; i <= n; i++) {
            split(CS[i], w, SUBSEP)
            o = o (i > 1 ? "," : "") "{\"cli\":" js(w[3]) ",\"project\":" opt(w[1]) ",\"session\":" opt(w[2]) ",\"count\":" CSn[CS[i]] ",\"auto\":" (CSauto[CS[i]] + 0) ",\"pre_tokens\":" jbig(CSpre[CS[i]]) "}"
        }
        o = o "]},\"codex_limits\":"
        if (LIM) o = o "{\"as_of\":" Lat ",\"used_percent\":" Lused ",\"window_minutes\":" Lwin ",\"resets_at\":" Lreset "}"
        else o = o "null"
        print o "}"
        return
    }
    vhead("tokens")
    if (!TL) {
        if (hist != 1) print "history is off (AGENTS_HISTORY=0): no tokens are recorded"
        else print "no token data yet (tokens.tsv): each agents sample adds what the Claude Code and Codex transcripts logged since the last"
        if (LIM) { print ""; codex_plan() }
        return
    }
    if (!TN) print "no tokens in this window"
    else {
        printf "%sTOKENS%s %s in %d model %s \302\267 %s cache hits%s\n", b, e, tk(Ttot), TN, nouns(TN, "call"), hitp(Tcr, Tin, Tcw), \
            (costed() ? " \302\267 " usd(Tusd) " API-equivalent" : "")
        printf "  in %s \302\267 cache write %s%s \302\267 cache read %s \302\267 out %s\n\n", tk(Tin), tk(Tcw), (Tcw1 > 0 ? " (1h " tk(Tcw1) ")" : ""), tk(Tcr), tk(Tout)
        ttable_tokens("model", "MODEL", 10)
        ttable_tokens("cli", "CLI", 10)
        ttable_tokens("agent", "AGENT", 10)
        ttable_tokens("project", "PROJECT", 8)
        ttable_tokens("session", "SESSION", 8)
        ttable_origins()
        printf "%sPOLLING%s  %s\n", b, e, (TpollN ? tk(Tpoll) " tokens (" pct(Tpoll, Ttot) ") in " TpollN " model " nouns(TpollN, "call") " that only waited" : "none")
        n = polling_sorted()
        if (n) {
            s = ""; for (i = 1; i <= n && i <= 5; i++) { a = PS[i]; s = s (i > 1 ? " \302\267 " : "") agentn(a) " " tk(PAt[a]) }
            print "  by agent    " s
        }
    }
    printf "%sCOMPACTIONS%s  %s\n", b, e, (CN ? CN " \302\267 " CAUTO " auto, " CMAN " manual \302\267 " tk(CPRE / CN) " tokens before, on average" : "none")
    n = compacts_sorted()
    if (n) {
        s = ""
        for (i = 1; i <= n && i <= 3; i++) { split(CS[i], w, SUBSEP); s = s (i > 1 ? " \302\267 " : "") cut(proj(w[1]), 20) " " CSn[CS[i]] " (" w[3] " " substr(w[2], 1, 8) ")" }
        print "  most        " s
    }
    if (LIM) codex_plan()
    if (TN && (costed() || TSTART < start)) print ""
    if (TN && costed()) {
        n = unpriced_models()
        th("API $: what these tokens would cost at API list prices" (PASOF != "" ? " (as of " PASOF ")" : "") \
            ", not what a subscription charges" (n ? "; " n " " nouns(n, "model") " unpriced, left out" : ""))
    }
    if (TN && TSTART < start) th("tokens before yesterday are kept by day: this window counts them from " dayhm(TSTART))
}
# codex_plan — the Codex plan's headroom, from its latest reading.
function codex_plan() {
    if (Lreset > 0 && Lreset <= now)
        printf "%sCODEX PLAN%s  the %s window has reset since the last reading (%d%% used at %s)\n", b, e, wmin(Lwin), Lused + 0.5, hm(Lat)
    else
        printf "%sCODEX PLAN%s  %d%% of the %s window used \302\267 resets %s %s(as of %s)%s\n", b, e, Lused + 0.5, wmin(Lwin), hm(Lreset), dim, hm(Lat), e
}
# ttable_tokens D TITLE LIM — one breakdown, at most LIM rows.
function ttable_tokens(d, title, lim,   n, i, k, nm) {
    n = tsorted(d)
    th("  " lc(title, 22) " " rc("TOKENS", 7) " " rc("%", 5) " " rc("IN", 7) " " rc("C.WRITE", 8) " " rc("C.READ", 7) " " rc("OUT", 7) " " rc("HIT", 5) (PRICED ? " " rc("API $", 9) : ""))
    for (i = 1; i <= n && i <= lim; i++) {
        nm = TS[i]; k = d SUBSEP nm
        print "  " lc(cut(tname(d, nm), 22), 22) " " rc(tk(Dtot[k]), 7) " " rc(pct(Dtot[k], Ttot), 5) " " rc(tk(Din[k]), 7) " " rc(tk(Dcw[k]), 8) \
            " " rc(tk(Dcr[k]), 7) " " rc(tk(Dout[k]), 7) " " rc(hitp(Dcr[k], Din[k], Dcw[k]), 5) (PRICED ? " " rc(dusd(k), 9) : "")
    }
    if (n > lim) th("  ... " (n - lim) " more (agents report --view tokens --json)")
    print ""
}
# ttable_origins — who drove the tokens: you, headless, subagents, forks.
function ttable_origins(   n, i, k) {
    n = tsorted("origin")
    th("  " lc("ORIGIN", 22) " " rc("SESSIONS", 8) " " rc("TOKENS", 7) " " rc("%", 5) (PRICED ? " " rc("API $", 9) : ""))
    for (i = 1; i <= n; i++) {
        k = "origin" SUBSEP TS[i]
        print "  " lc(tname("origin", TS[i]), 22) " " rc(Dss[k] + 0, 8) " " rc(tk(Dtot[k]), 7) " " rc(pct(Dtot[k], Ttot), 5) (PRICED ? " " rc(dusd(k), 9) : "")
    }
    print ""
}
# polling_sorted — PS[1..n], the agent types that polled, the most tokens first.
function polling_sorted(   i) {
    split("", PS)
    for (i = 1; i <= PAC; i++) PS[i] = PAO[i]
    sortk(PAt, PS, PAC)
    return PAC
}
# compacts_sorted — CS[1..n], sessions by compactions, then tokens before.
function compacts_sorted(   i, v) {
    split("", CS)
    for (i = 1; i <= CSC; i++) { CS[i] = CSO[i]; v[CS[i]] = CSn[CS[i]] + CSpre[CS[i]] / 1e12 }
    sortk(v, CS, CSC)
    return CSC
}
function jtrow(t, n, i, cw, cw1, cr, o, u, unp) {
    return "{\"calls\":" n ",\"in\":" jbig(i) ",\"cache_write\":" jbig(cw) ",\"cache_write_1h\":" jbig(cw1) ",\"cache_read\":" jbig(cr) ",\"out\":" jbig(o) ",\"total\":" jbig(t) \
        ",\"cache_hit_pct\":" pc1(cr, i + cw + cr) ",\"est_usd\":" jusd(u) ",\"unpriced_tokens\":" (PRICED ? jbig(unp) : "null") "}"
}
# jtdim D — dimension D as a JSON array, every name, the most tokens first;
# a session with its project, CLI and origin, an origin with its sessions.
function jtdim(d,   n, i, k, o, r, x) {
    n = tsorted(d); o = ""
    for (i = 1; i <= n; i++) {
        k = d SUBSEP TS[i]
        r = jtrow(Dtot[k], Dn[k], Din[k], Dcw[k], Dcw1[k], Dcr[k], Dout[k], PRICED ? (Dtot[k] > Dunp[k] ? Dusd[k] : -1) : -1, Dunp[k])
        x = d == "session" ? ",\"project\":" opt(SPj[TS[i]]) ",\"cli\":" js(SCl[TS[i]]) ",\"origin\":" opt(SOr[TS[i]]) \
            : d == "origin" ? ",\"sessions\":" (Dss[k] + 0) : ""
        o = o (i > 1 ? "," : "") "{\"" d "\":" (d == "cli" || d == "model" ? js(TS[i]) : opt(TS[i])) x ",\"pct\":" pc1(Dtot[k], Ttot) "," substr(r, 2)
    }
    return "[" o "]"
}

# --- The summary's line ----------------------------------------------------------

# tokens_text — the summary's Tokens line (nothing without token data).
function tokens_text() {
    if (!TL) return
    printf "%sTOKENS%s  %s", b, e, (TN ? tk(Ttot) " \302\267 " hitp(Tcr, Tin, Tcw) " cache hits \302\267 " pct(Tpoll, Ttot) " polling" : "none in this window")
    if (TN && costed()) printf " \302\267 %s API-equivalent", usd(Tusd)
    if (CN) printf " \302\267 %d %s", CN, nouns(CN, "compaction")
    printf "\n%s  by model, agent, session and origin: agents report --view tokens%s\n\n", dim, e
}
function tokens_json() {
    if (!TL) return "null"
    return "{\"calls\":" TN ",\"total\":" jbig(Ttot) ",\"in\":" jbig(Tin) ",\"cache_write\":" jbig(Tcw) ",\"cache_write_1h\":" jbig(Tcw1) ",\"cache_read\":" jbig(Tcr) ",\"out\":" jbig(Tout) \
        ",\"cache_hit_pct\":" pc1(Tcr, Tin + Tcw + Tcr) ",\"poll_tokens\":" jbig(Tpoll) ",\"poll_pct\":" pc1(Tpoll, Ttot) \
        ",\"est_usd\":" (costed() ? jusd(Tusd) : "null") ",\"compactions\":" CN "}"
}
