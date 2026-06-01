# Engineering Practices

How the shell, install, and config code in this repo is built. The bar is
**small, composable, non-destructive** — the same standard whether a human or an
agent is editing. Read this before touching anything under `scripts/`, `bin/`,
or `install.sh`.

> Conventions only. For *what* to contribute and the PR process see
> [CONTRIBUTING.md](../CONTRIBUTING.md); for *why* the project is shaped this way
> see the design decisions in [CLAUDE.md](../CLAUDE.md).

## Principles

- **DRY** — one behavior, one place. If two scripts need the same logic, it
  belongs in `scripts/lib/`, not copy-pasted. Pack-discovery, brew installs, and
  printing all already live in libs; reach for them.
- **KISS** — the obvious solution beats the clever one. Don't add an abstraction
  until there's a second caller. A four-line loop is fine; a four-line loop
  copied eight times is a missing helper.
- **Small functions, single responsibility** — a function does one nameable
  thing. If you can't summarize it in its name, split it. No behemoths: when a
  function outgrows a screen, extract the inner steps (see `_fnm_ensure_node`,
  `_report_brew_group`).
- **Separation of concerns** — *packs install tools; the cross-cutting section
  of `install.sh` writes settings.* Discovery, reporting, and mutation are
  separate functions. Keep them that way.
- **Non-destructive by default** — never `cp` over a user's file and never
  `rm -rf` a user config. Write through managed blocks; back up first.
- **Idempotent** — every install/update step is safe to run twice. Check before
  you mutate (`brew_has_formula`, `cmp -s`, "already present").
- **Fail soft on optional work** — an optional tool that won't install warns and
  continues (`|| print_warning "… (continuing)"`); only genuinely-required
  preconditions `die`.

## Use the shared libraries — don't reimplement

Source these instead of rolling your own. All are idempotent and safe to source
more than once.

| Lib | Provides | Reach for it when |
|-----|----------|-------------------|
| `scripts/lib/ui.sh` | `print_*`, `run_cmd`/`run_sh` (dry-run aware), `command_exists`, `is_macos`/`is_linux`, `die` | any user-facing output or guarded command |
| `scripts/lib/brew.sh` | `brew_update_once`, `brew_has_formula`/`brew_has_cask`, `brew_install_formula`/`brew_install_cask`, and the plural `brew_install_formulae`/`brew_install_casks` | installing Homebrew packages |
| `scripts/lib/config_write.sh` | `install_config` (managed-block + `--adopt-existing`) | writing anything into `$HOME` |
| `scripts/lib/profile.sh` | profile manifest read/write, `TUIDEV_VALID_PACKS` | reading/altering the active profile |

Rules of thumb:

- **Never call `brew install` directly** in a pack — `brew_install_formula(e)`
  is idempotent, dry-run aware, and keeps the install cache warm.
- **Never `echo` raw status** — use `print_step/success/warning/info` so
  `TUIDEV_NO_COLOR` and CI output behave.
- **Always wrap mutations in `run_cmd`** so `--dry-run` previews instead of
  executing.

## The pack contract

Every pack is one file: `scripts/install/<pack>.sh` (core packs) or
`scripts/install/packs/<pack>.sh` (optional). It must:

1. Start with `#!/bin/bash` and `set -eo pipefail`.
2. Resolve its own dir and source the libs it uses:
   ```bash
   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
   . "$SCRIPT_DIR/../../lib/ui.sh"
   . "$SCRIPT_DIR/../../lib/brew.sh"
   ```
3. Declare its Homebrew packages as **uppercase-name arrays** so the updater can
   discover them without running the installer (see table below):
   ```bash
   FOO_FORMULAE=(foo)      # brew formulae
   FOO_CASKS=(foo-app)     # brew casks (macOS)
   ```
4. Expose exactly one entrypoint, `<pack>_install` (hyphens in the pack name
   become underscores: `sandbox-container` → `sandbox_container_install`).
