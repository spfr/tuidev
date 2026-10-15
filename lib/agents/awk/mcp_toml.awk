# lib/agents/awk/mcp_toml.awk — the MCP servers in Codex's config.toml, as
# raw server records for awk/mcp.awk (mcp.sh documents them):
#   codex user NAME SRC - - stdio|http COMMAND ARGS(\037-joined) ENABLED
# One per [mcp_servers.NAME] table; of its keys only command, args, url and
# enabled (1, or 0 for `enabled = false`) are read, and its sub-tables (env,
# tools) are skipped. -v src=PATH names the file. Not a TOML parser: enough of TOML for these tables.

# strs(s, arr): the quoted strings on a line (TOML basic "…" with escapes,
# and literal '…'), in arr; their count. A # outside quotes ends the line.
function strs(s, arr,   n, i, c, q, v, L) {
    n = 0; L = length(s); i = 1
    while (i <= L) {
        c = substr(s, i, 1)
        if (c == "#") break
        if (c == "\"" || c == "'") {
            q = c; v = ""; i++
            while (i <= L) {
                c = substr(s, i, 1)
                if (q == "\"" && c == "\\" && i < L) { i++; v = v substr(s, i, 1); i++; continue }
                if (c == q) break
                v = v c; i++
            }
            gsub(/[[:cntrl:]]/, " ", v)
            arr[++n] = v
        }
        i++
    }
    return n
}
function flush() {
    if (cur != "" && (cmd != "" || url != ""))
        printf "codex\tuser\t%s\t%s\t-\t-\t%s\t%s\t%s\t%d\n", cur, src, (cmd == "" ? "http" : "stdio"), (cmd == "" ? "-" : cmd), args, on
    cur = ""; cmd = ""; url = ""; args = ""; on = 1
}
/^[ \t]*\[/ {
    h = $0; sub(/^[ \t]*\[+[ \t]*/, "", h)
    if (substr(h, 1, 12) != "mcp_servers.") { flush(); next }
    h = substr(h, 13)
    if (substr(h, 1, 1) == "\"") { k = index(substr(h, 2), "\""); name = substr(h, 2, k - 1); rest = substr(h, k + 2) }
    else { name = h; sub(/[].].*$/, "", name); rest = substr(h, length(name) + 1) }
    sub(/^[ \t]+/, "", rest)
    gsub(/[[:cntrl:]]/, "", name)
    if (substr(rest, 1, 1) == "]") { flush(); cur = name; insub = 0; on = 1 }
    else insub = 1                   # [mcp_servers.NAME.env], .tools.X
    next
}
cur != "" && !insub && /^[ \t]*enabled[ \t]*=[ \t]*false([ \t]|#|$)/ { on = 0; next }
cur != "" && !insub && /^[ \t]*(command|args|url)[ \t]*=/ {
    k = $0; sub(/^[ \t]*/, "", k); sub(/[ \t]*=.*$/, "", k)
    v = $0; sub(/^[^=]*=/, "", v)
    if (k == "args") {
        while (index(v, "]") == 0 && (getline more) > 0) v = v " " more     # an array over several lines
        n = strs(v, a); args = ""
        for (i = 1; i <= n; i++) { gsub(/\037/, " ", a[i]); args = args (i > 1 ? "\037" : "") a[i] }
    } else if (strs(v, a) > 0) {
        if (k == "command") cmd = a[1]; else url = a[1]
    }
}
BEGIN { on = 1 }
END { flush() }
