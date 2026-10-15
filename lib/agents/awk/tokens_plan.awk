# lib/agents/awk/tokens_plan.awk — _agents_tokens_scan's plan: the
# transcripts on stdin (_agents_tokens_list: "@claude" or "@codex", then
# "inode<TAB>size<TAB>mtime<TAB>path" lines) against tokens.state (sf;
# tokens.sh documents both). One line per transcript, every field set ("-"
# when unknown):
#   work cli path inode size mtime offset last_epoch last_id session project agent model pending
# work: 1 when it has bytes not read yet. A transcript with another inode,
# or shorter than its offset, starts again from 0 and keeps last_epoch, so
# only newer rows count; one no longer listed (gone, or older than the
# window) is forgotten.

function dash(s) { return s == "" ? "-" : s }
BEGIN {
    while ((getline line < sf) > 0) if (split(line, f, "\t") >= 11) st[f[1]] = line
    close(sf)
}
/^@/ { cli = substr($0, 2); next }
NF == 4 && $1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+$/ && $3 ~ /^[0-9]+$/ && $4 ~ /^\// && !($4 in seen) {
    seen[$4] = 1
    off = 0; le = 0; lid = "-"; sess = "-"; proj = "-"; ag = "-"; mod = "-"; pend = "-"
    if (($4 in st) && split(st[$4], f, "\t") >= 11 && f[2] == cli) {
        le = f[5] + 0; sess = dash(f[7]); proj = dash(f[8]); ag = dash(f[9]); mod = dash(f[10])
        if (f[3] == $1 && f[4] ~ /^[0-9]+$/ && f[4] + 0 <= $2 + 0) { off = f[4]; lid = dash(f[6]); pend = dash(f[11]) }
    }
    print ($2 + 0 > off + 0 ? 1 : 0), cli, $4, $1, $2, $3, off, le, lid, sess, proj, ag, mod, pend
}
