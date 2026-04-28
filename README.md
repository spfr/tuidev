# tuidev — macOS terminal dev setup

> Opinionated, terminal-first developer environment built around **tmux durability**, **sandboxed AI agents**, and **layered installation**.

![macOS](https://img.shields.io/badge/macOS-000000?style=flat&logo=apple)
![Linux](https://img.shields.io/badge/Linux-FCC624?style=flat&logo=linux&logoColor=black)
![License](https://img.shields.io/badge/license-MIT-blue)

## What this is

A small, opinionated set of configs + install scripts for an AI-assisted coding workflow. Three ideas shape it:

1. **One session, one pane, one task.** Your work has to survive disconnects, narrow terminals, and mobile reattaches. tmux is the durability layer; splits are a local bonus, not the story.
2. **Sandbox by default.** AI agents run inside macOS Seatbelt by default. Credentials (`~/.ssh`, `~/.aws`, keychain) are locked out even if the agent is compromised.
3. **Layered install.** Pick a profile (`minimal`, `desktop`, `remote`) or compose packs (`--core`, `--remote`, `--sandbox`, `--ui`, `--extras`, `--pack zellij`, ...). Your `~/.zshrc` is never overwritten — edits outside the tuidev-managed block survive forever.

## Quick start

```bash
git clone https://github.com/spfr/tuidev.git
cd tuidev
./install.sh --profile desktop    # or: minimal | remote
exec zsh -l

work myproject                    # bare tmux session, attach-or-create
dev                               # nvim | agent | runner
ai                                # nvim + 2 agent panes
sbx -- cc                         # Claude Code under Seatbelt
```

## The three profiles

| Profile   | Packs                          | For                                       |
|-----------|--------------------------------|-------------------------------------------|
| `minimal` | core                           | Remote servers, VMs, CI runners           |
| `desktop` | core + ui + sandbox            | **Default** — local macOS laptop/desktop  |
| `remote`  | core + remote + sandbox        | Headless machines, Tailscale nodes        |

Compose your own: `./install.sh --core --sandbox --pack zellij`. Full matrix in [docs/profiles.md](docs/profiles.md).

## Session commands (tmux-first)

All commands are attach-or-create and accept an optional session name:

| Command          | Layout                                          |
|------------------|-------------------------------------------------|
| `work [name]`    | bare named session (default: `$(basename $PWD)`) |
| `dev [name]`     | nvim 55% ∣ agent 25% ∣ runner 20%               |
| `ai [name]`      | nvim 60% + two agent panes                       |
| `ai-single`      | nvim + one shell                                |
| `ai-triple`      | nvim + three agent panes                         |
| `agents [name]`  | three columns: claude ∣ codex ∣ gemini          |
| `fullstack`      | five windows: code / web / api / db / logs      |
| `multi`          | three windows: dev / monitor / git              |
| `remote [name]`  | minimal nvim + shell for narrow terminals        |
| `tls` / `tk` / `tka` | list / kill named / kill all tmux sessions |

**Coming from the old Zellij-first setup?** See [docs/migration.md](docs/migration.md). The `z*` namespace (zdev, zwork, zai, ...) activates automatically once you install `--pack zellij`.

## Sandboxed agents

Claude Code, Codex, Gemini, and OpenCode are routed through a Seatbelt wrapper:

```bash
cc                          # = sbx -- claude (strict profile by default)
CC_NO_SANDBOX=1 cc          # one-shot escape hatch
sbx --profile standard -- npm ci   # wider network for package installs
sbx --profile off -- some-tool     # documented pass-through
```

Three profiles are shipped: **strict** (agent runs, LLM APIs work, package installs don't), **standard** (adds GitHub, npm, PyPI, crates, registries), **off** (escape hatch). The agent can read most of `$HOME` but **cannot** read `~/.ssh`, `~/.aws`, `~/.gnupg`, `~/Library/Keychains`, `~/.config/gh`, `~/.docker`, `~/.kube`, `~/.netrc` — ever.

Full details, including customization and troubleshooting: [docs/sandboxing.md](docs/sandboxing.md).

Tier 2 — Podman-backed microVMs — is available behind `./install.sh --pack sandbox-container` when you need kernel-namespace isolation. Docker Desktop / OrbStack are deliberately **not** used (not FOSS).

## Core tools

| Tool | Purpose |
|------|---------|
| [tmux](https://github.com/tmux/tmux) | Primary multiplexer — durable sessions |
| [Neovim](https://neovim.io/) + LazyVim | Editor (AI stays external by design) |
| [Ghostty](https://ghostty.org/) | Native macOS tabs/splits (desktop profile) |
| [Starship](https://starship.rs/) | Prompt |
| [ripgrep](https://github.com/BurntSushi/ripgrep) / [fd](https://github.com/sharkdp/fd) / [fzf](https://github.com/junegunn/fzf) | Search + find + fuzzy |
| [zoxide](https://github.com/ajeetdsouza/zoxide) | Smarter `cd` |
| [git-delta](https://github.com/dandavison/delta) | Git diffs |
| [lazygit](https://github.com/jesseduffield/lazygit) | Git TUI |
| [HTTPie](https://httpie.io/) | Friendly HTTP requests via `http` |
| [jq](https://stedolan.github.io/jq/) / [yq](https://github.com/mikefarah/yq) | JSON / YAML |
| [eza](https://github.com/eza-community/eza) / [bat](https://github.com/sharkdp/bat) | `ls` / `cat` replacements |

Optional: `--pack zellij` (alternative multiplexer), `--pack yazi` or `--pack nnn` (file manager), `--pack monitoring` (lazydocker, k9s, bottom), `--pack sandbox-container` (Podman), `--extras` (atuin, dust, broot, bandwhich, duf, hyperfine, tokei).

## AI CLIs

| Tool | Shell function | Notes |
|------|----------------|-------|
| [Claude Code](https://claude.ai/code) | `cc` | Primary; hooks in `configs/claude/settings.json` |
| [Codex CLI](https://github.com/openai/codex) | `cx` | Defaults in `configs/codex/config.toml` (workspace-write, on-request) |
| [Gemini CLI](https://github.com/google-gemini/gemini-cli) | `gem` | Optional |
| [OpenCode](https://opencode.ai) | `oc` | Multi-model |

All four auto-route through `sbx` when installed. Philosophy: **AI stays in external panes**. `configs/nvim/lua/plugins/ai.lua` is intentionally empty. (ACP-driven in-editor agents are a conscious non-goal; see VISION.md.)

## Remote workflow

Tailscale SSH + tmux is the durable path:

```bash
ssh my-dev-box      # Tailscale handles ACLs, SSO, no key sprawl
tmux attach -t main # your session survived the disconnect
```

mosh is an optional upgrade for flaky networks (`--pack mosh`). Full setup in [docs/remote.md](docs/remote.md). iOS clients: Blink, Moshi.

## Day-to-day

```bash
make check            # health check against installed profile
make test             # run core tests + any tags the active profile enables
make update           # profile-aware, drift-detecting update
make sbx-test         # prove the sandbox blocks creds and allows project writes
make help             # every available target
```

## Documentation

| Doc | What it covers |
|-----|----------------|
| [docs/profiles.md](docs/profiles.md) | Every profile and pack, tool matrix |
| [docs/sandboxing.md](docs/sandboxing.md) | Seatbelt profiles, escape hatches, Tier 2 pointer |
| [docs/remote.md](docs/remote.md) | Tailscale + tmux + mosh workflow |
| [docs/migration.md](docs/migration.md) | Upgrading from the old Zellij-first setup |
| [VISION.md](VISION.md) | Product direction + 2026 amendments |
| [AGENTS.md](AGENTS.md) | Universal instructions for AI coding agents |
| [CLAUDE.md](CLAUDE.md) | Claude Code–specific guidance for this repo |

Additional references live in `docs/`: CHEATSHEET, ARCHITECTURE, NEOVIM_QUICKSTART, TERMINAL_NAVIGATION, FAQ, IPHONE_SSH_CLIENTS, ZELLIJ_TROUBLESHOOTING.

## Safety and non-destructiveness

- `~/.zshrc` is written as a managed block (`# >>> tuidev managed (...) >>>`). User edits outside the block survive forever.
- `~/.config/nvim` is **backed up** (timestamped) before new config lands — never `rm -rf`'d.
- AI CLI settings (`~/.claude.json`, `~/.config/opencode/opencode.json`, `~/.codex/config.toml`) are `--adopt-existing` by default: if present, they are left alone.
- Backups live in `~/.config/tuidev/backups/`.
- `--dry-run` on any install or update command shows every mutation without performing it.

## Contributing

Issues and PRs welcome. See [VISION.md](VISION.md) and [docs/](docs/) for context on direction. Code style: keep packs self-contained, tests tagged, docs terse.

## License

MIT. Sponsored by [SpiceFactory](https://spfr.co).
