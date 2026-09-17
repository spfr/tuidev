# AGENTS.md

> Universal AI Agent Instructions for TUI Development Environment

This file provides guidance to AI coding agents (Claude Code, Codex CLI, OpenCode, and any other tool that reads `AGENTS.md`) when working with this setup or projects that use it.

---

## Environment Overview

This is a **terminal-first, AI-powered development environment** with:

- **Neovim** as the primary editor (no in-editor AI plugins by design)
- **tmux** as the only terminal multiplexer (durable sessions; agent tooling targets it)
- **Modern Rust CLI tools** replacing traditional Unix commands
- **AI agents run in parallel tmux panes**, not embedded in the editor
- **Sandbox by default** on macOS: AI CLIs auto-route through `sbx` (Seatbelt). Credentials (`~/.ssh`, `~/.aws`, keychain, etc.) are denied inside the sandbox.

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

> **Agents: the interactive TUIs are for the human, not you.** `lazygit`,
> `lazydocker`, `k9s`, `btm`/`bottom`, `yazi`, `fzf`, and `atuin` need a live
> terminal you can't drive non-interactively. Use the scriptable equivalents
> instead: `git`/`gh`, `docker`/`kubectl`, `git diff`, plain `fd`/`rg`. `gh` in
> particular (PRs, issues, `gh run view` for CI logs) is high-value and scriptable.

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

# AI CLI Tools (opt-in: ./install.sh --pack ai-clis; auto-route through sbx)
cc              # claude (primary)
cx              # codex (OpenAI)
oc              # opencode
agents          # Launch claude + codex in 2 tmux panes

