# Architecture Overview

> How all the pieces fit together in this TUI development setup

---

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              GHOSTTY TERMINAL                                │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │                           ZELLIJ MULTIPLEXER                          │  │
│  │  ┌─────────────────────────┬──────────────────────────────────────┐  │  │
│  │  │                         │           AI AGENT PANES             │  │  │
│  │  │       NEOVIM            │  ┌────────────────────────────────┐  │  │  │
│  │  │     (LazyVim)           │  │  Claude Code / OpenCode /      │  │  │  │
│  │  │                         │  │  Gemini CLI                    │  │  │  │
│  │  │  - LSP                  │  │                                │  │  │  │
│  │  │  - Treesitter           │  │  Connected via MCP to:         │  │  │  │
│  │  │  - Telescope            │  │  - filesystem                  │  │  │  │
│  │  │  - nvim-tree            │  │  - git                         │  │  │  │
│  │  │  - (no AI plugins)      │  │  - memory                      │  │  │  │
│  │  │                         │  │  - fetch                       │  │  │  │
│  │  │                         │  │  - playwright (browser)        │  │  │  │
│  │  │                         │  │  - figma (design)              │  │  │  │
│  │  │                         │  │  - github, brave-search...     │  │  │  │
│  │  │                         │  └────────────────────────────────┘  │  │  │
│  │  │                         ├──────────────────────────────────────┤  │  │
│  │  │                         │  ┌────────────────────────────────┐  │  │  │
│  │  │                         │  │  Second AI Agent / Terminal    │  │  │  │
│  │  │                         │  │  (for parallel workflows)      │  │  │  │
│  │  │                         │  └────────────────────────────────┘  │  │  │
│  │  └─────────────────────────┴──────────────────────────────────────┘  │  │
│  │                                                                       │  │
│  │  [ Tab: Code ]  [ Tab: Monitor ]  [ Tab: Git ]                       │  │
│  └───────────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Component Layers

### Layer 1: Terminal Emulator (Ghostty)

```
┌─────────────────────────────────────────┐
│              GHOSTTY                     │
│  - GPU-accelerated rendering            │
│  - Tokyo Night theme                    │
│  - macOS key fixes (Option-as-Alt)      │
│  - Native feel, fast startup            │
└─────────────────────────────────────────┘
                    │
                    ▼
```

### Layer 2: Terminal Multiplexers

```
┌─────────────────────────────────────────┐  ┌─────────────────────────────────────────┐
│              ZELLIJ                      │  │              TMUX                        │
│  (primary — workspace layouts)          │  │  (companion — agent teams split-pane)   │
│                                         │  │                                         │
│  - Session management                   │  │  - Claude agent teams split-pane mode   │
│  - Pane/tab organization                │  │  - Ctrl+a prefix, vi pane nav           │
│  - Pre-defined layouts:                 │  │  - Sessions: tai, tdev, tai-triple      │
│    • dual (nvim + 2 agents)             │  │  - Tokyo Night status bar               │
│    • triple (nvim + 3 agents)           │  │  - Config: ~/.config/tmux/tmux.conf     │
│    • fullstack (5-tab setup)            │  │                                         │
│    • multi-agent (dev + monitor + git)  │  │  Note: Zellij unsupported by Claude     │
│    • remote (SSH tunnel)                │  │  agent teams split-pane mode            │
└─────────────────────────────────────────┘  └─────────────────────────────────────────┘
                    │                                           │
        ┌───────────┴───────────────────────────────────────────┘
        ▼
```

### Layer 3: Applications

```
┌──────────────────┐     ┌──────────────────┐
│     NEOVIM       │     │   AI CLI TOOLS   │
│   (LazyVim)      │     │                  │
│                  │     │  Claude Code     │
│  • LSP           │     │  OpenCode        │
│  • Completion    │     │  Gemini CLI      │
│  • Git signs     │     │                  │
│  • Formatting    │     │  ┌────────────┐  │
│  • Debugging     │     │  │ MCP Servers│  │
│  • Testing       │     │  └────────────┘  │
│                  │     │                  │
│  (No AI plugins) │     │  (All AI here)   │
└──────────────────┘     └──────────────────┘
```

