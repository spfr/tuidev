# shellcheck shell=bash
# lib/agents/usage.sh — `agents --help`.
#
# Uses: config.sh (the settings it quotes).
# Public: agents_usage.

agents_usage() {
    cat <<EOF
agents — see and control local agentic-coding processes (claude, codex)

LOOK
  agents [ls]                  sessions (blocked first), then stale processes and
                               hogs when there are any, then system status
  agents watch [SECS]          the same, redrawn every SECS (default 2); q quits
  agents ps [PID]              everything a session runs: MCP servers, each command
                               (tool shell) with its origin (main or a worktree
                               subagent) and flags (dup, long, hot, wait, stuck), nested
                               sessions; all sessions without PID
  agents stale                 only stale processes: orphaned MCP servers, npx
                               helpers, caffeinate, dev servers (ppid 1)
  agents hogs                  top $AGENTS_HOG_TOP CPU hogs, any owner: lifetime average
                               >= ${AGENTS_HOG_PCT}% after ${AGENTS_HOG_MIN}m, or >= ${AGENTS_HOG_NOW}% now outside agent trees
  agents thermal               thermal pressure and energy mode (display only)
  agents show [--json] [--watch] PID[@START]
                               one process in detail: what and whose it is, its
                               verdict, session (id, model, what it is doing now),
                               where it lives (tmux, Herdr, terminal), CPU, memory,
                               threads, ports, files, children; --watch redraws
  agents pick                  browse it all in fzf: the preview is agents show;
                               enter jumps, ctrl-p peeks, ctrl-d details, ctrl-k kills
  agents jump [--notify] PID[@START]
                               go to where it runs: its Herdr or tmux pane, then the
                               terminal tab that shows it (Ghostty, iTerm, Terminal)
  agents root-of PID           the agent session PID runs under, as PID@START, with
                               the terminal app that shows it, its bundle id and the
                               command that jumps there (notify.sh: a banner's click)
  agents peek PID[@START] [LINES]
                               the last LINES (40) lines of its tmux or Herdr pane
  agents mcp [DIR]             the MCP servers Claude Code and Codex are configured
                               with (all, or those a session in DIR loads): name,
                               scope, copies running now (one per session) and
                               their memory, what starts it, where; processes go
                               by these names (never shows args, env, headers or URLs)
  agents mcp lazy|eager NAME...|--all
                               lazy: put mcp-lazy in front of a stdio server in Claude
                               Code's and Codex's configs, so a session starts it on
                               its first tool call, not with the session; eager: back
  agents json | tsv            machine-readable snapshot (tsv feeds SwiftBar)
  agents why [--copy] PID[@START]
                               why an item is listed, the evidence (owner, age,
                               ports, the file a loop watches and its last line)
                               and a verdict: safe to stop, check first, leave
                               it, informational; --copy puts it on the clipboard

HISTORY (local, names only; AGENTS_HISTORY=0 records nothing)
  agents report [--view VIEW] [--since 24h|7d|30d|today] [--json]
                               where the CPU went: CPU-hours by job (test, build,
                               server, browser, mcp, agent, wait, other), project,
                               session and hour, what was cleaned up, and the top
                               insights from the runs (default 24h). VIEW: runs
                               (repeated and slowest commands), waste (duplicates,
                               leaks, polling, failed re-runs), trends (against the
                               window before; default 7d), agents (by agent type),
                               tokens (by model, CLI, agent type, project, session
                               and origin; cache hits, polling, compactions, Codex
                               plan headroom, and what they would cost at API list
                               prices), context (MCP servers, skills and subagents
                               used and loaded, plugins, what is unused; default
                               7d), denials (tool calls denied, by command, with
                               what to try)
  agents runs [--since 24h|7d|30d|today] [--json]
                               finished commands, newest first: when, how long, CPU,
                               peak memory, exit code, project, session, the agent
                               that started it, dup, and whether agents stopped it
  agents sample                record one sample; the menu bar and 'agents watch'
                               do it every minute (cron it where neither runs)

ACT
  agents kill [OPTS] PID...    SIGTERM the whole tree, descendants first, then
                               SIGKILL whatever is left after ${AGENTS_GRACE}s
  agents reap [OPTS]           kill every stale tree
    --stuck                    reap: also stop polling loops flagged stuck
    --auto                     reap without asking only what is safe to: stale
                               trees that listen on no port, loops stuck on a file
                               quiet for 2 x AGENTS_WAIT_STUCK (cron; the menu runs
                               it with AGENTS_AUTO_REAP=1)
  agents term [OPTS] PID...    SIGTERM one process (for hogs), not its tree
    -n, --dry-run              show what would be signalled
    -y, --yes                  don't ask (required when stdin is not a terminal)
    --confirm-gui              ask with a macOS dialog instead (Cancel is the default)
    --notify                   report the result as a macOS notification
    PID@START                  a PID with its start time (from json/tsv): refused if
                               the pid now names a different process
  agents cwd PID@START         that process's working directory (copy-path puts it
                               on the clipboard, reveal shows it in Finder)
  agents open-term [-n] [--hold] CMD...
                               run 'agents CMD' in a new window of your terminal
                               (AGENTS_TERMINAL); -n prints the command

KEEP AWAKE
  agents awake [status]        keep-awake state, and who else holds the Mac awake
  agents awake on [DURATION]   hold system and display awake (30m, 2h, 1h30m);
                               no DURATION = until 'agents awake off'
  agents awake agents          hold while any claude/codex runs, then release
  agents awake lid DURATION    macOS: also keep awake with the lid closed, for at
                               most AGENTS_LID_MAX ($AGENTS_LID_MAX). Asks for an admin
                               password each time; a root guard restores lid sleep
                               when DURATION ends, below ${AGENTS_LID_MIN_BATTERY}% battery off AC,
                               or when thermal pressure reaches heavy
  agents awake off             release (ends lid mode too: one more password)
  agents awake restore         let a closed lid sleep again (pmset disablesleep 0),
                               e.g. after a reboot killed the guard
    --notify                   report lid mode's results as macOS notifications

CLAUDE CODE HOOKS (shipped in ~/.claude/settings.json; hook JSON on stdin)
  agents hook subagent-stop    stop the background commands a subagent left
                               running once it handed back its final report
  agents hook session-end      on /clear or /resume: stop the session's polling
                               loops and what its finished subagents left
    -n, --dry-run              print what it would stop (or AGENTS_DRY_RUN=true)
  Only tasks matched to their own process (its stdout is the task's output
  file) under the claude that runs the hook. AGENTS_HOOK_REAP=0 turns it off;
  AGENTS_HOOK_LOG=1 logs each run to $AGENTS_DATA_DIR/hooks.log

SETTINGS
  agents config [--edit]       effective settings, and the file they came from;
                               --edit opens the file in your text editor
  $AGENTS_CONF (KEY=value; AGENTS_CONF picks another file). Keys: AGENTS_HOG_PCT
  AGENTS_HOG_MIN AGENTS_HOG_NOW AGENTS_HOG_TOP AGENTS_GRACE AGENTS_AWAKE_POLL
  AGENTS_TOOL_LONG AGENTS_LS_TOOLS AGENTS_WAIT_STUCK AGENTS_NAMES AGENTS_NO_HERDR
  AGENTS_TERMINAL AGENTS_LID AGENTS_LID_MAX AGENTS_LID_MIN_BATTERY, and the menu
  bar's AGENTS_BAR_TITLE
  AGENTS_BAR_SECTIONS AGENTS_BAR_ICON AGENTS_BAR_TOP AGENTS_BAR_REFRESH. The same
  names in the environment win. NO_COLOR=1 turns colors off. Stale patterns:
  AGENTS_ORPHAN_PATTERNS in $_AGENTS_LIB/config.sh. History: AGENTS_HISTORY
  AGENTS_HISTORY_DAYS AGENTS_PRICES; extra job patterns (EREs): AGENTS_JOB_TEST
  AGENTS_JOB_BUILD AGENTS_JOB_SERVER AGENTS_JOB_BROWSER AGENTS_JOB_MCP. Data:
  $AGENTS_DATA_DIR

SAFETY
  Never signals pid 1, this shell or its parents, another user's process
  (prints the sudo command instead), a system or session process (anything
  under /System/Library, /usr/libexec or /usr/sbin; loginwindow, Finder, Dock,
  WindowServer, your terminal), or a process hosting a shell or an agent below
  it. Refuses to run as root. Re-checks each process's start time before every
  signal. Never marks as stale anything that hosts a session (an agent, a
  shell, tmux/screen/zellij/herdr/pm2), a launchd job or a systemd service.
  Keep-awake uses caffeinate (macOS) or systemd-inhibit (Linux); a closed lid
  still sleeps unless the Mac is on AC with an external display (closed-display
  mode). Only 'awake lid' uses 'pmset disablesleep', after macOS's own admin
  dialog, time-boxed, with a root guard that restores it; no sudo rights are
  stored. 'agents' warns when sleep is disabled with no guard to restore it.
EOF
}
