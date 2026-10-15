# lib/agents/awk/lib_where.awk — where a process lives: the tmux pane, Herdr,
# ssh session or terminal app it runs under, found by walking up its
# ancestors in the program's tables (pp, av). where_of(p).
# Reads ENVIRON AGENTS_PANES: "pane_pid<TAB>session:window.pane" lines (one
# tmux list-panes, where.sh). Needs lib_proc.awk (base).

function paneinit(   n, t, i, f) {
    if (pane_ok++) return
    n = split(ENVIRON["AGENTS_PANES"], t, "\n")
    for (i = 1; i <= n; i++) if (split(t[i], f, "\t") >= 2 && f[1] ~ /^[0-9]+$/) pane[f[1] + 0] = f[2]
}
# appname(a): the app a command line belongs to: the outermost .app bundle
# on its path (Ghostty, iTerm, Terminal, Visual Studio Code, Claude), or a
# Linux terminal emulator's own name; "" for neither.
function appname(a,   s, b) {
    if (match(a, /\/[^\/]+\.app\//)) { s = substr(a, RSTART + 1, RLENGTH - 6); return s }
    b = base(a)
    if (b ~ /^(gnome-terminal-server|konsole|xterm|alacritty|kitty|wezterm-gui|foot|tilix|terminator|xfce4-terminal|lxterminal|st|urxvt)$/) return b
    return ""
}
# where_of(p): "tmux<TAB>session:window.pane", "herdr<TAB>APP", "ssh<TAB>-",
# "app<TAB>APP", or "-<TAB>-": the first of these found from p up. Herdr
# goes on up to the app it runs in ("-" when none).
function where_of(p,   q, d, h, a) {
    paneinit(); q = p + 0; d = 0; h = 0
    while (q > 1 && (q in pp) && d++ < 64) {
        if (!h && (q in pane)) return "tmux\t" pane[q]
        if (!h && base(av[q]) == "herdr") h = 1
        else if (!h && base(av[q]) ~ /^sshd(-session)?:?$/) return "ssh\t-"
        else if ((a = appname(av[q])) != "") return (h ? "herdr" : "app") "\t" a
        q = pp[q]
    }
    return h ? "herdr\t-" : "-\t-"
}
