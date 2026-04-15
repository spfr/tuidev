# Vision

## 2026 Amendments

The original vision below was authored before several early-2026 shifts in the agentic-coding landscape. These amendments supersede the relevant sections without rewriting the body.

1. **Sandbox default is macOS Seatbelt (`sandbox-exec`), not Docker.** Anthropic shipped native sandboxing for Claude Code in early 2026 using `sandbox-exec` on macOS and `bubblewrap` on Linux, with first-class file and network boundary configuration. This is now Tier 1. Docker Desktop / OrbStack are deliberately skipped because they are not FOSS. The heavier optional tier is **Podman machine** (FOSS, daemonless, VM-backed) exposed via `--pack sandbox-container`.

2. **tmux is the default multiplexer. Zellij is an opt-in pack.** The original "keep Zellij optional" wording was soft. The concrete change: `ai`, `dev`, `work`, `fullstack`, `multi`, `remote` shell functions dispatch to tmux. Zellij-equivalent wrappers are namespaced `zai`, `zdev`, `zwork`, …, and only activate when `--pack zellij` is installed.

3. **Claude Code / Codex native controls are canonical.** `configs/claude/settings.json` and a new `configs/codex/config.toml` carry the authoritative policy (`PermissionDenied` hook, `MCP_CONNECTION_NONBLOCKING`, `sandbox_mode=workspace-write`, `approval_policy=on-request`). The repo's `sbx` wrapper is a uniform UX layer on top, not a replacement.

4. **Neovim stays lean. ACP not adopted.** Agent Client Protocol matured and can drive Nvim in-editor, but the "AI runs in external panes" principle holds. `configs/nvim/lua/plugins/ai.lua` remains intentionally empty. Users who want in-editor agents can add ACP themselves; the repo will not ship it by default.

## What This Project Should Become

This project should become an opinionated, minimal, macOS-first terminal development system for AI-assisted coding.

It should stop trying to be a broad "install everything" bootstrapper and become a smaller, sharper system with three priorities:

1. Best local coding experience on macOS.
2. Safe-by-default execution for AI agents through sandboxed workspaces.
3. Strong remote and mobile continuity when needed, without making that the whole product.

## What The Review Found

The current repo is solid in basic script quality, but the product direction is split.

- The docs and defaults center the "nvim + multiple side panes" workflow, which is good locally, but the repo does not clearly distinguish between local-first ergonomics and remote continuity.
- The actual long-term architecture still needs to support remote and mobile use, but that should reinforce the local workflow rather than replace it.
- Zellij is treated as primary even though its modal key model conflicts with modern AI CLIs, especially around `Ctrl+g`.
- The installer is too broad. It installs terminal tools, GUI apps, remote tools, editors, AI helpers, and system tweaks in one pass.
- The update flow is package-centric and file-copy-centric, but not policy-centric. It does not separate core from optional, or safe host setup from sandbox runtime setup.
- The test and health scripts assume "missing optional GUI app" means failure, which is the wrong signal for a lean terminal-first system.

## Direction

The project should optimize for this workflow:

1. Open the best local terminal environment on macOS.
2. Get fast editor, shell, git, and agent workflows immediately.
3. Use tabs, splits, and sessions intentionally, without keybinding friction.
4. Run agents inside a sandboxed project environment by default.
5. Reattach remotely when needed without changing the core workflow.

That means:

- `Ghostty` becomes the preferred local terminal on macOS.
- `tmux` becomes the primary session layer.
- `Zellij` becomes optional or is removed from the default path.
- remote access is built around `Tailscale SSH` plus `mosh` where available, when needed.
- host installs are kept minimal.
- project execution happens inside containers or VMs, not directly on the host by default.

## Product Principles

### 1. Local-First, But Durable

The primary workflow should be the best local macOS coding experience.

But if that workflow falls apart when the user reconnects remotely, changes networks, or drops to a single terminal, the architecture is brittle.

Desktop splits are useful, but they are a bonus. The core experience should survive:

