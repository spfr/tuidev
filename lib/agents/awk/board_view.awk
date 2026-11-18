# lib/agents/awk/board_view.awk — `agents board`: the list fzf shows and the
# top of its right-hand pane, from every machine's rows (awk/board_rows.awk),
# each prefixed with its machine's label ("local" for this one).
#
# What a machine sends is UNTRUSTED text, checked here and nowhere else: an id
# is used only when it has the shape of one, a state only when it is one of
# ours, no control character reaches the terminal (lib_maprows' clean), and
# every text has a length.
#
# -v mode=
#   list   the list, one line a thing:  MACHINE<TAB>KIND<TAB>ID<TAB>OWNER<TAB>TEXT
#          KIND head (ID a group: need review run unknown parked), mach (a
#          machine's heading), ses, kid (OWNER its session; "-" otherwise),
#          gap (an empty line between two groups).
#          -v lens=attention|tree|machines, -v all=1 lists the parked,
#          -v W= the columns the list has, -v hf= a file for the header (the
#          counts, ENVIRON LIMITS, the first warning).
#   card   the top of a session's card (-v cm= its machine, -v cid= its id)
#   kid    the same for what runs under one (-v cowner= its session)
#   group  a group's roll-up (-v cid= the group)
#   mach   a machine's (-v cm=)
# -v glyphs= the kinds' marks (glyph.sh). ENVIRON: the colors (B DIM NEED DONE
# RUN WARN ACC N), AGENTS_ASCII. Needs lib_fmt and lib_maprows.

