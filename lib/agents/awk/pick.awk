# lib/agents/awk/pick.awk — `agents pick`'s list, from agents_collect's
# records: a header, then one line per thing to pick, tab-separated
#   PID PID@START LINE
# each session (blocked first, as agents_enrich orders them) followed by what
# it runs (MCP servers by name, commands, nested sessions), then stale
# processes and hogs. LINE: type, pid, CPU%, memory, age, name, what. -v
# home=HOME. Needs lib_fmt.

function tilde(p) { return (p != "-" && home != "" && index(p, home) == 1) ? "~" substr(p, length(home) + 1) : p }
function row(pid, start, type, cpu, rss, age_s, name, what) {
    gsub(/[[:cntrl:]]/, " ", what); gsub(/[[:cntrl:]]/, " ", name)
    printf "%s\t%s@%s\t%-10s %7s %6.1f %6s %7s  %-22s %s\n", pid, pid, start, type, pid, cpu, mem(rss), age(age_s), cut(name, 22), what
}
BEGIN { FS = "\t" }
NF >= 14 && $1 == "agent" { na++; ag[na] = $0 }
NF >= 14 && $1 == "act" && $3 != "keepawake" { nx[$11]++; ax[$11, nx[$11]] = $0 }
NF >= 14 && $1 == "stale" { ns++; st[ns] = $0 }
NF >= 14 && $1 == "hog" { nh++; hg[nh] = $0 }
END {
    printf "PID\t-\t%-10s %7s %6s %6s %7s  %-22s %s\n", "TYPE", "PID", "CPU%", "MEM", "AGE", "NAME", "WHAT"
    for (i = 1; i <= na; i++) {
        split(ag[i], f, "\t")
        what = (f[12] != "-" ? f[12] " · " : "") f[14]
        row(f[2], f[9], (f[3] == "daemon" ? "daemon" : f[3]), f[5], f[7], f[4], (f[15] == "" ? "-" : f[15]), what)
        for (j = 1; j <= nx[f[2]]; j++) {
            split(ax[f[2], j], x, "\t")
            if (x[3] == "mcp") { nm = x[12]; what = x[14] }
            else if (x[3] == "tool") { nm = (x[15] == "" || x[15] == "-") ? "" : x[15]; what = x[14] }
            else { nm = (x[3] == "session" ? x[12] : ""); what = x[14] }
            row(x[2], x[9], "  " x[3], x[5], x[7], x[4], (nm == "" ? "-" : nm), what)
        }
    }
    for (i = 1; i <= ns; i++) { split(st[i], f, "\t"); row(f[2], f[9], "stale", f[5], f[7], f[4], (f[15] == "" ? tilde(f[13]) : f[15]), f[14]) }
    for (i = 1; i <= nh; i++) { split(hg[i], f, "\t"); row(f[2], f[9], "hog", f[5], f[7], f[4], f[11], f[3]) }
}
