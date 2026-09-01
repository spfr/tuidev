# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

> See also: [AGENTS.md](AGENTS.md) for universal AI agent instructions about CLI tools and environment, and [docs/engineering.md](docs/engineering.md) for the code conventions (shared libs, pack contract, managed blocks) to follow when editing `scripts/`, `bin/`, or `install.sh`.

## Project Overview

macOS TUI Development Setup — an opinionated, terminal-first developer environment for AI-powered workflows. **tmux is the primary multiplexer** (durable sessions survive disconnects, narrow terminals, and mobile reattaches); **Zellij is an opt-in pack** installed via `--pack zellij`. Nvim stays lightweight (no in-editor AI plugins); AI CLIs (claude, codex, opencode) are opt-in via `--pack ai-clis` and run in external panes for maximum speed and multi-agent collaboration.

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
make update-migrations    # Run pending one-shot migrations (once per machine)
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
make quick-agents         # claude + codex side-by-side (needs --pack ai-clis)
make quick-worktrees      # One git worktree + tmux window per agent (N=, CMD=)
make quick-lazygit

# Theming (palette-driven, managed blocks)
make theme-list           # Available themes, active one marked
make theme NAME=catppuccin-mocha  # Re-theme tmux / Ghostty / Starship
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
├── themes/                  # One palette.toml per theme (26-key contract)
├── herdr/config.toml        # Tokyo Night snippet; --adopt-existing (--pack herdr)
└── ssh/                     # Client config + sshd snippets

bin/
└── sbx                      # Seatbelt wrapper; uniform UX over sandbox-exec

scripts/
├── health_check.sh          # Profile-aware verification
├── test_suite.sh            # Tagged test runner (--tag core/ui/...)
├── validate_configs.sh
├── update.sh                # Profile-aware, drift-detecting updater
├── theme.sh                 # list | show | apply — palette-driven theming
├── fix_completions.sh
├── setup_agent_configs.sh   # AI-agent symlink generator
├── notify.sh
├── lib/
│   ├── ui.sh                # Shared printing / prompt helpers
│   ├── brew.sh              # Homebrew helpers (plural formulae/casks install)
│   ├── profile.sh           # Active-profile / pack resolution
│   ├── manifest.sh          # Append-only record of what we installed
│   ├── migrate.sh           # One-shot migration runner + state file
│   ├── config_write.sh      # Managed-block writer (preserves user edits)
│   └── test_*.sh            # Unit tests: config_write, profile, contract,
│                            #   theme, migrations (all run by CI `lib-tests`)
├── migrations/              # Timestamped one-shot scripts, run once per machine
├── install/
│   ├── core.sh              # Core pack (always installed; apt fallback on Linux)
│   ├── remote.sh            # Tailscale + ssh + (optional) mosh
│   ├── sandbox.sh           # sbx + Seatbelt profile install
│   ├── ui.sh                # Ghostty, Hammerspoon, Rectangle, etc.
│   ├── extras.sh            # atuin, broot, dust, duf, hyperfine, tokei, ...
│   └── packs/
│       ├── zellij.sh        # Opt-in zellij pack
│       ├── yazi.sh          # Opt-in file manager
│       ├── nnn.sh
│       ├── monitoring.sh    # lazydocker, k9s, bottom
│       ├── sandbox-container.sh  # Podman machine (Tier 2)
│       ├── mosh.sh          # mosh alone, without the full --remote pack
│       ├── fnm.sh           # Fast Node Manager
│       ├── cmux.sh          # macOS GUI terminal for parallel agents
│       ├── bosun.sh         # tmux-native agent session orchestrator
│       ├── ai-clis.sh       # cc/cx/oc wrappers + adopt-existing CLI configs
│       └── herdr.sh         # Opt-in agent runtime (fleet attention)
└── tmux/
    ├── _lib.sh              # Shared attach-or-create / arg-parsing helpers
    ├── layout-work.sh       # Reproducible attach-or-create layout helpers
    ├── layout-dev.sh        # nvim | agent | runner
    ├── layout-ai.sh         # nvim + 2 agents
    ├── layout-ai-single.sh
    ├── layout-ai-triple.sh
    ├── layout-agents.sh     # claude | codex
    ├── layout-worktrees.sh  # One git worktree + tmux window per agent
    ├── layout-fullstack.sh
    ├── layout-multi.sh
    └── layout-remote.sh
