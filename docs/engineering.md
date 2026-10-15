# Engineering

How tuidev is put together, and the conventions for changing `install.sh`, `uninstall.sh`, `scripts/`, `bin/` and `configs/`. The bar is **small, composable and non-destructive**, whether a human or an agent is editing. The PR process is in [CONTRIBUTING.md](../CONTRIBUTING.md), and the reasons behind the design are in [VISION.md](../VISION.md).

## Architecture

```
install.sh ─┬─ validate flags and --pack names, resolve the profile
            ├─ migrations: baseline on a fresh machine, run pending ones on an upgrade
            ├─ packs: core → remote → sandbox → ui → extras → each --pack   (scripts/lib/packs.sh)
            ├─ cross-cutting configs: ~/.zshrc, starship.toml (managed blocks)
            ├─ git defaults, notify.sh
            └─ default theme (fresh install), then the profile and env state files

every mutation → ~/.config/tuidev/manifest   (read by uninstall.sh)
```

| Repo source | Installed to | How |
|-------------|--------------|-----|
| `configs/zsh/.zshrc` | `~/.zshrc` | managed block `tuidev-zshrc` |
| `configs/starship/starship.toml` | `~/.config/starship.toml` | managed block `tuidev-starship` |
| `configs/ghostty/config` | `~/.config/ghostty/config` | managed block (ui pack) |
| `configs/ssh/config`, `configs/ssh/sshd_config.d/` | `~/.ssh/config`, `/etc/ssh/sshd_config.d/` | managed block / copied when writable (remote pack) |
| `bin/sbx`, `configs/sandbox/profiles/*.sb` | `~/.local/bin/sbx`, `~/.config/tuidev/sandbox/` | overwrite / upgrade-shipped (sandbox pack) |
| `configs/{claude,codex}/` | `~/.claude/settings.json` (`settings.linux.json` on Linux), `~/.codex/config.toml` | upgrade-shipped (ai-clis pack) |
| `configs/codex/rules/tuidev.rules` | `~/.codex/rules/tuidev.rules` | overwrite (ai-clis pack) |
| `configs/orchestration/` | `~/.claude/{rules,agents,skills}`, `~/.codex/{AGENTS.md,agents}`, `~/.agents/skills` | overwrite + managed block `tuidev-orchestration` in `~/.codex/AGENTS.md` (orchestration pack) |
| `configs/herdr/` | `~/.config/herdr/` | adopt-existing |
| `configs/themes/<name>/palette.toml` | `~/.config/tmux/theme.conf` + blocks in the Ghostty and Starship configs | `scripts/theme.sh` |
| `configs/nvim/` | `~/.config/nvim/` | upgrade-shipped per file, only while tuidev owns the tree (`nvim` pack) |
| `configs/tmux/tmux.conf` | `~/.config/tmux/tmux.conf` | managed block `tuidev-tmux` + TPM bootstrap (`tmux` pack) |
| `bin/agents`, `lib/agents/`, `configs/swiftbar/agents.10s.sh` | `~/.local/bin/agents`, `~/.local/lib/tuidev/agents/` (`TUIDEV_LIB_DIR`), SwiftBar's plugin folder (default `~/.config/swiftbar/plugins/`, named after `AGENTS_BAR_REFRESH`) | overwrite, file by file (`monitoring` pack; the plugin on macOS only) |
| `configs/agents/agents.conf` | `~/.config/agents.conf` | adopt-existing (`monitoring` pack) |

tuidev keeps its own state in `TUIDEV_STATE_DIR`, which defaults to `${XDG_CONFIG_HOME:-$HOME/.config}/tuidev`. It is defined once, in `scripts/lib/ui.sh`, and holds `profile`, `manifest`, `env`, `migrations`, `theme`, `backups/`, `sandbox/` and `shell.d/`. Derive every state path from it.

