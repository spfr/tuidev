# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

> See also: [AGENTS.md](AGENTS.md) for universal AI agent instructions about CLI tools and environment.

## Project Overview

macOS TUI Development Setup - an opinionated, terminal-first developer environment for AI-powered workflows. The philosophy: Nvim stays lightweight (no in-editor AI plugins); AI tools (opencode, claude, codex) run in parallel Zellij panes for maximum speed and multi-agent collaboration.

## Common Commands

```bash
# Installation & Management
make install              # Run full installer
make uninstall            # Remove setup

# Updates (seamless update experience)
make update-check         # Check for updates (preview only)
make update               # Update everything interactively
make update-packages      # Update brew packages only
make update-configs       # Sync configs from repo only
make update-all           # Update everything non-interactively

# Testing & Validation
make check                # Health check (quick verification)
make test                 # Full test suite (scripts/test_suite.sh)
make lint                 # Shellcheck all scripts
make validate-configs     # Validate KDL, TOML, shell syntax

# Docker Testing (clean Linux environment)
make docker-build         # Build Ubuntu test image
make docker-test          # Run tests in Docker container

# Quick Launchers
make quick-zellij         # Launch zellij with dev layout
make quick-lazygit        # Open git UI
```

The installer supports `--dry-run` for previewing changes without committing.

## Architecture

```
configs/                    # User configuration files (copied to ~/.config)
├── nvim/                   # LazyVim setup with LSP and plugins
│   ├── init.lua            # Plugin bootstrap, LazyVim extras
│   └── lua/
│       ├── config/         # keymaps.lua, options.lua, autocmds.lua
│       └── plugins/        # ai.lua (intentionally empty), coding.lua, editor.lua
├── zellij/                 # Terminal multiplexer
│   ├── config.kdl          # Main config with Tokyo Night theme
│   └── layouts/            # 7 workspace layouts (dual, triple, multi-agent, etc.)
├── zsh/.zshrc              # Shell config with modern CLI aliases
├── starship/starship.toml  # Shell prompt (Tokyo Night)
├── ghostty/config          # Terminal emulator
├── hammerspoon/init.lua    # macOS window automation
├── opencode/               # OpenCode CLI configuration
│   └── opencode.json       # Full config with MCP servers
├── claude/                 # Claude Code configuration
│   ├── settings.json       # Global settings with MCP servers
│   └── mcp.json            # Project-level MCP template
├── gemini/                 # Gemini CLI configuration
│   └── settings.json       # Settings with MCP servers
└── mcp/                    # MCP shared configuration
    └── env.template        # Environment variables template

scripts/                    # Automation (~2000 LOC)
├── health_check.sh         # Verify all tools installed
├── test_suite.sh           # Comprehensive testing
├── validate_configs.sh     # Config file validation
├── ai-workflow.sh          # Launch multiplexed AI sessions
└── fix_completions.sh      # Fix zsh security warnings
```

## Key Design Decisions

1. **AI runs externally**: `configs/nvim/lua/plugins/ai.lua` is intentionally empty - AI tools run in adjacent Zellij panes, not in-editor
2. **Rust-based CLI tools**: ripgrep, fd, starship, zoxide, eza, bottom for performance
3. **Tokyo Night theme**: Consistent across terminal, editor, multiplexer, prompt
4. **User-agnostic paths**: All configs use `$HOME` variables, never hardcoded paths
5. **Self-contained**: Configs copied to `~/.config` on install; repo is reference only

## Zellij Layouts

Located in `configs/zellij/layouts/`:
- `dual.kdl` - **DEFAULT**: Nvim (60%) + 2 AI agent terminals (40%)
- `triple.kdl` - Nvim + 3 AI agents
- `multi-agent.kdl` - Editor + Monitoring tab + Git tab
- `fullstack.kdl` - 5-tab full-stack setup
- `remote.kdl` - Tailscale + mosh remote development (editor, agent, status monitor)

## Shell Aliases (from .zshrc)

AI workflow shortcuts: `ai`, `ai-single`, `ai-triple`, `fullstack`, `multi`, `remote`, `dev`

These launch Zellij with the corresponding layout.

## AI CLI Tool Configuration

The setup includes configurations for three AI CLI tools with MCP (Model Context Protocol) server support:

### Configured Tools

| Tool | Config Location | Purpose |
|------|-----------------|---------|
| OpenCode | `~/.config/opencode/opencode.json` | Open-source AI coding CLI |
| Claude Code | `~/.claude.json` | Anthropic's official CLI |
| Gemini CLI | `~/.gemini/settings.json` | Google's Gemini AI CLI |

### MCP Servers

Pre-configured MCP servers (enable as needed):

**Core Development (enabled by default):**
- `filesystem` - File system access
- `git` - Git operations
- `fetch` - HTTP requests
- `memory` - Persistent memory across sessions

**Requires API Keys (disabled by default):**
- `github` - GitHub API (`GITHUB_PERSONAL_ACCESS_TOKEN`)
- `brave-search` - Web search (`BRAVE_API_KEY`)
- `figma` - Design-to-code workflows (`FIGMA_PERSONAL_ACCESS_TOKEN`)
- `postgres` - PostgreSQL (`POSTGRES_CONNECTION_STRING`)
- `sqlite` - SQLite (path argument)
- `playwright` - Browser automation

### Environment Variables Setup

```bash
# Copy the template and configure your API keys:
cp ~/.config/mcp-env.template ~/.config/mcp-env
nvim ~/.config/mcp-env
source ~/.config/mcp-env
```

Or add exports to `~/.zshrc.local` for persistence.

### Quick Commands

```bash
# OpenCode
oc                    # Launch OpenCode (alias)
opencode              # Direct command

# Claude Code
cc                    # Launch Claude Code (alias)
claude                # Direct command
claude mcp list       # List MCP servers

# Gemini CLI
gem                   # Launch Gemini (alias)
gemini                # Direct command
```

### Project-Level MCP Config

Copy `configs/claude/mcp.json` to `.mcp.json` in any project root for project-specific MCP servers.

## CI Pipeline

`.github/workflows/ci.yml` runs:
- Shellcheck linting
- KDL/TOML/Lua syntax validation
- Configuration consistency checks (no hardcoded paths)
- Docker integration tests
- Documentation link checks

## Commit Conventions

- Use conventional commit style with clear subject line
- Do NOT include `Co-Authored-By` trailers in commit messages
- Keep commits atomic and focused on single changes
