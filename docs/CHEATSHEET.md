# Cheatsheet

Quick reference for all tools and keybindings. Print this!

---

## macOS Terminal Navigation (Ghostty + Zellij)

### Command Line Navigation in Shell
| Key | Action |
|-----|--------|
| `Home` / `fn+←` | Beginning of line |
| `End` / `fn+→` | End of line |
| `Option+←` | Back one word |
| `Option+→` | Forward one word |
| `Fn+Delete` | Forward delete |
| `Delete` | Backspace |

### Zellij Terminal Passthrough
**Important:** When you need full shell key control:
| Key | Mode |
|-----|------|
| `Ctrl+g` | **Locked Mode** - Pass ALL keys to terminal (including arrow keys) |

### Zellij vs Shell Navigation
| Situation | Solution |
|-----------|----------|
| Need to use arrow keys in shell | Press `Ctrl+g` (Locked mode) |
| Need to navigate between panes | Use `Alt+h/j/k/l` (Normal mode) |
| Arrow keys not working | You're in a Zellij mode, press `Esc` or `Ctrl+g` |

### Common Issues Fixed
✓ **Arrow keys not navigating command line** → Use `Ctrl+g` for Locked mode
✓ **fn+Delete activating caps lock** → Fixed in Ghostty config
✓ **Option+Arrow not working** → Fixed in Ghostty config
✓ **Home/End keys not working** → Mapped to Ctrl+A / Ctrl+E equivalents

---

## Zellij (Terminal Multiplexer)

### Quick Navigation (Always Available)
| Key | Action |
|-----|--------|
| `Alt+n` | New pane |
| `Alt+h` | Focus left |
| `Alt+j` | Focus down |
| `Alt+k` | Focus up |
| `Alt+l` | Focus right |
| `Alt+=` | Increase pane size |
| `Alt+-` | Decrease pane size |

### Mode Switching
| Key | Mode |
|-----|------|
| `Alt+p` | **Pane** - Manage panes |
| `Ctrl+t` | **Tab** - Manage tabs |
| `Ctrl+s` | **Scroll** - Scroll and search |
| `Ctrl+o` | **Session** - Session management |
| `Ctrl+g` | **Locked** - Pass all keys to terminal |
| `Ctrl+q` | Quit |

### Pane Mode (`Alt+p`)
| Key | Action |
|-----|--------|
| `n` | New pane |
| `d` | Split down |
| `r` | Split right |
| `x` | Close pane |
| `f` | Fullscreen |
| `w` | Float |
| `h/j/k/l` | Navigate |

### Tab Mode (`Ctrl+t`)
| Key | Action |
|-----|--------|
| `n` | New tab |
| `x` | Close tab |
| `r` | Rename |
| `h/l` | Previous/next |
| `1-9` | Go to tab |

### Layouts
```bash
zellij --layout dev          # Editor + terminal
zellij --layout multi-agent  # AI workflows
zellij --layout fullstack    # Frontend + backend
```

### Sessions
```bash
zellij --session NAME        # Start/attach
zellij list-sessions         # List all
zellij attach NAME           # Attach
zellij kill-session NAME     # Kill
# Ctrl+o, d                  # Detach
```

### Quick Session Functions (Custom)

```bash
# AI Development Sessions (Zellij)
ai                # Dual agents (nvim + 2 terminals) - DEFAULT
ai-single         # Single agent (nvim + 1 terminal)
ai-triple         # Triple agents (nvim + 3 terminals)
multi             # Multi-agent with monitoring tabs
fullstack         # Full-stack dev (5 tabs)
remote            # Remote access session

# General Development (Zellij)
dev               # Classic dev session (nvim + terminal)
zk                # Kill all zellij sessions
```

---

## Tmux (Agent Teams Companion)

Zellij is primary for manual layouts. Use tmux when you need **Claude agent teams split-pane mode** — Zellij is unsupported by that feature.

### Prefix Key: `Ctrl+a`

### Pane Management
| Key | Action |
|-----|--------|
| `Ctrl+a \|` | Split vertically (new pane right) |
| `Ctrl+a -` | Split horizontally (new pane below) |
| `Ctrl+a h/j/k/l` | Navigate between panes (vi-style) |
| `Ctrl+a H/J/K/L` | Resize pane |
| `Ctrl+a x` | Kill current pane |
| `Ctrl+a z` | Toggle pane zoom (fullscreen) |

