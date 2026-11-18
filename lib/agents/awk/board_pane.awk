# lib/agents/awk/board_pane.awk — `agents board`: the end of a session's pane
# as its last lines of output. Plain text in (board.sh: _agents_board_pane),
# the last n lines out, each under two spaces.
#
# A pane ends in the agent's own screen furniture, which says nothing about
# what it did: Claude Code's input box (a rule, the prompt, a rule) with its
# status lines under it, Codex's prompt and footer. From the box on, it is
# left out, and so are the empty lines and rules before it. A rule anywhere
# else is cut to the width there is (-v W=), so it never wraps.
# The indent all its lines share goes too, and the line `agents peek` leads
# with. Variables: n (lines), W (columns; 0: no cut). Needs lib_fmt (dw, dcut).

# A rule: at least 8 rule characters (box-drawing horizontals, corners and
# joints, - _ =) and little else: Claude Code writes a session's name into
# the rule over its input box.
function isrule(s,   i, n, c, r, o) {
    n = length(s); r = 0; o = 0
    for (i = 1; i <= n; i++) {
        c = substr(s, i, 1)
        if (substr(s, i, 3) in rch) { r++; i += 2 }
        else if (c == "-" || c == "_" || c == "=") r++
        else if (c != " " && c != "\t" && (c < "\200" || c >= "\300")) o++
    }
    return r >= 8 && o * 3 <= r
}
# The mark an agent's prompt starts with: Claude Code's, Codex's.
function pmark(s) { s = substr(s, 1, 3); return s == "\342\235\257" || s == "\342\200\272" || s == "\342\226\214" }
# Where an agent takes what you type: such a mark, or a ">" alone, in a box
# or not.
function isprompt(s) {
    sub(/^[ \t]+/, "", s)
    if (substr(s, 1, 3) == "\342\224\202") { s = substr(s, 4); sub(/^[ \t]+/, "", s) }
    return pmark(s) || s == ">" || s ~ /^>[ \t]/
}
BEGIN {
    k = split("\342\224\200 \342\224\201 \342\224\204 \342\224\205 \342\224\210 \342\224\211 \342\225\220 \342\225\214 \342\225\215 \342\225\255 \342\225\256 \342\225\257 \342\225\260 " \
        "\342\224\214 \342\224\220 \342\224\224 \342\224\230 \342\224\234 \342\224\244 \342\224\254 \342\224\264 \342\224\274", rc_, " ")
    for (i = 1; i <= k; i++) rch[rc_[i]] = 1
}
{ sub(/[ \t]+$/, "") }
$0 == "" { blank++; next }
# The line `agents peek` leads with, naming the pane: the card says whose it is.
!m && /^\342\224\200\342\224\200 .* \342\224\200\342\224\200$/ { blank = 0; next }
{ if (m && blank) l[++m] = ""; blank = 0; l[++m] = $0 }
END {
    end = m
    # The input box: the first rule among the last lines with a prompt right
    # under it. Without a rule (Codex), a prompt at the very end.
    for (i = (m > 16 ? m - 15 : 1); i <= m && end == m; i++)
        if (isrule(l[i])) for (j = i + 1; j <= i + 2 && j <= m; j++) if (isprompt(l[j])) { end = i - 1; break }
    if (end == m) for (i = (m > 5 ? m - 4 : 1); i <= m; i++) if (pmark(l[i])) { end = i - 1; break }
    while (end > 0 && (l[end] == "" || isrule(l[end]))) end--
    # Nothing but the box: the screen as it is.
    if (end == 0) end = m
    # What every line is indented by goes: a break then lands under its line.
    first = (end > n ? end - n + 1 : 1); ind = -1
    for (i = first; i <= end; i++) if (l[i] != "") {
        match(l[i], /^ */)
        if (ind < 0 || RLENGTH < ind) ind = RLENGTH
    }
    for (i = first; i <= end; i++) {
        s = substr(l[i], ind + 1)
        print "  " ((W > 10 && isrule(s)) ? dcut(s, W - 4) : s)
    }
}
