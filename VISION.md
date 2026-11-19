# Vision

tuidev is for running coding agents anywhere and seeing everything they do: start them on a laptop, a VM or a box that stays on, pick them up from your phone, and know at any moment which one needs you and what each one runs, costs and leaves behind. It is how one team runs agents every day, shared in the open. What it does today and what comes next are in [docs/roadmap.md](docs/roadmap.md).

## Why it exists

Agents now run for hours, several at a time, on more than one machine. The tools that run them are good and keep getting better: Claude Code and Codex, Herdr, tmux, Ghostty. Each does its own part well. What none of them is meant to do is the setup around all of them: one view of every session on every machine, an account of what agents leave running and what they cost, one credential policy across both CLIs, and an install you can preview and undo. tuidev is that setup, as shell scripts and configs. It installs those tools and adds to them; it replaces none of them.

Priorities, in order:

1. **Work from anywhere.** Any machine, VM or phone, over plain ssh, with agents that keep running when you leave.
2. **See everything.** Which agent needs you, what it runs, what it costs, what it left behind.
3. **Safe by default.** Agents confined and kept away from your keys, without getting in the way of their work.
4. **Reversible.** Every change previewed, recorded and removable.

## Principles

**Built on open tools, replacing none.** Herdr owns the panes and the phone app, tmux keeps sessions alive, Ghostty is the terminal, SwiftBar draws the menu, and the CLIs bring their own sandboxes and background sessions. tuidev configures them and connects them. Host integrations stay thin: `agents` holds the logic, and a host supplies panes and a place to show state, so when a host does something better, tuidev's version can go.

**Local, and plain ssh.** Everything `agents` shows comes from local files and from your own machines over ssh; tuidev runs no service for anything to connect to, and sends nothing to a server you did not name (an [ntfy](https://ntfy.sh) topic for phone pushes is yours to set). No telemetry, ever: the one request tuidev makes of its own is a daily look at which release is the latest, and `tuidev latest off` stops it.

**Native sandboxes first, `sbx` for everything else.** Claude Code and Codex each ship a sandbox good enough to run unwrapped, so tuidev turns those on (`sandbox.enabled`, `sandbox_mode = "workspace-write"`) instead of routing every run through a wrapper. Where one falls short, tuidev says so: Codex's `workspace-write` does not block reads, so for credential-sensitive work Codex runs under `sbx`, a thin `sandbox-exec` wrapper that also confines any other command. The two never nest.

**Your editor is a GUI; the terminal runs agents.** VS Code and Cursor do review, debugging and navigation better than a terminal editor. The terminal's job is a fast shell and an agent CLI, side by side. Neovim ships as an optional pack for when a terminal editor is what you want.

**Durability where it matters.** A laptop session survives a reboot because the CLIs save their own state. Durability earns its keep on a machine that has to outlive your laptop lid, an always-on node you reach over Tailscale or SSH, where tmux, Herdr or herdr-core keep an agent running while you are away. So tmux is a pack, included by the `remote` profile, not baked into every install.

**Layered and reversible.** Profiles are shortcuts over packs, and every optional tool is a pack. Config is written as managed blocks or adopted, never clobbered. Every install is recorded, so uninstall removes exactly that, and migrations repair the past once per machine. A first install looks small; depth is there when you look for it.

**CLI-agnostic core.** The terminal layer doesn't depend on any AI CLI. Claude Code and Codex are one opt-in pack, so when a CLI is deprecated or a new one appears, the core doesn't move.

**Public means generic.** The repo ships best practices only. Hosts, IPs, usernames and hardware stay in gitignored `*.local` files.

## What we take, and what we refuse

From [Omarchy](https://omarchy.org) and [Omacosy](https://github.com/paulsp94/omacosy) we take a small core with explicit packs, one palette applied everywhere (one `palette.toml` renders tmux, Ghostty and Starship: [docs/theming.md](docs/theming.md)), no telemetry, and idempotent installs with a manifest-driven uninstall.

We refuse Omarchy as a product (Hyprland, an Arch desktop and a distro installer are the wrong OS and the wrong layer), desktop-environment experiments (tiling window managers, Super-key remaps, Karabiner as root; the `ui` pack stays Ghostty and Rectangle), and executable theme or plugin systems: code that runs at theme-switch time is a supply-chain surface ([basecamp/omarchy#5946](https://github.com/basecamp/omarchy/discussions/5946)). Themes here are static files that ship with the repo.

## What tuidev will not become

- **A terminal, a multiplexer or a phone app.** Ghostty, tmux and Herdr do that.
- **An agent, or an installer for one.** Claude Code and Codex update themselves.
- **A hosted service.** No accounts, no server, no telemetry.
- **A terminal IDE.** Prebuilt tmux layouts and a heavy Neovim config were once the most expensive thing this repo maintained, and they went unused.
- **A dotfiles dump, a kitchen-sink installer or a showcase of every modern CLI.** Speed comes from a short core and a runtime that knows agent state, not from another `ls` replacement.
- **Agents unsandboxed by default.**
- **In-editor agents (ACP) shipped by default.** You can add them; the repo won't ship them.
- **A team or deployment secret manager.** `secret` is one person's tokens on one machine ([docs/secrets.md](docs/secrets.md#when-to-use-something-else)).
- **Non-FOSS defaults.** Docker Desktop and OrbStack are never installed.
- **Third-party install scripts piped into a shell for you.** When a package manager can't supply a tool, the installer prints the official command. tuidev's own `get.sh` is the one script it asks you to pipe, and it is short enough to read first.
