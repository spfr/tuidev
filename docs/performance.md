# Performance: What the OS Does Behind Your Agents

Agents change what a dev machine does all day. Worktrees are created and deleted by the dozen, dependency trees are installed into each one, and thousands of freshly built binaries run once. The operating system's background services were tuned for a person editing documents: they index, back up, scan and watch every one of those files.

This page lists what is worth changing on macOS and Linux, in order of effect, with the command, its cost and how to undo it. Each claim says where it comes from: **measured** (on an M4 Pro MacBook, macOS 27.2, November 2026), **sourced** (linked), or **unverified**. tuidev checks all of it for you and applies the few fixes that are safe to automate: [let tuidev check](#let-tuidev-check).

## Let tuidev check

```bash
make perf          # the audit; changes nothing
make perf-fix      # the audit, then each fix that needs no root, one question at a time
```

```text
✓ Spotlight: package stores and repo folders are out of the index
⚠ Time Machine backs up ~/go/pkg/mod
    fix (--fix does this): tmutil addexclusion ~/go/pkg/mod
⚠ Spotlight indexes 270240 files in ~/Library/pnpm/store/v11, a package store no one searches
    fix: System Settings > Spotlight > Search Privacy > + > ~/Library/pnpm/store/v11   (macOS has no command for this list)
ℹ 2 to change, 1 of them by './scripts/perf.sh --fix'. Why: docs/performance.md
```

The same report closes every install, `make update-check` and `make update-all`, so the machine is checked again whenever you update: a new package manager's store, a backup disk you added, a limit a reinstall reset.

| It checks | It fixes | Otherwise |
|-----------|----------|-----------|
| Package stores and repo folders in the Spotlight index (it asks Spotlight how many files it holds under each) | | Names the folder to add in System Settings |
| Package stores in Time Machine backups, when a backup disk is set up | `tmutil addexclusion` | |
| `core.untrackedCache`, and a global `core.fsmonitor` | Sets the first, recorded for uninstall | Prints the command for the second |
| The open-files limit in your shell | The shipped `.zshrc` raises it | Points at `update.sh --configs` |
| Low Power Mode on the charger; repos in iCloud-synced folders; a store on another volume | | Says what to change |
| Linux: inotify limits, swap, `updatedb` | | Prints the drop-in or the line, for you to run with `sudo` |

It finds your package stores by asking pnpm, Go, uv and npm, and looks for repos in the usual folders (`~/workspace`, `~/code`, `~/src`, `~/dev`, `~/Developer`, `~/projects`, `~/repos`, `~/work`). Name others in `TUIDEV_PERF_DIRS`, colon-separated. It never runs `sudo`, and it never edits Spotlight's own files: [why](#1-spotlight).

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
# /etc/sysctl.d/60-inotify.conf
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

It does not touch Spotlight's list, Gatekeeper, power settings or sysctls. Those belong to you, most need root, and one trades away a malware scan. `make perf` tells you where they stand.
