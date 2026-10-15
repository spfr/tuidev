# lib/agents/awk/mcp_toml_launch.awk — Codex's config.toml with servers put
# behind mcp-lazy (-v mode=lazy) or taken from behind it (mode=eager): the
# whole file on stdout, unchanged but for the command and args of each
# [mcp_servers.NAME] table named in ENVIRON AGENTS_LAZY_NAMES ("\n"-joined:
# BWK awk takes no newline in a -v; "*" for all), and
# on stderr one line per server named:
#   done NAME | same NAME | skip NAME REASON   (tab-separated)
# Reads the file in ENVIRON AGENTS_LAZY_FILE twice: the first pass collects each server's
# env variable names (its env table, inline or [mcp_servers.NAME.env]).
# lazy: command = LZ (-v lz), args = ["--name", NAME, ("--env", NAMES,) "--",
# COMMAND, ARGS...] (mcp-lazy keys its cache by those variables' values);
# eager: back to what follows its "--". A table's command and args are
# rewritten only in the simple forms awk/mcp_toml.awk reads (one-line
# command, an args array over one or more lines) and without escapes, so
# nothing is lost; anything else is a skip, for a hand edit. The comments
# on a rewritten command or args go; every other line stays as it was.

function q(s) { gsub(/\\/, "\\\\", s); gsub(/"/, "\\\"", s); return "\"" s "\"" }
# strs(s, arr): the quoted strings on a line, as mcp_toml.awk reads them.
function strs(s, arr,   n, i, c, qc, v, L) {
    n = 0; L = length(s); i = 1
    while (i <= L) {
        c = substr(s, i, 1)
        if (c == "#") break
        if (c == "\"" || c == "'") {
            qc = c; v = ""; i++
            while (i <= L) { c = substr(s, i, 1); if (c == qc) break; v = v c; i++ }
            arr[++n] = v
        }
        i++
    }
    return n
}
# closes(s): whether s has a "]" outside its strings and before its
# comment: where an array over several lines ends.
function closes(s,   i, c, q, L) {
    q = ""; L = length(s)
    for (i = 1; i <= L; i++) {
        c = substr(s, i, 1)
        if (q != "") { if (q == "\"" && c == "\\") i++; else if (c == q) q = ""; continue }
        if (c == "#") return 0
        if (c == "\"" || c == "'") q = c
        else if (c == "]") return 1
    }
    return 0
}
function base(p) { sub(/.*\//, "", p); return p }
function wanted(nm) { return names == "*" || index("\n" names "\n", "\n" nm "\n") > 0 }
function report(what, nm, why) { printf "%s\t%s%s\n", what, nm, (why == "" ? "" : "\t" why) > "/dev/stderr" }

# The table held in body[1..nb] (cur's), rewritten, then printed.
function flush(   i, ci, ai, ae, k, n, a, t, cmd, out, j, d) {
    if (cur == "") return
    ci = ai = ae = 0
    for (i = 1; i <= nb; i++) {
        if (!ci && body[i] ~ /^[ \t]*command[ \t]*=/) ci = i
        else if (!ai && body[i] ~ /^[ \t]*args[ \t]*=/) {
            ai = i; ae = i
            while (!closes(ae == ai ? substr(body[ae], index(body[ae], "=") + 1) : body[ae]) && ae < nb) ae++
        }
    }
    if (!ci) { report("skip", cur, "no one-line command"); emit(); return }
    if (body[ci] ~ /\\/ || (ai && joined(ai, ae) ~ /\\/)) { report("skip", cur, "escapes in its command or args"); emit(); return }
    if (strs(body[ci], a) != 1) { report("skip", cur, "no one-line command"); emit(); return }
    cmd = a[1]; n = 0
    # Line by line: a comment ends only its own line.
    if (ai) for (i = ai; i <= ae; i++) { k = strs(i == ai ? substr(body[i], index(body[i], "=") + 1) : body[i], t); for (j = 1; j <= k; j++) a[++n] = t[j] }
    if (mode == "lazy") {
        if (base(cmd) == "mcp-lazy") { report("same", cur, ""); emit(); return }
        # A quote would come back escaped, which eager leaves alone.
        for (j = 1; j <= n; j++) if (index(a[j], "\"")) { report("skip", cur, "a quote in its args"); emit(); return }
        if (index(cmd, "\"")) { report("skip", cur, "a quote in its command"); emit(); return }
        out = q("--name") ", " q(cur) (envk[cur] == "" ? "" : ", " q("--env") ", " q(envk[cur])) ", " q("--") ", " q(cmd)
        for (j = 1; j <= n; j++) out = out ", " q(a[j])
        cmd = lz
    } else {
        if (base(cmd) != "mcp-lazy") { report("same", cur, ""); emit(); return }
        for (d = 1; d <= n && a[d] != "--"; d++) ;
        if (d >= n) { report("skip", cur, "no command after mcp-lazy's --"); emit(); return }
        cmd = a[d + 1]; out = ""
        for (j = d + 2; j <= n; j++) out = out (out == "" ? "" : ", ") q(a[j])
    }
    k = body[ci]; sub(/command[ \t]*=.*/, "", k)
    for (i = 1; i <= nb; i++) {
        if (ai && i >= ai && i <= ae) continue
        if (i == ci) { print k "command = " q(cmd); print k "args = [" out "]"; continue }
        print body[i]
    }
    report("done", cur, "")
    nb = 0; cur = ""
}
function joined(s, e,   i, t) { t = ""; for (i = s; i <= e; i++) t = t (i > s ? " " : "") body[i]; return t }
function emit(   i) { for (i = 1; i <= nb; i++) print body[i]; nb = 0; cur = "" }

# addenv(nm, k): k is one of server nm's env variables.
function addenv(nm, k) { if (k != "" && index("," envk[nm] ",", "," k ",") == 0) envk[nm] = envk[nm] (envk[nm] == "" ? "" : ",") k }
# tname(h): the server a [mcp_servers.…] header (without its "[") names, and
# in trest what follows that name; "" for another table.
function tname(h,   k, nm) {
    sub(/^[ \t]*\[+[ \t]*/, "", h)
    if (substr(h, 1, 12) != "mcp_servers.") return ""
    h = substr(h, 13)
    if (substr(h, 1, 1) == "\"") { k = index(substr(h, 2), "\""); nm = substr(h, 2, k - 1); trest = substr(h, k + 2) }
    else { nm = h; sub(/[].].*$/, "", nm); trest = substr(h, length(nm) + 1) }
    sub(/^[ \t]+/, "", trest)
    return nm
}
# inline_env(nm, v): the keys of an inline table v (what follows its "{"),
# bare or quoted, as server nm's env variables; values are skipped whole.
function inline_env(nm, v,   k, c, i) {
    while (1) {
        sub(/^[ \t,]+/, "", v)
        c = substr(v, 1, 1)
        if (c == "" || c == "}" || c == "#") return
        if (c == "\"" || c == "'") { i = index(substr(v, 2), c); if (!i) return; k = substr(v, 2, i - 1); v = substr(v, i + 2) }
        else if (match(v, /^[A-Za-z0-9_-]+/)) { k = substr(v, 1, RLENGTH); v = substr(v, RLENGTH + 1) }
        else return
        sub(/^[ \t]*=[ \t]*/, "", v)
        addenv(nm, k)
        c = substr(v, 1, 1)
        if (c == "\"") { if (!match(v, /^"([^"\\]|\\.)*"/)) return; v = substr(v, RLENGTH + 1) }
        else if (c == "'") { i = index(substr(v, 2), "'"); if (!i) return; v = substr(v, i + 2) }
        else { i = match(v, /[,}]/); if (!i) return; v = substr(v, i) }
    }
}
BEGIN {
    names = ENVIRON["AGENTS_LAZY_NAMES"]
    ARGV[ARGC++] = ENVIRON["AGENTS_LAZY_FILE"]; ARGV[ARGC++] = ENVIRON["AGENTS_LAZY_FILE"]
}
# Pass 1: the env variable names.
FNR == NR {
    if ($0 ~ /^[ \t]*\[/) {
        e1 = ""; t1 = tname($0)
        if (t1 != "" && trest ~ /^\.env[ \t]*\]/) { e1 = t1; t1 = "" }
        else if (substr(trest, 1, 1) != "]") t1 = ""
        next
    }
    if (e1 != "" && $0 ~ /^[ \t]*("[^"]*"|'[^']*'|[A-Za-z0-9_-]+)[ \t]*=/) { v = $0; sub(/^[ \t]*/, "", v); inline_env(e1, v) }
    if (t1 != "" && $0 ~ /^[ \t]*env[ \t]*=[ \t]*\{/) { v = $0; sub(/^[^{]*\{/, "", v); inline_env(t1, v) }
    next
}
/^[ \t]*\[/ {
    flush()
    h = $0; sub(/^[ \t]*\[+[ \t]*/, "", h)
    if (substr(h, 1, 12) == "mcp_servers.") {
        h = substr(h, 13)
        if (substr(h, 1, 1) == "\"") { k = index(substr(h, 2), "\""); nm = substr(h, 2, k - 1); rest = substr(h, k + 2) }
        else { nm = h; sub(/[].].*$/, "", nm); rest = substr(h, length(nm) + 1) }
        sub(/^[ \t]+/, "", rest)
        if (substr(rest, 1, 1) == "]" && wanted(nm)) { print; cur = nm; nb = 0; seen[nm] = 1; next }
    }
    print; next
}
cur != "" { body[++nb] = $0; next }
{ print }
END {
    flush()
    if (names != "*") {
        k = split(names, w, "\n")
        for (i = 1; i <= k; i++) if (w[i] != "" && !(w[i] in seen)) report("skip", w[i], "no [mcp_servers." w[i] "] table")
    }
}
