# lib/agents/awk/tokens_plan.awk — _agents_tokens_scan's plan: the
# transcripts on stdin (_agents_tokens_list: "@claude" or "@codex", then
# "inode<TAB>size<TAB>mtime<TAB>path" lines) against tokens.state (sf;
# tokens.sh documents both). One line per transcript, every field set ("-"
# when unknown):
#   work cli path inode size mtime offset last_epoch last_id session project agent model pending fork
# work: 1 when it has bytes not read yet. A transcript with another inode,
# or shorter than its offset, starts again from 0 and keeps last_epoch and
# last_id, so only newer rows count. One not listed this time (gone, out of
# the window, or under a CLAUDE_CONFIG_DIR or CODEX_HOME not set this time)
# keeps its state line, as work 0, until its last_epoch is older than cut
# (AGENTS_HISTORY_DAYS ago): listed again, it goes on from its offset, and a
# row it holds is never counted twice.

function dash(s) { return s == "" ? "-" : s }
BEGIN {
    while ((getline line < sf) > 0) if (split(line, f, "\t") >= 11 && !(f[1] in st)) { st[f[1]] = line; so[++sn] = f[1] }
    close(sf)
}
/^@/ { cli = substr($0, 2); next }
NF == 4 && $1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+$/ && $3 ~ /^[0-9]+$/ && $4 ~ /^\// && !($4 in seen) {
    seen[$4] = 1
    off = 0; le = 0; lid = "-"; sess = "-"; proj = "-"; ag = "-"; mod = "-"; pend = "-"; fk = "-"
    if (($4 in st) && split(st[$4], f, "\t") >= 11 && f[2] == cli) {
        le = f[5] + 0; lid = dash(f[6]); sess = dash(f[7]); proj = dash(f[8]); ag = dash(f[9]); mod = dash(f[10]); fk = dash(f[12])
        if (f[3] == $1 && f[4] ~ /^[0-9]+$/ && f[4] + 0 <= $2 + 0) { off = f[4]; pend = dash(f[11]) }
    }
    print ($2 + 0 > off + 0 ? 1 : 0), cli, $4, $1, $2, $3, off, le, lid, sess, proj, ag, mod, pend, fk
}
# Carried: as it was, size its offset and mtime 0 (sorted last), never read.
END {
    for (i = 1; i <= sn; i++) {
        p = so[i]
        if (p in seen) continue
        n = split(st[p], f, "\t")
        if (f[2] !~ /^(claude|codex)$/ || f[3] !~ /^[0-9]+$/ || f[4] !~ /^[0-9]+$/ || f[5] + 0 < cut + 0) continue
        print 0, f[2], p, f[3], f[4], 0, f[4], f[5] + 0, dash(f[6]), dash(f[7]), dash(f[8]), dash(f[9]), dash(f[10]), dash(f[11]), dash(n >= 12 ? f[12] : "")
    }
}
