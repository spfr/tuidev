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
#   warn<TAB>TEXT     what is wrong here, worst first: a process past the
#       memory warning, a hog, what sessions left behind
# Variables: sys (the summary), warn_kib (AGENTS_MEM_WARN in KiB). Needs
# lib_fmt (mem).

function one(s) { gsub(/[[:cntrl:]]/, " ", s); gsub(/  +/, " ", s); sub(/^ /, "", s); sub(/ $/, "", s); return s == "" ? "-" : s }
function base(s) { sub(/ .*/, "", s); sub(/.*\//, "", s); return s }

$1 == "sub" { nsub[$2]++; subl[$2, nsub[$2]] = $3 "\tsub\t" $6 "\t" $5 "\t" one($4); next }
$1 == "triage" { st[$2] = $3; ag[$2] = $4; lb[$2] = $5; next }
$1 == "agent" {
    if ($3 == "daemon") next
    order[++n] = $2; kind[$2] = $3; start[$2] = $9; proj[$2] = ($15 == "" ? "-" : $15)
    next
}
$1 == "herdr" { if ($4 != "" && $4 != "-") title[$2] = $4; next }
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
        for (j = 1; j <= nsub[p]; j++) print "kid\t" t "\t" subl[p, j]
        for (j = 1; j <= nk[p]; j++) print "kid\t" t "\t" kl[p, j]
    }
    for (i = 1; i <= nbig; i++) print "warn\t" big[i]
    for (i = 1; i <= nhot; i++) print "warn\t" hot[i]
    if (nstale) print "warn\t" nstale " left behind"
}
