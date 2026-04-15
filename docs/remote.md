# Remote Workflow

## Architecture

The host provides terminal, tmux, editor, and SSH. You reconnect from any client and run `tmux attach`. The core workflow survives disconnects because tmux does — not because of any magic layer above it. Everything else (Tailscale, mosh, mobile clients) is transport; tmux is the durability layer. See [`VISION.md`](../VISION.md) §"Remote Access Strategy" for the rationale.

## Primary Path: Tailscale SSH + tmux

Bring the node online:

```bash
tailscale up
tailscale status           # confirm node is listed
```

From a client on the same tailnet:

```bash
ssh devbox                 # or tailscale ssh devbox
tmux attach -t main        # reattach to the default session
```

Create a named session for a project (requires the updated tmux wrappers in `~/.zshrc`):

```bash
work myproject             # creates/attaches tmux session "myproject"
dev myproject              # 3-column dev layout: nvim | agent | runner
ai myproject               # nvim + 2 agent panes
```

Detach with `Ctrl-b d`. The session keeps running. Reconnect from a different laptop, phone, or network and `tmux attach -t myproject` picks up exactly where you left off.

## Why Tailscale SSH over Raw SSH

- ACL policy lives in the tailnet, not in `authorized_keys` files scattered across hosts.
- Check mode can force re-auth / SSO for sensitive sessions.
- Single-sign-on via your IdP; no key sprawl to rotate.
- Device posture is part of the identity — a revoked node loses access immediately.

Raw SSH still works and is fine as a fallback.

## mosh — Optional Upgrade

Use mosh when:

- You're on a mobile network or flaky Wi-Fi.
- You roam between networks (coffee shop → home → tether).
- You close the laptop lid frequently and want sessions to feel live on resume.

Install:

```bash
./install.sh --pack mosh
```

Connect:

```bash
mosh devbox -- tmux attach -t main
```

Gotchas:

- Scrollback is only partially synchronized. Keep real history in tmux's copy mode, not in the terminal scrollback.
- mosh needs UDP 60000–61000 open on the server's firewall.
- mosh does not survive server reboot; tmux does. Always wrap mosh around tmux.

## tmux is the Durability Layer

The setup ships:

- `tmux-continuum` — auto-saves session state every 15 minutes.
- `tmux-resurrect` — restores state on tmux start.

Session state persists across server reboots, SSH disconnects, and client changes. `tmux attach` from any client reconnects. A dead network doesn't kill your work; it interrupts your view of it.

Narrow-terminal tip: the `remote` wrapper (part of the tmux inversion, see [`migration.md`](migration.md)) uses `scripts/layout-remote.sh` for a two-pane layout that fits phone-sized terminals.

```bash
remote myproject
```

## Mobile (iOS / iPadOS)

- **Blink Shell** — native iOS/iPadOS SSH + mosh client.
- **Termius** — cross-platform SSH client with sync.

Both work. Neither is recommended over the other; pick by UI preference and pricing model.

## Push Notifications (Optional)

Claude Code hooks can POST to [ntfy.sh](https://ntfy.sh) (or any webhook) when a long agent task finishes, so you don't have to keep the session foregrounded on mobile. See [`configs/claude/settings.json`](../configs/claude/settings.json) for the hook schema; the Anthropic docs cover the event payload in full.

## Anti-Patterns

- Don't tunnel with Cloudflared by default. It's a fallback for when Tailscale genuinely isn't an option, not a primary transport.
- Don't hand-roll SSH keys and `authorized_keys` rotation when Tailscale SSH already owns the ACL layer.
- Don't rely on `screen`. tmux is the standard; tmux is what `tmux-continuum` / `tmux-resurrect` / the tmux wrappers target.
- Don't run agents against the host filesystem over SSH without a sandbox. See [`sandboxing.md`](sandboxing.md).