### Windows & Sessions
| Key | Action |
|-----|--------|
| `Ctrl+a c` | New window |
| `Ctrl+a 1-9` | Switch to window |
| `Ctrl+a ,` | Rename window |
| `Ctrl+a $` | Rename session |
| `Ctrl+a d` | Detach from session |
| `Ctrl+a r` | Reload config |

### Copy Mode (vi)
| Key | Action |
|-----|--------|
| `Ctrl+a [` | Enter copy mode |
| `v` | Begin selection |
| `y` | Copy to clipboard (pbcopy) |
| `Ctrl+v` | Rectangle selection |
| `q` / `Esc` | Exit copy mode |

### Session Functions (Custom)
```bash
# Start/attach
ta [name]         # Attach or create bare session (default: $PWD basename)

# Layout sessions
tdev [name]       # 3-column: nvim (55%) | agent (25%) | runner (20%)
tai [name]        # AI layout: nvim (60%) + 2 stacked agents (40%)
tai-triple [name] # AI triple: nvim (55%) + 3 stacked agents (45%)

# Management
tls               # List all sessions
tk [name]         # Kill named session
tka               # Kill all sessions
```

### Claude Agent Teams
```bash
# Start tmux session, then run Claude with split-pane mode
tai myproject
CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 claude
```

---

## fzf (Fuzzy Finder)

### Shell Integration
| Key | Action |
|-----|--------|
| `Ctrl+T` | Find files → insert path |
| `Ctrl+R` | Search history |
| `Alt+C` | Find directories → cd |

### Inside fzf
| Key | Action |
|-----|--------|
| `↑/↓` or `Ctrl+j/k` | Navigate |
| `Enter` | Select |
| `Tab` | Mark multiple |
| `Ctrl+C` / `Esc` | Cancel |

---

## File Managers

### nnn (Fastest, minimal)
```bash
n          # nnn with cd on quit (alias)
nnn        # Regular nnn
```

### yazi (Modern, async)
```bash
y          # Launch yazi
```

### broot (Directory navigator)
```bash
br         # Launch broot (great for large directories)
```

### Navigation
| Key | Action |
|-----|--------|
| `↑/↓` or `k/j` | Navigate |
| `Enter` | Open file/dir |
| `q` | Quit |
| `Esc` | Go up |
| `.` | Toggle hidden |
| `/` | Search |
| `?` | Help |

### Common Actions
| Key | Action |
|-----|--------|
| `Space` | Select |
| `d` | Delete |
| `y` | Copy |
| `x` | Move |
| `r` | Rename |
| `n` | New file |
| `Ctrl+r` | Sort |

### Integration
- Press `Enter` on a directory to cd there on exit
- Use `p` to preview files
- Supports plugins and scripting

---

## lazydocker (Docker TUI)

### Launch
```bash
ld            # lazydocker alias
lazydocker
```

### Navigation
| Key | Action |
|-----|--------|
| `q` | Quit |
| `1-5` | Jump to panel |
| `h/j/k/l` | Navigate |
| `Enter` | Select |

### Common Actions
| Key | Action |
|-----|--------|
| `Ctrl+u` | Create service |
| `Ctrl+d` | Remove service |
| `Ctrl+s` | Start |
| `Ctrl+p` | Pause |
| `Ctrl+x` | Stop |
| `r` | Restart |
| `e` | View logs |
| `c` | Commit |
| `b` | Build |
| `[` / `]` | Previous/next service |

---

## k9s (Kubernetes TUI)

### Launch
```bash
k9s
```

### Navigation
| Key | Action |
|-----|--------|
| `q` | Quit |
| `:ns` | Switch namespace |
| `:ctx` | Switch context |
| `/` | Filter |
| `Esc` | Clear filter |
| `Ctrl+d` | Delete resource |

### Common Actions
| Key | Action |
|-----|--------|
| `s` | Shell into pod |
| `l` | View logs |
| `e` | Edit resource |
| `y` | YAML output |
| `v` | View details |
| `Ctrl+f` | Port forward |

---

## lazygit (Git TUI)

### Launch
```bash
lg
```

