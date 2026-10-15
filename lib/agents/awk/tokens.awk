# lib/agents/awk/tokens.awk — _agents_tokens_scan: the token rows, from
# _agents_tokens_feed's headers and grep -b lines (tokens.sh documents the
# files). Needs lib_proc (projname) and lib_activity (waits).
# Writes, in the data directory d: tokens.hot.new, only when the hot state
# changed (every transcript the plan handed it: tokens.state, the cold
# rest, is never written here); tokens.add.tokens, .compacts, .denials,
# .tasks and .uses (rows to append); tokens.add.limits only when Codex
# logged a newer rate limit than limits.tsv holds. Prints two lines:
# tokens.today's (today's sums: the old ones when tokens.today is today's,
# else those in tokens.tsv from mid, local midnight, on; plus this scan's),
# then "hot<TAB>LINES<TAB>COLD": the hot state's lines, and how many of them
# have had no row for hotsecs (the next compaction moves them to
# tokens.state). tyf: _agents_tx_agent_types lines; frf: _agents_tokens_forks
# lines. Rows older than cut are not written.
# JSON is read by its keys' spelling, never parsed whole: Claude Code's
# top-level keys follow the message, so a line's own type, timestamp, cwd
# and entrypoint are the first after '"type":"assistant","uuid"' (or the
# line's type); its message's model, id and usage come before.

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
# wrappers (sudo, env, nohup, time, timeout N, xargs…, by name or path) and
# their options; "" for none (a wrapper with no command after it is its own
# program; command -v NAME runs nothing: "command").
function program(seg,   n, p, v, w) {
    n = split(seg, pw, /[ \t]+/); pk = 1; pn = n; w = ""
    while (pk <= n) {
        p = pw[pk]; gsub(/^["'(]+|["')]+$/, "", p); pw[pk] = p
        if (p == "" || p == "{" || p == "!" || p ~ /^[A-Za-z_][A-Za-z0-9_]*=/ || p ~ /^[A-Za-z_][A-Za-z0-9_-]*\(\)?$/) { pk++; continue }
        if (p == "function") { pk += 2; continue }
        sub(/^\/(usr\/)?(local\/)?s?bin\//, "", p)
        if (p == "command" && pw[pk + 1] ~ /^-[vV]$/) return p
        if (p ~ /^(sudo|env|command|exec|nohup|time|nice|builtin|xargs|timeout|then|do|else)$/) {
            v = (p == "sudo" || p == "env") ? "^-[ugUChprtDSP]$" : p == "nice" ? "^-n$" : p == "xargs" ? "^-[InPLsdE]$" : "^$"
            if (p !~ /^(then|do|else)$/) w = p
            pk++
            while (pk <= n && pw[pk] ~ /^-/) { if (pw[pk] ~ v) pk++; pk++ }
            if (p == "timeout") pk++
            continue
        }
        break
    }
    if (pk > n) return w
    p = pw[pk]; sub(/.*\//, "", p)
    return p
}
# bashsubj(c): a denied command's subject: of its segments' programs, the
# last that acts (the action usually comes last: cd x && make deploy), past
# those that only move around or set things (cd, export…) and those that
# only read or filter (cat, grep, sed, jq…); else the first filter; else the
# first program. A multi-command tool adds its subcommand (withsub). Never an
# argument; "-" for none.
function bashsubj(c,   n, seg, i, p, act, filt, first, fn, t) {
    c = unquoted(c)
    # A shell function the command defines is a name it made up, not a program.
    t = c; split("", fn)
    while (match(t, /[A-Za-z_][A-Za-z0-9_-]*[ \t]*\(\)/)) { p = substr(t, RSTART, RLENGTH); sub(/[ \t]*\(\)$/, "", p); fn[p] = 1; t = substr(t, RSTART + RLENGTH) }
    # What a command substitution runs is not what the command runs.
    for (i = 0; i < 4; i++) { gsub(/\$\([^()]*\)/, "\037", c); gsub(/`[^`]*`/, "\037", c) }
    gsub(/\n/, ";", c)
    n = split(c, seg, /&&|\|\||;|\|/); act = filt = first = ""
    for (i = 1; i <= n; i++) {
        p = program(seg[i])
        # Only a name: not a quoted or escaped word, nothing longer than one.
        if (p == "" || length(p) > 40 || (p !~ /^[A-Za-z0-9_][A-Za-z0-9._+-]*$/ && p !~ /^(\.|:|\[|\[\[)$/) || (p in fn)) continue
        if (first == "") first = withsub(p)
        if (p ~ /^(cd|pushd|popd|export|set|unset|source|\.|true|false|:|echo|printf|if|fi|then|elif|done|while|until|for|case|esac|break|continue|exit|return|local|read|shift|trap|command|test|\[|\[\[|sleep|wait)$/) continue
        if (p ~ /^(cat|grep|egrep|fgrep|rg|ag|head|tail|less|more|sed|awk|gawk|mawk|jq|yq|wc|sort|uniq|ls|find|fd|tr|cut|tee|xargs|column|diff|nl|stat|file|basename|dirname|realpath|readlink|pwd|which|date|env)$/) {
            if (filt == "") filt = p
            continue
        }
        act = withsub(p)
    }
    return dash(clean(act != "" ? act : filt != "" ? filt : first, 64, "[^A-Za-z0-9._+@:/ -]"))
}
# unquoted(c): c with each quoted string ('…', "…") made one \037 and each
# escaped character one \036 (neither is ever a program or a subcommand),
# and a heredoc's body (the lines after "<<") dropped: what they hold is an
# argument, and an operator in them (grep 'a|b', python3 -c 'a; b') is not
# one.
function unquoted(c,   o, i, q, t) {
    if ((i = index(c, "<<")) > 0 && (q = index(substr(c, i), "\n")) > 0) c = substr(c, 1, i + q - 2)
    o = ""
    while (match(c, /[\\'"]/)) {
        o = o substr(c, 1, RSTART - 1); q = substr(c, RSTART, 1); c = substr(c, RSTART + 1)
        if (q == "\\") { o = o "\036"; c = substr(c, 2); continue }
        o = o "\037"
        if (q == "'") { i = index(c, "'"); c = i ? substr(c, i + 1) : ""; continue }
        t = rawstr(c); c = substr(c, length(t) + 2)
    }
    return o c
}
# withsub(p): p, and when it is a multi-command tool (SUBS) its subcommand:
# the word right after it, taken only when no option comes first (an
# option's value can be any word: kubectl -n prod delete), and only when it
# is one of the tool's known subcommands (SUBS[p]), or, for a tool whose
# first word names a service ("*": aws, gcloud, az), a plain lowercase word.
# git's -C DIR and -c KEY=VALUE, each one word, are passed over.
function withsub(p,   k, w) {
    if (!SUBS_SET) subs_init()
    if (!(p in SUBS)) return p
    for (k = pk + 1; k <= pn; k++) {
        w = pw[k]; gsub(/^["']+|["')]+$/, "", w)
        if (w == "") continue
        if (p == "git" && (w == "-C" || w == "-c")) { k++; continue }
        if (w ~ /^-/) return p
        if (SUBS[p] == "*") return w ~ /^[a-z][a-z0-9]*(-[a-z0-9]+)*$/ && length(w) <= 24 ? p " " w : p
        return index(" " SUBS[p] " ", " " w " ") ? p " " w : p
    }
    return p
}
# subs_init(): the subcommands withsub names (any other word after the
# tool: none), set the first time one is needed.
function subs_init() {
    SUBS_SET = 1
    subs("git", "add am apply archive bisect blame branch checkout cherry-pick clean clone commit config describe diff fetch filter-branch filter-repo format-patch gc grep init lfs log merge mv notes prune pull push rebase reflog remote reset restore revert rm show sparse-checkout stash status submodule switch tag update-index update-ref worktree")
    subs("gh", "alias api attestation auth browse cache codespace completion config extension gist gpg-key issue label org pr project release repo ruleset run search secret ssh-key status variable workflow")
    subs("npm pnpm yarn bun", "add audit build ci create dedupe dev dlx exec i init install link outdated pack publish rebuild remove rm run start test uninstall unlink up update upgrade version why x")
    subs("deno", "add bench check compile deploy fmt info install lint publish remove run serve task test uninstall upgrade")
    subs("docker podman", "attach build buildx commit compose container context cp create exec image images inspect kill load login logout logs machine network pause prune ps pull push restart rm rmi run save start stats stop system tag top unpause update volume")
    subs("kubectl", "annotate apply attach auth autoscale certificate cluster-info config cordon cp create debug delete describe diff drain edit events exec explain expose get kustomize label logs patch port-forward proxy replace rollout run scale set taint top uncordon wait")
    subs("helm", "create dependency get history install lint list package plugin pull push registry repo rollback search show status template test uninstall upgrade verify")
    subs("terraform tofu", "apply console destroy fmt force-unlock get graph import init login logout output plan providers refresh show state taint test untaint validate workspace")
    subs("cargo", "add bench build check clean clippy doc fetch fix fmt init install login new package publish remove run search test tree uninstall update yank")
    subs("go", "build clean doc env fix fmt generate get install list mod run test tool vet work")
    subs("brew", "bundle cleanup doctor fetch info install link list outdated reinstall remove search services tap uninstall unlink untap update upgrade")
    subs("apt apt-get dnf yum", "autoremove build-dep check clean dist-upgrade download full-upgrade install purge reinstall remove search update upgrade")
    subs("pip pip3", "check download freeze install list show uninstall wheel")
    subs("uv", "add build cache export init lock pip publish python remove run sync tool tree venv")
    subs("poetry", "add build check init install lock publish remove run show sync update")
    subs("systemctl", "daemon-reload disable edit enable isolate kill mask reboot reload restart start status stop unmask")
    subs("launchctl", "bootout bootstrap disable enable kickstart kill list load print remove start stop submit unload")
    subs("aws gcloud az", "*")
    subs("fly flyctl", "apps certs config deploy destroy launch logs machine machines postgres scale secrets ssh status volumes")
    subs("vercel netlify", "build deploy dev env link login logout promote remove rm rollback")
    subs("wrangler", "d1 delete deploy dev kv login pages publish queues r2 rollback secret tail")
    subs("heroku", "addons apps config logs pg ps releases restart rollback run")
    subs("tmux", "attach attach-session capture-pane kill-pane kill-server kill-session kill-window new new-session new-window send-keys split-window")
    subs("herdr", "agent pane session")
    subs("gem bundle", "add exec install list outdated uninstall update")
    subs("rails", "console db generate new routes runner server test")
    subs("mix", "compile deps.get ecto.migrate ecto.reset format phx.server release run test")
    subs("dotnet", "add build clean new pack publish restore run test tool")
    subs("swift", "build package run test")
    subs("make", "all build check ci clean deploy dev dist docs fmt format install lint migrate publish push release run serve setup start stop test uninstall")
    subs("claude codex", "agents config doctor exec mcp plugin resume update")
    subs("agents", "awake hook json kill reap report runs sample term tsv watch why")
    subs("rustup", "component default override target toolchain update")
    subs("nix", "build develop flake profile run shell store")
}
# subs(TOOLS, WORDS): each of TOOLS takes WORDS as its subcommands.
function subs(tools, words,   t, n, i) {
    n = split(tools, t, " ")
    for (i = 1; i <= n; i++) SUBS[t[i]] = words
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
# (gtools) and those that only wait (gpolls); adds their ids to gtids, and
# what they use to gu[] (useof).
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
        useof(s, p, e, str(s, "name", p, 256))
        b = p + length(pat)
    }
}
# useof(s, p, e, name): what the tool call at p (its input ends before e)
# uses, by name only, into the group's gu[kind SUBSEP name]: an MCP server
# (mcp__SERVER__TOOL; a plugin's or claude.ai's server as the name says it:
# plugin_PLUGIN_SERVER, claude_ai_NAME), a skill (Skill: its skill, as
# PLUGIN:SKILL for a plugin's), a subagent type (Agent, Task:
# subagent_type, general-purpose when none is named).
function useof(s, p, e, nm,   k, v, i) {
    if (substr(nm, 1, 5) == "mcp__") {
        k = "mcp"; v = substr(nm, 6); if ((i = index(v, "__")) > 0) v = substr(v, 1, i - 1)
    } else if (nm == "Skill") {
        k = "skill"; i = at(s, "skill", p); v = (i && i < e) ? str(s, "skill", p, 128) : ""
    } else if (nm == "Agent" || nm == "Task") {
        k = "agent"; i = at(s, "subagent_type", p); v = (i && i < e) ? str(s, "subagent_type", p, 128) : "general-purpose"
    } else return
    v = clean(v, 64, "[^A-Za-z0-9_.:@-]")
    if (v != "") gu[k SUBSEP v]++
}

# --- Rows -------------------------------------------------------------------

# keep(ts, id): a row that counts: not older than cut and, in a transcript
# read again from 0, newer than the last row counted (floor), or as new for
# a message other than the last one counted (flid; id "" for a compaction or
# a denial, which then needs a newer time).
function keep(ts, id) { return ts >= cut && !(floor > 0 && (ts < floor || (ts == floor && (id == "" || id == flid)))) }
function today(ts, i, w, r, o) {
    if (ts >= mid && ts < mid + 86400) { si += i; sw += w; sr += r; so += o }
}
# trow(...): one token row (w: all cache writes, h: those of them cached
# for an hour); true when it counts.
function trow(ts, id, proj, model, i, w, r, o, poll, h) {
    if (ts > lastep) lastep = ts
    if (!keep(ts, id)) return 0
    printf "%d\t%s\t%s\t%s\t%s\t%s\t%.0f\t%.0f\t%.0f\t%.0f\t%d\t%.0f\t%s\n", ts, cli, proj, sess, agent, model, i, w, r, o, poll, h, origin > tf
    today(ts, i, w, r, o)
    return 1
}
# flush(): count the message the assistant lines read so far belong to,
# and, when it counts, what its tool calls used.
function flush(   k, w, h) {
    if (!gpend) return
    gpend = 0
    # Cache writes: the 5-minute and 1-hour ones (usage.cache_creation),
    # else all of them as 5-minute ones.
    h = gh; w = max(gw, g5 + gh); if (h > w) h = w
    if (!gskip && gmodel != "" && gmodel != "<synthetic>" \
        && trow(gts, gid, gproj, clean(gmodel, 64, "[^A-Za-z0-9._:/@+-]"), gi, w, gr, go, gtools > 0 && gpolls == gtools, h))
        for (k in gu) tally(gts, gproj, k, gu[k], 0)
    lastid = gid; lasttids = gtids
}
# tally(ts, proj, kind SUBSEP name, n, most): add n uses (most: the largest
# n seen, not their sum) to this transcript's tallies, by hour, written
# when it is done (finish).
function tally(ts, proj, kn, n, most,   k) {
    k = int(ts / 3600) SUBSEP proj SUBSEP kn
    if (!(k in ut)) { uo[++un] = k; ut[k] = 0 }
    if (most) { if (n > uc[k]) uc[k] = n } else uc[k] += n
    if (ts > ut[k]) ut[k] = ts
}
# origin_of(entrypoint): who drove a Claude Code session: you (the CLI, the
# desktop app, an IDE), or a script (the SDK, claude -p: sdk-*).
function origin_of(ep) { return ep == "" ? "" : ep ~ /^sdk/ ? "headless" : "you" }
function assistant(s, o,   a, mp, id, up, ts, cwd, ep, cc, it) {
    a = index(s, "\"type\":\"assistant\",\"uuid\":\"")
    if (!a) a = index(s, "\"type\":\"assistant\"")
    mp = at(s, "model", 1)
    id = mp ? clean(str(s, "id", mp, 128), 128, "[^A-Za-z0-9_-]") : ""
    if (id == "") return
    if (id != gid || !gpend) {
        flush()
        gid = id; gpend = 1; gstart = o; gtools = 0; gpolls = 0; gtids = ""; split("", gu)
        gmodel = str(s, "model", 1, 128); gts = iso(str(s, "timestamp", a, 64))
        # Not counted: the message counted last; a fork's copy of its
        # parent's last message (its first line), or of its parent
        # subagent's history (fork: until its first message of its own); a
        # message older by a minute than the newest line already read here
        # (a rewound or resumed session writes earlier messages again).
        if (fork != "-" && !((fpp SUBSEP id) in pids)) fork = "-"
        gskip = (id == lastid) || (fsub && index(s, "{\"parentUuid\":null,") == 1) || fork != "-" \
            || (gts > 0 && gts < lastep - 60)
        cwd = unesc(str(s, "cwd", a, 4096)); if (cwd != "") proj = projname(cwd)
        if (!fsub && (ep = origin_of(clean(str(s, "entrypoint", a, 64), 32, "[^a-z-]"))) != "") origin = ep
        gproj = proj; gi = gw = gr = go = g5 = gh = 0
    }
    gend = o + length(s) + 1
    up = lastat(s, "\"usage\":{", a)
    if (up) {
        gi = max(gi, num(s, "input_tokens", up)); gw = max(gw, num(s, "cache_creation_input_tokens", up))
        gr = max(gr, num(s, "cache_read_input_tokens", up)); go = max(go, num(s, "output_tokens", up))
        # The message's own cache_creation, never an iteration's.
        cc = at(s, "cache_creation", up); it = at(s, "iterations", up)
        if (cc && (!it || cc < it)) {
            g5 = max(g5, num(s, "ephemeral_5m_input_tokens", cc)); gh = max(gh, num(s, "ephemeral_1h_input_tokens", cc))
        }
    }
    tooluses(s, up ? up : a)
}
# tasks(s): the background tasks a line names ("backgroundTaskId", never in
# a string: a quote there is escaped), each once a scan, for the run
# ledger's tasks.idx: epoch session id source type.
function tasks(s,   a, ts, k, pat, b, p, id, key) {
    a = index(s, "\"type\":\"user\""); ts = iso(str(s, "timestamp", a, 64)); if (!ts) ts = now
    for (k = 1; k <= 2; k++) {
        pat = k == 1 ? "\"backgroundTaskId\":\"" : "\"backgroundTaskId\": \""; b = 1
        while ((p = index(substr(s, b), pat)) > 0) {
            p += b - 1; b = p + length(pat)
            id = substr(s, b, 80)
            if (!match(id, /^[A-Za-z0-9_-]+"/)) continue
            id = substr(id, 1, RLENGTH - 1); key = sess SUBSEP id SUBSEP src
            if (key in tseen) continue
            tseen[key] = 1
            printf "%d\t%s\t%s\t%s\t%s\n", ts, sess, id, src, agent > kf
        }
    }
}
# deferred(s): a session's deferred tool list (an attachment naming the
# tools it may load): how many tools each MCP server lists, a "listed"
# tally (the most a list named).
function deferred(s,   a, ts, i, j, t, n, nm, v, c, k) {
    a = index(s, "\"type\":\"attachment\""); ts = iso(str(s, "timestamp", a, 64))
    if (!ts || fork != "-" || !keep(ts, "")) return
    if (!(i = index(s, "\"addedNames\":["))) return
    t = substr(s, i + 14); if ((j = index(t, "]"))) t = substr(t, 1, j - 1)
    n = split(t, nm, ","); split("", c)
    for (i = 1; i <= n; i++) {
        v = nm[i]; gsub(/"/, "", v)
        if (substr(v, 1, 5) != "mcp__") continue
        v = substr(v, 6); if ((j = index(v, "__")) > 0) v = substr(v, 1, j - 1)
        v = clean(v, 64, "[^A-Za-z0-9_.:@-]"); if (v != "") c[v]++
    }
    for (k in c) tally(ts, proj, "listed" SUBSEP k, c[k], 1)
}
function compact(s,   a, ts, cwd, m, trig) {
    a = index(s, "\"type\":\"system\""); ts = iso(str(s, "timestamp", a, 64))
    cwd = unesc(str(s, "cwd", a, 4096)); if (cwd != "") proj = projname(cwd)
    m = at(s, "compactMetadata", 1)
    trig = clean(str(s, "trigger", m, 32), 16, "[^a-z]")
    if (ts > lastep) lastep = ts
    if (!m || fork != "-" || !keep(ts, "")) return
    printf "%d\t%s\t%s\t%s\t%s\t%s\t%.0f\t%.0f\n", ts, cli, proj, sess, agent, dash(trig), num(s, "preTokens", m), num(s, "postTokens", m) > cf
}
# denials(s): the tool results in a user line that say a call was denied.
function denials(s,   a, ts, cwd, k, pat, b, p) {
    a = index(s, "\"type\":\"user\""); ts = iso(str(s, "timestamp", a, 64))
    cwd = unesc(str(s, "cwd", a, 4096)); if (cwd != "") proj = projname(cwd)
    if (ts > lastep) lastep = ts
    if (fork != "-" || !keep(ts, "")) return
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
        # Who drove it: codex exec (headless), a subagent another session
        # started, or you (the TUI, an IDE).
        t = str(s, "source", p, 32)
        if (index(s, "\"source\":{\"subagent\"")) origin = "subagent"
        else if (t == "exec" || str(s, "originator", p, 64) == "codex_exec") origin = "headless"
        else if (t != "" || str(s, "originator", p, 64) != "") origin = "you"
        return
    }
    # A call of an MCP server's tool: a function call named mcp__SERVER__TOOL
    # (older Codex: SERVER__TOOL; its own tools never hold "__").
    if (index(s, "\"type\":\"function_call\"")) {
        t = str(s, "name", at(s, "payload", 1), 256)
        if (substr(t, 1, 5) == "mcp__") t = substr(t, 6)
        if ((i = index(t, "__")) < 2) return
        t = clean(substr(t, 1, i - 1), 64, "[^A-Za-z0-9_.:@-]")
        if (t != "" && ts && keep(ts, "")) tally(ts, proj, "mcp" SUBSEP t, 1, 0)
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
    trow(ts, t, proj, model, i - c, 0, c, o, 0, 0)
}

# --- One transcript at a time -------------------------------------------------

# begin(): a header: "F|K END work cli path inode size mtime offset last_epoch
# last_id session project agent model pending fork origin". fork: while a
# fork of a subagent is still in the history it copied, that subagent's id,
# else "-". origin: who drove the session (you, headless; a subagent's
# transcript is subagent's, or fork's), "-" until a line says.
function begin(   h, n, i, a, b, pa, pb) {
    split($0, h, "\t")
    mode = h[1]; fend = h[2] + 0; cli = h[4]; path = h[5]; ino = h[6]; fsize = h[7] + 0; mtime = h[8] + 0
    foff = h[9] + 0; lastep = h[10] + 0; lastid = h[11]; sess = h[12]; proj = h[13]; agent = h[14]; model = h[15]
    pending = h[16]; fork = h[17] == "" ? "-" : h[17]; origin = h[18] == "" ? "-" : h[18]
    floor = foff == 0 ? lastep : 0; flid = lastid
    flen = fend - foff
    fsub = (cli == "claude" && path ~ /\/subagents\/agent-[^\/]*\.jsonl$/)
    if (cli != "claude" || !fsub) agent = "main"
    else if (agent == "-" && (path in ty)) agent = ty[path]
    src = "main"
    if (fsub) { src = path; sub(/^.*\/agent-/, "", src); sub(/\.jsonl$/, "", src); origin = agent == "fork" ? "fork" : "subagent" }
    if (fsub && fork == "-" && foff == 0 && (path in fpar)) fork = fpar[path]
    a = path; sub(/\/[^\/]*$/, "", a); fpp = a "/agent-" fork ".jsonl"
    if (cli == "codex" && sess == "-") {
        a = path; sub(/\.jsonl$/, "", a); b = substr(a, length(a) - 35)
        if (length(b) == 36 && b ~ /^[0-9a-f-]+$/) sess = b
    }
    gpend = 0; gid = ""; gtids = ""; lasttids = ""; split("", tun); split("", tus); split("", dseen)
    un = 0; split("", uo); split("", ut); split("", uc)
    if (pending != "-") {
        n = split(pending, pa, ";")
        for (i = 1; i <= n; i++) if (split(pa[i], pb, "=") == 3) { tun[pb[1]] = pb[2]; tus[pb[1]] = pb[3]; lasttids = lasttids (lasttids == "" ? "" : " ") pb[1] }
    }
}
function finish(   off, n, i, ids, pend, line, q) {
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
    # This transcript's uses, one row per hour, project, kind and name.
    for (i = 1; i <= un; i++) {
        split(uo[i], q, SUBSEP)
        printf "%d\t%s\t%s\t%s\t%s\t%s\t%s\t%d\n", ut[uo[i]], cli, q[2], sess, agent, q[3], q[4], uc[uo[i]] > uf
    }
    pend = ""; n = split(lasttids, ids, " ")
    for (i = 1; i <= n && i <= 32; i++) if (ids[i] in tun) pend = pend (pend == "" ? "" : ";") ids[i] "=" tun[ids[i]] "=" tus[ids[i]]
    # Joined, not sprintf'd: mawk's sprintf stops at 8 KiB.
    line = path "\t" cli "\t" ino "\t" sprintf("%.0f", off) "\t" sprintf("%.0f", lastep) "\t" dash(lastid) "\t" dash(sess) \
        "\t" dash(proj) "\t" dash(agent) "\t" dash(model) "\t" dash(pend) "\t" dash(fork) "\t" dash(origin)
    if (!(path in olds) || olds[path] != line) dirty = 1
    news[++nnew] = line
    if (lastep < now - hotsecs) ncold++
    mode = ""
}

BEGIN {
    tf = d "/tokens.add.tokens"; cf = d "/tokens.add.compacts"; df = d "/tokens.add.denials"
    kf = d "/tokens.add.tasks"; uf = d "/tokens.add.uses"
    # The hot state is rewritten only when it changed.
    while ((getline line < (d "/tokens.hot")) > 0) { nold++; split(line, f, "\t"); olds[f[1]] = line }
    close(d "/tokens.hot")
    HEX = "0123456789abcdef"
    ASCII = " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~"
    dpre[1] = "Permission for this action was denied by the Claude Code auto mode classifier"
    dpre[2] = "Permission for this command was denied by a built-in Claude Code safety check"
    dpre[3] = "The user doesn't want to proceed"
    dby[1] = "classifier"; dby[2] = "safety"; dby[3] = "user"
    while ((getline line < tyf) > 0) if (split(line, f, "\t") == 2) ty[f[1]] = f[2]
    close(tyf)
    while ((getline line < frf) > 0) if (split(line, f, "\t") == 3) { if (f[1] == "F") fpar[f[2]] = f[3]; else if (f[1] == "I") pids[f[2], f[3]] = 1 }
    close(frf)
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
    # A line read only for a task id or a deferred tool list never ends the
    # message before it: a tool's result can come between two of its lines.
    if (index(s, "\"backgroundTaskId\"")) tasks(s)
    if (index(s, "\"type\":\"deferred_tools_delta\"")) deferred(s)
    if (!index(s, "\"type\":\"assistant\"") && !index(s, "\"subtype\":\"compact_boundary\"") && !index(s, "\"is_error\":true")) next
    flush()
    if (index(s, "\"subtype\":\"compact_boundary\"") && index(s, "\"type\":\"system\"")) compact(s)
    else if (index(s, "\"is_error\":true") && index(s, "\"type\":\"user\"")) denials(s)
}
END {
    finish()
    if (dirty || nnew != nold) {
        printf "" > (d "/tokens.hot.new")
        for (i = 1; i <= nnew; i++) print news[i] > (d "/tokens.hot.new")
    }
    printf "%s\t%.0f\t%.0f\t%.0f\t%.0f\t%.0f\n", day, si + sw + sr + so, si, sw, sr, so
    printf "hot\t%d\t%d\n", nnew, ncold
    if (lim_row != "" && lim_ep > lim_old) print lim_row > (d "/tokens.add.limits")
}
