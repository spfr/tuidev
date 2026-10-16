# lib/agents/awk/report_waits.awk — how long the agents waited on you and how
# often they called you, for `agents report --view waits`, the summary and
# the insights. Part of report.awk's program; needs lib_json, lib_sort and
# report_fmt.
#
# waits.tsv (agents sample, history.sh), one row per session and sample
# while Herdr shows it blocked or done, or, for a Claude Code session outside
# Herdr, while its hooks say it waits (hooks.sh):
#   epoch project agent status session secs
# blocked: waiting for your answer (a permission prompt, a question); done:
# finished, not yet looked at (outside Herdr: from the idle prompt to your
# next one); secs: the part of the time since the sample before that it
# waited, at most 5 minutes. notify.tsv (scripts/notify.sh), one row per notification:
#   epoch session project kind channels banner_skipped
# banner_skipped: present (you were at the Mac, in front of the session),
# remote (a session reached over ssh) or "-". Projects fold a subagent's
# worktree into its repository (pfold), as the token tables do.

# waits_load WAITS NOTIFY START — WaL 1 when either file has a row at all;
# this window's seconds WaB (blocked) and WaD (done), WaSC sessions; by
# project WaPO[1..WaPC] (WaPb, WaPd, WaPn notifications, WaPs banners
# skipped); by agent WaAO[1..WaAC] (WaAb, WaAd); WaN notifications, by kind
# WaKO[1..WaKC] (WaKn); WaSp and WaSr banners skipped (present, remote).
function waits_load(wf, nf, start,   ln, f, p, a, s, k) {
    WaL = WaB = WaD = WaSC = WaPC = WaAC = WaN = WaKC = WaSp = WaSr = 0
    while ((getline ln < wf) > 0) {
        if (split(ln, f, "\t") < 6 || f[1] !~ /^[0-9]+$/ || f[6] !~ /^[0-9]+$/) continue
        if (f[4] != "blocked" && f[4] != "done") continue
        WaL = 1
        if (f[1] + 0 < start) continue
        s = f[6] + 0; p = waits_proj(f[2]); a = f[3] == "" ? "-" : f[3]
        waits_p(p); waits_a(a)
        if (f[4] == "blocked") { WaB += s; WaPb[p] += s; WaAb[a] += s }
        else { WaD += s; WaPd[p] += s; WaAd[a] += s }
        if (!(f[5] in WaSs)) { WaSs[f[5]] = 1; WaSC++ }
    }
    close(wf)
    while ((getline ln < nf) > 0) {
        if (split(ln, f, "\t") < 6 || f[1] !~ /^[0-9]+$/) continue
        WaL = 1
        if (f[1] + 0 < start) continue
        p = waits_proj(f[3]); k = f[4] == "" ? "-" : f[4]
        waits_p(p); WaN++; WaPn[p]++
        if (!(k in WaKn)) WaKO[++WaKC] = k
        WaKn[k]++
        if (f[6] == "present" || f[6] == "remote") { WaPs[p]++; if (f[6] == "present") WaSp++; else WaSr++ }
    }
    close(nf)
}
function waits_proj(s) { return s == "" ? "-" : pfold(s) }
function waits_p(p) { if (!(p in WaPw)) { WaPO[++WaPC] = p; WaPw[p] = 0 } }
function waits_a(a) { if (!(a in WaAw)) { WaAO[++WaAC] = a; WaAw[a] = 0 } }

# waits_sorted — WaPO and WaAO by the time waited (WaPw, WaAw), the most
# first; projects that only notified by their notifications after.
function waits_sorted(   i, p) {
    for (i = 1; i <= WaPC; i++) { p = WaPO[i]; WaPw[p] = WaPb[p] + WaPd[p] + WaPn[p] / 1000 }
    for (i = 1; i <= WaAC; i++) WaAw[WaAO[i]] = WaAb[WaAO[i]] + WaAd[WaAO[i]]
    sortk(WaPw, WaPO, WaPC); sortk(WaAw, WaAO, WaAC); sortk(WaKn, WaKO, WaKC)
}

# waitw S — seconds waited, in words: 0 min, <1 min, 47 min, 2.5 h.
function waitw(s) {
    if (s <= 0) return "0 min"
    if (s < 30) return "<1 min"
    return s < 6000 ? int(s / 60 + 0.5) " min" : sprintf("%.1f h", s / 3600)
}
# waitc S — waitw in a table cell: "-" for none.
function waitc(s) { return s > 0 ? waitw(s) : "-" }
# kindn — a notification's kind in a list ("-": none was given).
function kindn(k) { return k == "-" ? "other" : k }
# skipw — the banners skipped, and why, in words ("" for none).
function skipw(   s) {
    if (!WaSp && !WaSr) return ""
    s = (WaSp + WaSr) " " nouns(WaSp + WaSr, "banner") " skipped ("
    if (WaSp) s = s WaSp " while you were at the Mac"
    if (WaSr) s = s (WaSp ? ", " : "") WaSr " for ssh sessions"
    return s ")"
}

