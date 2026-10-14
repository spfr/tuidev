# lib/agents/awk/hook_match.awk — _agents_hook_match: the background tasks
# that run as direct children of claude c, matched by their output file.
# Needs lib_proc and lib_activity.

function norm(s) { gsub(/\/\/+/, "/", s); sub(/^\/private\//, "/", s); return s }
function ends(s, t) { return length(s) >= length(t) && substr(s, length(s) - length(t) + 1) == t }
function firstword(s,   w) { w = s; sub(/^[( ]+/, "", w); sub(/[ ;&|)].*$/, "", w); sub(/.*\//, "", w); return w == "" ? "command" : w }
function hit(p, i,   s, w) {
    if (taken[p]++) return
    done[i] = 1
    s = tool_cmd(av[p]); w = waits(s) ? 1 : 0
    if (ts[i] == "wait" && !w) return
    gsub(/\t/, " ", s)
    printf "%d@%s\t%s\toutput\t%s\t%d\n", p, st[p], tid[i], (w ? "wait-loop" : firstword(s)), w
}
BEGIN {
    n = split(ENVIRON["H_TASKS"], t, "\n")
    for (i = 1; i <= n; i++) {
        if (split(t[i], f, "\t") < 3 || f[1] == "" || (f[1] in seen)) continue
        seen[f[1]] = 1; nt++; tid[nt] = f[1]; tp[nt] = (f[2] == "-" ? "-" : norm(f[2])); ts[nt] = f[3]
    }
    n = split(ENVIRON["H_OUTS"], t, "\n")
    for (i = 1; i <= n; i++) if (split(t[i], f, "\t") >= 2 && f[2] ~ /^\//) out[f[1] + 0] = norm(f[2])
}
NF >= 14 { p = $1 + 0; pp[p] = $2 + 0; uid[p] = $3; st[p] = lstart(); av[p] = argv($0); ord[++np] = p }
END {
    c += 0; if (c <= 1 || !(c in pp) || nt == 0) exit
    ancestors(self)
    for (k = 1; k <= np; k++) {
        p = ord[k]
        if (pp[p] != c || anc[p] || uid[p] != me || !(p in out)) continue
        for (i = 1; i <= nt; i++)
            if (!done[i] && (tp[i] != "-" ? out[p] == tp[i] : ends(out[p], "/tasks/" tid[i] ".output"))) { hit(p, i); break }
    }
}
