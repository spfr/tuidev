# lib/agents/awk/tokens.awk — _agents_tokens_scan: the token rows, from
# _agents_tokens_feed's headers and grep -b lines (tokens.sh documents the
# files). Needs lib_proc (projname) and lib_activity (waits).
# Writes, in the data directory d: tokens.state.new, only when the state
# changed; tokens.add.tokens, .compacts and .denials (rows to append);
# tokens.add.limits only when Codex logged a newer rate limit than
# limits.tsv holds. Prints tokens.today's line: today's sums (the old ones
# when tokens.today is today's, else those in tokens.tsv from mid, local
# midnight, on; plus this scan's). tyf: _agents_tx_agent_types lines. Rows
# older than cut are not written.
# JSON is read by its keys' spelling, never parsed whole: Claude Code's
# top-level keys follow the message, so a line's own type, timestamp and cwd
# are the first after '"type":"assistant","uuid"' (or the line's type);
# its message's model, id and usage come before.

function max(a, b) { return a > b ? a : b }
function dash(s) { return s == "" ? "-" : s }
# clean(s, n, ok): s with only the characters ok matches, at most n of them.
function clean(s, n, ok) { gsub(ok, "", s); return substr(s, 1, n) }
# at(s, k, from): where key k ("name":) is in s, from position from on; 0
# when it is not.
function at(s, k, from,   i) {
    if (from < 1) from = 1
    i = index(substr(s, from), "\"" k "\":")
    return i ? from + i - 1 : 0
}
# lastat(s, pat, before): the last position of pat in s before position before.
function lastat(s, pat, before,   i, p, t) {
    p = 0; t = substr(s, 1, before - 1)
    while ((i = index(substr(t, p + 1), pat)) > 0) p += i
    return p
}
# str(s, k, from, n): the string value of the first key k from position from
# on, raw (escapes kept), at most n bytes; "" when there is none.
function str(s, k, from, n,   p) {
    p = at(s, k, from)
    if (!p) return ""
    p += length(k) + 3
    if (substr(s, p, 1) != "\"") return ""
    return rawstr(substr(s, p + 1, n))
}
# rawstr(t): the JSON string t starts with (just past its opening quote),
# up to its closing quote, escapes kept.
function rawstr(t,   i, j, k, n) {
    n = 0
    while ((i = index(substr(t, n + 1), "\"")) > 0) {
        j = n + i; k = 0
        while (j - k - 1 > 0 && substr(t, j - k - 1, 1) == "\\") k++
        if (k % 2 == 0) return substr(t, 1, j - 1)
        n = j
    }
    return t
}
# unesc(r): a raw JSON string's text; \n as a newline, \r and \t as spaces,
#   to ~ as themselves (&: &), any other \uXXXX as "?".
function unesc(r,   o, i, c, h, x) {
    o = ""
    while ((i = index(r, "\\")) > 0) {
        o = o substr(r, 1, i - 1); c = substr(r, i + 1, 1)
        if (c == "u") {
            h = tolower(substr(r, i + 4, 2)); x = "?"
            if (substr(r, i + 2, 2) == "00" && h ~ /^[2-7][0-9a-f]$/)
                x = substr(ASCII, (index(HEX, substr(h, 1, 1)) - 1) * 16 + index(HEX, substr(h, 2, 1)) - 32, 1)
            o = o (x == "" ? "?" : x); r = substr(r, i + 6); continue
        }
        o = o ((c == "n" || c == "r" || c == "t") ? (c == "n" ? "\n" : " ") : c)
        r = substr(r, i + 2)
    }
    return o r
}
# num(s, k, from): the number value of the first key k from position from on, 0 when none.
function num(s, k, from,   p, t) {
    p = at(s, k, from)
    if (!p) return 0
    t = substr(s, p + length(k) + 3, 32)
    return match(t, /^-?[0-9]+(\.[0-9]+)?/) ? substr(t, 1, RLENGTH) + 0 : 0
}
# iso(t): the epoch of an ISO 8601 UTC time (2026-10-14T09:30:00.123Z), 0 for anything else.
function iso(t,   y, m, d, s) {
    if (t !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]/) return 0
    y = substr(t, 1, 4) + 0; m = substr(t, 6, 2) + 0; d = substr(t, 9, 2) + 0
    s = substr(t, 12, 2) * 3600 + substr(t, 15, 2) * 60 + substr(t, 18, 2)
    if (m <= 2) { y--; m += 12 }
    d = 365 * y + int(y / 4) - int(y / 100) + int(y / 400) + int((153 * (m - 3) + 2) / 5) + d - 719469
    if (match(t, /[+-][0-9][0-9]:[0-9][0-9]$/)) {
        m = substr(t, RSTART + 1, 2) * 3600 + substr(t, RSTART + 4, 2) * 60
        s -= (substr(t, RSTART, 1) == "+") ? m : -m
    }
    return d * 86400 + s
}

