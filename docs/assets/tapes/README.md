# Screenshot tapes

The images in [docs/assets/](..) are rendered from the [VHS](https://github.com/charmbracelet/vhs) tapes here, and the menu-bar picture from the SwiftBar plugin's own output, all against made-up data, so they can be re-made after a UI change and never show anything from the machine that rendered them. How to run them, and when, is in [engineering.md](../../engineering.md#screenshots).

```bash
make screenshots                         # every tape, then the menu picture
make screenshots TAPES="agents menu"     # some, by name (menu = scripts/render_menu.sh)
```

| Source | Image | Shows |
|--------|-------|-------|
| `tour.tape` | `tour.gif` | The README hero: a short tour of the shell, `agents` and `sbx` in one demo home |
| `herdr.tape` | `herdr.gif`, `herdr.png` | Herdr's sidebar over three machines (this Mac, and `devbox` and `workbox`, two Linux containers saved as SSH machines), six agent stand-ins; it jumps to the blocked one on `devbox`, answers it, then opens `workbox` |
| `cleanup.tape` | `cleanup.gif` | `agents` with a polling loop stuck for 5h, `agents why 2120` (safe to stop: what it waits for already finished), then `agents report` with its Top insights |
| `cli.tape` | `cli.gif` | The shipped zsh in the `~/api` demo repo: autosuggestions, `z`, `lt` (eza tree), `cat` (bat), Ctrl-T (fzf with a bat preview), Ctrl-R (atuin), `tokei` |
| `shell.tape` | `shell.png` | The real Starship prompt, `ll src` (eza with icons and a git column), `rg` and `git diff` through delta, in the `~/api` demo repo |
| `agents.tape` | `agents.png` | `agents` over the fixture process table |
| `sbx.tape` | `sbx.png` | a key read without and under `sbx`, then refused credentials and a `~/.zshrc` write, while `make test` runs |
| `social-preview.tape` | `social-preview.png` | The 1280×640 Open Graph card; its text is in `social-card.sh` |
| `theme.tape` | | Shared settings: the Tokyo Night palette and the Ghostty font, sourced by the others |
| [`scripts/render_menu.sh`](../../../scripts/render_menu.sh) | `menu-light.webp`, `menu-dark.webp`, `menu.gif` | The SwiftBar menu: the plugin's real output over the fixtures, drawn as a macOS menu ([below](#the-swiftbar-menu)) |

Besides VHS (`brew install vhs`), the shots need the [Symbols Nerd Font](https://github.com/ryanoasis/nerd-fonts) (`brew install --cask font-symbols-only-nerd-font`): `theme.tape` lists it after JetBrains Mono as a fallback, so the file icons `eza` draws render as they do in Ghostty. Without it they show as blanks, and `make screenshots` warns. The `herdr` tape also needs Herdr and Apple's [`container`](https://github.com/apple/container) CLI, running (`container system start`); without them `make screenshots` skips it with a warning. The menu needs Google Chrome or Chromium and Swift (the Xcode command-line tools). With `gifsicle` installed, the GIFs are optimized after rendering.

## The demo environment

`make screenshots` runs on macOS only: the `sbx` shot needs Seatbelt, and the demo is only checked there. `scripts/screenshots.sh` gives each tape a throwaway home under `/tmp` (short enough for the fake Herdr socket in it; `$TMPDIR` on macOS is too long) and deletes it afterwards. The `sbx` and `tour` tapes' home is `/Users/Shared/NAME` instead: strict lets `sbx` write to `$TMPDIR`, so a home there would make the "write outside the project" denial false, and `/Users/Shared/NAME` shows no real user in the error paths (the script refuses to run if it already exists). The `agents`, `cleanup` and `sbx` tapes source `demo-env.sh`, hidden, which:

- picks a time zone where it is mid-afternoon now, so the made-up history below has a working day behind its "Today", whenever the shots are rendered;
- builds that home with `demo-setup.sh`: three projects (`myapp`, `api`, `web`), fake `~/.ssh/id_ed25519`, `~/.aws/credentials` and `~/.zshrc` for `sbx` to protect, a `make test` target in `myapp`, a `~/.claude/settings.json`, and the state `agents` reads (a keep-awake record and a Herdr socket);
- writes the background-task output that the `api` session's polling loop watches (its last line is Claude Code's `[exited with code 0]`, dated 5 hours ago), and, with `demo-history.sh`, a made-up week of `agents sample` history, cleanups and finished runs (`runs.tsv`; fixed noise, ending now) for `agents report`, its Top insights and the menu's Today and insight lines (the insight is written by the real `agents` code, as a sample would);
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
| `herdr agent list` | `fixtures/herdr.tsv` (session status: blocked, working, idle) |
| `sysctl`, `memory_pressure`, `pmset`, `notifyutil`, `launchctl` | fixed answers in `demo-stub.sh` |
| `kill` | a no-op: the demo never signals anything |
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

- **Local** is a Herdr server on this Mac, in a throwaway home under `/tmp` (short, because Herdr's sockets live there). Its config is the shipped `configs/herdr/config.toml` plus demo-only settings: no onboarding, update checks or sounds, and `remote.manage_ssh_config = false`.
- **devbox** and **workbox** are two Linux containers (Apple `container`) built from `herdr/Containerfile`: Debian with OpenSSH, Herdr at the same version as this Mac's (its release binary, checked against the digest the release lists), and a user `dev`. Each publishes its sshd on a loopback port, which macOS's Local Network privacy can't block, and the Mac's Herdr saves them with `herdr machine add` under those labels, as you would a real node.
- **ssh never reads your own setup.** Every demo process runs with `env -i`, the throwaway `HOME` and an `ssh` wrapper first on `PATH` that passes `-F` with the demo's own config, key (made for the demo), `known_hosts`, `IdentitiesOnly` and no agent. Nothing from a Herdr pane the script runs in (`HERDR_ENV`, `HERDR_SOCKET_PATH`, …) reaches the demo, so it is a separate Herdr, not one nested in yours.
- **The agents are stand-ins.** `herdr/demo-agent.sh` prints a short scripted transcript and reports its state through Herdr's hook API (`herdr pane report-agent`), the call an agent integration makes: working, blocked on a yes/no question, then done when answered. No model runs, and each pane says so in its first line. Real Claude Code or Codex sessions would need accounts and would show their owners' conversations.

The first run builds the image (`tuidev-demo-node:VERSION-HASH`, about a minute); `container image delete` removes it. To look around by hand:

```bash
bash docs/assets/tapes/herdr-demo.sh up /tmp/hd/NAME
eval "$(bash docs/assets/tapes/herdr-demo.sh env /tmp/hd/NAME)" && herdr   # Ctrl+b q detaches
bash docs/assets/tapes/herdr-demo.sh down /tmp/hd/NAME
```

Don't run that client inside a Herdr pane of your own: open a plain terminal.

## The SwiftBar menu

SwiftBar draws a native macOS menu, which VHS can't record, and a screenshot of a real menu bar would show your own items. So `scripts/render_menu.sh` draws it from the plugin itself:

1. It runs `configs/swiftbar/agents.10s.sh` twice (the second run sees Herdr's status, as SwiftBar's second refresh would) with `AGENTS_BIN` set to the demo `agents`, in a demo home from `demo-env.sh`. The output is the text SwiftBar would get.
2. `docs/assets/menu/symbols.swift` renders every SF Symbol the output names (`sfimage=`, and `:name:` in titles) with AppKit, so the icons are the system's own.
3. `docs/assets/menu/menu.html` parses SwiftBar's format (`--` submenus, `---` separators, `size`, `checked`, `sfconfig` colors, rows without an action dimmed, as SwiftBar shows them) and lays it out as a macOS menu in light and dark, with given submenus open. Headless Chrome captures it at 2x: `menu-light.webp` and `menu-dark.webp` with the first stuck command's verdict open, and `menu.gif`, which opens four submenus in turn.

What it can't show: SwiftBar's own items at the bottom of a real menu, the live translucency of your wallpaper, and hover. When the plugin's output changes, `make screenshots TAPES=menu` redraws it.

To capture the real menu by hand instead, `swiftbar-demo.sh` writes a demo plugin over the same fixtures:

1. Write it into an empty folder: `bash docs/assets/tapes/swiftbar-demo.sh "$TMPDIR/swiftbar-demo"`.
2. In SwiftBar's settings, note your plugin folder, then choose the demo folder. After the second refresh (about 10 s) the title shows three sessions and `· 1 blocked`.
3. Open the menu, press `⌘⇧4` then `Space`, and click the menu to capture it with its shadow. Hover a session first to capture its submenu too.
4. Set SwiftBar's plugin folder back, and delete the demo folder.

Every action in the demo menu fails safe. SwiftBar runs a menu action in its own environment, without the plugin's `DEMO_HOME`, so an action that calls the demo `agents` directly stops at its `DEMO_HOME` check before doing anything. One that goes back through the demo plugin reaches the demo `agents`, which never signals and refuses keep-awake and new windows. Check the capture for anything from your own menu bar (other items, the clock) and crop it out.