- high latency
- roaming networks
- temporary disconnects
- narrow terminals
- keyboard-only operation

### 2. Productive Local UI, Not Pane Maximalism

Multiple panes are useful locally, especially on a large screen, but they should be a deliberate productivity tool rather than the whole product story.

The default mental model should be:

- one session
- one current pane
- one current task
- fast switching between windows/panes

This is the right fallback model for:

- focused local work
- long-running agent jobs
- remote development
- resilient reconnects

### 3. Sandbox First, Not Permission Prompts First

The system should not normalize running AI tools directly on the host with broad access.

The right default is:

- the host machine is trusted but stable
- projects run in isolated environments
- agents get broad access inside the sandbox
- escalation to host access is explicit and rare

This removes the worst UX pattern: repeated permission prompts in an unsafe host environment.

## Opinionated Technical Position

### Multiplexer Strategy

`tmux` should be the default and primary session layer.

Why:

- It is fundamentally built around durable sessions that can be detached and reattached cleanly.
- The official tmux docs still frame one of its main uses as protecting remote programs from connection drops and reattaching from another terminal.
- It is a better foundation for continuity across local and remote use than a modal desktop-style workspace manager.
- Claude agent teams already integrate with tmux split-pane mode.
- Its prefix model is easier to keep out of the way of editor and AI CLI shortcuts than Zellij's lock-mode model.

`Zellij` should not remain the default primary interface.

Why:

- The repo explicitly binds `Ctrl+g` to lock mode in [configs/zellij/config.kdl](/Users/miloszikic/workspace/playground/mactui_setup/configs/zellij/config.kdl:138).
- Zellij documents `Ctrl` as the primary modifier and `Alt` as the secondary modifier, and exposes `Ctrl+g` flows in its unlock-first preset.
- That is exactly the kind of modal interception that clashes with terminal-native tools and Vim-adjacent AI CLIs.
- The shell wrappers also make Zellij the default entrypoint for `dev`, `work`, `ai`, `ai-single`, `ai-triple`, `remote`, `fullstack`, and `multi` in [configs/zsh/.zshrc](/Users/miloszikic/workspace/playground/mactui_setup/configs/zsh/.zshrc:344).

Decision:

- Make `tmux` primary.
- Keep `zellij` as optional experimental local workflow support for now.
- Remove Zellij-first language from README and install defaults.
- Revisit deletion once tmux session UX and docs are complete.

### Local Terminal Strategy

`Ghostty` should be the preferred local terminal on macOS.

Why:

- Ghostty now has native tabs and splits on macOS, plus AppleScript automation for windows, tabs, terminals, and layouts.
- That makes Ghostty the right local shell surface without forcing the multiplexer to carry all UX responsibilities.

Decision:

- Use Ghostty for the best local tabs, splits, and windows.
- Use tmux for sessions, persistence, remoting, and single-view workflows.
- Do not depend on Ghostty-specific features for the core remote architecture.

### Remote Access Strategy

Remote access should standardize on:

- `Tailscale SSH` or standard `ssh` for authenticated connectivity
- `mosh` only for unstable or roaming networks
- `tmux` on the remote machine for durable sessions

Why:

- Tailscale SSH supports policy-based access and check mode, including stricter re-auth flows for high-risk access.
- Mosh is explicitly designed for roaming, intermittent connectivity, and high-latency links, but that is a specific remote-use optimization rather than a universal requirement.
- Mosh itself recommends using `screen` or `tmux` on the remote side because scrollback is only partially synchronized.

Decision:

- Make `ssh device` and `tmux attach` the standard continuity story.
- Document `mosh device` as the fallback for flaky Wi-Fi, mobile hotspots, roaming networks, and sleep/wake-heavy workflows.
- De-emphasize Cloudflare tunnel as a default.
- Keep tunnels as fallback, not primary architecture.

### Sandboxing Strategy

The project should adopt "sandbox by default, broad permissions inside sandbox" as the central execution model.

Recommended baseline:

