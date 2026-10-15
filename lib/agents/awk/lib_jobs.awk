# lib/agents/awk/lib_jobs.awk — where an agent tree's CPU goes: the job of
# each process (jobmatch, jobof) and the job records (jobs_emit), run at the
# end of classify.awk over its tables (ord, n, pp, kind, av, root, sroot,
# mine, cpu, rss, ct, et, st). The job rules are in config.sh, by
# _AGENTS_JOB_TEST_RE; AGENTS_JRE_* in the environment carry them here.
# Needs lib_proc.awk and lib_activity.awk.
#
# One "job" record per unit and job, a unit being the root of an agent tree
# or of a stale one, or a child of that root (a tool command, an MCP server…):
#   job ROOT JOB 0 CPU 0 RSS PROCS ROOT_START own|sub UNIT KIND - NAME
# own: JOB is the unit process's own job (what `agents json` gives a tool or
# an MCP server). KIND is the root's agent kind, "-" for a stale tree. NAME:
# an MCP server's name (mcp_name) on its own mcp row, else "-".
# agents_enrich adds the root's cwd (13) and project (15). With
# AGENTS_JOBS_PROC set (agents sample, the menu's run feed), also one line per
# process:
#   jp PID START ROOT JOB CPUTIME_S RSS AGE_S UNIT

function jobinit() {
    if (job_ok++) return
    jre_test = ENVIRON["AGENTS_JRE_TEST"]; jre_build = ENVIRON["AGENTS_JRE_BUILD"]; jre_server = ENVIRON["AGENTS_JRE_SERVER"]
    jre_browser = ENVIRON["AGENTS_JRE_BROWSER"]; jre_mcp = ENVIRON["AGENTS_JRE_MCP"]
}
# jobmatch: the job a process asks for by its own command, "" for none. A tool
# command is matched as the command it runs, and is never an MCP server.
function jobmatch(a,   c, t) {
    jobinit()
    t = tool_shell(a)
    if (t) { c = tool_cmd(a); if (waits(c)) return "wait" } else c = a
    if (jre_test != "" && c ~ jre_test) return "test"
    if (jre_build != "" && c ~ jre_build) return "build"
    if (!t && ((jre_mcp != "" && c ~ jre_mcp) || mcp_known(c, "") != "")) return "mcp"
    if (jre_server != "" && c ~ jre_server) return "server"
    return ""
}
# jobof: agent and browser always; otherwise the parent's job (unless that is
# agent or other), else its own match, else other. jroot[] is the scope.
function jobof(p,   j) {
    if (p in jb) return jb[p]
    jobinit()
    if (kind[p] != "") return jb[p] = "agent"
    if (jre_browser != "" && av[p] ~ jre_browser) return jb[p] = "browser"
    if (p != jroot[p] && (pp[p] in jroot)) {
        j = jobof(pp[p]); if (j != "agent" && j != "other") return jb[p] = j
    }
    j = jobmatch(av[p])
    return jb[p] = (j == "" ? "other" : j)
}
function jobs_emit(   k, p, q, r, u, d, j, key, nk, i, proc) {
    proc = (ENVIRON["AGENTS_JOBS_PROC"] != "")
    for (k = 1; k <= n; k++) {
        p = ord[k]
        if (mine[p]) continue
        r = root[p]; q = p; d = 0
        if (r == "") while (q > 1 && (q in pp) && d++ < 64) { if (q in sroot) { r = q; break } q = pp[q] }
        if (r != "") jroot[p] = r
    }
    nk = 0
    for (k = 1; k <= n; k++) {
        p = ord[k]
        if (!(p in jroot)) continue
        r = jroot[p]; u = p; d = 0
        while (u != r && pp[u] != r && d++ < 64) u = pp[u]
        j = jobof(p); key = u SUBSEP j
        if (!(key in jn)) { nk++; jku[nk] = u; jkj[nk] = j }
        jc[key] += cpu[p]; jm[key] += rss[p]; jn[key]++
        if (proc) printf "jp\t%d\t%s\t%d\t%s\t%d\t%d\t%d\t%d\n", p, st[p], r, j, ct[p], rss[p], et[p], u
    }
    for (i = 1; i <= nk; i++) {
        u = jku[i]; j = jkj[i]; key = u SUBSEP j; r = jroot[u]
        printf "job\t%d\t%s\t0\t%.1f\t0\t%d\t%d\t%s\t%s\t%d\t%s\t-\t%s\n", r, j, jc[key], jm[key], jn[key], st[r], (j == jobof(u) ? "own" : "sub"), u, (kind[r] == "" ? "-" : kind[r]), (j == "mcp" && j == jobof(u) ? mcp_name(av[u], kind[r]) : "-")
    }
}
