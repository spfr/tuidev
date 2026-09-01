# Contributing to tuidev

Thank you for your interest. This document captures the conventions this repo follows. See [VISION.md](VISION.md) for the product direction (especially the "2026 Amendments" at the top) before proposing anything directional.

## How to Contribute

### Reporting Issues

1. **Search existing issues** first to avoid duplicates
2. **Use issue templates** when available
3. **Include environment details:**
   - macOS version
   - Shell (zsh/bash)
   - Relevant tool versions

### Submitting Pull Requests

1. **Fork the repository** and create your branch from `main`
2. **Follow code style** (see below)
3. **Test your changes:**
   ```bash
   make ci-test           # lint + validate-configs + core tests (what CI gates on)
   make docker-test       # Linux smoke test in a clean container
   ```

   Or run the pieces individually:

   ```bash
   make lint              # shellcheck install/uninstall, scripts, lib, tmux, packs, migrations, bin
   make validate-configs  # KDL / TOML / Lua / JSON syntax
   make test-core         # core-tagged tests
   bash scripts/lib/test_config_write.sh   # and test_profile / test_contract /
                                           # test_theme / test_migrations
   ```
4. **Update documentation** if you changed behavior
5. **Write clear commit messages** using conventional commits

### Code Style

> The canonical engineering conventions — shared libs, the pack contract, the
> package-array discovery convention, managed-block rules, and the small-function
> bar — live in [docs/engineering.md](docs/engineering.md). The highlights:

#### Shell Scripts

- Use `shellcheck` for linting (run `make lint`)
- Use `$HOME` instead of `~` for portability
- Quote variables: `"$variable"` not `$variable`
- Use `[[ ]]` for conditionals (bash/zsh)
- Add comments for non-obvious code

#### Configuration Files

- Use consistent indentation (2 spaces for TOML/KDL, 4 for Lua)
- Use `$HOME` instead of a hardcoded home directory
- Personal LAN hosts and mDNS names belong in gitignored `*.local` overlays (`~/.zshrc.local`, `~/.ssh/config.local`) — never in `configs/`, `docs/`, or `scripts/`
- Test configs with `make validate-configs`

### Development Workflow

```bash
# Clone your fork
git clone https://github.com/YOUR_USERNAME/tuidev.git
cd tuidev

# Create a branch
git checkout -b feature/your-feature

# Make changes and test
make lint
make test

# Commit with conventional message
git commit -m "feat: add new feature"

# Push and create PR
git push origin feature/your-feature
```

### Commit Convention

Use conventional commit format:

- `feat:` New feature
- `fix:` Bug fix
- `docs:` Documentation only
- `style:` Formatting, no code change
- `refactor:` Code restructure, no behavior change
- `test:` Adding or updating tests
- `chore:` Maintenance tasks

Examples:
```
feat: add k9s kubernetes TUI
fix: correct zsh completion path
docs: update remote sessions guide
```

### Testing Requirements

All PRs must pass:

1. **Shellcheck** - No lint errors
2. **Config validation** - Valid KDL/TOML/Lua/JSON syntax
3. **No hardcoded paths** - Use `$HOME` variables; no real hostnames, mDNS names, or usernames anywhere in the repo (CI `check-paths` fails on both)
4. **Library unit tests** - `scripts/lib/test_*.sh` (config_write, profile, contract, theme, migrations)
5. **Seatbelt profiles** - Every `.sb` parses under `sandbox-exec -n` (macOS runner)
6. **Docker tests** - Install works in clean environment
7. **Docs links** - Every `docs/...` link in the README resolves

Run all checks:
```bash
make ci-test
```

### Packs, profiles, and managed blocks

See [docs/engineering.md](docs/engineering.md) for the full pack contract and a
worked example. In short:

- New tools go into the **right pack**: core (essential), remote (Tailscale/mosh), ui (macOS GUI), sandbox (Seatbelt/Podman), extras (optional), or a new pack under `scripts/install/packs/`.
- Every pack script follows the contract in `scripts/install/core.sh`: `#!/bin/bash`, `set -e`, source `scripts/lib/ui.sh`, expose one entrypoint function named `<pack>_install`, runnable both directly and when sourced.
- Configs that are written to `$HOME` use **managed blocks** via `scripts/lib/config_write.sh`. Never `cp` over a user's file; never `rm -rf ~/.config/X`.
- Tmux layouts live under `scripts/tmux/layout-*.sh` and are attach-or-create + dry-run aware.
- Sandbox profiles live under `configs/sandbox/profiles/*.sb` and must parse under `sandbox-exec -n NAME -f FILE` (CI enforces this on macOS).
- Anything a pack puts on the machine must be recorded to the install manifest via the shared libs, so `uninstall.sh` can remove it and nothing else. Never `brew install` directly — use `brew_install_formulae` / `brew_install_casks`.
- Removing a file the installer used to place needs a **migration** (`scripts/migrations/YYYYMMDDHHMM_slug.sh`) — deleting it from the repo will never clean up the copy in a user's `$HOME`. Contract: [`scripts/migrations/README.md`](scripts/migrations/README.md).
- New themes are a `configs/themes/<name>/palette.toml` satisfying the full 26-key contract — no per-tool config edits. See [docs/theming.md](docs/theming.md).
- Never pipe a remote install script into a shell on the user's behalf. If a package manager can't supply a tool, print the official command and let the user run it.

### Areas for contribution

- **New packs** that slot into the layered installer.
- **Tmux layouts** for workflows we haven't covered.
- **Seatbelt profile refinements** — especially narrowing net egress where Apple's kernel supports it.
- **Linux parity**: `bubblewrap` wiring for the sandbox; the core pack has an apt fallback already, so dnf/pacman equivalents and apt coverage in the remaining packs are the open work.
- **Docs**: clarity, not volume.
- **Bug fixes** — always with a test tag.

### What we're not looking for

- GUI application additions beyond the `ui` pack (the repo is terminal-first).
- AI tooling that runs **in-editor by default**. `configs/nvim/lua/plugins/ai.lua` stays empty; ACP integrations can be opt-in only.
- Breaking changes to public commands (`work`, `dev`, `ai`, `sbx`, …) without a deprecation path.
- Dependencies on non-FOSS tools for default paths (explains why Docker Desktop / OrbStack are not used).

## Getting Help

- Open an issue for questions
- Check existing docs in `docs/` directory
- Review [docs/FAQ.md](docs/FAQ.md) for common questions
- Participation is governed by our [Code of Conduct](CODE_OF_CONDUCT.md); security reports go through [SECURITY.md](SECURITY.md)

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
