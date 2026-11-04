# lib/agents/awk/limits.awk — the usage limits every CLI reported
# (limits.tsv; limits.sh documents it) and today's usage signals, for the
# menu (mode tsv: agents tsv's limit, denials and compacts records), for
# `agents limits` (mode view) and its --json (mode json). Needs lib_fmt
# (age, dayhm, gauge) and lib_json (js, opt).
#
# Variables: mode; lf (limits.tsv), now, off (the UTC offset); in mode tsv
# also df (denials.tsv), cf (compacts.tsv) and mid (local midnight); in mode
# view hist (AGENTS_HISTORY), and the colors in the environment.
#
# A reading is stale once its window has reset (resets_at passed), or, with
# no reset time (a window nothing has been used of yet), a day after it was
# read: the menu hides it, the view shows it dimmed. So is a plain claude
# reading that an account's (claude:NAME) supersedes: a later reading of the
# same window, resetting at the same second, at least as used. That is the
# copy agents before 3.12 wrote for every account under "claude"; usage in
# a window only grows, so hiding it never lowers what the menu's gauge
# shows, and a plain account in use reads anew within minutes.

# cliname F — a CLI family (limits.tsv's cli up to its ":") for people. A
# new CLI adds its line here and its probe in limits.sh.
function cliname(f) {
    if (f == "claude") return "Claude"
    if (f == "codex") return "Codex"
    if (f == "agy") return "Antigravity"
    if (f == "grok") return "Grok"
    if (f == "cursor-agent") return "Cursor"
    return f
}
# corder F — where a family sorts: the order the menu lists them in.
function corder(f) {
    if (f == "claude") return 1
    if (f == "codex") return 2
    if (f == "agy") return 3
    if (f == "grok") return 4
    if (f == "cursor-agent") return 5
    return 9
}
# wname M — a window in minutes for people: 5h, day, week, month, else 90m, 2h, 3d.
function wname(m) {
    if (m == 300) return "5h"
    if (m == 1440) return "day"
    if (m == 10080) return "week"
    if (m == 43200) return "month"
    return m > 0 && m % 1440 == 0 ? (m / 1440) "d" : m > 0 && m % 60 == 0 ? (m / 60) "h" : m "m"
}
# wday T — the local weekday of epoch T (1970-01-01 was a Thursday).
function wday(t) { return substr("ThuFriSatSunMonTueWed", (int((t + off) / 86400) % 7) * 3 + 1, 3) }
# hhmm T — the local clock time of epoch T.
function hhmm(t,   s) { s = (t + off) % 86400; return sprintf("%02d:%02d", int(s / 3600), int((s % 3600) / 60)) }
# rtext T — when a window resets, as short as it reads: 14:05 within a day,
# Mon 09:00 within a week, else Oct 19; "" for no reset time.
function rtext(t,   s) {
    if (t <= 0) return ""
    if (t - now < 86400) return hhmm(t)
    if (t - now < 7 * 86400) return wday(t) " " hhmm(t)
    s = dayhm(t); return substr(s, 1, 6)
}
# pace I — how window I compares with the time gone: PE, the % of the window
# elapsed now (-1 when its length or reset doesn't say); PV, over when the
# reading runs ahead of the time elapsed at that reading, under when not, "-"
# in the window's first PACE_EARLY % (3% used after 1% of the time says nothing
# yet) or with no reset to go by; PL, while over, the seconds left at this rate.
function pace(i,   win, at) {
    PE = -1; PV = "-"; PL = "-"
    win = W[i] * 60
    if (R[i] <= now || win <= 0) return
    at = win - (R[i] - E[i])
    PE = 100 * (win - (R[i] - now)) / win
    if (PE < 0) PE = 0
    if (at <= 0 || at > win || 100 * at / win < PACE_EARLY) return
    PV = (P[i] > 100 * at / win + PACE_MARGIN) ? "over" : "under"
    if (PV == "over") {
        # At the rate so far, from the reading on.
        PL = int((100 - P[i]) * at / P[i] - (now - E[i]))
        if (PL < 0) PL = 0
    }
}
function stale(i) { return (R[i] > 0 && R[i] <= now) || (R[i] <= 0 && now - E[i] > 86400) || (i in SUP) }
function name(i) { return cliname(F[i]) (L[i] != "-" && L[i] != "" ? " \302\267 " L[i] : "") }
function pcti(p) { return int(p + 0.5) }

