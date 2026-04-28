# Architecture Overview

> How the pieces fit together.

---

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              TERMINAL (Ghostty / any)                        │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │                            TMUX SESSION LAYER                         │  │
│  │  ┌─────────────────────────┬──────────────────────────────────────┐  │  │
│  │  │                         │          AGENT PANES (sandboxed)     │  │  │
│  │  │       NEOVIM            │  ┌────────────────────────────────┐  │  │  │
│  │  │     (LazyVim)           │  │  sbx -- cc  (Claude, Seatbelt) │  │  │  │
│  │  │                         │  └────────────────────────────────┘  │  │  │
│  │  │  - LSP                  │  ┌────────────────────────────────┐  │  │  │
│  │  │  - Treesitter           │  │  sbx -- cx  (Codex)            │  │  │  │
│  │  │  - (no AI plugins)      │  └────────────────────────────────┘  │  │  │
│  │  │                         │  ┌────────────────────────────────┐  │  │  │
│  │  │                         │  │  runner: tests / build         │  │  │  │
│  │  │                         │  └────────────────────────────────┘  │  │  │
│  │  └─────────────────────────┴──────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────┘
```

Zellij is an optional pack (`--pack zellij`) for users who prefer its workspace model. tmux is always installed and is the primary session layer.

---

## Component Layers

### Layer 1: Terminal Emulator

Any terminal works. Ghostty is configured out of the box with macos-option-as-alt and navigation key fixes.

### Layer 2: Session Layer — tmux

```
┌─────────────────────────────────────────┐
│                 TMUX                    │
│          (primary session layer)        │
│                                         │
│  - Named sessions, durable across       │
│    SSH disconnect / terminal crash      │
│  - Ctrl+a prefix, vi-style pane nav     │
│  - Launchers: work, dev, ai,            │
│    ai-triple, agents, remote            │
│  - Tokyo Night status bar               │
│  - Config: ~/.config/tmux/tmux.conf     │
└─────────────────────────────────────────┘
```

**Zellij (optional pack)** ships layout KDLs and the `z*` launchers for users who want manual workspace layouts. Install with `./install.sh --pack zellij`.

### Layer 3: Applications

```
┌──────────────────┐     ┌──────────────────────────────┐
│     NEOVIM       │     │   AI CLI TOOLS (sandboxed)   │
│   (LazyVim)      │     │                              │
│                  │     │  sbx -- cc    Claude Code    │
│  • LSP           │     │  sbx -- cx    Codex          │
│  • Completion    │     │  sbx -- gem   Gemini         │
│  • Git signs     │     │  sbx -- oc    OpenCode       │
│  (no AI plugins) │     │                              │
└──────────────────┘     └──────────────────────────────┘
```

---

## Sandbox Architecture

Two tiers, both opt-in at runtime via `sbx`. See [sandboxing.md](sandboxing.md) for full details.

```
┌─────────────────────────────────────────────────────────────────┐
│                    sbx -- <command> <args>                       │
│                              │                                   │
│                              ▼                                   │
│                  ┌───────────────────────┐                       │
│                  │  choose tier          │                       │
│                  │  (env or flag)        │                       │
│                  └─────────┬─────────────┘                       │
│                            │                                     │
│           ┌────────────────┴────────────────┐                    │
│           ▼                                 ▼                    │
│  ┌──────────────────┐            ┌───────────────────┐           │
│  │  Tier 1: Seatbelt│            │  Tier 2: Podman   │           │
│  │  (macOS default) │            │  (rootless, opt)  │           │
│  │                  │            │                   │           │
│  │  sandbox-exec    │            │  container with   │           │
│  │  policy scoped   │            │  read-only host,  │           │
│  │  to project dir, │            │  net off by       │           │
│  │  $HOME read-only │            │  default          │           │
│  │                  │            │                   │           │
│  │  configs/sandbox/│            │  configs/sandbox/ │           │
│  │    *.sb          │            │    Containerfile  │           │
│  └──────────────────┘            └───────────────────┘           │
└─────────────────────────────────────────────────────────────────┘
```

Tier 1 is always available on macOS (no install). Tier 2 ships with the `sandbox` pack and requires Podman.

---

## Install Flow — Layered Packs

```
./install.sh --profile <profile>
./install.sh --pack <name> [--pack <name>...]
./install.sh --profile desktop --extras

     │
     ▼