---

## MCP Server Architecture

```
                    ┌─────────────────────────────────┐
                    │       AI CLI TOOL               │
                    │  (Claude/OpenCode/Gemini)       │
                    └───────────────┬─────────────────┘
                                    │
                    ┌───────────────┴───────────────┐
                    │      MCP Protocol Layer       │
                    └───────────────┬───────────────┘
                                    │
        ┌───────────┬───────────┬───┴───┬───────────┬───────────┐
        ▼           ▼           ▼       ▼           ▼           ▼
   ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐
   │filesystm│ │   git   │ │ memory  │ │  fetch  │ │playwrigt│ │  figma  │
   │ (npx)   │ │ (npx)   │ │ (npx)   │ │ (uvx)   │ │ (npx)   │ │ (npx)   │
   └────┬────┘ └────┬────┘ └────┬────┘ └────┬────┘ └────┬────┘ └────┬────┘
        │           │           │           │           │           │
        ▼           ▼           ▼           ▼           ▼           ▼
   ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐
   │  Local  │ │  Git    │ │ JSONL   │ │  HTTP   │ │ Browser │ │ Figma   │
   │  Files  │ │  Repos  │ │  File   │ │  APIs   │ │(Chromium│ │  API    │
   └─────────┘ └─────────┘ └─────────┘ └─────────┘ └─────────┘ └─────────┘
```

---

## Shell Integration

```
┌─────────────────────────────────────────────────────────────────┐
│                          ZSH SHELL                               │
│                                                                  │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐              │
│  │  Starship   │  │    fzf      │  │   zoxide    │              │
│  │  (prompt)   │  │  (fuzzy)    │  │  (smart cd) │              │
│  └─────────────┘  └─────────────┘  └─────────────┘              │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │                    Modern CLI Tools                         ││
│  │  ripgrep  fd  bat  eza  delta  dust  procs  btm  tokei     ││
│  └─────────────────────────────────────────────────────────────┘│
│                                                                  │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │                    TUI Applications                         ││
│  │  lazygit  lazydocker  nnn  ncdu  k9s  glow  bandwhich      ││
│  └─────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────┘
```

---

## Configuration Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                        INSTALLATION                              │
│                                                                  │
│   tuidev/                                                  │
│   ├── configs/          ──────────────────┐                     │
│   │   ├── nvim/         ─────────────────>│ ~/.config/nvim/     │
│   │   ├── zellij/       ─────────────────>│ ~/.config/zellij/   │
│   │   ├── tmux/         ─────────────────>│ ~/.config/tmux/     │
│   │   ├── zsh/.zshrc    ─────────────────>│ ~/.zshrc            │
│   │   ├── starship/     ─────────────────>│ ~/.config/starship/ │
│   │   ├── ghostty/      ─────────────────>│ ~/.config/ghostty/  │
│   │   ├── hammerspoon/  ─────────────────>│ ~/.hammerspoon/     │
│   │   ├── opencode/     ─────────────────>│ ~/.config/opencode/ │
│   │   ├── claude/       ─────────────────>│ ~/.claude.json      │
│   │   ├── gemini/       ─────────────────>│ ~/.gemini/          │
│   │   └── mcp/          ─────────────────>│ ~/.config/mcp-env   │
│   │                                       │                     │
│   └── install.sh        ──────────────────┘ (copies configs)    │
└─────────────────────────────────────────────────────────────────┘
```

---

## Data Flow: AI Coding Session

```
                    User types in AI terminal
                              │
                              ▼
                    ┌─────────────────────┐
                    │  AI CLI Tool        │
                    │  (Claude Code)      │
                    └──────────┬──────────┘
                               │
           ┌───────────────────┼───────────────────┐
           │                   │                   │
           ▼                   ▼                   ▼
    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
    │ filesystem  │    │    git      │    │  memory     │
    │    MCP      │    │    MCP      │    │    MCP      │
    └──────┬──────┘    └──────┬──────┘    └──────┬──────┘
           │                   │                   │
           ▼                   ▼                   ▼
    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
    │ Read/Write  │    │ git status  │    │  Recall     │
    │   Files     │    │ git diff    │    │  Context    │
    └──────┬──────┘    └──────┬──────┘    └──────┬──────┘
           │                   │                   │
           └───────────────────┼───────────────────┘
                               │
                               ▼
                    ┌─────────────────────┐
                    │  AI Response        │
                    │  (code changes)     │
                    └──────────┬──────────┘
                               │
                               ▼
                    ┌─────────────────────┐
                    │  User reviews in    │
                    │  Neovim (left pane) │
                    └─────────────────────┘
