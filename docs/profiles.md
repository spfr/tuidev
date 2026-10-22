# Profiles and Packs

A **pack** is one install script. There are five built-in packs, each selected by its own flag (`--core`, `--remote`, `--sandbox`, `--ui`, `--extras`), and a set of optional packs, each selected with `--pack NAME`. A **profile** is a named set of built-in packs. Profiles are shortcuts, not walls: combine a profile with more flags, or skip profiles and compose packs directly.

```bash
./install.sh --profile desktop                      # a profile
./install.sh --profile desktop --pack ai-clis        # a profile plus an optional pack
./install.sh --core --sandbox --pack herdr           # no profile: built-in packs by flag
./install.sh --pack nvim                             # add one pack to an existing install
```

With no flags, `./install.sh` doesn't ask: it installs `desktop` on macOS and `minimal` on Linux. Unknown `--pack` names are rejected before anything runs. Re-running is safe. On an existing install, pending [migrations](updating.md#migrations) run before any pack. Every run is merged into `~/.config/tuidev/profile`, so a later `--pack` run keeps what you picked before.

**Package managers.** macOS uses Homebrew, and the installer warns and skips packages if Homebrew is missing. On Linux, packs use Homebrew when it is installed, and otherwise `apt-get`, `dnf` or `pacman`, in that order (`scripts/lib/pkg.sh`). System package managers run only as root or through passwordless `sudo`. Otherwise the exact command is printed. A tool the distro doesn't package is skipped with a link to its upstream installer. tuidev never pipes a remote script into a shell for you.

## Profiles

| Profile   | Equivalent to                              | For |
|-----------|---------------------------------------------|-----|
| `minimal` | `--core`                                    | Servers, VMs, CI runners, anyone who wants only the terminal layer |
| `desktop` | `--core --ui --sandbox`                     | A Mac with a display: the daily driver |
| `remote`  | `--core --remote --sandbox --pack tmux`     | A headless machine or Tailscale node you SSH into |
| `full`    | `--core --ui --sandbox --extras --pack ai-clis --pack orchestration --pack monitoring --pack cooling --pack herdr --pack tmux --pack release-age` | The whole agent setup on a Mac, in one command |

| Component | minimal | desktop | remote | full |
|-----------|:-------:|:-------:|:------:|:----:|
| Shell, prompt, CLI tools (core) | ✓ | ✓ | ✓ | ✓ |
| Ghostty config, Rectangle, Maccy (ui) | | ✓ | | ✓ |
| `sbx` + Seatbelt profiles (sandbox, macOS) | | ✓ | ✓ | ✓ |
| lazygit, uv, atuin and the other extras (`--extras`) | | | | ✓ |
| Tailscale, mosh, SSH client and sshd config (remote) | | | ✓ | |
| tmux, the `tuidev-tmux` block, TPM (`--pack tmux`) | | | ✓ | ✓ |
| Claude Code and Codex settings, tiered subagents (`ai-clis`, `orchestration`) | | | | ✓ |
| `agents`, its menu bar, cooling fans, Herdr (`monitoring`, `cooling`, `herdr`) | | | | ✓ |
| A 3-day minimum release age for npm, bun and uv (`release-age`) | | | | ✓ |
| Neovim, LazyVim config (`--pack nvim`) | | | | |
| Vim, zero-plugin vimrc (`--pack vim`) | | | | |
| Optional packs (`--pack NAME`) | + | + | + | + |