```


## Key Design Decisions

1. **AI runs externally.** `configs/nvim/lua/plugins/ai.lua` is intentionally empty — AI tools run in adjacent tmux panes, not in-editor. ACP is a conscious non-goal.
2. **tmux-primary; Zellij optional pack.** The ergonomic commands (`work`, `dev`, `ai`, ...) dispatch to tmux via reproducible layout scripts. Zellij wrappers are namespaced `z*` and only activate once `--pack zellij` is installed.
3. **Sandbox-ready.** `sbx` (Seatbelt) wraps any command; the AI-CLI wrappers (`cc`/`cx`/`oc`, from the opt-in `--pack ai-clis`) auto-route through it on macOS when both the CLI and `sbx` are on `PATH`. `~/.ssh`, `~/.aws`, `~/.gnupg`, `~/Library/Keychains`, `~/.config/gh`, `~/.docker`, `~/.kube`, `~/.netrc` are denied in every shipped profile. Escape hatch: `CC_NO_SANDBOX=1`.
4. **Rust-based CLI tools.** ripgrep, fd, starship, zoxide, eza, bat, delta for performance.
5. **One palette, applied everywhere.** Tokyo Night is the default; `scripts/theme.sh apply NAME` re-themes tmux, Ghostty and Starship from a single `configs/themes/<name>/palette.toml`. Neovim is deliberately out of scope (LazyVim owns its colorscheme). See [docs/theming.md](docs/theming.md).
6. **User-agnostic paths.** All configs use `$HOME`; no hardcoded `/Users/NAME` strings (CI enforces this). Personal LAN hosts belong in `~/.ssh/config.local` / `~/.zshrc.local`.
7. **Non-destructive by default.** `~/.zshrc` is written as a managed block (`# >>> tuidev managed >>>`); user edits outside survive. AI CLI settings use `--adopt-existing`. Backups live in `~/.config/tuidev/backups/`.
8. **Fleet attention is opt-in.** `--pack herdr` does not replace tmux layouts. Homebrew-only install — if brew has no formula the pack prints the official installer command instead of piping a remote script into a shell. See [docs/agent-workflows.md](docs/agent-workflows.md).
9. **Reversible installs.** Every install appends what it actually placed to `~/.config/tuidev/manifest`; `uninstall.sh` purges only those records, so a pre-existing `ripgrep` survives. One-shot `scripts/migrations/` repair past releases' leftovers and run before packs on an existing machine. See [docs/updating.md](docs/updating.md).
10. **macOS-first, Linux-capable.** `minimal` and `remote` install on Debian/Ubuntu via an apt fallback when Homebrew is absent (including arm64 boards like a Raspberry Pi). The installer never pipes a remote install script into a shell — it prints the command for you.

## Session Layouts

Bare `tmux` opens a single pane. Use the shell wrappers or the scripts directly for multi-pane layouts. Each script under `scripts/tmux/layout-*.sh` is attach-or-create and accepts an optional session name.

- `layout-work.sh` — bare named session (default: `$(basename $PWD)`)
- `layout-dev.sh` — 3 columns: nvim (55%) | agent (25%) | runner (20%)
- `layout-ai.sh` — nvim (60%) + 2 stacked agent panes (40%)
- `layout-ai-single.sh` — nvim + 1 agent
- `layout-ai-triple.sh` — nvim (55%) + 3 stacked agent panes (45%)
- `layout-agents.sh` — 2 columns: claude | codex
- `layout-worktrees.sh` — one git worktree + tmux window per agent; window `main` stays on the original repo. `[-n N] [--branch-prefix P] [--base REF] [--cmd CMD] | --list | --clean`. Default session `<repo>-wt`.
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
- `agents [name]` — claude + codex side-by-side (needs --pack ai-clis)
- `worktrees [name]` — one git worktree + tmux window per agent (default 2, max 8); `--list` / `--clean`

