# lib/agents/awk/show.awk — `agents show PID` (show.sh), in two phases over
# tab-separated rows on stdin: agents_collect's records, agents_assess's
# need/evid rows for PID, awk/show_tree.awk's proc/up rows, tmux's panes, and
# show.sh's
#   pane PANE_PID PLACE   each tmux pane (where it lives: lib_where.awk)
#   f KEY VALUE           what it gathered (session, activity, files, threads…)
#   info KEY VALUE        _agents_session_info's lines, when it is there
# -v t=PID. -v phase=who prints what PID is, for show.sh to gather the rest:
#   who CLASS KIND LABEL ROOT ROOTKIND ROOTAGE CWD PROJECT UNIT
# CLASS: agent (KIND claude, codex, daemon), what a session runs (mcp, tool,
# session, keepawake, other), stale, hog, child (inside UNIT, one of those),
# or process. -v phase=text (W, HOME, colors B DIM Y G R N, now) or json
# renders it. Needs lib_fmt, lib_json, lib_proc and lib_where.

function tilde(p) { return (p != "-" && home != "" && index(p, home) == 1) ? "~" substr(p, length(home) + 1) : p }
function v(k) { return (k in F) ? F[k] : "" }
function dash(s) { return s == "" ? "-" : s }
function nonempty(s) { return s != "" && s != "-" }
function line(k, s) { if (nonempty(s)) printf "%s%-9s%s %s\n", dim, k, e, cut(s, w - 10) }
function ago(at,   s) { s = now - at; return s < 0 ? "" : " (" age(s) " ago)" }
function num(x) { return (x == "" || x == "-") ? "null" : x + 0 }
BEGIN {
    FS = "\t"; home = ENVIRON["HOME"]; w = ENVIRON["W"] + 0; if (w < 60) w = 60
    b = ENVIRON["B"]; dim = ENVIRON["DIM"]; yel = ENVIRON["Y"]; red = ENVIRON["R"]; grn = ENVIRON["G"]; e = ENVIRON["N"]
    t += 0
}
$1 == "agent" && NF >= 14 { ag[$2] = $0 }
$1 == "act" && NF >= 14 { ac[$2] = $0 }
($1 == "stale" || $1 == "hog") && NF >= 14 && !(($2 + 0) in other) { other[$2 + 0] = $0 }
$1 == "proc" { if ($4 == 0) { self = $0; pp[$2 + 0] = $3 + 0; av[$2 + 0] = $11 } else { nk++; kid[nk] = $0; tr += $7 } }
$1 == "up" { nu++; up[nu] = $2 + 0; av[$2 + 0] = $3 }
$1 == "pane" { pane_ok = 1; pane[$2 + 0] = $3 }
$1 == "need" && $2 == t { need = $0 }
$1 == "evid" && $2 == t && $3 == "fact" { nev++; ev[nev] = $4 }
$1 == "f" { F[$2] = $3 }
$1 == "info" { ni++; ik[ni] = $2; iv[ni] = $3 }
END {
    for (i = 1; i < nu; i++) pp[up[i]] = up[i + 1]     # the ancestors, nearest first
    if (nu) pp[up[nu]] = 1
    split(where_of(t), wh, "\t")
    who()
    if (phase == "who") { printf "who\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", cls, dash(kind), dash(label), dash(root), dash(rkind), dash(rage), dash(cwd), dash(proj), dash(unit); exit }
    if (self == "") exit 1
    split(self, P, "\t")
    if (phase == "json") json(); else text()
}
# who(): what PID is, from the first record that names it (or, for a process
# deeper in a tree, the unit and session above it).
function who(   r, f, i, q) {
    cls = "process"; kind = label = root = rkind = rage = cwd = proj = unit = ""
    if ((t "") in ag) { split(ag[t], f, "\t"); cls = "agent"; kind = f[3]; root = t; cwd = f[13]; proj = f[15]; cmd = f[14] }
    else if ((t "") in ac) { split(ac[t], f, "\t"); cls = f[3]; label = f[12]; root = f[11]; cwd = f[13]; cmd = f[14] }
    else if (t in other) {
        split(other[t], f, "\t"); cls = f[1]; cmd = f[14]
        if (f[1] == "stale") { kind = f[3]; cwd = f[13]; proj = f[15] }
        if (f[1] != "stale") label = f[3]
    } else {
        for (i = 1; i <= nu; i++) {
            q = up[i] ""
            if (q in ac) { split(ac[q], f, "\t"); cls = "child"; unit = q; ucls = f[3]; label = (f[3] == "mcp" ? f[12] : ""); root = f[11]; break }
            if (q in ag) { cls = "child"; unit = q; root = q; break }
            if ((q + 0) in other) { split(other[q + 0], f, "\t"); if (f[1] == "stale") { cls = "child"; unit = q; ucls = "stale"; proj = f[15]; cwd = f[13] } break }
        }
    }
    if (root != "" && (root "") in ag) {
        split(ag[root], r, "\t"); rkind = r[3]; rage = r[4]; rstat = r[12]; rports = r[10]
        if (cwd == "" || cwd == "-") cwd = r[13]
        if (proj == "") proj = r[15]
    }
    if (cls == "agent") { rkind = kind }
    ports = "-"
    if ((t "") in ag) { split(ag[t], f, "\t"); ports = f[10] }
    else if ((t "") in ac) { split(ac[t], f, "\t"); ports = f[10] }
    else if (t in other) { split(other[t], f, "\t"); ports = f[10] }
}
function title(   s, c) {
    c = (cmd != "" ? cmd : P[11])
    if (cls == "agent") s = (kind == "daemon" ? "codex daemon" : kind " · " dash(proj))
    else if (cls == "mcp") s = "MCP server " label " · " dash(proj)
    else if (cls == "tool") s = "command · " c
    else if (cls == "session") s = "nested " rkind " session · " dash(proj)
    else if (cls == "keepawake") s = "keep-awake · " c
    else if (cls == "stale") s = "stale " (kind == "server" ? "dev server" : "helper") " · " c
    else if (cls == "hog") s = label " · CPU hog"
    else if (cls == "child") s = c
    else s = c
    return s
}
function where_text(   k, p) {
    k = wh[1]; p = wh[2]
    if (k == "tmux") return "tmux pane " p
    if (k == "herdr") return "Herdr" (nonempty(p) ? " in " p : "")
    if (k == "app") return p
    if (k == "ssh") return "an ssh session"
    return ""
}
function verdict_text(   f) {
    if (need == "") return ""
    split(need, f, "\t"); return f[11] " (" f[6] " confidence)"
}
function text(   i, s, f, ind, c, wcmd) {
    printf "%s%s%s  %spid %s · %s%s\n", b, cut(title(), w - 20), e, dim, t, P[5], e
    s = ""
    if (cls == "agent" && nonempty(rstat)) s = rstat
    if (nonempty(v("status"))) s = s (s == "" ? "" : " · ") v("status")
    if (cls != "agent" && cls != "process" && cls != "hog" && nonempty(root)) s = s (s == "" ? "" : " · ") "in " rkind " " root
    if (cls == "child" && nonempty(unit) && unit != root) s = s " · under " (ucls == "mcp" ? "MCP server " label : ucls) " " unit
    if (s != "") printf "%s%s%s\n", dim, s, e
    print ""
    if (nonempty(v("session"))) line("session", (nonempty(v("name")) ? v("name") " · " : "") v("session"))
    s = v("model"); if (nonempty(v("version"))) s = s (s == "" ? "" : " · ") dash(rkind) " " v("version")
    line("model", s)
    for (i = 1; i <= ni; i++) line(ik[i], iv[i])
    if (cls == "mcp" || nonempty(v("mcp_cli"))) {
        s = nonempty(v("mcp_cli")) ? "configured in " v("mcp_cli") " (" v("mcp_scope") ", " tilde(v("mcp_source")) ")" : "not in any config agents read (named by its package)"
        if (nonempty(v("mcp_needle"))) s = s " · starts with " tilde(v("mcp_needle"))
        line("mcp", s)
    }
    s = dash(proj); if (nonempty(v("branch"))) s = s " · branch " v("branch")
    if (nonempty(proj)) line("project", s)
    line("cwd", tilde(cwd))
    line("where", where_text())
    line("command", P[11])
    s = P[10]; gsub(/_/, " ", s)
    line("running", age(P[9]) " (since " s ")")
    s = sprintf("%.1f%% now · %s CPU time", P[6], dur(P[8]))
    if (P[9] > 0) s = s sprintf(" · %.1f%% average", 100 * P[8] / P[9])
    if (nonempty(v("threads"))) s = s " · " v("threads") " thread" (v("threads") == 1 ? "" : "s")
    line("cpu", s)
    s = mem(P[7]); if (nk) s = s " · " mem(P[7] + tr) " with " nk " child process" (nk > 1 ? "es" : "")
    line("memory", s)
    if (nonempty(ports)) line("ports", ports)
    if (nonempty(v("files"))) line("files", v("files") " open")
    if (nonempty(v("tool"))) line("doing", v("tool") (nonempty(v("aim")) ? ": " v("aim") : "") (nonempty(v("at")) ? ago(v("at")) : ""))
    if (nonempty(v("said"))) line("said", "\"" v("said") "\"")
    s = verdict_text()
    if (s != "") {
        split(need, f, "\t")
        c = (f[5] == "stop" ? yel : f[5] == "check" ? yel : grn)
        printf "%s%-9s%s %s%s%s\n", dim, "verdict", e, c, cut(s, w - 10), e
        for (i = 1; i <= nev; i++) printf "%s          %s%s\n", dim, cut(ev[i], w - 10), e
    }
    if (nk) {
        printf "\n%schildren (%d)%s\n", b, nk, e
        printf "%s  %-8s %6s %6s  %s%s\n", dim, "PID", "CPU%", "MEM", "COMMAND", e
        for (i = 1; i <= nk; i++) {
            split(kid[i], f, "\t")
            ind = ""; for (c = 1; c < f[4] && c < 8; c++) ind = ind "  "
            wcmd = w - 28 - length(ind)
            printf "  %-8s %6.1f %6s  %s%s\n", f[2], f[6], mem(f[7]), ind, cut(f[11], wcmd)
        }
    }
}
function json(   i, f, s, o) {
    o = "{\"schema_version\":1,\"pid\":" t ",\"start\":" js(P[10]) ",\"class\":" js(cls) ",\"kind\":" opt(kind) ",\"name\":" opt(label)
    o = o ",\"title\":" js(title()) ",\"command\":" js(P[11]) ",\"user\":" js(P[5]) ",\"cwd\":" opt(cwd) ",\"project\":" opt(proj) ",\"branch\":" opt(v("branch"))
    o = o ",\"session\":" (nonempty(root) ? "{\"pid\":" root ",\"kind\":" opt(rkind) ",\"status\":" opt(rstat) ",\"id\":" opt(v("session")) ",\"name\":" opt(v("name")) ",\"state\":" opt(v("status")) ",\"version\":" opt(v("version")) ",\"model\":" opt(v("model")) ",\"transcript\":" opt(v("transcript")) "}" : "null")
    s = ""; for (i = 1; i <= ni; i++) s = s (i > 1 ? "," : "") js(ik[i]) ":" js(iv[i])
    o = o ",\"info\":{" s "}"
    s = "null"
    if (need != "") {
        split(need, f, "\t")
        s = "{\"action\":" js(f[5]) ",\"confidence\":" js(f[6]) ",\"code\":" js(f[7]) ",\"text\":" js(f[11]) ",\"evidence\":["
        for (i = 1; i <= nev; i++) s = s (i > 1 ? "," : "") js(ev[i])
        s = s "]}"
    }
    o = o ",\"verdict\":" s
    o = o ",\"runtime_s\":" (P[9] + 0) ",\"cpu\":" (P[6] + 0) ",\"cputime_s\":" (P[8] + 0) ",\"rss_kib\":" (P[7] + 0) ",\"tree_rss_kib\":" (P[7] + tr)
    o = o ",\"threads\":" num(v("threads")) ",\"open_files\":" num(v("files"))
    o = o ",\"ports\":[" (nonempty(ports) ? ports : "") "]"
    o = o ",\"where\":" (nonempty(wh[1]) ? "{\"kind\":" js(wh[1]) ",\"place\":" opt(wh[2]) "}" : "null")
    o = o ",\"activity\":" (nonempty(v("tool")) || nonempty(v("said")) ? "{\"tool\":" opt(v("tool")) ",\"target\":" opt(v("aim")) ",\"said\":" opt(v("said")) ",\"at\":" num(v("at")) "}" : "null")
    o = o ",\"mcp\":" (cls == "mcp" ? "{\"name\":" opt(label) ",\"cli\":" opt(v("mcp_cli")) ",\"scope\":" opt(v("mcp_scope")) ",\"source\":" opt(v("mcp_source")) ",\"transport\":" opt(v("mcp_type")) ",\"starts_with\":" opt(v("mcp_needle")) "}" : "null")
    printf "%s", o
    printf ",\"children\":["
    for (i = 1; i <= nk; i++) {
        split(kid[i], f, "\t")
        printf "%s{\"pid\":%d,\"ppid\":%d,\"depth\":%d,\"cpu\":%s,\"rss_kib\":%d,\"command\":%s}", (i > 1 ? "," : ""), f[2], f[3], f[4], f[6] + 0, f[7], js(f[11])
    }
    printf "]}\n"
}