```
bin/sbx                 Seatbelt wrapper
bin/agents              agent process monitor (monitoring pack): the entrypoint, sourceable for tests
lib/agents/             its modules and awk programs (map below); installed beside it, so it runs without the repo
configs/                everything installed into $HOME (table above)
scripts/lib/            shared libraries + test_*.sh unit harnesses
scripts/install/        built-in packs (core remote sandbox ui extras); packs/ = optional packs (includes nvim.sh, tmux.sh)
scripts/migrations/     timestamped one-shot fixups
scripts/*.sh            update, health_check, test_suite, theme, validate_configs,
                        check_links, check_paths, container, notify, fix_completions, screenshots
templates/              AGENTS_TEMPLATE.md for downstream projects
docs/assets/            README images; tapes/ holds their VHS sources and demo fixtures
```

### The agents modules

`bin/agents` only finds its modules and sources them: `lib/agents/` next to `bin/` in a checkout, `lib/tuidev/agents/` next to an installed `~/.local/bin/agents`. It looks first beside the file it resolves to (through every symlink, and symlinked directories on the way), so a link to a checkout runs the checkout's modules even next to an older install, and only then beside the path it was run as. It checks that every module and every `awk/` program (`_AGENTS_AWK_FILES`, kept in step with the directory by `test_agents_install.sh`) is there before it sources any, and names what is missing. `config.sh` comes first, because it reads `agents.conf`; every other module only defines functions, so the test harnesses can source `bin/agents` and replace any function. Each module starts with what it owns, what it uses and its public functions.

