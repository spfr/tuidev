# lib/agents/awk/lib_activity.awk — what a session runs: tool shells and the
# command they run, MCP servers, polling loops and the file they watch.
#   tool_shell, is_mcp, mcp_known, mcp_name (mcp_word, mcp_tidy), mcp_via,
#   waits, watched, tool_cmd, cmd_name. ENVIRON AGENTS_MCP: the configured
#   servers (mcp.sh).
# Needs lib_proc.awk (base, pname, hostinit and its name lists).

# A tool shell: a shell running one command line, "/bin/zsh -c …" (the Claude
# Code Bash tool) or "bash -lc …" (Codex).
function tool_shell(a,   b) {
    hostinit()
    b = a; sub(/ .*/, "", b); sub(/^-/, "", b); sub(/.*\//, "", b)
    if (b == "sandbox-exec") return a ~ / (\/[^ ]*\/)?(bash|zsh|sh) +-[A-Za-z]*c /
    return (b in shells) && a ~ /^[^ ]+ +-[A-Za-z]*c( |$)/
}
# is_mcp: an MCP server by its command line (npm exec, npx, the npx cache,
# "mcp" in it), or one you configured (mcp_known).
function is_mcp(a) { return a ~ /(^|\/)npm exec( |$)|(^|\/)npx( |$)|\/_npx\/|mcp/ || mcp_known(a, "") != "" }
# The configured servers (mcp.sh's inventory), from ENVIRON AGENTS_MCP:
# "needle<TAB>name<TAB>cli" lines, longest needle first.
function mcpinit(   n, t, i, f) {
    if (mcp_ok++) return
    n = split(ENVIRON["AGENTS_MCP"], t, "\n"); mcpn = 0
    for (i = 1; i <= n; i++) if (split(t[i], f, "\t") >= 3 && f[1] != "") { mcpn++; mcpnd[mcpn] = f[1]; mcpnm[mcpn] = f[2]; mcpcli[mcpn] = f[3] }
}
# mcp_known(a, cli): the configured name of the server whose needle a's
# command line holds (mcp_at), "" for none; with cli (claude, codex), that
# CLI's server first when two configs start the same program.
function mcp_known(a, cli,   i, hit) {
    mcpinit(); hit = ""
    for (i = 1; i <= mcpn; i++) {
        if (!index(a, mcpnd[i]) || !mcp_at(a, mcpnd[i])) continue
        if (cli == "" || mcpcli[i] == cli) return mcpnm[i]
        if (hit == "") hit = mcpnm[i]
    }
    return hit
}
# mcp_at(a, nd): whether needle nd is in a as a word, never inside one: it
# starts a word, or follows a "/" (an absolute path's tail, as a
# ${CLAUDE_PROJECT_DIR}/x needle is; a name or @scope/name: a package under
# node_modules/, a program run by its path), and it ends one, or a version's
# "@" follows it (or, a package, a "/" into it).
function mcp_at(a, nd,   p, o, c, e, pk, ab) {
    ab = substr(nd, 1, 1) == "/"
    pk = !ab && (nd !~ /\// || nd ~ /^@[^\/]+\/[^\/]+$/)
    o = 0
    while ((p = index(substr(a, o + 1), nd)) > 0) {
        p += o; c = p > 1 ? substr(a, p - 1, 1) : " "; e = substr(a, p + length(nd), 1)
        if ((c == " " || ab || (c == "/" && pk)) && (e == "" || e == " " || e == "@" || (e == "/" && pk))) return 1
        o = p
    }
    return 0
}
# mcp_word: the package or program an MCP server's command line names, without
# version or extension: "npm exec X"'s or "npx X"'s package, the package a
# path under node_modules/ belongs to, else the first word with mcp in it,
# else the program's name.
function mcp_word(a,   n, w, i, s) {
    if (match(a, /(npm exec|npx)( +-[^ ]+)* +[^ -][^ ]*/)) {
        s = substr(a, RSTART, RLENGTH); sub(/.* /, "", s)
    } else {
        n = split(a, w, " "); s = ""
        for (i = 1; i <= n; i++) if (w[i] ~ /mcp/) { s = w[i]; break }
        if (s == "") s = pname(a)
    }
    if ((i = index(s, "node_modules/")) > 0) {
        s = substr(s, i + 13)
        if (substr(s, 1, 5) == ".bin/") s = substr(s, 6)
        if (substr(s, 1, 1) == "@") { if (match(s, /^@[^\/]+\/[^\/]+/)) s = substr(s, 1, RLENGTH) }
        else sub(/\/.*/, "", s)
    }
    if (substr(s, 1, 1) == "@") sub(/@[^@\/]*$/, "", s); else sub(/@.*$/, "", s)
    sub(/\.(c|m)?js$|\.py$|\.ts$/, "", s)
    return s
}
# mcp_tidy: the short name that goes by: the scope of @scope/mcp (or
# /mcp-server, /server), else its last path part without an mcp-server-,
# server- or mcp- prefix and a -mcp-server, -mcp or -server suffix
# (@playwright/mcp → playwright, chrome-devtools-mcp → chrome-devtools,
# @modelcontextprotocol/server-filesystem → filesystem).
function mcp_tidy(s,   t) {
    if (s ~ /^@[^\/]+\/(mcp|mcp-server|server)$/) { s = substr(s, 2); sub(/\/.*/, "", s); return s }
    sub(/.*\//, "", s); t = s
    sub(/^(mcp-server-|server-|mcp-)/, "", t); sub(/(-mcp-server|-mcp|-server)$/, "", t)
    return (t == "" || t == "mcp" || t == "server") ? s : t
}
# mcp_name(a, cli): the name an MCP server's process goes by: its configured
# name (mcp_known), else mcp_tidy of mcp_word; printable, never empty.
function mcp_name(a, cli,   s) {
    s = mcp_known(a, cli)
    if (s == "") s = mcp_tidy(mcp_word(a))
    gsub(/[[:cntrl:]]/, "", s)
    return s == "" ? pname(a) : s
}
# mcp_via(a): the launcher an MCP server's command line starts it through, a
# process of its own above the server's: lazy (mcp-lazy, which starts it on
# its first tool call), npx (npm exec, as ps shows it), pnpm (dlx), bunx,
# uvx (uv tool), docker or podman (run); "-" for none. Only that word: never
# the rest of the command line.
function mcp_via(a) {
    if (a ~ /(^|\/)mcp-lazy( |$)/) return "lazy"
    if (a ~ /(^|\/)npm exec( |$)|(^|\/)npx( |$)/) return "npx"
    if (a ~ /(^|\/)pnpm dlx( |$)|(^|\/)pnpx( |$)/) return "pnpm"
    if (a ~ /(^|\/)bunx( |$)|(^|\/)bun x( |$)/) return "bunx"
    if (a ~ /(^|\/)uvx( |$)|(^|\/)uv tool (uvx|run)( |$)/) return "uvx"
    if (a ~ /(^|\/)docker run( |$)/) return "docker"
    if (a ~ /(^|\/)podman run( |$)/) return "podman"
    return "-"
}
# A polling loop a session waits on ("until …; do sleep 5; done"), given the
# tidied command: never dup or long, it is how the agent waits for something.
function waits(c) { return c ~ /^(until|while) .*; *do .*sleep [0-9.]+.*; *done/ }
# watched: the file a polling loop waits on, "" when there is none: the first
# absolute path given to tail, head, grep, cat, wc, jq, test, [ or [[ in its
# condition, directly or through a VAR=/abs/path assignment before the loop
# ("F=/t/x.output; until tail -1 $F | grep -q ok; do …"). Arguments of any
# other command (docker exec db /usr/bin/pg_isready, curl --unix-socket
# /var/run/x.sock) never count, nor do /dev paths, globs and redirection
# targets. A quoted word split at its spaces is joined back ("/tmp/my dir/x").
# Sets watch_reads: 1 when the condition reads the file (tail, grep, jq…), 0
# when it only tests that it exists (test, [, [[: while [ -f lock ]).
function watched(s,   c, pre, j, n, w, i, t, cmd, cur, k, q, d, x) {
    q = sprintf("%c", 39); d = "\""; watch_reads = 0
    gsub(/\\012/, " ; ", s)
    if (!match(s, /(^|[;&(] *)(until|while) +/)) return ""
    pre = substr(s, 1, RSTART - 1); c = substr(s, RSTART + RLENGTH)
    j = match(c, / *; *do( |$)/); if (!j) return ""
    c = substr(c, 1, j - 1)
    split("", wv); gsub(/[;&|()]/, " ", pre); n = split(pre, w, " ")
    for (i = 1; i <= n; i++) {
        if (w[i] !~ /^[A-Za-z_][A-Za-z0-9_]*=./) continue
        k = index(w[i], "="); t = substr(w[i], k + 1); x = substr(t, 1, 1)
        if (x == q || x == d) {
            if (length(t) < 2 || substr(t, length(t)) != x) continue    # a quoted value with spaces
            t = substr(t, 2, length(t) - 2)
        }
        if (t ~ /^\//) wv[substr(w[i], 1, k - 1)] = t
    }
    gsub(/\|\||&&|[|;()]/, " & ", c); n = split(c, w, " "); cmd = 1; cur = ""
    for (i = 1; i <= n; i++) {
        t = w[i]; x = substr(t, 1, 1)
        if ((x == q || x == d) && (length(t) < 2 || substr(t, length(t)) != x))
            while (i < n && (length(t) < 2 || substr(t, length(t)) != x)) t = t " " w[++i]
        if (t ~ /^(\|\||&&|[|;()])$/) { cmd = 1; cur = ""; continue }
        if (t == "!") continue
        if (cmd) { cmd = 0; cur = t; sub(/.*\//, "", cur); continue }
        if (cur !~ /^(tail|head|grep|egrep|fgrep|cat|wc|jq|test|\[|\[\[)$/) continue
        if (t ~ /^[0-9]*[<>]/ || (i > 1 && w[i - 1] ~ /[<>]$/)) continue
        x = substr(t, 1, 1)
        if ((x == q || x == d) && length(t) >= 2 && substr(t, length(t)) == x) t = substr(t, 2, length(t) - 2)
        if (t ~ /^\$\{?[A-Za-z_][A-Za-z0-9_]*\}?$/) { gsub(/[${}]/, "", t); t = (t in wv) ? wv[t] : "" }
        if (t ~ /^\// && t !~ /^\/dev\// && t !~ /[*?]|\[/) { watch_reads = (cur !~ /^(test|\[|\[\[)$/); return t }
    }
    return ""
}
# tool_cmd: the command a tool shell runs, tidied for display and comparison:
# the string a Claude Code shell evals (or the -c string), without cd
# prefixes, VAR=value assignments, 2>&1, </dev/null or a trailing | tail/head.
# Sets tool_cd (the absolute directory it changes to first), tool_watch and
# watch_reads (watched).
function tool_cmd(a,   q, i, j, s, k, t) {
    q = sprintf("%c", 39); tool_cd = ""; tool_watch = ""
    i = index(a, " eval " q)
    if (i > 0) {
        s = substr(a, i + 7)
        j = 0; t = s
        while ((k = index(t, q " < /dev/null")) > 0) { j += k; t = substr(t, k + 1) }
        if (j > 0) s = substr(s, 1, j - 1)
        t = q "\"" q "\"" q
        while ((k = index(s, t)) > 0) s = substr(s, 1, k - 1) q substr(s, k + 5)
    } else {
        s = a
        if (base(a) == "sandbox-exec") {
            if (match(a, / (\/[^ ]*\/)?(bash|zsh|sh) +-[A-Za-z]*c +/)) s = substr(a, RSTART + RLENGTH)
        } else sub(/^[^ ]+ +-[A-Za-z]*c +/, "", s)
        if (substr(s, 1, 1) == q || substr(s, 1, 1) == "\"") {
            s = substr(s, 2); k = substr(s, length(s))
            if (k == q || k == "\"") s = substr(s, 1, length(s) - 1)
        }
    }
    while (match(s, /^ *cd +[^ ;&]+ *(&&|;) */)) {
        t = substr(s, RSTART, RLENGTH); s = substr(s, RSTART + RLENGTH)
        sub(/^ *cd +/, "", t); sub(/ *(&&|;) *$/, "", t)
        if (t ~ /^\//) tool_cd = t
    }
    tool_watch = watched(s)
    while (match(s, /(^|[;&|] *)[A-Za-z_][A-Za-z0-9_]*=[^ ]* +/)) {
        t = substr(s, RSTART, RLENGTH); k = t; sub(/[A-Za-z_][A-Za-z0-9_]*=[^ ]* +$/, "", k)
        s = substr(s, 1, RSTART - 1) k substr(s, RSTART + RLENGTH)
    }
    gsub(/ *2>&1/, "", s); gsub(/ *< *\/dev\/null/, "", s)
    gsub(/\\012/, " \342\217\216 ", s)        # ps shows a newline as \012: one line, marked
    sub(/ *\| *(tail|head)( +-[0-9A-Za-z]+)* *$/, "", s)
    gsub(/[ \t]+/, " ", s); sub(/^ /, "", s); sub(/ $/, "", s)
    gsub(/\/ /, " ", s); sub(/\/$/, "", s)
    if (length(s) > 400) s = substr(s, 1, 397) "..."   # compared whole; shortened on display
    return s == "" ? pname(a) : s
}
# cmd_name: the name a tidied command goes by, never its arguments: "wait-loop"
# for a polling loop, else its first word without a directory ("go" for
# "go test ./...", "make" for "/usr/bin/make -j8"), in [A-Za-z0-9._+-] only,
# at most 32 characters; "command" when nothing is left.
function cmd_name(c,   w) {
    if (waits(c)) return "wait-loop"
    w = c; sub(/^[( ]+/, "", w); sub(/[ ;&|)].*$/, "", w); sub(/.*\//, "", w)
    gsub(/[^A-Za-z0-9._+-]/, "", w)
    return w == "" ? "command" : substr(w, 1, 32)
}
