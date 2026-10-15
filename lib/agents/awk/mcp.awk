# lib/agents/awk/mcp.awk — the MCP inventory's rows, from raw server records
# (mcp.sh's jq and awk/mcp_toml.awk), tab-separated:
#   cli scope name source project root type command args(\037-joined)
# root: what ${CLAUDE_PLUGIN_ROOT} stands for in a plugin's command ("-").
# For each, the needle: the one word of its command line that names it in
# ps (needle()). The args are read for that alone and never printed: the rest
# of a command line can hold tokens. Prints, longest needle first:
#   srv CLI SCOPE NAME SOURCE PROJECT TYPE NEEDLE   ("-" when it has none)

function fname(p) { sub(/.*\//, "", p); return p }
# pkg: a package without its version (@scope/name@1.2 → @scope/name,
# name@latest → name, a Python spec's ==1.0 or [extra] too).
function pkg(s) {
    if (substr(s, 1, 1) == "@") sub(/@[^@\/]*$/, "", s); else sub(/@.*$/, "", s)
    sub(/[=<>~!\[].*$/, "", s)
    return s
}
# safe: a word fit to keep: no URL, no assignment, no control character, not
# a flag, at most 200 characters.
function safe(s) { return s != "" && length(s) <= 200 && s !~ /:\/\/|=|[[:cntrl:]]/ && substr(s, 1, 1) != "-" }
# generic: a word that names nothing in particular (an interpreter, a runner,
# a script's usual name).
function generic(s) {
    return length(s) < 3 || s ~ /^(node|nodejs|python[0-9.]*|ruby|php|java|npx|npm|pnpm|pnpx|yarn|bun|bunx|deno|uv|uvx|pipx|sh|bash|zsh|docker|podman|mcp|server|run|exec|dlx|index\.[cm]?[jt]s|main\.py|server\.[cm]?[jt]s|server\.py|cli\.[cm]?js)$/
}
# first(i): the first word from a[i] on that is not a flag, skipping the
# value of a flag that takes one; "" when none. pkgflag: those whose value
# is the package itself (npx -p, uvx --from).
function first(i,   w) {
    for (; i <= n; i++) {
        w = a[i]
        if (w ~ /^(-p|--package|--from)$/) { if (i < n && safe(a[i + 1])) return a[i + 1]; i++; continue }
        if (w ~ /^(--registry|--cache|--python|-w|--with|--index-url|--directory|-e|--env|-v|--volume|--name|--network|--entrypoint|-c|--config)$/) { i++; continue }
        if (substr(w, 1, 1) == "-") continue
        return w
    }
    return ""
}
function needle(cmd, args, root,   b, i, s, w) {
    b = fname(cmd); n = split(args, a, "\037")
    if (root != "-") for (i = 1; i <= n; i++) gsub(/\$\{CLAUDE_PLUGIN_ROOT\}/, root, a[i])
    s = 1                                # where its own words start
    if (b ~ /^(npm|pnpm|yarn|bun|pipx)$/ && a[1] ~ /^(exec|dlx|x|run)$/) { b = "npx"; s = 2 }
    else if (b == "uv" && a[1] == "tool" && a[2] == "run") { b = "uvx"; s = 3 }
    else if ((b == "uv" || b == "deno") && a[1] == "run") { b = "node"; s = 2 }
    if (b ~ /^(npx|bunx|pnpx|uvx)$/) { w = pkg(first(s)); return safe(w) ? w : "" }
    if (b ~ /^(node|nodejs|python[0-9.]*|ruby|php|bun|deno|uv|sh|bash)$/) {
        for (i = s; i < n; i++) if (a[i] == "-m") return safe(a[i + 1]) ? a[i + 1] : ""
        w = first(s)
        sub(/^.*\}/, "", w); sub(/^~/, "", w)    # ${CLAUDE_PROJECT_DIR:-.}/x, ~/x: the part ps shows as written
        return safe(w) ? w : ""
    }
    if (b ~ /^(docker|podman)$/) {
        for (i = 2; i <= n; i++)
            if (a[i] ~ /^[a-z0-9]+([._-][a-z0-9]+)*(\/[a-z0-9]+([._-][a-z0-9]+)*)+(:[A-Za-z0-9._-]+)?$/) return a[i]
        return ""
    }
    return safe(b) ? b : ""
}
BEGIN { FS = "\t"; m = 0 }
NF >= 8 {
    nd = needle($8, (NF >= 9 ? $9 : ""), $6)
    if (generic(fname(nd)) && nd !~ /\//) nd = ""
    nm = $3; gsub(/[[:cntrl:]]/, "", nm)
    if (nm == "") next
    row[++m] = "srv\t" $1 "\t" $2 "\t" nm "\t" $4 "\t" $5 "\t" $7 "\t" (nd == "" ? "-" : nd)
    len[m] = length(nd)
}
END {
    for (i = 1; i <= m; i++) {          # longest needle first: the most specific match wins
        b = i
        for (j = i + 1; j <= m; j++) if (len[j] > len[b]) b = j
        t = row[i]; row[i] = row[b]; row[b] = t; t = len[i]; len[i] = len[b]; len[b] = t
        print row[i]
    }
}
