# lib/agents/awk/report_context.awk — context hygiene, for `agents report
# --view context`: what the sessions load and what they use. From uses.tsv
# (uf; tokens.sh documents it), the token totals (report_tokens: tokens by
# subagent type) and the configured inventory (invf, context.sh's lines).
# Part of report.awk's program; needs lib_json, lib_sort, report_fmt and
# report_tokens.
#
# An MCP server counts by the name its tools carry (mcp__NAME__TOOL): a
# plugin's server is plugin_PLUGIN_SERVER (the plugin found among the
# installed ones by the longest name that fits, else up to the first _), a
# claude.ai connector claude_ai_NAME. Every server configured (mcp.sh's
# inventory, the mcpcfg lines) is listed too, called or not; its tool name
# is its name with anything but letters, digits, _ and - turned into _. A server's TOOLS is the tools a
# session's deferred tool list names for it, on average over the sessions
# that list it: a proxy for the context it takes. A cleanup candidate is
# loaded or enabled and unused in the window: an MCP server sessions list
# but never call, an enabled plugin none of whose skills, agents or MCP
# servers was used (commands and hooks are not seen, so a plugin with only
# those is never one), a configured and enabled MCP server (Claude Code's
# user, local, project or plugin ones, Codex's) never called, listed or not.

# --- Reading ----------------------------------------------------------------------

# context_load USES INVENTORY START — the inventory: PLN plugins (PLname,
# PLshort, PLmkt, PLon, PLin, PLsk PLag PLcm PLmcp PLhk, PLmn their MCP names),
# INOTE; and this window's uses: by MCP server key (cli SUBSEP raw name)
# MSO[1..MSC] (the servers used or configured), Mcalls, Mused (sessions that
# called it), Mlist (sessions that listed it), Mtools (their listed tools,
# summed), and for a configured one MCFG, MCscope, MCname, MCon; by skill SKO[1..SKC], SKcalls, SKsess; by subagent type
# AGst[type] started.
function context_load(uf, invf, start,   ln, f, n, k, s, i, k2, nc) {
    PLN = nc = 0; INOTE = ""; MSC = SKC = 0
    while ((getline ln < invf) > 0) {
        n = split(ln, f, "\t")
        if (f[1] == "plugin" && n >= 10) {
            PLN++; PLname[PLN] = f[2]; PLshort[PLN] = f[2]; sub(/@.*$/, "", PLshort[PLN]); PLmkt[PLN] = (index(f[2], "@") ? substr(f[2], index(f[2], "@") + 1) : "-")
            PLon[PLN] = f[3] == "1"; PLin[PLN] = f[4] == "1"; PLsk[PLN] = f[5]; PLag[PLN] = f[6]; PLcm[PLN] = f[7]; PLmcp[PLN] = f[8]; PLhk[PLN] = f[9]; PLmn[PLN] = f[10]
        } else if (f[1] == "mcpcfg" && n >= 6) { nc++; Ccli[nc] = f[2]; Cscope[nc] = f[3]; Cname[nc] = f[4]; Csrc[nc] = f[5]; Con[nc] = f[6] != "0" }
        else if (f[1] == "note" && n >= 2) INOTE = f[2]
    }
    close(invf)
    while ((getline ln < uf) > 0) {
        if (split(ln, f, "\t") < 8 || f[1] !~ /^[0-9]+$/ || f[1] + 0 < start || f[8] !~ /^[0-9]+$/) continue
        s = f[4]
        if (f[6] == "mcp" || f[6] == "listed") {
            k = f[2] SUBSEP f[7]
            if (!(k in Mcalls)) { MSO[++MSC] = k; Mcalls[k] = 0 }
            if (f[6] == "mcp") { Mcalls[k] += f[8]; if (!((k, s) in Mus)) { Mus[k, s] = 1; Mused[k]++ } }
            else {
                if (!((k, s) in Mls)) { Mls[k, s] = 0; Mlist[k]++ }
                if (f[8] + 0 > Mls[k, s]) { Mtools[k] += f[8] - Mls[k, s]; Mls[k, s] = f[8] + 0 }
            }
        } else if (f[6] == "skill") {
            k = f[7]
            if (!(k in SKcalls)) SKO[++SKC] = k
            SKcalls[k] += f[8]; if (!((k, s) in SKs)) { SKs[k, s] = 1; SKsess[k]++ }
        } else if (f[6] == "agent") AGst[f[7]] += f[8]
    }
    close(uf)
    for (i = 1; i <= nc; i++) {                 # configured: the key its tools carry
        k = Ccli[i] SUBSEP Cname[i]
        s = ""
        if (Ccli[i] == "claude" && Cscope[i] == "plugin") {
            s = Csrc[i]; sub(/@.*$/, "", s)
            k = Ccli[i] SUBSEP "plugin_" nrm(s) "_" nrm(Cname[i])
        } else if (!(k in Mcalls)) { k2 = Ccli[i] SUBSEP nrm(Cname[i]); if (k2 in Mcalls) k = k2 }
        if (k in MCFG) continue
        if (!(k in Mcalls)) { MSO[++MSC] = k; Mcalls[k] = 0 }
        MCFG[k] = 1; MCsp[k] = s; MCscope[k] = Cscope[i]; MCname[k] = Cname[i]; MCon[k] = Con[i]
    }
    for (i = 1; i <= MSC; i++) mcp_name(MSO[i])
}
# nrm NAME — the name as a tool name carries it.
function nrm(s) { gsub(/[^A-Za-z0-9_-]/, "_", s); return s }

