# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] - 2026-01-29

### Added

#### New CLI Tools
- **sd** - Intuitive find & replace (sed alternative)
- **yazi** - Modern async terminal file manager
- **broot** - Directory navigator for large codebases
- **tealdeer** - Fast tldr pages in Rust

#### AI Tools
- **Ralph Wiggum** - Autonomous AI agent orchestration script

#### Documentation
- **AI_ORCHESTRATION.md** - Complete guide for autonomous agent workflows

### Changed
- Updated README with new tools and orchestration section
- Enhanced .zshrc with aliases for new tools (y, br, ralph, tldr, sd)
- Added Ralph Wiggum orchestration to install.sh

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
