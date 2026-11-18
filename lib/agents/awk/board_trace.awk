# lib/agents/awk/board_trace.awk — `agents board`'s Trace: what a session did,
# one line an event, from the trace jq's lines (board.sh:
# _AGENTS_BOARD_TRACE_JQ), "HH:MM<TAB>KIND<TAB>TEXT<TAB>NOTE<TAB>COUNT":
#   14:02  you     fix the flaky cache test
#   14:03  edit    cache.ts, cache.test.ts
#   14:05  run     pnpm test cache                   exit 1
# The text is cut to the pane's width (-v W=); a note (a failed command's
# exit code, a denial) and a count of repeats ("x3") follow it. The text is
# a transcript's, so untrusted: lib_maprows' clean takes out what the jq left
# (C1 controls, bidi and line separators). ENVIRON: the colors (B DIM NEED
# DONE RUN WARN ACC N), AGENTS_ASCII. Needs lib_fmt and lib_maprows.

function kcolor(k) {
    return k == "you" ? ACC B : k == "ask" ? NEED B : k == "denied" || k == "stop" ? WARN : k == "agent" ? RUN : k == "edit" ? DONE : ""
}

BEGIN {
    B = ENVIRON["B"]; DIM = ENVIRON["DIM"]; NEED = ENVIRON["NEED"]; DONE = ENVIRON["DONE"]; RUN = ENVIRON["RUN"]
    WARN = ENVIRON["WARN"]; ACC = ENVIRON["ACC"]; N = ENVIRON["N"]
    times = (ENVIRON["AGENTS_ASCII"] != "") ? "x" : "\303\227"
    if (W + 0 < 30) W = 30
}
NF >= 5 && $1 ~ /^([0-9][0-9]:[0-9][0-9]|--:--)$/ && $2 ~ /^[a-z]+$/ {
    note = ($4 == "-") ? "" : substr(clean($4), 1, 12)
    more = ($5 ~ /^[0-9]+$/ && $5 + 0 > 1) ? " " times $5 : ""
    # "  HH:MM  kind    " is 17 columns; the note takes its own and a space.
    tw = W - 17 - 1 - (note == "" ? 0 : length(note) + 2) - dw(more)
    if (tw < 8) tw = 8
    text = dcut(clean($3), tw)
    printf "  %s%s%s  %s%-6s%s  %s%s%s", DIM, $1, N, kcolor($2), $2, N, text, DIM more, N
    if (note != "") printf "%s  %s%s%s", lc("", tw - dw(text)), (note ~ /^exit 0$/ ? DIM : WARN), note, N
    printf "\n"
}
