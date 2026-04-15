# Frequently Asked Questions

> Common questions and fixes for the TUI Development Setup.

---

## Installation

### Q: Does this work on Intel Macs?

**Yes.** The setup detects Apple Silicon (`/opt/homebrew`) vs Intel (`/usr/local`) and configures paths automatically.

### Q: Can I use this on Linux?

**Yes, for the remote/server profile.** CLI tools, tmux, Nvim, and the sandbox Tier 2 (Podman) all work on Linux. Skip macOS-only packs:

```bash
./install.sh --profile remote
```

Seatbelt (Tier 1 sandbox), Ghostty, Hammerspoon, and Rectangle are macOS-only and ship in the `ui` pack.

### Q: How do I install a minimal profile?

```bash
./install.sh --profile minimal
```

Just the core: Nvim, tmux, zsh, Starship, and the modern CLI tools. Add packs one at a time with `--pack NAME`. See [profiles.md](profiles.md) for the matrix.

### Q: How do I add a specific pack to an existing install?

```bash
./install.sh --pack zellij       # add Zellij on top of whatever you have
./install.sh --pack sandbox      # add the Podman-based Tier 2 sandbox
```

Packs are idempotent.

### Q: The installer failed. How do I retry?

```bash
./install.sh --dry-run --profile desktop   # see what it would do
./install.sh --profile desktop             # run for real
```

Backups land at `~/.config-backup-TIMESTAMP/`.

### Q: How do I update everything?

```bash
make update            # interactive
make update-all        # non-interactive
make update-check      # preview only
```

---

## Shell & Terminal

### Q: Why is my shell slow to start?

1. **nvm** — we lazy-load it; remove any manual `nvm.sh` source in `~/.zshrc.local`.
2. **Too many plugins** — audit what's sourced.
3. **Slow completions** — `compinit -C` caches.

Measure:

```bash
time zsh -i -c exit
```

### Q: How do I add my own aliases?

Edit `~/.zshrc.local`. Sourced last, never overwritten.

### Q: The `z` command doesn't work

`z` is zoxide. It learns from your `cd` history:

```bash
cd ~/projects/myapp       # teach it once
z myapp                   # jump there forever
```

---

## Sessions & tmux

### Q: Why tmux (not Zellij)?

- **Durability**: tmux sessions survive SSH disconnects and terminal crashes. Critical for remote work over flaky connections (iOS hotspot, mosh, long-running agents).
- **Remote parity**: every VPS, Linux server, and SSH host already has tmux; no extra install for remote sessions.
- **Agent integration**: Claude Code's agent teams split-pane mode targets tmux. iTerm2 is supported too, but tmux works in any terminal.
- **Ubiquity**: if you already know tmux, your muscle memory carries over to any other machine.

Zellij is still shipped as an opt-in pack (`./install.sh --pack zellij`) for users who prefer its workspace model.

### Q: How do I launch a session?

All launchers create a **named** session; calling them again reattaches.

```bash
work myproject        # bare session
dev                   # nvim | agent | runner (3 columns)
ai                    # nvim + 2 agent panes
ai-triple             # nvim + 3 agent panes
agents                # claude + codex + gemini, one per pane
remote                # minimal layout for mosh/SSH
```

Management: `tls` (list), `tk NAME` (kill one), `tka` (kill server).

### Q: Where did the old `ai` command go?

It still works — it just runs tmux now instead of Zellij. Same for `dev`, `ai-triple`, `fullstack` (where applicable), `remote`. The `t*` aliases (`ta`, `tdev`, `tai`, ...) remain available as the explicit tmux-named counterparts.

Coming from the pre-pivot setup? See [migration.md](migration.md).

### Q: tmux colors look wrong / config not loading

tmux 3.2+ auto-reads `~/.config/tmux/tmux.conf`. Older versions:

```bash
tmux -V                                              # check version
ln -s ~/.config/tmux/tmux.conf ~/.tmux.conf          # fallback for <3.2
```

### Q: Claude agent teams split-pane mode?

```bash
ai myproject
claude --teammate-mode tmux
```

