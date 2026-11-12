# Performance: What the OS Does Behind Your Agents

Agents change what a dev machine does all day. Worktrees are created and deleted by the dozen, dependency trees are installed into each one, and thousands of freshly built binaries run once. The operating system's background services were tuned for a person editing documents: they index, back up, scan and watch every one of those files.

This page lists what is worth changing on macOS and Linux, in order of effect, with the command, its cost and how to undo it. Each claim says where it comes from: **measured** (on an M4 Pro MacBook, macOS 27.2, November 2026), **sourced** (linked), or **unverified**. tuidev checks all of it for you and applies the few fixes that are safe to automate: [let tuidev check](#let-tuidev-check).

## Let tuidev check

```bash
make perf          # the audit; changes nothing
make perf-fix      # the audit, then each fix that needs no root, one question at a time
```

```text
✓ Background daemons, share of one core since boot (3 h 23 m): Spotlight 5.8%, syspolicyd 1.9%, fseventsd 1.7%
    how: ps -Ao time,comm (CPU time since boot) over sysctl -n kern.boottime: warns from 15% of one core, judged after the first hour
⚠ Time Machine backs up ~/go/pkg/mod
    how: tmutil destinationinfo, then tmutil isexcluded for each package store: wants them excluded
    fix (--fix does this): tmutil addexclusion ~/go/pkg/mod
    undo: tmutil removeexclusion ~/go/pkg/mod
⚠ Spotlight indexes 270240 files in ~/Library/pnpm/store/v11, a package store no one searches
    fix: System Settings > Spotlight > Search Privacy > + > ~/Library/pnpm/store/v11   (macOS has no command for this list)
    undo: System Settings > Spotlight > Search Privacy > select it > -
ℹ 2 to change, 1 of them by './scripts/perf.sh --fix'. Why: docs/performance.md
```

Every line says how it was measured (the command, and the threshold it is compared against), so the report has numbers even when everything is right; every fix has its undo. `--fix` prints the whole plan before it asks anything, asks once per fix with No as the default, does nothing without a terminal unless you add `--yes`, and logs each change with its undo in `~/.config/tuidev/disk.log` (`--dry-run` prints the commands and log lines instead).

The same report closes every install, `make update-check` and `make update-all` (there without the `how:` lines and without what is fine), so the machine is checked again whenever you update: a new package manager's store, a backup disk you added, a limit a reinstall reset.

| It checks | It fixes | Otherwise | How to undo |
|-----------|----------|-----------|-------------|
| Package stores and repo folders in the Spotlight index (it asks Spotlight how many files it holds under each) | | Names the folder to add in System Settings | Search Privacy: select it, then − |
| Package stores in Time Machine backups, when a backup disk is set up | `tmutil addexclusion` | | `tmutil removeexclusion PATH` |
| `core.untrackedCache`, and a global `core.fsmonitor` | Sets the first, recorded for uninstall | Prints the command for the second | `git config --global --unset core.untrackedCache` |
| The open-files limit in your shell | The shipped `.zshrc` raises it | Points at `update.sh --configs` | Delete the `ulimit` line |
| Low Power Mode on the charger; repos in iCloud-synced folders; a store on another volume | | Says what to change | The same setting, back |
| Linux: inotify limits, swap, `updatedb` | | Prints the drop-in or the line, for you to run with `sudo` | `sudo rm /etc/sysctl.d/zz-tuidev-inotify.conf && sudo sysctl --system` |
| Measured, macOS: CPU since boot of `mds`, `mds_stores`, `mdworker*`, `fseventsd`, `syspolicyd`, `XprotectService`, `logd` and endpoint agents (`ps -Ao time,comm` over `kern.boottime`); memory pressure and swap (`sysctl`); local Time Machine snapshots | | Warns from 15% of one core averaged since boot (after the first hour), on pressure `warn` or `critical`; notes swap past a quarter of RAM | Nothing to undo: it only reads |
| Measured, both: free space on your home's volume (`df -Pk`); a corporate endpoint agent (CrowdStrike, Sophos, SentinelOne, Jamf Protect, Defender) | | Warns below 10% free and points at `make disk`; for an endpoint agent, ask IT for exclusions, never turn it off | Nothing to undo |
| Measured, Linux: load over 5 minutes against cores, swap in use, a `/tmp` in RAM (tmpfs) | | Warns when load exceeds the cores | Nothing to undo |

The 15% threshold: on the test Mac, busy with agents, Spotlight averaged about 4% of one core. Averaged over the whole uptime, 15% means a service spent a seventh of every hour flat out: an index rebuild, a package store churning inside the index, or a scanner chasing every file a build writes. A sandbox that denies `ps` or `sysctl` makes those checks say nothing rather than guess.

It finds your package stores by asking pnpm, Go, uv and npm, and looks for repos in the usual folders (`~/workspace`, `~/code`, `~/src`, `~/dev`, `~/Developer`, `~/projects`, `~/repos`, `~/work`). Name others in `TUIDEV_PERF_DIRS`, colon-separated. It never runs `sudo`, and it never edits Spotlight's own files: [why](#1-spotlight).

## Disk

```bash
make disk          # what dev tools and agents left on disk, with the command for each; deletes nothing
make disk-fix      # the same, then the plan, then one question per tool cleanup command
./scripts/disk.sh --json          # one JSON object, for an agent you ask to plan a cleanup
./scripts/disk.sh --explain ID    # one item in full (the IDs are in --json)
./scripts/disk.sh --quick         # leave out the repos in your code folders
./scripts/disk.sh --min 1G        # hide what is smaller (default 100 MB)
./scripts/disk.sh --verbose       # also say which places are not there
```

It is not a Mac cleaner. It looks only at what dev tools and agents leave behind, in places it names as it goes (on stderr, so `--json` stays clean): the Go build and module caches, the npm, pnpm, bun, uv and pip caches, Homebrew's downloads, the Cargo registry, Gradle's caches, Playwright's and Cypress's browsers, CocoaPods, Xcode's DerivedData, iOS DeviceSupport and simulators, Podman, Docker and Apple `container` storage, Node versions fnm installed and Pythons uv installed that a newer patch has superseded, Claude Code transcripts and Codex sessions, tuidev's own backups, and in each git repo in your code folders (to a depth of 4, `TUIDEV_DISK_DEPTH`) the untracked `node_modules`, `target`, `.next`, `.turbo`, `dist` and `.venv` at its root and its linked worktrees. Each is sized with one `du -sk`, eight at a time. On the test Mac a full run took 15 to 40 seconds depending on what else was running, and `--quick` about 8. It never walks the home folder, and never looks at app data, browser or system caches, Downloads or Trash. A code folder reached twice (a symlink, or `~/projects` and `~/Projects` on a case-insensitive disk) is scanned once.

Every item says what it is, why it got its verdict (who owns it, when it was last written, whether anything uses it now), what reclaiming it costs you, and the exact command:

```text
regenerable: caches a tool rebuilds; safe to clear   35 GB in all
     6.7 GB  pnpm store   ~/Library/pnpm/store
             what: Every package your projects' node_modules link to; prune removes only what no project uses, so it frees less than this.
             why:  a cache pnpm owns and rebuilds; written to in the last day
             cost: little: only packages no project links to go; an install fetches them again if needed
             run (--fix offers this): pnpm store prune

stale: superseded or unused; safe after a look   4.5 GB in all
     433 MB  Node v24.22.1 (fnm)   ~/.local/share/fnm/node-versions/v24.22.1
             what: Node.js v24.22.1, installed by fnm, with global npm packages: @openai/codex.
             why:  superseded by v24.22.3, the same major, and not fnm's default (v26.13.1); --fix skips it now: global npm packages installed with it would go too: @openai/codex
             cost: the version and every global npm package installed with it (@openai/codex); a project pinned to exactly v24.22.1 needs 'fnm install 24.22.1' again
             run (--fix skips it now): fnm uninstall v24.22.1
```

| Verdict | Means | `--fix` |
|---------|-------|---------|
| `regenerable` | A cache a tool rebuilds. Safe to clear. | Offers the tool's own command for the caches in [What `--fix` runs](#what---fix-runs). The Go module cache and Homebrew's downloads are report-only: the first also holds downloaded Go toolchains and private modules that may need credentials to fetch again; `brew cleanup` also removes old versions from Homebrew's prefix, outside your home. |
| `stale` | Superseded or unused: a Node or Python patch with a newer one beside it, a merged or idle worktree, build output of a repo untouched for 30 days (`TUIDEV_DISK_STALE_DAYS`), a cache whose tool is gone, more than 1,000 fnm links of shells that have ended. Safe after a look. | Offers `fnm uninstall` and `uv python uninstall` when the checks below pass; everything else, worktrees included, is report-only |
| `managed` | Another tool owns the cleanup: Podman, Docker, Apple `container`, simulators. | Never; it prints that tool's command |
| `yours` | Transcripts, tuidev's backups, a worktree that holds work, a folder with its own `.git`. Listed from 1 GB, as information. | Never |

Build output in a repo changed within the stale window is only counted ("In use: 26 GB ... in 16 repos"), never listed. `du` counts a hardlinked or cloned file in full, so deleting a `node_modules` that pnpm or bun linked from their store frees less than its size.

**Worktrees are report-only.** A merged or idle worktree is `stale` only when removing it loses nothing: no changes, no untracked file (whatever `status.showUntrackedFiles` says), nothing ignored except build folders, and, when detached, a commit some branch, tag or remote contains. Anything else makes it `yours`. Ignored entries come from `git status -z --ignored=matching`, which shows an ignored folder as one entry; one counts as build output only when its own last path component is `node_modules`, `target`, `.venv`, `dist`, `.next`, `.turbo`, `__pycache__`, `.pytest_cache` or `coverage` (compared literally: `old dist/` is not, nor is a folder named `*`), or when it lies inside such a folder. Everything inside those build folders goes with the worktree, unlooked at. The command it prints for you, `git -c status.showUntrackedFiles=all -C REPO worktree remove PATH`, makes git itself refuse a worktree with untracked files; `--fix` never runs it.

**What a read touches.** Nothing under your home is written while it looks. It runs no tool that writes when asked: not `go` (`go env` updates its telemetry counters; the caches come from `GOCACHE`, `GOMODCACHE`, `GOPATH`, go's env file and its defaults), not `pnpm` (`pnpm store path` writes under its home; the store comes from `npm_config_store_dir`, `store-dir` in pnpm's rc file, read as text for that one key, then `PNPM_HOME`, `XDG_DATA_HOME` and pnpm's default; `~/.npmrc` holds registry tokens and is never read, so when it exists and `npm_config_store_dir` is unset, `pnpm store prune` is shown but not offered), and not `fnm` (`fnm ls` creates its aliases folder when it is missing; the versions are the `node-versions` folder's entries and the default is the `aliases/default` link). `npm` runs with its debug log off (`npm_config_logs_max=0`), `uv` lists Pythons with `--no-cache`, and `git` runs with `--no-optional-locks` and `core.fsmonitor=false`, so `git status` neither rewrites an index nor starts a daemon. Tested against a throwaway home: every path and modification time is the same after a scan. What it does still run: `uv cache dir`, `uv python dir`, `uv tool dir`, `pip3 cache dir`, `brew --cache`, `podman system df`, `docker system df`, `readlink` on fnm's links of running shells, and `git log`, `ls-files`, `worktree list`, `status`, `for-each-ref` and `merge-base` in your repos; it reads the process table once (`ps`).

**For an agent.** `--json` prints `{generated_at, free_bytes, total_bytes, items: [{id, label, path, bytes, verdict, what, why, cost, evidence, reclaim, safe, fix_offered, fix_reason}], reclaimable_bytes, in_use: {bytes, repos}}`. `evidence` repeats `why`. `safe` is true for `regenerable` only. `fix_offered` is the same decision `--fix` makes at that moment (false when the process table could not be read), and `fix_reason` says why not. Ask the agent to read it and propose; the commands are for you to run, or for `--fix`.

### What `--fix` runs

Only these, each a tool's own command, each asked for on its own:

| Item | Command |
|------|---------|
| Go build cache | `go clean -cache` |
| npm cache | `npm cache clean --force` |
| pnpm store | `pnpm store prune`, only when the store it found exists and no file that could name another store is unreadable |
| bun cache | `bun pm cache rm` |
| uv cache | `uv cache prune` |
| pip cache | `pip3 cache purge` |
| CocoaPods cache | `pod cache clean --all` |
| A superseded Node version with no global npm packages | `fnm uninstall VERSION` |
| A superseded Python no venv uses | `uv python uninstall KEY` |

**How `--fix` works.** It reads the process table again, then prints the plan: every command it would run, the size of each and the total, and every item it will not offer now, with the reason. Then it asks once per command; only `y` or `yes` and Enter is yes, and anything typed while it scanned is thrown away first. Without a terminal it stops after the plan unless you add `--yes`. After each yes it looks again, with a fresh process table, and works out a runtime's block again from the disk (a global package installed, a venv made since the plan); anything that changed skips that item. Each command runs on its own: a failure stops that item, shows the command's output and is logged, and nothing bigger is tried instead. Each item is measured again afterwards, and the run ends with what ran, what was skipped and why, and the bytes actually freed. Every command run is a tab-separated line in `~/.config/tuidev/disk.log`: time, source, item, command, exit code, bytes before, bytes after, undo. `--dry-run` prints the plan, the commands and the log lines and runs nothing.

**When `--fix` holds back.**

| Item | Not offered while |
|------|-------------------|
| A tool's cache | That tool runs (`go`, `gopls`, `npm`, `pnpm`, `bun`, `uv`, `pip`, `pod`), or anything in it was written in the last two minutes |
| A Node version | It has global npm packages besides npm and corepack (they are named; `fnm uninstall` deletes them), a running process was started from it, or a running shell's fnm link points at it (fnm makes one link per shell, named after its PID; only the links of running shells are read) |
| A Python | A venv points at it (`pyvenv.cfg` in the code folders to depth 7, uv tools, pipx, `~/.virtualenvs`, poetry, hatch), a running process was started from it, or `--quick` skipped the venv search. A venv elsewhere is not seen, and the cost line says so |
| Anything | `ps` cannot be read; the path is gone, a symlink, outside your home, your home, `/`, or a repo root |

**What it will never do.**

- Run `rm`. Only a tool's own command from the table above; everything else is report-only, and the `rm` it prints is for you to run after a look. A folder under `.claude/worktrees` that has a `.git` of its own is never given an `rm` line.
- Remove a worktree, or run `brew`.
- Touch anything `yours` or `managed`.
- Change anything outside your home.
- Run anything without asking, or without a terminal unless you passed `--yes`.
- Remove fnm's default Node, the newest patch of any Node major or Python minor, or a Node version with global packages.

**How to undo.** A cache comes back the next time its tool needs it (a build, an install). A Node version: `fnm install VERSION`. A Python: `uv python install KEY`. For what you remove by hand from the report: a worktree on a branch comes back with `git worktree add PATH BRANCH`, since the branch stays in the repo; a detached worktree is `stale` only when a branch, tag or remote contains its commit, so `git worktree add --detach PATH COMMIT` brings it back.

## First, look

Don't tune what isn't slow. Three commands say whether the OS is competing with your agents:

```bash
agents                     # hogs: a system service at the top is named as one
agents mem                 # who holds the memory, by real footprint
ps -Ao time,comm | sort -r | head -20     # CPU time since boot: mds, mds_stores, fseventsd, syspolicyd, XprotectService
```

On the test Mac, 77 minutes after boot with agents running, Spotlight (`mds`, `mds_stores`) had used about 3 minutes of CPU, `fseventsd` 1 minute and `syspolicyd` 40 seconds. That is small, and on Apple Silicon Spotlight runs on the efficiency cores at low priority ([Eclectic Light](https://eclecticlight.co/2026/02/10/in-the-background-spotlight-indexing/)). It stops being small when an index is being rebuilt, when a package store of hundreds of thousands of files is inside it, or when a corporate security agent scans every file a build writes.

## macOS

| # | What | Effect | Verdict |
|---|------|--------|---------|
| 1 | [Package stores in the Spotlight index](#1-spotlight) | Hundreds of thousands of files indexed for nothing | **Do it** |
| 2 | [XProtect scans of fresh binaries](#2-xprotect-and-freshly-built-binaries) | Up to 2.7× on suites that run many binaries | **Opt in**; a security trade |
| 3 | [Low Power Mode](#3-low-power-mode) | About half the CPU throughput | **Check it** |
| 4 | [Repos in iCloud-synced folders](#4-icloud-drive) | Sync daemons fight git | **Don't** |
| 5 | [Time Machine and build trees](#5-time-machine) | Backups of `node_modules` and `target` | **Do it** if you back up |
| 6 | [Copy-on-write installs](#6-clones-not-copies) | A dependency tree per worktree for almost no disk or time | **Keep the defaults** |
| 7 | [Git for many worktrees](#7-git) | Faster `status`; no stray daemons | **Do it** |
| 8 | [File descriptor limit](#8-file-descriptors) | `EMFILE` in watchers and test runners | **Do it** |
| 9 | [Corporate endpoint security](#9-endpoint-security-agents) | Builds several times slower | Ask IT |

### 1. Spotlight

**What we found (measured).** Of 636,000 files in the home folder's Spotlight index, 489,000 (77%) were package caches no one searches: 270,000 in pnpm's store (`~/Library/pnpm/store`) and 219,000 in Go's module cache (`~/go/pkg/mod`). Nothing under a dot-directory (`~/.npm`, `~/.cargo`, `~/.cache`, `~/.claude`) or `~/Library/Caches` came back from a search.

**What controls it (sourced).**

| Method | Works? | Notes |
|--------|--------|-------|
| System Settings › Spotlight › Search Privacy | Yes | The supported way. There is no supported command for it: `mdutil` has no exclusion verb. |
| A directory name ending in `.noindex` | Yes | No sudo; undo by renaming. [Eclectic Light, Jan 2026](https://eclecticlight.co/2026/01/06/exclude-or-include-items-in-backup-search-icloud-drive-and-quicklook-preview/) |
| A dot-prefixed directory | Hidden from search | Whether its contents still cost indexing time is disputed; don't count on it for CPU. |
| `.metadata_never_index` file | **No** | Stopped working in recent macOS ([Eclectic Light, 2025](https://eclecticlight.co/2025/06/16/spotlight-search-can-be-blocked-by-extended-attributes/)). Tools built on it no longer help. |
| `sudo mdutil -i off /Volumes/NAME` | Yes, per volume | Suits a separate APFS volume for code. Clones can't cross volumes, so the package stores must move there too. |
| Editing `VolumeConfiguration.plist` with PlistBuddy | Unsupported | Needs root, and sources disagree on whether `mds` reads it before a reboot. Not something to script. |

**So can a command line manage it?** Reading, yes; writing, no. `mdfind -onlyin DIR -count …` says how many files Spotlight holds under a folder, without root, and that is what `make perf` runs on every update: an exclusion that works reads as zero. Adding to the list has one supported route, the Settings window. tuidev stops there on purpose. The plist edit writes as root into a file `mds` owns, and no source shows it taking effect on macOS 26 or 27 without a reboot.

**What to do.**

1. Add your package stores to Search Privacy: `~/Library/pnpm`, `~/go`, and any other store outside a dot-directory. Find yours with `pnpm store path`, `go env GOMODCACHE`, `bun pm cache`, `uv cache dir`.
2. Add the folder that holds your repos, if you never search code with Spotlight. `rg` and `fd` do not use it.
3. Where a tool lets you name the directory, end it in `.noindex`.

Claude Code's worktrees live under `.claude/worktrees/`, a dot-directory, so they stay out of search results either way; excluding the repos folder (step 2) settles the indexing question for them too.

**Cost.** Finder search, `mdfind` and launchers such as Alfred and Raycast stop finding files in what you exclude. Leave indexing on for the volume as a whole: Mail search, app launching and Time Machine rely on it.

### 2. XProtect and freshly built binaries

**What happens (sourced).** The first time a binary runs, macOS checks it: an XProtect scan and a notarization lookup, in a single-threaded service. A compiler's test suite or a Rust workspace runs thousands of binaries exactly once. Measured by a rustc maintainer: one test suite went from 9m42s to 3m33s, and build scripts from 0.5–3.9 s each to about 0.1 s, with the check off ([Nethercote, 2025](https://nnethercote.github.io/2025/09/04/faster-rust-builds-on-mac.html)). Go builds gain 3–11% ([dreadl0ck](https://dreadl0ck.net/posts/faster-builds-on-mac/)).

**The switch.**

```bash
sudo spctl developer-mode enable-terminal
# then: System Settings › Privacy & Security › Developer Tools › turn on Ghostty (and tmux, if you use it)
# restart the terminal. Undo: turn it off there.
```

Still present on macOS 27.2 (measured: `spctl` lists it). Each terminal app is granted separately ([cargo-nextest's notes](https://nexte.st/docs/installation/macos/)).

**Cost.** Nothing started from that terminal is scanned for malware. On a machine whose point is to run code an agent just wrote or just installed, that is a real trade, and it is why this is opt-in. If you take it, keep the sandbox and [`release-age`](sandboxing.md#minimum-release-age) on.

**Caveat.** A report against Claude Code on macOS 27 says commands from its Bash tool lose the exemption and are scanned anyway ([anthropics/claude-code#104173](https://github.com/anthropics/claude-code/issues/104173), open). Check before you rely on it: time a build from the terminal and the same build from an agent.

### 3. Low Power Mode

About half the CPU throughput on an M4 Pro ([Eclectic Light](https://eclecticlight.co/2025/01/22/m4-pro-full-on-when-cpu-and-gpu-draw-over-50-w-and-how-low-power-mode-changes-that/)). `pmset -g | grep powermode` prints `0` when it is off; the menu's system row and `agents` show the energy mode too. It is easy to leave on after a flight. On battery it is a fair trade; on the charger it is not.

### 4. iCloud Drive

Keep repos out of Desktop and Documents when "Desktop & Documents Folders" sync is on. Git writes many small files quickly, and the sync daemons (`bird`, `fileproviderd`) try to upload each one; reports of pinned CPUs and reverted files are anecdotal but common. A folder name ending in `.nosync` is not synced.

### 5. Time Machine

```bash
tmutil addexclusion ~/Library/pnpm ~/go/pkg         # sticky: an attribute on the folder, no sudo, follows a move
sudo tmutil addexclusion -p ~/code/myrepo/node_modules   # by path: survives the folder being deleted and recreated
tmutil isexcluded PATH                              # check
tmutil removeexclusion [-p] PATH                    # undo
```

A sticky exclusion disappears with the folder, which suits a store and does not suit a `node_modules` that is deleted and reinstalled; use `-p` on a stable parent for those. [asimov](https://github.com/stevegrunwell/asimov) applies exclusions to dependency folders on a schedule. Local snapshots are of the whole volume and kept about a day, so deleted build output keeps its disk space until the snapshot expires, exclusions or not.

### 6. Clones, not copies

APFS can clone a file: a second name for the same blocks, copied only when one side changes. pnpm (`auto`), uv (`link-mode = "clone"`) and bun all install this way on macOS by default (their docs: [pnpm](https://pnpm.io/settings/node-modules), [uv](https://docs.astral.sh/uv/reference/settings/), [bun](https://bun.com/docs/pm/global-cache)), so a full dependency tree in every worktree costs little time and almost no disk.

Two things undo it:

- **A store on another volume.** Clones cannot cross volumes; the installer silently falls back to a full copy.
- **npm.** It copies. In a repo with many worktrees, pnpm or bun is the difference between seconds and minutes per worktree.

By hand, `cp -c` clones. Cargo neither links nor clones: share build output across worktrees with `CARGO_TARGET_DIR` or sccache, and note that a shared target directory makes builds wait on one lock.

### 7. Git

```bash
git config --global core.untrackedCache true     # about 2× faster status on a large tree; a tuidev git default
git config --global feature.manyFiles true       # index v4, skipHash and untrackedCache, for big repos
```

Leave `core.fsmonitor` off for repos you create worktrees in. It starts one daemon per working directory, each linked worktree gets its own, and they outlive the worktree. If you want it in one large repo, set it there, not globally. Remove worktrees with `git worktree remove`, not `rm -rf`; `git worktree prune` cleans up after the second. `git maintenance start` keeps a large repo's object store and commit graph fresh in the background.

### 8. File descriptors

macOS starts every process with a soft limit of 256 open files (measured: `launchctl limit maxfiles`). Node raises its own; a file watcher, a Python test runner or a database started from your shell may not, and fails with `EMFILE` or "too many open files" once enough agents run. Raise it where the shell starts:

```bash
ulimit -n 65536
```

The shipped `.zshrc` does this for you (only ever upward, and only when the limit is a number below 65,536), and everything started from that shell inherits it.

Don't use the old `launchctl limit maxfiles` LaunchDaemon recipe: System Integrity Protection refuses it on current macOS, and Apple's advice is the shell profile ([developer forums](https://developer.apple.com/forums/thread/735798)).

### 9. Endpoint security agents

If your Mac runs a corporate endpoint agent, look at its CPU during a build. Reports put CrowdStrike Falcon near 300% CPU under Xcode builds and Sophos at up to 10× slower builds. It is not yours to turn off; ask IT for exclusions on the repos folder and the package stores.

### What has no knob

- **`fseventsd`** has no tuning. Fewer watchers is the only lever: stop dev servers and watch-mode tests in worktrees no one is looking at (`agents` flags them as `long` or `dup`).
- **Container bind mounts.** A `node_modules` on a bind mount from macOS into a Linux container is far slower than one in a named volume.

## Linux

Most of this is for the box that stays on. Every `/etc` change needs root; undo is deleting the file and running `sudo sysctl --system` or `systemctl daemon-reload`.

| # | What | Verdict |
|---|------|---------|
| 1 | [inotify limits](#1-inotify) | **Do it** |
| 2 | [A memory cap per agent](#2-a-memory-cap-per-agent) | **Do it**, above all on a small box |
| 3 | [Swap present](#3-swap) | **Check it** |
| 4 | [Stores and worktrees on one filesystem](#4-links-and-reflinks) | **Do it** |
| 5 | [Git](#5-git) | **Do it** |
| 6 | [Desktop indexers and `locate`](#6-indexers) | **Do it** on a desktop |
| 7 | [Background maintenance](#7-background-maintenance) | **Do it** |
| 8 | [File descriptors](#8-file-descriptors-1), [mount options](#9-disks-on-a-small-box) | Opt in |

### 1. inotify

Every watcher (a dev server, tsserver, a test runner in watch mode) takes inotify instances and watches from one per-user budget. The defaults are 128 instances and a watch count scaled to RAM (8,192 to 1,048,576, [kernel source](https://github.com/torvalds/linux/blob/master/fs/notify/inotify/inotify_user.c)). Several agents in several worktrees hit the 128 instances first; the symptom is `ENOSPC` or a watcher that falls back to polling, which burns CPU.

```ini
# /etc/sysctl.d/zz-tuidev-inotify.conf
fs.inotify.max_user_instances = 1024
fs.inotify.max_user_watches = 524288     # 262144 on an 8 GB machine
```

`sudo sysctl --system` applies it. A watch costs about 1 kB of kernel memory when in use ([VS Code](https://code.visualstudio.com/docs/setup/linux)), so the full 524,288 is at most about 540 MB.

### 2. A memory cap per agent

On a desktop distro, `systemd-oomd` kills a whole cgroup under memory pressure. A runaway test in one agent can take the tmux server, and every other agent, with it. Give each agent its own scope with its own limit, and the kernel stops the runaway inside it:

```bash
systemd-run --user --scope -p MemoryHigh=6G -p MemoryMax=8G -- claude
```

`MemoryHigh` throttles first and `MemoryMax` is the last resort ([systemd.resource-control](https://www.freedesktop.org/software/systemd/man/latest/systemd.resource-control.html)). No root, and nothing to undo. `-p CPUWeight=50` in the same command keeps a background agent from starving your shell. `agents mem guard` covers the same case from the outside, on any Linux.

### 3. Swap

An OOM kill with no swap is abrupt, and `systemd-oomd` wants swap to work well. Raspberry Pi OS (trixie) and Fedora ship compressed swap in RAM (zram) by default; a Debian or Ubuntu server may have none. Check with `swapon --show`. With zram, a `vm.swappiness` above the default 60 is reasonable ([kernel docs](https://www.kernel.org/doc/html/latest/admin-guide/sysctl/vm.html)); without it, leave it.

### 4. Links and reflinks

On Linux, pnpm and bun hardlink from their store, and uv clones or links; all fall back to a full copy across filesystems. Keep the stores and the worktrees on one filesystem. On btrfs or xfs, `cp --reflink=auto` (cp's default) clones. Debian 13 mounts `/tmp` as tmpfs, up to half the RAM: a build that writes there is using memory, and a worktree there cannot link to a store on disk.

### 5. Git

As on macOS: `core.untrackedCache true`, and `feature.manyFiles true` for big repos. The built-in fsmonitor daemon reached Linux in Git 2.55 and draws on the inotify budget above, once per worktree; leave it off for short-lived worktrees. `git maintenance start` installs systemd user timers.

### 6. Indexers

- **GNOME (LocalSearch, formerly Tracker)** indexes your XDG folders and already skips any directory that contains `.git`. If your repos sit in `~/Documents`: `touch DIR/.trackerignore`, or `gsettings set org.freedesktop.Tracker3.Miner.Files ignored-directories "['node_modules','target']"`, then `localsearch reset --filesystem`.
- **KDE (Baloo)** already skips `node_modules`, `.git`, `.venv` and `__pycache__`, but not `target`. `balooctl6 config` edits the list; `balooctl6 disable` turns it off.
- **`plocate`**: Debian ships `PRUNENAMES` commented out, so the nightly `updatedb` walks every `node_modules`. In `/etc/updatedb.conf`: `PRUNENAMES=".git node_modules target .venv"`.

### 7. Background maintenance

| Job | Change | Cost |
|-----|--------|------|
| journald (default: up to 10% of the disk, 4 GB) | `SystemMaxUse=200M` in `/etc/systemd/journald.conf.d/size.conf` | Shorter log history |
| `man-db` rebuild after every `apt` install (can take minutes) | `echo "set man-db/auto-update false" \| sudo debconf-communicate` | Stale `apropos` |
| `apt-daily-upgrade.timer` | `systemctl edit` it to a quiet hour | None. Keep security updates on. |
| snap refresh, four times a day | `sudo snap set system refresh.timer=…` | None |

### 8. File descriptors

systemd's default is a soft limit of 1,024 and a hard limit of 524,288. Node raises its own. For what does not: `ulimit -n 65536` in the shell profile, or `LimitNOFILE=65536` in a user unit. The shipped `.zshrc` raises it for the shell and what it starts, never past the hard limit. Don't raise the system-wide default (`DefaultLimitNOFILE`); services that use `select()` break above 1,023 ([Poettering](https://0pointer.net/blog/file-descriptor-limits.html)).

### 9. Disks on a small box

On a Raspberry Pi 5, boot from NVMe, not an SD card. If it must be an SD card: `noatime,commit=60` on the root filesystem cuts writes, and loses up to a minute of data on a power cut. Leave `fstrim.timer` weekly. Don't turn on PCIe Gen 3 on a box no one watches; the Pi's own docs call it uncertified.

### Sandboxes on Ubuntu

Ubuntu 24.04 and later restrict unprivileged user namespaces through AppArmor. A namespace-based sandbox that fails to start there needs an AppArmor profile for the program, not the `kernel.apparmor_restrict_unprivileged_userns=0` switch, which turns the protection off for everything.

## What tuidev sets today

| Setting | Where |
|---------|-------|
| A 4 GB Node heap cap for agents, so a runaway test fails inside the test | `--pack ai-clis` |
| A memory guard that stops a runaway in an agent tree | `--pack monitoring` |
| Cleanup of what a finished subagent or cleared session left running | `--pack ai-clis` hooks |
| MCP servers started on first use, not once per session | `agents mcp lazy` |
| Fans that follow sustained chip temperature | `--pack cooling` |
| `cat`, `ls` and `top` that stay the real commands for agents | the shipped `.zshrc` |
| An open-files limit of 65,536 for the shell and what it starts | the shipped `.zshrc` |
| `core.untrackedCache`, while you have not set it | the git defaults |
| Time Machine exclusions for package stores, when you say yes | `make perf-fix` |
| Tools' own cache cleanups and superseded runtimes, each when you say yes | `make disk-fix` |

It does not touch Spotlight's list, Gatekeeper, power settings or sysctls. Those belong to you, most need root, and one trades away a malware scan. `make perf` tells you where they stand.