- macOS host:
  - keep host setup thin
  - run projects in Docker Desktop with Enhanced Container Isolation if available
  - or run projects in Podman machine if users want a VM-backed open-source runtime
- Linux host:
  - use Docker or Podman rootless where practical
- agent runtime:
  - give the agent broad permissions inside the sandboxed project environment
  - avoid broad host-level permissions by default

Why:

- Docker says Enhanced Container Isolation is designed to prevent malicious containers from compromising Docker Desktop or the host system, and notes that even `--privileged` containers remain contained under ECI.
- Podman documents that on macOS each Podman machine is backed by a virtual machine, which is a reasonable isolation boundary for local agent execution.

Decision:

- Add first-class sandbox docs and setup flows.
- Treat host-native execution as an opt-out expert mode.
- Design the repo around project sandbox launchers, not just host shell aliases.

## Minimal Default Toolset

The default install should be aggressively smaller.

### Core Required

- `tmux`
- `ghostty` on macOS
- `neovim`
- `ripgrep`
- `fd`
- `bat`
- `fzf`
- `zoxide`
- `starship`
- `git-delta`
- `lazygit`
- `jq`
- `yq`
- `tailscale`

### Optional Packs

- `zellij`
- `mosh`
- `yazi` or `nnn` but not both by default
- `lazydocker`
- `k9s`
- `atuin`
- `broot`
- `bandwhich`
- `dust`
- `duf`
- `hyperfine`
- `tokei`
- GUI helpers like Rectangle, Stats, Maccy, Hidden Bar, Hammerspoon

Rule:

- if a tool is not essential to the core workflow, it should not be installed by default
- optional packs should be explicit flags like `--pack ui`, `--pack ops`, `--pack extras`

## Required Repo Changes

### 1. Reposition The README

The README should stop presenting wide split layouts as the whole story.

The new story should be:

- best local macOS terminal workflow
- tmux primary for session continuity
- Ghostty primary for local UX
- sandboxed agents
- remote continuity when needed, with `mosh` as an optional optimization rather than a default dependency

### 2. Split Installation Into Layers

The current installer at [install.sh](/Users/miloszikic/workspace/playground/mactui_setup/install.sh:184) installs a large mixed set of tools and GUI apps, then overwrites core shell/editor config files.

Replace it with layered commands:

- `./install.sh --core`
- `./install.sh --remote`
- `./install.sh --sandbox`
- `./install.sh --ui`
- `./install.sh --extras`

And add:

- `--no-overwrite`
- `--adopt-existing`
- `--profile minimal|desktop|remote`

### 3. Stop Overwriting Core Configs By Default

Current examples:

- shell config copy in [install.sh](/Users/miloszikic/workspace/playground/mactui_setup/install.sh:335)
- starship config copy in [install.sh](/Users/miloszikic/workspace/playground/mactui_setup/install.sh:460)
- zellij config copy in [install.sh](/Users/miloszikic/workspace/playground/mactui_setup/install.sh:509)

The project should move toward:

- additive includes
- template generation
- clear "managed block" boundaries
- no full-file replacement unless explicitly requested

### 4. Promote tmux Wrappers, Demote Zellij Wrappers

The shell config currently makes Zellij wrappers the main ergonomic path and tmux wrappers secondary in [configs/zsh/.zshrc](/Users/miloszikic/workspace/playground/mactui_setup/configs/zsh/.zshrc:344) and [configs/zsh/.zshrc](/Users/miloszikic/workspace/playground/mactui_setup/configs/zsh/.zshrc:456).

This should invert.

The default user commands should become something like:

- `work`
- `dev`
- `ai`
- `remote`

All tmux-backed.

If Zellij remains, its commands should be explicitly namespaced, for example:

- `zdev`
- `zai`
- `zremote`

### 5. Fix Test Semantics

The current test suite and health check treat missing optional GUI apps as failures or strong negatives, which distorts the signal for a lean system.

Examples:

