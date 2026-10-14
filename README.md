# tuidev

**A terminal setup for running AI coding agents on macOS and Linux: Claude Code and Codex sandboxed by default (`--pack ai-clis`), easy to watch, and installed in layers you can undo.**

[![CI](https://github.com/spfr/tuidev/actions/workflows/ci.yml/badge.svg)](https://github.com/spfr/tuidev/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/spfr/tuidev?sort=semver)](https://github.com/spfr/tuidev/releases/latest)
![macOS](https://img.shields.io/badge/macOS-000000?style=flat&logo=apple)
![Linux](https://img.shields.io/badge/Linux-FCC624?style=flat&logo=linux&logoColor=black)
[![License](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

![The agents command in a terminal. Three sessions: a Claude Code session in api, blocked and waiting for input, with its polling command; a working Claude Code session in myapp with two MCP servers and three commands, two of them from subagents in their own worktrees; an idle Codex session in web running a dev server on port 5173. Below them, two stale processes a crashed session left behind, one CPU hog, and a status line with CPU, memory, battery, thermal pressure and keep-awake.](docs/assets/agents.png)

<sub>`agents` (`--pack monitoring`) over demo fixtures: what your Claude Code and Codex sessions run, what they left behind, and what is eating the CPU. Rendered with `make screenshots`.</sub>

tuidev is shell scripts and configs for coding with AI agents from the terminal. Claude Code is the primary CLI and Codex the second: run them in a Ghostty tab and review the diff in VS Code or Cursor. It installs a small core, and everything else is an opt-in pack.

## Why tuidev

- **Agents don't get your credentials.** `--pack ai-clis` turns on Claude Code's and Codex's own sandboxes, so plain `claude` and `codex` run confined without a wrapper. Claude Code's Bash and `Read` tools are denied `~/.ssh`, `~/.aws` and the other 21 paths on one [credential list](configs/sandbox/credential-paths.txt). For everything else, including Codex, whose sandbox limits writes and network but not reads, `sbx` runs any command under a macOS Seatbelt profile that denies the same list. A contract test keeps every copy of the list in step. [Sandboxing](docs/sandboxing.md)
- **You see what your agents run, and can stop it.** `agents` lists each session with its MCP servers, ports and the commands its subagents run in their worktrees, flags the MCP and dev servers a crashed session left running, and kills a tree, descendants first, re-checking each process's start time before every signal. With [Herdr](https://herdr.dev/), sessions waiting for you come first. On macOS its SwiftBar menu shows the same, keeps the Mac awake while agents run, and shows CPU, memory, battery and thermal pressure, standing in for Amphetamine and Stats. [Agent workflows](docs/agent-workflows.md#local-processes-agents---pack-monitoring)
- **Subagents on the cheapest tier that works.** `--pack orchestration` pins Claude Code and Codex subagents to tiers (on Claude: Haiku for search and command runs, Sonnet for standard implementation, Opus for complex work and review) and adds a delegation skill for parallel worktrees. It installs on its own, without the rest of tuidev. [Orchestration](docs/orchestration.md)
- **An install you can preview and undo.** Pick a profile or compose packs, and `--dry-run` shows every change first. Config goes into managed blocks, so your own lines survive, and a config file you edited keeps your changes through updates. Every install is recorded, `./uninstall.sh` removes only what tuidev put there, and one-shot migrations clean up after older releases. [Updating](docs/updating.md)
- **Sessions that outlive your laptop.** On an always-on machine you reach over Tailscale, SSH or mosh, tmux or Herdr keeps an agent running while you're away; `t NAME` re-attaches. [Remote](docs/remote.md)
- **One palette.** One `palette.toml` colors Ghostty, tmux and Starship; `make theme NAME=catppuccin-mocha` switches all three. [Theming](docs/theming.md)
- **Linux too.** `minimal` and `remote` install with `apt-get`, `dnf` or `pacman` when there's no Homebrew, and `agents` works there. `sbx` and the `ui` pack are macOS only. [Profiles](docs/profiles.md)

![sbx in a terminal: without a sandbox, cat of ~/.ssh/id_ed25519 prints the key; under sbx the same read and a read of ~/.aws/credentials fail with "Operation not permitted", so does appending to ~/.zshrc, and make test in the project still runs and passes.](docs/assets/sbx.png)

<sub>Without a sandbox, any command an agent runs can read your keys. Under `sbx` (strict profile), the same read is refused, so are the other credentials and writes outside the project, and the project's own work still runs. Demo home with made-up files.</sub>

## Who it's for

**For you if** you run Claude Code or Codex from a terminal next to a GUI editor, mostly on a Mac, maybe with a Linux box that stays on, and you want agents confined by default and a setup you can read in an afternoon and remove cleanly.

**Not for you if** you want:

- a terminal IDE: there are no prebuilt tmux layouts, and Neovim is an optional pack;
- a personal dotfiles dump, a kitchen-sink Homebrew installer, or a showcase of every modern CLI;
- AI agents running unsandboxed on the host by default: `--pack ai-clis`, part of the quick start, turns on Claude Code's and Codex's sandboxes;
- in-editor ACP agents shipped for you;
- Docker Desktop or OrbStack (never installed), or `curl | sh` installers (the installer prints the official command instead).

The reasoning is in [VISION.md](VISION.md).

## Quick start

tuidev configures Claude Code and Codex but doesn't install them, since they update themselves. Install them first with their official instructions: [Claude Code](https://code.claude.com/docs/en/setup), [Codex](https://github.com/openai/codex). Then:

```bash
git clone https://github.com/spfr/tuidev.git
cd tuidev
./install.sh --profile desktop --pack ai-clis --dry-run   # preview every change
./install.sh --profile desktop --pack ai-clis             # or: --profile minimal | remote
exec zsh -l

claude                             # Claude Code, sandboxed by its own settings
codex                              # Codex, sandboxed by its own settings
```

Add `--pack monitoring` for `agents` and the menu bar, and `--pack orchestration` for tiered subagents. The first-run walkthrough is [docs/QUICK_START_GUIDE.md](docs/QUICK_START_GUIDE.md).

**Only want the agent setup?** The `orchestration` pack installs on its own, without the shell, theme or packages: `bash scripts/install/packs/orchestration.sh` from a clone. `git pull` and re-run to update, and `./uninstall.sh` to remove it. See [docs/orchestration.md](docs/orchestration.md).

## Profiles and packs

| Profile   | Packs                                   | For                                     |
|-----------|-----------------------------------------|-----------------------------------------|
| `minimal` | core                                    | Servers, VMs, CI runners                |
| `desktop` | core + ui + sandbox                     | **Default on macOS**: laptop or desktop |
| `remote`  | core + remote + sandbox + `--pack tmux` | Headless machines, Tailscale nodes      |

Compose your own with `--core`, `--remote`, `--sandbox`, `--ui` and `--extras`, and add optional packs with `--pack NAME`:

```bash
./install.sh --core --sandbox --pack ai-clis --pack herdr
```

| Optional pack | Adds |
|---------------|------|
| `ai-clis` | Claude Code and Codex settings with their native sandboxes on, and git and gh write gates |
| `orchestration` | Tiered subagents and the delegation skill for Claude Code and Codex |
| `monitoring` | `agents`, its SwiftBar menu (macOS), `lazydocker` and `bottom` |
| `tmux`, `herdr` | Durable sessions; Herdr's agent-aware runtime |
| `nvim`, `vim` | LazyVim, or a zero-plugin vimrc for servers |
| `sandbox-container` | Tier 2 sandboxing in a container runtime (Apple `container`, Podman or Docker) |
| `fnm`, `hunk` | Node via fnm; a review-first diff viewer |

What each profile and pack installs is in [docs/profiles.md](docs/profiles.md). macOS needs Homebrew. On Linux, `minimal` and `remote` also install without it, and anything the distro lacks is skipped with a link to its upstream installer.

## Everyday commands

```bash
claude | codex                           # AI CLIs, sandboxed by their own native settings
claude -w NAME                           # Claude Code in its own git worktree, for parallel agents
agents                                   # sessions, stale processes, hogs (--pack monitoring)
sbx -- CMD                               # any command under the strict Seatbelt profile (macOS)
t [NAME]                                 # attach-or-create a tmux session (--pack tmux)
make check                               # health check for the installed profile
make update                              # profile-aware, drift-detecting update
make theme NAME=catppuccin-mocha         # re-theme tmux, Ghostty and Starship
make help                                # every target
```

Every key binding and command is listed in [docs/CHEATSHEET.md](docs/CHEATSHEET.md).

## What it changes on your machine

- `~/.zshrc`, `~/.config/starship.toml` and `~/.ssh/config` get `# >>> tuidev managed (...) >>>` blocks. Everything outside the markers is yours. `~/.config/tmux/tmux.conf` gets the same with `--pack tmux`.
- AI CLI settings (`~/.claude/settings.json`, `~/.codex/config.toml`) are placed only where absent or unmodified. An edited `~/.claude/settings.json` gets new shipped settings merged in, and your values win ([docs/updating.md](docs/updating.md#shipped-configs-you-may-have-edited)).
- Anything tuidev replaces is backed up to `~/.config/tuidev/backups/` first.
- `~/.config/tuidev/manifest` records what was installed. `./uninstall.sh` removes only those records: a `ripgrep` you already had survives, and so do CLI logins and session state.
- tuidev sends no telemetry.

## Documentation

| Doc | Covers |
|-----|--------|
| [Quick start](docs/QUICK_START_GUIDE.md) | Install to first sandboxed agent session |
| [Cheatsheet](docs/CHEATSHEET.md) | Session commands, tmux keys, aliases, Makefile |
| [FAQ](docs/FAQ.md) | Troubleshooting |
| [Profiles and packs](docs/profiles.md) | What each profile and pack installs |
| [Sandboxing](docs/sandboxing.md) | Native CLI sandboxes, `sbx`, Seatbelt profiles, credential deny list |
| [Agent workflows](docs/agent-workflows.md) | AI CLIs, editor integration, agent teams, worktrees, Herdr, `agents` and the menu bar, notifications |
| [Orchestration](docs/orchestration.md) | The `orchestration` pack: subagent tiers, skills, git gates, CI runners |
| [Remote and mobile](docs/remote.md) | Tailscale, SSH, mosh, always-on nodes, iOS clients |
| [Neovim](docs/nvim.md) | The `nvim` pack: LazyVim essentials |
| [Vim](docs/vim.md) | The `vim` pack: a zero-plugin vimrc for servers |
| [Theming](docs/theming.md) | Palette contract and `theme.sh` |
| [Updating](docs/updating.md) | Updates, migrations, the install manifest, uninstall |
| [Engineering](docs/engineering.md) | Architecture, shared libs, pack contract, verification, screenshots |
| [Roadmap](docs/roadmap.md) | Watch-list and adopt/hold criteria |
| [VISION.md](VISION.md) | Principles and non-goals |
| [AGENTS.md](AGENTS.md) / [CLAUDE.md](CLAUDE.md) | Instructions for AI agents working on this repo |
| [AGENTS template](templates/AGENTS_TEMPLATE.md) | Starter `AGENTS.md` for your own projects |
| [Migrations](scripts/migrations/README.md) | Script-level contract for one-shot migrations |
| [Screenshot tapes](docs/assets/tapes/README.md) | Demo fixtures and VHS tapes behind the README images |
| [CONTRIBUTING.md](CONTRIBUTING.md) / [SECURITY.md](SECURITY.md) / [Code of Conduct](CODE_OF_CONDUCT.md) | Contributing and reporting |
| [CHANGELOG.md](CHANGELOG.md) | Release history |

## Contributing

Issues and PRs are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) and [VISION.md](VISION.md) first, and run `make ci-test` before you push.

## License

[MIT](LICENSE). Sponsored by [SpiceFactory](https://spfr.co).
