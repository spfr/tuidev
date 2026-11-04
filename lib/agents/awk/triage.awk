# lib/agents/awk/triage.awk — what state each session is in, the one place
# that decides it (triage.sh says what each state means and why). From the
# records on stdin, one row per session:
#   triage PID STATE AGE LABEL
# STATE: need, review, run, parked or unknown. AGE: seconds in that state ("-"
# unknown; a running session: since it started). LABEL: what to call it:
# permission, done, tests 3m12s, working, idle, no signal.
# Variables: now, PARKED_S, wf (waits.now), busy (the CPU% that says a session
# with no other evidence works), fresh (how old a record may be and still say
# what happened since); ENVIRON T_HOOKS (the open hook waits: the lines of
# waiting/*), T_NOTIFY (notify.tsv's end, while one blocks). Needs lib_fmt.

# job_label J — a job as a session's activity; "" when it says nothing.
function job_label(j) {
    if (j == "test") return "tests"
    if (j == "build") return "builds"
    if (j == "browser") return "browser"
    if (j == "wait") return "waiting"
    return ""
}
# doing P — what running session P does: its busiest command's job and how long
# it has run. A dev server idling at 0% or a polling loop says little, so those
# count only when nothing else runs.
function doing(p,   i, f, b, bs, s, l) {
    b = 0; bs = -1
    for (i = 1; i <= nt; i++) {
        split(tl[i], f, "\t")
        if (f[11] != p) continue
        s = f[5] + (ujob[f[2]] == "test" || ujob[f[2]] == "build" ? 1000 : 0) - (ujob[f[2]] == "wait" ? 1000 : 0)
        if (s > bs || !b) { b = i; bs = s }
    }
    if (!b) return "working"
    split(tl[b], f, "\t")
    l = job_label(ujob[f[2]])
    return l == "" ? "working" : l " " dur(f[4])
}
# blocked_label T SINCE — why session T blocks: the kind of the notification
# that said so, when one came with this wait; else just blocked.
function blocked_label(t, since,   n, a, g, i, k) {
    n = split(ENVIRON["T_NOTIFY"], a, "\n")
    k = ""
    for (i = n; i >= 1 && k == ""; i--)
        if (split(a[i], g, "\t") >= 4 && g[2] == t && g[1] + 0 >= (since == "-" ? now - 600 : since - 120)) k = g[4]
    if (k == "" || k == "-" || k == "Idle") return "blocked"
    return tolower(k)
}
function emit(p, st, ag, lb) { print "triage\t" p "\t" st "\t" ag "\t" lb }
# since_change T — seconds since session T's last sample, the latest it can have
# changed status, while that sample is recent; "-" otherwise.
function since_change(t,   a) {
    if (!(t in WSt)) return "-"
    a = now - WLa[t]
    return a > fresh ? "-" : (a < 0 ? 0 : a)
}
# held T P S — seconds session T (pid P) has been S, from waits.now, and only
# from the latest stretch. Herdr numbers each state change: the number the record
# holds says for certain whether this is its stretch, however old the record.
# Without one, a record too old to say what happened since says nothing, and one
# flagged "~" knows only a lower bound: no use until that alone is past the
# threshold. "-" unknown: a session never skips To review on a guess.
function held(t, p, s,   a) {
    if (!(t in WSt)) return "-"
    if ((p in HQ) && WSq[t] ~ /^[0-9]+$/)
        return (WSt[t] == s && WSq[t] == HQ[p]) ? now - WSi[t] : since_change(t)
    if (now - WLa[t] > fresh) return "-"
    if (WSt[t] != s) return since_change(t)
    a = now - WSi[t]
    return (WSq[t] == "~" && a < PARKED_S) ? "-" : a
}
# rested_since T P — how long idle session T has sat: since it finished, when the
# record holds the done you then looked at; else as held.
function rested_since(t, p,   a) {
    if ((t in WSt) && WSt[t] == "done") return now - WLa[t] > fresh ? "-" : now - WSi[t]
    return held(t, p, "idle")
}
# rested P AGE — to review, until AGE (when known) passes the threshold.
function rested(p, a) {
    if (a != "-" && a >= PARKED_S) emit(p, "parked", a, "done")
    else emit(p, "review", a, "done")
}
function judge(r,   f, t, h, a) {
    split(r, f, "\t")
    t = f[2] "@" f[9]; h = f[12]
    if (h == "blocked") { a = held(t, f[2], h); emit(f[2], "need", a, blocked_label(t, a == "-" ? "-" : now - a)); return }
    if (h == "done") { rested(f[2], held(t, f[2], "done")); return }
    if (h == "idle") { emit(f[2], "parked", rested_since(t, f[2]), "idle"); return }
    if (h == "working") { emit(f[2], "run", f[4] + 0, doing(f[2])); return }
    # Outside Herdr: what Claude Code's hooks recorded.
    if (t in HSt) {
        a = now - HSi[t]; if (a < 0) a = 0
        if (HSt[t] == "blocked") emit(f[2], "need", a, blocked_label(t, HSi[t]))
        else rested(f[2], a)
        return
    }
    # Nothing says. Running while it runs a command or uses the CPU; otherwise it
    # may be finished, thinking, or waiting for you: no signal is not parked, so
    # it keeps a row of its own.
    if ((f[2] in tools) || f[5] + 0 >= busy) emit(f[2], "run", f[4] + 0, doing(f[2]))
    else emit(f[2], "unknown", "-", "no signal")
}
BEGIN {
    FS = "\t"; now += 0; PARKED_S += 0; fresh += 0
    while ((getline ln < wf) > 0)
        if (split(ln, g, "\t") >= 4) { WSt[g[1]] = g[2]; WSi[g[1]] = g[3] + 0; WLa[g[1]] = g[4] + 0; WSq[g[1]] = g[5] == "" ? "-" : g[5] }
    close(wf)
    n = split(ENVIRON["T_HOOKS"], hk, "\n")
    # start status project PID@START
    for (i = 1; i <= n; i++) if (split(hk[i], g, "\t") >= 4 && (g[2] == "blocked" || g[2] == "done")) { HSt[g[4]] = g[2]; HSi[g[4]] = g[1] + 0 }
}
$1 == "hstate" { HQ[$2] = $3; next }
$1 == "agent" && NF >= 14 && $3 != "daemon" { ag[++na] = $0; next }
$1 == "act" && $3 == "tool" { tl[++nt] = $0; tools[$11] = 1; next }
$1 == "job" && $10 == "own" { ujob[$11] = $3; next }
END { for (i = 1; i <= na; i++) judge(ag[i]) }
