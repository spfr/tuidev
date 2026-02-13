# AGENTS.md

> Universal AI Agent Instructions for TUI Development Environment

This file provides guidance to AI coding agents (Claude Code, OpenCode, Gemini CLI, Cursor, Windsurf, Codex, etc.) when working with this setup or projects that use it.

---

## Environment Overview

This is a **terminal-first, AI-powered development environment** with:

- **Neovim** as the primary editor (no in-editor AI plugins by design)
- **Zellij** as terminal multiplexer for multi-pane workflows
- **Modern Rust CLI tools** replacing traditional Unix commands
- **AI agents run in parallel terminal panes**, not embedded in the editor

---

## Available CLI Tools

### Use These Modern Alternatives

When executing shell commands, prefer these faster, better alternatives:

| Task | Use This | Instead Of | Why |
|------|----------|------------|-----|
| Search file contents | `rg` (ripgrep) | `grep` | 10-100x faster, better defaults |
| Find files | `fd` | `find` | Simpler syntax, faster |
| List files | `eza --icons` | `ls` | Git status, icons, colors |
| View files | `bat` | `cat` | Syntax highlighting, git integration |
| Disk usage | `dust` | `du` | Visual, fast |
| Disk free | `duf` | `df` | Better formatting |
| Process list | `procs` | `ps` | Better output, searchable |
| System monitor | `btm` | `top` / `htop` | Modern TUI |
| Directory jump | `z <partial>` | `cd` | Learns from usage |
| Git TUI | `lazygit` or `lg` | - | Visual git operations |
| Docker TUI | `lazydocker` or `ld` | - | Container management |
| JSON processing | `jq` | - | Query JSON |
| YAML processing | `yq` | - | Query YAML |
| HTTP requests | `http` (httpie) | `curl` | Better UX for APIs |
| Benchmarking | `hyperfine` | `time` | Statistical analysis |
| Code stats | `tokei` | `cloc` | Fast line counting |

### Available Aliases

```bash
# Editor
v, vim, vi      # All map to nvim

# File listing (eza)
ls              # eza --icons
ll              # eza -l --icons (long format with git)
la              # eza -la --icons (all files)
lt              # eza --tree --level=2 --icons

# Git
lg              # lazygit
gs              # git status
ga              # git add
gc              # git commit
gp              # git push
gl              # git pull
gd              # git diff

# Docker
ld              # lazydocker

# System
top             # btm (bottom)
bottom          # btm
sys             # fastfetch

# Navigation
cd              # z (zoxide) in interactive shells; builtin cd in scripts
..              # cd ..
...             # cd ../..
....            # cd ../../..
```

---

## File Operations

### Reading Files
```bash
# Preferred: bat with syntax highlighting
bat file.py

# View specific lines
bat -r 10:20 file.py

# Plain output (for piping)
bat -p file.py
```

### Searching Code
```bash
# Search in all files
rg "pattern"

# Case insensitive
rg -i "pattern"

# Specific file types
rg "TODO" --type py
rg "function" -t js -t ts

# With context
rg "error" -B 3 -A 3

# Files only (no content)
rg "pattern" -l
```

### Finding Files
```bash
# Find by name
fd "config"

# Find by extension
fd -e json

# Find directories only
fd -t d "test"

# Include hidden
fd -H "secret"

# Execute on results
fd -e py -x wc -l
```

### Directory Navigation
```bash
# Smart jump (learns from usage)
z project       # Jump to ~/projects/myproject
z doc           # Jump to most-used directory containing "doc"

# Interactive selection
zi
```

---

## Project Structure Guidelines

When creating or modifying projects with this setup:

### Configuration Locations

```
~/.zshrc                     # Shell config (aliases, functions)
~/.zshrc.local               # Personal customizations (gitignored)
~/.config/nvim/              # Neovim (LazyVim)
~/.config/zellij/            # Zellij configs and layouts
~/.config/starship.toml      # Shell prompt
~/.config/ghostty/config     # Terminal emulator
~/.hammerspoon/init.lua      # macOS automation
```

### AI Tool Configurations

```
~/.config/opencode/opencode.json    # OpenCode CLI
~/.claude.json                       # Claude Code
~/.gemini/settings.json             # Gemini CLI
~/.config/mcp-env                   # MCP environment variables
```

---

## Working with Zellij Sessions

### Session Commands

