# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

> See also: [AGENTS.md](AGENTS.md) for universal AI agent instructions about CLI tools and environment.

## Project Overview

macOS TUI Development Setup — an opinionated, terminal-first developer environment for AI-powered workflows. **tmux is the primary multiplexer** (durable sessions survive disconnects, narrow terminals, and mobile reattaches); **Zellij is an opt-in pack** installed via `--pack zellij`. Nvim stays lightweight (no in-editor AI plugins); AI CLIs (claude, codex, gemini, opencode) still run in external panes for maximum speed and multi-agent collaboration.

Installation is layered — pick a profile (`minimal`, `desktop`, `remote`) or compose packs directly (`--core`, `--remote`, `--sandbox`, `--ui`, `--extras`, `--pack NAME`). See `docs/profiles.md`.

## Common Commands

```bash
# Installation (profile-aware, layered)
make install              # Interactive (defaults: desktop on macOS, minimal on Linux)
make install-minimal      # core only
make install-desktop      # core + ui + sandbox
make install-remote       # core + remote + sandbox
make install-dry PROFILE=desktop  # preview without mutating
make uninstall

# Updates (profile-aware, drift-detecting)
make update-check         # Preview available updates
make update               # Interactive update
make update-packages      # Brew packages for active profile
make update-configs       # Re-apply managed blocks and pack-owned configs
make update-all           # Non-interactive: packages + configs + repo
make update-sandbox-image # Rebuild Podman image (requires --pack sandbox-container)
make update-security      # Audit Tailscale + SSH + Seatbelt drift

# Tests and health (profile-aware)
make check                # Health check against installed profile
make check-minimal        # Health check against minimal profile
make check-desktop
make check-remote
make test                 # Default-tagged tests
make test-core            # Only core-tagged tests
make test-ui              # Only ui-tagged (macOS GUI) tests
make test-all             # Every tag including ui

# Lint and validate
make lint                 # shellcheck install/scripts/lib/tmux/install packs/bin
make validate-configs     # KDL, TOML, Lua, JSON syntax

# Sandbox
make sbx-test             # Smoke-test Seatbelt: deny ~/.ssh, allow project writes
make sandbox-up           # Start Podman VM (Tier 2; --pack sandbox-container)
make sandbox-down

# Migration helpers
make adopt                # Convert existing dotfiles to managed-block form
make migrate              # Print migration guide from the old zellij-first setup

# Docker (Linux parity CI)
make docker-build
make docker-test

# Quick launchers
make quick-dev            # tmux dev layout (nvim | agent | runner)
make quick-ai             # tmux ai layout (nvim + 2 agents)
make quick-agents         # claude + codex + gemini side-by-side
make quick-lazygit
```

All install commands support `--dry-run` for previewing mutations.

## Architecture

