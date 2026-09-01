# Updating an Installed tuidev

How an existing install moves forward, and what the installer records so it can
be undone. For the one-time zellij-to-tmux command changes see
[migration.md](migration.md); for what each profile installs see
[profiles.md](profiles.md).

## The three kinds of change

An update has to handle three different things, and they need different
machinery:

| Change | Handled by | Runs |
|--------|-----------|------|
| A package got a new version | `update.sh --packages` | every time |
| A repo-owned config changed | `update.sh --configs` (managed blocks) | every time |
| A past release left an artifact behind | `update.sh --migrations` | once per machine |

The first two converge *current* state and are safe to repeat forever. The third
cannot be: once a file's source is deleted from the repo, no amount of
re-running the installer will ever notice — let alone remove — the copy sitting
in `$HOME`. That is what migrations are for.

## Migrations

```bash
make update-check                 # lists pending migrations, runs nothing
./scripts/update.sh --migrations  # runs them
./scripts/update.sh --configs     # runs pending migrations first, then configs
./scripts/update.sh --all         # packages, then migrations + configs, then repo
```

Each migration is a script in `scripts/migrations/`, named
`YYYYMMDDHHMM_short_slug.sh`. The timestamp prefix means lexical sort is
chronological, which is the order they run in. The id (the filename without
`.sh`) is appended to `~/.config/tuidev/migrations` once it has succeeded, and a
recorded id never runs again on that machine.

Three properties worth knowing:

- **`--dry-run` and `--check` list, they never run.** You always get to see what
  is pending before anything happens.
- **A failure stops the whole run** and the id is *not* recorded, so the next
  update retries it. The machine is in a known-bad state at that point and
  re-applying configs on top would only obscure it.
- **Fresh installs skip history; upgrades apply it.** On a machine tuidev has
  never touched, `install.sh` marks every existing migration applied without
  running it — a brand-new machine has no legacy state to repair. On a machine
  that already has a tuidev install, re-running `install.sh` (`./install.sh
  --pack herdr`, say) *applies* pending migrations first, before the packs write
  anything. The "never touched" test is the absence of both
  `~/.config/tuidev/profile` and `~/.config/tuidev/manifest`, checked before the
  run writes anything — not the absence of the migrations state file, which
  every pre-2.2 install also lacks.

To inspect or reset by hand:

```bash
cat ~/.config/tuidev/migrations                 # what has been applied
grep -v '^202608310900' ~/.config/tuidev/migrations > /tmp/m \
  && mv /tmp/m ~/.config/tuidev/migrations      # force one to run again
```

Writing one? The contract is in
[`scripts/migrations/README.md`](../scripts/migrations/README.md).

## The install manifest

`~/.config/tuidev/profile` records *which packs you picked*. As of 2.2.0 the
write is a merge, not a rewrite: a pack-only run like `./install.sh --pack
herdr` unions `extra_packs` with what was already recorded, only ever flips
group booleans (core/remote/sandbox/ui/extras) true, and keeps the previously
recorded profile name (minimal/desktop/remote) instead of resetting it to
`custom` — unless `--profile` is explicitly passed on that run.
`~/.config/tuidev/manifest` records *what was actually put on the machine* —
the question the uninstaller needs answered. It is written silently as a side
effect of the shared libs: every `brew_install_formula`, every managed block,
every file `install_config` places appends a line.

```
# tuidev install manifest — one record per line: <kind> <value>
profile desktop
pack core
formula ripgrep
cask ghostty
block tuidev-zshrc /Users/NAME/.zshrc
file /Users/NAME/.local/bin/notify.sh
dir /Users/NAME/.config/nvim
```

Line-oriented and greppable on purpose — `grep '^formula ' ~/.config/tuidev/manifest`
is a valid way to use it. The file is append-only and deduplicated, so
installing another pack later adds to it rather than replacing it. Records can
go stale (a formula you later removed by hand); every consumer re-checks that a
thing exists before acting on it, so a stale record is inert.

**Only packages tuidev actually installed are recorded.** A formula that was
already present when a pack ran is skipped, so `./uninstall.sh` will not remove
the `ripgrep` you had before you ever found this repo.

### What uninstall does with it

`./uninstall.sh` prints which mode it is in on startup:

- **Manifest present** — it strips the managed blocks, removes the `~/.local/bin`
  helpers, and purges the brew packages that *this* machine recorded.
- **No manifest** (an install predating this feature, or one that never
  finished) — it warns and falls back to the built-in list covering everything
  tuidev can install. Uninstall has never required a manifest and still doesn't.

The opt-in "also remove tuidev-owned configs" step is the one exception: it
removes the union of the manifest's records and the well-known tuidev-owned
paths, because a few packs still place configs with a bare `cp` and record
nothing. That step is consented to and backs everything up to
`~/.config-uninstall-backup-*/` first.

## Everything else `update.sh` does

```bash
make update-check          # preview: packages, migrations, drift, repo
make update-packages       # brew upgrade, scoped to your active packs
make update-configs        # migrations, then re-apply managed blocks + pack configs
make update-all            # non-interactive packages + configs + repo
make update-security       # audit Tailscale, SSH perms, Seatbelt drift
```

Bare `./scripts/update.sh` gives an interactive menu with the same actions.
Every mode honors `--dry-run`.
