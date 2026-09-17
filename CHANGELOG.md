# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

---

## [2.3.1] - 2026-09-17

Herdr 0.9.x fleet practices and one zsh fix.

### Changed
- **Herdr docs and pack hints track Herdr 0.9.x.** 0.9.0 moved the TUI into
  each client and 0.9.1 added `herdr --machine <label> <cmd>`, so the
  fleet docs (`agent-workflows.md`, `remote.md`, `CHEATSHEET.md`,
  `agent-primer.md`, `AGENTS.md`) now show `herdr machine add` as the way to
  keep an always-on node in the sidebar and `herdr --machine NODE agent list`
  instead of `ssh node -- herdr agent list`. New practices: upgrade the client
  and leave a compatible server running (`herdr status` reports
  `server_binary_stale`), restart servers only when agents are idle or with
  `--handoff`, keep one `herdr` binary per node, and re-run
  `herdr integration status` after every upgrade. The pack prints the matching
  upgrade path (`brew upgrade herdr` vs `herdr update`) and the integration
  reminder.

### Removed
- zsh: the `alias ssh='TERM=xterm-256color ssh'` "Ghostty SSH fix". It shadowed Ghostty's own `ssh` wrapper (the `ssh-terminfo` shell-integration feature already copies `xterm-ghostty` terminfo to remote hosts), so every hop lost truecolor and the automatic terminfo install.

---

## [2.3.0] - 2026-09-15

Opinionated and current. tmux is the only multiplexer, the AI-CLI configs
match the September 2026 docs, containers prefer Apple's native runtime, and
the Linux parity image builds in seconds instead of tens of minutes.

### Removed

- **The Zellij pack.** tmux is the only multiplexer: Claude Code's agent-team
  split panes, Herdr, bosun and cmux all target or sit beside tmux, and every
  Zellij layout already existed as a tmux script. Gone: `--pack zellij`,
  `configs/zellij/` (config + 7 KDL layouts), the `z*` shell wrappers, the KDL
  validator, `scripts/clean-zellij.sh`, `docs/ZELLIJ_TROUBLESHOOTING.md`,
  `docs/migration.md` and `make migrate` (the 2.0 zellij→tmux guide), and the
  Ghostty `ctrl+p` pass-through that existed for Zellij. Migration
  `202609151300_remove_zellij_pack` backs up and removes `~/.config/zellij`
  only where the manifest shows tuidev installed it, drops `zellij` from the
  recorded `extra_packs`, and leaves the brew formula for you to remove.
- The repo's own tracked copies of the per-vendor instruction symlinks
  (`.cursorrules`, `.windsurfrules`, `.aider.md`, `.clinerules`, Roo, Copilot,
  and the Codex `instructions.md` that Codex never read).

### Changed

