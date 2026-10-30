# shellcheck shell=bash
# lib/agents/classify.sh — what each process is.
#
# Owns: agents_classify (one awk pass over a snapshot: agent trees, stale
#   helpers, dev-server candidates, hogs, what each session runs, jobs) and
#   agents_enrich (cwds, Herdr status, projects, flags), and the rule for a
#   session's project name.
# Uses: config.sh (the patterns), util.sh (_agents_awk, _agents_now), mcp.sh
#   (_agents_mcp_needles: which MCP server is which); awk/classify.awk,
#   awk/enrich.awk and the lib_*.awk they need.
# Public: agents_classify, agents_enrich, agents_project.

# agents_classify LISTENERS KEEP_PIDS [PANES] < SNAPSHOT
# LISTENERS: "pid port" lines. KEEP_PIDS: pids never flagged (our own
# keep-awake holder). Prints tab-separated records, 14 columns:
#   type pid kind age_s cpu avg rss_kib kids start ports user herdr cwd args
# type is agent | stale | cand (a dev-server candidate agents_enrich confirms
# by cwd) | hog (CPU, or an RSS past AGENTS_MEM_WARN GB, listed first). Unknown fields are "-". Plus "watch PID PATH read|exists"
# records: the file a polling loop waits on, and whether its condition reads
# it or only tests that it exists (agents_collect checks its age,
# agents_enrich drops them), "where PID tmux|herdr|ssh|app|- PLACE" records
# for each session (awk/lib_where.awk; PANES: tmux's "pane_pid<TAB>
# session:window.pane" lines, where.sh), and "job" records (awk/lib_jobs.awk).
agents_classify() {
    local mcp
    _agents_mcp_needles mcp     # which configured MCP server each process is
    local IFS=$'\n'
    AGENTS_MCP="$mcp" AGENTS_PANES="${3:-}" AGENTS_LISTEN="$1" AGENTS_KEEP="$2" AGENTS_PATTERNS="${AGENTS_ORPHAN_PATTERNS[*]}" \
    AGENTS_UID="$AGENTS_UID" AGENTS_SELF="$AGENTS_SELF" AGENTS_NAMES="$AGENTS_NAMES" \
    AGENTS_DAEMON="$AGENTS_DAEMON_PATTERN" AGENTS_SYSTEM="$AGENTS_SYSTEM_PATTERN" \
    AGENTS_HOG_PCT="$AGENTS_HOG_PCT" AGENTS_HOG_MIN="$AGENTS_HOG_MIN" \
    AGENTS_HOG_NOW="$AGENTS_HOG_NOW" AGENTS_HOG_TOP="$AGENTS_HOG_TOP" AGENTS_BAR_TOP="$AGENTS_BAR_TOP" \
    AGENTS_MEM_WARN_KIB=$((AGENTS_MEM_WARN * 1048576)) \
    _agents_awk "lib_proc lib_activity lib_jobs lib_where classify"
}

# Where a dev server's cwd must be for it to count as one an agent left: a
# directory under $HOME (not ~/Library), $TMPDIR, or Claude Code's per-user
# temp dir (/private/tmp/claude-UID, its sandbox scratchpads).
_agents_cwd_roots() {
    local t="${TMPDIR:-}"
    t="${t%/}"
    printf '%s/\n' "$HOME"
    if [[ -n "$t" ]]; then
        printf '%s/\n' "$t"
        [[ "$t" == /var/* || "$t" == /tmp/* ]] && printf '/private%s/\n' "$t"
    fi
    printf '/private/tmp/claude-%s/\n/tmp/claude-%s/\n' "$AGENTS_UID" "$AGENTS_UID"
}

# agents_project CWD — the short name a session goes by: the directory's name,
# or REPO/NAME for a worktree under REPO/.claude/worktrees/NAME; "~" for $HOME;
# never a control character. The one rule, awk/lib_proc.awk's projname, which
# agents_enrich applies to every record.
agents_project() {
    _AGENTS_CWD="$1" HOME="$HOME" _agents_awk_eval lib_proc 'BEGIN { print projname(ENVIRON["_AGENTS_CWD"]) }'
}

# agents_enrich CWDS HERDR [WATCHED [PANES]] < RECORDS — fill in cwd
# ("pid<TAB>cwd" lines, or _agents_cwds --stdout's, whose "pid<TAB>path<TAB>1"
# lines it skips) and Herdr status (_agents_herdr's "kind<TAB>status<TAB>cwd
# [<TAB>pane<TAB>title[<TAB>session]]" lines), and append column 15, the
# project name (agents_project). A session's Herdr agent is the one of its
# kind in its pane (PANES: _agents_pane_env's "pid<TAB>pane" lines), else the
# only one of its kind in its directory that no session claimed by pane;
# each match also adds a "herdr PID PANE TITLE" record ("-" for unknown)
# after the agent rows. Then one "ident PID PANE SESSION" record per agent
# row, the key other tools join on: its Herdr pane and its CLI session id
# (Claude Code's sessions/PID.json, else Herdr's, else a --resume on its
# command line), "-" for unknown. A dev-server candidate is kept, as stale,
# only when its cwd is under one of _agents_cwd_roots. Agent rows come first,
# ordered by what needs you: blocked, working, idle/done, unknown, the daemon;
# then activity rows, where column 15 is the origin (main, or the worktree a
# subagent runs in), 16 the flags (dup, long, hot, wait, stuck) and 17 how
# many copies of that command run in the same directory (in the session, or
# any session). A tool's cwd is where it cd's to first, if it does. WATCHED:
# "pid<TAB>quiet|fresh" for polling loops whose watched file exists
# (_agents_watched).
agents_enrich() {
    local now cdir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
    _agents_now now
    AGENTS_CLAUDE_DIR="$cdir" AGENTS_ENRICH_NOW="$now" \
    AGENTS_CWDS="$1" AGENTS_HERDR="$2" AGENTS_WATCHED="${3:-}" AGENTS_HPANES="${4:-}" AGENTS_CWD_ROOTS="$(_agents_cwd_roots)" HOME="$HOME" \
    AGENTS_TOOL_LONG="$AGENTS_TOOL_LONG" AGENTS_HOG_NOW="$AGENTS_HOG_NOW" AGENTS_WAIT_STUCK="$AGENTS_WAIT_STUCK" \
    _agents_awk "lib_proc lib_activity enrich" -F '\t' -v OFS='\t'
}
