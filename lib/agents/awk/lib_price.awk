# lib/agents/awk/lib_price.awk — API list prices: reading the price files,
# which line prices a model, and what tokens cost at it (report_tokens and
# tokens_session). Needs nothing.
#
# A price file (lib/agents/prices.tsv, which ships, then yours:
# AGENTS_PRICES), USD per million tokens, one model per line, # comments:
#   MODEL_PREFIX IN CACHE_WRITE_5M CACHE_WRITE_1H CACHE_READ OUT
# or, as written before 1h cache writes were counted apart,
#   MODEL_PREFIX IN CACHE_WRITE CACHE_READ OUT
# (its one cache-write price then for both). A "# as of DATE" line says when
# the prices were checked.

# prices_load FILES — the prices in FILES ("|"-separated, read in order): PN
# of them, PP[i] the prefix, Pin P5 P1 Pcr Pout per million tokens; PRICED
# when there is one; PASOF the first "as of" date. A malformed line is
# reported and ignored.
function prices_load(files,   nf, fl, i, pf, ln, f, n, nr) {
    PN = 0; PRICED = 0; PASOF = ""
    nf = split(files, fl, "|")
    for (i = 1; i <= nf; i++) {
        pf = fl[i]; nr = 0
        if (pf == "") continue
        while ((getline ln < pf) > 0) {
            nr++
            if (PASOF == "" && match(ln, /^#[ \t]*as of [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/)) PASOF = substr(ln, RLENGTH - 9, 10)
            sub(/[ \t]+#.*$/, "", ln); sub(/^[ \t]+/, "", ln); sub(/[ \t\r]+$/, "", ln)
            if (ln == "" || ln ~ /^#/) continue
            n = split(ln, f, /[ \t]+/)
            if ((n != 5 && n != 6) || f[1] !~ /^[A-Za-z0-9][A-Za-z0-9._:\/@+-]*$/ || !usdnum(f[2]) || !usdnum(f[3]) || !usdnum(f[4]) \
                || !usdnum(f[5]) || (n == 6 && !usdnum(f[6]))) {
                printf "agents: %s:%d: not MODEL_PREFIX IN CACHE_WRITE_5M CACHE_WRITE_1H CACHE_READ OUT (USD per million tokens), ignored\n", pf, nr > "/dev/stderr"
                continue
            }
            PN++; PP[PN] = f[1]; Pin[PN] = f[2] + 0; P5[PN] = f[3] + 0
            if (n == 6) { P1[PN] = f[4] + 0; Pcr[PN] = f[5] + 0; Pout[PN] = f[6] + 0 }
            else { P1[PN] = f[3] + 0; Pcr[PN] = f[4] + 0; Pout[PN] = f[5] + 0 }
        }
        close(pf)
    }
    PRICED = PN > 0
}
function usdnum(s) { return s ~ /^[0-9]+([.][0-9]+)?$/ || s ~ /^[.][0-9]+$/ }

# price_of MODEL — the index of its price, 0 for none: of the lines whose
# prefix names it (pnames), the longest; of two as long, the later.
function price_of(m,   k, i, best, bl) {
    if (m in PMx) return PMx[m]
    k = m
    while (k ~ /^[^\/]+\//) sub(/^[^\/]+\//, "", k)     # openai/, openrouter/anthropic/
    sub(/^([a-z]+[.])?anthropic[.]/, "", k)             # us.anthropic., anthropic.
    best = 0; bl = 0
    for (i = 1; i <= PN; i++) if (length(PP[i]) >= bl && pnames(PP[i], k)) { best = i; bl = length(PP[i]) }
    PMx[m] = best
    return best
}
# pnames PREFIX MODEL — does PREFIX name MODEL? It starts it, and what
# follows is a version boundary: nothing, dates (-20251001, -2025-10-01),
# version tags (-v1, -latest), then nothing or [..., @..., :...; or PREFIX
# ends in - or . (a family).
function pnames(p, m,   r) {
    if (substr(m, 1, length(p)) != p) return 0
    if (p ~ /[-.]$/) return 1
    r = substr(m, length(p) + 1)
    while (r != "") {
        if (r ~ /^-[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]/) r = substr(r, 10)
        else if (r ~ /^-[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/) r = substr(r, 12)
        else if (r ~ /^-v[0-9]/) { sub(/^-v[0-9]+/, "", r) }
        else if (r ~ /^-latest/) r = substr(r, 8)
        else return r ~ /^[@:]/ || substr(r, 1, 1) == "["
    }
    return 1
}
# usd_of P IN CW CW1H CR OUT — what the tokens cost at price P, in USD (CW:
# every cache write, CW1H those of them cached for an hour).
function usd_of(p, i, cw, w1, cr, o) {
    return (i * Pin[p] + (cw - w1) * P5[p] + w1 * P1[p] + cr * Pcr[p] + o * Pout[p]) / 1e6
}
