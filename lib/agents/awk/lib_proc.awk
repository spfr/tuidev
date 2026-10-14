# lib/agents/awk/lib_proc.awk — process-table primitives, shared by every
# program that reads an agents_snapshot record (pid ppid uid user %cpu rss
# time etime lstart(5 words) args):
#   secs, base, pname, critical, agent_kind, interactive_shell, supervisor,
#   hosts, argv, lstart, ancestors.
# Reads ENVIRON: AGENTS_NAMES, AGENTS_SUPERVISOR_NAMES, AGENTS_SHELL_NAMES,
# AGENTS_DAEMON_PATTERN, AGENTS_CRITICAL_NAMES, AGENTS_CRITICAL_PATH.

# secs: ps `time`/`etime` ([DD-][HH:]MM:SS[.cc]) to seconds.
# pname: a readable name for argv (the executable inside an .app bundle).
function secs(s,   d, i, n, a, t) {
    sub(/\.[0-9]*$/, "", s)
    d = 0; i = index(s, "-")
    if (i > 0) { d = substr(s, 1, i - 1) + 0; s = substr(s, i + 1) }
    n = split(s, a, ":"); t = 0
    for (i = 1; i <= n; i++) t = t * 60 + a[i]
    return d * 86400 + t
}
function base(a,   b) { b = a; sub(/ .*/, "", b); sub(/.*\//, "", b); return b }
function pname(a,   i, s) {
    i = index(a, ".app/Contents/MacOS/")
    if (i == 0) return base(a)
    s = substr(a, i + 20); sub(/ --?[A-Za-z].*$/, "", s)
    return s
}
function critical(a,   n, t, i, nm, w) {
    if (ENVIRON["AGENTS_CRITICAL_PATH"] != "" && a ~ ENVIRON["AGENTS_CRITICAL_PATH"]) return 1
    nm = pname(a); w = nm; sub(/ .*/, "", w)       # "Terminal" from "Terminal -psn_0_1"
    n = split(ENVIRON["AGENTS_CRITICAL_NAMES"], t, " ")
    for (i = 1; i <= n; i++) if (nm == t[i] || w == t[i]) return 1
    return 0
}
# Name lists for the host checks below, read once from the environment.
function hostinit(   n, t, i) {
    if (host_ok++) return
    n = split(ENVIRON["AGENTS_NAMES"], t, " "); for (i = 1; i <= n; i++) names[t[i]] = 1
    n = split(ENVIRON["AGENTS_SUPERVISOR_NAMES"], t, " "); for (i = 1; i <= n; i++) sups[t[i]] = 1
    n = split(ENVIRON["AGENTS_SHELL_NAMES"], t, " "); for (i = 1; i <= n; i++) shells[t[i]] = 1
}
function agent_kind(a,   b) {
    hostinit()
    if (a ~ /--chrome-native-host/) return ""        # a browser bridge, not a session
    b = base(a)
    if (b in names) return b
    if (a ~ /claude-code\/cli\.m?js/) return "claude"
    if (a ~ /@openai\/codex\/bin\/codex/) return "codex"
    return ""
}
# An interactive or login shell: "-zsh", "zsh", "/bin/bash -l", but not
# "bash -c CMD" or "sh script.sh".
function interactive_shell(a,   b, login, rest) {
    hostinit()
    b = a; sub(/ .*/, "", b); login = (substr(b, 1, 1) == "-"); sub(/^-/, "", b); sub(/.*\//, "", b)
    if (!(b in shells)) return 0
    if (login || index(a, " ") == 0) return 1
    rest = a; sub(/^[^ ]+ +/, "", rest)
    return rest ~ /^(-[A-Za-z]+|--login|--interactive)( +(-[A-Za-z]+|--login|--interactive))*$/
}
function supervisor(a) { hostinit(); return (base(a) in sups) || a ~ /^PM2 / || a ~ /^tmux: / }
# Hosts a session: an agent (or the Codex daemon), an interactive shell, or a
# session supervisor. Such a process shelters every ancestor.
function hosts(a) {
    return agent_kind(a) != "" || a ~ ENVIRON["AGENTS_DAEMON_PATTERN"] || interactive_shell(a) || supervisor(a)
}
# argv(): the command line, column 14 on, of the current record (line is $0).
# Skips the 13 fields by position, cheaper than 13 regex substitutions.
function argv(line,   s, i, p, k) {
    p = 1
    for (i = 1; i <= 13; i++) { k = index(substr(line, p), $i); p += k - 1 + length($i) }
    s = substr(line, p); sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s
}
# lstart(): the current record's start time (its 5 lstart words) as one token,
# Wed_Oct_14_08:00:00_2026: what PID@START names a process by.
function lstart() { return $9 "_" $10 "_" $11 "_" $12 "_" $13 }
# ancestors(p): anc[q] = 1 for p and every process above it, by the
# program's parent table pp[] (at most 64 levels).
function ancestors(p,   d) {
    p += 0; d = 0
    while (p > 0 && (p in pp) && d++ < 64) { anc[p] = 1; p = pp[p] }
}
