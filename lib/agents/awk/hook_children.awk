# lib/agents/awk/hook_children.awk — _agents_hook_children: the direct
# children of claude c, leaving out this process's own ancestors (the hook's
# shell). Needs lib_proc.

NF >= 14 { p = $1 + 0; pp[p] = $2 + 0; ord[++n] = p }
END {
    ancestors(self)
    for (k = 1; k <= n; k++) if (pp[ord[k]] == c + 0 && !anc[ord[k]]) print ord[k]
}
