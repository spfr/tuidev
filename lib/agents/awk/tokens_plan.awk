# lib/agents/awk/tokens_plan.awk — _agents_tokens_scan's plan: the
# transcripts on stdin (_agents_tokens_list: "@claude" or "@codex", then
# "inode<TAB>size<TAB>mtime<TAB>path" lines) against the state: tokens.state
# (sf, the cold lines) and tokens.hot (hf, the hot ones, which win; tokens.sh
# documents both). One line per transcript the scan must handle, every field
# set ("-" when unknown):
#   work cli path inode size mtime offset last_epoch last_id session project agent model pending fork origin
# work: 1 when it has bytes not read yet. A transcript with another inode,
# or shorter than its offset, starts again from 0 and keeps last_epoch and
# last_id, so only newer rows count. A transcript with nothing new is left
# out when its line is cold (it stays in tokens.state as it is), and kept,
# as work 0, when it is hot (tokens.hot is written whole). One not listed
# this time (gone, out of the window, or under a CLAUDE_CONFIG_DIR or
# CODEX_HOME not set this time) keeps its line: a hot one is carried, as
# work 0, until its last_epoch is older than cut (AGENTS_HISTORY_DAYS ago);
# listed again, it goes on from its offset, and a row it holds is never
# counted twice.

function dash(s) { return s == "" ? "-" : s }
# load(FILE, HOT) — FILE's state lines into st[], first line of a path wins
# within a file; a hot line replaces a cold one.
function load(file, hot,   line, f, n, seen) {
    while ((getline line < file) > 0) {
        if ((n = split(line, f, "\t")) < 11 || (f[1] in seen)) continue
        seen[f[1]] = 1
        if (!(f[1] in st)) so[++sn] = f[1]
        st[f[1]] = line
        if (hot) ishot[f[1]] = 1
    }
    close(file)
}
BEGIN { load(sf, 0); load(hf, 1) }
/^@/ { cli = substr($0, 2); next }
NF == 4 && $1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+$/ && $3 ~ /^[0-9]+$/ && $4 ~ /^\// && !($4 in seen) {
    seen[$4] = 1
    off = 0; le = 0; lid = "-"; sess = "-"; proj = "-"; ag = "-"; mod = "-"; pend = "-"; fk = "-"; org = "-"
    if (($4 in st) && (n = split(st[$4], f, "\t")) >= 11 && f[2] == cli) {
        le = f[5] + 0; lid = dash(f[6]); sess = dash(f[7]); proj = dash(f[8]); ag = dash(f[9]); mod = dash(f[10])
        fk = dash(n >= 12 ? f[12] : ""); org = dash(n >= 13 ? f[13] : "")
        if (f[3] == $1 && f[4] ~ /^[0-9]+$/ && f[4] + 0 <= $2 + 0) { off = f[4]; pend = dash(f[11]) }
    }
    work = $2 + 0 > off + 0 ? 1 : 0
    if (work || ($4 in ishot)) print work, cli, $4, $1, $2, $3, off, le, lid, sess, proj, ag, mod, pend, fk, org
}
# Carried: a hot line as it was, size its offset and mtime 0 (sorted last),
# never read.
END {
    for (i = 1; i <= sn; i++) {
        p = so[i]
        if ((p in seen) || !(p in ishot)) continue
        n = split(st[p], f, "\t")
        if (f[2] !~ /^(claude|codex)$/ || f[3] !~ /^[0-9]+$/ || f[4] !~ /^[0-9]+$/ || f[5] + 0 < cut + 0) continue
        print 0, f[2], p, f[3], f[4], 0, f[4], f[5] + 0, dash(f[6]), dash(f[7]), dash(f[8]), dash(f[9]), dash(f[10]), dash(f[11]), \
            dash(n >= 12 ? f[12] : ""), dash(n >= 13 ? f[13] : "")
    }
}
