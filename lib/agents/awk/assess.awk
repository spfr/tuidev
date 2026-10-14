# lib/agents/awk/assess.awk — agents_assess: the evidence and the verdict for
# each item that needs you (assess.sh documents the need and evid rows).

function age(s) {
    s = int(s); if (s < 0) s = 0
    if (s < 60) return s "s"
    if (s < 3600) return int(s / 60) "m"
    if (s < 86400) return int(s / 3600) "h" int((s % 3600) / 60) "m"
    return int(s / 86400) "d" int((s % 86400) / 3600) "h"
}
function tilde(p) { return (home != "" && index(p, home "/") == 1) ? "~" substr(p, length(home) + 1) : p }
# A path short enough for a menu line: ~/…/dir/file.
function shortp(p,   n, a) {
    p = tilde(p); if (length(p) <= 60) return p
    n = split(p, a, "/")
    p = a[n - 1] "/" a[n]; if (length(p) > 54) p = substr(a[n], 1, 54)
    return (a[1] == "~" ? "~/" : "/") "\342\200\246/" p
}
function plist(s,   n, a, i, o) {
    n = split(s, a, ","); o = ""
    for (i = 1; i <= n && i <= 3; i++) o = o (i > 1 ? ", " : "") ":" a[i]
    return n > 3 ? o " +" (n - 3) : o
}
# A log line as display text: color codes gone, spaces squeezed, 80 chars.
function tidy(s, max) {
    gsub(/\[[0-9;]*m/, "", s); gsub(/[\001-\037\177]/, " ", s)
    gsub(/  +/, " ", s); sub(/^ /, "", s); sub(/ $/, "", s)
    if (length(s) > max) { s = substr(s, 1, max - 3); sub(/[\300-\377][\200-\277]*$/, "", s); s = s "..." }
    return s
}
# The last line of a log says the work is over: Claude Code task output
# ("[exited with code 0]"), "exit 1", test runners (ok, PASS, FAIL, --- FAIL,
# pytest and cargo summaries), done/finished/error.
function marker(s,   l) {
    l = tolower(s)
    if (l ~ /^\[exited with code -?[0-9]+\]$/) return 1
    if (l ~ /^((process|command|task) )?exit(ed)?( with)?( (code|status))?[ :=]*-?[0-9]+[.!]?$/) return 1
    if (l ~ /^(ok|pass|passed|fail|failed|failure|done|success|succeeded|successful|finished|complete|completed|error)([^a-z]|$)/) return 1
    if (l ~ /^--- (pass|fail)/ || l ~ /^=+ .*(passed|failed|error)/ || l ~ /^test result: / || l ~ /^ran all test suites/) return 1
    return 0
}
function owner(r) {
    if (!(r in akind)) return "session " r
    return akind[r] " " r (aproj[r] != "-" ? " in " aproj[r] : "") (astat[r] != "-" ? " (" astat[r] ")" : "")
}
# proven(tok): a sample saw this pid@start under an agent (sample.state, read
# once, only when a stale tree needs it).
function proven(tok,   line, f) {
    if (!seen_read++) {
        while ((getline line < ENVIRON["AGENTS_SEEN"]) > 0) if (split(line, f, "\t") >= 3 && f[3] == 1) seenp[f[1]] = 1
        close(ENVIRON["AGENTS_SEEN"])
    }
    return (tok in seenp)
}
function fact(s) { facts = facts "evid\t" P "\tfact\t" s "\n" }
function hint(s) { facts = facts "evid\t" P "\tnext\t" s "\n" }
function verdict(a, c, code, text) { ACT = a; CONF = c; CODE = code; TEXT = text }
# judge(f) — fills the verdict for one record (split into f) and prints it.
function judge(f,   t, cls, fl, ports, root, cwd, w, have, rd, hv, quiet, last, mk, stuck2, nope, lbl, tok, pa, pv) {
    t = f[1]; P = f[2]; facts = ""; AUTO = 0; nope = ""
    ports = (f[10] == "" ? "-" : f[10]); cwd = (f[13] == "" ? "-" : f[13])
    tok = f[2] "@" f[9]; quiet = "-"; last = "-"; mk = "-"; w = "-"; OWN = "-"
    if (t == "stale") {
        FLAG = "stale"
        fact("owner: none, its session ended (the process now belongs to pid 1)")
        fact("running " age(f[4]) " \302\267 " int(f[5] + 0.5) "% CPU")
        if (ports != "-") fact("listens on " plist(ports))
        if (cwd != "-") fact("in " shortp(cwd))
        if (ports != "-") {
            split(ports, pa, ",")
            verdict("check", "medium", "server-orphan", "check first \342\200\224 a server on " plist(ports) ", left behind when its session ended")
            hint("leave it if you still use it (http://localhost:" pa[1] "); otherwise stop it")
            nope = "it listens on a port, and a server an agent started for you may still be wanted"
        } else if (!lsok) {
            verdict("check", "medium", "ports-unknown", "check first \342\200\224 its session ended, but the port check was unavailable")
            fact("listening ports could not be listed (no lsof or ss, or it failed)")
            hint("if it serves nothing you use, stop it")
            nope = "the port check was unavailable, so it may be a server you use"
        } else {
            pv = proven(tok)
            if (pv) {
                fact("ran under an agent session before it ended (agents sample saw it)")
                verdict("stop", "high", "session-ended", "safe to stop \342\200\224 its session ended")
            } else verdict("stop", "medium", "session-ended", "safe to stop \342\200\224 probably left by an agent session that ended")
            hint("nothing uses it any more: its session is gone")
            if (!pv) nope = "no sample saw it under an agent" (hist ? "" : " (AGENTS_HISTORY=0 records none)") ", so it may be yours"
            else if (f[14] ~ /(^|\/)caffeinate( |$)/ && f[14] !~ / -[A-Za-z]*t *[0-9]/) nope = "a caffeinate without -t keeps the Mac awake until stopped, which you may want"
            else AUTO = 1
        }
        hint("stop it: agents kill " tok)
    } else if (t == "act") {
        cls = f[3]; fl = "," f[16] ","; root = f[11]; OWN = root
        fact("owner: " owner(root))
        fact((index(fl, ",wait,") ? "waiting " : "running ") age(f[4]) " \302\267 " int(f[5] + 0.5) "% CPU")
        if (ports != "-") fact("listens on " plist(ports))
        if (cls == "tool" && index(fl, ",wait,")) {
            FLAG = index(fl, ",stuck,") ? "stuck" : "wait"
            w = (P in wpath) ? wpath[P] : "-"
            have = (w != "-" && wm[P] != "-")
            # rd: its condition reads the file (tail, grep…), so how long the
            # file has been quiet is evidence; not for [ -f lock ] (exists).
            rd = !((P in wrd) && !wrd[P]); hv = (have && rd)
            if (have) {
                quiet = now - wm[P]; if (quiet < 0) quiet = 0
                fact("watches " shortp(w))
                if (rd) {
                    last = (wl[P] == "-" ? "" : tidy(wl[P], 80)); mk = marker(last)
                    fact("last line: " (last == "" ? "(none: the file is empty)" : last) (mk ? " (a completion marker)" : ""))
                } else fact("its condition only tests whether the file exists, so how long it has been quiet says nothing")
                fact(quiet < 60 ? "file changed just now" : (quiet < stuck ? "file changed " age(quiet) " ago" : "file quiet for " age(quiet)))
                hint("look at it: " (rd ? "tail -5 " : "ls -l ") (index(w, " ") ? "\"" w "\"" : tilde(w)))
            } else if (w != "-") fact("watches " shortp(w) ", which no longer exists")
            else fact("watches no file agents can check, so only its age counts")
            stuck2 = (stuck > 0 && hv && quiet >= 2 * stuck)
            if (FLAG == "stuck") {
                if (hv && mk) verdict("stop", "high", "finished", "safe to stop \342\200\224 what it waits for already finished (" tidy(last, 40) ", " age(quiet) " ago)")
                else if (hv) verdict("stop", "high", "quiet", "safe to stop \342\200\224 nothing has written to the file it watches for " age(quiet))
                else if (have) verdict("check", "medium", "exists-only", "check first \342\200\224 waiting " age(f[4]) " on whether " shortp(w) " exists")
                else if (w != "-") verdict("check", "medium", "gone", "check first \342\200\224 the file it watches is gone; waiting " age(f[4]))
                else verdict("check", "medium", "age-only", "check first \342\200\224 waiting " age(f[4]) ", with no file to judge by (age only)")
                if (stuck2) AUTO = 1
                else if (!have) nope = "nothing but its age says it is stuck"
                else if (!rd) nope = "it only tests whether its file exists, so the file being quiet proves nothing"
                else nope = "its file has been quiet less than " age(2 * stuck) " (2 x AGENTS_WAIT_STUCK)"
            } else if (hv && quiet < stuck && !mk) {
                verdict("leave", "high", "file-active", "leave it \342\200\224 the file it watches changed " (quiet < 60 ? "just now" : age(quiet) " ago") ": something still writes it")
                nope = "its file is still being written, so it is not stuck"
            } else if (hv && mk && quiet >= 120) {
                verdict("check", "medium", "finished-young", "check first \342\200\224 what it waits for looks finished (" tidy(last, 40) ", " age(quiet) " ago), but it keeps waiting")
                nope = "it has not waited " age(stuck) " (AGENTS_WAIT_STUCK) yet"
            } else {
                verdict("info", "high", "waiting", "informational \342\200\224 waiting " age(f[4]) (stuck > 0 ? " (stuck after " age(stuck) ")" : ""))
                nope = "it is not stuck"
            }
            hint("stopping it ends only the loop: the session sees the command fail and carries on")
        } else if (cls == "tool") {
            FLAG = index(fl, ",long,") ? "long" : index(fl, ",dup,") ? "dup" : "tool"
            if (cwd != "-") fact("in " shortp(cwd))
            if (index(fl, ",dup,")) fact("the same command runs " f[17] "\303\227 in this directory")
            if (FLAG == "long" && ports != "-") {
                verdict("check", "medium", "server", "check first \342\200\224 dev server on " plist(ports) ", its session is still active")
                hint("a dev server runs until stopped on purpose: leave it while you use it")
            } else if (FLAG == "dup") {
                verdict("check", "medium", "dup", "check first \342\200\224 the same command runs " f[17] "\303\227 in this directory")
                hint("keep the newest: the menu has Stop duplicates (keep newest)")
            } else {
                verdict("info", "high", FLAG == "long" ? "long" : "running", "informational \342\200\224 running " age(f[4]) (index(fl, ",hot,") ? " at " int(f[5] + 0.5) "% CPU" : "") "; its session is still active")
                hint("builds, test suites and servers often run this long; look at it if you expected it to end")
            }
            nope = "it belongs to a live session and is not stuck"
        } else {
            FLAG = cls
            verdict("info", "high", "live", "informational \342\200\224 part of a live session; it ends with the session")
            nope = "it belongs to a live session"
        }
        hint("stop it: agents kill " tok)
    } else if (t == "agent") {
        FLAG = "agent"; OWN = "-"
        fact("a " f[3] " session" (f[15] != "-" ? " in " f[15] : "") (f[12] != "-" ? " (" f[12] ")" : ""))
        fact("running " age(f[4]) " \302\267 " int(f[5] + 0.5) "% CPU \302\267 " f[8] " child processes")
        verdict("info", "high", "session", "informational \342\200\224 a live agent session")
        hint("kill it only when you are done with it: agents kill " tok)
        nope = "it is a session"
    } else {
        FLAG = "hog"; OWN = "-"
        fact(int(f[5] + 0.5) "% CPU now \302\267 " int(f[6] + 0.5) "% on average over " age(f[4]) " \302\267 owned by " f[11])
        verdict("check", "medium", "hog", "check first \342\200\224 " f[3] " uses " int(f[5] + 0.5) "% CPU")
        hint("quit it normally if you can; agents term " tok " sends it SIGTERM")
        nope = "it is not an agent leftover"
    }
    if (AUTO) facts = facts "evid\t" P "\tauto\t" (autoon ? "auto-reap is on: it stops this within a minute" : "auto-reap (AGENTS_AUTO_REAP=1) would stop this on its own") "\n"
    else facts = facts "evid\t" P "\tauto\tauto-reap never stops this: " nope "\n"
    lbl = (ACT == "stop" ? "safe to stop" : ACT == "check" ? "check first" : ACT == "leave" ? "leave it" : "informational")
    print "need", P, f[9], FLAG, ACT, CONF, CODE, AUTO, OWN, lbl, TEXT, (OWN in akind ? akind[OWN] : "-"), (OWN in aproj ? aproj[OWN] : "-"),
        f[4] + 0, f[5] + 0, ports, w, quiet, (last == "" ? "-" : last), mk
    printf "%s", facts
}
BEGIN {
    now = ENVIRON["NOW"] + 0; home = ENVIRON["HOME"]; target = ENVIRON["AGENTS_TARGET"]
    stuck = 60 * ENVIRON["AGENTS_WAIT_STUCK"]; autoon = (ENVIRON["AGENTS_AUTO_REAP"] == 1)
    hist = (ENVIRON["AGENTS_HISTORY"] == 1); lsok = 1
}
$1 == "probe" && $2 == "listen" { lsok = ($3 != "fail"); next }
$1 == "watched" { wpath[$2] = $3; wm[$2] = $4; wl[$2] = $5; wrd[$2] = ($6 != "exists"); next }
NF < 14 { next }
$1 == "agent" { akind[$2] = $3; aproj[$2] = ($15 == "" ? "-" : $15); astat[$2] = $12 }
$1 == "agent" || $1 == "act" || $1 == "stale" || $1 == "hog" { row[++n] = $0 }
END {
    # With a target: its best record (a stale tree before a command before
    # a session before a hog: one pid can be listed as two).
    best = 0; bw = 0
    for (i = 1; i <= n; i++) {
        split(row[i], f, "\t")
        if (target != "") {
            if (f[2] != target) continue
            r = (f[1] == "stale" ? 4 : f[1] == "act" ? 3 : f[1] == "agent" ? 2 : 1)
            if (r > bw) { bw = r; best = i }
            continue
        }
        if (f[1] == "stale" || (f[1] == "act" && f[3] == "tool" && f[16] ~ /(^|,)(stuck|long|dup)(,|$)/)) judge(f)
    }
    if (best) { split(row[best], f, "\t"); judge(f) }
}
