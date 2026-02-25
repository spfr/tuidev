# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.2.0] - 2026-02-25

### Added

#### Tmux Support (First-Class)
- **`configs/tmux/tmux.conf`** - Full Tokyo Night themed tmux configuration
  - `Ctrl+a` prefix (ergonomic), true color, mouse, base index 1, vi copy mode
  - Pane splits: `|` / `-`, navigation: `h/j/k/l`, resize: `H/J/K/L`
  - Status bar matching Tokyo Night palette (`#1a1b26` bg, `#7aa2f7` accent)
- **Tmux shell functions** in `.zshrc` — mirror Zellij session pattern with `t` prefix:
  - `ta [name]` — attach or create bare session
  - `tdev [name]` — 3-column: nvim (55%) | agent (25%) | runner (20%)
  - `tai [name]` — nvim (60%) + 2 stacked agent panes (40%)
  - `tai-triple [name]` — nvim (55%) + 3 stacked agent panes (45%)
  - `tls`, `tk [name]`, `tka` — session management
- **Health check** (`scripts/health_check.sh`): Tmux Check section (version, config, true color hint)
- **Config validation** (`scripts/validate_configs.sh`): tmux.conf validation + required files
- **Update sync** (`scripts/update.sh`): tmux.conf included in config change detection and apply
- **Install/uninstall**: backup, mkdir, copy, and remove `~/.config/tmux/`

#### Documentation
- `docs/CHEATSHEET.md` — full tmux section (key bindings, session functions, agent teams), tmux in Quick Reference Card, tmux in Config Locations; removed duplicate blocks
- `README.md` — dual session tables, tmux in Core Tools and Theme, `configs/tmux/` in project structure
- `docs/ARCHITECTURE.md` — side-by-side Zellij + tmux in Layer 2, dual orchestrator in Design Philosophy, tmux in Config Flow and File Locations
- `docs/QUICK_START_GUIDE.md` — step 9 "Tmux for Claude Agent Teams" with key bindings and agent teams workflow
- `AGENTS.md` — "Working with Tmux Sessions" section with why tmux, key bindings, session commands, agent teams integration
- `CLAUDE.md` — architecture table, shell functions split into Zellij/tmux subsections, Key Design Decision #6

### Changed
- `CLAUDE.md` and `AGENTS.md` updated to reflect dual-multiplexer architecture
- Zellij positioned as primary for manual workspace layouts; tmux as companion for Claude agent teams

### Context
Claude Code's experimental agent teams feature (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`) requires tmux or iTerm2 for split-pane mode. Zellij is explicitly unsupported. tmux was already installed by `install.sh` but had no config, shell functions, or documentation.

---

## [1.1.0] - 2026-01-29

### Added

#### New CLI Tools
- **sd** - Intuitive find & replace (sed alternative)
- **yazi** - Modern async terminal file manager
- **broot** - Directory navigator for large codebases
- **tealdeer** - Fast tldr pages in Rust

### Changed
- Updated README with new tools
- Enhanced .zshrc with aliases for new tools (y, br, tldr, sd)

---

## [1.0.0] - 2026-01-29

### Added

#### Core Tools
- **Neovim** with LazyVim - Full IDE experience with LSP
- **Zellij** - Terminal multiplexer with 7 pre-built layouts
- **Ghostty** - Fast terminal emulator configuration
- **Starship** - Modern shell prompt with Tokyo Night theme

#### Modern CLI Replacements
- **ripgrep** - Fast grep replacement (10x faster)
- **fd** - Simple find replacement
- **eza** - Modern ls with icons and git status
- **bat** - cat with syntax highlighting
- **zoxide** - Smart cd that learns from usage
- **delta** - Beautiful git diffs

#### TUI Applications
- **lazygit** - Git TUI interface
- **lazydocker** - Docker management TUI
- **nnn** - Fastest TUI file manager
- **k9s** - Kubernetes cluster management
- **ncdu** - Interactive disk usage analyzer
- **bottom** - System monitor

#### System Tools
- **fastfetch** - Fast system info display
- **bandwhich** - Network bandwidth monitor by process
- **fzf** - Fuzzy finder for files and history
- **atuin** - Enhanced shell history

#### macOS Applications
- **Rectangle** - Window snapping and management
- **Hammerspoon** - macOS automation with Lua
- **Stats** - Menu bar system monitor
- **Maccy** - Clipboard history manager
- **Hidden Bar** - Hide menu bar icons

#### AI CLI Tools
- **OpenCode** configuration with MCP servers
- **Claude Code** configuration with MCP servers
- **Gemini CLI** configuration with MCP servers

#### MCP Servers (Pre-configured)
- `filesystem` - File system access
- `git` - Git operations
- `fetch` - HTTP requests
- `memory` - Persistent memory across sessions
- `github` - GitHub API (requires API key)
- `brave-search` - Web search (requires API key)
- `figma` - Design-to-code workflows (requires API key)
- `playwright` - Browser automation
- `postgres` - PostgreSQL access
- `sqlite` - SQLite database access

#### Zellij Layouts
- `dual.kdl` - Editor + 2 AI agents (default)
- `single.kdl` - Editor + 1 AI agent
- `triple.kdl` - Editor + 3 AI agents
- `multi-agent.kdl` - Full workflow with monitoring
- `fullstack.kdl` - 5-tab full-stack development
- `remote.kdl` - Remote access with tunnel
- `dev.kdl` - Classic development layout

#### Documentation
- Quick Start Guide
- Architecture overview
- MCP Servers guide
- Neovim quickstart
- Complete cheatsheet
- Terminal navigation fixes
- Remote sessions guide
- FAQ

#### Infrastructure
- GitHub Actions CI/CD pipeline
- Docker test environment
- Makefile with common commands
- Health check script
- Comprehensive test suite
- Configuration validation
- Dry-run mode for installer

### Changed
- All configurations use `$HOME` variables (no hardcoded paths)
- Consistent Tokyo Night theme across all tools

### Security
- No sensitive data in repository
- API keys stored in environment variables
- MCP servers requiring authentication disabled by default

---

## Pre-release Development

### Elite Tools Phase
- Added nnn TUI file manager
- Added lazydocker for Docker management
- Added ncdu for disk usage analysis
- Added bandwhich for network monitoring
- Added fastfetch for system info
- Added k9s for Kubernetes
- Added Hammerspoon for macOS automation

### Testing Infrastructure Phase
- Created health check script
- Created comprehensive test suite
- Added Docker test environment
- Added GitHub Actions CI/CD
- Added Makefile for development workflow
- Added dry-run mode to installer

### Documentation Phase
- Created remote sessions guide
- Created iPhone SSH clients guide
- Created Zellij troubleshooting guide
- Updated all documentation for clarity

### AI Integration Phase
- Added OpenCode configuration
- Added Claude Code configuration
- Added Gemini CLI configuration
- Pre-configured MCP servers
- Created AGENTS.md for AI assistants
