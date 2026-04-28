# Install Profiles

## Overview

Profiles are pre-selected pack sets for common install shapes. They are shortcuts, not walls: every pack a profile enables can be added or omitted individually with `--pack NAME`. If a profile doesn't fit, compose packs directly. See [`VISION.md`](../VISION.md) for the architectural rationale and [`sandboxing.md`](sandboxing.md) for sandbox details.

## `minimal`

**For:** remote servers, slim VMs, CI runners, anyone who only needs the terminal layer.

**Command:**

```bash
./install.sh --profile minimal
# equivalent to:
./install.sh --core
```

**Contents:**

| Tool        | Purpose                                     |
|-------------|---------------------------------------------|
| zsh         | Login shell                                 |
| starship    | Prompt                                      |
| tmux        | Session multiplexer (durability layer)      |
| neovim      | Editor                                      |
| git, gh     | VCS + GitHub CLI                            |
| ripgrep, fd | Search                                      |
| fzf         | Fuzzy finder                                |
| eza, bat    | `ls` / `cat` replacements                   |
| zoxide      | Smarter `cd`                                |
| httpie      | Friendly HTTP requests via `http`           |
| claude      | Anthropic CLI                               |
| codex       | OpenAI CLI                                  |

No GUI apps, no sandbox profiles, no remote stack.

## `desktop`

**For:** local macOS developer with a display. The daily-driver shape.

**Command:**

```bash
./install.sh --profile desktop
# equivalent to:
./install.sh --core --ui --sandbox
```

**What's added over `minimal`:**

| Tool              | Purpose                                          |
|-------------------|--------------------------------------------------|
| Ghostty config    | Preferred local terminal (tabs, splits, AppleScript) |
| Rectangle         | Window snapping                                  |
| Stats             | Menu-bar system monitor                          |
| Maccy             | Clipboard history                                |
| Hidden Bar        | Menu-bar declutter                               |
| Hammerspoon       | macOS scripting / automation hooks               |
| Seatbelt profiles | `sandbox-exec` policies under `configs/sandbox/` |
| `sbx` wrapper     | Uniform UX for launching sandboxed agents        |

## `remote`

**For:** headless machine, Tailscale node, cloud dev box, anything you `ssh` into.

**Command:**

```bash
./install.sh --profile remote
# equivalent to:
./install.sh --core --remote --sandbox
```

**What's added over `minimal`:**

| Tool                | Purpose                                         |
|---------------------|-------------------------------------------------|
| tailscale           | Mesh VPN + Tailscale SSH                        |
| mosh                | Optional: roaming / high-latency SSH            |
| SSH config snippets | `~/.ssh/config` block for Tailscale hosts       |
| sshd_config.d       | Hardening snippets for incoming SSH             |
| Seatbelt profiles   | Agents sandboxed even without a display         |

See [`remote.md`](remote.md) for the workflow.

## Comparison Matrix

| Component           | minimal | desktop | remote |
|---------------------|:-------:|:-------:|:------:|
| zsh + starship      | ✓       | ✓       | ✓      |
| tmux                | ✓       | ✓       | ✓      |
| neovim              | ✓       | ✓       | ✓      |
| ripgrep / fd / fzf  | ✓       | ✓       | ✓      |
| claude / codex CLIs | ✓       | ✓       | ✓      |
| Ghostty config      |         | ✓       |        |
| Rectangle / Stats / Maccy / Hidden Bar |  | ✓ |    |
| Hammerspoon         |         | ✓       |        |
| Seatbelt + `sbx`    |         | ✓       | ✓      |
| Tailscale           |         |         | ✓      |
| mosh                |         |         | ✓      |
| SSH hardening       |         |         | ✓      |

## Packs Available Outside Profiles

Any of these can be added to any profile with `--pack NAME`:

- `--pack zellij` — Zellij multiplexer + `z*` shell wrappers (`zai`, `zdev`, `zwork`, …). See [`migration.md`](migration.md).
- `--pack yazi` — TUI file manager.
- `--pack nnn` — Minimal TUI file manager.
- `--pack monitoring` — `lazydocker`, `k9s`, `bottom` (`btm`).
- `--pack sandbox-container` — Podman machine for VM-backed sandboxing (Tier 2).
- `--pack mosh` — mosh on its own, without the full `--remote` pack.
- `--extras` — `atuin`, `dust`, `broot`, `bandwhich`, `duf`, `hyperfine`, `tokei`.

Example:

```bash
./install.sh --profile desktop --pack zellij --pack yazi
```

## Picking a Profile

- Do you have a display and work locally on this Mac? → `desktop`.
- Is this machine headless / only reached via SSH? → `remote`.
- Is this a constrained server, VM, or CI runner? → `minimal`.
- Do you want Zellij back after the tmux inversion? → any profile `--pack zellij`.
- Do you need Podman-based sandboxing? → any profile `--pack sandbox-container`.
- Unsure? → `desktop` on your laptop, `remote` on everything you SSH into.