# load — N rows, the latest per cli and window: E epoch, C cli, F family,
# P used %, W window minutes, R resets_at, L label; sorted by family,
# label and window (K the sort keys); SUP the superseded plain claude rows.
function load(   ln, f, k, i, j, t, n) {
    N = 0
    while ((getline ln < lf) > 0) {
        n = split(ln, f, "\t")
        if (n < 5 || f[1] !~ /^[0-9]+$/ || f[2] !~ /^[a-z0-9][a-z0-9:._-]*$/ || f[3] !~ /^[0-9]+([.][0-9]+)?$/) continue
        if (f[4] !~ /^[0-9]+$/ || f[5] !~ /^[0-9]+$/) continue
        k = f[2] SUBSEP f[4]
        if (k in at) { i = at[k]; if (f[1] + 0 < E[i]) continue }
        else { i = ++N; at[k] = i }
        E[i] = f[1] + 0; C[i] = f[2]; P[i] = f[3] + 0; W[i] = f[4] + 0; R[i] = f[5] + 0
        L[i] = n >= 6 && f[6] != "" ? f[6] : "-"
        F[i] = C[i]; sub(/:.*/, "", F[i])
    }
    close(lf)
    for (i = 1; i <= N; i++) {
        if (C[i] != "claude" || R[i] <= 0) continue
        for (j = 1; j <= N; j++)
            if (F[j] == "claude" && C[j] != "claude" && W[j] == W[i] && R[j] == R[i] && E[j] > E[i] && P[j] >= P[i]) { SUP[i] = 1; break }
    }
    for (i = 1; i <= N; i++) { O[i] = i; K[i] = corder(F[i]) " " F[i] " " (L[i] == "-" ? "" : L[i]) " " sprintf("%09d", W[i]) }
    for (i = 2; i <= N; i++) {
        t = O[i]
        for (j = i - 1; j >= 1 && K[O[j]] > K[t]; j--) O[j + 1] = O[j]
        O[j + 1] = t
    }
}

# today FILE COL — rows of FILE written since mid: their count, and in TOP
# the value of column COL seen most often, "-" not counting (ties: the
# first by name); "-" when none.
function today(file, col,   ln, f, n, k, cnt, best) {
    n = 0; TOP = "-"
    if (file == "") return 0
    while ((getline ln < file) > 0) {
        if (split(ln, f, "\t") < col || f[1] !~ /^[0-9]+$/ || f[1] + 0 < mid) continue
        n++
        if (f[col] != "-" && f[col] != "") cnt[f[col]]++
    }
    close(file)
    best = 0
    for (k in cnt) if (cnt[k] > best || (cnt[k] == best && k < TOP)) { best = cnt[k]; TOP = k }
    return n
}

function tsv(   i, x, n) {
    for (x = 1; x <= N; x++) {
        i = O[x]
        if (stale(i)) continue
        n = rtext(R[i])
        print "limit\t" name(i) "\t" wname(W[i]) "\t" pcti(P[i]) "\t" (n == "" ? "-" : n) "\t" C[i] "\t" (now - E[i])
        pace(i)
        print "pace\t" int(PE) "\t" PV "\t" PL "\t" gauge(P[i], 12, PE, "", "", "")
    }
    if ((n = today(df, 8)) > 0) print "denials\t" n "\t" TOP
    if ((n = today(cf, 1)) > 0) print "compacts\t" n
}