function okstate(s) { return s == "need" || s == "review" || s == "run" || s == "parked" || s == "unknown" }
function oknum(s) { return s ~ /^[0-9]+$/ && length(s) <= 10 }
function txt(s, n) { s = clean(s); gsub(/  +/, " ", s); return substr(s, 1, n) }
function kmark(kind) {
    if (!gon) return ""
    if (kind in gmap) return gmap[kind]
    return ("agent" in gmap) ? gmap["agent"] : ""
}
function mk(n) {
    if (ENVIRON["AGENTS_ASCII"] != "")
        return n == "tee" ? "|-" : n == "end" ? "`-" : n == "ok" ? "v" : n == "cmd" ? "$" : n == "ses" ? ">" : n == "warn" ? "!" : n
    return n == "tee" ? "\342\224\234" : n == "end" ? "\342\224\224" : n == "ok" ? "\342\234\223" : n == "cmd" ? "\342\232\231" : \
        n == "ses" ? "\342\227\207" : n == "warn" ? "!" : n
}
function scolor(s) { return s == "need" ? NEED B : s == "review" ? DONE : s == "run" ? RUN : DIM }
function sname(i) { return stitle[i] != "-" ? stitle[i] : sproj[i] }
# What a session is doing, in a word or two.
function doing(i,   l) {
    l = slabel[i]
    if (sst[i] == "need") return l == "blocked" ? "waiting on you" : (l == "permission" ? "wants permission" : l)
    if (sst[i] == "review") return "finished"
    if (sst[i] == "parked") return "idle"
    return l
}
function since(i) { return sage[i] == "-" ? "" : age(sage[i] + 0) }
function counts(i,   o) {
    o = ""
    if (nsubs[i]) o = "+" nsubs[i] " sub"
    if (ncmds[i]) o = o (o == "" ? "+" : ", ") ncmds[i] " cmd"
    return o
}
# A machine is listed once it has sent any valid row, sys or not.
function seen(m) { if (!(m in mseen)) { mseen[m] = 1; mo[++nm] = m } }
# What a machine says about the sessions it sent beyond MAXSES.
function unshown(m) { return head("more", "+" dropped[m] " sessions not shown", m) }
function plural(n, one, many) { return n " " (n == 1 ? one : many) }
# A session's line: its state's shape, its kind's mark, a name that stays, what
# it does, since when, its machine (only when there is more than one) and a
# count of what runs under it.
function srow(i,   s, nc, dc, o) {
    s = sst[i]
    nc = s == "need" ? B : (s == "parked" ? DIM : "")
    dc = s == "need" ? NEED : (s == "review" ? DONE : DIM)
    o = " " scolor(s) gl(s) N "  " (gon ? DIM lc(kmark(skind[i]), gwid) N " " : "") nc lc(dcut(sname(i), NW), NW) N \
        "  " dc lc(dcut(doing(i), DW), DW) N "  " DIM rc(since(i), 5)
    if (multi && lens != "machines") o = o "  " lc(dcut(sm[i], MW), MW)
    if (EW) o = o "  " counts(i)
    return sm[i] "\tses\t" sid[i] "\t-\t" o N
}
function krow(i, k, last,   m, c, right) {
    if (ktype[i, k] == "sub") { m = (kstate[i, k] == "run") ? RUN gl("run") N : DIM mk("ok") N; right = (kstate[i, k] == "run") ? "running" : "done" }
    else { m = DIM mk(ktype[i, k]) N; right = (kstate[i, k] == "-") ? "" : kstate[i, k] }
    return sm[i] "\tkid\t" kid[i, k] "\t" sid[i] "\t" "     " DIM mk(last ? "end" : "tee") N " " m "  " \
        lc(dcut(ktext[i, k], KW), KW) " " DIM lc(dcut(right, 9), 9) " " rc(kage[i, k] == "-" ? "" : age(kage[i, k] + 0), 5) N
}
# A heading: in its group's color, on the rows' left edge.
function head(id, title, note,   c) {
    c = id == "need" ? NEED B : id == "review" ? DONE B : id == "run" ? RUN B : DIM
    return "-\thead\t" id "\t-\t" " " c title N (note == "" ? "" : "  " DIM note N)
}
# An empty line between two groups (a row of its own: fzf has no other gap).
function gap() { if (shown++) print "-\tgap\t" shown "\t-\t" }
function folded() { gap(); print head("parked", "PARKED", cnt["parked"] "  " gl("dot") "  press . to show") }
function group(s, title,   i, any) {
    if (!cnt[s]) return
    gap()
    print head(s, title, cnt[s])
    for (i = 1; i <= ord[s, 0]; i++) print srow(ord[s, i])
}
# The sessions of state S, in the order to read them: the longest wait first
# for what waits on you, the newest first for what finished.
function sort(s,   i, j, t, n, desc) {
    n = 0
    for (i = 1; i <= ns; i++) if (sst[i] == s) ord[s, ++n] = i
    ord[s, 0] = n
    if (s != "need" && s != "review" && s != "parked") return
    desc = (s == "need")
    for (i = 2; i <= n; i++) {
        t = ord[s, i]
        for (j = i - 1; j >= 1 && (desc ? sage[ord[s, j]] + 0 < sage[t] + 0 : sage[ord[s, j]] + 0 > sage[t] + 0); j--) ord[s, j + 1] = ord[s, j]
        ord[s, j + 1] = t
    }
}
function rollup(m,   i, k, kinds, o, c, st) {
    kinds = ""
    for (i = 1; i <= ns; i++) if (sm[i] == m) { if (!((m, skind[i]) in rk)) rko[m, ++rkn[m]] = skind[i]; rk[m, skind[i]]++; rs[m, sst[i]]++ }
    for (k = 1; k <= rkn[m]; k++) kinds = kinds (kinds == "" ? "" : ", ") rk[m, rko[m, k]] " " rko[m, k]
    o = ""
    if (rs[m, "need"]) o = plural(rs[m, "need"], "needs you", "need you")
    if (rs[m, "review"]) o = o (o == "" ? "" : ", ") rs[m, "review"] " to review"
    if (rs[m, "run"]) o = o (o == "" ? "" : ", ") rs[m, "run"] " working"
    if (rs[m, "parked"]) o = o (o == "" ? "" : ", ") rs[m, "parked"] " parked" ((mode == "list" && !all) ? ", hidden" : "")
    if (rs[m, "unknown"]) o = o (o == "" ? "" : ", ") rs[m, "unknown"] " no signal"
    return kinds == "" ? "no sessions" : kinds "; " o
}
function header(   o, w, more) {
    o = ""
    if (cnt["need"]) o = o "   " NEED B gl("need") " " plural(cnt["need"], "needs you", "need you") N
    if (cnt["review"]) o = o "   " DONE gl("review") " " cnt["review"] " to review" N
    if (cnt["run"]) o = o "   " RUN gl("run") N " " cnt["run"] " working"
    if (cnt["unknown"]) o = o "   " DIM "? " cnt["unknown"] " no signal" N
    if (cnt["parked"]) o = o "   " DIM gl("parked") " " cnt["parked"] " parked" N
    if (o == "") o = "   " DIM "no sessions" N
    printf "%s", substr(o, 3) > hf
    if (ENVIRON["LIMITS"] != "") printf "\n %s%s%s", DIM, txt(ENVIRON["LIMITS"], 160), N > hf
    if (nw) {
        more = nw > 1 ? "  (+" (nw - 1) " more)" : ""
        printf "\n\n %s%s %s%s%s%s", WARN, mk("warn"), (multi ? wm[1] ": " : ""), wt[1], more, N > hf
    }
    printf "\n\n" > hf
    close(hf)
}
function find(m, id,   i) { for (i = 1; i <= ns; i++) if (sm[i] == m && sid[i] == id) return i; return 0 }
function state_line(i,   s, a) {
    s = sst[i]; a = since(i)
    if (s == "need") return NEED B gl("need") " needs you" (a == "" ? "" : " " gl("dot") " " a) N "  " NEED doing(i) N
    if (s == "review") return DONE gl("review") " finished" (a == "" ? "" : " " a " ago") ", not looked at" N
    if (s == "run") return RUN gl("run") N " " doing(i) (a == "" ? "" : DIM " " gl("dot") " running " a N)
    if (s == "parked") return DIM gl("parked") " idle" (a == "" ? "" : " for " a) N
    return DIM "? no signal: nothing says what it is doing" N
}
function under(i,   k, m, right) {
    if (!nkids[i]) return
    printf "\n %sRUNNING UNDER IT%s\n", DIM, N
    for (k = 1; k <= nkids[i]; k++) {
        if (ktype[i, k] == "sub") { m = (kstate[i, k] == "run") ? RUN gl("run") N : DIM mk("ok") N; right = (kstate[i, k] == "run") ? "running" : "done" }
        else { m = DIM mk(ktype[i, k]) N; right = (kstate[i, k] == "-") ? "" : kstate[i, k] }
        printf "  %s  %s %s%s %s%s\n", m, lc(dcut(ktext[i, k], 30), 30), DIM, lc(right, 9), rc(kage[i, k] == "-" ? "" : age(kage[i, k] + 0), 5), N
    }
}

