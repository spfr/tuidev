# lib/agents/awk/mem_view.awk — `agents mem`: memory and swap as bars, the
# guard, and the processes holding the most, each on a bar that ends at the
# guard's stop size, with its warning drawn on it: how far from being stopped is
# what you read a footprint for.
# Stdin, biggest first: pid footprint_kib rss_kib what project session.
# Variables: total free level su stot ("-" when unknown), gstate gpid gmode
# stops (the guard), warn stop (KiB), high (the swap % that is high); ENVIRON W
# and the colors. Needs lib_fmt.

function bar_line(tag, p, c, rest) { print B lc(tag, 8) e gauge(p, BAR, -1, c, DIM, "") "  " rest }
function gb(k) { return sprintf("%.1fG", k / 1048576) }
function head_memory(   p, c, t) {
    if (free !~ /^[0-9]+$/) { print B "MEMORY" e "  pressure " level; return }
    p = 100 - free
    c = level == "critical" ? NEED : level == "warn" ? WARN : RUN
    t = p "%" (narrow ? "" : " used")
    if (total ~ /^[0-9]+$/ && total + 0 > 0) t = t " of " gb(total)
    # Short of room, the pressure only when it says something.
    if (level == "critical") t = t " " gl("dot") " " NEED B "pressure critical" e
    else if (level == "warn") t = t " " gl("dot") " " WARN "pressure warn" e
    else if (!narrow) t = t " " gl("dot") " pressure " level
    bar_line("MEMORY", p, c, t)
}
function head_swap(   p, hi) {
    if (su !~ /^[0-9]+$/ || stot !~ /^[0-9]+$/ || stot + 0 <= 0) return
    p = 100 * su / stot; hi = p >= high
    bar_line("SWAP", p, hi ? WARN : RUN, (hi ? WARN "! " : "") sprintf("%.1f of %s", su / 1048576, gb(stot)) (hi ? e : ""))
}
function head_guard(   t) {
    t = gstate == "on" ? "running (pid " gpid ")" : gstate == "stopped" ? WARN "not running" e " (agents mem restart)" : gstate == "off" ? "off (AGENTS_MEM_GUARD=off)" : "not running (run \"agents mem guard\" in a tmux pane)"
    # Its sizes are over the table's bars.
    if (gstate != "off") t = t " " gl("dot") " " gmode
    if (stops + 0 > 0) t = t " " gl("dot") " " stops " " (stops == 1 ? "stop" : "stops") " in 7 days"
    print B lc("GUARD", 8) e t
}
# table_head — the column titles, the guard's two sizes above where the bar
# reaches them.
function table_head(   m, s, l, w) {
    m = warn < stop ? int(warn * CELLS / stop + 0.5) : -1
    s = "PID     " rc("FOOTPRINT", 9) "  "
    l = "stop " sprintf("%.0fG", stop / 1048576)
    if (m >= 0 && m + 1 + 2 + dw(l) <= CELLS + 1) {
        w = "warn " sprintf("%.0fG", warn / 1048576)
        s = s rc(w, m + 1) rc(l, CELLS - m)
    } else s = s rc(l, CELLS + 1)
    print DIM s "  PROCESS" e
}
BEGIN {
    B = ENVIRON["B"]; DIM = ENVIRON["DIM"]; NEED = ENVIRON["NEED"]; WARN = ENVIRON["WARN"]; RUN = ENVIRON["RUN"]; ACC = ENVIRON["ACC"]; e = ENVIRON["N"]
    W = ENVIRON["W"] + 0; narrow = W < 72; CELLS = narrow ? 12 : 24; BAR = narrow ? 18 : 30
    warn += 0; stop += 0; high += 0
    head_memory(); head_swap(); head_guard()
    print ""
    table_head()
}
{
    fp = $2 + 0; c = fp >= stop ? NEED : fp >= warn ? WARN : RUN
    what = $4
    if ($5 != "-") what = what " " gl("dot") " " $5
    if ($6 != "-") what = what " " gl("dot") " " $6
    what = what " " gl("dot") " rss " mem($3 + 0)
    print lc($1, 7) " " (c == RUN ? "" : c (fp >= stop ? B : "")) rc(gb(fp), 9) (c == RUN ? "" : e) "  " \
        gauge(stop > 0 ? 100 * fp / stop : 0, CELLS, warn < stop ? 100 * warn / stop : -1, c, DIM, ACC) "  " dcut(what, W - CELLS - 22 < 12 ? 12 : W - CELLS - 22)
}