5. Be runnable both sourced and directly:
   ```bash
   if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then foo_install "$@"; fi
   ```

`install.sh`'s `run_optional_pack` auto-discovers `packs/<name>.sh` →
`<name>_install`; **no edit to `install.sh` is needed** to add an optional pack.
Register the pack name in `scripts/lib/profile.sh` (`TUIDEV_VALID_PACKS`) and the
docs.

### Package-array convention (why the arrays matter)

`scripts/update.sh` upgrades packages by *sourcing each pack in a subshell and
reading its arrays* — it never runs the installer. It sniffs these names, in
order, and falls back to scraping `brew install` lines:

| Kind | Array names checked |
|------|---------------------|
| Formulae | `<PACK>_FORMULAE`, `<PACK>_PACKAGES`, `<PACK>_BREW`, `<PACK>_BREW_FORMULAE`, `FORMULAE`, `PACKAGES` |
| Casks | `<PACK>_CASKS`, `<PACK>_CASKS_MACOS`, `<PACK>_BREW_CASKS`, `CASKS`, `CASKS_MACOS` |

If a pack installs via brew but **doesn't** declare an array, it silently drops
out of `update.sh --packages`. Declare the array. Tools installed by other means
(cargo, official scripts) legitimately have no array and are reported as
"no formulae discovered" — that's expected.

## Managed blocks (writing into `$HOME`)

User home files are shared territory. `install_config` writes a fenced region:

```
# >>> tuidev managed (tuidev-zshrc) >>>
…repo-owned content…
# <<< tuidev managed (tuidev-zshrc) <<<
```

- Content **outside** the markers is the user's and is preserved across updates.
- Re-running rewrites only the block; `update.sh --configs` detects drift and
  re-applies.
- Use `--adopt-existing` for formats where `#` isn't a comment (e.g. KDL —
  see `packs/zellij.sh`): drop the file in only when absent, never inject markers.
- Backups land in `~/.config/tuidev/backups/` before any overwrite.

## Verification gates

Run before every commit; CI (`.github/workflows/ci.yml`) enforces the same:

```bash
make lint              # shellcheck — install.sh, scripts/**, bin/sbx
make validate-configs  # JSON / TOML / Lua / KDL syntax; .zshrc via zsh -n
make test-core         # core-tagged contract + behavior tests
make docker-test       # Linux smoke test in a clean container (parity)
```

Notes:

- **Lint is non-negotiable** — zero shellcheck findings. Quote variables, prefer
  `[[ ]]`, declare `local`.
- `.zshrc` is **zsh**, not bash — validate with `zsh -n`, never `bash -n`
  (anonymous functions, glob qualifiers, and `${(nO)}` are zsh-only).
- macOS ships **bash 3.2**; libs avoid associative arrays. `update.sh` uses
  bash-4 features and is run under a newer bash — keep new lib code 3.2-clean.
- No hardcoded `/Users/NAME` or `/home/NAME` — always `$HOME` (CI `check-paths`).
- Every `docs/…` link in `README.md` must resolve (CI `check-docs`).

## Worked example — a minimal optional pack

```bash
#!/bin/bash
# Optional pack: foo — installs the foo TUI.
set -eo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/../../lib/ui.sh"
. "$SCRIPT_DIR/../../lib/brew.sh"

FOO_FORMULAE=(foo)   # discovered by update.sh --packages

foo_install() {
    print_header "Pack: foo"
    command_exists brew || die "Homebrew is required; install from https://brew.sh"
    brew_install_formulae "${FOO_FORMULAE[@]}"
    print_success "foo pack complete"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then foo_install "$@"; fi
```

Then: add `foo` to `TUIDEV_VALID_PACKS` in `scripts/lib/profile.sh`, list it in
`docs/profiles.md` + `README.md`, and you're done — install, update, and
health-check all pick it up.