| Module | Owns |
|--------|------|
| `config.sh` | every `AGENTS_*` setting (`agents.conf`, the environment, defaults), the process patterns, the run and data dirs, this process's pid and uid; `agents config` |
| `util.sh` | `_agents_awk` (runs the `awk/` programs), durations, `--since` windows, clock times, timeouts, probes started in the background and read later (`_agents_bg`, `_agents_bg_wait`: a process substitution per probe, so a refresh's `lsof`, `launchctl` and `pmset` run while `ps` does), detached jobs, lock directories (each records its holder, `PID START`, and is taken over only once that holder is gone), a state file's holder check, epoch stamps, atomic replace |
| `snapshot.sh` | the `ps` snapshot, start times, listeners, cwds (`/proc` or `lsof`, looked up early for the pids the last run asked about), pids never stale, Herdr's cached view, `agents_collect` |
| `mcp.sh` | the MCP servers Claude Code and Codex are configured with (names, scopes, sources, the word that starts each; never args, env, headers or URLs), cached in `mcp.tsv`; `agents mcp` |
| `where.sh` | where a process lives (tmux pane, Herdr pane, ssh, terminal app) and the one `tmux list-panes`; `agents jump`, `agents peek` |
| `classify.sh` | `agents_classify` and `agents_enrich`: agents, stale, hogs, what each session runs, jobs, flags, project names |
| `watched.sh` | the files polling loops watch: quiet or fresh, mtime, last line, and the credential files never read |
| `system.sh` | thermal pressure, energy mode, sleep disabled, load, memory, battery, machine CPU% |
| `awake.sh` | the keep-awake holder and `agents awake` |
| `lid.sh` | `awake lid`: the root guard, the admin dialog, the lid state |
| `kill.sh` | refusals, PID@START plans, SIGTERM then SIGKILL (`kill`, `term`, and every other stop) |
| `reap.sh` | what `agents reap` stops, by hand or with `--auto` |
| `events.sh` | the private data dir and `events.tsv` |
| `assess.sh` | Needs you: evidence and a verdict per item, `agents why` |
| `history.sh` | `agents sample`: `history.tsv`, `today.tsv`, `sample.state`, pruning |
| `runs.sh` | the run ledger (`runs.state`, `runs.tsv`), the menu's run feed, `agents runs` |
| `tokens.sh` | the token scanner `agents sample` runs: what Claude Code and Codex transcripts say about tokens, read incrementally and within a byte budget (`tokens.state`), into `tokens.tsv`, `compacts.tsv`, `denials.tsv`, `limits.tsv` and the menu's `tokens.today` |
| `transcript.sh` | reading Claude Code transcripts: task-id lines, subagent meta and type, which agent started a task, which transcripts changed lately and whose session each is (shared by `hooks.sh`, `runs.sh` and `tokens.sh`) |
| `report.sh` | `agents report` and its views, `insight.txt` (`agents_insight_write`, the menu's top insight), the menu's tokens row (from `tokens.today`) |
| `render.sh` | the human views: the table, its status lines, `agents watch` |
| `json.sh` | `agents json`, a versioned contract |
| `tsv.sh` | `agents tsv`, what the SwiftBar plugin reads |
| `terminal.sh` | `agents open-term`: a window of your terminal |
| `activity.sh` | which session a process is (Claude Code's `sessions/PID.json`, Codex's open rollout file) and what it is doing, from the last 256 KiB of its transcript |
| `show.sh` | `agents show`: one process in detail, and its JSON |
| `pick.sh` | `agents pick`: the fzf browser, its list and its command line |
| `hooks.sh` | `agents hook`: what a finished subagent or a cleared session left running |
| `notify.sh` | the y/N prompt, the macOS dialog, notifications |
| `usage.sh` | `agents --help` |
| `cli.sh` | `agents_main`: options and the subcommand table; `agents cwd` |
| `awk/lib_*.awk` | awk functions shared by several programs: process-table primitives (`lib_proc`), what a tool shell runs and the name it and an MCP server go by (`lib_activity`), jobs (`lib_jobs`), where a process lives (`lib_where`), JSON strings (`lib_json`), ordering, heapsorts (`lib_sort`), durations and sizes for people (`lib_fmt`) |
| `awk/*.awk` | one program each (`classify`, `enrich`, `assess`, `render`, `json`, `report`, `sample`, `runs_obs`, `runs`, `runs_view`, `tokens_plan`, `tokens`, `refusal`, `tree`, `new_members`, `hook_*`, `mcp` and `mcp_toml` (the inventory), `where`, `show_tree` and `show`, `pick`), run by `_agents_awk` after the libraries it names; `report` comes in parts: `report_fmt` (numbers and cells), `report_runs` (reads `runs.tsv` once for every view), `report_tokens` (`tokens.tsv`, `compacts.tsv`, `limits.tsv`, the price file, and the tokens view), `report_denials` (`denials.tsv` and the denials view), `report_insights`, `report_views` |

The monitoring pack installs each file with `install_config --overwrite`, so the manifest records it and `uninstall.sh` removes it. Adding a module needs no migration; renaming or removing one does, like any installed file. `scripts/lib/test_agents_golden.sh` compares every view and dry run with recorded output byte for byte, and `test_agents_install.sh` runs the installed command outside the repo.

## Principles

- **DRY:** one behavior lives in one place. Logic two scripts need belongs in `scripts/lib/`.
- **KISS:** don't add an abstraction until it has a second caller.
- **Small functions:** a function does one nameable thing. When it outgrows a screen, extract the steps (see `_fnm_ensure_node` and `_report_brew_group`).
- **Separation of concerns:** packs install tools, and the cross-cutting section of `install.sh` writes shared settings. Discovery, reporting and mutation are separate functions.
- **Non-destructive:** never `cp` over a user's file, and never `rm -rf` a user config. Write through managed blocks or adopt-existing, and back up first.
- **Idempotent:** every step is safe to run twice. Check before you mutate.
- **Fail soft:** a pack that can't install an optional tool warns and continues. Only genuine preconditions `die`, and those are checked up front (as `install.sh` does for unknown `--pack` names).

## Shared libraries

Source these instead of reimplementing them. Each lib is idempotent to source, sources its own dependencies, and is bash 3.2-clean.

| Lib | Provides |
|-----|----------|
| `ui.sh` | `print_header/step/success/warning/error/info`, `run_cmd` (dry-run aware), `command_exists`, `is_macos`/`is_linux`, `file_mode`/`file_owner`, `die`, `TUIDEV_STATE_DIR`, `TUIDEV_LIB_DIR` |
| `pkg.sh` | `pkg_install NAME...`: Homebrew, then `apt-get`, `dnf`, `pacman`, using Homebrew names mapped per distro. Also `pkg_manager`, `pkg_manual_hint` and `PKG_UNAVAILABLE`, plus the `pkg_native_*` helpers `update.sh --packages` uses to find and upgrade outdated apt/dnf/pacman packages. It fails soft, never prompts for a sudo password, and records what it installs |
| `gitconfig.sh` | `tuidev_git_defaults`: opinionated global git defaults (histogram, zdiff3, rerere, autoSquash/updateRefs, autoSetupRemote, delta). Sets a key only while it is unset, `[include]`s counted, records each in the manifest; run by install.sh and `update.sh --configs` |
| `brew.sh` | `brew_install_formulae` / `brew_install_casks` (and the singular forms), `brew_has_formula` / `brew_has_cask`, `brew_update_once`. Use it for casks and tap formulae. Everything else goes through `pkg_install` |
| `packs.sh` | `pack_script`, `pack_entrypoint`, `pack_run`, `pack_array NAME formulae\|casks`, `pack_binaries`, `TUIDEV_BUILTIN_PACKS` |
| `profile.sh` | `load_tuidev_profile`, `tuidev_profile_write`, `tuidev_profile_add_pack` / `tuidev_profile_remove_pack`, `tuidev_active_packs`, `tuidev_is_valid_pack`, `TUIDEV_VALID_PACKS` |
| `config_write.sh` | `install_config DEST SRC --managed-block ID \| --adopt-existing \| --upgrade-shipped HASHFILE \| --overwrite`, `tuidev_is_shipped`, `write_managed_block`, `read_managed_block`, `remove_managed_block`, `tuidev_backup` |
| `manifest.sh` | `tuidev_manifest_record KIND VALUE`, `tuidev_manifest_has`, `tuidev_manifest_values` |
| `migrate.sh` | The migration runner, including the baseline and pending lists |
| `container.sh` | `tuidev_container_runtime` (Apple `container` → podman → docker) and up/down/build/run shims |

Rules of thumb: never call `brew install` or `apt-get` directly in a pack; never `echo` raw status (use `print_*` so `NO_COLOR` and `TUIDEV_NO_COLOR` work); wrap every mutation in `run_cmd` so `--dry-run` previews it.

## The pack contract

A pack is one file. The five built-in packs are `scripts/install/<name>.sh`, and optional packs are `scripts/install/packs/<name>.sh`. A pack must:

1. Start with `#!/bin/bash` and `set -eo pipefail`, resolve `SCRIPT_DIR`, and source the libs it uses.
2. Declare its packages as `<PACK>_FORMULAE=(...)` and `<PACK>_CASKS=(...)`, where the prefix is the pack name in upper snake case (`sandbox-container` → `SANDBOX_CONTAINER_FORMULAE`). These are the only names `pack_array` reads, which is how `update.sh --packages`, `health_check.sh` and `uninstall.sh` discover a pack's packages without running it. A pack that installs with Homebrew but declares no array silently drops out of updates. Tools installed another way (cargo, an official installer the user runs) have no array.
3. Define exactly one entrypoint, `<pack>_install`, with hyphens turned into underscores. `pack_run` sources the file into the installer's shell and calls it, so the file itself may only define functions and arrays.
4. Warn and continue on failure (`pkg_install ... || print_warning "... (continuing)"`) rather than exit.
5. End with `if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then <pack>_install "$@"; fi`, so the file also runs on its own.

To add an optional pack, create the file, add its name to `TUIDEV_VALID_PACKS` in `scripts/lib/profile.sh`, and document it in [profiles.md](profiles.md). Install, update, health check, uninstall and `test_contract.sh` all find it from there, and `install.sh` needs no edit.

```bash
#!/bin/bash
# Optional pack: foo — installs the foo TUI.
set -eo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/../../lib/ui.sh"
. "$SCRIPT_DIR/../../lib/pkg.sh"

FOO_FORMULAE=(foo)   # read by pack_array: update, health check, uninstall

foo_install() {
    print_header "Pack: foo"
    pkg_install "${FOO_FORMULAE[@]}" || print_warning "foo not installed (continuing)"
    print_success "foo pack complete"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then foo_install "$@"; fi
```

## Writing into `$HOME`

`install_config` has four modes, and a modifier for the third:

- `--managed-block ID` writes a fenced region and leaves everything outside it alone. Re-running rewrites only the block, and `update.sh --configs` re-applies it when it drifts. Use this for any file where `#` starts a comment, and for Markdown, where the markers are HTML comments because a `#` line would be a heading the agent reads.
  ```
  # >>> tuidev managed (tuidev-zshrc) >>>
  …repo-owned content…
  # <<< tuidev managed (tuidev-zshrc) <<<
  ```
- `--adopt-existing` places the file only when it is absent. Use it for formats without `#` comments (JSON) and for files the user owns once they exist.
- `--upgrade-shipped HASHFILE` is `--adopt-existing`, except that a file byte-identical to any version tuidev shipped is backed up and replaced, so fixes reach existing installs. HASHFILE (`shipped.sha256` next to the source) lists `<basename without extension> <sha256>` for every version ever shipped. Use it for whole files the user may edit (Seatbelt profiles, Claude and Codex settings). When you change such a source, append its new hash; `test_contract.sh` fails until you do.
- `--upgrade-shipped HASHFILE --merge-json` (JSON only) goes further for a file the user edited: it three-way merges the base (the source last applied, kept at `$TUIDEV_STATE_DIR/shipped/<name>.json`; `{}` before the first merge, so only additions arrive), the user's file and the new source. Values the user never touched follow the source; the user's changes and deletions stay; arrays keep the user's entries, drop the ones the source removed and append its new ones; where both changed a value, the user's wins and the path is reported. The file is backed up before a write and left alone when nothing changes. Invalid JSON or a missing `jq` falls back to plain `--upgrade-shipped`. The jq program is `tuidev_json_merge3` in `config_write.sh`. Use it for `~/.claude/settings.json`, which users always edit.
- `--overwrite` replaces the file after taking a backup. Use it only for files tuidev fully owns (`sbx`, `notify.sh`, the `shell.d` fragments).

Backups go to `$TUIDEV_STATE_DIR/backups/`, and only the most recent copies of each file are kept. Everything placed is recorded in the manifest, so `uninstall.sh` can remove exactly that and nothing else.

## Migrations

Deleting or renaming something the installer used to place needs a migration. Removing it from the repo never cleans up the copy already in a user's `$HOME`. A migration is `scripts/migrations/YYYYMMDDHHMM_slug.sh`, runs at most once per machine, and has to be safe to re-run by hand. The contract is in [scripts/migrations/README.md](../scripts/migrations/README.md), and how migrations run is in [updating.md](updating.md#migrations).

## Shell rules

- **bash 3.2.** macOS ships bash 3.2, so every script, including `update.sh`, must run under it: no associative arrays, `mapfile`, `${var,,}` or `declare -n`. CI runs the lib tests and a desktop dry-run under `/bin/bash` on macOS.
- **`.zshrc` is zsh.** Validate it with `zsh -n`, never `bash -n`.
- **shellcheck-clean.** Quote variables, prefer `[[ ]]`, declare `local`.
- **`$HOME`, never a literal home path.** CI rejects `/Users/<name>/`, `/home/<name>/` and `user@host.local` forms. Placeholders such as `/Users/NAME` are fine.
- **Nothing personal.** Hosts, IPs, usernames and hardware go in gitignored `*.local` files or `.local/`. See [CONTRIBUTING.md](../CONTRIBUTING.md#personal-vs-published).
- **No `curl | sh`.** When a package manager can't supply a tool, print the official command and let the user run it.

## Verification

Run these locally, in this order. `make ci-test` runs the first four.

```bash
make lint              # shellcheck -x over every shell file (the list lives in the Makefile)
make validate-configs  # JSON, TOML, Lua, zsh/sh syntax (CI adds --strict)
make check-links       # every relative link in every tracked .md resolves
make test-lib          # scripts/lib/test_*.sh: agents, agents_golden, agents_history, agents_hooks, agents_report, agents_report_tokens, agents_install, agents_mcp, agents_needs, agents_runs, agents_show, agents_tokens, config_write, container, contract, gitconfig, migrations, orchestration, pkg, profile, theme, update_packages
make test-core         # core-tagged tests against this machine
make container-test    # core-tagged tests in an Alpine container (tests scripts and configs, not the installer)
```

CI (`.github/workflows/ci.yml`, with actions pinned to a SHA and updated by Dependabot) runs these jobs:

- **shellcheck** (`make lint`)
- **validate configs** (`--strict`)
- **no hardcoded paths** (`scripts/check_paths.sh`, also `make check-paths`)
- **required files**
- **macOS**: Seatbelt profiles parse, the `sbx` smoke test, the lib tests under bash 3.2, and a `desktop` dry-run
- **unit tests**, plus `minimal` and `remote` dry-runs
- **docker core-tag test**
- **documentation links** (`scripts/check_links.sh`)
- **summary**, which fails if any job failed

## Screenshots

The README's images in `docs/assets/` and the social preview card (`social-preview.png`, 1280×640, uploaded by hand in the repo's Settings › Social preview) are regenerated, never edited by hand:

- the terminal shots (`tour.gif`, `herdr.gif` and `herdr.png`, `cleanup.gif`, `cli.gif`, `shell.png`, `agents.png`, `sbx.png`, the card) from [VHS](https://github.com/charmbracelet/vhs) tapes in `docs/assets/tapes/`;
- the menu-bar picture (`menu-light.webp`, `menu-dark.webp`, `menu.gif`) by `scripts/render_menu.sh`, which draws the SwiftBar plugin's real output as a macOS menu and captures it with headless Chrome.

Re-render them whenever a change alters what they show, such as `agents` output or its verdicts, the menu plugin, `sbx` messages, the shipped zsh, the prompt or the palette:

```bash
brew install vhs                 # once; it brings ttyd and ffmpeg
make screenshots                 # every tape, then the menu (scripts/screenshots.sh)
make screenshots TAPES=sbx       # just one; TAPES=menu for the menu picture
```

The tapes run in a throwaway home with made-up projects, `agents` reads fixture process tables and a made-up history, and the Herdr tape runs a real Herdr against two throwaway Linux containers with scripted agent stand-ins, so nothing from your machine reaches an image. Look at every image before you commit it (for a GIF, pull frames out with `ffmpeg -ss SECONDS -i docs/assets/tour.gif -frames:v 1 frame.png`), and keep each still under about 500 KB and each GIF under 2 MB (with `gifsicle` installed, the script optimizes them). End a tape with a `Sleep` after its last `Screenshot`: VHS can drop one that is the final command, and the script fails when a tape's file is missing. `make screenshots` runs on macOS only: the `sbx` shot needs Seatbelt, and the demo is only checked there. The Herdr tape also needs Apple's `container` CLI (without it, the tape is skipped), and the menu needs Chrome or Chromium and Swift. If VHS fails, the script prints the end of its log. VHS listens on a local port, so it fails inside a sandbox that doesn't allow binding one, such as Claude Code's native sandbox unless `sandbox.network.allowLocalBinding` is on; run `make screenshots` outside it. The fixtures, the demo wrappers, the Herdr fleet and the menu renderer are described in [docs/assets/tapes/README.md](assets/tapes/README.md).
