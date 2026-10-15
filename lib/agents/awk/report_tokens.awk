# lib/agents/awk/report_tokens.awk — where agent tokens went, for `agents
# report` (--view tokens, the summary's Tokens line and the token insights):
# tokens.tsv, compacts.tsv, limits.tsv and, when you keep one, a price file.
# Part of report.awk's program; needs lib_json, lib_sort and report_fmt.
#
# tokens.tsv, one row per API message (Claude Code; the scanner counts each
# message id once) or per Codex turn:
#   epoch cli project session agent model in cache_write cache_read out poll
# compacts.tsv: epoch cli project session agent trigger pre_tokens post_tokens
# limits.tsv, the latest Codex reading: epoch cli used_percent window_minutes
#   resets_at
# The price file (AGENTS_PRICES; yours, none ship), USD per million tokens:
#   model_prefix in cache_write cache_read out
# one model per line, # comments; the longest prefix of a model wins, and of
# a prefix listed twice the later line.
#
# A row counts in the window it was written in (epoch >= start). A total
# counts every token, cache reads included; the cache hit rate is cache_read
# over the input side (in + cache_write + cache_read).

# --- Reading ----------------------------------------------------------------------

# prices_load FILE — PN prices: PP[i] the prefix, Pin Pcw Pcr Pout per million
# tokens; PRICED when there is one. A malformed line is reported and ignored.
function prices_load(pf,   ln, f, n, nr) {
    PN = 0; PRICED = 0
    if (pf == "") return
    while ((getline ln < pf) > 0) {
        nr++
        sub(/[ \t]+#.*$/, "", ln); sub(/^[ \t]+/, "", ln); sub(/[ \t\r]+$/, "", ln)
        if (ln == "" || ln ~ /^#/) continue
        n = split(ln, f, /[ \t]+/)
        if (n != 5 || f[1] !~ /^[A-Za-z0-9][A-Za-z0-9._:\/@+-]*$/ || !usdnum(f[2]) || !usdnum(f[3]) || !usdnum(f[4]) || !usdnum(f[5])) {
            printf "agents: %s:%d: not MODEL_PREFIX IN CACHE_WRITE CACHE_READ OUT (USD per million tokens), ignored\n", pf, nr > "/dev/stderr"
            continue
        }
        PN++; PP[PN] = f[1]; Pin[PN] = f[2] + 0; Pcw[PN] = f[3] + 0; Pcr[PN] = f[4] + 0; Pout[PN] = f[5] + 0
    }
    close(pf)
    PRICED = PN > 0
}
function usdnum(s) { return s ~ /^[0-9]+([.][0-9]+)?$/ || s ~ /^[.][0-9]+$/ }
# price_of MODEL — the index of its price (the longest prefix), 0 for none.
function price_of(m,   i, best, bl) {
    if (m in PMx) return PMx[m]
    best = 0; bl = 0
    for (i = 1; i <= PN; i++) if (length(PP[i]) >= bl && substr(m, 1, length(PP[i])) == PP[i]) { best = i; bl = length(PP[i]) }
    PMx[m] = best
    return best
}

# tokens_load TOKENS COMPACTS LIMITS PRICES START — read the three files:
#   TL 1 when tokens.tsv has any row at all; this window's TN model calls,
#     Tin Tcw Tcr Tout Ttot, Tusd (the priced ones' estimate), Tunp (tokens of
#     models without a price), Tpoll/TpollN (calls that only waited);
#   by dimension D (model, cli, agent, project), keyed D SUBSEP name: Dn Din
#     Dcw Dcr Dout Dtot Dusd Dunp; DKN[D] names, DK[D, 1..DKN[D]] first seen
#     first; polling by agent: PAt[agent], PAO[1..PAC];
#   compactions (compacts_load) and the Codex plan (limits_load).
function tokens_load(tf, cf, lf, pf, start,   ln, f, d, k, i, t, u, p, nm, poll) {
    prices_load(pf)
    TL = 0; TN = 0; Tin = Tcw = Tcr = Tout = Ttot = Tusd = Tunp = Tpoll = TpollN = 0; PAC = 0
    split("model cli agent project", TDIMS, " ")
    while ((getline ln < tf) > 0) {
        if (split(ln, f, "\t") < 11 || f[1] !~ /^[0-9]+$/) continue
        if (f[7] !~ /^[0-9]+$/ || f[8] !~ /^[0-9]+$/ || f[9] !~ /^[0-9]+$/ || f[10] !~ /^[0-9]+$/) continue
        TL = 1
        if (f[1] + 0 < start) continue
        for (i = 2; i <= 6; i++) if (f[i] == "") f[i] = "-"
        t = f[7] + f[8] + f[9] + f[10]; poll = f[11] == "1"
        TN++; Tin += f[7]; Tcw += f[8]; Tcr += f[9]; Tout += f[10]; Ttot += t
        u = -1
        if (PRICED && (p = price_of(f[6]))) u = (f[7] * Pin[p] + f[8] * Pcw[p] + f[9] * Pcr[p] + f[10] * Pout[p]) / 1e6
        if (u >= 0) Tusd += u; else Tunp += t
        if (poll) {
            Tpoll += t; TpollN++
            if (!(f[5] in PAt)) PAO[++PAC] = f[5]
            PAt[f[5]] += t
        }
        TRow[2] = f[6]; TRow[3] = f[2]; TRow[4] = f[5]; TRow[5] = f[3]
        for (d = 1; d <= 4; d++) {
            nm = TRow[d + 1]; k = TDIMS[d] SUBSEP nm
            if (!(k in Dn)) DK[TDIMS[d], ++DKN[TDIMS[d]]] = nm
            Dn[k]++; Din[k] += f[7]; Dcw[k] += f[8]; Dcr[k] += f[9]; Dout[k] += f[10]; Dtot[k] += t
            if (u >= 0) Dusd[k] += u; else Dunp[k] += t
        }
    }
    close(tf)
    compacts_load(cf, start)
    limits_load(lf)
}

# compacts_load FILE START — this window's CN compactions, CAUTO and CMAN of
# them auto and manual, CPRE their tokens before; by session (project SUBSEP
# session SUBSEP cli): CSO[1..CSC], CSn CSauto CSpre.
function compacts_load(cf, start,   ln, f, k) {
    CN = CAUTO = CMAN = CPRE = 0; CSC = 0
    while ((getline ln < cf) > 0) {
        if (split(ln, f, "\t") < 8 || f[1] !~ /^[0-9]+$/ || f[1] + 0 < start) continue
        if (f[7] !~ /^[0-9]+$/) f[7] = 0
        CN++; CPRE += f[7]
        if (f[6] == "auto") CAUTO++; else if (f[6] == "manual") CMAN++
        k = (f[3] == "" ? "-" : f[3]) SUBSEP (f[4] == "" ? "-" : f[4]) SUBSEP f[2]
        if (!(k in CSn)) CSO[++CSC] = k
        CSn[k]++; CSpre[k] += f[7]
        if (f[6] == "auto") CSauto[k]++
    }
    close(cf)
}

# limits_load FILE — LIM 1 with the latest Codex reading: Lat (when it was
# read), Lused (%), Lwin (minutes), Lreset (epoch).
function limits_load(lf,   ln, f) {
    LIM = 0
    while ((getline ln < lf) > 0) {
        if (split(ln, f, "\t") < 5 || f[1] !~ /^[0-9]+$/ || f[2] != "codex" || f[3] !~ /^[0-9]+([.][0-9]+)?$/) continue
        if (f[4] !~ /^[0-9]+$/ || f[5] !~ /^[0-9]+$/) continue
        if (LIM && f[1] + 0 < Lat) continue
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
# hm T — the local clock time of epoch T, with the weekday when it is not today.
function hm(t,   s, d) {
    s = sprintf("%02d:%02d", int(((t + off) % 86400) / 3600), int(((t + off) % 3600) / 60))
    d = int((t + off) / 86400)
    if (d != int((now + off) / 86400)) s = substr("ThuFriSatSunMonTueWed", (d % 7) * 3 + 1, 3) " " s
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
# dusd K — a row's estimate: "-" when none of its tokens has a price.
function dusd(k) { return Dtot[k] > Dunp[k] ? usd(Dusd[k]) : "-" }
# tname D NAME — a name as the tables show it.
function tname(d, s) { return d == "project" ? proj(s) : d == "agent" ? agentn(s) : s }

# --- The view -----------------------------------------------------------------------

# view_tokens — totals, then by model, CLI, agent type and project; polling,
# compactions and the Codex plan's headroom.
function view_tokens(   o, d, i, n, k, s, a, w) {
    if (json) {
        o = jhead("tokens") ",\"data\":" jb(TL) ",\"priced\":" jb(PRICED) ",\"totals\":" jtrow(Ttot, TN, Tin, Tcw, Tcr, Tout, PRICED && Ttot > Tunp ? Tusd : -1, Tunp)
        for (d = 1; d <= 4; d++) o = o ",\"" TDIMS[d] "s\":" jtdim(TDIMS[d])
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
            (PRICED && Ttot > Tunp ? " \302\267 est. " usd(Tusd) : "")
        printf "  in %s \302\267 cache write %s \302\267 cache read %s \302\267 out %s\n\n", tk(Tin), tk(Tcw), tk(Tcr), tk(Tout)
        ttable_tokens("model", "MODEL", 10)
        ttable_tokens("cli", "CLI", 10)
        ttable_tokens("agent", "AGENT", 10)
        ttable_tokens("project", "PROJECT", 8)
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
    if (PRICED && TN) {
        print ""
        n = 0; for (i = 1; i <= DKN["model"]; i++) { k = "model" SUBSEP DK["model", i]; if (Dtot[k] == Dunp[k]) n++ }
        th("est. $: an estimate from " pbase() " (USD per million tokens)" (n ? "; " n " " nouns(n, "model") " without a price (-) left out" : ""))
    }
}
function pbase(   s) { s = pf; sub(/.*\//, "", s); return s }
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
    th("  " lc(title, 22) " " rc("TOKENS", 7) " " rc("%", 5) " " rc("IN", 7) " " rc("C.WRITE", 8) " " rc("C.READ", 7) " " rc("OUT", 7) " " rc("HIT", 5) (PRICED ? " " rc("EST $", 9) : ""))
    for (i = 1; i <= n && i <= lim; i++) {
        nm = TS[i]; k = d SUBSEP nm
        print "  " lc(cut(tname(d, nm), 22), 22) " " rc(tk(Dtot[k]), 7) " " rc(pct(Dtot[k], Ttot), 5) " " rc(tk(Din[k]), 7) " " rc(tk(Dcw[k]), 8) \
            " " rc(tk(Dcr[k]), 7) " " rc(tk(Dout[k]), 7) " " rc(hitp(Dcr[k], Din[k], Dcw[k]), 5) (PRICED ? " " rc(dusd(k), 9) : "")
    }
    if (n > lim) th("  ... " (n - lim) " more (agents report --view tokens --json)")
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
function jtrow(t, n, i, cw, cr, o, u, unp) {
    return "{\"calls\":" n ",\"in\":" jbig(i) ",\"cache_write\":" jbig(cw) ",\"cache_read\":" jbig(cr) ",\"out\":" jbig(o) ",\"total\":" jbig(t) \
        ",\"cache_hit_pct\":" pc1(cr, i + cw + cr) ",\"est_usd\":" jusd(u) ",\"unpriced_tokens\":" (PRICED ? jbig(unp) : "null") "}"
}
# jtdim D — dimension D as a JSON array, every name, the most tokens first.
function jtdim(d,   n, i, k, o, r) {
    n = tsorted(d); o = ""
    for (i = 1; i <= n; i++) {
        k = d SUBSEP TS[i]
        r = jtrow(Dtot[k], Dn[k], Din[k], Dcw[k], Dcr[k], Dout[k], PRICED ? (Dtot[k] > Dunp[k] ? Dusd[k] : -1) : -1, Dunp[k])
        o = o (i > 1 ? "," : "") "{\"" d "\":" (d == "agent" || d == "project" ? opt(TS[i]) : js(TS[i])) ",\"pct\":" pc1(Dtot[k], Ttot) "," substr(r, 2)
    }
    return "[" o "]"
}

# --- The summary's line ----------------------------------------------------------

# tokens_text — the summary's Tokens line (nothing without token data).
function tokens_text() {
    if (!TL) return
    printf "%sTOKENS%s  %s", b, e, (TN ? tk(Ttot) " \302\267 " hitp(Tcr, Tin, Tcw) " cache hits \302\267 " pct(Tpoll, Ttot) " polling" : "none in this window")
    if (TN && PRICED && Ttot > Tunp) printf " \302\267 est. %s", usd(Tusd)
    if (CN) printf " \302\267 %d %s", CN, nouns(CN, "compaction")
    printf "\n%s  by model, agent and project: agents report --view tokens%s\n\n", dim, e
}
function tokens_json() {
    if (!TL) return "null"
    return "{\"calls\":" TN ",\"total\":" jbig(Ttot) ",\"in\":" jbig(Tin) ",\"cache_write\":" jbig(Tcw) ",\"cache_read\":" jbig(Tcr) ",\"out\":" jbig(Tout) \
        ",\"cache_hit_pct\":" pc1(Tcr, Tin + Tcw + Tcr) ",\"poll_tokens\":" jbig(Tpoll) ",\"poll_pct\":" pc1(Tpoll, Ttot) \
        ",\"est_usd\":" (PRICED && Ttot > Tunp ? jusd(Tusd) : "null") ",\"compactions\":" CN "}"
}
