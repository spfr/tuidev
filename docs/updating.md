# Updating an Installed tuidev

How an existing install moves forward, and what the installer records so it can
be undone. For what each profile installs see
[profiles.md](profiles.md).

## Upgrading to 3.0

3.0 made tmux and Neovim optional packs, dropped the `cc`/`cx` wrappers in
favor of the CLIs' own native sandboxes, and removed the `bosun`, `yazi` and
`nnn` packs. On an existing machine, upgrade with:

```bash
git pull
./scripts/update.sh --configs     # or: make update-configs
```

That runs the three migrations below, then re-applies the configs of every
pack your profile records, including one a migration just added: the
`tuidev-tmux` block, the Neovim config and its `nvim.zsh` aliases, and an
unmodified 2.x `~/.claude/settings.json` upgraded to the one with the
`sandbox` block. `./install.sh` on its own is not enough: it runs the
migrations too, but only installs the packs you name on that command line.

The migrations, in order:

- `202609231200_v3_optional_nvim_tmux.sh` — if tuidev already owns
  `~/.config/nvim`, adds `nvim` to `extra_packs`; if the profile is `remote`
  or `~/.config/tmux/tmux.conf` has the `tuidev-tmux` block, adds `tmux`. So
  nothing you were using disappears. Prints what it carried over and how to
  drop it by hand (edit `extra_packs` in `~/.config/tuidev/profile`). A
  `tmux.conf` of your own never gains the `tuidev-tmux` block from an update;
  `./install.sh --pack tmux` adds it.
- `202609231210_v3_drop_tui_packs.sh` — removes `bosun`, `yazi` and `nnn` from
  `extra_packs`. The tools themselves are left installed; only the pack
  registration goes.
- `202609231220_v3_drop_ai_wrappers.sh` — backs up and deletes the
  tuidev-owned `ai-clis.zsh` shell fragment, so `cc`/`cx` disappear. It never
  edits `~/.claude/settings.json`; it tells you where that file stands. With
  a `sandbox` block, plain `claude` is sandboxed. An unmodified 2.x copy is
  upgraded by `./scripts/update.sh --configs`. One you edited is kept: merge
  the `sandbox` block yourself (see [sandboxing.md](sandboxing.md)). Until
  then, `claude` runs unsandboxed.

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

`~/.config/tuidev/profile` records *which packs you picked*. Each run merges
into it: a pack-only run like `./install.sh --pack herdr` adds to
`extra_packs`, only ever turns the built-in pack flags (core, remote, sandbox,
ui, extras) on, and keeps the recorded profile name unless you pass
`--profile` again.

`~/.config/tuidev/manifest` records *what was actually put on the machine*,
which is the question the uninstaller needs answered. The shared libs write it
as a side effect: every package `pkg_install` or `brew_install_*` actually
installed, every managed block, every file `install_config` placed, and every
git default the installer set gets a line.

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

The file is line-oriented and greppable on purpose: `grep '^formula ' ~/.config/tuidev/manifest`
is a valid way to use it. It is append-only and deduplicated. Records can go
stale (a formula you later removed by hand), so every consumer re-checks that a
thing exists before acting on it.

**Only what tuidev installed is recorded.** A package that was already present
when a pack ran is skipped, so `./uninstall.sh` won't remove the `ripgrep` you
had before you found this repo.

## Uninstall

```bash
./uninstall.sh --dry-run   # preview
./uninstall.sh             # interactive: asks before each step
./uninstall.sh --all       # yes to every step
```

It removes only what the manifest records:

- managed blocks, including the `tuidev-theme` blocks (content outside the markers stays);
- helpers in `~/.local/bin`;
- global git keys tuidev set, and only while they still hold tuidev's value;
- optionally, the config files tuidev created (each one backed up first). A
  file tuidev adopted is never removed, and neither is a whole CLI home, so auth
  and session state (`~/.claude/…`, `~/.codex/auth.json`) always survive;
- optionally, the Homebrew formulae and casks tuidev installed. apt, dnf and
  pacman packages are listed for you to remove, not removed;
- tuidev's state dir, except `backups/`.

An install that predates the manifest gets only the safe subset: managed blocks,
and helpers still byte-identical to the repo copy. Everything else is listed for
you to review.

## Everything else `update.sh` does

```bash
make update-check          # preview: packages, migrations, drift, repo
make update-packages       # upgrade the packages of your active packs only
make update-configs        # migrations, then re-apply managed blocks + pack configs
make update-all            # non-interactive packages + configs + repo
make update-security       # audit Tailscale, SSH permissions, Seatbelt profile drift
```

A bare `./scripts/update.sh` gives an interactive menu with the same actions.
Every mode honors `--dry-run`. `update.sh` runs under macOS's stock bash 3.2.

### Shipped configs you may have edited

Some configs are whole files the user may take over, so they can't be managed
blocks: the Seatbelt profiles in `~/.config/tuidev/sandbox/`, every file of
the Neovim config in `~/.config/nvim/` (with `--pack nvim`, keyed by its
path, so the two `init.lua` files stay distinct), and (with `--pack ai-clis`)
`~/.claude/settings.json` and `~/.codex/config.toml`. Each is installed with
`install_config --upgrade-shipped`:

- absent: it is placed;
- byte-identical to any version tuidev ever shipped (the `shipped.sha256` next
  to the source lists every one): it is backed up to
  `~/.config/tuidev/backups/` and replaced, so fixes such as tighter
  permissions reach existing installs;
- anything else is your edit and is kept; the run prints a
  `diff <yours> <shipped>` command so you can merge by hand.

`make update-configs` re-runs the packs, so this happens on every update.
Files you added (say, `~/.config/nvim/lua/plugins/mine.lua`) are never
touched. After a Neovim upgrade, `:Lazy sync` installs and cleans plugins.

`make update-configs` also applies new **git defaults** (`scripts/lib/gitconfig.sh`)
to keys you have not set, `[include]`d files included.
`make update-security` also shows how your profiles differ from the shipped
ones (see [sandboxing.md](sandboxing.md#customizing)).