# Fleet runtime (opt-in: ./install.sh --pack herdr)
herdr           # attach to the local Herdr server (prefix ctrl+b)
herdr --machine NODE agent list   # drive a saved SSH node without the TUI
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
~/.zshrc                         # Shell config (managed block; user edits outside survive)
~/.zshrc.local                   # Personal customizations (gitignored)
.local/                          # Machine-local notes/scripts/instructions in a checkout (gitignored)
~/.config/nvim/                  # Neovim (LazyVim)
~/.config/tmux/tmux.conf         # Primary multiplexer
~/.config/starship.toml          # Shell prompt
~/.config/ghostty/config         # Terminal emulator
~/.hammerspoon/init.lua          # macOS automation (desktop profile)
~/.config/tuidev/backups/        # Timestamped backups taken before any overwrite
```

### AI Tool Configurations

AI CLIs are opt-in via `./install.sh --pack ai-clis` and self-update. That pack ships hooks/policy and the `cc`/`cx`/`oc` wrappers; individual user configs are `--adopt-existing` by default (if present, left alone). Gemini CLI is deprecated (successor: Antigravity, `agy`) — not shipped.

```
~/.claude/settings.json              # Claude Code (primary) — NOT ~/.claude.json (that is CLI state)
~/.codex/config.toml                 # Codex CLI (OpenAI)
~/.config/opencode/opencode.json     # OpenCode CLI
~/.config/opencode/tui.json          # OpenCode TUI (theme, scroll, attention)
```

**Which CLI reads which instruction file** (verified against each tool's docs, Sept 2026):

| CLI | Reads natively | To load the other file |
|-----|----------------|------------------------|
| Claude Code | `CLAUDE.md` (managed → `~/.claude/CLAUDE.md` → project → `CLAUDE.local.md`), `.claude/rules/*.md` | put `@AGENTS.md` in `CLAUDE.md`, or `ln -s AGENTS.md CLAUDE.md` |
| Codex CLI | `AGENTS.md` (`~/.codex/AGENTS.md`, then repo root down to cwd; 32 KiB cap) | `project_doc_fallback_filenames = ["CLAUDE.md"]` |
| OpenCode | nearest `AGENTS.md`; falls back to `CLAUDE.md` only when no `AGENTS.md` exists | list `CLAUDE.md` under `instructions` (the shipped config does) |

Keep instruction files under ~200 lines each; every one loads into context at session start.

---

## Working with Sessions (tmux-first)

### Session Commands

Every command is **attach-or-create**, accepts an optional session name, and is backed by a reproducible script under `scripts/tmux/layout-*.sh`.

```bash
# Bare named session (default name: $(basename $PWD))
work [name]

# Development (3 columns: nvim 55% | agent 25% | runner 20%)
dev [name]

# AI workflow layouts
ai [name]         # nvim 60% + 2 stacked agent panes
ai-single [name]  # nvim + 1 agent
ai-triple [name]  # nvim + 3 stacked agent panes

# Multi-agent (claude | codex in 2 columns; needs --pack ai-clis)
agents [name]

# Worktree-per-agent: one git worktree + one tmux window per agent, so parallel
# agents never fight over the index. Window `main` stays on the original repo.
worktrees [name] [-n N] [--branch-prefix P] [--base REF] [--cmd CMD]
worktrees --list          # path, branch, dirty?, commits ahead
worktrees --clean         # remove only clean, fully-merged worktrees

# Other layouts
fullstack [name]  # 5 windows: code / web / api / db / logs
multi [name]      # 3 windows: dev / monitor / git
remote [name]     # minimal nvim + shell (narrow terminals, mosh, mobile)

# Session management (tmux-native)
tls               # list sessions
tk [name]         # kill a named session
tka               # kill all sessions (tmux kill-server)
```

**Deprecated aliases** (one-time warning, forward to the new names): `ta` → `work`, `tdev` → `dev`, `tai` → `ai`, `tai-triple` → `ai-triple`.

### tmux Key Bindings

```
Prefix: Ctrl+a

Pane splits:
  Ctrl+a |       Split vertically (new pane right)
  Ctrl+a -       Split horizontally (new pane below)

Pane navigation:
  Ctrl+a h/j/k/l Move between panes (vi-style)
  Ctrl+a H/J/K/L Resize pane

Copy mode (vi):
  Ctrl+a [       Enter copy mode
  v              Begin selection
  y              Copy to clipboard (pbcopy)

Sessions:
  Ctrl+a $       Rename session
  Ctrl+a d       Detach from session
  Ctrl+a r       Reload config
```

### Agent Teams Integration

Claude agent teams are experimental and off upstream; the shipped
`configs/claude/settings.json` turns them on (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`)
and sets `"teammateMode": "auto"`. Two display modes:

- **In-process** (upstream default): teammates run inside your terminal; the
  agent panel below the prompt lists them (arrow keys select, Enter opens,
  `x` stops). Works in any terminal including Ghostty.
- **Split-pane** (`auto` picks it when you are already inside tmux): each
  teammate gets its own tmux pane. Needs tmux or iTerm2 + `it2`; not
  Ghostty's native splits, VS Code's terminal, or Windows Terminal.

```bash
ai myproject                  # tmux layout first …
cc                            # … teammates open as panes (teammateMode=auto)
cc --teammate-mode in-process # one terminal, agent panel
```

With teams enabled, a *named* subagent launches as a teammate. Prefer plain
subagents for focused work that only needs a result back; reach for a team
when teammates must talk to each other. Set the variable to `0` to disable.

---

## Sandboxed AI Execution

On macOS, the `cc`/`cx`/`oc` wrappers (from `--pack ai-clis`) auto-route through `sbx` (a Seatbelt wrapper) when both the CLI and `sbx` are on `PATH`. Three profiles are shipped:

- **strict** (default) — agent runs, LLM APIs work, package installs don't
- **standard** — adds GitHub, npm, PyPI, crates, and common registries
- **off** — full pass-through; escape hatch only

Credential directories are denied in every profile: `~/.ssh`, `~/.aws`, `~/.gnupg`, `~/Library/Keychains`, `~/.config/gh`, `~/.docker`, `~/.kube`, `~/.netrc`.

Escape hatches:

```bash
CC_NO_SANDBOX=1 cc          # bypass sbx for this invocation
sbx --profile standard -- cc  # wider profile explicitly
sbx --profile off -- cc     # documented pass-through
unalias cc                  # nuclear option
```

Smoke-test the sandbox: `make sbx-test`. Full details: `docs/sandboxing.md`.

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
- Don't install AI plugins in nvim (intentionally excluded; ACP is a conscious non-goal)
- AI agents run in adjacent tmux panes by design
- Don't write credentials or probe `~/.ssh`/`~/.aws` — the sandbox denies them
- Keep configs in `~/.config/` following XDG conventions

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

# Sessions (tmux-backed; attach-or-create)
work [name]               # Bare named session
dev [name]                # 3-column dev layout
ai [name]                 # AI workflow (nvim + 2 agents)
agents [name]             # claude | codex (needs --pack ai-clis)
worktrees [name]          # One git worktree + tmux window per agent
tls / tk / tka            # List / kill named / kill all
```

---

## For Agent Developers

If building AI agents that integrate with this environment:

1. **Check for modern tools first** — Most users will have `rg`, `fd`, `bat`
2. **Use the shell aliases** — They're faster and more user-friendly
3. **Assume tmux** — it is the only multiplexer shipped
4. **Respect the sandbox** — On macOS, agents run under Seatbelt; don't expect host-level filesystem access
5. **Read the palette, don't hardcode it** — Tokyo Night is the default, but the user may have applied another theme. The active one is named in `~/.config/tuidev/theme` and its colors live in `configs/themes/<name>/palette.toml`
6. **Follow the engineering conventions** — When editing this repo's scripts, see [docs/engineering.md](docs/engineering.md): use the shared libs, follow the pack contract, never `cp` over user files
7. **Record what you install** — Anything placed on the machine goes through the shared libs so it lands in `~/.config/tuidev/manifest` and `uninstall.sh` can undo it. Removing a previously installed file needs a migration under `scripts/migrations/`, not just a repo deletion
8. **Don't pipe remote scripts into a shell** — If a package manager can't supply a tool, print the official install command and let the user run it

### Multi-agent symlink helper

`AGENTS.md` is the cross-vendor convention: Codex and OpenCode read it natively, Claude Code reads `CLAUDE.md`. For downstream projects that want one canonical file:

```bash
cp templates/AGENTS_TEMPLATE.md ~/myproject/AGENTS.md
./scripts/setup_agent_configs.sh ~/myproject
```

By default this creates only `CLAUDE.md` as a symlink to `AGENTS.md` (Codex and OpenCode need nothing). Pass `--all` to also create the legacy per-vendor files (`.cursorrules`, `.windsurfrules`, `.aider.md`, `.clinerules`, Copilot, Roo). If you want Claude-specific additions on top, replace the `CLAUDE.md` symlink with a real file whose first line is `@AGENTS.md`.

---

*This file is designed to be symlinked or referenced by project-specific agent configs.*