### Deprecated (one-time warning, forward to the new names)

- `ta` → `work`, `tdev` → `dev`, `tai` → `ai`, `tai-triple` → `ai-triple`

### Session management (tmux-native)

- `tls` — list sessions
- `tk [name]` — kill named session
- `tka` — kill all sessions (`tmux kill-server`)

### Zellij wrappers (activated when `--pack zellij` installs `zellij` on `PATH`)

- `zwork`, `zdev`, `zai`, `zai-single`, `zai-triple`, `zfullstack`, `zmulti`, `zremote`
- `zk` — kill all zellij sessions

## AI CLI Tools (opt-in — `--pack ai-clis`)

The core install is CLI-agnostic; AI CLIs live in one opt-in pack
(`./install.sh --pack ai-clis`). All are self-updating. `cc`/`cx`/`oc` are zsh
functions (not plain aliases) that auto-route through `sbx` when both the CLI and
`sbx` are on `PATH` (else they call the CLI directly).

| Tool | Function | Config | Purpose |
|------|----------|--------|---------|
| Claude Code | `cc` | `configs/claude/settings.json` | Anthropic's official CLI (primary) |
| Codex CLI | `cx` | `configs/codex/config.toml` | OpenAI; `sandbox_mode=workspace-write`, `approval_policy=on-request` |
| OpenCode | `oc` | `configs/opencode/opencode.json` | Open-source, multi-model |

Gemini CLI is deprecated upstream (successor: Antigravity, `agy`) and is not
shipped — the pack stays CLI-agnostic; add your own wrapper if you use one.

Escape hatches for the sandbox (all one-shot):

```bash
cc                          # = sbx -- claude (strict profile)
CC_NO_SANDBOX=1 cc          # bypass sbx for this invocation
sbx --profile standard -- cc  # wider profile (GitHub, npm, PyPI, registries)
sbx --profile off -- cc     # full pass-through
agents                      # claude + codex in 2 tmux panes
```

See `docs/sandboxing.md` for profile internals and customization.

## CI Pipeline

`.github/workflows/ci.yml` runs:

- `lint-scripts` — shellcheck over `install.sh`, `scripts/*.sh`, `scripts/lib/*.sh`, `scripts/tmux/layout-*.sh`, `scripts/install/*.sh`, `scripts/install/packs/*.sh`, `bin/sbx`
- `script-syntax` — `bash -n` across install/uninstall/scripts/bin
- `validate-configs` — JSON (claude, opencode), TOML (starship, codex), Lua (nvim, hammerspoon)
- `check-paths` — no hardcoded `/Users/NAME` or `/home/NAME` leaked into configs, docs, `bin/`, `uninstall.sh`, or the `Makefile`; also fails on mDNS `user@host.local` forms
- `required-files` — every file `install.sh` references must exist (tmux, sandbox profiles, codex config, sbx, lib, docs)
- `seatbelt-profiles` (macOS runner) — each `.sb` parses under `sandbox-exec -n` and `bin/sbx --dry-run` runs
- `lib-tests` — `test_config_write.sh`, `test_profile.sh`, `test_contract.sh`, `test_theme.sh`, `test_migrations.sh` under `scripts/lib/`
- `docker-core` — Ubuntu image runs `test_suite.sh --tag core`
- `check-docs` — every `docs/...` link in README exists
- `summary` — aggregates the job results into one required status

## Commit Conventions

- Use conventional commit style with clear subject line
- Do NOT include `Co-Authored-By` trailers in commit messages
- Keep commits atomic and focused on single changes