```
configs/
├── nvim/                    # LazyVim setup; ai.lua is intentionally empty
├── tmux/tmux.conf           # Primary multiplexer (Tokyo Night)
├── zellij/                  # Opt-in pack (install via --pack zellij)
│   ├── config.kdl
│   └── layouts/             # 7 KDL workspace layouts
├── zsh/.zshrc               # Shell config, written as managed block
├── starship/starship.toml
├── ghostty/config
├── hammerspoon/init.lua     # macOS window automation
├── claude/settings.json     # Hooks + permissions (authoritative policy)
├── codex/config.toml        # sandbox_mode=workspace-write, approval=on-request
├── opencode/opencode.json
├── sandbox/profiles/        # Seatbelt profiles: strict.sb, standard.sb, off.sb
└── ssh/                     # Client config + sshd snippets

bin/
└── sbx                      # Seatbelt wrapper; uniform UX over sandbox-exec

scripts/
├── health_check.sh          # Profile-aware verification
├── test_suite.sh            # Tagged test runner (--tag core/ui/...)
├── validate_configs.sh
├── update.sh                # Profile-aware, drift-detecting updater
├── fix_completions.sh
├── setup_agent_configs.sh   # AI-agent symlink generator
├── notify.sh
├── lib/
│   ├── ui.sh                # Shared printing / prompt helpers
│   ├── config_write.sh      # Managed-block writer (preserves user edits)
│   └── test_config_write.sh # Unit tests for config_write
├── install/
│   ├── core.sh              # Core pack (always installed)
│   ├── remote.sh            # Tailscale + ssh + (optional) mosh
│   ├── sandbox.sh           # sbx + Seatbelt profile install
│   ├── ui.sh                # Ghostty, Hammerspoon, Rectangle, etc.
│   ├── extras.sh            # atuin, broot, dust, duf, hyperfine, tokei, ...
│   └── packs/
│       ├── zellij.sh        # Opt-in zellij pack
│       ├── yazi.sh          # Opt-in file manager
│       ├── nnn.sh
│       ├── monitoring.sh    # lazydocker, k9s, bottom
│       └── sandbox-container.sh  # Podman machine (Tier 2)
└── tmux/
    ├── layout-work.sh       # Reproducible attach-or-create layout helpers
    ├── layout-dev.sh        # nvim | agent | runner
    ├── layout-ai.sh         # nvim + 2 agents
    ├── layout-ai-single.sh
    ├── layout-ai-triple.sh
    ├── layout-agents.sh     # claude | codex | gemini
    ├── layout-fullstack.sh
    ├── layout-multi.sh
    └── layout-remote.sh
```


## Key Design Decisions

1. **AI runs externally.** `configs/nvim/lua/plugins/ai.lua` is intentionally empty — AI tools run in adjacent tmux panes, not in-editor. ACP is a conscious non-goal.
2. **tmux-primary; Zellij optional pack.** The ergonomic commands (`work`, `dev`, `ai`, ...) dispatch to tmux via reproducible layout scripts. Zellij wrappers are namespaced `z*` and only activate once `--pack zellij` is installed.
3. **Sandbox by default.** AI CLIs (`cc`/`cx`/`gem`/`oc`) auto-route through `sbx` (Seatbelt) on macOS when both the CLI and `sbx` are on `PATH`. `~/.ssh`, `~/.aws`, `~/.gnupg`, `~/Library/Keychains`, `~/.config/gh`, `~/.docker`, `~/.kube`, `~/.netrc` are denied in every shipped profile. Escape hatch: `CC_NO_SANDBOX=1`.
4. **Rust-based CLI tools.** ripgrep, fd, starship, zoxide, eza, bat, delta for performance.
5. **Tokyo Night theme.** Consistent across terminal, editor, multiplexer, and prompt.
6. **User-agnostic paths.** All configs use `$HOME`; no hardcoded `/Users/NAME` strings (CI enforces this).
7. **Non-destructive by default.** `~/.zshrc` is written as a managed block (`# >>> tuidev managed >>>`); user edits outside survive. AI CLI settings use `--adopt-existing`. Backups live in `~/.config/tuidev/backups/`.

## Session Layouts

Bare `tmux` opens a single pane. Use the shell wrappers or the scripts directly for multi-pane layouts. Each script under `scripts/tmux/layout-*.sh` is attach-or-create and accepts an optional session name.

- `layout-work.sh` — bare named session (default: `$(basename $PWD)`)
- `layout-dev.sh` — 3 columns: nvim (55%) | agent (25%) | runner (20%)
- `layout-ai.sh` — nvim (60%) + 2 stacked agent panes (40%)
- `layout-ai-single.sh` — nvim + 1 agent
- `layout-ai-triple.sh` — nvim (55%) + 3 stacked agent panes (45%)
- `layout-agents.sh` — 3 columns: claude | codex | gemini
- `layout-fullstack.sh` — 5 windows: code / web / api / db / logs
- `layout-multi.sh` — 3 windows: dev / monitor / git
- `layout-remote.sh` — minimal nvim + shell for narrow terminals