┌────────────────────────────────────────────────┐
│                  scripts/install/              │
│                                                │
│   00-prereqs.sh     brew, xcode-select         │
│   10-core.sh        nvim, tmux, zsh, CLI tools │
│   20-remote.sh      Tailscale, mosh, SSH       │
│   30-sandbox.sh     Podman, policy files       │
│   40-ui.sh          Ghostty, Hammerspoon       │
│   90-extras.sh      optional tools             │
│   pack-zellij.sh    Zellij + layouts           │
│                                                │
│   Each script is idempotent and pack-scoped.   │
└────────────────────────────────────────────────┘
```

| Profile | Packs |
|---------|-------|
| `minimal` | core |
| `remote`  | core, remote |
| `desktop` | core, remote, sandbox, ui |
| `full`    | core, remote, sandbox, ui, extras |

Add named packs on top with `--pack`. Full matrix in [profiles.md](profiles.md).

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
│  Modern CLI: ripgrep fd bat eza delta dust procs btm tokei      │
│  TUI apps:   lazygit lazydocker nnn ncdu k9s glow bandwhich     │
│  Launchers:  work dev ai ai-triple agents remote sbx            │
└─────────────────────────────────────────────────────────────────┘
```

---

## Configuration Flow

```
tuidev/                                          ~/
├── configs/                                     ├── .zshrc          ◄── configs/zsh/.zshrc
│   ├── nvim/          ──────────────────────►   ├── .config/
│   ├── tmux/          ──────────────────────►   │   ├── nvim/
│   ├── zsh/.zshrc     ──────────────────────►   │   ├── tmux/
│   ├── starship/      ──────────────────────►   │   ├── starship.toml
│   ├── ghostty/       ──────────────────────►   │   ├── ghostty/
│   ├── sandbox/       ──────────────────────►   │   └── sandbox/
│   ├── claude/        ──────────────────────►   └── .claude.json
│   ├── opencode/      ──────────────────────►
│   └── zellij/ (pack) ──────────────────────►       .config/zellij/ (opt-in)
└── install.sh ── scripts/install/*.sh ──────►   copies configs, installs packages
```

---

## File Layout

```
tuidev/
├── bin/                        # user-facing wrappers (sbx, etc.)
├── configs/
│   ├── nvim/                   # LazyVim
│   ├── tmux/tmux.conf          # tmux (primary)
│   ├── zsh/.zshrc              # shell
│   ├── starship/               # prompt
│   ├── ghostty/                # terminal (macOS)
│   ├── hammerspoon/            # macOS automation (UI pack)
│   ├── claude/                 # Claude Code hooks
│   ├── opencode/               # OpenCode settings
│   ├── ssh/                    # remote pack
│   ├── sandbox/                # Seatbelt .sb + Containerfile
│   └── zellij/                 # opt-in pack
├── scripts/
│   ├── lib/                    # shared shell helpers
│   ├── install/                # numbered pack installers
│   ├── tmux/                   # tmux layout builders
│   ├── health_check.sh
│   ├── test_suite.sh
│   ├── validate_configs.sh
│   └── update.sh
├── docs/
├── templates/
├── AGENTS.md
├── CLAUDE.md
├── install.sh                  # profile/pack dispatcher
├── Makefile
└── Dockerfile
```

---

## Data Flow: AI Coding Session

```
        User types in an agent pane
                    │
                    ▼
         ┌────────────────────────┐
         │  sbx <tier> -- <cli>   │
         │  (Seatbelt or Podman)  │
         └──────────┬─────────────┘
                    │
                    ▼
         ┌────────────────────────┐
         │  AI CLI                │
         │  - reads project files │
         │  - writes within scope │
         │  - shells commands     │
         └──────────┬─────────────┘
                    │
                    ▼
         ┌────────────────────────┐
         │  User reviews diff in  │
         │  Neovim (other pane)   │
         └────────────────────────┘
```

---

## Design Philosophy

```
┌───────────────────────────────────────────────────────────────┐
│                   SEPARATION OF CONCERNS                      │
│                                                               │
│   ┌─────────────────┐          ┌─────────────────┐            │
│   │     EDITOR      │          │    AI AGENTS    │            │
│   │    (Neovim)     │          │  (sbx -- cli)   │            │
│   │                 │          │                 │            │
│   │  stays light:   │          │  do the work:   │            │
│   │  no AI bloat    │          │  codegen,       │            │
│   │  pure editing   │          │  refactor,      │            │
│   │                 │          │  shell, tests   │            │
│   └────────┬────────┘          └────────┬────────┘            │
│            └───────────┬───────────────-┘                     │
│                        ▼                                      │
│               ┌─────────────────┐                             │
│               │      TMUX       │                             │
│               │  (session layer)│                             │
│               │                 │                             │
│               │  organizes,     │                             │
│               │  persists,      │                             │
│               │  survives SSH   │                             │
│               └─────────────────┘                             │
└───────────────────────────────────────────────────────────────┘
```

---

## See Also

- [profiles.md](profiles.md) — layered install matrix
- [sandboxing.md](sandboxing.md) — Seatbelt / Podman tier details
- [remote.md](remote.md) — mosh, Tailscale, iOS clients
- [migration.md](migration.md) — moving from the old Zellij-first layout
