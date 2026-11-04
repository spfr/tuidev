# lib/agents/awk/triage_view.awk — `agents`: who needs you first. Reads the need
# and triage rows and the records (_agents_with_needs); triage.sh says what each
# state means. Shapes carry the states, so it reads the same under NO_COLOR, and
# a locale with no such glyphs gets shapes of its own (lib_fmt's gl).
# The table with PIDs, ports and MCP servers is `agents ls`.
# ENVIRON: W, SYSLINE, SWAP (a percent, while swap is high), and the colors.
# Needs lib_fmt.

function color(st) {
    return st == "need" ? NEED B : st == "review" ? DONE : st == "run" ? RUN : DIM
}
# painted S C — S in color C, the row's tint back on after the reset.
function painted(s, c) { return s == "" || c == "" ? s : c s e TI }
# row P — one session: glyph and project in the state's color, then what it is,
# how long, and whatever else fits.
function row(p, st,   a, rest, r, title, room, ca, cb, o, k, gap) {
    a = ag[p] == "-" ? "" : age(ag[p] + 0)
    r = " " gl(st) " " lc(dcut(nm[p], pw), pw)
    title = (p in ti) ? ti[p] : ""
    rest = ""
    if (st == "need") { rest = narrow ? "" : "agents show " p }
    else if (st == "run" || st == "unknown") {
        ca = sprintf("%.1f", cpu[p] / 100); cb = mem(rss[p])
        rest = narrow ? ca "c " cb : ca " cores  " cb
    }
    room = L - (3 + pw + 1 + sw + 1 + 6 + (narrow ? 2 : 3))
    TI = st == "need" ? TINT : ""
    o = TI painted(r, color(st)) (st == "need" ? B : "") " " lc(dcut(lb[p], sw), sw) (st == "need" ? e TI : "") " " rc(a, 6)
    gap = narrow ? "  " : "   "
    if (rest != "") { rest = dcut(rest, room); o = o gap painted(rest, st == "need" ? DIM : ""); room -= dw(rest) + 2; gap = "  " }
    if (!narrow && title != "" && room >= 10) o = o gap painted(dcut(title, room), DIM)
    # The tint runs to the edge of the view, not just the text.
    if (TI != "") { k = L - dw(strip(o)); while (k-- > 0) o = o " "; o = o e }
    else sub(/ +$/, "", o)
    print o
    TI = ""
    warnings(p, 1)
}
# strip S — S without its color sequences (to measure a painted row).
function strip(s) { gsub(/\033\[[0-9;]*m/, "", s); return s }
# warning_text I — a flagged command, as the verdict sees it: stuck loops by
# their age, long and duplicate commands by what they run.
function warning_text(i,   f, what, why, c, d, dot) {
    split(needs[i], f, "\t")
    c = (f[2] in cmd) ? cmd[f[2]] : "command"
    if (f[4] == "stuck") what = "wait-loop stuck " age(f[14] + 0)
    else if (f[4] == "dup") what = (f[2] in dup ? dup[f[2]] (ENVIRON["AGENTS_ASCII"] == "" ? "\303\227 " : "x ") : "") dcut(c, 28)
    else what = dcut(c, 28) " running " age(f[14] + 0)
    # Nothing to decide: what it is says it all.
    if (f[5] == "info" || f[5] == "leave") return what
    dot = " " gl("dot") " "
    # "safe to stop — what it waits for already finished (ok, 5h)": the middle.
    d = index(f[11], " \342\200\224 ")
    why = d ? substr(f[11], d + 5) : ""
    sub(/ \(.*$/, "", why)
    # The verdict's own "3×".
    if (ENVIRON["AGENTS_ASCII"] != "" && (d = index(why, "\303\227"))) why = substr(why, 1, d - 1) "x" substr(why, d + 2)
    return (narrow || why == "") ? what dot f[10] : what dot why dot f[10]
}
# warnings OWNER SHOWN — what is flagged under session OWNER: at most three
# lines under its row (SHOWN), or, for one whose row is folded into the parked
# line, with its project in front. Copies of one command say so once. "!" asks
# for a decision; what the verdict only informs about stays dim.
function warnings(p, shown,   i, f, n, t, pre, seen, act) {
    n = 0
    split("", seen)
    for (i = 1; i <= nn; i++) {
        split(needs[i], f, "\t")
        if (f[9] != p) continue
        t = warning_text(i)
        if (t in seen) continue
        seen[t] = 1
        if (++n > 3) continue
        pre = shown ? "   " : " "
        act = f[5] == "stop" || f[5] == "check"
        t = dcut((shown ? "" : nm[p] ": ") t, L - length(pre) - 2)
        print pre (act ? WARN "!" e " " t : DIM gl("dot") " " t e)
    }
    if (n > 3) print "   " DIM "... " (n - 3) " more (agents ps " p ")" e
}
# section ST TITLE — one group, most urgent first; nothing when it is empty.
function section(st, title,   i) {
    if (!cnt[st]) return
    if (!narrow) print DIM title e
    for (i = 1; i <= na; i++) if (state[order[i]] == st) row(order[i], st)
}
# sort_key P — within a group: who has waited longest, the newest finished, the
# busiest, the longest parked.
function sort_key(p) {
    return state[p] == "need" ? -ag_n(p) : state[p] == "review" ? ag_n(p) : (state[p] == "run" || state[p] == "unknown") ? -cpu[p] : -ag_n(p)
}
function ag_n(p) { return ag[p] == "-" ? 0 : ag[p] + 0 }
function plural(n, s) { return n == 1 ? s : s "s" }
function summary(   s, right, k) {
    if (!na) s = " no agent sessions"
    else {
        s = ""
        if (narrow) {
            if (cnt["need"]) s = s " " NEED B gl("need") " " cnt["need"] e " "
            if (cnt["review"]) s = s " " DONE gl("review") " " cnt["review"] e " "
            if (cnt["run"]) s = s " " RUN gl("run") " " cnt["run"] e " "
            if (cnt["unknown"]) s = s " " DIM gl("unknown") " " cnt["unknown"] e " "
            if (cnt["parked"]) s = s " " DIM gl("parked") " " cnt["parked"] e
        } else {
            if (cnt["need"]) s = s " " NEED B gl("need") " " cnt["need"] " needs you" e "  "
            if (cnt["review"]) s = s " " DONE gl("review") " " cnt["review"] " to review" e "  "
            if (cnt["run"]) s = s " " RUN gl("run") " " cnt["run"] " running" e "  "
            if (cnt["unknown"]) s = s " " DIM gl("unknown") " " cnt["unknown"] " no signal" e "  "
            if (cnt["parked"]) s = s " " DIM gl("parked") " " cnt["parked"] " parked" e
        }
    }
    sub(/ +$/, "", s)
    if (ENVIRON["SWAP"] != "") {
        right = "! swap " ENVIRON["SWAP"] "%"
        k = L - dw(strip(s)) - dw(right)
        if (k < 2) k = 2
        while (k-- > 0) s = s " "
        s = s WARN right e
    }
    print s
}
function parked_line(   oldest, i, p, s, dot) {
    oldest = -1
    for (i = 1; i <= na; i++) { p = order[i]; if (state[p] == "parked" && ag[p] != "-" && ag[p] + 0 > oldest) oldest = ag[p] + 0 }
    s = ""
    dot = " " gl("dot") " "
    if (cnt["parked"]) s = gl("parked") " " cnt["parked"] " parked" (oldest >= 0 ? (narrow ? dot "oldest " : ", oldest ") rough(oldest) : "")
    if (!narrow) {
        s = s (s == "" ? "" : dot)
        s = s (ns ? WARN "! " ns " stale: agents stale" e DIM : "no stale") dot (nh ? WARN "! " nh " " plural(nh, "hog") ": agents hogs" e DIM : "no hogs")
    } else {
        if (ns) s = s (s == "" ? "" : dot) WARN "! " ns " stale" e DIM
        if (nh) s = s (s == "" ? "" : dot) WARN "! " nh " " plural(nh, "hog") e DIM
    }
    if (s != "") print DIM s e
}
BEGIN {
    B = ENVIRON["B"]; DIM = ENVIRON["DIM"]; NEED = ENVIRON["NEED"]; DONE = ENVIRON["DONE"]; RUN = ENVIRON["RUN"]
    WARN = ENVIRON["WARN"]; TINT = ENVIRON["TINT"]; e = ENVIRON["N"]; TI = ""
    W = ENVIRON["W"] + 0; L = W > 80 ? 80 : W; narrow = W < 72
}
$1 == "triage" { state[$2] = $3; ag[$2] = $4; lb[$2] = $5; next }
$1 == "herdr" && $4 != "-" { ti[$2] = $4; next }
$1 == "need" { if ($4 == "stuck" || $4 == "long" || $4 == "dup") if ($9 != "-") needs[++nn] = $0; next }
$1 == "act" && NF >= 14 { cmd[$2] = $14; if ($17 + 0 > 1) dup[$2] = $17; next }
$1 == "agent" && NF >= 14 && $3 != "daemon" {
    order[++na] = $2; nm[$2] = ($15 == "" || $15 == "-") ? $3 : $15; cpu[$2] = $5 + 0; rss[$2] = $7 + 0
    next
}
$1 == "stale" && NF >= 14 { ns++; next }
$1 == "hog" && NF >= 14 { nh++; next }
END {
    pw = narrow ? 8 : 10
    for (i = 1; i <= na; i++) {
        p = order[i]; cnt[state[p]]++
        if (state[p] != "parked" && dw(nm[p]) > pw) pw = dw(nm[p])
        key[p] = sort_key(p)
    }
    if (narrow) { if (pw > 10) pw = 10 } else if (pw > 18) pw = 18
    sw = narrow ? 12 : 13
    # Insertion, stable: only a handful of sessions.
    for (i = 2; i <= na; i++) {
        t = order[i]
        for (j = i - 1; j >= 1 && key[order[j]] > key[t]; j--) order[j + 1] = order[j]
        order[j + 1] = t
    }
    summary()
    if (na) print ""
    section("need", "NEEDS YOU")
    section("review", "TO REVIEW")
    section("run", "RUNNING")
    section("unknown", "NO SIGNAL")
    if (!narrow && (cnt["need"] + cnt["review"] + cnt["run"] + cnt["unknown"])) print ""
    parked_line()
    for (i = 1; i <= na; i++) if (state[order[i]] == "parked") warnings(order[i], 0)
    if (!narrow && ENVIRON["SYSLINE"] != "") print DIM dcut(ENVIRON["SYSLINE"], L) e
}
