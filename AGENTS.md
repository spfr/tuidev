# AGENTS.md

Instructions for AI coding agents (Claude Code, Codex, OpenCode, and others) working **on this repository**. For the human-facing docs, start at [README.md](README.md).

## What this repo is

tuidev: an opinionated, agent-first terminal setup for macOS (and Linux). It is shell scripts plus configs:

- `install.sh` / `uninstall.sh`: a layered, manifest-recording installer.
- `scripts/`: packs, libs, update, tests, migrations.
- `configs/`: what gets installed into `$HOME`.
- `bin/sbx`: the Seatbelt wrapper.

It is a **public** repo that ships best practices only. The architecture map is in [docs/engineering.md](docs/engineering.md).

## Verify

Run the cheapest check that covers your change, then the full local gate before you say you're done:

```bash
make lint              # shellcheck -x over every shell file (list: SHELL_FILES in the Makefile)
make validate-configs  # JSON / TOML / Lua / shell syntax
make test-lib          # scripts/lib/test_*.sh unit harnesses
make check-links       # relative links in every tracked .md
make ci-test           # all of the above: what CI gates on, minus the macOS and container jobs
```

Targeted runs: `bash scripts/lib/test_contract.sh` (cross-file names and documented packs), `bash scripts/lib/test_<name>.sh`, and `./install.sh --profile desktop --dry-run < /dev/null` (also try it under `/bin/bash` on macOS, which is 3.2).

**Done means verified.** Don't report a change as finished until the relevant commands above pass. Paste the command and its result, not a claim. If you couldn't run something (no tmux, not on macOS), say so.

## Engineering rules

The full conventions are in [docs/engineering.md](docs/engineering.md). The rules that matter most:

- **Use the shared libs in `scripts/lib/`, and never reimplement them:**
  - `ui.sh`: output, `run_cmd`, platform probes, `TUIDEV_STATE_DIR`
  - `pkg.sh`: `pkg_install` over brew → apt → dnf → pacman
  - `gitconfig.sh`: `tuidev_git_defaults` (unset keys only; install and `update --configs`)
  - `packs.sh`: pack discovery and arrays
  - `config_write.sh`: `install_config`, managed blocks, backups
  - `profile.sh`: the profile file and `TUIDEV_VALID_PACKS`
  - `manifest.sh`: install records
  - `migrate.sh`: the migration runner
- **Pack contract:**
  - One file, at `scripts/install/<name>.sh` for built-in packs or `scripts/install/packs/<name>.sh` for optional ones.
  - One entrypoint, `<name>_install` (hyphens become underscores).
  - Packages declared only as `<PACK>_FORMULAE` / `<PACK>_CASKS`.
  - The file defines only functions and arrays. It is sourced into the installer's shell.
  - Warn and continue on failure, never `exit`.
  - Register new packs in `TUIDEV_VALID_PACKS`, and document them in `docs/profiles.md`.
- **Writing into `$HOME`:** only through `install_config`:
  - `--managed-block ID` for `#`-comment formats;
  - `--adopt-existing` for JSON and user-owned files;
  - `--upgrade-shipped HASHFILE` for shipped whole files the user may edit (Seatbelt profiles, Claude and Codex settings). When you change such a file, append its new hash to the `shipped.sha256` next to it; `test_contract.sh` fails until you do;
  - `--overwrite` only for files tuidev fully owns.

  Never `cp` over a user file, and never `rm -rf` a config. Wrap mutations in `run_cmd` so `--dry-run` works.
- **Record what you install.** The libs write `~/.config/tuidev/manifest`, and `uninstall.sh` removes only what it records.
- **Removing or renaming an installed artifact needs a migration**, `scripts/migrations/YYYYMMDDHHMM_slug.sh`. See [scripts/migrations/README.md](scripts/migrations/README.md).
- **bash 3.2:** no associative arrays, `mapfile`, `${var,,}` or namerefs. `.zshrc` is zsh (`zsh -n`), not bash.
- **Portable paths:** `$HOME` and `$TUIDEV_STATE_DIR`, never a literal home directory.
- **No `curl | sh`.** If a package manager can't supply a tool, print the official command for the user.
- **Nothing personal:** no real hostnames, IPs, usernames or hardware. Use placeholders (`devbox`, `workbox`, `/Users/NAME`). Personal notes belong in the gitignored `.local/` folder or `CLAUDE.local.md`.
- **Docs:** each topic has one owning doc, listed in the README's documentation index. Update that doc, add a `CHANGELOG.md` entry, and keep `make check-links` green.

## Commits

- Conventional commits (`feat:`, `fix:`, `docs:`, `refactor:`, `test:`, `chore:`, `ci:`), atomic and focused.
- No `Co-Authored-By` trailers.
- Don't commit, push or open a PR unless you were asked to.

## Sandbox boundary

On a tuidev machine, you usually run under your CLI's own native sandbox now (Claude Code's `sandbox.enabled`, Codex's `sandbox_mode = "workspace-write"`), not `sbx`. `sbx` (macOS Seatbelt, `strict` profile) is still available as a general-purpose wrapper. The boundaries differ: Codex's `workspace-write` limits writes and network but **not reads**.

- **Writes:** only the project directory, `/tmp`, and the AI CLIs' own state dirs (`~/.claude`, `~/.codex`, …), but not the CLIs' settings, hooks, plugins or binaries (`~/.claude/settings.json`, `~/.codex/config.toml`, …). Ask the human to change those outside `sbx`.
- **Denied under `sbx` (read and write) and to Claude Code's Bash and `Read` tools; Codex `workspace-write` does not block reading them:** `~/.ssh`, `~/.aws`, `~/.gnupg`, `~/Library/Keychains`, `~/.config/gh`, `~/.config/gcloud`, `~/.config/op`, `~/.azure`, `~/.docker`, `~/.kube`, `~/.terraform.d`, `~/.password-store`, `~/.netrc`, `~/.git-credentials`, `~/.npmrc`, `~/.pypirc`, `~/.cargo/credentials*`, `~/.vault-token`, `~/.pgpass`, `~/.config/git/credentials`, `~/.config/containers/auth.json`, `~/.gem/credentials`. Don't read them under any sandbox, and don't work around a denial.
- **Network:** TCP 443, DNS and loopback only. Package installs over other ports need `sbx --profile standard`. Ask the human rather than escalating yourself.
- **`gh` fails under `sbx`**, because its token is denied. Ask the human to run it outside `sbx`, or (under the native sandbox) rely on its `excludedCommands` entry for `gh *`.
- **Herdr:** if `HERDR_ENV=1`, you are inside a Herdr pane. Use `herdr agent list` and the socket API, never the TUI, and never launch `herdr` again. Under `strict`, the socket is reachable only with `sbx --allow-herdr`.
- **Long-running processes** (dev servers, watchers) belong in a tmux pane, not a backgrounded `&` job.
- **Interactive TUIs are for the human.** Don't drive `lazygit`, `btm`, `lazydocker`, `k9s`, `fzf` or `atuin`. Use `git`, `gh`, `rg`, `fd` and `jq`.

Details: [docs/sandboxing.md](docs/sandboxing.md).
