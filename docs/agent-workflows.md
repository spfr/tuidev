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
herdr machine add workbox --label workbox     # save an SSH node (interactive, once)
herdr --machine workbox agent list            # scriptable, no TUI
```

Herdr is a second multiplexer. tmux (`--pack tmux`) is the default for a durable local session. Reach for Herdr when the question is *which agent needs me*, not *how do I keep this pane alive*. Its prefix is `Ctrl+b`, so it doesn't clash with tmux's `Ctrl+a`.

Practices:

1. **Never nest.** When `HERDR_ENV=1`, you are inside a Herdr pane. Use `herdr agent list` or the socket API, never the TUI.
2. **The sidebar is the queue.** Don't tab through panes looking for a prompt.
3. **Detach, don't kill.** `Ctrl+b q` leaves agents running. `herdr server stop` ends the herd.
4. **Sleep-proof work lives on an always-on node**, whether a saved machine (`herdr machine add`) or `herdr --remote NODE`.
5. **Upgrade clients freely, and servers deliberately.** A newer client keeps using a running compatible server (`herdr status` reports `server_binary_stale`). Restart a server when its agents are idle, or try `herdr update --handoff`. Homebrew installs upgrade with `brew upgrade herdr` (or `make update-packages`). Keep exactly one `herdr` binary on each node.
6. **Links stay clickable.** Herdr ≥ 0.9.2 sets `TERM_PROGRAM=herdr`, which Claude Code doesn't recognize as hyperlink-capable, so the tuidev `.zshrc` exports `FORCE_HYPERLINK=1` inside Herdr panes (unless you set it). Ctrl+click opens a link. Restart an agent that started before the change.
7. **Reinstall integrations after upgrades.** Run `herdr integration install claude` (or `codex`, …) once, then `herdr integration status` after every upgrade, and reinstall anything reported `outdated`.
8. **Start the server from a login shell.** Integrations read the *server's* `PATH`. A server started by `brew services`, or by a non-interactive `ssh host herdr server`, gets a stripped `PATH` and reports the CLIs as `not found`. On Linux, use a systemd user unit with `ExecStart=/bin/bash -lc 'exec herdr server'`.

`herdr machine add` checks and, after asking, installs the remote server. It never copies your config or secrets. Passphrase-protected keys need `ssh-add` first. Under `sbx --profile strict`, an agent reaches the Herdr socket only with `--allow-herdr` (see [sandboxing.md](sandboxing.md#profiles)). Inside a Herdr pane, `HERDR_ENV=1` is already set, and `sbx` hides the wrapped process from Herdr's detection unless you pass `--allow-herdr`. Herdr's docs: <https://herdr.dev/docs/>.

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
