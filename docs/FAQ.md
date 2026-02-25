# Frequently Asked Questions

> Common questions and solutions for the TUI Development Setup

---

## Installation

### Q: Does this work on Intel Macs?

**Yes.** The setup detects whether you're on Apple Silicon (`/opt/homebrew`) or Intel (`/usr/local`) and configures paths automatically.

### Q: Can I use this on Linux?

**Partially.** The CLI tools work on Linux, but:
- macOS apps (Rectangle, Hammerspoon, Stats) won't install
- Ghostty config is macOS-specific
- Install script needs modification for Linux package managers

### Q: The installer failed. How do I retry?

```bash
# Run with dry-run first to see what would happen
./install.sh --dry-run

# Then run for real
./install.sh
```

Backups are created at `~/.config-backup-TIMESTAMP/` before overwriting.

### Q: How do I update everything?

```bash
# Update all Homebrew packages
brew update && brew upgrade

# Update Neovim plugins
nvim -c 'Lazy update' -c 'quit'

```

---

## Shell & Terminal

### Q: My arrow keys navigate Zellij panes instead of the command line

Press `Ctrl+g` to enter **Locked Mode** - this passes all keys directly to the terminal. Press `Ctrl+g` again to exit.

### Q: Why is my shell slow to start?

Common causes:
1. **nvm** - We lazy-load it, but if you have manual nvm config it may double-load
2. **Too many plugins** - Check what's sourced in `.zshrc`
3. **Slow completions** - Try `compinit -C` for cached completions

Check startup time:
```bash
time zsh -i -c exit
```

### Q: How do I add my own aliases?

Add them to `~/.zshrc.local` - this file is sourced at the end and never overwritten by updates.

### Q: The `z` command doesn't work

`z` is an alias for `zoxide`. It learns from your navigation:
```bash
# First, navigate normally
cd ~/projects/myapp
cd ~/documents/notes

# Then use z
z myapp    # Jumps to ~/projects/myapp
z notes    # Jumps to ~/documents/notes
```

---

## Neovim

### Q: Why is there no AI plugin in Neovim?

**By design.** This setup's philosophy is:
- Neovim stays fast and lightweight
- AI tools run in adjacent Zellij panes
- Multiple AI agents can work in parallel

This avoids the overhead of in-editor AI and lets you use multiple AI tools simultaneously.

### Q: Neovim plugins aren't loading

```bash
# Clear and reinstall
rm -rf ~/.local/share/nvim ~/.local/state/nvim ~/.cache/nvim
nvim
```

LazyVim will reinstall all plugins on next launch.

### Q: How do I add custom plugins?

Create `~/.config/nvim/lua/plugins/custom.lua`:
```lua
return {
  -- Your plugins here
  { "tpope/vim-surround" },
}
```

### Q: LSP isn't working for my language

```bash
# In Neovim, check LSP status
:LspInfo

# Install language server
:Mason
# Search for your language and press i to install
```

---

## Tmux & Claude Agent Teams

### Q: Why is there a tmux config if Zellij is the primary multiplexer?

Claude Code's experimental **agent teams** feature (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`) uses split-pane mode where each teammate gets its own visible pane. This requires **tmux or iTerm2** — Zellij is explicitly unsupported by that feature. So:
- **Zellij** → manual workspace layouts (`ai`, `dev`, `multi`, etc.)
- **tmux** → Claude agent teams split-pane mode (`tai`, `tdev`, etc.)

### Q: How do I use Claude agent teams split-pane mode?

```bash
# 1. Start a tmux session
tai myproject        # nvim + 2 stacked agent panes

# 2. Run Claude with agent teams enabled
CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 claude

# Claude automatically splits tmux panes for each agent
```

### Q: How do I kill all tmux sessions?

```bash
tka              # kill-server (all sessions)
tk [name]        # kill named session
tls              # list sessions
```

### Q: The tmux config isn't loading / colors look wrong

tmux 3.2+ reads from `~/.config/tmux/tmux.conf` via XDG automatically. Older versions need `~/.tmux.conf`. Check your version:

```bash
tmux -V          # should be 3.2+
```

If you're on an older version, symlink the config:
```bash
ln -s ~/.config/tmux/tmux.conf ~/.tmux.conf
```

### Q: tmux functions (`ta`, `tdev`, `tai`) aren't found

The functions live in `~/.zshrc`. If you just installed, source it:

```bash
source ~/.zshrc

# Or sync from repo first:
make update-configs
source ~/.zshrc
```

---

## Zellij

### Q: How do I kill all sessions?

```bash
zk  # Alias for zellij kill-all-sessions
```

### Q: My layout isn't loading

```bash
# Check layout exists
ls ~/.config/zellij/layouts/

# Try loading explicitly
zellij --layout dual
```

### Q: How do I create a custom layout?

1. Copy an existing layout:
   ```bash
   cp ~/.config/zellij/layouts/dual.kdl ~/.config/zellij/layouts/custom.kdl
   ```

2. Edit the KDL file
3. Use it: `zellij --layout custom`

---

## AI CLI Tools

### Q: Which AI tool should I use?

| Tool | Best For |
|------|----------|
| **Claude Code** | Complex coding tasks, large context |
| **OpenCode** | Open-source, customizable |

You can run multiple in different Zellij panes!

---

## Window Management

### Q: Rectangle vs Hammerspoon - which should I use?

- **Rectangle**: Simple, GUI-based, great defaults
- **Hammerspoon**: Programmable, Lua scripting, unlimited customization

We include both - use Rectangle for basics, Hammerspoon for advanced automation.

### Q: How do I customize Hammerspoon?

Edit `~/.hammerspoon/init.lua`, then reload with `Cmd+Option+Ctrl+R`.

---

## Git & GitHub

### Q: Delta diff colors look wrong

Delta uses the terminal theme. Ensure your terminal (Ghostty) is using Tokyo Night theme.

### Q: lazygit keybindings

Press `?` in lazygit to see all keybindings. Key ones:
- `Space` - Stage/unstage
- `c` - Commit
- `P` - Push
- `p` - Pull

---

## Troubleshooting

### Q: Command not found: <tool>

```bash
# Refresh shell
source ~/.zshrc

# Check if installed
brew list | grep <tool>

# Install if missing
brew install <tool>
```

### Q: How do I reset everything?

```bash
# Restore backups (if you have them)
cp -r ~/.config-backup-TIMESTAMP/* ~/

# Or reinstall
./install.sh
```

### Q: Something is broken after an update

```bash
# Check health
make check

# Run full tests
make test

# Validate configs
make validate-configs
```

---

## Performance

### Q: How do I benchmark tool performance?

```bash
# Benchmark any command
hyperfine 'rg pattern' 'grep pattern'

# Shell startup time
hyperfine 'zsh -i -c exit'
```

### Q: Which tools are fastest?

| Task | Tool | Speed vs Traditional |
|------|------|---------------------|
| Search | `rg` | 10-100x faster than grep |
| Find | `fd` | 5-10x faster than find |
| List | `eza` | Similar, but prettier |
| View | `bat` | Slightly slower (highlighting) |

---

## Getting Help

### Q: Where can I get more help?

1. **Check docs:** `ls docs/`
2. **Read cheatsheet:** `glow docs/CHEATSHEET.md`
3. **Tool help:** `<tool> --help`
4. **Man pages:** `man <tool>`
5. **TLDR:** `tldr <tool>` (if installed)

### Q: How do I report issues?

Open an issue on GitHub with:
1. Your macOS version (`sw_vers`)
2. Output of `make check`
3. Relevant error messages
