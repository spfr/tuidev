# lib/agents/awk/lib_maprows.awk — the checks for a row another machine sent
# (`agents map`: sys, proc, port, file, fwd), in one place, so the list and the
# menu bar's board accept or refuse the same row. What a machine sends is
# UNTRUSTED text: an id is used only when it has the shape of one, no control
# character reaches the terminal, and every text has a length.
#
#   clean(s)   s with no control character: C0 and DEL, C1 as UTF-8 writes it
#              (U+009B is another spelling of ESC [), and the characters that
#              reorder or break text (bidi embeddings, overrides and isolates,
#              U+2028, U+2029), each as a space;
#   tilde(p)   p with the home directory (-v home) written as ~;
#   mr_sys()   mr_proc()   mr_port()   mr_file()   mr_fwd()
#              check the current record ($1 is the machine, $2 the kind) and
#              return 1 with the row's fields in R_*, or 0 for no row.
#
# R_text  sys: the summary (at most 120 characters)
# R_id, R_pid, R_line   proc: PID or PID@START, its PID, the pick row (clean)
# R_port, R_ppid, R_cmd, R_cwd   port: its number, the PID of the process that
#              holds it or "-", the command, the project directory (clean)
# R_path, R_session   file: an absolute path of plain characters, its session
# R_flocal, R_flabel, R_fremote, R_fstate, R_fage   fwd: the local port, the
#              machine, its port, active|dead, minutes open
#
# The awk here runs under LC_ALL=C, so a character is its bytes.

function clean(s) {
    gsub(/[[:cntrl:]]/, " ", s)
    gsub(/\302[\200-\237]/, " ", s)
    gsub(/\342\200[\250-\256]/, " ", s)
    gsub(/\342\201[\246-\251]/, " ", s)
    return s
}
function tilde(p) { return (home != "" && index(p, home) == 1) ? "~" substr(p, length(home) + 1) : p }

# mr_idok(s): PID (at most 10 digits) or PID@START (START 1 to 48 of
# A-Z a-z 0-9 _ : + . -): the shape _AGENTS_MAP_ID_RE gives the keys.
function mr_idok(s,   p) {
    if (s !~ /^[0-9]+(@[A-Za-z0-9_:+.-]+)?$/) return 0
    p = s; sub(/@.*/, "", p)
    if (length(p) > 10) return 0
    if (length(s) > length(p) && length(s) - length(p) - 1 > 48) return 0
    return 1
}
function mr_numok(s, n) { return s ~ /^[0-9]+$/ && length(s) <= n }

function mr_sys() { R_text = substr(clean($3), 1, 120); return 1 }
function mr_proc() {
    if (!mr_idok($3)) return 0
    R_id = $3; R_pid = $3; sub(/@.*/, "", R_pid)
    R_line = clean($4)
    return 1
}
function mr_port() {
    if (!mr_numok($3, 5)) return 0
    R_port = $3
    R_ppid = mr_numok($4, 10) ? $4 : "-"
    R_cmd = clean($5); R_cwd = clean($6)
    return 1
}
function mr_file() {
    if ($3 !~ /^\/[A-Za-z0-9._ @+,=\/~-]+$/ || length($3) > 400) return 0
    R_path = $3; R_session = clean($4)
    return 1
}
# A forward is a row of this machine only: one another machine sends is no row.
function mr_fwd() {
    if ($1 != "local" || !mr_numok($3, 5) || $4 !~ /^[A-Za-z0-9._-]+$/ || length($4) > 64 || !mr_numok($5, 5) || $6 !~ /^(active|dead)$/ || !mr_numok($7, 9)) return 0
    R_flocal = $3; R_flabel = $4; R_fremote = $5; R_fstate = $6; R_fage = $7
    return 1
}
