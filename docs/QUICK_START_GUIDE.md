# Quick Start Guide

Get productive with your TUI development environment in 5 minutes.

---

## 1. Start Your First AI Session

The killer feature - nvim + AI agent terminals side by side:

```bash
ai
```

This opens:
- **Left (60%)**: Neovim editor
- **Right (40%)**: Two terminal panes for AI tools (opencode, claude)

### Available Sessions

| Command | Layout | Use Case |
|---------|--------|----------|
| `ai` | nvim + 2 agents | Default - most common |
| `ai-single` | nvim + 1 agent | Lighter workload |
| `ai-triple` | nvim + 3 agents | Heavy AI work |
| `fullstack` | 5 tabs | Full-stack development |
| `multi` | Dev + Monitor + Git | Complete workflow |
| `remote` | nvim + tunnel | Remote access |
| `dev` | Classic layout | No AI focus |

---

## 2. Navigate Zellij

| Key | Action |
|-----|--------|
| `Alt+h/j/k/l` | Move between panes |
| `Alt+n` | New pane |
| `Ctrl+t` then `n` | New tab |
| `Ctrl+t` then `1-9` | Switch to tab |
| `Alt+p` then `x` | Close pane |
| `Ctrl+q` | Quit zellij |

**Detach & Resume:**
```bash
# Detach (session keeps running)
Ctrl+o, then d

# Resume later
zellij list-sessions
zellij attach <session-name>
```

---

## 3. Master Fuzzy Finding

The most productivity-boosting shortcuts:

| Key | Action |
|-----|--------|
| `Ctrl+T` | Find files anywhere |
| `Ctrl+R` | Search command history |
| `Alt+C` | Jump to directory |

**In fzf:**
- Type to filter
- Arrow keys to navigate
- `Enter` to select
- `Esc` to cancel

---

## 4. Smart Navigation (zoxide)

Stop typing long paths:

```bash
# Visit directories normally first
cd ~/projects/my-app
cd ~/work/api

# Later, jump with partial names
z my-app    # → ~/projects/my-app
z api       # → ~/work/api
z proj api  # → multiple matches? picks best
```

---

## 5. Neovim Essentials

**Leader key = `Space`** - press and wait to see all commands.

| Key | Action |
|-----|--------|
| `Space f f` | Find files |
| `Space f g` | Search in files (grep) |
| `Space e` | File explorer |
| `g d` | Go to definition |
| `K` | Hover docs |
| `Space c a` | Code actions |

See [NEOVIM_QUICKSTART.md](NEOVIM_QUICKSTART.md) for complete guide.

---

## 6. Git with LazyGit

```bash
lg    # or `lazygit`
```

| Key | Action |
|-----|--------|
| `j/k` | Navigate |
| `Space` | Stage/unstage |
| `c` | Commit |
| `P` | Push |
| `p` | Pull |
| `?` | Help |
| `q` | Quit |

---

## 7. Modern CLI Tools

Your commands got superpowers:

```bash
# File listing (eza)
ls          # With icons
ll          # Long + git status
lt          # Tree view

# File viewing (bat)
cat file.js # Syntax highlighted

# Search (ripgrep)
rg "TODO"              # Search all files
rg "bug" --type py     # Only Python files

# Find files (fd)
fd "*.js"              # Find JS files
fd -t d                # Find directories

# Markdown (glow)
glow README.md         # Beautiful rendering
```

---

## 8. Window Management (Rectangle)

| Shortcut | Action |
|----------|--------|
| `⌃⌥ ←` | Left half |
| `⌃⌥ →` | Right half |
| `⌃⌥ Enter` | Maximize |
| `⌃⌥ C` | Center |

---

## Daily Workflow

### Start Work
```bash
ai                    # Start AI session
z myproject           # Jump to project
```

### During Work
- Edit in nvim (left pane)
- Ask AI questions in right panes (opencode, claude)
- `Ctrl+T` to find any file
- `Alt+h/l` to switch panes
- `lg` for git operations

### End of Day
```bash
Ctrl+o, d             # Detach (session keeps running)
```

### Next Day
```bash
zellij attach <name>  # Resume exactly where you left
```

---

## Useful Aliases

```bash
v           # nvim
lg          # lazygit
gs          # git status
..          # cd ..
reload      # source ~/.zshrc
zk          # kill all zellij sessions
tls         # list tmux sessions
tka         # kill all tmux sessions
```

---

## 9. Tmux for Claude Agent Teams

tmux is required for Claude Code's experimental **agent teams split-pane mode**, where each teammate gets its own visible pane. Zellij is unsupported for this feature.

```bash
# Start an AI layout in tmux
tai myproject

# Inside the session, enable agent teams
CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 claude
# Claude automatically splits tmux panes for each agent
```

**Key bindings** (prefix = `Ctrl+a`):

| Key | Action |
|-----|--------|
| `Ctrl+a \|` | Split pane right |
| `Ctrl+a -` | Split pane down |
| `Ctrl+a h/j/k/l` | Navigate panes |
| `Ctrl+a d` | Detach session |
| `Ctrl+a r` | Reload config |

**Session commands:**
```bash
ta [name]     # Attach or create session
tdev          # 3-column: nvim | agent | runner
tai           # nvim + 2 stacked agents (default for agent teams)
tls           # List sessions
tka           # Kill all sessions
```

---

## Getting Help

```bash
tldr <command>        # Quick examples
<command> --help      # Built-in help
```

**In Zellij:** `Alt+p` then `?`
**In LazyGit:** `?`
**In Neovim:** `Space` then wait

---

## Next Steps

1. [CHEATSHEET.md](CHEATSHEET.md) - All keybindings (print this!)
2. [NEOVIM_QUICKSTART.md](NEOVIM_QUICKSTART.md) - Full nvim guide
3. [REMOTE_SESSIONS.md](REMOTE_SESSIONS.md) - Work from phone/tablet

---

**You're ready! Run `ai` and start coding.**