# mcp_name KEY — MN[key] the server's name, MP[key] the plugin it comes
# with ("-"), MF[key] where it comes from: plugin, claude.ai, user, local or
# project (Claude Code's scopes), config (Codex's config.toml), or "-".
function mcp_name(k,   w, r, i, p, best) {
    split(k, w, SUBSEP); r = w[2]; MP[k] = "-"; MF[k] = "-"; MN[k] = r
    if (substr(r, 1, 7) == "plugin_") {
        r = substr(r, 8); best = ""
        for (i = 1; i <= PLN; i++) { p = PLshort[i]; if (substr(r, 1, length(p) + 1) == p "_" && length(p) > length(best)) best = p }
        if (best == "" && (i = index(r, "_"))) best = substr(r, 1, i - 1)
        if (best != "") { MP[k] = best; MN[k] = substr(r, length(best) + 2); MF[k] = "plugin" }
    } else if (substr(r, 1, 10) == "claude_ai_") { MN[k] = substr(r, 11); MF[k] = "claude.ai" }
    else if (w[1] == "codex") MF[k] = "config"
    if (k in MCFG) {
        MN[k] = MCname[k]
        if (MCscope[k] == "plugin") { MF[k] = "plugin"; MP[k] = MCsp[k] }
        else MF[k] = (w[1] == "codex" ? "config" : MCscope[k])
    }
}

# --- Findings ------------------------------------------------------------------------

# plugin_uses I — calls of plugin I's skills, agents and MCP servers in the window.
function plugin_uses(i,   p, k, n, j, w) {
    p = PLshort[i]; n = 0
    for (j = 1; j <= SKC; j++) if (index(SKO[j], p ":") == 1) n += SKcalls[SKO[j]]
    for (k in AGst) if (index(k, p ":") == 1) n += AGst[k]
    for (j = 1; j <= MSC; j++) { k = MSO[j]; if (MP[k] == p) n += Mcalls[k] }
    return n
}
# plugin_idle I — plugin I is a cleanup candidate: enabled, installed, and
# none of its skills, agents or MCP servers used.
function plugin_idle(i) { return PLon[i] && PLsk[i] != "-" && PLsk[i] + PLag[i] + PLmcp[i] > 0 && !plugin_uses(i) }
# mcp_where K — where to remove configured server K.
function mcp_where(k,   q) {
    if (MF[k] == "plugin") return "disable the plugin (/plugin) where you do not need it"
    if (MF[k] == "claude.ai") return "disconnect it in claude.ai's connectors, or turn it off per project"
    if (MF[k] == "config") return "remove it from ~/.codex/config.toml, or set enabled = false"
    if (MF[k] == "user" || MF[k] == "local" || MF[k] == "project") {
        q = MN[k]; if (q ~ /[^A-Za-z0-9_.@:-]/) q = "\"" q "\""
        return "remove it with `claude mcp remove " q " -s " MF[k] "`"
    }
    return "remove it from the MCP config, or scope it to the projects that use it"
}
# cleanups — CL[1..CLN] the cleanup candidates, CLK their kind, CLN_ their
# name, CLW their weight (the context they take: tools listed times the
# sessions that list them; a plugin's contributions), heaviest first.
function cleanups(   i, j, k, t, n, s, w, idle) {
    CLN = 0
    for (i = 1; i <= MSC; i++) SRV[i] = MSO[i]
    sortk(ZERO, SRV, MSC)                         # equal weights then go by name, whatever the inventory's order
    for (i = 1; i <= MSC; i++) {
        k = SRV[i]
        if (Mcalls[k] || (!Mlist[k] && !((k in MCFG) && MCon[k]))) continue
        idle = 0                                  # a plugin that is itself a candidate carries its servers
        if (MF[k] == "plugin") for (j = 1; j <= PLN; j++) if (PLshort[j] == MP[k] && plugin_idle(j)) idle = 1
        if (idle) continue
        t = Mlist[k] ? int(Mtools[k] / Mlist[k] + 0.5) : 0
        s = MN[k] (MF[k] == "plugin" ? " (plugin " MP[k] ")" : MF[k] == "claude.ai" ? " (claude.ai)" : MF[k] == "config" ? " (Codex MCP server)" : "") ": " \
            (Mlist[k] ? (t ? t " " nouns(t, "tool") " " : "") "listed in " Mlist[k] " " nouns(Mlist[k], "session") ", " : "") \
            "never called \342\200\224 " mcp_where(k)
        w = Mtools[k] + Mlist[k]; if (!w) w = 1
        cl_add(MF[k] == "config" ? "codex_mcp" : "mcp", MN[k], w, s)
    }
    for (i = 1; i <= PLN; i++) {
        if (!plugin_idle(i)) continue
        n = PLsk[i] + PLag[i] + PLmcp[i]
        cl_add("plugin", PLshort[i], n, PLshort[i] " (plugin): " contrib(i) ", none used \342\200\224 disable it (/plugin) to load less into every session")
    }
    for (i = 1; i <= CLN; i++) CLO[i] = i
    sorti(CLWN, CLO, CLN)
}
function cl_add(kind, nm, w, text) { CLN++; CLK[CLN] = kind; CLNM[CLN] = nm; CLWN[CLN] = -w; CLT[CLN] = text }
# contrib I — what plugin I contributes, in words.
function contrib(i,   s) {
    if (PLsk[i] == "-") return "not installed"
    s = PLsk[i] " " nouns(PLsk[i], "skill") ", " PLag[i] " " nouns(PLag[i], "agent") ", " PLcm[i] " " nouns(PLcm[i], "command")
    return s ", " PLmcp[i] " MCP " nouns(PLmcp[i], "server") ", " PLhk[i] " hook " nouns(PLhk[i], "event")
}

