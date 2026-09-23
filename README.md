# tuidev — an agent-first terminal setup for macOS (and Linux)

> Opinionated macOS (and Linux) terminal environment for running AI coding agents next to your editor, with **native sandboxes on by default**, **durable remote sessions**, and **layered, reversible installation**.

[![CI](https://github.com/spfr/tuidev/actions/workflows/ci.yml/badge.svg)](https://github.com/spfr/tuidev/actions/workflows/ci.yml)
![macOS](https://img.shields.io/badge/macOS-000000?style=flat&logo=apple)
![Linux](https://img.shields.io/badge/Linux-FCC624?style=flat&logo=linux&logoColor=black)
![License](https://img.shields.io/badge/license-MIT-blue)

## What this is

A small set of configs and install scripts for coding with AI agents from the terminal. Three ideas shape it:

1. **A fast, clean terminal for agents, next to a GUI editor.** Claude Code is the primary CLI, Codex is secondary. Run them in a Ghostty tab, review the diff in VS Code or Cursor. Neovim and tmux are still here, but as optional packs, not the core.
2. **Sandboxed by default.** Plain `claude` and `codex` run under their own **native** sandboxes — no wrapper required. `sbx` (macOS Seatbelt) is still here as a general-purpose tool for sandboxing anything else, and as an optional kernel-level mode for Codex.
3. **Durable remote sessions where they matter.** tmux and Herdr keep agent sessions alive on always-on nodes you reach over Tailscale, SSH or mosh — not on your laptop, where the CLIs' own session state already survives a restart.

Layered, reversible install stays: pick a profile or compose packs. Config lands in managed blocks, so your edits outside them survive. Every install is recorded, and `./uninstall.sh` removes only what tuidev put there.

## Quick start

```bash
git clone https://github.com/spfr/tuidev.git
cd tuidev
./install.sh --profile desktop --pack ai-clis    # or: minimal | remote   (add --dry-run to preview)
exec zsh -l

claude                             # Claude Code, sandboxed by its own settings
codex                              # Codex, sandboxed by its own settings
```

The first-run walkthrough is [docs/QUICK_START_GUIDE.md](docs/QUICK_START_GUIDE.md).

## Profiles

| Profile   | Packs                   | For                                      |
|-----------|-------------------------|-------------------------------------------|
| `minimal` | core                    | Servers, VMs, CI runners                 |
| `desktop` | core + ui + sandbox     | **Default on macOS**: laptop or desktop  |
| `remote`  | core + remote + sandbox + `--pack tmux` | Headless machines, Tailscale nodes |

Compose your own with `--core`, `--remote`, `--sandbox`, `--ui` and `--extras`, and add optional packs with `--pack NAME`:

```bash
./install.sh --core --sandbox --pack ai-clis --pack herdr
```

Optional packs: `ai-clis`, `opencode`, `nvim`, `tmux`, `herdr`, `cmux`, `sandbox-container`, `mosh`, `fnm`, `monitoring`. See [docs/profiles.md](docs/profiles.md) for what each installs.

macOS needs Homebrew. On Linux, `minimal` and `remote` also install without it: packages come from `apt-get`, `dnf` or `pacman`, and anything the distro lacks is skipped with a link to its upstream installer. The installer never pipes a remote script into a shell.

## Everyday commands

```bash
claude | codex                           # AI CLIs, sandboxed by their own native settings
claude -w NAME                           # Claude Code in its own git worktree, for parallel agents
t [NAME]                                 # attach-or-create a tmux session (--pack tmux)
make check                               # health check for the installed profile
make update                              # profile-aware, drift-detecting update
make theme NAME=catppuccin-mocha         # re-theme tmux, Ghostty and Starship
make help                                # every target
```

Every key binding and command is listed in [docs/CHEATSHEET.md](docs/CHEATSHEET.md).

## Safety

- `~/.zshrc`, `~/.config/starship.toml` and `~/.ssh/config` are written as `# >>> tuidev managed (...) >>>` blocks. Everything outside the markers is yours. `~/.config/tmux/tmux.conf` gets the same treatment when you install `--pack tmux`.
- AI CLI settings (`~/.claude/settings.json`, `~/.codex/config.toml`, OpenCode's) are adopt-existing or upgrade-shipped: tuidev never clobbers a file you've edited.
- Anything tuidev overwrites is backed up to `~/.config/tuidev/backups/` first. `--dry-run` previews every mutation.
- `~/.config/tuidev/manifest` records what was actually installed. `./uninstall.sh` removes only those records: a `ripgrep` you already had survives, and so does CLI auth or session state.
- One-shot migrations repair what past releases left behind, at most once per machine. See [docs/updating.md](docs/updating.md).

## Documentation

| Doc | Covers |
|-----|--------|
| [Quick start](docs/QUICK_START_GUIDE.md) | Install to first sandboxed agent session |
| [Cheatsheet](docs/CHEATSHEET.md) | Session commands, tmux keys, aliases, Makefile |
| [FAQ](docs/FAQ.md) | Troubleshooting |
| [Profiles and packs](docs/profiles.md) | What each profile and pack installs |
| [Sandboxing](docs/sandboxing.md) | Native CLI sandboxes, `sbx`, Seatbelt profiles, credential deny list |
| [Agent workflows](docs/agent-workflows.md) | AI CLIs, editor integration, agent teams, worktrees, Herdr, cmux, notifications |
| [Remote and mobile](docs/remote.md) | Tailscale, SSH, mosh, always-on nodes, iOS clients |
| [Neovim](docs/nvim.md) | The `nvim` pack: LazyVim essentials |
| [Theming](docs/theming.md) | Palette contract and `theme.sh` |
| [Updating](docs/updating.md) | Updates, migrations, the install manifest, uninstall |
| [Engineering](docs/engineering.md) | Architecture, shared libs, pack contract, verification |
| [Roadmap](docs/roadmap.md) | Watch-list and adopt/hold criteria |
| [VISION.md](VISION.md) | Principles and non-goals |
| [AGENTS.md](AGENTS.md) / [CLAUDE.md](CLAUDE.md) | Instructions for AI agents working on this repo |
| [AGENTS template](templates/AGENTS_TEMPLATE.md) | Starter `AGENTS.md` for your own projects |
| [Migrations](scripts/migrations/README.md) | Script-level contract for one-shot migrations |
| [CONTRIBUTING.md](CONTRIBUTING.md) / [SECURITY.md](SECURITY.md) / [Code of Conduct](CODE_OF_CONDUCT.md) | Contributing and reporting |
| [CHANGELOG.md](CHANGELOG.md) | Release history |

## Contributing

Issues and PRs are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) and [VISION.md](VISION.md) first, and run `make ci-test` before you push.

## License

[MIT](LICENSE). Sponsored by [SpiceFactory](https://spfr.co).
