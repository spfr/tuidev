# lib/agents/awk/mcp.awk — the MCP inventory's rows, from raw server records
# (mcp.sh's jq and awk/mcp_toml.awk), tab-separated:
#   cli scope name source project root type command args(\037-joined) [enabled]
# root: what ${CLAUDE_PLUGIN_ROOT} stands for in a plugin's command ("-").
# For each, the needle: the one word of its command line that names it in
# ps (needle()). The args are read for that alone and never printed: the rest
# of a command line can hold tokens. Prints, longest needle first:
#   srv CLI SCOPE NAME SOURCE PROJECT TYPE NEEDLE ENABLED LAUNCH   ("-" when
#   it has no needle; ENABLED 1, or 0 for a Codex server set
#   `enabled = false`; LAUNCH lazy for a server behind mcp-lazy, whose
#   needle is then its own command's, after mcp-lazy's "--", else "-")

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
# a tool, a script's usual name).
function generic(s) {
    return length(s) < 3 || s ~ /^(node|nodejs|python[0-9.]*|ruby|php|perl|java|npx|npm|pnpm|pnpx|yarn|bun|bunx|deno|tsx|ts-node|uv|uvx|pip[0-9]*|pipx|poetry|sh|bash|zsh|env|sudo|nohup|ssh|socat|curl|wget|make|cargo|rustc|go|dotnet|swift|gradle|mvn|kubectl|gcloud|aws|docker|podman|mcp|server|run|exec|dlx|index\.[cm]?[jt]s|main\.py|server\.[cm]?[jt]s|server\.py|cli\.[cm]?js)$/
}
# weak(s): a needle too common to name one server, which a process would
# match by chance: a word of under 5 letters or a generic one; a path that,
# past a generic file name, has only build directories left (dist/index.js,
# ${CLAUDE_PROJECT_DIR}/build/server.js).
function weak(s,   d) {
    if (s !~ /\//) return generic(s) || (s !~ /[.@]/ && length(s) < 5)
    if (substr(s, 1, 1) == "@") return 0
    d = s; sub(/\/[^\/]*$/, "", d)
    if (!generic(fname(s))) return 0
    while (match(d, /(^|\/)(dist|build|out|lib|src|bin|app|server|\.|\.\.)$/)) d = substr(d, 1, RSTART - 1)
    return d !~ /[^\/~]/
}
# noval(w): a flag that takes no value (the launchers' and interpreters'
# common ones: npx -y, uvx -q, node --inspect, deno -A, python -u…): any
# other flag without "=" is taken to take the next word as its value.
function noval(w) {
    if (w == "--" || w ~ /^-[yqsvnuABEIOPSUbdx]+$/) return 1
    return w ~ /^--(yes|no|quiet|silent|verbose|offline|prefer-offline|prefer-online|ignore-existing|isolated|refresh|native-tls|preview|upgrade|watch|hot|smol|bun|inspect|inspect-brk|inspect-wait|no-[a-z0-9-]+|allow-[a-z0-9-]+|unstable[a-z0-9-]*|experimental-[a-z0-9-]+|enable-[a-z0-9-]+|trace-[a-z0-9-]+)$/
}
# shaped(w): a word that looks like what names a server: a path or a
# package (it holds "/", "." or "@"), or a plain name (a letter first, then
# letters, digits, "_" and "-", at most 4 digits); never one that starts
# like a credential (sk-, ghp_, xoxb-, AKIA, eyJ…).
function shaped(w,   t) {
    if (w ~ /^(sk[-_]|(ghp|gho|ghs|ghu|ghr|github_pat|glpat|xox[abprs])[-_]|AKIA|ASIA|AIza|ya29\.|eyJ)/) return 0
    if (w ~ /[\/.@]/) return 1
    t = w
    return w ~ /^[A-Za-z][A-Za-z0-9_-]*$/ && gsub(/[0-9]/, "", t) <= 4
}
# first(i, pf): the first word from a[i] on that is not a flag or a flag's
# value, when it is shaped (else "": the next one could be a secret too);
# a flag matching pf (npx -p, uvx --from) has the package as its value.
function first(i, pf,   w) {
    for (; i <= n; i++) {
        w = a[i]
        if (pf != "" && w ~ pf) { if (i < n && safe(a[i + 1]) && shaped(a[i + 1])) return a[i + 1]; i++; continue }
        if (substr(w, 1, 1) == "-") { if (!index(w, "=") && !noval(w)) i++; continue }
        return shaped(w) ? w : ""
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
    if (b ~ /^(npx|bunx|pnpx|uvx)$/) { w = pkg(first(s, b == "uvx" ? "^--from$" : "^(-p|--package)$")); return safe(w) ? w : "" }
    if (b ~ /^(node|nodejs|python[0-9.]*|ruby|php|bun|deno|uv|sh|bash)$/) {
        for (i = s; i < n; i++) if (a[i] == "-m") return safe(a[i + 1]) && shaped(a[i + 1]) ? a[i + 1] : ""
        w = first(s, "")
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
# lazy(cmd, args): whether cmd is mcp-lazy (lazy.sh); then sets lz_cmd and
# lz_args to the command after its "--", the server's own.
function lazy(cmd, args,   w, k, i) {
    if (fname(cmd) != "mcp-lazy") return 0
    k = split(args, w, "\037")
    for (i = 1; i < k; i++) if (w[i] == "--") break
    if (i >= k) return 0
    lz_cmd = w[i + 1]; lz_args = ""
    for (i += 2; i <= k; i++) lz_args = lz_args (lz_args == "" ? "" : "\037") w[i]
    return 1
}
NF >= 8 {
    if (($1, $2, $3, $4, $5) in seen) next      # one server, named twice (a plugin's .mcp.json and plugin.json)
    seen[$1, $2, $3, $4, $5] = 1
    lz = lazy($8, (NF >= 9 ? $9 : ""))
    nd = lz ? needle(lz_cmd, lz_args, $6) : needle($8, (NF >= 9 ? $9 : ""), $6)
    if (weak(nd)) nd = ""
    nm = $3; gsub(/[[:cntrl:]]/, "", nm)
    if (nm == "") next
    row[++m] = "srv\t" $1 "\t" $2 "\t" nm "\t" $4 "\t" $5 "\t" $7 "\t" (nd == "" ? "-" : nd) "\t" ($10 == "0" ? 0 : 1) "\t" (lz ? "lazy" : "-")
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
