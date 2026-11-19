# Updating an Installed tuidev

Read this to update tuidev, roll an update back, understand migrations, or remove
tuidev again: how an existing install moves forward, and what the installer records so it can
be undone. For what each profile installs see
[profiles.md](profiles.md).

## The short version

```bash
tuidev update              # tuidev itself: the latest release, its migrations, its configs
tuidev update --check      # preview: packages, migrations, config drift, the latest release
tuidev update --packages   # the packages of your active packs
tuidev update --all        # all of it, non-interactive
tuidev update --rollback   # back to the release before this one
tuidev whatsnew [FROM]     # this release's changelog, or everything since FROM
tuidev md [FILE]           # read Markdown in the pager, rendered where glow is installed
```

`tuidev` is installed into `~/.local/bin` by every install and finds tuidev's files through the path the installer recorded (`repo=` in `~/.config/tuidev/profile`). On its own it opens the palette, a searchable list of everything it and `agents` can do. In a clone the Makefile has the same actions as targets (`make update-check`, `make check`, `make perf`, `make disk`; `make help` lists them), and `./install.sh`, `./uninstall.sh` and `./scripts/update.sh` are what `tuidev install`, `uninstall` and `update` run.

## Installed with get.sh, or from a clone

Both run the same `install.sh`. They differ in where tuidev's files live and how the next version arrives.

| | `get.sh` (the one-line install) | A git clone |
|---|---|---|
| Files | `~/.local/share/tuidev/versions/X.Y.Z`, with `current` pointing at the one in use | Wherever you cloned it |
| Needs | `curl`, `tar`, `shasum` or `sha256sum` | `git` |
| `tuidev update` | Asks which release is the latest and, when it is newer, downloads it, checks it and moves `current` to it | `git pull --ff-only` |
| Version | A tagged release | Whatever you checked out |
| Rollback | `tuidev update --rollback` | `git checkout` a tag, then `./install.sh` |

