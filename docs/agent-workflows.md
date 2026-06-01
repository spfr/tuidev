# Agent Workflows

How to run and drive AI coding agents (claude, codex, opencode) with this setup —
locally, in parallel, and from your phone. The CLIs themselves are opt-in
(`./install.sh --pack ai-clis`); the core setup stays CLI-agnostic. The throughline is unchanged
from [`VISION.md`](../VISION.md): **tmux is the durability layer.** Everything
here either runs *inside* tmux or is an optional layer *on top* of it.

## Driving Agents Remotely — Native Remote Control

The biggest 2026 shift: the agent CLIs now ship their own remote control, so you
no longer need an SSH session just to *steer* an agent from your phone.

- **Claude Code Remote Control** — connects `claude.ai/code` and the Claude iOS /
  Android apps to a Claude Code session running on your machine. Your code never
  leaves the machine; only chat messages and tool results cross an encrypted
  bridge (files, MCP servers, env, and project settings stay local). Requires
  Claude Code ≥ v2.1.51 and a Pro / Max / Team / Enterprise plan (API keys are not
  supported). Start a local session, then pick it up from the app or web.
  Docs: <https://code.claude.com/docs/en/remote-control>
- **Codex / others** — third-party mobile control layers cover Codex and more:
  [Tactic Remote](https://clauderc.com/) (Claude / Codex / Amp) and
  [QuivrHQ/247-claude-code-remote](https://github.com/QuivrHQ/247-claude-code-remote)
  (Tailscale + Fly.io).

**When to use which:**

| Goal | Reach for |
|------|-----------|
| Steer one agent from your phone, low friction | Native Remote Control |
| Full terminal: edit files, run anything, non-agent work | SSH + tmux ([`remote.md`](remote.md)) |
| Survive flaky/cellular networks | mosh wrapping tmux ([`remote.md`](remote.md)) |

Remote Control replaces the *"SSH in just to talk to Claude"* case. It does **not**
replace the durable backbone — tmux + Tailscale + mosh still own full terminal
access, non-Claude work, and surviving disconnects.

## Running Agents in Parallel

The shipped, zero-extra-install way is tmux panes:

```bash
agents [name]     # claude | codex, two columns (needs --pack ai-clis)
ai [name]         # nvim + 2 agent panes
ai-triple [name]  # nvim + 3 agent panes
```

These survive disconnects, reattach over SSH, and work identically on Linux. For
heavier multi-agent days, two optional tools layer on top.

### cmux — native macOS terminal for parallel agents (`--pack cmux`)

[cmux](https://github.com/manaflow-ai/cmux) is a Ghostty-based, GPU-accelerated
macOS terminal built specifically for running coding agents side by side: vertical
tabs, notification rings (it picks up OSC 9/99/777 escape sequences and Claude
Code hooks), a built-in browser with Playwright-equivalent automation, and Claude
Code Teams integration. It works with claude, codex, opencode, and any CLI.

```bash
./install.sh --pack cmux     # brew tap manaflow-ai/cmux + cask (macOS 14+)
```

**Trade-off:** cmux is a native macOS GUI app. You gain a slick parallel-agent UX;
you give up tmux's session durability, SSH-reattach, mobile access, and Linux
parity. Treat it as a desktop *complement* to the tmux workflow, not a
replacement. Great at your desk; tmux is still what you reattach to from the train.

### bosun — tmux-native agent orchestrator (`--pack bosun`)

[bosun](https://github.com/yetidevworks/bosun) (Rust + ratatui) lists, previews,
creates, and manages tmux sessions running Claude Code, Codex, or a plain shell
from one TUI — a recent-sessions picker, modal session creation, lifecycle
controls (attach / rename / restart / kill), and push notifications from tmux via
control mode. It runs its sessions on a dedicated `tmux -L bosun` socket, so it
never touches your main tmux state.

```bash
./install.sh --pack bosun     # via Homebrew formula if available, else cargo
```

Because bosun stays inside the terminal and drives tmux, it fits the tmux-primary
thesis directly — it's the orchestration layer that survives disconnects and works
over SSH, unlike a GUI app.

## Sandboxing

However you run them, the AI-CLI wrappers (`--pack ai-clis`) auto-route through
`sbx` (Seatbelt) on macOS when `--pack sandbox` is present — `cc` / `cx` / `oc`
are sandboxed by default. cmux and bosun launch those same wrappers, so the
sandbox still applies. See [`sandboxing.md`](sandboxing.md).

## Notifications

Both the panes workflow and cmux/bosun can surface "agent needs you" signals:

- Claude Code hooks can POST to [ntfy.sh](https://ntfy.sh) or any webhook when a
  long task finishes — see [`configs/claude/settings.json`](../configs/claude/settings.json).
- cmux and bosun additionally consume terminal notification escape sequences, so
  an idle/finished agent shows up natively without extra wiring.
