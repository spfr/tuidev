# lib/agents/awk/hook_claude.awk — _agents_hook_claude: the nearest ancestor
# of this process that is a claude agent. Needs lib_proc.

NF >= 14 { p = $1 + 0; pp[p] = $2 + 0; av[p] = argv($0) }
END {
    q = pp[self + 0]; d = 0
    while (q > 1 && (q in pp) && d++ < 64) { if (agent_kind(av[q]) == "claude") { print q; exit } q = pp[q] }
}