# wtag M — a window as a gauge's label: 5h, wk, mo.
function wtag(m) { return m == 10080 ? "wk" : m == 43200 ? "mo" : wname(m) }
# over_text ROOM — over pace in words, as much as fits in ROOM columns ("" if not
# even the word does): the time left at this rate is what you'd act on, and "at
# this rate" the first to go.
function over_text(room,   t, l) {
    l = PL == "-" ? "" : PL > 0 ? rough(PL) " left" : "at the limit"
    t = "! over pace" (l == "" ? "" : ", " l " at this rate"); if (dw(t) <= room) return t
    if (l != "") {
        t = "! over pace, " l; if (dw(t) <= room) return t
        t = "! over, " l; if (dw(t) <= room) return t
        t = "! " l; if (dw(t) <= room) return t
    }
    t = "! over pace"; if (dw(t) <= room) return t
    t = "! over"; return dw(t) <= room ? t : ""
}
# tail ROOM RESET READ — what follows the percent, fit to ROOM columns: over pace
# first, with the time left even at the reset's cost; then the reset, the pace
# when under, and how old the reading is.
function tail(room, rt, rd,   t, c, r, used) {
    room -= 3
    if (room < 1) return ""
    if (dw(rt) > room) rt = ""
    t = ""; c = ""
    if (PV == "over") {
        c = WARN
        t = over_text(rt == "" ? room : room - dw(rt) - 2)
        if (PL != "-" && !index(t, "left") && !index(t, "limit")) { rt = ""; t = over_text(room) }
    } else if (PV == "under" && (rt == "" ? 10 : dw(rt) + 12) <= room) { c = DIM; t = "under pace" }
    r = rt; used = dw(rt)
    if (t != "") {
        # Lined up with the rows above, when there is room for that.
        if (rt != "" && 20 + 2 + dw(t) <= room) { r = lc(rt, 20); used = 20 }
        r = r (r == "" ? "" : "  ") c t e
        used += (used ? 2 : 0) + dw(t)
    }
    if (rd != "" && used + 2 + dw(rd) <= room) r = r (r == "" ? "" : "  ") DIM rd e
    return r == "" ? "" : "   " r
}
function view(   i, x, w, s, rt, any, cl, c, rd, cells, width, lab, tag, g) {
    # A narrow pane keeps what you act on: the gauge and the pace.
    width = ENVIRON["W"] + 0; cells = width < 72 ? 10 : 20
    printf "%s\n\n", b dcut("agents limits", width) e dim dcut(" " gl("dot") " usage limits each CLI reported, newest reading per window", width - 13) e
    w = 12
    for (i = 1; i <= N; i++) if (dw(name(i) " " wtag(W[i])) > w) w = dw(name(i) " " wtag(W[i]))
    if (w > (width < 72 ? 16 : 24)) w = width < 72 ? 16 : 24
    if (N) {
        for (x = 1; x <= N; x++) {
            i = O[x]; s = stale(i)
            rt = rtext(R[i])
            if (R[i] > 0 && R[i] <= now) rt = "reset " age(now - R[i]) " ago"
            else if (rt != "") rt = "resets " rt
            else rt = "-"
            pace(i)
            tag = wtag(W[i]); lab = lc(dcut(name(i), w - dw(tag) - 1) " " tag, w)
            rd = (s || now - E[i] >= 600) ? "read " age(now - E[i]) " ago" : ""
            if (s) { PV = "-"; g = gauge(P[i], cells, -1, "", "", "") " "; c = "" }
            else {
                c = P[i] >= 95 ? NEED : (P[i] >= 80 || PV == "over") ? WARN : RUN
                g = gauge(P[i], cells, PE, c, dim, ACC) (PE < 0 ? " " : "")
            }
            printf "%s%s  %s  %s%3d%%%s%s%s\n", (s ? dim : ""), lab, g, ((s || c == RUN) ? "" : c), pcti(P[i]), ((s || c == RUN) ? "" : e), tail(width - w - 2 - cells - 1 - 2 - 4, rt, rd), (s ? e : "")
            if (F[i] == "claude") cl = 1
            any = 1
        }
    } else if (hist != 1) {
        print "history is off (AGENTS_HISTORY=0): no limits are recorded"
        return
    } else print "no readings yet"
    print ""
    if (!cl) printf "%s%s%s\n", dim, dcut("Claude Code: no reading yet. Its status line reports them (Pro and Max plans): agents statusline", width), e
    if (any) {
        printf "%s%s%s\n", dim, dcut(gl("mark") " marks the time gone in the window.", width), e
        printf "%s%s%s\n", dim, dcut("A window that has reset is dimmed until the CLI reports it again.", width), e
    }
}

function json(   i, x, o) {
    o = "{\"schema_version\":1,\"now\":" now ",\"limits\":["
    for (x = 1; x <= N; x++) {
        i = O[x]
        pace(i)
        o = o (x > 1 ? "," : "") "{\"cli\":" js(C[i]) ",\"name\":" js(cliname(F[i])) ",\"label\":" opt(L[i]) \
            ",\"window_minutes\":" W[i] ",\"used_percent\":" P[i] ",\"resets_at\":" (R[i] > 0 ? R[i] : "null") \
            ",\"as_of\":" E[i] ",\"stale\":" (stale(i) ? "true" : "false") \
            ",\"elapsed_percent\":" (PE < 0 ? "null" : int(PE + 0.5)) ",\"pace\":" opt(PV) ",\"left_s\":" (PL == "-" ? "null" : PL) "}"
    }
    print o "]}"
}

BEGIN {
    now += 0; off += 0; mid += 0
    PACE_EARLY = 5; PACE_MARGIN = 5
    b = ENVIRON["B"]; dim = ENVIRON["DIM"]; e = ENVIRON["N"]
    NEED = ENVIRON["NEED"]; WARN = ENVIRON["WARN"]; RUN = ENVIRON["RUN"]; ACC = ENVIRON["ACC"]; DIM = dim
    load()
    if (mode == "tsv") tsv()
    else if (mode == "json") json()
    else view()
}