- GUI checks in [scripts/health_check.sh](/Users/miloszikic/workspace/playground/mactui_setup/scripts/health_check.sh:57)
- GUI tests in [scripts/test_suite.sh](/Users/miloszikic/workspace/playground/mactui_setup/scripts/test_suite.sh:67)

The new test model should separate:

- required core
- optional extras
- local desktop enhancements
- sandbox runtime health

### 6. Make Update Policy A First-Class Concept

The update script is useful, but it is still a package and file sync tool, not an environment policy tool.

Current behavior in [scripts/update.sh](/Users/miloszikic/workspace/playground/mactui_setup/scripts/update.sh:123) and [scripts/update.sh](/Users/miloszikic/workspace/playground/mactui_setup/scripts/update.sh:312):

- checks a hardcoded package list
- diffs copied config files
- pulls the repo

It should evolve into:

- profile-aware updates
- core vs optional update streams
- config drift detection with managed/unmanaged boundaries
- sandbox image updates
- security posture checks

## Proposed Architecture

### Host

The host should provide:

- terminal emulator
- tmux
- editor
- SSH/Tailscale/Mosh
- a container or VM runtime

It should not be the default execution surface for agent-driven project mutation.

### Project Runtime

Each project should have:

- a reproducible sandbox definition
- mounted working tree
- persistent caches where needed
- a standard way to launch agent CLIs inside the sandbox

Candidate forms:

- Docker Compose dev environment
- `devcontainer.json`
- Podman machine plus per-project container

### Session Model

The stable session model should be:

- local terminal
- remote SSH or local shell
- tmux server
- project sandbox
- shells/editor/agents inside that sandbox

## Concrete Near-Term Roadmap

### Phase 1: Clarify

- add this vision document
- rewrite README positioning
- define supported modes: `minimal`, `remote`, `desktop`
- mark Zellij as optional, not primary

### Phase 2: Slim Down

- split install into core and optional packs
- reduce default package set
- stop installing broad GUI extras by default
- keep only one default file manager

### Phase 3: tmux-First

- rename wrappers so tmux owns the default commands
- make mobile and single-terminal docs the primary docs
- keep Ghostty split recipes as local convenience docs

### Phase 4: Sandbox-First

- add documented sandbox runtime choices
- add project launcher commands
- add "run agent inside sandbox" scripts
- define host vs sandbox permission policy

### Phase 5: Better Validation

- rewrite health checks around profiles
- test core separately from extras
- add sandbox health checks
- add remote workflow smoke tests

## Explicit Non-Goals

This project should not try to be:

- a giant personal dotfiles repo
- a kitchen-sink brew installer
- a showcase for every modern Rust CLI
- a workflow that depends on a 16:9 desktop full of panes
- a system where AI agents run unsandboxed on the host by default

## Current Recommendation

Until the repo is simplified, the recommended target state is:

- Ghostty as the preferred local macOS terminal
- tmux as the primary session layer
- Zellij optional only
- `ssh` or Tailscale SSH for normal remote access
- `mosh` only as an optional upgrade for unstable or mobile networks
- containerized or VM-backed agent execution by default
- a much smaller default package set

That is the direction that best matches the actual goal: high local developer productivity on macOS, opinionated engineering defaults, durable sessions, and safer agent execution.

## Sources

These sources were used to ground the direction above:

- Ghostty features: native tabs/splits and AppleScript automation on macOS
  - https://ghostty.org/docs/features
- Zellij modifier model and rebinding guidance
  - https://zellij.dev/documentation/changing-modifiers.html
- tmux remote-session rationale
  - https://github.com/tmux/tmux/wiki/Getting-Started
- Tailscale SSH policy and check mode
  - https://tailscale.com/docs/features/tailscale-ssh
- Mosh roaming and remote resilience
  - https://mosh.org/
- Docker Enhanced Container Isolation
  - https://docs.docker.com/enterprise/security/hardened-desktop/enhanced-container-isolation/
- Podman on macOS using a VM-backed machine
  - https://podman.io/docs/installation
