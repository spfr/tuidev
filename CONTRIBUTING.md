# Contributing to tuidev

Thanks for your interest. Read [VISION.md](VISION.md) before proposing anything directional, and [docs/engineering.md](docs/engineering.md) before touching `install.sh`, `scripts/`, `bin/` or `configs/`. It holds the architecture, shared libraries, pack contract and managed-block rules that this file only summarizes.

## Reporting issues

Search existing issues first, then use the issue template. Include your tuidev version (`git describe --tags`), OS and version, profile and packs (`cat ~/.config/tuidev/profile`), and the output of `make check`. Report security issues privately (see [SECURITY.md](SECURITY.md)).

## Pull requests

1. Fork, then branch from `main`.
2. Make the change, following [docs/engineering.md](docs/engineering.md).
3. Verify:
   ```bash
   make ci-test        # lint + validate-configs + check-links + test-lib
   make test-core      # core-tagged tests against your machine
   make container-test # core-tagged tests in an Alpine container (Apple container → podman → docker)
   ```
4. Update the docs that own the topic you changed (the README's documentation index says which doc owns what), and add a `CHANGELOG.md` entry under the unreleased version.
5. Use conventional commits: `feat:`, `fix:`, `docs:`, `refactor:`, `test:`, `chore:`, `ci:`. Keep commits atomic, and don't add `Co-Authored-By` trailers.

### Test harnesses

| Harness | Covers |
|---------|--------|
| `make lint` | shellcheck over every shell file (the list is `SHELL_FILES` in the Makefile) |
| `make validate-configs` | JSON, TOML, Lua and shell syntax of everything in `configs/` |
| `make check-links` | Every relative link in every tracked Markdown file |
| `make test-lib` | `scripts/lib/test_*.sh`: config_write, container, contract (cross-file names, documented packs), migrations, pkg, profile, theme |
| `make test` / `test-core` / `test-all` | `scripts/test_suite.sh`: tagged checks against the installed machine |
| `make container-test` | `test_suite.sh --tag core` in an Alpine image. It tests the scripts, configs and tool contract on Linux, **not** the installer. The apt path is exercised on a real Debian box. |
| `make sbx-test` | On macOS: `sbx` can read the project and cannot read `~/.ssh` |

CI runs lint, validate-configs (`--strict`), check-links, test-lib and the container core-tag test. On macOS it also parses the Seatbelt profiles, runs the lib tests under bash 3.2, and does a `desktop` install dry-run. On Linux it does `minimal` and `remote` dry-runs. The job list is in [docs/engineering.md](docs/engineering.md#verification).

## Where changes go

- **New tools** go in the right pack: core (essential), remote, sandbox, ui (macOS GUI), extras, or a new optional pack under `scripts/install/packs/`. Follow the pack contract, and register the pack in `TUIDEV_VALID_PACKS`.
- **Files written to `$HOME`** go through `install_config` (managed block, adopt-existing or overwrite). Never `cp` over a user's file, and never `rm -rf` a config.
- **Removing something the installer used to place** needs a migration in `scripts/migrations/` (see [its README](scripts/migrations/README.md)).
- **Optional tools like `nvim` and `tmux`** are packs like any other: follow the pack contract in [docs/engineering.md](docs/engineering.md#the-pack-contract), not a special case.
- **Seatbelt profiles** go in `configs/sandbox/profiles/*.sb`. Every profile must parse under `sandbox-exec` (CI checks this on macOS).
- **Themes** are one `configs/themes/<name>/palette.toml` with all 26 keys (see [docs/theming.md](docs/theming.md)).

Good areas to contribute: new packs, tighter Seatbelt rules, Linux parity (a `bubblewrap` backend for `sbx`; wider dnf and pacman coverage), bug fixes with a test, and docs that gain clarity without gaining volume.

Not wanted: GUI apps outside the `ui` pack; AI that runs in-editor by default; breaking public commands (`t`, `sbx`, `claude -w`, …) without a deprecation path; non-FOSS tools on default paths; `curl | sh` on the user's behalf.

## Personal vs published

This repository is public, and cloning it should never leak anyone's setup.

| Belongs in git | Belongs in `*.local` or `.local/` only |
|----------------|----------------------------------------|
| `ssh devbox`, `herdr --remote workbox` | Real hostnames, mDNS names, Tailscale IPs, usernames |
| A commented `Host always-on` example | Your `Host` stanzas (`~/.ssh/config.local`) |
| Hardware *class* ("a Raspberry Pi or NUC") | Your board, services and network layout |
| Generic agent guidance (`AGENTS.md`) | Machine notes and personal agent instructions (`.local/`, `CLAUDE.local.md`) |

`.gitignore` excludes `*.local`, `.local/` and `CLAUDE.local.md`. The shipped SSH block includes `~/.ssh/config.local*`, and `.zshrc` sources `~/.zshrc.local` last. CI's `no hardcoded paths` job fails on `/Users/<name>/`, `/home/<name>/` and `user@host.local` forms. Placeholders like `/Users/NAME` pass.

## Getting help

Open an issue, or check [docs/FAQ.md](docs/FAQ.md). Participation is governed by the [Code of Conduct](CODE_OF_CONDUCT.md).

## License

By contributing, you agree that your contributions are licensed under the MIT License.