# wait_insight DASH — the wait finding: WAIT_NOTABLE seconds or more waited
# in the window; an hour waited weighs as 10 CPU-min (never below
# INSIGHT_MIN).
function wait_insight(dash,   t, s, top) {
    WAIT_NOTABLE = 1800
    t = WaB + WaD
    if (t < WAIT_NOTABLE) return
    waits_sorted(); top = WaPO[1]
    s = "Agents waited on you " waitw(t) " " wword() " (top: " cut(proj(top), 32) " " waitw(WaPb[top] + WaPd[top])
    if (WaN) s = s "; " WaN " " nouns(WaN, "notification") (WaSp ? ", " WaSp " " nouns(WaSp, "banner") " skipped while you were at the Mac" : "")
    s = s ")" dash (WaB >= WaD ? "allow what you always approve, so they ask less" \
        : "finished sessions sat unseen: queue the next task before they finish")
    ins_add("waited", "waits", t / 6 < INSIGHT_MIN ? INSIGHT_MIN : t / 6, top, "-", "-", "-", s)
}

# view_waits — the time waited and the notifications, by project, agent and kind.
function view_waits(   i, p, a, k, o, n) {
    waits_sorted()
    if (json) {
        o = jhead("waits") ",\"data\":" jb(WaL) ",\"waited_s\":" (WaB + WaD) ",\"blocked_s\":" WaB ",\"done_s\":" WaD ",\"sessions\":" WaSC
        o = o ",\"notifications\":" WaN ",\"banners_skipped\":{\"present\":" WaSp ",\"remote\":" WaSr "},\"kinds\":["
        for (i = 1; i <= WaKC; i++) o = o (i > 1 ? "," : "") "{\"kind\":" opt(WaKO[i]) ",\"count\":" WaKn[WaKO[i]] "}"
        o = o "],\"agents\":["
        for (i = 1; i <= WaAC; i++) { a = WaAO[i]; o = o (i > 1 ? "," : "") "{\"agent\":" opt(a) ",\"blocked_s\":" (WaAb[a] + 0) ",\"done_s\":" (WaAd[a] + 0) "}" }
        o = o "],\"projects\":["
        for (i = 1; i <= WaPC; i++) {
            p = WaPO[i]
            o = o (i > 1 ? "," : "") "{\"project\":" opt(p) ",\"waited_s\":" (WaPb[p] + WaPd[p]) ",\"blocked_s\":" (WaPb[p] + 0) ",\"done_s\":" (WaPd[p] + 0) \
                ",\"notifications\":" (WaPn[p] + 0) ",\"banners_skipped\":" (WaPs[p] + 0) "}"
        }
        print o "]}"
        return
    }
    vhead("waits")
    if (!WaL) {
        if (hist != 1) print "history is off (AGENTS_HISTORY=0): no waits or notifications are recorded"
        else print "no waits recorded yet (waits.tsv, notify.tsv): each agents sample adds the sessions waiting on you (from Herdr, or Claude Code's hooks outside it), and each notification the hooks send is logged"
        return
    }
    if (!WaPC) { print "no waits or notifications in this window"; return }
    printf "%sWAITED ON YOU%s  %s \302\267 blocked %s \302\267 done, unseen %s \302\267 %d %s\n", b, e, waitw(WaB + WaD), waitw(WaB), waitw(WaD), WaSC, nouns(WaSC, "session")
    o = ""
    for (i = 1; i <= WaKC && i <= 5; i++) o = o " \302\267 " kindn(WaKO[i]) " " WaKn[WaKO[i]]
    k = skipw()
    printf "%sNOTIFICATIONS%s  %d%s%s\n\n", b, e, WaN, o, (k == "" ? "" : " \302\267 " k)
    th("  " lc("PROJECT", 24) " " rc("WAITED", 8) " " rc("BLOCKED", 8) " " rc("DONE", 8) " " rc("NOTIFIED", 9) " " rc("SKIPPED", 8))
    for (i = 1; i <= WaPC && i <= 10; i++) {
        p = WaPO[i]
        print "  " lc(cut(proj(p), 24), 24) " " rc(waitc(WaPb[p] + WaPd[p]), 8) " " rc(waitc(WaPb[p]), 8) " " rc(waitc(WaPd[p]), 8) \
            " " rc(WaPn[p] + 0, 9) " " rc(WaPs[p] + 0, 8)
    }
    if (WaPC > 10) th("  ... " (WaPC - 10) " more (agents report --view waits --json)")
    if (WaAC) {
        o = ""; n = 0
        for (i = 1; i <= WaAC && i <= 5; i++) { a = WaAO[i]; o = o (n++ ? " \302\267 " : "") agentn(a) " " waitw(WaAb[a] + WaAd[a]) }
        printf "\n%sBY AGENT%s     %s\n", b, e, o
    }
    print ""
    th("blocked: waiting for your answer; done: finished, not yet looked at (outside Herdr: until your next prompt). Counted once a minute while the menu runs.")
}

# waits_text — the summary's Waits line (nothing without wait data).
function waits_text(   k) {
    if (!WaL) return
    k = skipw()
    if (!WaPC) printf "%sWAITS%s  none in this window\n", b, e
    else printf "%sWAITS%s  %s waited on you \302\267 %d %s%s\n", b, e, waitw(WaB + WaD), WaN, nouns(WaN, "notification"), (k == "" ? "" : " \302\267 " k)
    printf "%s  by project and kind: agents report --view waits%s\n\n", dim, e
}
function waits_json() {
    if (!WaL) return "null"
    return "{\"waited_s\":" (WaB + WaD) ",\"blocked_s\":" WaB ",\"done_s\":" WaD ",\"notifications\":" WaN \
        ",\"banners_skipped\":{\"present\":" WaSp ",\"remote\":" WaSr "}}"
}
