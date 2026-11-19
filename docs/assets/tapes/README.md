# Screenshot tapes

The images in [docs/assets/](..) are rendered from the [VHS](https://github.com/charmbracelet/vhs) tapes here, and the menu-bar picture from the SwiftBar plugin's own output, all against made-up data, so they can be re-made after a UI change and never show anything from the machine that rendered them. How to run them, and when, is in [engineering.md](../../engineering.md#screenshots).

```bash
make screenshots                         # every tape, then the menu picture
make screenshots TAPES="agents menu"     # some, by name (menu = scripts/render_menu.sh)
make screenshots TAPES=clips             # every clip (clip-*.tape, clip-menu, clip-remote)
```

| Source | Image | Shows |
|--------|-------|-------|
| `tour.tape` | `tour.gif` | The README hero: a short tour of the shell, `agents` and `sbx` in one demo home |
| `herdr.tape` | `herdr.gif`, `herdr.png` | Herdr's sidebar over three machines (this Mac, and `devbox` and `workbox`, two Linux containers saved as SSH machines) with tuidev on each: seven agent stand-ins in six workspaces, tabs named after their tasks, and tuidev's sidebar rows (each workspace's branch and roll-up, a red `blocked` count, since when an agent waits); it jumps to the blocked one on `devbox`, answers it, then opens `workbox` |
| `cleanup.tape` | `cleanup.gif` | `agents` with a polling loop stuck for 5h, `agents why 2120` (safe to stop: what it waits for already finished), then `agents report` with its Top insights |
| `cli.tape` | `cli.gif` | The shipped zsh in the `~/api` demo repo: autosuggestions, `z`, `lt` (eza tree), `cat` (bat), Ctrl-T (fzf with a bat preview), Ctrl-R (atuin), `tokei` |
| `shell.tape` | `shell.png` | The real Starship prompt, `ll src` (eza with icons and a git column), `rg` and `git diff` through delta, in the `~/api` demo repo |
| `agents.tape` | `agents.png` | `agents` over the fixture process table |
| `board.tape` | `board.gif`, `board.png` | `agents board` over the same three sessions, in a plain terminal (VHS records one terminal, not Herdr's popup): it opens on the one that needs you with its question on the right, moves to the finished one and the working one, then switches to the Tree lens |
| `sbx.tape` | `sbx.png` | a key read without and under `sbx`, then refused credentials and a `~/.zshrc` write, while `make test` runs |
| `social-preview.tape` | `social-preview.png` | The 1280×640 Open Graph card; its text is in `social-card.sh` |
| `theme.tape` | | Shared settings: the Tokyo Night palette and the Ghostty font, sourced by the others |
| [`scripts/render_menu.sh`](../../../scripts/render_menu.sh) | `menu-light.webp`, `menu-dark.webp`, `menu.gif`, `clips/menu.mp4` | The SwiftBar menu: the plugin's real output over the fixtures, drawn as a macOS menu ([below](#the-swiftbar-menu)) |
| `clip-install.tape` | `clips/install.mp4`, `.gif` | The installer's dry run for `--profile full`, from a copy of the checkout in the demo home: its opening screen (profile, packs, first steps; `2>&1 \| head -24`), then the whole run, recorded hidden and shown once it ends on "Next:" and the numbered steps it would leave to you |
| `clip-needs-you.tape` | `clips/needs-you.mp4`, `.gif` | `agents`, then `agents board` opening on the session blocked on a question |
| `clip-leftovers.tape` | `clips/leftovers.mp4`, `.gif` | `agents stale`, `agents why 4500` (check first: a server left behind), `agents reap -n` planning only the safe ones and counting what it left out |
| `clip-cost.tape` | `clips/cost.mp4`, `.gif` | `agents limits`, then `agents report`: CPU by job and project, tokens and their API-equivalent cost |
| `clip-keys.tape` | `clips/keys.mp4`, `.gif` | `sbx` refusing the fake key while `make test` runs, then `secret scan` naming the demo's `DEMO_TOKEN` without printing it |
| `clip-hog.tape` | `clips/hog.mp4`, `.gif` | With `DEMO_HOG=1`: `agents hogs`, `agents why 1311` and `agents mem`, a test run past the guard's warning size |
| `clip-remote` (no tape) | `clips/remote.mp4`, `.gif` | A cut from `remote-cut.mp4` ([below](#the-remote-screencasts-fleet)) at the seconds `REMOTE_SEGMENTS` in `scripts/screenshots.sh` lists: three machines, the map, then the checkout page served from atlas in a browser here, held at the end |

Besides VHS (`brew install vhs`), the shots need the [Symbols Nerd Font](https://github.com/ryanoasis/nerd-fonts) (`brew install --cask font-symbols-only-nerd-font`): `theme.tape` lists it after JetBrains Mono as a fallback, so the file icons `eza` draws render as they do in Ghostty. Without it they show as blanks, and `make screenshots` warns. The `herdr` tape also needs Herdr and a container runtime: Apple's [`container`](https://github.com/apple/container) CLI (`container system start`) or podman. `herdr-demo.sh` reads `TUIDEV_CONTAINER_RUNTIME=container|podman` (see [The Herdr fleet](#the-herdr-fleet)). `make screenshots` skips the tape unless Herdr is installed and the runtime is running (Apple's `container system start`, or `podman machine start`). The menu needs Google Chrome or Chromium and Swift (the Xcode command-line tools). With `gifsicle` installed, the GIFs are optimized after rendering.

## The clips

The clips in `docs/assets/clips/` are short and silent, 15 to 20 s each, for README sections, release notes and posts. Each one shows a single outcome and holds its last frame for 2 s. A clip tape records `clips/NAME.mp4` with VHS. `scripts/screenshots.sh` then scales it to 1200 px wide at most and burns in a caption from [`clips.txt`](clips.txt) (one line per clip, so a caption can be reworded without touching the tape). The caption sits in a strip under the terminal, in the margin's color. Last, the script makes `NAME.gif` from the result. The ffmpeg Homebrew installs has no `drawtext` filter, so ImageMagick (`brew install imagemagick`) draws the caption and ffmpeg overlays it. `CLIP_CAPTIONS=0 make screenshots TAPES=clips` renders them without captions. The menu's clip comes from `render_menu.sh`'s frames, and the remote one is cut from `remote-cut.mp4`, so it exists only where that hand-made file does.

`clip-install` and `clip-keys` run in `/Users/Shared/NAME`, as `sbx` and `tour` do. `clip-install` copies the checkout to `~/tuidev` in that home (without `.git` and `docs/assets`) and runs the installer from there, so its paths are the demo's, not the renderer's. It also drops the renderer's own home from `PATH`, and records the full run hidden, because its middle names the renderer's SwiftBar plugin folder (read with `defaults`). The demo `~/.zshrc` exports a made-up `DEMO_TOKEN` for `secret scan` to name. `DEMO_HOG=1` (set by `clip-hog`) adds `fixtures/hog/` to the process table: a vitest run at 9.9 GB under the `myapp` session, plus the warning the guard recorded for it in `memory.tsv`. `agents cool` is not in that clip. It reads the fan daemon's status file, which would need a made-up one of its own, and it tells a different story (heat, not memory).

## The demo environment

`make screenshots` runs on macOS only: the `sbx` shot needs Seatbelt, and the demo is only checked there. `scripts/screenshots.sh` gives each tape a throwaway home under `/tmp` (short enough for the fake Herdr socket in it; `$TMPDIR` on macOS is too long) and deletes it afterwards. The `sbx` and `tour` tapes' home is `/Users/Shared/NAME` instead: strict lets `sbx` write to `$TMPDIR`, so a home there would make the "write outside the project" denial false, and `/Users/Shared/NAME` shows no real user in the error paths (the script refuses to run if it already exists). The `agents`, `cleanup` and `sbx` tapes source `demo-env.sh`, hidden, which:

- drops what the renderer's own shell would leak into the shots: `XDG_CONFIG_HOME`, `XDG_DATA_HOME`, `XDG_STATE_HOME`, `XDG_CACHE_HOME`, `ZDOTDIR`, `HISTFILE` and every `ATUIN_*` and `_ZO_*` (zoxide) setting, so neither this bash nor the `cli` tape's `exec zsh -i` reads or writes your history, zoxide database or config;
- picks a time zone where it is mid-afternoon now, so the made-up history below has a working day behind its "Today", whenever the shots are rendered;
- builds that home with `demo-setup.sh`: three projects (`myapp`, `api`, `web`), fake `~/.ssh/id_ed25519`, `~/.aws/credentials` and `~/.zshrc` for `sbx` to protect, a `make test` target in `myapp`, a `~/.claude/settings.json`, and the state `agents` reads (a keep-awake record and a Herdr socket);
- writes the background-task output that the `api` session's polling loop watches (its last line is Claude Code's `[exited with code 0]`, dated 5 hours ago), and, with `demo-history.sh`, a made-up week of `agents sample` history, cleanups, finished runs (`runs.tsv`), waits (`waits.tsv`, which also sets the menu's blocked time) and tokens (`tokens.tsv`, `tokens.today`, with a few compactions and denials and a Codex plan reading; fixed noise, ending now) for `agents report`, its Top insights and the menu's Today, tokens and insight lines (the insight is written by the real `agents` code, as a sample would);
- sets `HOME` to it and draws a two-line prompt shaped like the shipped Starship one, without Starship (the `shell`, `cli` and `tour` tapes start the real one, below);
- puts `bin/agents` (the demo wrapper) and the repo's `bin/sbx` first on `PATH`.

The `shell`, `cli` and `tour` tapes source `demo-shell.sh` instead, which sources `demo-env.sh` and then, with `demo-shell-setup.sh`:

- makes `~/api`, a small repo with a staged change, an unstaged one and an untracked file, with fixed file times;
- installs the shipped `starship.toml` as a managed block and applies the Tokyo Night palette with `scripts/theme.sh`, as an install would, then starts the real Starship (the prompt shows `~/api` and the branch, never a user or host);
- sets the git defaults tuidev ships (`delta` as the pager) in the demo home, and reads the `cat`, `ls` and `ll` aliases from `configs/zsh/.zshrc`, so they can't drift. The one override is `ll`: it adds `--no-user --no-permissions`, because the owner column would show whoever renders it.

The `cli` tape then runs `demo-zsh-setup.sh`, which copies the shipped `configs/zsh/.zshrc` into the demo home, writes a short made-up `~/.zsh_history` (imported into atuin's database there, for Ctrl-R) and ranks three directories for zoxide, and `exec zsh -i`: what you see is the shipped zsh, with its plugins, Starship, fzf, zoxide and atuin, in the demo home.

`sbx` is the real one. The demo `agents` is the real `bin/agents`, sourced, with these swapped in:

| Real | Demo |
|------|------|
| `ps`, `lsof` (listeners) | `fixtures/ps.txt`, `fixtures/listeners.txt` |
| working directories (`lsof`, or `/proc` on Linux) | `fixtures/cwds.tsv`, read by the wrapper's own `_agents_cwds` |
| `herdr agent list` | `fixtures/herdr.tsv` (session status: blocked, working, done) |
| `herdr pane read`, `herdr pane process-info` (only with `DEMO_PANES=1`, which `board.tape` sets) | `fixtures/panes.tsv` (each session's pane id and task title) and `fixtures/panes/*.txt` (a made-up screen each, input box and status lines included, so the board trims them as it does a real one) |
| `sysctl`, `memory_pressure`, `pmset`, `notifyutil`, `launchctl` | fixed answers in `demo-stub.sh` |
| `top` (each process's footprint, for `agents mem`) | `ps.txt`'s RSS, biggest first, in `demo-stub.sh` |
| the memory guard (`agents mem guard`) | pid 8900 in `ps.txt` holds its lock (`demo-setup.sh`), the wrapper keeps its heartbeat current, and `memtotal` makes it a 48 GB Mac (warn at 8G, stop at 24G) |
| `kill` | a no-op: the demo never signals anything, but for the process group of a job its own shell started (the watcher of a timed-out probe) |
| `AGENTS_UID`, `AGENTS_SELF` | the fixture's uid 501, and a pid that isn't in the table (`AGENTS_TESTING=1`, the test harness's hook) |
| `~/.local/state/tuidev/agents` | the same path in the demo home (`AGENTS_DATA_DIR`), filled by `demo-history.sh` |

`awake on|off|agents` and `open-term` are refused, because they would start real processes. Paths inside command lines in `ps.txt` use `/Users/NAME`, except the polling loop's watched file, which uses `@HOME@` because it must exist; working directories in `cwds.tsv` and `herdr.tsv` use `@HOME@` too, which becomes the demo home so the `CWD` column shows `~/myapp`.

To try the demo by hand, from the repo root in bash:

```bash
source docs/assets/tapes/demo-env.sh
agents
agents why 2120
agents report
sbx -- cat ~/.ssh/id_ed25519
```

Without `DEMO_HOME` set, `demo-env.sh` makes the home with `mktemp` and leaves it there: when you're done, close that shell and `rm -rf "$(dirname "$DEMO_HOME")"` (run it in the demo shell first to see the path, `echo "$DEMO_HOME"`). Set `DEMO_HOME` before sourcing to choose the place yourself.

To change a shot, edit the fixtures or the tape, run `make screenshots`, and look at the result before committing it. Keep names generic (`myapp`, `api`, `web`, user `NAME`, hosts `devbox` and `workbox`); CI's no-hardcoded-paths scan reads this folder too.

## The Herdr fleet

A Herdr picture is only honest if Herdr is real and really talks to more than one machine, so `herdr.tape` runs on a small fleet that `herdr-demo.sh` starts before the tape and removes after it:

- **Local** is a Herdr server on this Mac, in a throwaway home under `/tmp` (short, because Herdr's sockets live there). Its config is the shipped `configs/herdr/config.toml` plus demo-only settings: no onboarding, update checks or sounds, and `remote.manage_ssh_config = false`. It also gets the herdr pack's two managed blocks, its keys (`configs/herdr/keys.toml`) and its sidebar rows (`configs/herdr/sidebar.toml`). Every demo process runs with `TZ=UTC`, the containers' zone, so the times in the sidebar agree across machines and say nothing about where it was rendered.
- **devbox** and **workbox** are two Linux containers (Apple `container` or podman) built from `herdr/Containerfile`: Debian with OpenSSH, Herdr at the same version as this Mac's (its release binary, checked against the digest the release lists), and a user `dev`. The runtime comes from [`scripts/lib/container.sh`](../../../scripts/lib/container.sh): `TUIDEV_CONTAINER_RUNTIME=container|podman` when that command is on PATH, otherwise Apple `container` on macOS, then podman. herdr-demo.sh runs `container` and podman. On some Macs an Apple container VM has no outbound network, so `apt-get` in the Containerfile times out; `TUIDEV_CONTAINER_RUNTIME=podman` builds the same file. Each publishes its sshd on a loopback port, which macOS's Local Network privacy can't block, and the Mac's Herdr saves them with `herdr machine add` under those labels, as you would a real node.
- **ssh never reads your own setup.** Every demo process runs with `env -i`, the throwaway `HOME` and an `ssh` wrapper first on `PATH` that passes `-F` with the demo's own config, key (made for the demo), `known_hosts`, `IdentitiesOnly` and no agent. Nothing from a Herdr pane the script runs in (`HERDR_ENV`, `HERDR_SOCKET_PATH`, …) reaches the demo, so it is a separate Herdr, not one nested in yours.
- **tuidev runs on every machine**, as in the remote screencast's fleet: this checkout's `agents` and the `tuidev.link` plugin, linked into each machine's Herdr. The plugin's hooks run `agents herdr sync` on each server for its own panes: tabs are named after the stand-ins' terminal titles (`✳ Fix 404 routes`), and the sync sets the `$tuidev_agents`, `$tuidev_need` and `$tuidev_since` tokens the sidebar rows show.
- **The cast** is six workspaces, each a git repo with one commit, so the sidebar shows a branch: on Local, `myapp` (two Claude Code stand-ins and a shell) and `web` (Codex); on devbox, `api` (one blocked on `git push`, and a shell) and `api-docs`; on workbox, `infra` (Codex) and `api-tests`.
- **The agents are stand-ins.** `herdr/demo-agent.sh` prints a short scripted transcript, sets its task as the terminal title (`✳ TITLE` for Claude, as Claude Code does) and reports its state through Herdr's hook API (`herdr pane report-agent`), the call an agent integration makes: working, blocked on a yes/no question, then idle when answered. No model runs, and each pane says so in its first line. Real Claude Code or Codex sessions would need accounts and would show their owners' conversations.
- **"done" needs a client that watched.** Herdr's client shows an agent as done only when it saw the agent finish; one that finished before the client attached is idle. Two stand-ins (`review+N`) wait for `herdr-demo.sh go HOME`, which the tape runs just before it attaches, then finish N seconds later. Without the cue they wait at most 60 s.

The first run builds the image (`tuidev-demo-node:VERSION-HASH`, about a minute). Remove it with `container image delete` or `podman rmi`, for the runtime that built it. To look around by hand:

```bash
bash docs/assets/tapes/herdr-demo.sh up /tmp/hd/NAME
eval "$(bash docs/assets/tapes/herdr-demo.sh env /tmp/hd/NAME)" && herdr   # Ctrl+b q detaches
bash docs/assets/tapes/herdr-demo.sh down /tmp/hd/NAME
```

Export `TUIDEV_CONTAINER_RUNTIME` for both `up` and `down` when podman should own the containers, so `down` removes the ones `up` started.

Don't run that client inside a Herdr pane of your own: open a plain terminal.

## The SwiftBar menu

SwiftBar draws a native macOS menu, which VHS can't record, and a screenshot of a real menu bar would show your own items. So `scripts/render_menu.sh` draws it from the plugin itself:

1. It runs `configs/swiftbar/agents.10s.sh` twice (the second run sees Herdr's status, as SwiftBar's second refresh would) with `AGENTS_BIN` set to the demo `agents`, in a demo home from `demo-env.sh`. The output is the text SwiftBar would get.
2. `docs/assets/menu/symbols.swift` renders every SF Symbol the output names (`sfimage=`, and `:name:` in titles) with AppKit, so the icons are the system's own.
3. `docs/assets/menu/menu.html` parses SwiftBar's format (`--` submenus, `---` separators, `size`, `font`, `checked`, `sfconfig` and `sfcolor` colors, rows without an action dimmed, as SwiftBar shows them) and lays it out as a macOS menu in light and dark, with given submenus open. Headless Chrome captures it at 2x: `menu-light.webp` and `menu-dark.webp` with the first flagged command's verdict open, and `menu.gif`, which opens four submenus in turn.

What it can't show: the live translucency of your wallpaper, and hover. When the plugin's output changes, `make screenshots TAPES=menu` redraws it (`MENU_OUT=DIR scripts/render_menu.sh` draws it elsewhere, to look at a change first).

To capture the real menu by hand instead, `swiftbar-demo.sh` writes a demo plugin over the same fixtures:

1. Write it into an empty folder: `bash docs/assets/tapes/swiftbar-demo.sh "$TMPDIR/swiftbar-demo"`.
2. In SwiftBar's settings, note your plugin folder, then choose the demo folder. After the second refresh (about 10 s) the title shows three sessions and `· 1 blocked`.
3. Open the menu, press `⌘⇧4` then `Space`, and click the menu to capture it with its shadow. Hover a session first to capture its submenu too.
4. Set SwiftBar's plugin folder back, and delete the demo folder.

Every action in the demo menu fails safe. SwiftBar runs a menu action in its own environment, without the plugin's `DEMO_HOME`, so an action that calls the demo `agents` directly stops at its `DEMO_HOME` check before doing anything. One that goes back through the demo plugin reaches the demo `agents`, which never signals and refuses keep-awake and new windows. Check the capture for anything from your own menu bar (other items, the clock) and crop it out.

## The remote screencast's fleet

`remote-demo.sh` is the same fleet with tuidev on every machine, for recording "remote feels local" ([remote.md](../../remote.md#remote-feels-local-ports-links-and-files)) without a real hostname or session on screen:

```bash
bash docs/assets/tapes/remote-demo.sh up /tmp/hd/aurora
eval "$(bash docs/assets/tapes/remote-demo.sh env /tmp/hd/aurora)" && herdr   # Ctrl+b q detaches
bash docs/assets/tapes/remote-demo.sh down /tmp/hd/aurora
```

- The machines are **atlas** and **kepler** (two containers, as above). Each has this checkout's `agents` and the `tuidev.link` plugin with its keys; this Mac's demo home has them too, and runs the link watcher.
- The cast: on atlas, a `storefront` session that starts a real web server on `localhost:5173` and writes `review.md`, and a `search` session blocked on a question; on kepler, an `orders-api` session that started a server on `:8080` and ended, leaving it behind, and a `platform-infra` session; here, `payments` and `docs-site`. They are the same stand-ins, run under their agent's name so `agents` lists them as sessions.
- The environment sets `AGENTS_MAP_ROOT` to the demo home, so `agents map` lists only what runs under it and never the sessions of whoever records.
- The storefront stand-in also leaves what Claude Code keeps about a session (a record in `~/.claude/sessions` and a transcript with one Write call), so the map lists `review.md` among the files sessions wrote.
- `remote.tape` renders `docs/assets/remote.mp4`: start the fleet with `TUIDEV_DEMO_NO_BROWSER=1` (the demo's `open` then only records what it was given, so no tab opens while VHS draws), then `DEMO_HOME=/tmp/hd/aurora vhs docs/assets/tapes/remote.tape`. `remote-browser.png` is the forwarded page as headless Chrome renders it, cut in with ffmpeg for `remote-cut.mp4` and `remote.gif`. The tape's prompt shows no path, so nothing of the machine that renders it is on screen.
- What is real: the ssh tunnels, the Herdr plugin's click, the browser tab (this Mac's own browser, on a `127.0.0.1` port), `agents map` and its stop. It is not a VHS tape: a click that opens a browser needs a screen recording.