### Navigation
| Key | Action |
|-----|--------|
| `h/j/k/l` | Navigate |
| `1-5` | Jump to panel |
| `?` | Help |
| `q` | Quit |

### Common Actions
| Key | Action |
|-----|--------|
| `Space` | Stage/unstage |
| `a` | Stage all |
| `c` | Commit |
| `P` | Push |
| `p` | Pull |
| `e` | Edit file |
| `d` | Discard |

---

## Neovim

### Basic Movement
| Key | Action |
|-----|--------|
| `h/j/k/l` | Left/down/up/right |
| `w` | Next word |
| `b` | Previous word |
| `e` | Next word end |
| `0` | Start of line |
| `$` | End of line |
| `gg` | Start of file |
| `G` | End of file |
| `:{n}` | Go to line n |

### Editing
| Key | Action |
|-----|--------|
| `i` | Insert before cursor |
| `a` | Insert after cursor |
| `I` | Insert at line start |
| `A` | Insert at line end |
| `o` | New line below |
| `O` | New line above |
| `Esc` | Normal mode |
| `x` | Delete char |
| `dw` | Delete word |
| `dd` | Delete line |
| `cw` | Change word |
| `cc` | Change line |
| `yy` | Yank line |
| `p` | Paste after |
| `P` | Paste before |
| `u` | Undo |
| `Ctrl+r` | Redo |

### Visual Mode
| Key | Action |
|-----|--------|
| `v` | Visual mode |
| `V` | Visual line |
| `Ctrl+v` | Visual block |

### Files & Buffers
| Key | Action |
|-----|--------|
| `:w` | Save |
| `:q` | Quit |
| `:wq` | Save & quit |
| `:q!` | Quit without save |
| `:e file` | Open file |
| `:ls` | List buffers |
| `:b {n}` | Go to buffer n |
| `:bd` | Close buffer |

### Windows & Tabs
| Key | Action |
|-----|--------|
| `:split` or `Ctrl+s` | Horizontal split |
| `:vsplit` or `Ctrl+v` | Vertical split |
| `Ctrl+w h/j/k/l` | Navigate windows |
| `Ctrl+w c` | Close window |
| `:tabnew` | New tab |
| `gt` | Next tab |
| `gT` | Prev tab |

### Search & Replace
| Key | Action |
|-----|--------|
| `/pattern` | Search forward |
| `?pattern` | Search backward |
| `n` | Next match |
| `N` | Previous match |
| `*` | Search word under cursor |
| `:%s/old/new/g` | Replace all |

### LSP (Language Server)
| Key | Action |
|-----|--------|
| `gd` | Go to definition |
| `gr` | Go to references |
| `gi` | Go to implementation |
| `K` | Hover docs |
| `<leader>rn` | Rename |
| `<leader>ca` | Code actions |
| `<leader>fm` | Format |
| `[d` / `]d` | Prev/next diagnostic |

### Telescope (Fuzzy Finder)
| Key | Action |
|-----|--------|
| `<leader>ff` | Find files |
| `<leader>fg` | Live grep |
| `<leader>fb` | Find buffers |
| `<leader>fh` | Find help |
| `<leader>fs` | Grep string |

### File Explorer (nvim-tree)
| Key | Action |
|-----|--------|
| `<leader>e` | Toggle explorer |
| `o` / `Enter` | Open file |
| `a` | Create file/folder |
| `d` | Delete |
| `r` | Rename |

### Leader Keybindings
| Key | Action |
|-----|--------|
| `<leader>ww` | Save |
| `<leader>qq` | Quit all |

---

## System Info & Monitoring

### fastfetch (System Info)
```bash
sys           # fastfetch alias
fastfetch     # Show system info
```

### ncdu (Disk Usage)
```bash
ncdu          # Interactive disk usage
ncdu /path    # Specific path
```

### bandwhich (Network Monitor)
```bash
sudo bandwhich    # Show bandwidth by process
```

### bottom (System Monitor)
```bash
btm           # System monitor alias
btm --color   # Color mode
```

---

## Modern CLI Commands

### File Listing (eza)
```bash
ls       # Icons
ll       # Long + git
la       # All files
lt       # Tree view
```

### File Viewing (bat)
```bash
cat file.js       # Syntax highlighting
bat -n file.js    # With line numbers
bat -A file.txt   # Show whitespace
```