Zellij layouts (KDL) still live under `configs/zellij/layouts/` and are installed verbatim when the user runs `--pack zellij`.

## Shell Functions (from .zshrc)

All wrappers are attach-or-create, accept an optional name, and default to a layout-specific name or `$(basename $PWD)`.

### Primary (tmux-backed)

- `work [name]` — bare named session
- `dev [name]` — 3-column dev layout (nvim | agent | runner)
- `ai [name]` — nvim + 2 agent panes
- `ai-single [name]` — nvim + 1 agent
- `ai-triple [name]` — nvim + 3 agent panes
- `fullstack [name]` — 5-window full-stack layout
- `multi [name]` — dev + monitor + git windows
- `remote [name]` — minimal layout for narrow terminals
- `agents [name]` — claude + codex + gemini side-by-side

### Deprecated (one-time warning, forward to the new names)

- `ta` → `work`, `tdev` → `dev`, `tai` → `ai`, `tai-triple` → `ai-triple`

### Session management (tmux-native)

- `tls` — list sessions
- `tk [name]` — kill named session
- `tka` — kill all sessions (`tmux kill-server`)

### Zellij wrappers (activated when `--pack zellij` installs `zellij` on `PATH`)

- `zwork`, `zdev`, `zai`, `zai-single`, `zai-triple`, `zfullstack`, `zmulti`, `zremote`
- `zk` — kill all zellij sessions

## AI CLI Tools

Four AI CLIs are supported. All are self-updating. `cc`/`cx`/`gem`/`oc` are zsh functions (not plain aliases) that auto-route through `sbx` when both the CLI and `sbx` are on `PATH`.

| Tool | Function | Config | Purpose |
|------|----------|--------|---------|
| Claude Code | `cc` | `configs/claude/settings.json` | Anthropic's official CLI (primary) |
| Codex CLI | `cx` | `configs/codex/config.toml` | OpenAI; `sandbox_mode=workspace-write`, `approval_policy=on-request` |
| Gemini CLI | `gem` | n/a | Google's AI CLI (optional) |
| OpenCode | `oc` | `configs/opencode/opencode.json` | Open-source, multi-model |

Escape hatches for the sandbox (all one-shot):

```bash
cc                          # = sbx -- claude (strict profile)
CC_NO_SANDBOX=1 cc          # bypass sbx for this invocation
sbx --profile standard -- cc  # wider profile (GitHub, npm, PyPI, registries)
sbx --profile off -- cc     # full pass-through
agents                      # claude + codex + gemini in 3 tmux panes
```

See `docs/sandboxing.md` for profile internals and customization.

## CI Pipeline

`.github/workflows/ci.yml` runs:

- `lint-scripts` — shellcheck over `install.sh`, `scripts/*.sh`, `scripts/lib/*.sh`, `scripts/tmux/layout-*.sh`, `scripts/install/*.sh`, `scripts/install/packs/*.sh`, `bin/sbx`
- `script-syntax` — `bash -n` across install/uninstall/scripts/bin
- `validate-configs` — JSON (claude, opencode), TOML (starship, codex), Lua (nvim, hammerspoon)
- `check-paths` — no hardcoded `/Users/NAME` or `/home/NAME` leaked into configs
- `required-files` — every file `install.sh` references must exist (tmux, sandbox profiles, codex config, sbx, lib, docs)
- `seatbelt-profiles` (macOS runner) — each `.sb` parses under `sandbox-exec -n` and `bin/sbx --dry-run` runs
- `lib-tests` — `scripts/lib/test_config_write.sh`
- `docker-core` — Ubuntu image runs `test_suite.sh --tag core`
- `check-docs` — every `docs/...` link in README exists

## Commit Conventions

- Use conventional commit style with clear subject line
- Do NOT include `Co-Authored-By` trailers in commit messages
- Keep commits atomic and focused on single changes
