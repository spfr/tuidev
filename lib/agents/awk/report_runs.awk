# lib/agents/awk/report_runs.awk — the run ledger, read once for every view
# of `agents report`. Part of report.awk's program; needs lib_sort.
#
# runs.tsv, one row per finished run:
#   end_epoch start_epoch job project session agent cmd duration_s cpu_s
#   peak_rss_kib exit dup cleaned
# A run counts in the window it ended in: this one (end >= start) or the one
# before it (pstart <= end < pend), which only the trends need.
#
# Definitions, the same in every view:
#   failed    a known, non-zero exit; a run a cleanup stopped (cleaned=1) is
#             neither failed nor not: it counts in no failure rate;
#   re-run    a failed run followed by the same command (project, cmd, job)
#             from the same session starting within RERUN_GAP seconds of its
#             end; its CPU counts as wasted;
#   dup       a run the ledger marked a duplicate: the same command already
#             running in the same project;
#   cleaned   a run a cleanup stopped (kill, reap, auto-reap, a hook): it was
#             left running, and its CPU and hours are the leak's cost.

# runs_load FILE START PSTART PEND — read the ledger into:
#   RL 1 when it has any row at all; RN, RCPU, RDUR: this window's runs.
#   Commands (project SUBSEP cmd SUBSEP job): GO[1..GC] first seen first;
#     Gn Gcpu Gknown Gfail Gdup Gdupcpu Grer Grercpu, Gd[k, 1..Gn[k]] durations.
#   Agent types: AO[1..AC]; An Acpu Aknown Afail Adup Adupcpu Acln Aclncpu
#     Aclndur Aclnw Aclnwdur Aw Awdur Awcpu (w: wait loops).
#   Cleaned runs by job: CJO[1..CJC]; CJn CJcpu CJdur.
#   Both windows, W 1 (this) or 2 (before), by project and by job: TPn[W, p]
#     TPcpu[W, p] TPd[W, p, i]; TJn TJcpu TJd likewise; TPJcpu[W, p, j];
#     TPO[1..TPC] and TJO[1..TJC] the names seen in either.
function runs_load(rf, start, pstart, pend,   ln, f, e, w, j, p, a, c, d, cpu, k, rk, x, cln, dup, known, failed, n) {
    RERUN_GAP = 120
    RL = 0; RN = 0; RCPU = 0; RDUR = 0; GC = 0; AC = 0; CJC = 0; TPC = 0; TJC = 0
    while ((getline ln < rf) > 0) {
        if (split(ln, f, "\t") < 13 || f[1] !~ /^[0-9]+$/) continue
        RL = 1
        e = f[1] + 0
        if (e >= start) w = 1; else if (e >= pstart && e < pend) w = 2; else continue
        j = f[3] == "" ? "other" : f[3]; p = f[4] == "" ? "-" : f[4]
        a = f[6] == "" ? "-" : f[6]; c = f[7] == "" ? "-" : f[7]
        d = f[8] + 0; cpu = f[9] + 0
        if (d < 0) d = 0
        if (cpu < 0) cpu = 0
        if (!((1, p) in TPn) && !((2, p) in TPn)) TPO[++TPC] = p
        if (!((1, j) in TJn) && !((2, j) in TJn)) TJO[++TJC] = j
        n = ++TPn[w, p]; TPcpu[w, p] += cpu; TPd[w, p, n] = d; TPJcpu[w, p, j] += cpu
        n = ++TJn[w, j]; TJcpu[w, j] += cpu; TJd[w, j, n] = d
        if (w == 2) continue

        RN++; RCPU += cpu; RDUR += d
        cln = f[13] == "1"; dup = f[12] == "1"
        known = !cln && f[11] ~ /^[0-9]+$/; failed = known && f[11] + 0 != 0
        k = p SUBSEP c SUBSEP j
        if (!(k in Gn)) GO[++GC] = k
        n = ++Gn[k]; Gcpu[k] += cpu; Gd[k, n] = d
        if (known) Gknown[k]++
        if (failed) Gfail[k]++
        if (dup) { Gdup[k]++; Gdupcpu[k] += cpu }
        if (!(a in An)) AO[++AC] = a
        An[a]++; Acpu[a] += cpu
        if (known) Aknown[a]++
        if (failed) Afail[a]++
        if (dup) { Adup[a]++; Adupcpu[a] += cpu }
        if (j == "wait") { Aw[a]++; Awdur[a] += d; Awcpu[a] += cpu }
        if (cln) {
            Acln[a]++; Aclncpu[a] += cpu; Aclndur[a] += d
            if (j == "wait") { Aclnw[a]++; Aclnwdur[a] += d }
            if (!(j in CJn)) CJO[++CJC] = j
            CJn[j]++; CJcpu[j] += cpu; CJdur[j] += d
        }
        # A re-run: the last failed run of this command in this session ended
        # just before this one started (rows come in the order runs ended).
        rk = k SUBSEP f[5]
        if (rk in LFe) {
            x = f[2] - LFe[rk]
            if (x >= -2 && x <= RERUN_GAP) { Grer[k]++; Grercpu[k] += LFc[rk] }
            if (x >= -2) { delete LFe[rk]; delete LFc[rk] }
        }
        if (failed) { LFe[rk] = e; LFc[rk] = cpu }
    }
    close(rf)
}

# dstats ARR KEY N — D_MED (the middle run; the mean of the middle two),
# D_P90 (nearest rank) and D_MAX of ARR[KEY, 1..N]; all 0 when N is 0.
function dstats(arr, k, n,   i, t) {
    D_MED = D_P90 = D_MAX = 0
    if (n < 1) return
    split("", t)
    for (i = 1; i <= n; i++) t[i] = arr[k, i]
    sortn(t, n)
    D_MED = (n % 2) ? t[(n + 1) / 2] : (t[n / 2] + t[n / 2 + 1]) / 2
    D_P90 = t[int((9 * n + 9) / 10)]
    D_MAX = t[n]
}

# gsplit K — G_P, G_C, G_J: the project, cmd and job of a command key.
function gsplit(k,   f) { split(k, f, SUBSEP); G_P = f[1]; G_C = f[2]; G_J = f[3] }

# Regressions, window over window, for a project or a job: more CPU (up by
# half or more, and by 0.25 CPU-h or more), or slower (the median run up by
# half and 30 s or more, over 5 runs or more in each window).
function cpu_regressed(c, p) { return p > 0 && c - p >= 900 && c >= 1.5 * p }
function slower(mc, mp, nc, np) { return nc >= 5 && np >= 5 && mp > 0 && mc - mp >= 30 && mc >= 1.5 * mp }