### Searching (ripgrep)
```bash
rg "pattern"              # Search all files
rg "pattern" -i           # Case insensitive
rg "TODO" --type js       # Only JS files
rg "bug" -A 3 -B 3        # Context lines
rg "func" -l              # Files only
```

### Finding Files (fd)
```bash
fd pattern           # Find files
fd -e js             # By extension
fd -t d              # Directories only
fd -H pattern        # Include hidden
```

### Navigation (zoxide)
```bash
z partial-name       # Jump to directory
z -                  # Previous directory
zi                   # Interactive selection
```

### Markdown Viewing
```bash
glow README.md       # View markdown with glow
glow -p              # Render and open in pager
mdp README.md       # Preview markdown (glow or bat fallback)
mde README.md       # Open in nvim
```

### Remote Tunneling
```bash
tunnel            # Start SSH tunnel (cloudflared or ngrok)
tunnel 3000       # Tunnel specific port
```

---

## Hammerspoon (macOS Automation)

### Reload Config
| Shortcut | Action |
|----------|--------|
| `⌘⌥⌃ R` | Reload Hammerspoon config |

### Window Management
| Shortcut | Action |
|----------|--------|
| `⌃⌥ ←` | Left half |
| `⌃⌥ →` | Right half |
| `⌃⌥ ↑` | Top half |
| `⌃⌥ ↓` | Bottom half |
| `⌃⌥ M` | Maximize |
| `⌃⌥ C` | Center |
| `⌃⌥ F` | Full screen |

### Window Movement
| Shortcut | Action |
|----------|--------|
| `⌃⌥⇧ ←` | Move to previous screen |
| `⌃⌥⇧ →` | Move to next screen |
| `⌃⌥ S` | Move to next screen |
| `⌃⌥ Tab` | Focus next window |
| `⌃⌥⇧ Tab` | Focus previous window |

### Application Launcher
| Shortcut | Action |
|----------|--------|
| `⌃⌥ P` | Launch Ghostty |
| `⌃⌥ E` | Launch Neovim |
| `⌃⌥ B` | Launch Browser |

### Clipboard
| Shortcut | Action |
|----------|--------|
| `⌘⇧ V` | Open Maccy (alternative) |

### Utilities
| Shortcut | Action |
|----------|--------|
| `⌃⌥ H` | Hide all windows except current |
| `⌃⌥ I` | Show window info |

### Configuration
- Location: `~/.hammerspoon/init.lua`
- Edit file and reload with `⌘⌥⌃ R`
- Can add custom hotkeys and automations

---

## Rectangle (Window Manager)

### Half Screen
| Shortcut | Position |
|----------|----------|
| `⌃⌥ ←` | Left half |
| `⌃⌥ →` | Right half |
| `⌃⌥ ↑` | Top half |
| `⌃⌥ ↓` | Bottom half |

### Quarters
| Shortcut | Position |
|----------|----------|
| `⌃⌥ U` | Top-left |
| `⌃⌥ I` | Top-right |
| `⌃⌥ J` | Bottom-left |
| `⌃⌥ K` | Bottom-right |

### Other
| Shortcut | Action |
|----------|--------|
| `⌃⌥ Enter` | Maximize |
| `⌃⌥ C` | Center |
| `⌃⌥ Backspace` | Restore |

---

## System Productivity

### Maccy (Clipboard)
| Shortcut | Action |
|----------|--------|
| `⌘⇧C` | Open clipboard history |

### Stats
Click menu bar icon to configure.

### Hidden Bar
Drag icons past the arrow to hide.

---

## Shell Aliases

### Navigation
```bash
..        # cd ..
...       # cd ../..
....      # cd ../../..
```

### Editors
```bash
v         # nvim
vim       # nvim
vi        # nvim
```

### Git & Docker
```bash
lg        # lazygit
ld        # lazydocker
gs        # git status
ga        # git add
gc        # git commit
gp        # git push
gl        # git pull
gd        # git diff
```

### Utility
```bash
reload    # source ~/.zshrc
```

---

## Functions

### fcd - Fuzzy cd
```bash
fcd       # Interactive directory picker
```

### mkcd - Make and cd
```bash
mkcd newdir    # mkdir + cd in one
```

### mdp - Markdown preview
```bash
mdp README.md  # Preview markdown with glow
```