[`get.sh`](../get.sh) is about 230 lines and is the only code that fetches tuidev. It downloads `tuidev.tar.gz` and `tuidev.tar.gz.sha256` from the release, refuses the archive unless the sha256 matches, every path in it sits under one `tuidev-X.Y.Z/` directory and none is a symlink or a hard link, unpacks it, asks what this machine should get when you named no flags (the installer's own four choices), and asks before it runs `install.sh` (answer `p` for a `--dry-run` first; with no terminal, as in CI or a container build, it installs only with `--yes`). `TUIDEV_VERSION=v3.23.0` picks a release other than the latest, and `bash get.sh --fetch` only downloads. The checksum guards against a truncated or mismatched download; that the files are tuidev's rests on HTTPS to github.com and on who can publish a release. The archive is `git archive` of the tagged commit. Each download is capped at 5 minutes and 64 MB. `current` switches with one rename, so it never points nowhere, and a re-download that is interrupted puts the earlier files back. If the installer stops partway, `get.sh` says the install is not complete and names `tuidev update --rollback` when an earlier release is kept. The release before the current one stays on disk, both for `--rollback` and because an update in progress still reads its files from there. Releases before 3.23.0 have no archive: clone the repo for those.

An update hands over to the new release's own `update.sh` before it runs migrations or writes configs, so those always come from the version you are moving to.

When `tuidev update` (or `--all`) cannot get the new files, because the release can't be reached or its download is refused, or a clone's `git pull --ff-only` fails, it changes nothing else and ends with `not updated: …` and exit 1, never with "Update Complete". An update whose files arrived but whose migrations or configs did not run to the end (the installed version in `~/.config/tuidev/version` is not the files' `VERSION`) is finished by the next `tuidev update`, which says `finishing the update to X`, even offline.

One update or install runs at a time: started again from the terminal, the menu bar or Herdr's popup while one runs, it stops with `another tuidev update is running (pid N)`. The lock is `~/.config/tuidev/update.lock`; one whose holder is gone (killed, or the machine restarted) is taken over. `--check` and `--dry-run` take none.

## Checking the install: `tuidev check`

`tuidev check` runs `scripts/health_check.sh` against the profile in `~/.config/tuidev/profile` (without one: `desktop` on macOS, `minimal` on Linux; a `custom` profile is checked as `minimal`). `tuidev check --profile P` forces one. It prints a line per probe and ends with a summary.

A probe is required or optional. A failed required probe counts toward the exit code; a failed optional one prints a warning and changes nothing.

| Group | What it probes | Required in |
|-------|----------------|-------------|
| Core | every core tool on `PATH`, `compaudit` clean for zsh; optional, never a failure: `secret` and `tuidev` on `PATH`, and a warning for token-looking exports in shell startup files | every profile (on Linux without Homebrew, tools the distro doesn't package are optional) |
| Remote | `tailscale` and `mosh` | `remote` |
| Sandbox (macOS) | `sandbox-exec` runs, the strict profile and `sbx` are in place | `desktop`, `full`, `remote` |
| UI (macOS) | Ghostty, its config and the GUI apps | `desktop`, `full` |
| Extras | the extras tools | never |
| Packs | each pack in `extra_packs`: its own `<pack>_check` if it defines one, else every command and (macOS) app it declares. With `monitoring`: `agents` loads its modules, the SwiftBar plugin and terminal-notifier. With `herdr`: outdated integrations, a server on an older binary, large logs | never |
| Shell, power | `compinit` run more than once per shell; lid sleep disabled with nothing to restore it | never |

**Skipped, already inside a sandbox.** Seatbelt doesn't nest. Run from inside an agent's sandbox, `sandbox-exec` is refused with `sandbox_apply: Operation not permitted`, which says nothing about Seatbelt itself. That one probe prints `skipped, already inside a sandbox` and counts as neither a pass nor a failure. Any other failure of it counts. Run `tuidev check` from your own shell for the full answer.

**Exit codes.** `0`: every required probe passed, warnings or not. `1`: at least one required probe failed (the summary names the count; run the installer for the profile or install the missing tools). `2`: a bad `--profile` value or an unknown argument.

## Hearing about a new release

Once a day, `tuidev latest --if-due` asks `https://github.com/spfr/tuidev/releases/latest` where it redirects to, which is the latest release's tag. It is one request with no body, no API call and no identifier beyond the request itself, and the answer goes into `~/.cache/tuidev/latest`. A check that fails is tried again an hour later, and checks that start together make one request. Nothing starts a timer for this: the menu bar's refresh, a Herdr event, Herdr starting and a run of `agents` each read when the next check is due from that file, and start it only then.

When the release is newer than the one installed:

- the menu bar shows a row for it, with Update now… and What changed (macOS, `--pack monitoring`);
- Herdr shows one toast, and **prefix+u** opens a popup with the installed and the latest version that asks before it updates (`--pack herdr`);
- `agents` ends with one line, and so does `tuidev latest`;
- the palette's first row is the update.

You are told once per release. Nothing is ever updated without you asking. `tuidev latest off` turns the check off for this machine (`tuidev latest on` back on); `tuidev update --check` and `--ask` still ask when you run them. `TUIDEV_UPDATE_CHECK=0` does the same for commands that inherit it, such as a CI job; the menu bar and Herdr don't see your shell's environment, so use `tuidev latest off` for those.

## Upgrading from 2.x

3.0 made tmux and Neovim optional packs, dropped the `cc`/`cx` wrappers for the CLIs' own native sandboxes, and removed the `bosun`, `yazi` and `nnn` packs. Run `tuidev update`; a clone from before 3.23 has no `tuidev` command, so run `git pull && ./scripts/update.sh --configs`. It runs three migrations (they keep tmux and Neovim where you used them, drop the removed packs from `extra_packs`, and remove the `ai-clis.zsh` fragment) and re-applies the configs of every pack your profile records. `./install.sh` alone is not enough: it installs only the packs you name. An unmodified 2.x `~/.claude/settings.json` gets the `sandbox` block; one you edited gets it merged in ([Shipped configs you may have edited](#shipped-configs-you-may-have-edited)). Until then, `claude` runs unsandboxed. Details: the [3.0.0 entry in the CHANGELOG](../CHANGELOG.md).

## The three kinds of change

An update has to handle three different things, and they need different
machinery:

| Change | Handled by | Runs |
|--------|-----------|------|
| A package got a new version | `tuidev update --packages` | every time |
| A repo-owned config changed | `tuidev update --configs` (managed blocks) | every time |
| A past release left an artifact behind | `tuidev update --migrations` | once per machine |

The first two converge *current* state and are safe to repeat forever. The third
cannot be: once a file's source is deleted from the repo, no amount of
re-running the installer will ever notice — let alone remove — the copy sitting
in `$HOME`. That is what migrations are for.

## Migrations

```bash
tuidev update --check       # lists pending migrations, runs nothing
tuidev update --migrations  # runs them
tuidev update --configs     # runs pending migrations first, then configs
tuidev update --all         # tuidev's files first (a pull or the latest release), then packages, migrations and configs; a new release continues with itself
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
  re-applying configs on top would only obscure it. The run says where the
  install stands (in an install made with `get.sh`, `current` already points
  at the new release while the configs are the old one's) and the two ways
  out: fix the cause and run `tuidev update` again, which finishes the
  update, or go back with `tuidev update --rollback`.
- **Fresh installs skip history; upgrades apply it.** On a machine tuidev has
  never touched, `install.sh` marks every existing migration applied without
  running it — a brand-new machine has no legacy state to repair. On a machine
  that already has a tuidev install, re-running the installer (`tuidev install
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
into it: a pack-only run like `tuidev install --pack herdr` adds to
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
tool /Users/NAME/.local/bin/herdr
dir /Users/NAME/.config/nvim
```

The file is line-oriented and greppable on purpose: `grep '^formula ' ~/.config/tuidev/manifest`
is a valid way to use it. It is append-only and deduplicated. Records can go
stale (a formula you later removed by hand), so every consumer re-checks that a
thing exists before acting on it.

**Only what tuidev installed is recorded.** A package that was already present
when a pack ran is skipped, so `tuidev uninstall` won't remove the `ripgrep` you
had before you found this repo.

## Uninstall

```bash
tuidev uninstall --dry-run   # preview
tuidev uninstall             # interactive: asks before each step
tuidev uninstall --all       # yes to every step (keeps the agents history)
tuidev uninstall --purge-history   # also delete the agents history, without asking
```

It removes only what the manifest records:

- managed blocks, including the `tuidev-theme` blocks (content outside the markers stays);
- helpers in `~/.local/bin`, and the `agents` modules in `~/.local/lib/tuidev`;
- global git keys tuidev set, and only while they still hold tuidev's value;
- optionally, the config files tuidev created (each one backed up first). A
  file tuidev adopted is never removed, and neither is a whole CLI home, so auth
  and session state (`~/.claude/…`, `~/.codex/auth.json`) always survive;
- optionally, the Homebrew formulae and casks tuidev installed. apt, dnf and
  pacman packages are listed for you to remove, not removed;
- optionally, in a step of its own, the tools tuidev downloaded: Herdr's
  release binary (`~/.local/bin/herdr`, a `tool` record; installs that
  recorded it as a `file` are treated the same). It stays while a Herdr server
  runs from it, or when uninstall can't tell which binary a running server
  uses: then it prints `rm ~/.local/bin/herdr` for after you have stopped the
  server. Say no and it is kept, with the same command;
- tuidev's state dir, except `backups/`;
- the releases `get.sh` downloaded (`versions/` and `current` in the home the
  uninstall runs from, `~/.local/share/tuidev` unless you set `TUIDEV_HOME`)
  and the update check's cache. A git clone is yours and stays;
- the [agents history](agent-workflows.md#history-and-agents-report) (`~/.local/state/tuidev/agents`, or under `$XDG_STATE_HOME`), only when you say so. In a terminal, uninstall asks and the default is to keep it (no answer is no). `--purge-history` deletes it without asking; `--all` keeps it and never asks. It never asks when stdin isn't a terminal. Only that one directory goes, only inside `$HOME`, and never through a symlink. `--dry-run` shows the removal.

An install that predates the manifest gets only the safe subset: managed blocks,
and helpers still byte-identical to the repo copy. Everything else is listed for
you to review.

## Everything else `update.sh` does

```bash
tuidev update --check          # preview: packages, migrations, drift, repo, performance
tuidev update --packages       # upgrade the packages of your active packs only
tuidev update --configs        # migrations, then re-apply managed blocks + pack configs
tuidev update --all            # non-interactive: repo first, then packages + configs
tuidev update --security       # audit Tailscale, SSH permissions, Seatbelt profile drift
tuidev perf                    # performance audit: Spotlight, Time Machine, limits, git
tuidev perf --fix              # the same, then offer each fix that needs no root
```

`tuidev update --check` and `tuidev update --all` end with the performance report, so a package store that crept back into the Spotlight index or a new backup disk shows up the next time you update. It only reports there; `tuidev perf --fix` (or `tuidev update --perf`) applies. What it checks and why is in [performance.md](performance.md#let-tuidev-check).

`tuidev update` with any of `update.sh`'s flags runs that mode. In a clone, a bare `./scripts/update.sh` gives an interactive menu with the same actions.
Every mode honors `--dry-run`. `update.sh` runs under macOS's stock bash 3.2.

### Packages on Linux

`--packages` uses the same manager the installer did: Homebrew when it is on
`PATH`, otherwise `apt-get`, `dnf` or `pacman`. With a native manager it checks
the pack packages installed through that manager, whoever installed them (as
with Homebrew). A tool you put there another way, or one the distribution
doesn't ship, is left alone, and Debian's unrelated `yq` is never counted.
Outdated packages from every pack are upgraded in one batch
(`apt-get install --only-upgrade` or `dnf upgrade`), so nothing new is ever
installed by an update, and apt keeps each package's auto/manual mark. A probe
that fails is reported as "status unknown", never as up to date.

It never asks for a sudo password. As root or with passwordless sudo it
refreshes the apt lists first and upgrades. Otherwise it reports from the
cached lists and prints the commands to run yourself:

```bash
sudo apt-get update
sudo apt-get install --only-upgrade -y tmux vim
```

pacman is checked against the local sync database, and the fix is always
`sudo pacman -Syu`: Arch doesn't support upgrading a subset of packages, so
tuidev prints that command instead of upgrading them one by one, and never
runs a bare `pacman -Sy`.

### Node (fnm)

Homebrew upgrades fnm itself, never the Node versions it installed, so a Node
security release used to reach them only by hand. Whenever fnm is installed,
`--packages` lists Node releases from nodejs.org and, for each major you have,
installs its latest patch when yours is behind (after asking). It then offers
to move fnm's `default` to the newest patch of the default's major. It never
installs a major you don't have, never changes the default's major, and never
removes a version: an older patch a project pins exactly
(`.nvmrc: 24.16.0`) keeps working. `--check` lists the patches newer ones
have replaced, for `fnm uninstall VERSION` once no project pins them. When
nodejs.org can't be reached, the group is "status unknown".

### uv and its Pythons

Homebrew's uv is an extras formula and upgrades with them. uv from Astral's
standalone installer (it leaves `~/.config/uv/uv-receipt.json`) isn't
Homebrew's to upgrade, so `--packages` runs `uv self update` for it, which
checks the download against the release's sha256. uv knows only the Python
builds that existed at its own release, so the order matters: uv first, then
`uv python upgrade`, which moves each installed minor (3.12, 3.14, …) to its
latest patch and repoints the minor's directory, so venvs built on it follow.
It never installs a minor you don't have. `--check` lists what the installed
uv knows to be behind; a newer uv may know more. If GitHub rate-limits the
check, set `UV_GITHUB_TOKEN`.

### Herdr

The herdr pack installs Herdr's release binary, not Homebrew's, because only
that one can update itself. With the pack active, `--packages` (after asking)
runs `~/.local/bin/herdr update` with stdin closed, outside any Herdr pane:

- with a server running, `herdr update --handoff`, which moves the server's
  panes onto the new binary while their processes keep running;
- without one, plain `herdr update`;
- when a LaunchAgent supervises the server in a way a handoff would upset,
  plain `herdr update` and the change to make (see
  [agent-workflows.md](agent-workflows.md#fleet-attention--herdr---pack-herdr)).

It never stops a server: with stdin closed, Herdr answers each "stop the old
server?" prompt no. A server it couldn't hand over keeps running and picks up
the new binary at its next start; a release that needs a server restart is
then not installed at all, and Herdr says so.

On Linux, when a systemd user unit runs a server (`herdr.service`,
`herdr-session@NAME.service`, or any unit a running server sits in),
`herdr update --handoff` never runs: systemd would stop the new server and
its panes, or lose track of it. Instead `--packages`:

1. installs the new release binary itself, checked against the release's
   sha256 and renamed into place, when `~/.local/bin/herdr` isn't it
   (`TUIDEV_HERDR_VERSION` pins one);
2. runs `systemctl --user reload UNIT` (300 s at most) for each unit whose
   `ExecReload` runs a `herdr-handoff` wrapper and which has
   `NotifyAccess=exec` (or `all`), once its server is on an older binary. Exit 0 means the
   panes are on the new server and systemd follows it; a failure is a warning
   with the `journalctl --user -u UNIT` to read, and the old server keeps
   running;
3. skips every other unit with a hint: it keeps the old binary until its
   next start.

The unit pattern is in
[agent-workflows.md](agent-workflows.md#fleet-attention--herdr---pack-herdr)
(practice 5, and the unit example under Sessions and devices).

A Homebrew herdr is switched instead (after asking): `--packages` installs the
release binary in its place, as the `202610161843_herdr_direct_install`
migration does, and prints what is left by hand. A failed download is retried
on the next `--packages`, or by `tuidev install --pack herdr`.

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
  `diff <yours> <shipped>` command so you can merge by hand. The exception is
  `~/.claude/settings.json`, below.

`~/.claude/settings.json` is edited by nearly everyone (plugins, `statusLine`,
`/config`), so an edited copy is merged instead of kept as it is
(`--upgrade-shipped --merge-json`). tuidev stores the version it last applied
as `~/.config/tuidev/shipped/settings.json`, and each update does a three-way
merge of that base, your file and the new shipped file:

- a value you never changed follows the shipped one, including a key tuidev
  removed;
- a value you changed or deleted stays yours;
- lists (`permissions.allow`, `sandbox.excludedCommands`, hooks) keep your
  entries in your order, lose the entries tuidev removed (even one you had
  added yourself before), and gain the new ones at the end. List elements
  are compared whole, so a shipped hook group you edited stays as your copy,
  and the new shipped version is added next to it;
- where you and tuidev both changed the same value, yours wins and the run
  names the path, with the `diff` command;
- before a write, the old file is backed up to `~/.config/tuidev/backups/`
  (a real copy, even when the file is a symlink into your dotfiles; the
  write goes through the link). If nothing would change, the file isn't
  touched.

The first update after an install that predates this has no stored base, so
it only adds: new keys and new list entries arrive, and none of your values
change or go. That also means a shipped key or list entry you had deleted
comes back, because without a base tuidev can't tell a deletion from a
missing addition. Preview it first with
`tuidev install --pack ai-clis --dry-run`, which lists the paths that would
change and writes nothing (`tuidev update --dry-run` doesn't show this
preview). From then on the base is there, and a deletion sticks.

A file that isn't valid JSON (say, one with comments), or a machine without
`jq`, gets the old behavior: kept, with a warning and the `diff` command. jq
rewrites the whole file when it merges, with 2-space indentation; jq 1.6 may
also normalize number literals (1.7 and later keep them). So personal
additions such as an extra `sandbox.excludedCommands` entry (`"git *"`)
belong in `~/.claude/settings.json` itself, and they survive updates unless
a release removes that same entry. `~/.codex/config.toml` is TOML and is not
merged.

`tuidev update --configs` re-runs the packs, so this happens on every update.
Files you added (say, `~/.config/nvim/lua/plugins/mine.lua`) are never
touched. After a Neovim upgrade, `:Lazy sync` installs and cleans plugins.

`tuidev update --configs` also applies new **git defaults** (`scripts/lib/gitconfig.sh`)
to keys you have not set, `[include]`d files included.
`tuidev update --security` also shows how your profiles differ from the shipped
ones (see [sandboxing.md](sandboxing.md#customizing)).
