# Agent Workflows

How to run AI coding agents with tuidev: one at a time, in parallel, across machines, and from your phone. The core install is CLI-agnostic. The CLI integrations are opt-in packs.

**Your editor is a GUI; the terminal runs agents.** Open a Ghostty tab, run `claude` or `codex` in it, and review the diff in VS Code or Cursor. tmux and Herdr are for sessions that must survive on an always-on node, not required for everyday work on your laptop.

## Control plane

A fleet of agents is an **attention queue**, not a wall of panes. Look at an agent only when it needs you.

| Need | Tool |
|------|------|
| A quick local session | A Ghostty tab: `claude` or `codex` |
| One durable task over SSH/mosh | **tmux** (`--pack tmux`): `t [NAME]` (prefix `Ctrl+a`) |
| Parallel agents on one repo | **Worktrees**: `claude -w NAME`, or a subagent with `isolation: worktree` |
| Sessions that keep running with the terminal closed | **Background sessions**: `claude --bg`, `claude agents` (see [below](#background-sessions)) |
| Many agents: which one is blocked? | **Herdr** (`--pack herdr`, prefix `Ctrl+b`) |
| Steer one agent from your phone | The CLI's native **remote control** |
| What is running, what leaked, what keeps the Mac awake? | **`agents`** (`--pack monitoring`), plus a SwiftBar menu on macOS (see [below](#local-processes-agents---pack-monitoring)) |

These tools don't replace each other. tmux doesn't know agent state, and Herdr doesn't replace a Ghostty tab. Work that must survive a laptop lid belongs on an always-on node (see [remote.md](remote.md)).

## Editor integration

Run the agent in a terminal tab next to your editor, not inside it:

- **Claude Code's `/ide` command** connects a running session to VS Code or Cursor: diffs and file selections show in the editor instead of the terminal. Run it from inside a `claude` session.
- **Codex's `file_opener` setting** (`configs/codex/config.toml`, shipped as `vscode`) controls which editor Codex links to when it prints a file reference. Alternatives are commented in the shipped config: `cursor`, `vscode-insiders`, `windsurf`, `none`.

## AI CLIs

| CLI | Pack | Shipped config (adopted, never overwritten) |
|-----|------|----------------------------------------------|
| Claude Code (primary) | `ai-clis` | `configs/claude/settings.json` (Linux: `settings.linux.json`) → `~/.claude/settings.json` |
| Codex (secondary) | `ai-clis` | `configs/codex/config.toml` → `~/.codex/config.toml` |

The packs install configs, not the CLIs. The CLIs update themselves. Claude Code and Codex run as plain `claude` and `codex`, sandboxed by the native settings each CLI ships with — see [sandboxing.md](sandboxing.md). Gemini CLI is deprecated upstream (its successor is Antigravity, `agy`) and isn't shipped. To use it, add your own wrapper in `~/.zshrc.local`.

**Shipped Claude Code policy:**

- Permissions: read-only commands are allowed (`gh pr view/list`, `gh run view/list`, `rg`, `jq`, `shellcheck`). `git add`, `commit`, `push`, `merge` and `tag`, and `gh pr create`, `gh pr merge`, `gh release` and `gh api` always ask. Credential paths and `.env*` are denied.
- `sandbox.enabled` is `true`: Claude Code's native sandbox confines the Bash tool and its children by default. See [sandboxing.md](sandboxing.md) for what it confines and how to adjust it.
- `attribution` is empty (no `Co-Authored-By`). Agent teams are off (see [Agent teams](#agent-teams)).
- Notification hooks cover permission prompts, idle prompts, idle teammates and auto-mode denials. There is no `Stop` hook.

**Shipped Codex policy:** `sandbox_mode = "workspace-write"`, `approval_policy = "on-request"`, network off by default, `file_opener = "vscode"`, an unpinned model, and `~/.codex/rules/tuidev.rules`, which makes the same git and gh writes prompt. See [sandboxing.md](sandboxing.md) for how this native sandbox relates to `sbx`.

**Multi-agent orchestration** (tiered subagents, a delegation skill, one policy for both CLIs) is its own pack: see [orchestration.md](orchestration.md).

### Instruction files

| CLI | Reads natively | To share one file |
|-----|----------------|-------------------|
| Claude Code | `CLAUDE.md` (managed → `~/.claude/CLAUDE.md` → project → `CLAUDE.local.md`) and `.claude/rules/*.md`. Reads `AGENTS.md` when the project has no `CLAUDE.md` (v2.1.277+). | Put `@AGENTS.md` on the first line of `CLAUDE.md` |
| Codex | `AGENTS.md` (`~/.codex/AGENTS.md`, then repo root down to the cwd; 32 KiB cap) | `project_doc_fallback_filenames = ["CLAUDE.md"]` |

Start a project's instructions from [templates/AGENTS_TEMPLATE.md](../templates/AGENTS_TEMPLATE.md). Claude Code and Codex both read `AGENTS.md`; for Claude-specific notes, add a `CLAUDE.md` whose first line is `@AGENTS.md`. Keep each instruction file short, because every one loads into context at session start.

### Agent teams

Claude Code's experimental agent teams are **off** in the shipped settings. While teams are enabled, every subagent Claude names launches as a teammate, without asking. That makes teams form during ordinary delegation, and each teammate is a full session with its own context and a 5-minute cache. Plain subagents cover focused work that only needs to return a result.

Turn teams on when teammates must talk to each other: `export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` for a shell, or the same key under `env` in `~/.claude/settings.json`. The shipped `"teammateMode": "auto"` then picks the display:

- **Inside tmux** (`--pack tmux`), each teammate gets its own tmux pane. Run `claude` from inside a tmux session.
- **Elsewhere**, teammates run in-process. The agent panel below the prompt lists them: arrow keys select, Enter opens, `x` stops. Force this mode with `claude --teammate-mode in-process`.

Split panes need tmux or iTerm2. Ghostty's native splits don't work for this.

## Worktree-per-agent

A terminal tab or pane per agent isolates the terminal. A **worktree** per agent isolates git state. Without one, parallel agents collide on the index, on each other's half-staged files, and on `HEAD`.

**Claude Code does this natively. Reach for it first:**

- `claude -w NAME` (`--worktree`) starts a session in a new worktree under `.claude/worktrees/NAME`.
- A subagent with `isolation: worktree` in its frontmatter runs in its own worktree.

Both keep the checkout inside the repo, which is where `sbx` and the native sandboxes allow writes.

**For other CLIs**, there's no tuidev wrapper: use `git worktree add` directly.

```bash
git worktree add ../repo-agent-1 -b agent/1   # one worktree, one branch
git worktree list                             # path, branch, HEAD
git worktree remove ../repo-agent-1            # after merging, once it's clean
```

**A worktree isolates git state only.** Ports collide, so give each worktree its own `PORT`. `node_modules`, `.venv` and `target` are neither shared nor copied. Gitignored files such as `.env` don't follow the worktree. A shared dev database is still shared. Use worktrees for genuinely independent tasks. When tasks touch the same files, one worktree and sequential agents are faster than merging the collisions.

## Background sessions

Claude Code and Codex can run sessions without holding a terminal. Both put them in worktrees, so they combine with [Worktree-per-agent](#worktree-per-agent) rather than replace it.

**Claude Code** ([agent view](https://code.claude.com/docs/en/agent-view)): a supervisor service runs background sessions so they survive closing agent view or the terminal.

```bash
claude agents                     # agent view: dispatch, list, reply
claude --bg "investigate the flaky test"   # start one and return
claude attach ID                  # open a session in this terminal
claude logs ID                    # print recent output
claude stop ID                    # stop it
claude respawn ID                 # restart it
claude rm ID                      # drop it from the list
```

Inside a session, `/bg` moves the conversation to the background and `/fork` copies it into a new background session while you keep working. Every background session, and each `/fork` copy, moves into its own worktree under `.claude/worktrees/` before it edits files (`worktree.bgIsolation: "none"` turns that off).

**Codex**: 0.156.0 enabled worktrees by default and added worktree session creation to the agents overview. 0.156.0 also added `/daemon` (update the local background server) and `--no-daemon` (bypass it). 0.157.0 made automatic background-server startup the default for eligible interactive sessions. See [the daemon note](sandboxing.md#codex-background-server).

**Git and the ask rules.** Claude Code tells a background session that changed files in a worktree to commit without asking, push the branch when there is a remote, and open a draft PR when the task calls for it. It never pushes to `main`/`master`, force-pushes or merges. The docs say your instructions win: if the task, `CLAUDE.md` or memory says you handle committing or pushing yourself, Claude leaves git to you. `--pack orchestration`'s rules file (`~/.claude/rules/tuidev-orchestration.md`) says to leave work uncommitted until you ask, which covers that. The shipped `ask` rules (`git add|commit|push|merge|tag`, `gh pr create|merge`) are permission decisions, and the docs say a background session waits under `Needs input` on "a permission decision"; answer it from the peek panel in `claude agents` (Space, type a reply, Enter) or after `claude attach ID`. Checked on v2.1.284: `ask` rules hold in a `claude --bg` session, which waits under `Needs input` on the `git commit` approval. They only gate what your settings still list: an `allow` rule such as `Bash(git *)` in your own `~/.claude/settings.json`, or `auto` mode, lets the session commit without asking.

Permission mode carries over from the session you backgrounded. Sessions started with `claude --bg` or `claude agents` use the target directory's configuration, the same as plain `claude` there.

**With tmux and Herdr.** Background sessions are supervised by Claude Code itself, not by a pane, so they don't need tmux to survive. `claude agents` is a per-CLI queue for Claude sessions. Herdr is the queue across CLIs and panes ([Fleet attention](#fleet-attention--herdr---pack-herdr)), and tmux keeps a terminal alive over SSH ([remote.md](remote.md)). Sandbox and login behavior is unchanged: see [sandboxing.md](sandboxing.md).

## Remote control from a phone

The CLIs now ship their own remote control, so you don't need SSH just to *steer* an agent.

- **Claude Code Remote Control** connects `claude.ai/code` and the Claude mobile apps to a session running on your machine. Code stays local. See <https://code.claude.com/docs/en/remote-control> for plan requirements.
- **Codex and others**: third-party layers such as [Tactic Remote](https://clauderc.com/).

For a full terminal (editing files, non-agent work, a flaky network), use SSH or mosh plus tmux, covered in [remote.md](remote.md).

## Fleet attention — Herdr (`--pack herdr`)

[Herdr](https://herdr.dev/) is an agent runtime. A server owns the terminal processes, clients attach and detach, and each pane holding an agent is marked `working`, `blocked`, `done` or `idle`. The CLI and a local socket API are the same surface, so agents can split panes, start each other, and wait on a blocked peer instead of sending keystrokes.

```bash
./install.sh --pack herdr
herdr                                         # attach; the first attach starts the server
herdr machine add workbox                     # save an SSH node (interactive, once)
herdr --machine workbox agent list            # scriptable, no TUI
```

Herdr is a second multiplexer. tmux (`--pack tmux`) is the default for a durable local session. Reach for Herdr when the question is *which agent needs me*, not *how do I keep this pane alive*. Its prefix is `Ctrl+b`, so it doesn't clash with tmux's `Ctrl+a`.

Practices:

1. **Never nest.** When `HERDR_ENV=1`, you are inside a Herdr pane. Use `herdr agent list` or the socket API, never the TUI.
2. **The sidebar is the queue.** Don't tab through panes looking for a prompt.
3. **Detach, don't kill.** `Ctrl+b q` leaves agents running. `herdr server stop` ends the herd.
4. **Sleep-proof work lives on an always-on node**, whether a saved machine (`herdr machine add`) or `herdr --remote NODE`.
5. **Upgrade clients freely, and servers deliberately.** A newer client keeps using a running compatible server (`herdr status` reports `server_binary_stale`). Restart a server when its agents are idle, or try `herdr update --handoff`. `herdr update` refuses to run inside a Herdr pane: detach (`Ctrl+b q`) and run it from a plain shell. Homebrew installs upgrade with `brew upgrade herdr` (or `make update-packages`). Keep exactly one `herdr` binary on each node.
6. **Links stay clickable.** Herdr ≥ 0.9.2 sets `TERM_PROGRAM=herdr`, which Claude Code doesn't recognize as hyperlink-capable, so the tuidev `.zshrc` exports `FORCE_HYPERLINK=1` inside Herdr panes (unless you set it). The variable comes from the pane's shell, so a pane opened before the change needs `exec zsh` (or a new pane) before its agent emits links; restarting only the agent isn't enough.
   - **Ctrl-click, not Cmd-click.** Herdr captures the mouse and opens pane links itself on Ctrl-click: OSC 8 links and plain `http(s)://` URLs. Cmd-click never reaches it. In Ghostty, hovering doesn't underline a link, even with Ctrl held, but the click still works.
   - **Shift-Cmd-click for file paths.** Shift bypasses Herdr's mouse capture, so Ghostty handles the click with its own link detection, which also matches file paths such as `/tmp/x.log`, `./src/main.rs` or `data/backups/x.db`. Herdr itself doesn't linkify plain paths (upstream treats that as a feature request).
   - **Saved-machine panes:** Ctrl-click doesn't open OSC 8 links there yet ([herdr#4447](https://github.com/herdrdev/herdr/issues/4447)); plain `https://` URLs still open.
7. **Reinstall integrations after upgrades.** Run `herdr integration install claude` (or `codex`, …) once, then `herdr integration status` after every upgrade, and reinstall anything reported `outdated`.
8. **Start the server from a login shell.** Integrations read the *server's* `PATH`. A server started by `brew services`, or by a non-interactive `ssh host herdr server`, gets a stripped `PATH` and reports the CLIs as `not found`. On Linux, use a systemd user unit with `ExecStart=/bin/bash -lc 'exec herdr server'`.

### Sessions and devices

A **session** is one Herdr server with its own workspaces, panes and socket. Plain `herdr` attaches to the `default` session; `herdr --session NAME` (or `herdr session attach NAME`) starts or attaches a named one, each with its own server.

- **Keep one session per machine** unless you need hard isolation (stopping or upgrading one project's server without touching the others). Split projects into *workspaces* inside it instead: every device then lands in the same sidebar.
- **A saved machine points at one session on that host**, picked during `herdr machine add`, which lists the sessions already running there. To switch, run `machine add` again and `herdr machine remove` the old entry.
- **Every device reaches the same session.** From a laptop, the node is a saved machine in the sidebar, or `herdr --remote workbox --session NAME`. From a phone, SSH in and run `herdr` (see [remote.md](remote.md#iphone-and-ipad)).
- **Inside a pane, `HERDR_SOCKET_PATH` wins over `HERDR_SESSION`**, so `HERDR_SESSION=other herdr status` still reports the pane's own session. Target another one explicitly: `HERDR_SOCKET_PATH=~/.config/herdr/sessions/NAME/herdr.sock herdr status` (`~/.config/herdr/herdr.sock` for `default`).
- **Manage them** with `herdr session list`, `herdr session stop NAME` (kills its panes) and `herdr session delete NAME`. Retiring a session means recreating its workspaces elsewhere; agents with native resume (`claude --resume`, `codex resume`) pick up their conversations.
- **Supervise every session on an always-on node**, or it won't come back after a reboot. A systemd user unit for the default session:

  ```ini
  # ~/.config/systemd/user/herdr.service
  [Unit]
  Description=Herdr agent runtime

  [Service]
  ExecStart=/bin/bash -lc 'exec herdr server'
  Restart=on-failure

  [Install]
  WantedBy=default.target
  ```

  Enable it with `systemctl --user enable --now herdr.service`, and run `sudo loginctl enable-linger $USER` once so user units run without a login. A named session needs the same unit with `Environment=HERDR_SESSION=NAME`.

`herdr machine add` checks and, after asking, installs the remote server. It never copies your config or secrets. `herdr machine status` checks saved machines without prompting; `herdr machine reconnect` finishes SSH authentication (MFA included) in your terminal. Passphrase-protected keys need `ssh-add` first. Under `sbx --profile strict`, an agent reaches the Herdr socket only with `--allow-herdr` (see [sandboxing.md](sandboxing.md#profiles)). Inside a Herdr pane, `HERDR_ENV=1` is already set, and `sbx` hides the wrapped process from Herdr's detection unless you pass `--allow-herdr`. Herdr's docs: <https://herdr.dev/docs/>.

## Local processes: `agents` (`--pack monitoring`)

Every `claude` session starts its own MCP servers (`npm exec chrome-devtools-mcp@latest`, `node …/some-mcp.cjs`), about 250 MB a session, and holds a rolling `caffeinate -i -t 300`. When a session dies badly, those children are reparented to launchd and keep running. `agents` (`~/.local/bin/agents`) shows what is running and cleans up what leaked. It reads one `ps` snapshot per run and never needs sudo.

```bash
agents                    # sessions (blocked first), stale processes and hogs if any, system status
agents watch              # the same, redrawn every 2s (q quits)
agents open-term watch    # the same in a new window of your terminal (AGENTS_TERMINAL)
agents ps 90419           # everything one session runs (all sessions without a pid)
agents reap -n            # what `reap` would kill: every stale tree
agents reap -n --stuck    # the same, plus the polling loops flagged stuck
agents reap               # SIGTERM each stale tree, SIGKILL what's left after 3s (asks first)
agents kill PID           # one tree, descendants first
agents term PID           # one process only (a hog), SIGTERM
agents awake on 2h        # keep the Mac and display awake (30m, 1h30m; no duration = until off)
agents awake agents       # stay awake while any claude or codex runs, then release
agents awake lid 3h       # macOS, opt-in: awake with the lid closed too (asks for your password)
agents awake status       # our hold, plus who else holds the Mac awake (pmset -g assertions)
agents json               # machine-readable; `agents tsv` feeds the menu-bar plugin
```

- **Agents** are processes named `claude` or `codex` (`AGENTS_NAMES` adds more): one row per tree, with its project (the directory's name, or `repo/name` for a worktree under `.claude/worktrees/`), tree CPU and memory, child count, cwd, listening ports and, when Herdr is running, its status for the pane in that directory. Sessions waiting for you (Herdr's `blocked`) come first, then `working`, then `idle` and `done`, then sessions without a status. Herdr's answer is cached for ten seconds in `~/.config/tuidev/run/`; the menu bar never waits for it and refreshes it in the background. The Codex app-server daemon (`codex app-server … --managed-daemon` and its `pid-update-loop`) is long-lived by design: it gets its own `daemon` row and is never stale. `claude --chrome-native-host`, the browser bridge Chrome starts, is not a session.
- **What sessions run.** Under each session, `agents ls` lists its MCP servers on one line and its busiest commands (`AGENTS_LS_TOOLS`), and `agents ps PID` lists everything:

  ```
    90419   claude  working    3h30m  537.0   2.1G   33  64013  myapp        ~/code/myapp
        mcp: 2 servers · 4 procs · 209M
        └ go test -race ./internal/web · 2m08s · 100% · feat-a  x2 dup  hot
        └ npm run dev · 1h00m · 0% · feat-b  long
  ```

  Each child of a session is one unit, with its whole subtree's CPU and memory:
  - **MCP servers**, grouped by name (`npm exec X-mcp@latest`, `node …/x-mcp.cjs`);
  - **commands**: each tool shell, Claude Code's `zsh -c … eval '<command>'` or Codex's `bash -lc <command>` (on macOS wrapped in `sandbox-exec`), shown as the command itself, without its `cd`, `VAR=value` prefixes, `2>&1` and a trailing `| tail`;
  - the session's own `caffeinate`, nested sessions (a `claude -p` a command started), and anything else.

  A command's **origin** is the worktree subagent it runs for, from its directory (`<repo>/.claude/worktrees/<name>`), or `main`. Subagents run inside the session's own process, so the directory is the only reliable clue. Flags:
  - `dup`: the same command runs more than once in the same directory, within a session or across sessions. A command's directory is where it `cd`s first, so parallel worktree subagents running the same `go test` in their own worktrees are not duplicates;
  - `long`: running longer than `AGENTS_TOOL_LONG` (20 minutes);
  - `wait`: a polling loop the agent waits on (`until …; do sleep 5; done`). It is never `dup` or `long`; the menu marks it with a gray hourglass, and it can still be stopped;
  - `stuck` (with `wait`): a polling loop that has run `AGENTS_WAIT_STUCK` (60 minutes) or longer, unless the file it watches changed within that time: then its producer is alive (a long build's log), and the loop stays a plain `wait`. The watched file is the first absolute path the loop's condition gives to `tail`, `head`, `grep`, `cat`, `test`, `[` or `[[`, directly (`until grep -q ok /tmp/x.log`) or through an assignment before the loop (`F=/tmp/x.output; until tail -1 $F | …`); paths other commands take (`docker exec db /usr/bin/pg_isready`, `curl --unix-socket …`) don't count. `agents` checks every such file with one `find -mmin`. A loop with no watched file, or whose file doesn't exist, is judged by its age alone. A stuck loop usually waits for a line that will never come: it needs you. `agents reap --stuck` stops every stuck loop along with the stale trees;
  - `hot`: its subtree uses `AGENTS_HOG_NOW` CPU or more.

  For agent authors: Claude Code appends `[exited with code N]` as the last line of a background task's `.output` file, so a loop such as `until tail -1 "$F" | grep -qE '^(ok|FAIL)'` never ends once the task has finished. Match the exit line too (`grep -qE '^(ok|FAIL)|^\[exited with code'`), or cap the tries (`for i in $(seq 120); do …; sleep 5; done`).

  Stopping a command is an ordinary tree kill with every safety check: the session sees the command fail and carries on.
- **Stale** means reparented to launchd (ppid 1), yours, and either matching an agent-helper pattern (MCP servers, `npm exec`/npx, `caffeinate`; the list is `AGENTS_ORPHAN_PATTERNS` at the top of the script) or a dev server: a process that listens on a TCP port itself or through its children (an orphaned `npm run dev` whose vite listens), started from a directory under `$HOME` (not `~/Library`), `$TMPDIR` or Claude Code's `/private/tmp/claude-UID` scratchpads. Never flagged:
  - a session, or anything that hosts one: a process whose tree holds an agent, an interactive or login shell, or a tmux, screen, zellij, Herdr or pm2 server (so a tmux server whose claude pane listens on a port is left alone);
  - launchd jobs (`launchctl list`: LaunchAgents, Homebrew services) and, on Linux, processes in a systemd `.service` unit;
  - the Codex daemon and `agents`' own keep-awake holder.

  Stale detection is mostly a macOS story: on Linux, orphans usually reparent to a `systemd --user` subreaper instead of pid 1, so they don't look orphaned.
- **Hogs** are any process of any owner averaging at least 50% CPU over its lifetime after 30 minutes (a Messages.app stuck at 100% for days), or at least 90% right now outside an agent tree. `AGENTS_HOG_PCT`, `AGENTS_HOG_MIN`, `AGENTS_HOG_NOW` and `AGENTS_HOG_TOP` tune them. On Linux, `ps` reports only the lifetime average.
- **Safety.** `kill`, `reap` and `term` refuse:
  - pid 1, `agents` itself and its parents (so the session you run it from);
  - other users' processes, for which they print the `sudo kill` to run yourself;
  - system and session processes: anything under `/System/Library`, `/usr/libexec` or `/usr/sbin`, and `loginwindow`, Finder, Dock, WindowServer, SystemUIServer, ControlCenter and your terminal (Ghostty, Terminal, iTerm2, WezTerm, kitty, Alacritty). Apps in `/System/Applications`, such as a runaway Messages, stay allowed. Inside a tree, such members are skipped;
  - any process hosting an interactive shell or an agent below it: a terminal app (Warp, Hyper, Tabby…), an editor's helper, a tmux or screen server. An agent root itself can still be killed, with its tree;
  - running as root at all.

  Before every signal they re-check the process's start time, so a reused pid is never hit, and `PID@START` (from `json` or `tsv`) pins the exact process that was listed. A tree kill returns as soon as everything exited after SIGTERM; after the grace period it SIGKILLs the survivors, plus, if the tree's root is still running then, anything that root's tree spawned meanwhile. Without a terminal they need `-y`.
- **Keep-awake** is `caffeinate -di` (system and display idle sleep). By default it never uses `pmset disablesleep` or sudo; `awake lid` (below) is the explicit opt-in. The holder's pid lives in `~/.config/tuidev/run/awake`, and `on`, `off` and `agents` take a lock (released on any exit), so two clicks never leave two holders. The record is dropped only when the holder is really gone; if its start time can't be checked (`ps` blocked, as in a sandbox), `awake off` refuses to signal the pid and tells you how to stop it yourself. Without `caffeinate` or `systemd-inhibit`, `awake on` fails with a message. `./uninstall.sh` runs `agents awake off` before it removes the helper. `awake agents` re-checks every minute, which also covers Claude Code's own gap between stopping one `caffeinate` and starting the next. A closed lid still sleeps the Mac unless it runs on power with an external display attached (Apple's closed-display mode). On Linux, `systemd-inhibit` holds the same locks.
- **Keep awake with the lid closed** (`agents awake lid DURATION`, macOS only; Linux reports it as unsupported). For when you want an agent to keep working in a closed laptop for a few hours. If you can, use closed-display mode instead (power plus an external display), which needs no root. Otherwise:
  - it runs `pmset -a disablesleep 1`, which needs root. It asks for your administrator password each time, in macOS's own dialog (`/usr/bin/osascript … with administrator privileges`, started with an empty environment, so nothing inherited reaches the root shell). No sudo rights or sudoers file are stored;
  - it is always time-boxed: a duration is required, and one longer than `AGENTS_LID_MAX` (8h) is refused;
  - the same root command starts a small root-owned guard, which turns lid sleep back on (`pmset -a disablesleep 0`) when the time is up, when the battery falls below `AGENTS_LID_MIN_BATTERY` (20%) off AC, or when thermal pressure reaches heavy (moderate is common in a closed Mac running a build, so it doesn't count). It checks once a minute. The guard is fixed text in `bin/agents`: only the checked duration in seconds and the battery number are added to the root command;
  - the usual `caffeinate -di` holder runs for the same time, so the display and idle behaviour match `awake on`;
  - `agents awake off` ends it early, which asks for your password once more: it restores the setting and retires the guard (after checking that the pid is still root's guard). Switching to `awake on` or `awake agents` replaces only the `caffeinate` holder: lid mode keeps running, with no dialog, until it times out or `awake off` / `awake restore` ends it. `agents awake restore` restores the setting whatever ran it.

  **Reboot caveat:** macOS keeps `disablesleep` across a reboot (it's a system-wide setting, stored in `/Library/Preferences/com.apple.PowerManagement.*.plist`; `man pmset` doesn't document it), but the reboot kills the guard. `agents`, `agents awake status`, the menu and `make check` (`scripts/health_check.sh`) all notice sleep disabled with no live guard: `WARNING: lid sleep disabled with nothing to restore it`. The fix is `agents awake restore`, or `sudo pmset -a disablesleep 0`. A Mac in a bag can overheat, so the menu offers lid mode only with `AGENTS_LID=1`.
- **Thermal** shows the kernel's thermal pressure (`nominal`, `moderate`, `heavy`, `trapping`, `sleeping`, from `notifyutil -g com.apple.system.thermalpressurelevel`) and the energy mode (`automatic`, `low`, `high`). Both are read-only: macOS runs the fans, and `agents` never changes the energy mode.

### Menu bar (SwiftBar, macOS)

On macOS the pack also installs [SwiftBar](https://swiftbar.app) and its `agents.10s.sh` plugin, which also stands in for a system-stats menu bar app. If SwiftBar already has a plugin folder, the plugin goes there; otherwise the pack sets the folder to `~/.config/swiftbar/plugins`. Open SwiftBar once (`open -a SwiftBar`) and turn on **Launch at login** in its settings. The pack doesn't add login items. Uninstalling removes the plugin but leaves SwiftBar's plugin-folder setting as it is.

- **Title:** by default an SF Symbol and the number of sessions, plus `· N blocked` when sessions wait for you and a cup while keep-awake is on. The icon turns orange when something needs a look (a blocked session, stale processes, a hog, memory pressure) and red for heavy thermal pressure, critical memory pressure, or sleep disabled with nothing to restore it; otherwise it follows the menu bar's colors. The session count is the same in the title, the menu and `agents ls`; the Codex daemon is listed separately and not counted.
- **Menu**, in the order of `AGENTS_BAR_SECTIONS` (sections with nothing to show are left out):
  - **Needs you:** sessions Herdr reports as blocked, waiting for input or a permission; commands running more than once (`myapp: 3× go test running`, with Stop duplicates (keep newest)…) commands running longer than `AGENTS_TOOL_LONG` (with Stop command…), and polling loops flagged `stuck` (`myapp: until tail -1 $F … · stuck 3h27m`, an orange hourglass, with Stop command…). A polling loop that is not stuck stays out of it. Stuck loops and long or duplicate commands tint the icon orange, but only blocked sessions count in the title's `· N blocked`.
  - **Agents:** one line per session: project, kind, status, CPU and memory, with a dot colored by status (orange blocked, green working, gray idle). When its commands use most of the CPU the row says so (`735% (tools 728%)`). Clicking it shows the project in Finder. Its submenu holds the full path, pid, age, children and ports; Running (N), one line per command (command, age, CPU, origin, flags) with Stop command… (asks first); the MCP servers on one line; Stop duplicates (keep newest)… when a command runs twice; and Kill session…, Copy path, Open in Finder and Copy PID. The Codex daemon follows on its own line with a gear.
  - **Stale:** each with Kill tree, plus Reap all stale, which kills exactly the processes listed, not whatever is stale when you click.
  - **Hogs:** each with Terminate (SIGTERM, your own processes only).
  - **Awake:** the state (off, while agents run, time left, `lid closed · 2h41m left`), with a check mark on the active choice among Until turned off, For 1 hour, For 3 hours, While agents run and Off, plus who holds the Mac awake. With `AGENTS_LID=1`, a Lid closed too… group offers 1, 3 and 8 hours (up to `AGENTS_LID_MAX`), each running `agents awake lid` and asking for your password. When sleep is disabled with nothing to restore it, a red Restore lid sleep… item leads Needs you and the Awake section.
  - **System**, two lines: CPU (the sum of `%cpu` over the `ps` snapshot, divided by the cores), memory used (`memory_pressure -Q`) and the load, which opens `agents watch`, with the busiest processes in its submenu (each opens Activity Monitor); then battery and charging (`pmset -g batt`), thermal pressure and energy mode, which opens System Settings › Battery, where Energy Mode lives.
  - Then Open agents watch, Edit settings (opens `~/.config/agents.conf`) and Refresh.
- Every action runs `agents` with the `PID@START` it listed, so a menu opened before a pid was reused can't kill the wrong process. Menu parameters carry only fixed words and such tokens, never a path or a name a process controls: Copy path and Open in Finder run `agents copy-path|reveal PID@START`, which looks the directory up when you click (`agents cwd PID@START` prints it). Killing a live session asks first in a macOS dialog (`--confirm-gui`, Cancel is the default) naming the project, pid and child count; stale processes and hogs, already filtered, go in one click. Each action reports its result as a notification (`--notify`).
- Windows open in your terminal (`agents open-term`, `AGENTS_TERMINAL`), not through SwiftBar's own terminal option, which always uses Terminal.app. For Ghostty (1.2 or later; `auto` skips an older one) that is `open -na Ghostty --args -e …`; one-shot views such as "Who holds the Mac awake?" wait for a key before the window closes.
- Text uses the menu's own label color. Status colors are on the symbols only (SwiftBar colors an item's symbol through `sfconfig`, not `sfcolor`), and lines that only inform, such as section headers and the details in a submenu, appear dimmed.
- One refresh runs `agents tsv` once: one `ps` snapshot, two `lsof` calls, a handful of one-line probes, and Herdr from its cache, in 0.2–0.6 s depending on load.

### Machine-readable output: `agents json`

`agents json` is a contract other tools build on: fields are only added within a `schema_version`, and anything removed or changed bumps it. Version 1:

```
{
  "schema_version": 1,
  "agents": [{
    "pid", "kind" ("claude"|"codex"|…|"daemon"), "age_s", "cpu", "avg_cpu", "rss_kib", "children",
    "start", "start_epoch", "ports": [n], "user", "herdr" (status or null), "cwd", "project", "command",
    "activity": {
      "cpu":     {"self", "tools", "mcp", "other"},          percent, subtree sums
      "rss_kib": {"self", "tools", "mcp", "other"},
      "mcp":   [{"name", "procs", "cpu", "rss_kib"}],
      "tools": [{"pid", "start", "start_epoch", "token" ("PID@START"), "cmd", "origin" ("main"|worktree|null),
                 "cwd", "age_s", "cpu", "rss_kib", "processes", "ports": [n],
                 "flags": ["dup"|"long"|"hot"|"wait"|"stuck"], "dup_count"}],
      "child_sessions": [{"pid", "start", "start_epoch", "token", "depth" ("direct"|"nested"), "age_s", "cpu", "rss_kib", "command"}]
    }
  }],
  "stale": [same fields as an agent, without activity], "hogs": [...], "top": [...],
  "system": {"cpu_pct", "load1", "cores", "mem_free_pct", "mem_pressure", "battery_pct", "battery_state"},
  "awake": {"active", "pid", "mode" ("on"|"timed"|"agents"|"lid"), "until"},
  "lid": {"active", "pid", "until", "sleep_disabled" (true|false|null), "stale"},
  "thermal": {"level", "name"}, "powermode"
}
```

`start` is the process start time as `ps` prints it (it is part of the `token`); `start_epoch` is the same moment in Unix seconds, derived from the elapsed time (±1 s). A tool's `cwd` is the directory its command `cd`s into, when it does. `flags` is an open set: a new flag value is added within a version (as `stuck` was, always alongside `wait`), so ignore values you don't know. A `token` is what `agents kill`, `term`, `cwd`, `copy-path` and `reveal` take: they refuse it once the pid names another process.

### Settings: `~/.config/agents.conf`

The pack places a fully commented [`agents.conf`](../configs/agents/agents.conf) once (`--adopt-existing`) and never overwrites it. Uncomment a line to change it; `agents config` prints what is in effect. The file is read as `KEY=value` lines, never run as a script: unknown keys and malformed values are reported and ignored. The same names in the environment win, and `AGENTS_CONF` points at another file.

| Key | Default | Meaning |
|-----|---------|---------|
| `AGENTS_HOG_PCT` | `50` | Lifetime-average CPU% that makes a long-running process a hog |
| `AGENTS_HOG_MIN` | `30` | Minutes a process must have run before its average counts |
| `AGENTS_HOG_NOW` | `90` | Current CPU% that makes a process outside any agent tree a hog |
| `AGENTS_HOG_TOP` | `5` | Hogs listed |
| `AGENTS_TOOL_LONG` | `20` | Minutes before a session's command (a tool shell) is flagged `long` |
| `AGENTS_LS_TOOLS` | `5` | Commands listed under each session in `agents ls` and `watch`; `agents ps` lists all |
| `AGENTS_WAIT_STUCK` | `60` | Minutes a polling loop (`wait`) runs before it is flagged `stuck`, unless the file it watches changed within that time. `0` never flags one |
| `AGENTS_NAMES` | `claude codex` | Process names (argv[0] basenames) that count as agent sessions |
| `AGENTS_GRACE` | `3` | Seconds between SIGTERM and SIGKILL when killing a tree |
| `AGENTS_AWAKE_POLL` | `60` | Seconds between checks in `agents awake agents` |
| `AGENTS_LID` | `0` | `1` offers Lid closed too… in the menu. `agents awake lid` works either way |
| `AGENTS_LID_MAX` | `8h` | The longest `agents awake lid` may run; longer requests are refused |
| `AGENTS_LID_MIN_BATTERY` | `20` | Battery % (off AC) below which the lid guard turns lid sleep back on |
| `AGENTS_NO_HERDR` | empty | `1` skips the Herdr status lookup |
| `AGENTS_TERMINAL` | `auto` | Where `agents open-term` and the menu open windows: `ghostty` (1.2 or later), `iterm`, `terminal`, `wezterm`, `kitty`, or `auto` (the first installed of Ghostty 1.2+, iTerm, WezTerm and kitty, else Terminal) |
| `AGENTS_BAR_TITLE` | `count awake` | Title tokens after the icon: `count` (sessions, and how many are blocked), `cpu`, `mem`, `load`, `battery`, `thermal` (only above nominal), `awake`, `warn` (a triangle as well as the tint). Empty shows the icon alone |
| `AGENTS_BAR_SECTIONS` | `needs agents stale hogs awake system` | Menu sections, in order; `needs`, `stale` and `hogs` appear only when they have entries |
| `AGENTS_BAR_ICON` | `terminal` | The title's SF Symbol |
| `AGENTS_BAR_TOP` | `3` | Busiest processes in the System section (`0` for none) |
| `AGENTS_BAR_REFRESH` | `10s` | SwiftBar's refresh interval, which it reads from the plugin's file name. Re-run `./install.sh --pack monitoring` (or `make update-configs`) after changing it, and the pack renames the plugin. One refresh takes 0.2–0.6 s depending on load, so 10s or slower is plenty |

The stale patterns are not a setting: extend `AGENTS_ORPHAN_PATTERNS` at the top of `bin/agents` and send the change upstream if it's general.

## Desk and session tools

**Superlogical** (<https://www.superlogical.com/>) is on the watch-list. There is no pack until a public release exists (see [roadmap.md](roadmap.md)).

## Notifications

Don't watch panes. `~/.local/bin/notify.sh` (from `scripts/notify.sh`) is called by the Claude Code hooks, and optionally by Codex's `notify`. It uses the first channel that works:

1. A Herdr toast, inside a Herdr pane
2. The tmux status line, inside tmux
3. A macOS banner (`osascript`)
4. `notify-send`, on a Linux desktop
5. An [ntfy](https://ntfy.sh) push, when `NTFY_URL` is set (for example `export NTFY_URL=https://ntfy.sh/your-topic` in `~/.zshrc.local`)
6. Nothing: it stays silent and always exits 0

tmux also flags any window whose agent rings the bell.

## Done means verified

An agent that says "done" isn't done until the checks pass. Verify the cheapest checks first: lint and syntax, then targeted tests, then health checks, then CI. For this repo, that is `make ci-test`, then `make check` (see [engineering.md](engineering.md#verification)).
