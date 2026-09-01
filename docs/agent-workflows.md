# Agent Workflows

How to run and drive AI coding agents with this setup — locally, in parallel,
across machines, and from your phone. The CLIs themselves are opt-in
(`./install.sh --pack ai-clis`); the core setup stays CLI-agnostic.

The throughline is unchanged from [`VISION.md`](../VISION.md): **tmux is the
durability layer.** Everything here either runs *inside* tmux, sits *beside*
it as an optional runtime, or is a client that attaches to work that already
lives on a machine.

## Control plane

Look at agents only when they need you. A fleet is an **attention queue**, not
a wall of panes.

| Role | Tool | When |
|------|------|------|
| One task, durable, SSH/mosh, muscle memory | **tmux** (`work` / `dev` / `ai`) | Default. Prefix `Ctrl+a`. |
| Fleet attention (`working` / `blocked` / `done`) | **Herdr** (`--pack herdr`) | Many agents, many repos. Prefix `Ctrl+b`. |
| Pick / restart tmux agent sessions | **bosun** (`--pack bosun`) | Stays on a private `tmux -L bosun` socket. |
| Desk-only GPU parallel panes | **cmux** (`--pack cmux`) | macOS GUI. Not the remote story. |
| Steer one Claude/Codex from a phone | **Native CLI remote control** | No SSH just to talk to the agent. |
| Session around *all* work (local + remote + CI) | **[Superlogical](https://www.superlogical.com/)** | Watch-list. No pack until a beta ships. |

Do not collapse these. tmux does not know agent state. Herdr does not replace
`work` / `dev` / `ai`. cmux does not survive SSH. Superlogical is not
installable yet.

### Machine roles

- **Mac (control plane)** — Ghostty, Seatbelt (`sbx`), local Herdr server,
  tmux layouts. This is where you sit.
- **Always-on Linux node** — any cheap box that stays awake (a Raspberry Pi,
  NUC, or VM). Pattern: `ssh user@devbox` then `tmux attach` or `herdr`, or
  `herdr --remote workbox` from the Mac. Bind real hostnames only in
  `~/.ssh/config.local` or `~/.zshrc.local` — never in this repo. See
  [`remote.md`](remote.md) and [`inspiration.md`](inspiration.md).

Laptop sleep must not kill work that should keep running. Put that herd on
the always-on node.

## Driving one agent remotely — native remote control

The agent CLIs ship their own remote control, so you no longer need SSH just
to *steer* an agent from your phone.

- **Claude Code Remote Control** — connects `claude.ai/code` and the Claude iOS /
  Android apps to a Claude Code session running on your machine. Your code never
  leaves the machine; only chat messages and tool results cross an encrypted
  bridge. Requires Claude Code ≥ v2.1.51 and a Pro / Max / Team / Enterprise
  plan (API keys are not supported). Docs:
  <https://code.claude.com/docs/en/remote-control>
- **Codex / others** — third-party mobile control layers cover Codex and more:
  [Tactic Remote](https://clauderc.com/) (Claude / Codex / Amp) and
  [QuivrHQ/247-claude-code-remote](https://github.com/QuivrHQ/247-claude-code-remote)
  (Tailscale + Fly.io).

**When to use which:**

| Goal | Reach for |
|------|-----------|
| Steer one agent from your phone, low friction | Native Remote Control |
| Full terminal: edit files, run anything, non-agent work | SSH + tmux ([`remote.md`](remote.md)) |
| Fleet of agents, who is blocked? | Herdr (below) |
| Survive flaky/cellular networks | mosh wrapping tmux ([`remote.md`](remote.md)) |

Remote Control replaces the *"SSH in just to talk to Claude"* case. It does
**not** replace the durable backbone.

## One-task durability — tmux panes

The shipped, zero-extra-install way:

```bash
agents [name]     # claude | codex, two columns (needs --pack ai-clis)
ai [name]         # nvim + 2 agent panes
ai-triple [name]  # nvim + 3 agent panes
```

These survive disconnects, reattach over SSH, and work identically on Linux.

## Worktree-per-agent

For genuinely parallel agents, give each one its own checkout. A tmux pane per
agent isolates the *terminal*; a worktree per agent isolates the *git state* —
without it, two agents editing at once collide on the index, on each other's
half-staged files, and on the branch that HEAD points at.

```bash
worktrees feat -n 3 --cmd cc     # 3 worktrees, 3 windows, cc in each
worktrees --list                 # path / branch / dirty? / commits ahead
worktrees --clean                # reap the ones that landed
```

Worktrees live at `../<repo>-wt/agent-1`, `agent-2`, ... on branches `agent/1`,
`agent/2`, ... Window `main` stays on the original repo: review each branch
there and `git merge agent/2` what you want to keep. `--clean` then removes the
merged worktrees and refuses any that still hold uncommitted changes or
unmerged commits, naming what blocks each one.

**A worktree isolates git state only.** Ports collide — give each worktree its
own `PORT` or run one server at a time. `node_modules` / `.venv` / `target` are
neither shared nor copied, so each worktree needs its own install. Gitignored
files such as `.env` do not follow the worktree; copy or symlink them in. One
shared dev database or cloud project is still shared.

Use this when tasks are genuinely independent (separate features, competing
implementations of the same task). For tasks that touch the same files, one
worktree and sequential agents is faster than merging the collisions.

## Fleet attention — Herdr (`--pack herdr`)

[Herdr](https://herdr.dev/) is a Rust runtime for coding-agent fleets. A
background server owns real terminal processes. Clients attach, detach, and
render. Herdr detects agents in panes and marks each `working`, `blocked`,
`done`, or `idle`. The CLI and a local socket API are the same surface — agents
can split panes, start each other, and wait until another agent is genuinely
blocked instead of firing keystrokes.

```bash
./install.sh --pack herdr
herdr                 # attach to the local server
herdr --remote workbox  # thin local client over SSH (Host from your SSH config)
```

**Trade-off:** Herdr is a second multiplexer. tmux remains the default for
`work` / `dev` / `ai`. Use Herdr when the bottleneck is *which agent needs
you*, not *how do I keep this pane alive*. Prefix is `ctrl+b`; this setup's
tmux prefix is `ctrl+a`, so they do not clash if you use both.

If `HERDR_ENV=1`, you are already inside a Herdr pane. Do not run `herdr`
again from that pane — nested launches are blocked by design. Drive Herdr
with the CLI (`herdr agent list`, `herdr status`) instead of scripting the
TUI. Agent skill (documented, not auto-installed):
`npx skills add herdrdev/herdr --skill herdr -g`.

Integrations (optional, after install): `herdr integration install claude`
adds native session restore where supported. Upstream:
<https://herdr.dev/docs/>.

On a Linux node without Homebrew, the pack prints Herdr's official installer
command for you to run — it never pipes a remote script to a shell. Distro
tmux/git/rg are enough for the durability path; `--core` fills in the rest via
its apt fallback where the release packages it.

### First fleet (generic)

Personal hosts stay in `~/.ssh/config.local`. The shipped SSH snippet already
`Include`s that file (glob, so a missing file is ignored).

```bash
# Mac — once
./install.sh --profile desktop --pack herdr --pack ai-clis
herdr server              # headless; clients attach with `herdr`
# Detach a client: prefix then q  (ctrl+b, then q). The server keeps running.

# Always-on node — herdr on PATH (official installer if no brew)
# ~/.local/bin must be on PATH for *non-interactive* SSH too (~/.profile).

# ~/.ssh/config.local  (never commit this)
#   Host workbox
#       HostName devbox.example.com
#       User your-username

herdr --remote workbox    # thin client TUI (needs a real terminal)
ssh workbox -- herdr agent list   # scriptable; agents use this, not the TUI
herdr agent list          # who is working / blocked / done
herdr status              # local client + server
```

**Integrations say `not found` but the CLIs are installed.** Herdr scans the
*server process* PATH, not your interactive shell. `brew services start herdr`
and a non-interactive `ssh host herdr server` inherit a stripped PATH
(`/usr/bin:/bin` on macOS). Start the server from a login shell instead:

```bash
# macOS — prefer an attach that starts the server, or a login-shell LaunchAgent
herdr                 # from Ghostty/zsh; first attach starts the server with your PATH
# Linux node — systemd user unit with: ExecStart=/bin/bash -lc 'exec herdr server'
```

Then `herdr integration install claude` (and `codex` / `grok` / …) for native
lifecycle hooks. `agy` is not the same slot as Herdr's `antigravity-cli`.

**Practices that stay true in 2027:**

1. **One workspace per repo or task.** Split panes for an agent vs a runner;
   do not pile unrelated jobs in one workspace.
2. **The sidebar is the queue.** Do not tab through panes looking for a prompt.
3. **Detach, don't kill.** `prefix+q` leaves agents running. `herdr server stop`
   is how you actually end the herd.
4. **Sleep-proof work lives on the always-on node.** Laptop Herdr dies with the
   lid; `herdr --remote workbox` does not.
5. **Never nest.** If `HERDR_ENV=1`, use `herdr agent list` / the socket API.
6. **Done means verified.** Lint → tests → `make check` before you trust "done".
7. **tmux still wins for one durable task** (`work` / `dev` / `ai`). Herdr wins
   when the question is *which agent needs you*.

## Parallel agents on the desk — cmux (`--pack cmux`)

[cmux](https://github.com/manaflow-ai/cmux) is a Ghostty-based, GPU-accelerated
macOS terminal built specifically for running coding agents side by side:
vertical tabs, notification rings (OSC 9/99/777 and Claude Code hooks), a
built-in browser with Playwright-equivalent automation, and Claude Code Teams
integration. It works with claude, codex, opencode, and any CLI.

```bash
./install.sh --pack cmux     # brew tap manaflow-ai/cmux + cask (macOS 14+)
```

**Trade-off:** cmux is a native macOS GUI app. You gain a slick parallel-agent
UX; you give up tmux's session durability, SSH-reattach, mobile access, and
Linux parity. Treat it as a desktop *complement*, not a replacement.

## tmux session picker — bosun (`--pack bosun`)

[bosun](https://github.com/yetidevworks/bosun) (Rust + ratatui) lists, previews,
creates, and manages tmux sessions running Claude Code, Codex, or a plain shell
from one TUI — lifecycle controls (attach / rename / restart / kill), and push
notifications from tmux via control mode. It runs its sessions on a dedicated
`tmux -L bosun` socket, so it never touches your main tmux state.

```bash
./install.sh --pack bosun     # via Homebrew formula if available, else cargo
```

Because bosun stays inside the terminal and drives tmux, it fits the
tmux-primary thesis — orchestration that survives disconnects and works over
SSH. It does not detect agent state the way Herdr does.

## Horizon — Superlogical

[Superlogical](https://www.superlogical.com/) (Hashimoto, Pearkes, and others)
is building a multiplexer for *all* work: interactive sessions, agents,
background jobs, and production, with web and native clients. There is no
public binary yet. When a beta exists and it remains excellent at being a
multiplexer, this repo will add `--pack superlogical` the same way it added
Herdr. Until then: tmux + Herdr.

## Execution is unverified until the ladder ran

An agent that says "done" is not done. Verify cheapest-first:

1. Lint / syntax (`make lint`, `make validate-configs`)
2. Targeted tests (`make test-core`)
3. Health (`make check`, `make sbx-test` on macOS)
4. CI

See [`engineering.md`](engineering.md). Parallel implementors get **isolated
git worktrees** — do not share a dirty index. Herdr can open worktrees from
the sidebar; that is optional, not required.

## Sandboxing

The AI-CLI wrappers (`--pack ai-clis`) auto-route through `sbx` (Seatbelt) on
macOS when `--pack sandbox` is present — `cc` / `cx` / `oc` are sandboxed by
default. cmux, bosun, and Herdr launch those same wrappers, so the sandbox
still applies. Linux nodes are a trusted host plus tmux/Herdr; kernel isolation
there is `--pack sandbox-container`. See [`sandboxing.md`](sandboxing.md).

**Herdr's socket under Seatbelt.** The profiles are `(deny default)`, which
blocks AF_UNIX connects too — so a sandboxed agent could not reach the socket
API the section above tells it to use. `strict.sb` and `standard.sb` therefore
allow outbound connections to a subpath of `~/.config/herdr`, covering both
`~/.config/herdr/herdr.sock` and `~/.config/herdr/sessions/<name>/herdr.sock`.
Two honest caveats: if you point `HERDR_SOCKET_PATH` outside that directory the
connect is denied again (move it back, or use `sbx --profile off`), and the
allow is path-scoped only — anything that can reach that path can talk to the
herdr server, which can spawn panes outside the sandbox.

## Notifications — don't watch panes

- Claude Code hooks can POST to [ntfy.sh](https://ntfy.sh) or any webhook when a
  long task finishes — see [`configs/claude/settings.json`](../configs/claude/settings.json).
- [`scripts/notify.sh`](../scripts/notify.sh) is the local macOS banner helper.
- cmux and bosun consume terminal notification escape sequences.
- Herdr's sidebar *is* the attention queue; pair it with ntfy when you are
  away from the TUI.

## Agents driving agents

Herdr's CLI and socket API are the integration surface (spawn panes, wait on
blocked peers). Do not send raw keystrokes into another agent's TUI and hope.
Documented skill install is opt-in and global to *your* agent CLI — this
repo does not write it for you. Upstream: <https://herdr.dev/docs/socket-api/>.
