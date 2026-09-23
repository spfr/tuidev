# Vision

tuidev is an opinionated, minimal terminal setup for engineering with AI agents. macOS is the daily driver, and Linux nodes are first-class for the remote path. It is a sharp system with a small core, not a kitchen-sink bootstrapper.

Priorities, in order:

1. A fast, clean terminal for running AI coding agents next to a GUI editor.
2. Safe-by-default execution for those agents.
3. Remote and mobile continuity, on the machines that need it, without making that the whole product.

The forward-looking view (fleet-scale agents, sandbox succession, watch-list criteria) is in [docs/roadmap.md](docs/roadmap.md).

## Principles

**Your editor is a GUI; the terminal runs agents.** VS Code and Cursor do code review, debugging and navigation better than a terminal editor does. The terminal's job is a fast shell and an agent CLI, side by side. Neovim still ships, as an optional `nvim` pack, for when a terminal editor is genuinely what you want — not because every session needs one.

**Native sandboxes first, `sbx` for everything else.** Claude Code and Codex each ship their own sandbox now, good enough to run unwrapped. tuidev turns those on by default (`sandbox.enabled` in Claude's settings, `sandbox_mode = "workspace-write"` in Codex's) instead of routing every invocation through a shell wrapper. `sbx`, a thin `sandbox-exec` wrapper, stays as a general-purpose tool: sandbox any command, or give Codex an optional kernel-level boundary (`sbx -- codex -s danger-full-access -a on-request`). The two never nest — pick one per process tree.

**Durability where it matters.** A laptop session survives a reboot because the CLIs save their own state, and because you reopen the editor and the terminal tab. Durability earns its keep on a machine that has to outlive your laptop lid: an always-on Linux node you reach over Tailscale or SSH, where tmux (or Herdr) keeps an agent running while you're away. tmux is an optional `tmux` pack, not baked into every profile.

**Layered and reversible.** Profiles are shortcuts over packs, and every optional tool — including tmux and Neovim now — is a pack. Config is written as managed blocks or adopted, never clobbered. Every install is recorded so uninstall removes exactly that. Migrations repair the past once per machine.

**CLI-agnostic core.** The terminal layer doesn't depend on any AI CLI. Claude Code (primary) and Codex (secondary) are one opt-in pack, and OpenCode is optional. When a CLI is deprecated or a new one appears, the core doesn't move.

**Public means generic.** The repo ships best practices only. Hosts, IPs, usernames and hardware stay in gitignored `*.local` files. No telemetry, ever.

## What we take, and what we refuse

From [Omarchy](https://omarchy.org) and [Omacosy](https://github.com/paulsp94/omacosy), we take:

- **A small core with explicit packs.** A tool that isn't essential is `--pack NAME` or `--extras` — that now includes tmux and Neovim.
- **One palette, applied everywhere.** One `palette.toml` renders tmux, Ghostty and Starship (see [docs/theming.md](docs/theming.md)).
- **No telemetry.** Nothing phones home.
- **Idempotent installs and manifest-driven uninstall.**

From OpenClaw's 2.0 rework, we take three lessons: complexity should be progressive (a first install looks small, and depth is discoverable); CI scales with pack count (every pack gets lint, validation and contract tests); and agents orchestrate existing tools through their CLIs and sockets rather than reimplementing them, which is why `sbx` wraps `sandbox-exec` instead of replacing it.

We refuse:

- **Omarchy as a product.** Hyprland, an Arch desktop and a distro installer are the wrong OS and the wrong layer.
- **Desktop-environment experiments:** tiling window managers, Super-key remaps, Karabiner-as-root. The `ui` pack stays lean: Ghostty, Rectangle, Stats, Maccy and Hidden Bar.
- **Executable theme and plugin systems.** Code that runs at theme-switch time is a supply-chain surface (see [basecamp/omarchy#5946](https://github.com/basecamp/omarchy/discussions/5946)). Themes here are static files that ship with the repo.
- **Kitchen-sink CLI lists.** Speed comes from a short core and a runtime that knows agent state, not from another `ls` replacement.

## Non-goals

- A terminal IDE. Ten prebuilt tmux splits and a heavier Neovim config were the most expensive thing this repo maintained, and the maintainer's own shell history shows they went unused: the terminal's job is a shell and an agent, and the editor's job is everything else.
- A giant personal dotfiles repo, or a kitchen-sink Homebrew installer.
- A showcase for every modern CLI.
- AI agents running unsandboxed on the host by default.
- In-editor ACP agents. Users can add them, but the repo won't ship them.
- Non-FOSS defaults. Docker Desktop and OrbStack are never installed.
- Piping remote install scripts into a shell. When a package manager can't supply a tool, the installer prints the official command instead.

## Sources

- tmux sessions and re-attach: <https://github.com/tmux/tmux/wiki/Getting-Started>
- Ghostty features: <https://ghostty.org/docs/features>
- Tailscale SSH and check mode: <https://tailscale.com/docs/features/tailscale-ssh>
- mosh: <https://mosh.org/>
- Apple containerization: <https://github.com/apple/container>