# --- The view -----------------------------------------------------------------------

# view_context — MCP servers, skills and subagent types used and loaded,
# the servers and plugins configured, and the cleanup candidates.
function view_context(   i, k, n, o, t, en, ak, av, a) {
    context_load(uf, invf, start); cleanups()
    for (i = 1; i <= MSC; i++) { MK[i] = MSO[i]; MV[MSO[i]] = Mcalls[MSO[i]] + Mtools[MSO[i]] / 1e6 }
    sortk(MV, MK, MSC)
    for (i = 1; i <= SKC; i++) SKK[i] = SKO[i]
    sortk(SKcalls, SKK, SKC)
    n = 0
    for (a in AGst) if (!(a in av)) { ak[++n] = a; av[a] = Dtot["agent" SUBSEP a] + AGst[a] / 1e9 }
    for (i = 1; i <= DKN["agent"]; i++) { a = DK["agent", i]; if (a != "main" && !(a in av)) { ak[++n] = a; av[a] = Dtot["agent" SUBSEP a] + AGst[a] / 1e9 } }
    sortk(av, ak, n)
    if (json) {
        o = jhead("context") ",\"mcp_servers\":["
        for (i = 1; i <= MSC; i++) {
            k = MK[i]; split(k, t, SUBSEP)
            o = o (i > 1 ? "," : "") "{\"server\":" js(MN[k]) ",\"cli\":" js(t[1]) ",\"source\":" opt(MF[k]) ",\"plugin\":" opt(MP[k]) ",\"configured\":" jb(k in MCFG) ",\"enabled\":" ((k in MCFG) ? jb(MCon[k]) : "null") \
                ",\"calls\":" Mcalls[k] ",\"sessions_used\":" (Mused[k] + 0) ",\"sessions_listed\":" (Mlist[k] + 0) \
                ",\"tools_listed\":" (Mlist[k] ? int(Mtools[k] / Mlist[k] + 0.5) : "null") "}"
        }
        o = o "],\"skills\":["
        for (i = 1; i <= SKC; i++) { k = SKK[i]; o = o (i > 1 ? "," : "") "{\"skill\":" js(k) ",\"plugin\":" opt(index(k, ":") ? substr(k, 1, index(k, ":") - 1) : "") ",\"calls\":" SKcalls[k] ",\"sessions\":" SKsess[k] "}" }
        o = o "],\"subagents\":["
        for (i = 1; i <= n; i++) { a = ak[i]; o = o (i > 1 ? "," : "") "{\"agent\":" opt(a) ",\"started\":" (AGst[a] + 0) ",\"tokens\":" jbig(Dtot["agent" SUBSEP a]) ",\"pct\":" pc1(Dtot["agent" SUBSEP a], Ttot) "}" }
        o = o "],\"plugins\":["
        for (i = 1; i <= PLN; i++) {
            o = o (i > 1 ? "," : "") "{\"plugin\":" js(PLshort[i]) ",\"marketplace\":" opt(PLmkt[i]) ",\"enabled\":" jb(PLon[i]) ",\"installed\":" jb(PLin[i]) \
                ",\"skills\":" jnum(PLsk[i]) ",\"agents\":" jnum(PLag[i]) ",\"commands\":" jnum(PLcm[i]) ",\"mcp_servers\":" jnum(PLmcp[i]) ",\"hooks\":" jnum(PLhk[i]) \
                ",\"calls\":" plugin_uses(i) "}"
        }
        o = o "],\"cleanup\":["
        for (i = 1; i <= CLN; i++) { k = CLO[i]; o = o (i > 1 ? "," : "") "{\"kind\":" js(CLK[k]) ",\"name\":" js(CLNM[k]) ",\"text\":" js(CLT[k]) "}" }
        print o "],\"note\":" opt(INOTE) "}"
        return
    }
    vhead("context")
    printf "%sMCP SERVERS%s\n", b, e
    if (!MSC) print "  none configured, called or listed in this window"
    else {
        th("  " lc("SERVER", 22) " " lc("CLI", 6) " " rc("CALLS", 6) " " rc("USED IN", 8) " " rc("LISTED IN", 9) " " rc("TOOLS", 5) "  FROM")
        for (i = 1; i <= MSC && i <= 15; i++) {
            k = MK[i]; split(k, t, SUBSEP)
            print "  " lc(cut(MN[k], 22), 22) " " lc(t[1], 6) " " rc(tk(Mcalls[k]), 6) " " rc(Mused[k] + 0, 8) " " rc(Mlist[k] + 0, 9) " " \
                rc(Mlist[k] ? int(Mtools[k] / Mlist[k] + 0.5) : "-", 5) "  " (MF[k] == "plugin" ? "plugin " MP[k] : MF[k]) ((k in MCFG) && !MCon[k] ? " (off)" : "")
        }
        if (MSC > 15) th("  ... " (MSC - 15) " more (agents report --view context --json)")
    }
    print ""
    printf "%sSKILLS%s\n", b, e
    if (!SKC) print "  none called in this window"
    else {
        th("  " lc("SKILL", 30) " " rc("CALLS", 6) " " rc("SESSIONS", 8))
        for (i = 1; i <= SKC && i <= 10; i++) { k = SKK[i]; print "  " lc(cut(k, 30), 30) " " rc(SKcalls[k], 6) " " rc(SKsess[k], 8) }
        if (SKC > 10) th("  ... " (SKC - 10) " more (agents report --view context --json)")
    }
    print ""
    printf "%sSUBAGENTS%s\n", b, e
    if (!n) print "  none in this window"
    else {
        th("  " lc("TYPE", 30) " " rc("STARTED", 7) " " rc("TOKENS", 7) " " rc("%", 5))
        for (i = 1; i <= n && i <= 10; i++) { a = ak[i]; print "  " lc(cut(agentn(a), 30), 30) " " rc(AGst[a] + 0, 7) " " rc(tk(Dtot["agent" SUBSEP a]), 7) " " rc(pct(Dtot["agent" SUBSEP a], Ttot), 5) }
        if (n > 10) th("  ... " (n - 10) " more (agents report --view context --json)")
    }
    print ""
    en = 0; for (i = 1; i <= PLN; i++) en += PLon[i]
    printf "%sPLUGINS%s  %s\n", b, e, (INOTE != "" ? INOTE : PLN ? en " of " PLN " enabled (Claude Code)" : "none in Claude Code's settings")
    for (i = 1; i <= PLN; i++) if (PLon[i]) print "  " lc(cut(PLshort[i], 22), 22) " " contrib(i) " \302\267 " plugin_uses(i) " " nouns(plugin_uses(i), "call")
    print ""
    printf "%sCLEANUP CANDIDATES%s  %s\n", b, e, (CLN ? "loaded or enabled, unused " wword() : "none: everything loaded was used " wword())
    for (i = 1; i <= CLN && i <= 10; i++) print "  " CLT[CLO[i]]
    if (CLN > 10) th("  ... " (CLN - 10) " more (agents report --view context --json)")
}
function jnum(s) { return s ~ /^[0-9]+$/ ? s + 0 : "null" }
