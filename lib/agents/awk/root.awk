# lib/agents/awk/root.awk — agents_root_of, from a snapshot on stdin: for
# process -v t=PID the agent session it runs under, as one line
#   PID@START APP
# (the outermost claude or codex process from t up, as agents_where names a
# session's ROOT, and its start time; APP: the terminal app that shows it,
# "-" when that can't be told from the process table). A tmux or Herdr
# session's app is the app every tmux (or Herdr) client runs in, when they
# all run in one. Nothing when t is not running or runs under no agent.
# Needs lib_proc and lib_where.
NF >= 14 { p = $1 + 0; pp[p] = $2 + 0; av[p] = argv($0); st[p] = lstart(); ord[++n] = p }
END {
    t += 0
    if (!(t in pp)) exit
    q = t; d = 0; root = ""; mux = ""
    while (q > 1 && (q in pp) && d++ < 64) {
        if (agent_kind(av[q]) != "") root = q
        q = pp[q]
    }
    if (root == "") exit
    # Its place, without a tmux pane map: a tmux server above it is tmux.
    split(where_of(root), w, "\t")
    app = (w[1] == "app" || w[1] == "herdr") ? w[2] : "-"
    if (w[1] == "herdr") mux = "herdr"
    else if (w[1] == "-") {
        q = pp[root]; d = 0
        while (q > 1 && (q in pp) && d++ < 64) { if (base(av[q]) ~ /^tmux:?$/) { mux = "tmux"; break } q = pp[q] }
    }
    # The app the clients run in, when they all run in the same one.
    if (mux != "" && app == "-") {
        for (i = 1; i <= n; i++) {
            p = ord[i]
            b = base(av[p]); sub(/:$/, "", b)    # Linux names them "tmux: server", "tmux: client"
            if (b != mux) continue
            split(where_of(p), c, "\t")
            if ((c[1] != "app" && c[1] != "herdr") || c[2] == "-") continue
            if (found == "") found = c[2]
            else if (found != c[2]) found = "-"
        }
        if (found != "") app = found
    }
    print root "@" st[root] "\t" app
}