In-process mode (default `claude`) works in any terminal — use `Shift+Down` to cycle teammates.

---

## Sandboxing

### Q: How do I turn off the sandbox?

Just call the CLI directly without `sbx`:

```bash
cc                    # raw, no sandbox
sbx -- cc             # Seatbelt (Tier 1)
```

There's no global on/off — sandboxing is per-invocation.

### Q: Seatbelt vs Podman — which tier?

| Tier | Tool | OS | Good for |
|------|------|----|----|
| 1 | Seatbelt (`sandbox-exec`) | macOS | default; scoped FS, network allowed |
| 2 | Podman (rootless) | macOS + Linux | stricter; network off, read-only host |

Full details and the policy file layout: [sandboxing.md](sandboxing.md).

### Q: The sandbox blocked something I need

Either switch tiers (`sbx --tier 1 -- ...`) or edit the policy at `~/.config/sandbox/<profile>.sb` (Seatbelt) or the `Containerfile` (Podman). Don't run agents unsandboxed as a workaround — scope the policy instead.

---

## Zellij (opt-in pack)

### Q: I want Zellij back

```bash
./install.sh --pack zellij
source ~/.zshrc
```

Launchers: `zdev`, `zai`, `zai-triple`, `zfullstack`, `zmulti`, `zremote`, `zwork`. Keybindings, prefix-mode conflicts, and layout files: [ZELLIJ_TROUBLESHOOTING.md](ZELLIJ_TROUBLESHOOTING.md).

### Q: My old Zellij layout isn't loading

```bash
ls ~/.config/zellij/layouts/
zellij --layout dual
```

If the `zellij/` dir is missing, you're on a profile without the pack — install it: `./install.sh --pack zellij`.

---

## Neovim

### Q: Why is there no AI plugin in Neovim?

**By design.** Nvim stays fast; AI agents run in adjacent tmux panes (ideally sandboxed via `sbx`). Multiple agents in parallel with no editor overhead.

### Q: Neovim plugins broken

```bash
rm -rf ~/.local/share/nvim ~/.local/state/nvim ~/.cache/nvim
nvim       # LazyVim reinstalls everything
```

### Q: LSP isn't working for my language

```vim
:LspInfo
:Mason         " search language, press i to install
```

### Q: How do I add custom plugins?

Create `~/.config/nvim/lua/plugins/custom.lua`:

```lua
return {
  { "tpope/vim-surround" },
}
```

---

## AI CLI Tools

### Q: Which AI tool should I use?

| Tool | Alias | Best for |
|------|-------|----------|
| Claude Code | `cc` | complex tasks, large context, agent teams |
| Codex | `cx` | OpenAI-flavored workflows |
| Gemini | `gem` | long-context Google workflows |
| OpenCode | `oc` | open-source, multi-model |

Run multiple in parallel via `ai` or `agents`. Prefer `sbx -- <alias>` over raw invocation.

---

## Git

### Q: Delta diff colors look wrong

Delta picks up the terminal theme. Ensure Ghostty (or your terminal) is on Tokyo Night.

### Q: lazygit keybindings?

Press `?` inside lazygit. Main ones: `Space` stage, `c` commit, `P` push, `p` pull.

---

## Troubleshooting

### Q: Command not found

```bash
source ~/.zshrc
brew list | grep <tool>
brew install <tool>
```

### Q: Something broke after an update

```bash
make check
make test
make validate-configs
```

### Q: How do I reset everything?

```bash
cp -r ~/.config-backup-TIMESTAMP/* ~/       # restore
./install.sh --profile desktop              # or reinstall
```

---

## Remote Access

### Q: How do I work from my phone / iPad?

See [remote.md](remote.md) — Tailscale, mosh, iOS SSH clients, and named tmux sessions for iffy connections.

```bash
remote myproject      # minimal layout, optimized for mobile
```

---

## Getting Help

- Full docs: `ls docs/`
- Tool-specific: `<tool> --help`, `tldr <tool>`
- Report issues on GitHub with: `sw_vers`, `make check` output, relevant logs.