Neither `desktop` nor `minimal` installs tmux or Neovim by default — add `--pack tmux` and/or `--pack nvim` yourself. An existing install that already had them keeps them: see [updating.md](updating.md#migrations) for the migration that carries them into your profile.

## Built-in packs

**`--core`** (`scripts/install/core.sh`)
: `bat`, `eza`, `fd`, `fzf`, `gh`, `git`, `git-delta`, `jq`, `ripgrep`, `shellcheck`, `starship`, `yq`, `zoxide`, and the zsh plugins `zsh-autosuggestions`, `zsh-completions` and `zsh-syntax-highlighting`. On macOS it also installs the Ghostty app. The installer then writes the managed blocks for `~/.zshrc` and `~/.config/starship.toml`, and sets [git defaults](#git-defaults).

**`--ui`** (macOS only)
: The Ghostty config (as a managed block), and the Rectangle and Maccy casks. Menu-bar items are hidden natively in System Settings. For CPU, memory, battery and thermal readings in the menu bar, add `--pack monitoring` (its SwiftBar menu replaces a stats app). The hotkeys are in the [cheatsheet](CHEATSHEET.md#macos-hotkeys-desktop-profile).

**`--sandbox`** (macOS only)
: `sbx` in `~/.local/bin` and the Seatbelt profiles in `~/.config/tuidev/sandbox/`. See [sandboxing.md](sandboxing.md).

**`--remote`**
: Tailscale (a Homebrew cask on macOS; on Linux, a link to the official installer), mosh, the SSH client config as a managed block, and sshd hardening snippets (these are copied only when `/etc/ssh/sshd_config.d` is writable, and otherwise printed as `sudo` commands). See [remote.md](remote.md).

**`--extras`**
: `atuin`, `broot`, `duf`, `dust`, `glow`, `hyperfine`, `lazygit`, `procs`, `sd`, `tealdeer`, `tokei`, `uv` (Python versions, venvs and tools), `xh` (HTTP client). Every one is optional: whatever the package manager lacks is skipped.

## Optional packs

| Pack | Installs |
|------|----------|
| `--pack ai-clis` | Adopts/upgrades `~/.claude/settings.json` and `~/.codex/config.toml`, which turn on Claude Code's and Codex's native sandboxes. Does not install the CLIs, which update themselves. See [agent-workflows.md](agent-workflows.md) and [sandboxing.md](sandboxing.md). |
| `--pack orchestration` | The multi-agent policy for Claude Code and Codex: a rule file in `~/.claude/rules/`, a managed block in `~/.codex/AGENTS.md`, tiered subagents, and the `delegation` skill. Pair it with `ai-clis`, which holds the git and gh write gates. Also runs on its own, without the rest of tuidev. See [orchestration.md](orchestration.md). |
| `--pack nvim` | `neovim`, and the LazyVim config in `configs/nvim/`, deployed file by file with `--upgrade-shipped`, only while tuidev owns the tree. See [nvim.md](nvim.md). |
| `--pack vim` | `vim` (on macOS the system Vim is used), and a zero-plugin vimrc deployed as `~/.vim/vimrc` with `--upgrade-shipped`. A `~/.vimrc` of your own wins. The light alternative to `nvim` for servers and small boxes. See [vim.md](vim.md). |
| `--pack tmux` | `tmux`, the `tuidev-tmux` managed block in `~/.config/tmux/tmux.conf`, and TPM (tmux-resurrect, tmux-continuum). Included by the `remote` profile. |
| `--pack herdr` | [Herdr](https://herdr.dev/), an agent-aware runtime for fleet attention: its release binary in `~/.local/bin/herdr` (macOS and Linux), checked against the sha256 its GitHub release lists, so `herdr update --handoff` can upgrade a running server without stopping its panes. `TUIDEV_HERDR_VERSION` pins a release. A herdr installed another way (mise, Nix) is left alone. Adopts a Tokyo Night `~/.config/herdr/config.toml`. |
| `--pack sandbox-container` | Tier 2 sandboxing: finds a container runtime (Apple `container`, then Podman, then Docker), installs Podman only when none exists, and starts it. See [sandboxing.md](sandboxing.md#tier-2-containers). |
| `--pack fnm` | fnm (Fast Node Manager): the only way the shipped `.zshrc` puts Node on `PATH`. `update.sh --packages` keeps each installed Node major on its latest patch ([updating.md](updating.md#node-fnm)). |
| `--pack hunk` | [hunk](https://hunk.dev), a review-first diff viewer for agent-written changesets (`hunk diff --watch`, `hunk show`). Homebrew only; 0.x, so opt-in. Nothing is written to `$HOME`: to page git through it, run `git config --global core.pager "hunk pager"`. |
| `--pack monitoring` | `lazydocker` (`lzd`), `bottom` (`btm`, aliased as `top`), and `agents` in `~/.local/bin` (its modules in `~/.local/lib/tuidev/agents/`): agent sessions, orphaned MCP and dev servers, CPU hogs, keep-awake and thermal pressure, with settings in `~/.config/agents.conf` (placed once, yours to edit). On macOS, also SwiftBar and an `agents` menu-bar plugin that doubles as a CPU, memory, battery and thermal readout, and `terminal-notifier`, which makes an agent's notification clickable: a click jumps to its session ([Notifications](agent-workflows.md#notifications)). See [agent-workflows.md](agent-workflows.md#local-processes-agents---pack-monitoring). |
| `--pack release-age` | A minimum release age (`TUIDEV_RELEASE_AGE_DAYS`, default 3) for npm, bun and uv, so a hijacked release is pulled before it can install here. Managed blocks in `~/.npmrc`, `~/.bunfig.toml` and uv's `uv.toml` (`[pip]` only), plus a `shell.d` fragment for `uvx` and `uv tool`; never project lockfiles. pnpm keeps its own 1-day default. Included in `full`. See [sandboxing.md](sandboxing.md#minimum-release-age). |
| `--pack cooling` | Apple Silicon only. `tuidev-fan` (`lib/fan/tuidev-fan.swift`), built with the Command Line Tools' `swiftc`, runs as the root LaunchDaemon `dev.tuidev.fan` and raises the fans with the SoC's sustained temperature (what the palm rest feels), from their minimum at 60 °C to their maximum at 95 °C by default, long before macOS would, so a MacBook stays cool to the touch under agent workloads. One `sudo` prompt installs it, and again only when its source changes. `agents cool` and the menu switch between cool (palms first), balanced, quiet, max and off. See [agent-workflows.md](agent-workflows.md#fans---pack-cooling). |

The canonical list of pack names is `TUIDEV_VALID_PACKS` in `scripts/lib/profile.sh`. Adding a pack is covered in [engineering.md](engineering.md#the-pack-contract).

## Git defaults

When `git` is installed, the installer sets these global keys, but only the ones you haven't already set — including values from `[include]`d files. It records each one so that `uninstall.sh` can unset exactly what it set:

`init.defaultBranch main`, `column.ui auto`, `branch.sort -committerdate`, `tag.sort version:refname`, `help.autocorrect prompt`, `commit.verbose`, `diff.algorithm histogram`, `diff.colorMoved default`, `diff.renames`, `merge.conflictStyle zdiff3` (git 2.35 or later), `rerere.enabled`, `rebase.autoSquash`, `rebase.autoStash`, `rebase.updateRefs`, `push.autoSetupRemote`, `push.followTags`, `fetch.prune`, and, when delta is installed, delta as the pager (`core.pager`, `interactive.diffFilter`) with navigation and line numbers. Delta is **not** set to side-by-side: agent panes are often around 80 columns wide. Toggle it per run with `git -c delta.side-by-side=true diff` or `delta -s`. For a large repo, run `git maintenance start` yourself: the installer only prints it as a tip.

## Picking a profile

- A Mac you work at: `desktop`.
- A machine you only SSH into: `remote`.
- A constrained server, VM or CI runner: `minimal`.
- Running AI agents: add `--pack ai-clis`, and `--pack orchestration` for tiered subagents.
- A terminal editor or a durable local tmux session: add `--pack nvim` / `--pack tmux`.
- Many agents across machines: add `--pack herdr`.
