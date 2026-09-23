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

| Component | minimal | desktop | remote |
|-----------|:-------:|:-------:|:------:|
| Shell, prompt, CLI tools (core) | ✓ | ✓ | ✓ |
| Ghostty config, Rectangle, Stats, Maccy, Hidden Bar (ui) | | ✓ | |
| `sbx` + Seatbelt profiles (sandbox, macOS) | | ✓ | ✓ |
| Tailscale, mosh, SSH client and sshd config (remote) | | | ✓ |
| tmux, the `tuidev-tmux` block, TPM (`--pack tmux`) | | | ✓ |
| Neovim, LazyVim config (`--pack nvim`) | | | |
| Optional packs (`--pack NAME`) | + | + | + |

Neither `desktop` nor `minimal` installs tmux or Neovim by default — add `--pack tmux` and/or `--pack nvim` yourself. An existing install that already had them keeps them: see [updating.md](updating.md#migrations) for the migration that carries them into your profile.

## Built-in packs

**`--core`** (`scripts/install/core.sh`)
: `bat`, `eza`, `fd`, `fzf`, `gh`, `git`, `git-delta`, `jq`, `ripgrep`, `shellcheck`, `starship`, `yq`, `zoxide`, and the zsh plugins `zsh-autosuggestions`, `zsh-completions` and `zsh-syntax-highlighting`. On macOS it also installs the Ghostty app. The installer then writes the managed blocks for `~/.zshrc` and `~/.config/starship.toml`, and sets [git defaults](#git-defaults).

**`--ui`** (macOS only)
: The Ghostty config (as a managed block), and the Rectangle, Stats, Maccy and Hidden Bar casks. The hotkeys are in the [cheatsheet](CHEATSHEET.md#macos-hotkeys-desktop-profile).

**`--sandbox`** (macOS only)
: `sbx` in `~/.local/bin` and the Seatbelt profiles in `~/.config/tuidev/sandbox/`. See [sandboxing.md](sandboxing.md).

**`--remote`**
: Tailscale (a Homebrew cask on macOS; on Linux, a link to the official installer), mosh, the SSH client config as a managed block, and sshd hardening snippets (these are copied only when `/etc/ssh/sshd_config.d` is writable, and otherwise printed as `sudo` commands). See [remote.md](remote.md).

**`--extras`**
: `atuin`, `bandwhich`, `broot`, `duf`, `dust`, `fastfetch`, `glow`, `httpie`, `hyperfine`, `lazygit`, `ncdu`, `procs`, `sd`, `tealdeer`, `tokei`. Every one is optional: whatever the package manager lacks is skipped.

## Optional packs

| Pack | Installs |
|------|----------|
| `--pack ai-clis` | Adopts/upgrades `~/.claude/settings.json` and `~/.codex/config.toml`, which turn on Claude Code's and Codex's native sandboxes. Does not install the CLIs, which update themselves. See [agent-workflows.md](agent-workflows.md) and [sandboxing.md](sandboxing.md). |
| `--pack orchestration` | The multi-agent policy for Claude Code and Codex: a rule file in `~/.claude/rules/`, a managed block in `~/.codex/AGENTS.md`, tiered subagents, and the `delegation` and `verification` skills. Pair it with `ai-clis`, which holds the git and gh write gates. Also runs on its own, without the rest of tuidev. See [orchestration.md](orchestration.md). |
| `--pack opencode` | `oc` wrapper for OpenCode, and adopts `opencode.json` + `tui.json`. Prints OpenCode's official installer command rather than running it. |
| `--pack nvim` | `neovim`, and the LazyVim config in `configs/nvim/`, deployed file by file with `--upgrade-shipped`, only while tuidev owns the tree. See [nvim.md](nvim.md). |
| `--pack tmux` | `tmux`, the `tuidev-tmux` managed block in `~/.config/tmux/tmux.conf`, and TPM (tmux-resurrect, tmux-continuum). Included by the `remote` profile. |
| `--pack herdr` | [Herdr](https://herdr.dev/), an agent-aware runtime for fleet attention, installed through Homebrew. When Homebrew has no formula, the pack prints the official installer command instead. Adopts a Tokyo Night `~/.config/herdr/config.toml`. |
| `--pack cmux` | [cmux](https://github.com/manaflow-ai/cmux), a macOS terminal app for parallel agents (macOS 14+). |
| `--pack sandbox-container` | Tier 2 sandboxing: finds a container runtime (Apple `container`, then Podman, then Docker), installs Podman only when none exists, and starts it. See [sandboxing.md](sandboxing.md#tier-2-containers). |
| `--pack mosh` | mosh on its own, without the rest of `--remote`. |
| `--pack fnm` | fnm (Fast Node Manager), which `.zshrc` prefers over nvm when present. |
| `--pack monitoring` | `lazydocker` (`lzd`), `k9s`, `bottom` (`btm`, aliased as `top`). |

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
