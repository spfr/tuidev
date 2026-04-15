# Quick Start Guide

5-minute crash course: zero to a working tmux session with Nvim and AI agents.

---

## 1. Install

```bash
git clone https://github.com/spfr/tuidev.git
cd tuidev
./install.sh --profile desktop
source ~/.zshrc
```

The `desktop` profile installs the core, remote, sandbox, and UI packs — everything a macOS developer needs. Other profiles:

| Profile | What you get | Use when |
|---------|--------------|----------|
| `minimal` | core only (Nvim, tmux, shell tooling) | headless box, slow disk |
| `remote`  | core + remote (Tailscale, mosh, SSH) | VPS, Linux server |
| `desktop` | core + remote + sandbox + UI | **recommended** for macOS |
| `full`    | everything (+ extras pack) | kitchen sink |

Add a single pack on top with `--pack NAME` (e.g. `--pack zellij`). See [profiles.md](profiles.md) for the full matrix.

---

## 2. Your First Session

tmux is the session layer. All launchers create a **named** session and re-attach if it already exists.

```bash
work myproject        # bare tmux session named "myproject"
dev                   # 3-column: nvim (55%) | agent (25%) | runner (20%)
ai                    # nvim (60%) + 2 stacked agent panes (40%)
```

Exit with `Ctrl+a d` (detach — session keeps running). Reattach by re-running the same launcher (`work myproject`) — launchers are attach-or-create.

### All session launchers

| Command | Layout |
|---------|--------|
| `work [name]` | bare named session (default: `$PWD` basename) |
| `dev [name]`  | nvim + agent + runner |
| `ai [name]`   | nvim + 2 agents |
| `ai-triple [name]` | nvim + 3 agents |
| `agents [name]` | claude + codex + gemini, one per pane |
| `remote [name]` | minimal layout for mosh/SSH |
| `tls` | list sessions |
| `tk [name]` | kill one session |
| `tka` | kill all (tmux kill-server) |

---

## 3. tmux Keys You Need

Prefix is `Ctrl+a`.

| Keys | Action |
|------|--------|
| `Ctrl+a \|` | split pane vertically |
| `Ctrl+a -` | split pane horizontally |
| `Ctrl+a h/j/k/l` | move between panes |
| `Ctrl+a d` | detach (session survives) |
| `Ctrl+a [` | scroll/copy mode (`q` to exit) |
| `Ctrl+a ?` | list every keybinding |

See [TERMINAL_NAVIGATION.md](TERMINAL_NAVIGATION.md) if arrow keys or Option-word-jump misbehave.

---

## 4. Run an AI Agent in a Sandbox

AI tools write files and run commands. Launch them through `sbx` so they can't escape the project directory:

```bash
sbx -- cc              # Claude Code, sandboxed
sbx -- cx              # Codex CLI, sandboxed
sbx -- oc              # OpenCode, sandboxed
```

On macOS, `sbx` uses Seatbelt (Tier 1) — no extra install. For stricter isolation (network-off, rootless container), see [sandboxing.md](sandboxing.md) for the Podman-based Tier 2 flow.

Run AI agents unsandboxed with `cc`, `cx`, `gem`, `oc` if you need raw access — but prefer `sbx` by default.

---

## 5. Nvim Essentials

Leader key is `Space`. Press and wait to see the menu.

| Keys | Action |
|------|--------|
| `Space f f` | find files |
| `Space f g` | grep across project |
| `Space e`   | file tree |
| `g d`       | go to definition |
| `K`         | hover docs |

Full guide: [NEOVIM_QUICKSTART.md](NEOVIM_QUICKSTART.md).

---

## 6. Daily Flow

```bash
# Morning
work myproject         # reattach or create
z myproject            # jump to project dir (zoxide)

# While working
# - edit in nvim pane
# - talk to an agent in the sbx pane
# - Ctrl+a o to rotate panes, Ctrl+a z to zoom

# End of day
# Ctrl+a d              # detach — session keeps running
```

Next morning: `work myproject` picks up exactly where you left off, even after a reboot of the remote host (as long as tmux server is still up).

---

## Got Stuck?

- Arrow keys or Option misbehaving → [TERMINAL_NAVIGATION.md](TERMINAL_NAVIGATION.md)
- Coming from the old Zellij-first setup → [migration.md](migration.md)
- Want Zellij back → `./install.sh --pack zellij`, then see [ZELLIJ_TROUBLESHOOTING.md](ZELLIJ_TROUBLESHOOTING.md)
- Remote access (phone, iPad, Tailscale) → [remote.md](remote.md)
- Anything else → [FAQ.md](FAQ.md)

---

**You're ready. Run `work` and start coding.**