- **Ghostty on macOS 27:** shipped `macos-titlebar-style` is now `transparent`.
  The `tabs` style collapses the tab strip on macOS 27 with stable 1.3.1
  (ghostty-org/ghostty#13070; fix #13069 is on the tip channel until 1.4.0).
  Opting back into titlebar tabs via `auto-update-channel = tip` is documented
  in the config and `docs/FAQ.md`.
- **Claude Code settings refreshed against the Sept 2026 docs:** permission
  rules use the canonical `Bash(git *)` form, credential directories and
  `.env*` get `permissions.deny` rules (so `Read`/`Edit` honor the same boundary
  `sbx` enforces in the kernel), `teammateMode = "auto"` (tmux panes per
  teammate when already inside tmux), `attribution.commit = ""` (no
  `Co-Authored-By` trailer), `Notification` hook scoped to
  `permission_prompt|idle_prompt`. Dropped the undocumented `projects`,
  `MCP_CONNECTION_NONBLOCKING`, and the `if` filter on `Stop`.
- **Codex config:** `model` is no longer pinned (`gpt-5-codex` is retired
  upstream; the CLI's own default tracks the current lineup),
  `file_opener = "none"` (`nvim` was never a valid value),
  `disable_response_storage` removed (no such key), `web_search = "cached"`,
  and `[tui]` notifications for turn-complete / approval-requested.
- **OpenCode config:** model `anthropic/claude-sonnet-5`; the deprecated `theme` and
  `tui` keys moved out and the legacy `tools` boolean map folded into `permission` — TUI settings now ship in a sibling
  `configs/opencode/tui.json` the pack installs alongside `opencode.json`;
  `permission` gains `external_directory` / `doom_loop`; `share = "manual"`.
- `cc` steps aside for Claude Code's built-in sandbox: Seatbelt does not nest,
  so when `~/.claude/settings.json` has `sandbox.enabled = true` the wrapper
  calls `claude` directly instead of through `sbx`. `docs/sandboxing.md` gains
  a "pick one" comparison.
- `AGENTS.md` documents which CLI reads which instruction file (Claude Code →
  `CLAUDE.md`; Codex / OpenCode → `AGENTS.md`) and the current agent-teams UX
  (agent panel, `teammateMode`). `setup_agent_configs.sh` no longer creates a
  Codex `instructions.md` symlink — Codex reads `AGENTS.md` natively.
- `setup_agent_configs.sh` now creates only `CLAUDE.md` by default; the legacy
  per-vendor files (Cursor, Windsurf, Aider, Cline, Roo, Copilot) moved behind
  `--all`, and the repo's own copies of those symlinks were removed.

- **Container runtime order: Apple `container` → Podman → Docker.** New
  `scripts/lib/container.sh` picks the first runtime present (override with
  `TUIDEV_CONTAINER_RUNTIME`) and shims the CLI differences; `make
  container-build/test/clean` (the `docker-*` names remain as aliases),
  `make sandbox-up/down`, `make update-sandbox-image`, and the
  `sandbox-container` pack all go through it. The pack no longer installs
  Podman when a runtime already exists, and on macOS 26+ without one it points
  at Apple's signed pkg before falling back to Podman. Unit-tested by
  `scripts/lib/test_container.sh` (CI `lib-tests`).
- **Test image rebuilt for speed: Alpine, one package layer, no compiling.**
  The old `Dockerfile` (Ubuntu 22.04) ran `cargo install` for six Rust tools,
  which took tens of minutes on an arm64 builder. Every tool the core suite
  probes is an Alpine package (neovim, ripgrep, fd, bat, fzf, zoxide, delta,
  eza, starship, zellij, bottom, lazygit, yq-go, gh, shellcheck, httpie), so
  the toolchain is a single cached `apk add` layer; no rustup, no
  build-essential, no GitHub downloads, and lazygit is native for the running
  architecture (the old image always pulled the x86_64 tarball). The repo is
  copied last so edits only rebuild the final layer, the entrypoint is the real
  `scripts/test_suite.sh --tag core` instead of an inline ad-hoc script, and a
  `.dockerignore` keeps `.git` and screenshots out of the context. Apple's
  builder VM is sized to the host (`TUIDEV_BUILDER_CPUS` /
  `TUIDEV_BUILDER_MEMORY`, default half the cores / 4g) instead of its 2-CPU
  default. The Debian/Ubuntu apt installer path is validated on a real Debian
  box, not by this image.

### Fixed

- `--pack ai-clis` installed Claude Code settings to `~/.claude.json`, which is
  the CLI's *state* file (OAuth, onboarding, per-project state), so the shipped
  hooks and permissions were never read. It now targets
  `~/.claude/settings.json`; migration `202609151200_claude_settings_path`
  backs up the legacy keys to `~/.config/tuidev/backups/` on machines that got
  the old path (leaving `~/.claude.json` untouched) and lets the pack install
  the current file, and `uninstall.sh` no longer removes `~/.claude.json`.

- `scripts/lib/migrate.sh` no longer honors `XDG_CONFIG_HOME` for its state
  paths — every other tuidev state file lives literally under
  `~/.config/tuidev`, and the mismatch made an installed machine read as a
  fresh one (baselining away its pending migrations) wherever
  `XDG_CONFIG_HOME` points elsewhere.
- Docker test image builds Rust tools with `cargo install --locked`, so
  transitive crate drift (e.g. `palette`) can't break the build.
- Two `shellcheck disable=SC2119` annotations in `install.sh` for
  optional-arg lib calls (shellcheck 0.9.0 flags them; newer versions don't).

---

## [2.2.0] - 2026-09-01

Elite agent-orchestration layer. tmux stays the durability backbone; **Herdr**
is an opt-in fleet runtime. Personal LAN hosts stay in gitignored `*.local`
overlays.

### Added

- **`--pack herdr`** — [Herdr](https://herdr.dev/) agent-aware runtime (sidebar
  states, CLI + socket API). Homebrew-only install; without brew it prints the
  official installer command rather than piping a remote script to a shell. tmux
  wrappers (`work` / `dev` / `ai`) are unchanged. Prefix `ctrl+b` vs tmux
  `ctrl+a`.
- **[`docs/inspiration.md`](docs/inspiration.md)** — Omarchy/Omacosy practices
  we steal vs desktop systems we refuse; the `.local` split.
- Shipped SSH snippet `Include`s `~/.ssh/config.local*` (glob; missing file is
  ignored). Generic `Host always-on` / `workbox` examples only.
- First-fleet walkthrough and detach/verify practices in
  [`docs/agent-workflows.md`](docs/agent-workflows.md).
- CI `check-paths` also scans docs and fails on mDNS `user@` + hostname forms.
- **Worktree-per-agent layout** — `scripts/tmux/layout-worktrees.sh`, the
  `worktrees` shell wrapper, and `make quick-worktrees`. One git worktree per
  agent under `../<repo>-wt/<branch>` on `agent/N` branches, one tmux window
  each, with window `main` kept on the original repo for review and merging.
  Attach-or-create and idempotent; `--list` reports status; `--clean` removes
  only worktrees that are clean and fully merged (relative to the current or
  `--base` branch), printing what blocks the rest, and warns-and-continues when
  git refuses a branch delete instead of aborting the run. Bare `worktrees`
  defaults to a per-repo `<repo>-wt` session.
- **Palette-driven theming** — `scripts/theme.sh list|show|apply`, a 26-key
  palette contract under `configs/themes/`, and two shipped themes
  (`tokyo-night`, `catppuccin-mocha`). Applying writes `tuidev-theme` managed
  blocks into tmux/Ghostty/Starship configs; user edits outside the blocks
  survive. `apply` skips starship (with the fix to run) until `install.sh` has
  written its own block and a top-level `palette = "tuidev"` selector, rather
  than appending a table that would swallow the rest of the file, and it moves
  the theme block back to the end of any file it is no longer last in so the
  palette actually wins. `make theme NAME=…` / `make theme-list` wrap it.
  See [`docs/theming.md`](docs/theming.md).
- **Versioned one-shot migrations** — `scripts/migrations/` holds timestamped
  scripts run at most once per machine (applied ids in
  `~/.config/tuidev/migrations`); `update.sh --migrations` runs them, and they
  run first in `--configs` / `--all`. A failure stops the run and stays
  unrecorded so the next update retries it. Re-running `install.sh` on an
  existing machine applies pending migrations before the packs run; only a
  machine tuidev has never touched baselines history without running it.
  Inaugural migration prunes orphaned pre-2.0 files
  (`~/.local/bin/ai-workflow.sh`, `~/.config/mcp-env.template`) with backups.
  See [`docs/updating.md`](docs/updating.md).
- **Install manifest** — installs record packs, formulae, casks, managed
  blocks, and files to `~/.config/tuidev/manifest` (opt-in, append-only,
  recorded via the shared libs). `uninstall.sh` consults it when present and
  purges only what *we* installed — a pre-existing `ripgrep` now survives;
  pre-manifest installs fall back to the old behavior with a warning.
- **[`docs/roadmap.md`](docs/roadmap.md)** — 2027/28 readiness groundwork:
  multiplexer landscape (tmux/Herdr/Superlogical posture), Seatbelt →
  Apple-containerization succession, fleet-scale agent horizons, and explicit
  adopt/hold criteria for the watch-list.
- **Linux/apt support** — `minimal` and `remote` install on Debian/Ubuntu
  without Homebrew, including arm64 boards like a Raspberry Pi. See
  [`docs/profiles.md`](docs/profiles.md).
- New Makefile targets: `update-migrations`, `theme`, `theme-list`,
  `quick-worktrees`.
- CI `lib-tests` also runs `test_profile.sh`, `test_contract.sh`,
  `test_theme.sh`, and `test_migrations.sh`.

### Fixed

- Linux install: the core pack no longer hard-requires Homebrew. On apt-only
  systems (Debian/Raspberry Pi — Homebrew has no aarch64 Linux build) it probes
  `apt-cache policy` per tool, installs what the release actually packages,
  shims Debian's renamed binaries (`fdfind`→`fd`, `batcat`→`bat`) into
  `~/.local/bin`, declines Debian's incompatible `yq` v3, and prints official
  install commands for the rest instead of piping remote installers. Extras
  warn-and-skip on brewless Linux instead of aborting. The apt path records the
  `fd`/`bat` compat shims it drops in `~/.local/bin` as manifest `file` records
  (so `uninstall.sh` removes them) and the apt packages it installs under a new
  `apt` manifest kind (recorded but not yet purged — inert until a future
  uninstall step consumes it).
- Login shell: `chsh` needs a TTY for its PAM password prompt, so a piped or
  CI install silently left the shell as bash. The installer now detects the
  cases it cannot win (no TTY, no `chsh`, `zsh` absent from `/etc/shells`) and
  prints the exact command to run by hand instead of failing quietly.
- SSH managed block: prefix the `Include ~/.ssh/config.local*` with
  `Match all` — appended after a user config ending in a `Host` stanza, a bare
  `Include` was scoped to that host and `config.local` was never read.
- Sandbox: `strict.sb` / `standard.sb` now allow outbound AF_UNIX connects
  under `~/.config/herdr` only, so sandboxed agents can use the Herdr socket
  API the docs point them at. Credential paths stay denied.
- Health check: the `ai-clis` probe was a literal `true`; it now checks that at
  least one of claude/codex/opencode is on `PATH`.
- CI `check-paths`: capture matches once instead of piping into `grep -q .`
  (SIGPIPE under `pipefail` silently passed above ~5k matching lines); also
  scan `bin/`, `uninstall.sh`, and `Makefile`.
- `install.sh` now auto-applies the `tokyo-night` theme on a fresh, non-dry-run
  install with no existing `~/.config/tuidev/theme`. Previously the shipped
  `starship.toml` selected `palette = "tuidev"` with no `[palettes.tuidev]`
  table until you ran `make theme` by hand, so every prompt warned `Could not
  find color palette: tuidev`. An already-themed machine is left alone.
- `install.sh`'s profile record is now additive: a pack-only run (e.g.
  `./install.sh --pack herdr`) merges with any existing
  `~/.config/tuidev/profile` instead of rewriting it from scratch — group
  booleans (core/remote/sandbox/ui/extras) only ever flip true, `extra_packs`
  is a set union, and a previously recorded profile name (minimal/desktop/
  remote) survives unless `--profile` is explicitly passed this run.
- `scripts/health_check.sh`: `profile=custom` (recorded by pack-only installs)
  no longer exits 2 with "Invalid profile" — it now checks the minimal
  baseline and prints an info line explaining why.

### Changed

- [`docs/agent-workflows.md`](docs/agent-workflows.md) is a control-plane guide
  (attention queue, machine roles, decision table, verification-as-done).
- Agent primer: Herdr nesting, don't script the Herdr TUI, done means verified.
- [`docs/inspiration.md`](docs/inspiration.md) now distinguishes adopted vs
  watched practices (manifest-driven uninstall, in-progress theming pipeline),
  adds an omarchy executable-theme supply-chain caution, and OpenClaw 2.0
  lessons.
- `uninstall.sh` also strips `tuidev-theme` managed blocks from tmux, Ghostty
  and Starship configs, and removes the theme state file.

---

## [2.1.0] - 2026-06-01

Modernization for the 2026 agentic stack. **The core install is now a pure,
continuously-updatable terminal-tools bundle**; AI CLIs, faster Node, and
parallel-agent tooling are opt-in packs. tmux stays the durable backbone.

> **Heads-up (behavior change):** AI CLI wrappers (`cc`/`cx`/`oc`) moved out of
> the default install into `--pack ai-clis`. If you relied on them, add the pack
> — see [Migration](#migration-2-0--2-1).

### Added

- **`--pack ai-clis`** — opt-in AI coding-CLI integration: the `cc`/`cx`/`oc`
  wrappers (sbx auto-routing) + adopt-existing claude/codex/opencode configs.
  Keeps the repo CLI-agnostic as CLIs churn. Pairs with `--pack sandbox`.
- **`--pack fnm`** — fnm (Fast Node Manager, Rust): ~1ms shell init, auto-switch
  Node per project from `.nvmrc`/`.node-version`, Node 24 (LTS) default. The
  shipped `~/.zshrc` prefers fnm when present and falls back to nvm.
- **`--pack cmux`** — native macOS GUI terminal for agents side-by-side
  (notification rings, built-in browser, Claude Teams). A desk-side tmux complement.
- **`--pack bosun`** — tmux-native Rust orchestrator for agent sessions on a
  dedicated `tmux -L bosun` socket; never touches your main tmux state.
- **`shell.d/` loader** — the managed `~/.zshrc` sources opt-in pack fragments
  from `~/.config/tuidev/shell.d/`, so packs can add shell hooks cleanly.
- **New docs:** `agent-workflows.md` (remote control, cmux, bosun),
  `agent-primer.md` (copy-paste brief for any agentic CLI),
  `engineering.md` (shared libs, pack contract, package-array convention).
- TPM (tmux plugin manager) is **bootstrapped on install**.

### Changed

- **Core = terminal tools only.** AI-CLI wrappers/configs no longer install on
  every profile; the cross-cutting installer is "shell + editor", nothing else.
- **Node works from the first prompt in every shell** — the default version's bin
  is on `PATH` immediately, so `node`/`npx` and global Node CLIs resolve on the
  very first command; the heavy manager stays lazy.
- `update.sh --packages` rewritten around one shared discovery path — every
  pack's formulae **and** casks are tracked.
- DRY pass: plural `brew_install_formulae`/`brew_install_casks` helpers; deduped
  install loops across 11 pack scripts.
- `agents` layout is now **claude | codex** (two panes).
- Remote/mobile docs reframed tmux-first; **Moshi** added to the iOS client list.
- opencode model bumped to `anthropic/claude-sonnet-4-6`; CI `seatbelt-profiles`
  pinned to `macos-15`.

### Deprecated

- **Gemini CLI** is no longer shipped (deprecated upstream; succeeded by
  Antigravity, `agy`). The repo stays CLI-agnostic — add your own wrapper in
  `~/.config/tuidev/shell.d/` if you use it.

### Fixed

- `update.sh --packages` silently skipped `fnm`/`cmux` (extra-pack loop ignored
  casks and most array-name conventions).
- `--pack bosun` now actually usable: correct `cargo install --git` + `~/.cargo/bin`
  on `PATH`. Removed dead `collect_active_*` helpers.

### Removed

- `docs/REMOTE_SESSIONS.md` — deprecated stub, superseded by `remote.md` +
  `agent-workflows.md`.

### Migration (2.0 → 2.1)

- Want the `cc`/`cx`/`oc` wrappers back? `./install.sh --pack ai-clis`
  (add `--pack sandbox` for Seatbelt routing).
- Want fnm? `./install.sh --pack fnm` — your existing nvm setup keeps working
  either way.

---

## [2.0.0] - 2026-04-14

Major rewrite. tmux becomes the primary multiplexer; Zellij demoted to an
opt-in pack. Installer is now layered and non-destructive. AI agents run
sandboxed by default on macOS. See [VISION.md](VISION.md) for the full
product rationale, especially the "2026 Amendments" section.

### Added

- **Layered installer** with profiles (`minimal`, `desktop`, `remote`) and
  composable packs (`--core`, `--remote`, `--sandbox`, `--ui`, `--extras`,
  `--pack NAME`). Pack scripts live under `scripts/install/`.
- **macOS Seatbelt sandbox** (Tier 1): `configs/sandbox/profiles/{strict,standard,off}.sb`
  plus `bin/sbx` wrapper. `cc`/`cx`/`gem`/`oc` auto-route through `sbx` when
  both are on `PATH`. Credentials (`~/.ssh`, `~/.aws`, `~/.gnupg`, keychains,
  `~/.config/gh`, `~/.docker`, `~/.kube`, `~/.netrc`) are denied.
- **Podman sandbox-container pack** (Tier 2) for VM-backed isolation
  (`--pack sandbox-container`). Docker Desktop / OrbStack explicitly excluded
  (not FOSS).
- `scripts/lib/ui.sh` — shared shell library (colors, printers, `run_cmd`).
- `scripts/lib/config_write.sh` — non-destructive managed-block writer with
  9-case unit test suite (`scripts/lib/test_config_write.sh`).
- `scripts/tmux/layout-*.sh` — nine reusable tmux layout helpers
  (work / dev / ai / ai-single / ai-triple / fullstack / multi / remote / agents).
- `configs/codex/config.toml` — opinionated Codex defaults
  (`sandbox_mode = "workspace-write"`, `approval_policy = "on-request"`).
- Managed-block config writes: `~/.zshrc`, `~/.config/starship.toml`,
  `~/.config/tmux/tmux.conf` now write under `# >>> tuidev managed (...) >>>`
  markers that preserve user edits outside the block.
- `~/.config/tuidev/profile` manifest + `~/.config/tuidev/env` sourceable
  env file written at install time.
- tmux plugins: `tmux-resurrect` + `tmux-continuum` declared in `tmux.conf`
  for durable session state across reboots.
- New docs: `docs/profiles.md`, `docs/sandboxing.md`, `docs/remote.md`,
  `docs/migration.md`.
- Claude Code hooks refreshed for 2.1.x: `PermissionDenied` event,
  conditional `if` filter on `Stop` hook, `MCP_CONNECTION_NONBLOCKING=true`,
  baseline `permissions.allow` seeded for common tools.
- New Makefile targets: `install-{minimal,desktop,remote}`,
  `check-{minimal,desktop,remote}`, `test-{core,ui,all}`, `sbx-test`,
  `sandbox-up`/`sandbox-down`, `adopt`, `migrate`,
  `update-sandbox-image`, `update-security`.
- Health check and test suite now use profile-aware tag system
  (`core`/`remote`/`sandbox`/`ui`/`extras`/`packs`); missing GUI apps no
  longer fail the suite.
- CI: macOS-runner job validates every Seatbelt profile with
  `sandbox-exec -n`; Linux Docker job narrowed to `--tag core`.

### Changed

- **Default multiplexer: tmux.** The ergonomic commands `work`, `dev`,
  `ai`, `ai-single`, `ai-triple`, `fullstack`, `multi`, `remote`,
  `agents` now launch tmux via the layout helpers. Zellij versions are
  namespaced `zdev`, `zwork`, `zai`, ... and only activate when
  `command -v zellij` succeeds (i.e., after `./install.sh --pack zellij`).
- Installer no longer overwrites `~/.zshrc`, `~/.config/starship.toml`,
  or `~/.config/tmux/tmux.conf` — managed-block writes preserve user edits.
- `~/.config/nvim` is **backed up** (timestamped, under
  `~/.config/tuidev/backups/`) before a new config lands — no more
  `rm -rf` of user state.
- AI CLI configs (`~/.claude.json`, `~/.config/opencode/opencode.json`,
  `~/.codex/config.toml`) use `--adopt-existing` by default: if present,
  tuidev leaves them alone.
- README trimmed from 403 → 154 lines; leads with tmux/sandbox/layered narrative.
- Default package set shrunk: `nnn`, `lazydocker`, `k9s`, `atuin`, `broot`,
  `bandwhich`, `dust`, `duf`, `hyperfine`, `tokei` moved to `--extras`.
- Rectangle/Stats/Maccy/Hidden Bar/Hammerspoon now require
  `--profile desktop` or `--pack ui`.
- `update.sh` is profile-aware: updates only packs the user installed,
  diffs managed blocks instead of blindly copying.

### Fixed

- `update.sh` now detects the **pre-managed-block duplication** foot-gun
  (an older installer wrote the raw source into the file; a newer run
  wrapped the same content in markers, producing TOML duplicate-key
  errors in starship, `parse error near '()'` in zsh when a legacy
  `alias cc=...` collided with the managed-block `cc()` function, and
  redundant `set -g` directives in tmux.conf). `detect_outside_duplication`
  categorizes matches as `exact-*` (safe to auto-clean with backup) or
  `partial-*` (signature match, warn only). Surfaced in both
  `make update-check` and interactive `make update-configs`.
- `configs/zsh/.zshrc`: `unalias cc cx gem oc` is now issued before the
  function definitions, making the managed block robust against stale
  aliases from pre-2.0 installs.
- `scripts/lib/config_write.sh`: `write_managed_block` passes content via
  a sidecar file instead of `awk -v`; BSD awk on macOS rejects literal
  newlines in `-v` values and was silently emptying the destination on
  in-place replacement.

### Deprecated

- `ta`, `tdev`, `tai`, `tai-triple` shell functions — still work, but emit
  a one-time deprecation notice (stamped in `~/.config/tuidev/deprecations`).
  Use `work`, `dev`, `ai`, `ai-triple` instead.

### Removed

- `install.sh.legacy` backup copy (superseded; git history preserves the
  old installer).
- `scripts/ai-workflow.sh` — zellij-only launcher, superseded by
  `scripts/tmux/layout-*.sh`.
- Old README's multi-pane "hero box" framing and Zellij-first command tables.

### Migration

Existing users: on next update, `make update` will show drift on your
shell dotfiles. Run `make adopt` to convert them to managed-block form.
See [docs/migration.md](docs/migration.md) for the full cutover guide.

---

## [1.3.0] - 2026-03-26

### Added

#### Multi-Agent CLI Support
- Shell aliases for all AI CLIs: `cc` (Claude), `cx` (Codex), `gem` (Gemini), `oc` (OpenCode)
- **`agents` function** — launches Claude, Codex, and Gemini in 3 tmux panes with one command
- Health checks for Codex CLI and Gemini CLI presence
- No custom configs shipped — all CLIs are self-updating and manage their own configuration

#### Ghostty Modernization
- Enabled font ligatures (`+calt`) for operator readability (`=>`, `!=`, `>=`)
- Added `scrollback-limit = 100000` for AI agent output
- Added `link-url = true` for clickable URLs
- Added `auto-update = check`
- Added quick terminal keybinding (`Ctrl+\``) for system-wide dropdown terminal

### Changed
- AI CLI tool ordering: Claude Code primary, Codex secondary, Gemini optional, OpenCode community
- Updated README, CLAUDE.md, AGENTS.md with 4-CLI architecture and `agents` function
- Updated ASCII diagrams to show 3 agent panes (Claude/Codex/Gemini)
- Documentation across all guides updated for multi-agent workflow

### Fixed
- Cleaned stale permission entries in `.claude/settings.local.json` (removed refs to deleted mcp.json, gemini, ralph)

---

## [1.2.0] - 2026-02-25

### Added

#### Tmux Support (First-Class)
- **`configs/tmux/tmux.conf`** - Full Tokyo Night themed tmux configuration
  - `Ctrl+a` prefix (ergonomic), true color, mouse, base index 1, vi copy mode
  - Pane splits: `|` / `-`, navigation: `h/j/k/l`, resize: `H/J/K/L`
  - Status bar matching Tokyo Night palette (`#1a1b26` bg, `#7aa2f7` accent)
- **Tmux shell functions** in `.zshrc` — mirror Zellij session pattern with `t` prefix:
  - `ta [name]` — attach or create bare session
  - `tdev [name]` — 3-column: nvim (55%) | agent (25%) | runner (20%)
  - `tai [name]` — nvim (60%) + 2 stacked agent panes (40%)
  - `tai-triple [name]` — nvim (55%) + 3 stacked agent panes (45%)
  - `tls`, `tk [name]`, `tka` — session management
- **Health check** (`scripts/health_check.sh`): Tmux Check section (version, config, true color hint)
- **Config validation** (`scripts/validate_configs.sh`): tmux.conf validation + required files
- **Update sync** (`scripts/update.sh`): tmux.conf included in config change detection and apply
- **Install/uninstall**: backup, mkdir, copy, and remove `~/.config/tmux/`

#### Documentation
- `docs/CHEATSHEET.md` — full tmux section (key bindings, session functions, agent teams), tmux in Quick Reference Card, tmux in Config Locations; removed duplicate blocks
- `README.md` — dual session tables, tmux in Core Tools and Theme, `configs/tmux/` in project structure
- `docs/ARCHITECTURE.md` — side-by-side Zellij + tmux in Layer 2, dual orchestrator in Design Philosophy, tmux in Config Flow and File Locations
- `docs/QUICK_START_GUIDE.md` — step 9 "Tmux for Claude Agent Teams" with key bindings and agent teams workflow
- `AGENTS.md` — "Working with Tmux Sessions" section with why tmux, key bindings, session commands, agent teams integration
- `CLAUDE.md` — architecture table, shell functions split into Zellij/tmux subsections, Key Design Decision #6

### Changed
- `CLAUDE.md` and `AGENTS.md` updated to reflect dual-multiplexer architecture
- Zellij positioned as primary for manual workspace layouts; tmux as companion for Claude agent teams

### Context
Claude Code's experimental agent teams feature (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`) requires tmux or iTerm2 for split-pane mode. Zellij is explicitly unsupported. tmux was already installed by `install.sh` but had no config, shell functions, or documentation.

---

## [1.1.0] - 2026-01-29

### Added

#### New CLI Tools
- **sd** - Intuitive find & replace (sed alternative)
- **yazi** - Modern async terminal file manager
- **broot** - Directory navigator for large codebases
- **tealdeer** - Fast tldr pages in Rust

### Changed
- Updated README with new tools
- Enhanced .zshrc with aliases for new tools (y, br, tldr, sd)

---

## [1.0.0] - 2026-01-29

### Added

#### Core Tools
- **Neovim** with LazyVim - Full IDE experience with LSP
- **Zellij** - Terminal multiplexer with 7 pre-built layouts
- **Ghostty** - Fast terminal emulator configuration
- **Starship** - Modern shell prompt with Tokyo Night theme

#### Modern CLI Replacements
- **ripgrep** - Fast grep replacement (10x faster)
- **fd** - Simple find replacement
- **eza** - Modern ls with icons and git status
- **bat** - cat with syntax highlighting
- **zoxide** - Smart cd that learns from usage
- **delta** - Beautiful git diffs

#### TUI Applications
- **lazygit** - Git TUI interface
- **lazydocker** - Docker management TUI
- **nnn** - Fastest TUI file manager
- **k9s** - Kubernetes cluster management
- **ncdu** - Interactive disk usage analyzer
- **bottom** - System monitor

#### System Tools
- **fastfetch** - Fast system info display
- **bandwhich** - Network bandwidth monitor by process
- **fzf** - Fuzzy finder for files and history
- **atuin** - Enhanced shell history

#### macOS Applications
- **Rectangle** - Window snapping and management
- **Hammerspoon** - macOS automation with Lua
- **Stats** - Menu bar system monitor
- **Maccy** - Clipboard history manager
- **Hidden Bar** - Hide menu bar icons

#### AI CLI Tools
- **OpenCode** configuration with MCP servers
- **Claude Code** configuration with MCP servers
- **Gemini CLI** configuration with MCP servers

> Note: Gemini CLI and MCP server configs were removed in the v1.2.0 cleanup. Gemini CLI re-added minimally in v1.3.0. MCP configs are managed separately per-project.

#### MCP Servers (Pre-configured, removed in v1.2.0)
- `filesystem` - File system access
- `git` - Git operations
- `fetch` - HTTP requests
- `memory` - Persistent memory across sessions
- `github` - GitHub API (requires API key)
- `brave-search` - Web search (requires API key)
- `figma` - Design-to-code workflows (requires API key)
- `playwright` - Browser automation
- `postgres` - PostgreSQL access
- `sqlite` - SQLite database access

#### Zellij Layouts
- `dual.kdl` - Editor + 2 AI agents (default)
- `single.kdl` - Editor + 1 AI agent
- `triple.kdl` - Editor + 3 AI agents
- `multi-agent.kdl` - Full workflow with monitoring
- `fullstack.kdl` - 5-tab full-stack development
- `remote.kdl` - Remote access with tunnel
- `dev.kdl` - Classic development layout

#### Documentation
- Quick Start Guide
- Architecture overview
- MCP Servers guide
- Neovim quickstart
- Complete cheatsheet
- Terminal navigation fixes
- Remote sessions guide
- FAQ

#### Infrastructure
- GitHub Actions CI/CD pipeline
- Docker test environment
- Makefile with common commands
- Health check script
- Comprehensive test suite
- Configuration validation
- Dry-run mode for installer

### Changed
- All configurations use `$HOME` variables (no hardcoded paths)
- Consistent Tokyo Night theme across all tools

### Security
- No sensitive data in repository
- API keys stored in environment variables
- MCP servers requiring authentication disabled by default

---

## Pre-release Development

Iterative build-up to 1.0.0 (all folded into the 1.0.0 entry above): the
modern-CLI tool set, macOS automation, the test/CI/Docker harness, the docs set,
and the first AI-CLI + MCP integration.
- Created AGENTS.md for AI assistants
