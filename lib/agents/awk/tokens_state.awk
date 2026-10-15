# lib/agents/awk/tokens_state.awk — _agents_tokens_compact: the scan state
# (tokens.sh documents it) made cold again. Reads tokens.state (sf) and
# tokens.hot (hf), whose line for a path wins; writes so, every line
# (tokens.state.new), and ho, the lines whose last_epoch is hot or later
# (tokens.hot.new); a line whose last_epoch is before cut (0: none) goes.
# Runs in BEGIN: it reads no input.

function load(file,   line, f, seen) {
    while ((getline line < file) > 0) {
        if (split(line, f, "\t") < 11 || f[1] == "" || (f[1] in seen)) continue
        seen[f[1]] = 1
        if (!(f[1] in st)) o[++n] = f[1]
        st[f[1]] = line; ep[f[1]] = f[5] + 0
    }
    close(file)
}
BEGIN {
    load(sf); load(hf)
    printf "" > so; printf "" > ho
    for (i = 1; i <= n; i++) {
        p = o[i]
        if (cut + 0 > 0 && ep[p] < cut + 0) continue
        print st[p] > so
        if (ep[p] >= hot + 0) print st[p] > ho
    }
    close(so); close(ho)
}