# --- What a tool call is ----------------------------------------------------

# program(seg): the program a shell command segment runs (sets pw[], pk:
# its words, the index of the program's, their count), past VAR=value, "!",
# wrappers (sudo, env, nohup, time, timeout N, xargs…) and their options;
# "" for none.
function program(seg,   n, p, v) {
    n = split(seg, pw, /[ \t]+/); pk = 1; pn = n
    while (pk <= n) {
        p = pw[pk]; gsub(/^["'(]+|["')]+$/, "", p); pw[pk] = p
        if (p == "" || p == "{" || p == "!" || p ~ /^[A-Za-z_][A-Za-z0-9_]*=/) { pk++; continue }
        if (p ~ /^(sudo|env|command|exec|nohup|time|nice|builtin|xargs|timeout|then|do|else)$/) {
            v = (p == "sudo" || p == "env") ? "^-[ugUChprtDSP]$" : p == "nice" ? "^-n$" : p == "xargs" ? "^-[InPLsdE]$" : "^$"
            pk++
            while (pk <= n && pw[pk] ~ /^-/) { if (pw[pk] ~ v) pk++; pk++ }
            if (p == "timeout") pk++
            continue
        }
        break
    }
    if (pk > n) return ""
    p = pw[pk]; sub(/.*\//, "", p)
    return p
}
# bashsubj(c): a denied command's subject: the program of its first segment
# that does more than move around or set things (cd, export, echo…), and
# for a multi-command tool its subcommand: never an argument; "-" for none.
function bashsubj(c,   n, seg, i, p, first, k) {
    # What a command substitution runs is not what the command runs.
    for (i = 0; i < 4; i++) { gsub(/\$\([^()]*\)/, "X", c); gsub(/`[^`]*`/, "X", c) }
    gsub(/\n/, ";", c)
    n = split(c, seg, /&&|\|\||;|\|/); first = ""
    for (i = 1; i <= n; i++) {
        p = program(seg[i])
        if (p == "") continue
        if (first == "") { first = p; fk = pk; fn = pn; split("", fw); for (k = 1; k <= pn; k++) fw[k] = pw[k] }
        if (p ~ /^(cd|pushd|popd|export|set|unset|source|\.|true|false|:|echo|printf|if|fi|then|done|while|until|for|test|\[|\[\[)$/) continue
        return dash(clean(withsub(p), 64, "[^A-Za-z0-9._+@:/ -]"))
    }
    if (first == "") return "-"
    for (k = 1; k <= fn; k++) pw[k] = fw[k]
    pk = fk; pn = fn
    return dash(clean(withsub(first), 64, "[^A-Za-z0-9._+@:/ -]"))
}
function withsub(p,   k, w) {
    if (p !~ /^(git|gh|npm|pnpm|yarn|bun|deno|docker|podman|kubectl|helm|terraform|tofu|cargo|go|brew|apt|apt-get|dnf|yum|pacman|pip|pip3|uv|poetry|systemctl|launchctl|aws|gcloud|az|fly|flyctl|vercel|netlify|wrangler|heroku|tmux|herdr|gem|bundle|rails|mix|dotnet|swift|make|claude|codex|agents|rustup|nix)$/) return p
    for (k = pk + 1; k <= pn; k++) {
        w = pw[k]; gsub(/^["']+|["')]+$/, "", w)
        if (w == "") continue
        if (w ~ /^-/) { if (p == "git" && (w == "-C" || w == "-c")) k++; continue }
        return w ~ /^[a-z][a-z0-9_-]*$/ ? p " " w : p
    }
    return p
}
# host(u): the host of a URL, lower case, nothing else of it.
function host(u) {
    sub(/^[A-Za-z][A-Za-z0-9+.-]*:\/\//, "", u); sub(/[\/?#].*$/, "", u); sub(/^.*@/, "", u); sub(/:[0-9]*$/, "", u)
    u = clean(tolower(u), 64, "[^a-z0-9.-]")
    return u == "" ? "-" : u
}
# pollcmd(c): a Bash command that only waits: sleep, a sleep loop, reading
# a Claude Code task's output file (tasks/ID.output), and filters on that.
function pollcmd(c,   t, n, seg, i, s, any) {
    t = c; gsub(/\n/, "; ", t); sub(/^[ \t;]+/, "", t); sub(/[ \t;]+$/, "", t)
    if (t == "") return 0
    if (waits(t) || t ~ /^for .*; *do .*sleep [0-9.]+.*; *done/) return 1
    n = split(t, seg, /&&|\|\||;|\|/); any = 0
    for (i = 1; i <= n; i++) {
        s = seg[i]; gsub(/^[ \t]+|[ \t]+$/, "", s)
        if (s == "") continue
        if (s ~ /^sleep +[0-9.]+[smhd]?$/) { any = 1; continue }
        if (s ~ /^(cat|tail|head)( |$)/ && s ~ /\/tasks\/[A-Za-z0-9_-]+\.output["']?( |$)/) { any = 1; continue }
        if (any && s ~ /^(grep|tail|head|wc)( |$)/) continue
        return 0
    }
    return any
}
# tooluses(s, lim): the tool calls in an assistant line, before position
# lim: into tun[id] (name) and tus[id] (subject); counts the group's calls
# (gtools) and those that only wait (gpolls); adds their ids to gtids.
function tooluses(s, lim,   pat, p, b, e, id, nm, cmd, url, nx) {
    pat = "{\"type\":\"tool_use\",\"id\":\""; b = 1
    while ((p = index(substr(s, b), pat)) > 0) {
        p += b - 1
        if (p >= lim) break
        id = rawstr(substr(s, p + length(pat), 128))
        nx = index(substr(s, p + 1), pat); e = nx ? p + nx : lim
        nm = clean(str(s, "name", p, 128), 64, "[^A-Za-z0-9_.:-]")
        cmd = ""; url = ""
        if (nm == "Bash") cmd = unesc(str(s, "command", p, 4096))
        else if (nm == "WebFetch") url = unesc(str(s, "url", p, 2048))
        if (at(s, "command", p) >= e) cmd = ""
        if (at(s, "url", p) >= e) url = ""
        id = clean(id, 64, "[^A-Za-z0-9_-]")
        if (id != "") {
            tun[id] = dash(nm)
            tus[id] = nm == "Bash" ? bashsubj(cmd) : nm == "WebFetch" ? host(url) : dash(nm)
            gtids = gtids (gtids == "" ? "" : " ") id
        }
        gtools++
        if (nm ~ /^(BashOutput|TaskOutput|AgentOutputTool|Monitor)$/ || (nm == "Bash" && pollcmd(cmd))) gpolls++
        b = p + length(pat)
    }
}

# --- Rows -------------------------------------------------------------------

function keep(ts) { return ts >= cut && !(floor > 0 && ts <= floor) }
function today(ts, i, w, r, o) {
    if (ts >= mid && ts < mid + 86400) { si += i; sw += w; sr += r; so += o }
}
function trow(ts, proj, model, i, w, r, o, poll) {
    if (ts > lastep) lastep = ts
    if (!keep(ts)) return
    printf "%d\t%s\t%s\t%s\t%s\t%s\t%.0f\t%.0f\t%.0f\t%.0f\t%d\n", ts, cli, proj, sess, agent, model, i, w, r, o, poll > tf
    today(ts, i, w, r, o)
}
# flush(): count the message the assistant lines read so far belong to.
function flush() {
    if (!gpend) return
    gpend = 0
    if (!gskip && gmodel != "" && gmodel != "<synthetic>")
        trow(gts, gproj, clean(gmodel, 64, "[^A-Za-z0-9._:/@+-]"), gi, gw, gr, go, gtools > 0 && gpolls == gtools)
    lastid = gid; lasttids = gtids
}
function assistant(s, o,   a, mp, id, up, ts, cwd) {
    a = index(s, "\"type\":\"assistant\",\"uuid\":\"")
    if (!a) a = index(s, "\"type\":\"assistant\"")
    mp = at(s, "model", 1)
    id = mp ? clean(str(s, "id", mp, 128), 128, "[^A-Za-z0-9_-]") : ""
    if (id == "") return
    if (id != gid || !gpend) {
        flush()
        gid = id; gpend = 1; gstart = o; gtools = 0; gpolls = 0; gtids = ""
        gskip = (id == lastid) || (fsub && index(s, "{\"parentUuid\":null,") == 1)
        gmodel = str(s, "model", 1, 128); gts = iso(str(s, "timestamp", a, 64))
        cwd = unesc(str(s, "cwd", a, 4096)); if (cwd != "") proj = projname(cwd)
        gproj = proj; gi = gw = gr = go = 0
    }
    gend = o + length(s) + 1
    up = lastat(s, "\"usage\":{", a)
    if (up) {
        gi = max(gi, num(s, "input_tokens", up)); gw = max(gw, num(s, "cache_creation_input_tokens", up))
        gr = max(gr, num(s, "cache_read_input_tokens", up)); go = max(go, num(s, "output_tokens", up))
    }
    tooluses(s, up ? up : a)
}
function compact(s,   a, ts, cwd, m, trig) {
    a = index(s, "\"type\":\"system\""); ts = iso(str(s, "timestamp", a, 64))
    cwd = unesc(str(s, "cwd", a, 4096)); if (cwd != "") proj = projname(cwd)
    m = at(s, "compactMetadata", 1)
    trig = clean(str(s, "trigger", m, 32), 16, "[^a-z]")
    if (ts > lastep) lastep = ts
    if (!m || !keep(ts)) return
    printf "%d\t%s\t%s\t%s\t%s\t%s\t%.0f\t%.0f\n", ts, cli, proj, sess, agent, dash(trig), num(s, "preTokens", m), num(s, "postTokens", m) > cf
}
# denials(s): the tool results in a user line that say a call was denied.
function denials(s,   a, ts, cwd, k, pat, b, p) {
    a = index(s, "\"type\":\"user\""); ts = iso(str(s, "timestamp", a, 64))
    cwd = unesc(str(s, "cwd", a, 4096)); if (cwd != "") proj = projname(cwd)
    if (ts > lastep) lastep = ts
    if (!keep(ts)) return
    for (k = 1; k <= 6; k++) {
        pat = (k <= 3 ? "\"content\":\"" : "\"text\":\"") dpre[(k - 1) % 3 + 1]; b = 1
        while ((p = index(substr(s, b), pat)) > 0) {
            p += b - 1
            denial(s, ts, p, k)
            b = p + length(pat)
        }
    }
}
function denial(s, ts, p, k,   q, t, rest, seg, i, id, by, reason, r) {
    q = p + (k <= 3 ? 11 : 8)
    t = rawstr(substr(s, q, 65536)); rest = substr(s, q + length(t) + 1, 4096)
    if (k > 3 && (i = index(rest, "]"))) rest = substr(rest, i + 1)
    seg = rest; if ((i = index(seg, "}"))) seg = substr(seg, 1, i)
    id = str(seg, "tool_use_id", 1, 128)
    if (id == "") { i = lastat(s, "\"tool_use_id\":\"", p); if (i) id = rawstr(substr(s, i + 15, 128)) }
    id = clean(id, 64, "[^A-Za-z0-9_-]")
    by = (k - 1) % 3 + 1; reason = "-"
    if (by == 1 && (i = index(t, "Reason: ["))) {
        r = substr(t, i + 9, 200)
        if ((i = index(r, "]"))) reason = dash(clean(substr(r, 1, i - 1), 64, "[^A-Za-z0-9 ._-]"))
    }
    if (id != "" && (id in dseen)) return
    if (id != "") dseen[id] = 1
    printf "%d\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", ts, cli, proj, sess, agent, (id in tun) ? tun[id] : "-", dby[by], reason, (id in tus) ? tus[id] : "-" > df
}
function codex(s,   ts, p, cwd, t, i, c, o) {
    ts = iso(str(s, "timestamp", 1, 64))
    if (index(s, "\"type\":\"session_meta\"")) {
        p = at(s, "payload", 1)
        t = clean(str(s, "id", p, 128), 64, "[^A-Za-z0-9_-]"); if (t != "") sess = t
        cwd = unesc(str(s, "cwd", p, 4096)); if (cwd != "") proj = projname(cwd)
        return
    }
    if (index(s, "\"type\":\"turn_context\"")) {
        p = at(s, "payload", 1)
        t = clean(str(s, "model", p, 128), 64, "[^A-Za-z0-9._:/@+-]"); if (t != "") model = t
        cwd = unesc(str(s, "cwd", p, 4096)); if (cwd != "") proj = projname(cwd)
        return
    }
    if (!index(s, "\"type\":\"token_count\"")) return
    if ((p = at(s, "primary", 1)) && substr(s, p + 10, 1) == "{" && ts >= lim_ep && ts >= cut) {
        t = substr(s, p, 256)
        lim_ep = ts; lim_row = ts "\tcodex\t" num(t, "used_percent", 1) "\t" sprintf("%.0f", num(t, "window_minutes", 1)) "\t" sprintf("%.0f", num(t, "resets_at", 1))
    }
    if (index(s, "\"info\":null")) return
    p = at(s, "total_token_usage", 1); t = p ? sprintf("%.0f", num(s, "total_tokens", p)) : "-"
    if (t != "-" && t == lastid) return
    lastid = t
    if (!(p = at(s, "last_token_usage", 1))) return
    i = num(s, "input_tokens", p); c = num(s, "cached_input_tokens", p); o = num(s, "output_tokens", p)
    if (c > i) c = i
    trow(ts, proj, model, i - c, 0, c, o, 0)
}

# --- One transcript at a time -------------------------------------------------

# begin(): a header: "F|K END work cli path inode size mtime offset last_epoch
# last_id session project agent model pending".
function begin(   h, n, i, a, b, pa, pb) {
    split($0, h, "\t")
    mode = h[1]; fend = h[2] + 0; cli = h[4]; path = h[5]; ino = h[6]; fsize = h[7] + 0; mtime = h[8] + 0
    foff = h[9] + 0; lastep = h[10] + 0; lastid = h[11]; sess = h[12]; proj = h[13]; agent = h[14]; model = h[15]
    pending = h[16]
    floor = foff == 0 ? lastep : 0
    flen = fend - foff
    fsub = (cli == "claude" && path ~ /\/subagents\/agent-[^\/]*\.jsonl$/)
    if (cli != "claude" || !fsub) agent = "main"
    else if (agent == "-" && (path in ty)) agent = ty[path]
    if (cli == "codex" && sess == "-") {
        a = path; sub(/\.jsonl$/, "", a); b = substr(a, length(a) - 35)
        if (length(b) == 36 && b ~ /^[0-9a-f-]+$/) sess = b
    }
    gpend = 0; gid = ""; gtids = ""; lasttids = ""; split("", tun); split("", tus); split("", dseen)
    if (pending != "-") {
        n = split(pending, pa, ";")
        for (i = 1; i <= n; i++) if (split(pa[i], pb, "=") == 3) { tun[pb[1]] = pb[2]; tus[pb[1]] = pb[3]; lasttids = lasttids (lasttids == "" ? "" : " ") pb[1] }
    }
}
function finish(   off, n, i, ids, pend, line) {
    if (mode == "") return
    off = foff
    if (mode == "F") {
        off = fend
        # The last message of an active transcript (or of a cut read) is read
        # again next time, once a line after it shows it complete; one that
        # fills a cut read whole counts now, so the scan moves on.
        if (gpend && gend == flen && (fend < fsize || now - mtime < quiet) && !(gstart == 0 && fend < fsize))
            { off = foff + gstart; gpend = 0 }
        else flush()
    }
    pend = ""; n = split(lasttids, ids, " ")
    for (i = 1; i <= n && i <= 32; i++) if (ids[i] in tun) pend = pend (pend == "" ? "" : ";") ids[i] "=" tun[ids[i]] "=" tus[ids[i]]
    # Joined, not sprintf'd: mawk's sprintf stops at 8 KiB.
    line = path "\t" cli "\t" ino "\t" sprintf("%.0f", off) "\t" sprintf("%.0f", lastep) "\t" dash(lastid) "\t" dash(sess) \
        "\t" dash(proj) "\t" dash(agent) "\t" dash(model) "\t" dash(pend)
    if (!(path in olds) || olds[path] != line) dirty = 1
    news[++nnew] = line
    mode = ""
}

BEGIN {
    tf = d "/tokens.add.tokens"; cf = d "/tokens.add.compacts"; df = d "/tokens.add.denials"
    # The state is rewritten only when it changed (most minutes it does not).
    while ((getline line < (d "/tokens.state")) > 0) { nold++; split(line, f, "\t"); olds[f[1]] = line }
    close(d "/tokens.state")
    HEX = "0123456789abcdef"
    ASCII = " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~"
    dpre[1] = "Permission for this action was denied by the Claude Code auto mode classifier"
    dpre[2] = "Permission for this command was denied by a built-in Claude Code safety check"
    dpre[3] = "The user doesn't want to proceed"
    dby[1] = "classifier"; dby[2] = "safety"; dby[3] = "user"
    while ((getline line < tyf) > 0) if (split(line, f, "\t") == 2) ty[f[1]] = f[2]
    close(tyf)
    # Today's sums so far: tokens.today when it is today's; else, when there
    # is none, what tokens.tsv holds of today (once); else nothing yet.
    yf = d "/tokens.today"; si = sw = sr = so = 0
    if ((getline line < yf) > 0) {
        if (split(line, f, "\t") >= 6 && f[1] == day) { si = f[3] + 0; sw = f[4] + 0; sr = f[5] + 0; so = f[6] + 0 }
    } else {
        while ((getline line < (d "/tokens.tsv")) > 0)
            if (split(line, f, "\t") >= 11) today(f[1] + 0, f[7] + 0, f[8] + 0, f[9] + 0, f[10] + 0)
        close(d "/tokens.tsv")
    }
    close(yf)
    lim_ep = 0
    if ((getline line < (d "/limits.tsv")) > 0) lim_ep = line + 0
    close(d "/limits.tsv")
    lim_old = lim_ep; lim_row = ""
}
/^[FK]\t/ { finish(); begin(); next }
mode == "F" {
    c = index($0, ":"); o = substr($0, 1, c - 1) + 0; s = substr($0, c + 1)
    if (o + length(s) + 1 > flen) next
    if (cli == "codex") { codex(s); next }
    if (index(s, "\"type\":\"assistant\"") && (index(s, "\"type\":\"assistant\",\"uuid\":\"") || \
        !(index(s, "\"type\":\"user\"") || index(s, "\"type\":\"progress\"") || index(s, "\"type\":\"system\"")))) {
        assistant(s, o); next
    }
    flush()
    if (index(s, "\"subtype\":\"compact_boundary\"") && index(s, "\"type\":\"system\"")) compact(s)
    else if (index(s, "\"is_error\":true") && index(s, "\"type\":\"user\"")) denials(s)
}
END {
    finish()
    if (dirty || nnew != nold) {
        printf "" > (d "/tokens.state.new")
        for (i = 1; i <= nnew; i++) print news[i] > (d "/tokens.state.new")
    }
    printf "%s\t%.0f\t%.0f\t%.0f\t%.0f\t%.0f\n", day, si + sw + sr + so, si, sw, sr, so
    if (lim_row != "" && lim_ep > lim_old) print lim_row > (d "/tokens.add.limits")
}