BEGIN {
    B = ENVIRON["B"]; DIM = ENVIRON["DIM"]; NEED = ENVIRON["NEED"]; DONE = ENVIRON["DONE"]; RUN = ENVIRON["RUN"]
    WARN = ENVIRON["WARN"]; ACC = ENVIRON["ACC"]; N = ENVIRON["N"]
    n = split(glyphs, gw, " ")
    for (i = 1; i <= n; i++) if ((k = index(gw[i], "=")) > 1) { gmap[substr(gw[i], 1, k - 1)] = substr(gw[i], k + 1); gon = 1 }
    gwid = 1
    MAXSES = 200    # sessions one machine may have on the board
    for (k in gmap) if (dw(gmap[k]) > gwid) gwid = dw(gmap[k])
}
{ $1 = txt($1, 64) }
$1 == "" { next }
$2 == "sys" { seen($1); msys[$1] = txt($3, 120); next }
$2 == "ses" {
    if (!mr_idok($3) || !okstate($4) || $7 !~ /^[a-z0-9-]+$/ || length($7) > 24) next
    seen($1)
    if (nses[$1] >= MAXSES) { dropped[$1]++; next }
    nses[$1]++
    ns++; sm[ns] = $1; sid[ns] = $3; sst[ns] = $4; sage[ns] = oknum($5) ? $5 : "-"
    slabel[ns] = txt($6, 40); skind[ns] = $7; stitle[ns] = txt($8, 120); sproj[ns] = txt($9, 64)
    if (stitle[ns] == "") stitle[ns] = "-"
    if (sproj[ns] == "") sproj[ns] = "-"
    cnt[$4]++; idx[$1, $3] = ns
    next
}
$2 == "kid" {
    if (!(($1, $3) in idx) || ($5 != "sub" && $5 != "cmd" && $5 != "ses")) next
    if ($5 == "sub" ? ($4 !~ /^[A-Za-z0-9_-]+$/ || $4 !~ /[A-Za-z]/ || length($4) > 64) : !mr_idok($4)) next
    seen($1)
    i = idx[$1, $3]
    if (nkids[i] >= 40) next
    k = ++nkids[i]
    kid[i, k] = $4; ktype[i, k] = $5; kstate[i, k] = txt($6, 24); kage[i, k] = oknum($7) ? $7 : "-"; ktext[i, k] = txt($8, 400)
    if (kstate[i, k] == "") kstate[i, k] = "-"
    if ($5 != "sub") ncmds[i]++
    else if ($6 == "run") nsubs[i]++
    next
}
$2 == "warn" { seen($1); if (nw < 20) { nw++; wm[nw] = $1; wt[nw] = txt($3, 120) } next }
END {
    multi = (nm > 1)
    if (mode == "card") {
        i = find(cm, cid)
        if (!i) { printf "\n %sIt is gone: the session ended.%s\n", DIM, N; exit }
        printf "\n %s%s%s\n %s%s %s %s%s%s\n\n %s\n", B, sname(i), N, DIM, sproj[i], gl("dot"), skind[i], (multi ? " " gl("dot") " " sm[i] : ""), N, state_line(i)
        under(i)
        exit
    }
    if (mode == "kid") {
        i = find(cm, cowner)
        for (k = 1; i && k <= nkids[i]; k++) if (kid[i, k] == cid) {
            printf "\n %s%s%s\n %s%s of %s%s\n", B, dcut(ktext[i, k], 60), N, DIM, \
                (ktype[i, k] == "sub" ? "a sub-agent" : ktype[i, k] == "cmd" ? "a command" : "a session"), sname(i), N
            if (ktype[i, k] == "sub") printf "\n %s%s\n", (kstate[i, k] == "run" ? RUN gl("run") N " running" : DIM mk("ok") " done"), \
                DIM (kage[i, k] == "-" ? "" : " " gl("dot") " last wrote " age(kage[i, k] + 0) " ago") N
            else printf "\n %s%s%s%s\n", DIM, (kage[i, k] == "-" ? "" : "running " age(kage[i, k] + 0)), (kstate[i, k] == "-" ? "" : " " gl("dot") " " kstate[i, k]), N
            exit
        }
        printf "\n %sIt is gone: it finished.%s\n", DIM, N
        exit
    }
    if (mode == "group") {
        if (cid == "need") printf "\n %sNeeds you%s\n %sblocked on an answer only you can give, the longest wait first%s\n", B, N, DIM, N
        else if (cid == "review") printf "\n %sTo review%s\n %sfinished and not looked at yet; one you open leaves this group%s\n", B, N, DIM, N
        else if (cid == "run") printf "\n %sWorking%s\n %snothing to do here until one asks or finishes%s\n", B, N, DIM, N
        else if (cid == "unknown") printf "\n %sNo signal%s\n %snothing says whether these work, wait or finished (agents ls)%s\n", B, N, DIM, N
        else if (cid == "parked") {
            printf "\n %sParked%s\n %sidle, and already looked at%s\n\n", B, N, DIM, N
            for (i = 1; i <= ns; i++) if (sst[i] == "parked")
                printf "  %s%s  %s %s%s%s\n", DIM, gl("parked"), lc(dcut(sname(i), 30), 30), rc(since(i), 5), (multi ? "  " sm[i] : ""), N
        }
        exit
    }
    if (mode == "mach") {
        printf "\n %s%s%s\n %s%s%s\n", B, cm, N, DIM, rollup(cm), N
        if (cm in msys) printf "\n  %s\n", msys[cm]
        for (i = 1; i <= nw; i++) if (wm[i] == cm) printf "\n  %s%s %s%s\n", WARN, mk("warn"), wt[i], N
        exit
    }

    # The list. Widths: the name takes what the rest leaves.
    if (W + 0 < 40) W = 80
    # What a session does and its name are as wide as the widest listed, so
    # no column stands apart from the next.
    DW = 4; MW = 0; KW = 30; NM = 8; EW = 0
    for (i = 1; i <= ns; i++) if (all || sst[i] != "parked") {
        if (dw(doing(i)) > DW) DW = dw(doing(i))
        if (dw(sname(i)) > NM) NM = dw(sname(i))
        if (multi && length(sm[i]) > MW) MW = length(sm[i])
        if (length(counts(i)) > EW) EW = length(counts(i))
    }
    if (DW > 16) DW = 16
    if (MW > 12) MW = 12
    # The count of what runs under a session goes first when the list is
    # narrow: a name is never cut for it.
    if (EW && W - (4 + (gon ? gwid + 1 : 0) + 2 + DW + 2 + 5 + (multi && lens != "machines" ? MW + 2 : 0) + EW + 2) - 2 < (NM < 20 ? NM : 20)) EW = 0
    NW = W - (4 + (gon ? gwid + 1 : 0) + 2 + DW + 2 + 5 + (multi && lens != "machines" ? MW + 2 : 0) + (EW ? EW + 2 : 0)) - 2
    if (NW > 60) NW = 60
    if (NW > NM) NW = NM
    if (NW < 8) NW = 8
    sort("need"); sort("review"); sort("run"); sort("unknown"); sort("parked")
    if (hf != "") header()
    if (!ns) { print head("-", "NO SESSIONS", "start an agent in any pane and it shows here"); exit }
    if (lens == "tree") {
        ng = split(all ? "need review run unknown parked" : "need review run unknown", go, " ")
        for (g = 1; g <= ng; g++) for (j = 1; j <= ord[go[g], 0]; j++) {
            i = ord[go[g], j]
            print srow(i)
            for (k = 1; k <= nkids[i]; k++) print krow(i, k, k == nkids[i])
        }
        shown = 1
        if (cnt["parked"] && !all) folded()
        for (m = 1; m <= nm; m++) if (dropped[mo[m]]) print unshown(mo[m])
        exit
    }
    if (lens == "machines") {
        for (m = 1; m <= nm; m++) {
            if (m > 1 && (nses[mo[m]] || nses[mo[m - 1]])) { shown = 1; gap() }
            print mo[m] "\tmach\t-\t-\t" " " B mo[m] N "  " DIM rollup(mo[m]) N
            ng = split(all ? "need review run unknown parked" : "need review run unknown", go, " ")
            for (g = 1; g <= ng; g++) for (j = 1; j <= ord[go[g], 0]; j++) if (sm[ord[go[g], j]] == mo[m]) print srow(ord[go[g], j])
            if (dropped[mo[m]]) print unshown(mo[m])
        }
        exit
    }
    group("need", "NEEDS YOU"); group("review", "TO REVIEW"); group("run", "WORKING"); group("unknown", "NO SIGNAL")
    if (cnt["parked"]) {
        if (all) group("parked", "PARKED")
        else folded()
    }
    for (m = 1; m <= nm; m++) if (dropped[mo[m]]) print unshown(mo[m])
}
