# lib/agents/awk/mcp_view.awk — `agents mcp`: the configured servers, what
# runs of each now, and where each is configured. Reads mcp.sh's inventory
# rows (srv CLI SCOPE NAME SOURCE PROJECT TYPE NEEDLE ENABLED LAUNCH), then
# classify's job records (awk/lib_jobs.awk) for what runs. -v dir: only the
# servers a session started there loads; -v dim, -v off: the colors. Needs
# lib_fmt.awk.
#
# A copy is one session's server, or one a stale tree left behind: every
# session starts its own. Copies count on the row of their CLI and name (a
# stale one's session is gone, so it counts on the first row of its name),
# once, with their memory in use (RSS). A server behind mcp-lazy (LAUNCH
# lazy) says so; its copies not started yet are mcp-lazy alone. Then the
# hints: a Claude Code server at user scope running in more than one session
# (one copy per session, wherever it is used: agents mcp lazy starts it on
# first use instead), the copies of a lazy one not started, and stale
# copies.

function tilde(s,   i, h) {
    h = ENVIRON["HOME"]
    if (h == "" || h == "/") return s
    while ((i = index(s, h)) > 0) s = substr(s, 1, i - 1) "~" substr(s, i + length(h))
    return s
}
function copies(c, k) { return c " cop" (c == 1 ? "y" : "ies") ", " mem(k) }
BEGIN { FS = "\t"; n = 0 }
$1 == "srv" && NF >= 8 {
    if (($3 == "local" || $3 == "project") && dir != "" && $6 != dir) next
    n++; cli[n] = $2; scope[n] = $3; name[n] = $4; src[n] = $5; type[n] = $7; nd[n] = $8; lz[n] = ($10 == "lazy")
    next
}
# One copy per session (or stale tree) root and name; its memory, its named
# rows' (each holds its subtree's MCP processes).
$1 == "job" && $3 == "mcp" && $10 == "own" && NF >= 14 && $14 != "-" {
    c = ($12 == "claude" || $12 == "codex") ? $12 : "-"
    if (!(($2, $14) in seen)) { seen[$2, $14] = 1; cp[c, $14]++; if ($12 == "-") sc[c, $14]++; if ($16 == "lazy-idle") ic[c, $14]++ }
    rk[c, $14] += $7
    if ($12 == "-") sk[c, $14] += $7
}
END {
    if (!n) exit
    printf "%s%-22s %-6s %-8s %-6s %-15s %-34s %s%s\n", dim, "NAME", "CLI", "SCOPE", "TYPE", "RUNNING", "STARTS WITH", "SOURCE", off
    for (i = 1; i <= n; i++) {
        c = k = s = m = id = 0
        if (!((cli[i], name[i]) in shown)) {
            shown[cli[i], name[i]] = 1
            c = cp[cli[i], name[i]]; k = rk[cli[i], name[i]]; s = sc[cli[i], name[i]]; m = sk[cli[i], name[i]]; id = ic[cli[i], name[i]]
        }
        if (!(name[i] in named)) {
            named[name[i]] = 1
            c += cp["-", name[i]]; k += rk["-", name[i]]; s += sc["-", name[i]]; m += sk["-", name[i]]; id += ic["-", name[i]]
        }
        w = nd[i]
        if (w == "-" && type[i] == "http") w = "(a URL)"
        else if (lz[i]) w = w " (lazy)"
        printf "%-22s %-6s %-8s %-6s %-15s %-34s %s\n", name[i], cli[i], scope[i], type[i], (c ? copies(c, k) : "-"), tilde(w), tilde(src[i])
        if (c) any = 1
        if (c - s > 1 && cli[i] == "claude" && scope[i] == "user" && !lz[i])
            hint = hint sprintf("%s: %d copies · %s — user scope starts one per session; scope it to the projects that use it, or agents mcp lazy %s starts it on first use\n", name[i], c - s, mem(k - m), name[i])
        if (id) hint = hint sprintf("%s: %d of %d cop%s not started — mcp-lazy stands in until a tool call\n", name[i], id, c, (c == 1 ? "y" : "ies"))
        if (s == 1) hint = hint sprintf("%s: 1 stale copy · %s — its session ended; agents stale lists it\n", name[i], mem(m))
        if (s > 1) hint = hint sprintf("%s: %d stale copies · %s — their sessions ended; agents stale lists them\n", name[i], s, mem(m))
    }
    if (any) printf "%sRUNNING: copies now (each session starts its own) and their memory in use (RSS), not data sent%s\n", dim, off
    printf "%s", hint
}
