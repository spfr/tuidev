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
| `configs/zsh/opencode.zsh` | `~/.config/tuidev/shell.d/` | overwrite; sourced last by `.zshrc` |
| `configs/{claude,codex}/` | `~/.claude/settings.json` (`settings.linux.json` on Linux), `~/.codex/config.toml` | upgrade-shipped (ai-clis pack) |
| `configs/codex/rules/tuidev.rules` | `~/.codex/rules/tuidev.rules` | overwrite (ai-clis pack) |
| `configs/orchestration/` | `~/.claude/{rules,agents,skills}`, `~/.codex/{AGENTS.md,agents}`, `~/.agents/skills` | overwrite + managed block `tuidev-orchestration` in `~/.codex/AGENTS.md` (orchestration pack) |
| `configs/{opencode,herdr}/` | `~/.config/opencode/`, `~/.config/herdr/` | adopt-existing |
| `configs/themes/<name>/palette.toml` | `~/.config/tmux/theme.conf` + blocks in the Ghostty and Starship configs | `scripts/theme.sh` |
| `configs/nvim/` | `~/.config/nvim/` | upgrade-shipped per file, only while tuidev owns the tree (`nvim` pack) |
| `configs/tmux/tmux.conf` | `~/.config/tmux/tmux.conf` | managed block `tuidev-tmux` + TPM bootstrap (`tmux` pack) |

tuidev keeps its own state in `TUIDEV_STATE_DIR`, which defaults to `${XDG_CONFIG_HOME:-$HOME/.config}/tuidev`. It is defined once, in `scripts/lib/ui.sh`, and holds `profile`, `manifest`, `env`, `migrations`, `theme`, `backups/`, `sandbox/` and `shell.d/`. Derive every state path from it.

```
bin/sbx                 Seatbelt wrapper
configs/                everything installed into $HOME (table above)
scripts/lib/            shared libraries + test_*.sh unit harnesses
scripts/install/        built-in packs (core remote sandbox ui extras); packs/ = optional packs (includes nvim.sh, tmux.sh)
scripts/migrations/     timestamped one-shot fixups
scripts/*.sh            update, health_check, test_suite, theme, validate_configs,
                        check_links, container, notify, setup_agent_configs, fix_completions
templates/              AGENTS_TEMPLATE.md for downstream projects
```

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
| `ui.sh` | `print_header/step/success/warning/error/info`, `run_cmd` (dry-run aware), `command_exists`, `is_macos`/`is_linux`, `file_mode`/`file_owner`, `die`, `TUIDEV_STATE_DIR` |
| `pkg.sh` | `pkg_install NAME...`: Homebrew, then `apt-get`, `dnf`, `pacman`, using Homebrew names mapped per distro. Also `pkg_manager`, `pkg_manual_hint` and `PKG_UNAVAILABLE`. It fails soft, never prompts for a sudo password, and records what it installs |
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

`install_config` has four modes:

- `--managed-block ID` writes a fenced region and leaves everything outside it alone. Re-running rewrites only the block, and `update.sh --configs` re-applies it when it drifts. Use this for any file where `#` starts a comment, and for Markdown, where the markers are HTML comments because a `#` line would be a heading the agent reads.
  ```
  # >>> tuidev managed (tuidev-zshrc) >>>
  …repo-owned content…
  # <<< tuidev managed (tuidev-zshrc) <<<
  ```
- `--adopt-existing` places the file only when it is absent. Use it for formats without `#` comments (JSON) and for files the user owns once they exist.
- `--upgrade-shipped HASHFILE` is `--adopt-existing`, except that a file byte-identical to any version tuidev shipped is backed up and replaced, so fixes reach existing installs. HASHFILE (`shipped.sha256` next to the source) lists `<basename without extension> <sha256>` for every version ever shipped. Use it for whole files the user may edit (Seatbelt profiles, Claude and Codex settings). When you change such a source, append its new hash; `test_contract.sh` fails until you do.
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
make test-lib          # scripts/lib/test_*.sh: config_write, container, contract, migrations, pkg, profile, theme
make test-core         # core-tagged tests against this machine
make container-test    # core-tagged tests in an Alpine container (tests scripts and configs, not the installer)
```

CI (`.github/workflows/ci.yml`, with actions pinned to a SHA and updated by Dependabot) runs these jobs:

- **shellcheck** (`make lint`)
- **validate configs** (`--strict`)
- **no hardcoded paths**
- **required files**
- **macOS**: Seatbelt profiles parse, the `sbx` smoke test, the lib tests under bash 3.2, and a `desktop` dry-run
- **unit tests**, plus `minimal` and `remote` dry-runs
- **docker core-tag test**
- **documentation links** (`scripts/check_links.sh`)
- **summary**, which fails if any job failed
