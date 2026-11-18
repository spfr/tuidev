# lib/agents/awk/board_rows.awk — this machine as `agents board` reads it
# (board.sh says what the board is). From "sub" lines (board.sh:
# _agents_board_subs), then the need and triage rows and the records
# (_agents_with_needs), the rows another machine can ask for:
#   sys<TAB>SUMMARY
#   ses<TAB>PID@START<TAB>STATE<TAB>AGE<TAB>LABEL<TAB>KIND<TAB>TITLE<TAB>PROJECT
#       STATE, AGE and LABEL are the triage row's (awk/triage.awk); TITLE the
#       session's own task title ("-" for none)
#   kid<TAB>OWNER<TAB>ID<TAB>sub|cmd|ses<TAB>STATE<TAB>AGE<TAB>TEXT
#       what runs under session OWNER (its PID@START): a sub-agent (ID its
#       agent id, TEXT its type, STATE run while its transcript is being
#       written, else done, AGE seconds since its last line), a command or a
#       nested session (ID its PID@START, STATE its flags or "-", AGE its age)
#   phone<TAB>PID@START<TAB>hosted|mirror|off|none<TAB>NAME<TAB>PANE
#       right after its session, only while herdr-core is installed and only
#       for a session in a Herdr pane: whether Herdr's phone app reaches it
#       (hosted in herdr-core, or a mirror of its pane, NAME the terminal's
#       name there), or not (off: its pane is opted out of mirrors; none)
#   warn<TAB>TEXT     what is wrong here, worst first: a process past the
#       memory warning, a hog, what sessions left behind
# Variables: sys (the summary), warn_kib (AGENTS_MEM_WARN in KiB). Needs
# lib_fmt (mem). The phone's lines come first (hcphone.sh's
# _agents_hc_phone_feed): "phonecore" (herdr-core is installed),
# "phone<TAB>PANE<TAB>hosted|mirror<TAB>NAME" and "phoneoff<TAB>PANE".

function one(s) { gsub(/[[:cntrl:]]/, " ", s); gsub(/  +/, " ", s); sub(/^ /, "", s); sub(/ $/, "", s); return s == "" ? "-" : s }
# A process's name from its command line. An app's is its bundle's
# ("/Applications/Some App.app/Contents/…" is Some App: a path with spaces
# can't be cut at the first one); else the base name of its first word.
function base(s,   i, t) {
    if (substr(s, 1, 1) == "/" && (i = index(s, ".app/")) > 0) { t = substr(s, 1, i - 1); sub(/.*\//, "", t); if (t != "") return t }
    sub(/ .*/, "", s); sub(/.*\//, "", s); return s
}

# phone(pane): "KIND<TAB>NAME<TAB>PANE" for a session in that Herdr pane. A
# hosted agent is reached whatever the opt-out says; an opted-out pane's
# mirror is ending (agents hc mirror off ends it, else the next sync).
function phone(pn) {
    if (!(pn in phk)) return ((pn in phoff) ? "off" : "none") "\t-\t" pn
    if (phk[pn] != "hosted" && (pn in phoff)) return "off\t-\t" pn
    return phk[pn] "\t" phn[pn] "\t" pn
}

$1 == "sub" { nsub[$2]++; subl[$2, nsub[$2]] = $3 "\tsub\t" $6 "\t" $5 "\t" one($4); next }
$1 == "triage" { st[$2] = $3; ag[$2] = $4; lb[$2] = $5; next }
$1 == "agent" {
    if ($3 == "daemon") next
    order[++n] = $2; kind[$2] = $3; start[$2] = $9; proj[$2] = ($15 == "" ? "-" : $15)
    next
}
$1 == "herdr" { if ($4 != "" && $4 != "-") title[$2] = $4; if ($3 != "" && $3 != "-") hpane[$2] = $3; next }
$1 == "phonecore" { hcon = 1; next }
$1 == "phone" { if ($3 == "hosted" || $3 == "mirror") { phk[$2] = $3; phn[$2] = ($4 == "" ? "-" : $4) } next }
$1 == "phoneoff" { phoff[$2] = 1; next }
$1 == "act" {
    if ($3 != "tool" && $3 != "session") next
    o = $11
    nk[o]++
    kl[o, nk[o]] = $2 "@" $9 "\t" ($3 == "tool" ? "cmd" : "ses") "\t" ($16 == "" ? "-" : $16) "\t" $4 "\t" one($14)
    next
}
$1 == "stale" { nstale++; next }
$1 == "hog" {
    if ($7 + 0 >= warn_kib && warn_kib > 0) big[++nbig] = base($14) " holds " mem($7)
    else hot[++nhot] = base($14) " at " int($5) "% CPU"
    next
}
END {
    print "sys\t" one(sys)
    for (i = 1; i <= n; i++) {
        p = order[i]; t = p "@" start[p]
        print "ses\t" t "\t" ((p in st) ? st[p] : "unknown") "\t" ((p in ag) ? ag[p] : "-") "\t" ((p in lb) ? one(lb[p]) : "no signal") \
            "\t" kind[p] "\t" ((p in title) ? one(title[p]) : "-") "\t" one(proj[p])
        if (hcon && (p in hpane)) print "phone\t" t "\t" phone(hpane[p])
        for (j = 1; j <= nsub[p]; j++) print "kid\t" t "\t" subl[p, j]
        for (j = 1; j <= nk[p]; j++) print "kid\t" t "\t" kl[p, j]
    }
    for (i = 1; i <= nbig; i++) print "warn\t" big[i]
    for (i = 1; i <= nhot; i++) print "warn\t" hot[i]
    if (nstale) print "warn\t" nstale " left behind"
}
