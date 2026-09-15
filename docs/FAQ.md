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

`--core` uses Homebrew when it is present and falls back to `apt-get` when it is
not — which is what makes `minimal` / `remote` work on arm64 Debian (a Raspberry
Pi, say), where Homebrew has no build at all. Core probes each package against
your release rather than assuming, so the split adapts as distros move. At the
time of writing, Debian 12 bookworm's apt supplied 14 of the 20 core tools;
`eza`, `starship`, `lazygit`, `git-delta`, `zsh-completions` and `yq` were
skipped with a link to each project's install page. (Debian's `yq`
is a different program — a Python jq wrapper — so core deliberately declines it.)
Debian renames two binaries; core symlinks `fdfind` → `fd` and `batcat` → `bat`
into `~/.local/bin` so the aliases and docs work unchanged. If apt needs a
password and passwordless `sudo` isn't set up, core prints the exact command to
run instead of hanging on a prompt. `--pack herdr` installs Herdr only when
Homebrew has the formula; without brew it prints the official installer command
(`curl -fsSL https://herdr.dev/install.sh | sh`, binary lands in `~/.local/bin`)
for you to run yourself, then re-run the pack to get the config. Bind real hostnames in
`~/.ssh/config.local`, not in this repo. See [inspiration.md](inspiration.md)
and [agent-workflows.md](agent-workflows.md).

For the 5 tools apt can't supply on arm64 Debian (`eza`, `starship`,
`lazygit`, `git-delta`, `zsh-completions` — a Raspberry Pi, say), the
recommended pattern is the same manual one used for the Herdr fallback above:
grab the `aarch64`/`arm64` binary asset from each project's GitHub Releases
page and drop it straight into `~/.local/bin`, no pipe-to-shell needed. Note
that `~/.local/bin` only lands on `PATH` for interactive shells (`.zshrc`) —
a non-interactive SSH session (e.g. a script run via `ssh host 'cmd'`) won't
see it; see [agent-workflows.md](agent-workflows.md) for that distinction.

### Q: How do I install a minimal profile?

```bash
./install.sh --profile minimal
```

Just the core: Nvim, tmux, zsh, Starship, and the modern CLI tools. Add packs one at a time with `--pack NAME`. See [profiles.md](profiles.md) for the matrix.

### Q: How do I add a specific pack to an existing install?

```bash
./install.sh --sandbox                # Seatbelt profiles + the `sbx` wrapper (Tier 1)
./install.sh --pack sandbox-container # VM-backed isolation (Tier 2): Apple container → podman → docker
./install.sh --pack ai-clis           # cc/cx/oc wrappers + adopt-existing CLI configs
```

Packs are idempotent. On a machine that already has tuidev, re-running
`install.sh` applies any pending one-shot migrations before the packs run — see
[updating.md](updating.md).

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

### Q: Ghostty tabs broke after upgrading to macOS 27

Stable Ghostty 1.3.1 predates macOS 27: with `macos-titlebar-style = tabs` the
tab strip collapses into a tiny box beside the `+` button. The fix
(ghostty-org/ghostty#13069) is on the tip channel only until 1.4.0 ships. Two
ways out:

1. **Stay on stable** — the shipped config now defaults to
   `macos-titlebar-style = transparent`, whose native tab bar lays out
   correctly. `make update-configs` re-applies it; restart Ghostty.
2. **Get titlebar tabs back** — add `auto-update-channel = tip` to
   `~/.config/ghostty/config` (outside the managed block), set
   `macos-titlebar-style = tabs`, fully quit and relaunch, accept the update.
   Or swap casks: `brew uninstall --cask ghostty && brew install --cask ghostty@tip`.
   Known cosmetic leftover on 27: the tab strip renders in the system glass
   material rather than the terminal background (#14103).

Tracking issue for the public-release status: ghostty-org/ghostty#13070.

### Q: How do I add my own aliases?

Edit `~/.zshrc.local`. Sourced last, never overwritten.

### Q: Where do personal SSH hosts / LAN names go?

Not in this repo. Put `Host` stanzas in `~/.ssh/config.local`. The shipped SSH
snippet `Include`s `~/.ssh/config.local*` (glob, so a missing file is ignored).
The block opens with `Match all` so the `Include` is unconditional: it is
appended to whatever `~/.ssh/config` you already had, and without that reset a
trailing `Host` stanza of yours would scope the `Include` to just that host.
Because the block is appended, your own stanzas are read first and win on
conflicts (ssh takes the first value for each option).
You can also put hosts *outside* the tuidev managed block in `~/.ssh/config`.
The gitignore already drops `*.local` files in a clone. Published docs use
generic names (`devbox`, `workbox`, `always-on`) only.

### Q: The `z` command doesn't work

`z` is zoxide. It learns from your `cd` history:

```bash
cd ~/projects/myapp       # teach it once
z myapp                   # jump there forever
```

---

## Sessions & tmux

### Q: How do I launch a session?

All launchers create a **named** session; calling them again reattaches.

```bash
work myproject        # bare session
dev                   # nvim | agent | runner (3 columns)
ai                    # nvim + 2 agent panes
ai-triple             # nvim + 3 agent panes
agents                # claude + codex, one per pane
remote                # minimal layout for mosh/SSH
```

Management: `tls` (list), `tk NAME` (kill one), `tka` (kill server).

### Q: Where did the old `ai` command go?

It still works — it runs tmux. Same for `dev`, `ai-triple`, `fullstack` (where applicable), `remote`. The `t*` aliases (`ta`, `tdev`, `tai`, ...) remain available as the explicit tmux-named counterparts.


### Q: tmux colors look wrong / config not loading

tmux 3.2+ auto-reads `~/.config/tmux/tmux.conf`. Older versions:

```bash
tmux -V                                              # check version
ln -s ~/.config/tmux/tmux.conf ~/.tmux.conf          # fallback for <3.2
```

### Q: Claude agent teams split-pane mode?

Agent teams are still experimental; the shipped `configs/claude/settings.json`
enables them (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`) and sets
`"teammateMode": "auto"`, which opens one tmux pane per teammate whenever `cc`
already runs inside tmux and stays in-process otherwise:

```bash
ai myproject          # tmux layout first …
cc                    # … then teammates get their own panes
cc --teammate-mode in-process   # one session only
```

In-process mode works in any terminal (arrow keys select a teammate in the
agent panel, Enter opens it). Split panes need tmux or iTerm2 — not Ghostty's
native splits. Side effect worth knowing: with teams enabled, a *named*
subagent launches as a teammate; set the variable to `0` to get plain
subagents back.

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
| OpenCode | `oc` | open-source, multi-model |

Aliases come from the opt-in `--pack ai-clis`. (Gemini CLI is deprecated upstream — successor: Antigravity, `agy`; add your own wrapper if you use it.) Run multiple in parallel via `ai` or `agents`. The wrappers already route through `sbx`; see [sandboxing.md](sandboxing.md#sbx-vs-claude-codes-built-in-sandbox--pick-one) before enabling Claude's own `/sandbox` — Seatbelt does not nest, so it is one or the other.

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