All functions create **named sessions** with re-attachment support. Pass an optional name argument.

```bash
# Development (3 columns: nvim | agent | runner)
dev [name]        # Default session name: "dev"

# Bare named session (for remote attachment via Tailscale/Termius/mosh)
work [name]       # Default session name: current directory basename

# AI workflow layouts
ai [name]         # nvim + 2 agent terminals
ai-single [name]  # nvim + 1 agent
ai-triple [name]  # nvim + 3 agents

# Other layouts
fullstack [name]  # 5-tab full-stack setup
multi [name]      # Dev + Monitor + Git tabs
remote [name]     # Minimal for Tailscale/mosh

# Kill all sessions
zk
```

### Navigation While in Zellij

```
Alt+h/j/k/l   # Move between panes
Alt+n         # New pane
Ctrl+t, n     # New tab
Ctrl+g        # Locked mode (pass keys to terminal)
```

---

## MCP Servers Available

Model Context Protocol servers pre-configured. See [docs/MCP_SERVERS.md](docs/MCP_SERVERS.md) for full details.

**Enabled by default:**
- `filesystem` - File system access
- `git` - Git operations
- `memory` - Persistent memory across sessions
- `fetch` - HTTP requests

**Browser Automation (Playwright):**
- Control Chrome/Firefox/Safari programmatically
- Take screenshots, fill forms, click buttons
- No API key needed, just: `npx playwright install`
- Example: "Open example.com and screenshot the homepage"

**Design-to-Code (Figma):**
- Read Figma designs and extract specs
- Generate code from design components
- Requires: `FIGMA_PERSONAL_ACCESS_TOKEN` in `~/.config/mcp-env`
- Example: "Generate React component from this Figma frame"

**Other Available (require API keys):**
- `github` - GitHub API (issues, PRs, repos) - requires Docker
- `brave-search` - Web search capability
- `postgres` - PostgreSQL database queries
- `sqlite` - SQLite database queries

---

## Best Practices for AI Agents

### 1. Use Modern Tools
Always prefer `rg` over `grep`, `fd` over `find`, `bat` over `cat`.

### 2. Check Tool Availability
```bash
command -v rg && rg "pattern" || grep "pattern"
```

### 3. Leverage zoxide for Navigation
```bash
# Don't use full paths when zoxide can help
z project    # Instead of: cd ~/workspace/projects/myproject
```

### 4. Use Aliases for Git
```bash
lg           # Instead of: git log --oneline
```

### 5. Respect the Environment
- Don't install AI plugins in nvim (they're intentionally excluded)
- AI agents run in separate Zellij panes by design
- Keep configs in ~/.config/ following XDG conventions

### 6. For Debugging and Monitoring
```bash
btm              # System resources
lazydocker       # Docker containers
bandwhich        # Network by process (needs sudo)
ncdu             # Disk usage analyzer
```

---

## File Format Support

### Markdown
```bash
glow README.md   # Render in terminal
mdp README.md    # Preview function
```

### JSON
```bash
jq '.' file.json           # Pretty print
jq '.key' file.json        # Extract key
```

### YAML
```bash
yq '.' file.yaml           # Pretty print
yq '.key' file.yaml        # Extract key
```

---

## Commit Conventions

When creating commits:
- Use conventional commit style
- Do NOT include `Co-Authored-By` trailers
- Keep commits atomic and focused

---

## Quick Reference

```
# Search
rg "pattern"              # Search contents
fd "name"                 # Find files

# Navigate
z partial                 # Jump to directory
lg                        # Git TUI

# View
bat file                  # View with highlighting
btm                       # System monitor
ld                        # Docker TUI

# Edit
v file                    # Open in nvim

# Sessions (all support named sessions)
dev [name]                # 3-column dev layout
work [name]               # Bare named session
ai [name]                 # AI workflow (nvim + 2 agents)
zk                        # Kill all sessions
```

---

## For Agent Developers

If building AI agents that integrate with this environment:

1. **Check for modern tools first** - Most users will have `rg`, `fd`, `bat`
2. **Use the shell aliases** - They're faster and more user-friendly
3. **Respect Zellij context** - Users may be in multiplexed sessions
4. **MCP servers available** - Use them for file/git/memory operations
5. **Tokyo Night theme** - If generating TUI output, match the color scheme

---

*This file is designed to be symlinked or referenced by project-specific agent configs.*
