# lib/agents/awk/runs_obs.awk — _agents_runs_observe: what one snapshot shows
# of the runs (runs.sh documents them), from enriched agent, stale and act
# records and jp lines (awk/lib_jobs.awk). Needs lib_proc and lib_activity.
# One line per run, then one per process in a run:
#   run  EPOCH KEY START_EPOCH JOB PROJECT SESSION CMD RSS_KIB DUP ORIGIN OUT
#   runp EPOCH RUN_KEY PROC_KEY CPUTIME_S JOB START_EPOCH PROJECT SESSION_KIND
# KEY: pid@start. ORIGIN: the subagent worktree the command runs in
# (agent-ID), else "-". OUT: its stdout when that is a Claude Code task
# output file (…/tasks/ID.output), else "-". The runp lines carry what a
# history sample needs to count a process that ends before it sees it.
# ENVIRON AGENTS_PATHS: _agents_cwds --stdout's lines.

function key(p, s) { return p "@" s }
function run(k, start, job, proj, sess, cmd, rss, dup, orig, out) {
    nr++; rk[nr] = k
    rl[nr] = k "\t" start "\t" (job == "" ? "-" : job) "\t" proj "\t" sess "\t" cmd "\t" (rss + 0) "\t" dup "\t" orig "\t" out
}
BEGIN {
    n = split(ENVIRON["AGENTS_PATHS"], t, "\n")
    for (i = 1; i <= n; i++)
        if (split(t[i], f, "\t") >= 3 && f[3] == "1" && f[2] ~ /^\/.*\/tasks\/[A-Za-z0-9_-]+\.output$/) out[f[1]] = f[2]
}
$1 == "agent" && NF >= 15 { k = ($3 == "daemon" ? "codex" : $3); proj[$2] = $15; kind[$2] = k; sess[$2] = k ":" $2 }
$1 == "stale" && NF >= 15 { ns++; sp[ns] = $2; sl[ns] = $0; proj[$2] = $15; kind[$2] = "-"; srun[$2] = key($2, $9) }
$1 == "act" && $3 == "tool" && NF >= 17 { nt++; tp[nt] = $2; tl[nt] = $0; trun[$2] = key($2, $9) }
$1 == "jp" && NF >= 9 { nj++; jl[nj] = $0; ujob[$2] = $5 }
END {
    for (i = 1; i <= nt; i++) {
        $0 = tl[i]; r = $11
        o = ($15 ~ /^agent-[A-Za-z0-9]+$/) ? $15 : "-"
        run(trun[$2], now - $4, ujob[$2], (r in proj) ? proj[r] : "-", (r in sess) ? sess[r] : "-",
            cmd_name($14), $7, ($16 ~ /(^|,)dup(,|$)/) ? 1 : 0, o, ($2 in out) ? out[$2] : "-")
    }
    for (i = 1; i <= ns; i++) {
        $0 = sl[i]; a = $14
        c = tool_shell(a) ? cmd_name(tool_cmd(a)) : cmd_name(pname(a))
        run(srun[$2], now - $4, ujob[$2], $15, "-", c, $7, 0, "-", "-")
    }
    for (i = 1; i <= nr; i++) print "run\t" now "\t" rl[i]
    for (i = 1; i <= nj; i++) {
        split(jl[i], f, "\t")
        # f: jp PID START ROOT JOB CPUTIME RSS AGE UNIT
        if (f[9] in trun) k = trun[f[9]]; else if (f[4] in srun) k = srun[f[4]]; else continue
        r = f[4]
        print "runp\t" now "\t" k "\t" key(f[2], f[3]) "\t" (f[6] + 0) "\t" f[5] "\t" (now - f[8]) "\t" ((r in proj) ? proj[r] : "-") "\t" ((r in kind) ? kind[r] : "-")
    }
}
