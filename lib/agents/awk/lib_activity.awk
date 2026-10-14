# lib/agents/awk/lib_activity.awk — what a session runs: tool shells and the
# command they run, MCP servers, polling loops and the file they watch.
#   tool_shell, is_mcp, mcp_name, waits, watched, tool_cmd.
# Needs lib_proc.awk (base, pname, hostinit and its name lists).

# A tool shell: a shell running one command line, "/bin/zsh -c …" (the Claude
# Code Bash tool) or "bash -lc …" (Codex).
function tool_shell(a,   b) {
    hostinit()
    b = a; sub(/ .*/, "", b); sub(/^-/, "", b); sub(/.*\//, "", b)
    if (b == "sandbox-exec") return a ~ / (\/[^ ]*\/)?(bash|zsh|sh) +-[A-Za-z]*c /
    return (b in shells) && a ~ /^[^ ]+ +-[A-Za-z]*c( |$)/
}
function is_mcp(a) { return a ~ /(^|\/)npm exec( |$)|(^|\/)npx( |$)|\/_npx\/|mcp/ }
# mcp_name: "chrome-devtools-mcp" from "npm exec chrome-devtools-mcp@latest",
# "example-agent-mcp" from "node …/example-agent-mcp.cjs".
function mcp_name(a,   n, w, i, s) {
    if (match(a, /(npm exec|npx)( +-[^ ]+)* +[^ -][^ ]*/)) {
        s = substr(a, RSTART, RLENGTH); sub(/.* /, "", s)
    } else {
        n = split(a, w, " "); s = ""
        for (i = 1; i <= n; i++) if (w[i] ~ /mcp/) { s = w[i]; break }
        if (s == "") s = pname(a)
    }
    sub(/.*\//, "", s); sub(/@[^@\/]*$/, "", s); sub(/\.(c|m)?js$|\.py$|\.ts$/, "", s)
    return s == "" ? pname(a) : s
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