### pstats - Project statistics
```bash
pstats         # Show code stats and disk usage
```

### bench - Benchmark command
```bash
bench "command"  # Benchmark with hyperfine
```

### dev - Quick dev session
```bash
dev              # Start dev session with dev layout
```

### Zellij Sessions
```bash
ai               # Dual agent session (default)
ai-single        # Single agent session
ai-triple        # Triple agent session
multi            # Multi-agent with monitoring
fullstack        # Full-stack 5-tab session
remote           # Remote access session
```

### Tmux Sessions (for Claude agent teams)
```bash
ta [name]         # Attach or create bare session
tdev [name]       # 3-column: nvim | agent | runner
tai [name]        # nvim (60%) + 2 stacked agents
tai-triple [name] # nvim (55%) + 3 stacked agents
tls               # List sessions
tk [name]         # Kill session
tka               # Kill all sessions
```

### AI CLI Tools
```bash
cc               # Claude Code (Anthropic)
oc               # OpenCode (open-source, multi-model)
```

### zk - Kill all sessions
```bash
zk               # Kill all zellij sessions
```

### tunnel - Remote access tunnel
```bash
tunnel           # Start SSH tunnel (cloudflared or ngrok)
tunnel 3000      # Tunnel specific port
```

---

## Configuration Locations

```
~/.zshrc                     # Shell config
~/.zshrc.local               # Personal customizations (not overwritten)
~/.config/nvim/
├── init.lua                 # LazyVim bootstrap
└── lua/
    ├── config/              # Neovim settings
    └── plugins/             # Plugin configs (ai, coding, editor)
~/.config/starship.toml      # Prompt
~/.config/zellij/
├── config.kdl               # Zellij config
└── layouts/                 # 7 workspace layouts
~/.config/tmux/tmux.conf     # Tmux config (agent teams companion)
~/.config/ghostty/config     # Ghostty terminal
~/.hammerspoon/init.lua      # Hammerspoon automation
```

---

## Getting Help

```bash
tldr COMMAND      # Quick examples
man COMMAND       # Full manual
COMMAND --help    # Built-in help
```

In zellij: `Alt+p` then `?`
In lazygit: `?`

---

## Quick Reference Card

```
 ┌─ ZELLIJ ──────────────────────────────────┐
 │ Alt+n       New pane                      │
 │ Alt+h/j/k/l Navigate                      │
 │ Alt+p       Pane mode                     │
 │ Ctrl+t      Tab mode                      │
 │ Ctrl+q      Quit                          │
 ├─ TMUX (prefix = Ctrl+a) ──────────────────┤
 │ Ctrl+a |    Split right                   │
 │ Ctrl+a -    Split down                    │
 │ Ctrl+a h/j/k/l Navigate panes            │
 │ Ctrl+a d    Detach session                │
 │ tai [name]  nvim + 2 agents (agent teams) │
 ├─ FZF ─────────────────────────────────────┤
 │ Ctrl+T      Find files                    │
 │ Ctrl+R      Search history                │
 │ Alt+C       Find directories              │
 ├─ ELITE TOOLS ─────────────────────────────┤
 │ nnn         TUI file manager              │
 │ ld          lazydocker                    │
 │ sys         fastfetch                     │
 │ ncdu        Disk usage                    │
 │ sudo bandwhich  Network monitor           │
 │ k9s         Kubernetes                    │
 ├─ HAMMERSPOON ─────────────────────────────┤
 │ ⌃⌥ ←/→      Left/right half              │
 │ ⌃⌥ ↑/↓      Top/bottom half              │
 │ ⌃⌥ M        Maximize                     │
 │ ⌃⌥ C        Center                       │
 ├─ RECTANGLE ───────────────────────────────┤
 │ ⌃⌥ ←/→      Left/right half              │
 │ ⌃⌥ ↑/↓      Top/bottom half              │
 │ ⌃⌥ Enter    Maximize                     │
 ├─ ALIASES ─────────────────────────────────┤
 │ ls/ll/la    eza                           │
 │ cat         bat                           │
 │ lg          lazygit                       │
 │ ld          lazydocker                    │
 │ sys         fastfetch                     │
 │ z name      zoxide                        │
 └───────────────────────────────────────────┘
```

---

**Print and keep handy!**