```

---

## Window Management Layer

```
┌─────────────────────────────────────────────────────────────────┐
│                         macOS                                    │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │                      HAMMERSPOON                           │ │
│  │  - Lua scripting                                           │ │
│  │  - Custom hotkeys                                          │ │
│  │  - Window automation                                       │ │
│  │  - App launching                                           │ │
│  └────────────────────────────────────────────────────────────┘ │
│                              +                                   │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │                       RECTANGLE                            │ │
│  │  - Simple window snapping                                  │ │
│  │  - Keyboard shortcuts                                      │ │
│  │  - No scripting needed                                     │ │
│  └────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

---

## Design Philosophy

```
┌─────────────────────────────────────────────────────────────────┐
│                     SEPARATION OF CONCERNS                       │
│                                                                  │
│   ┌───────────────────┐          ┌───────────────────┐          │
│   │      EDITOR       │          │      AI AGENTS    │          │
│   │     (Neovim)      │          │  (Claude/OpenCode)│          │
│   │                   │          │                   │          │
│   │  - Fast startup   │          │  - Heavy lifting  │          │
│   │  - Pure editing   │          │  - Code generation│          │
│   │  - No AI bloat    │          │  - Refactoring    │          │
│   │  - Vim motions    │          │  - Debugging      │          │
│   │                   │          │                   │          │
│   │  "I stay light"   │          │  "I do the work"  │          │
│   └───────────────────┘          └───────────────────┘          │
│              │                              │                    │
│              └──────────┬───────────────────┘                    │
│                         │                                        │
│                         ▼                                        │
│    ┌───────────────────┐  ┌──────────────────┐                    │
│    │      ZELLIJ       │  │      TMUX        │                    │
│    │  (orchestrator)   │  │  (agent teams)   │                    │
│    │                   │  │                  │                    │
│    │  "I organize      │  │  "I split panes  │                    │
│    │   workspaces"     │  │   for AI agents" │                    │
│    └───────────────────┘  └──────────────────┘                    │
└─────────────────────────────────────────────────────────────────┘
```

---

## File Locations Summary

```
~/.zshrc                          # Shell config (entry point)
~/.zshrc.local                    # User customizations
~/.config/
├── nvim/                         # Neovim (LazyVim)
│   ├── init.lua                  # Bootstrap
│   └── lua/
│       ├── config/               # keymaps, options
│       └── plugins/              # plugin configs
├── zellij/
│   ├── config.kdl                # Zellij settings
│   └── layouts/                  # Workspace layouts
├── tmux/
│   └── tmux.conf                 # Tmux config (agent teams companion)
├── starship.toml                 # Prompt
├── ghostty/config                # Terminal
├── opencode/opencode.json        # OpenCode + MCP
└── mcp-env                       # MCP environment vars

~/.claude.json                    # Claude Code + MCP
~/.gemini/settings.json           # Gemini CLI + MCP
~/.hammerspoon/init.lua           # macOS automation
~/.local/share/
├── nvim/                         # Neovim data
├── claude/memory.jsonl           # Claude memory
├── opencode/memory.jsonl         # OpenCode memory
└── mcp/                          # Shared MCP data
```
