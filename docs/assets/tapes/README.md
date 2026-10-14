# Screenshot tapes

The images in [docs/assets/](..) are rendered from the [VHS](https://github.com/charmbracelet/vhs) tapes here, against made-up data, so they can be re-made after a UI change and never show anything from the machine that rendered them. How to run them, and when, is in [engineering.md](../../engineering.md#screenshots).

```bash
make screenshots                    # every tape
make screenshots TAPES="agents"     # one or more by name
```

| Tape | Image | Shows |
|------|-------|-------|
| `tour.tape` | `tour.gif` | The README hero: a short tour of the shell, `agents` and `sbx` in one demo home |
| `shell.tape` | `shell.png` | The real Starship prompt, `ll src` (eza with icons and a git column), `rg` and `git diff` through delta, in the `~/api` demo repo |
| `agents.tape` | `agents.png` | `agents` over the fixture process table |
| `sbx.tape` | `sbx.png` | a key read without and under `sbx`, then refused credentials and a `~/.zshrc` write, while `make test` runs |
| `social-preview.tape` | `social-preview.png` | The 1280×640 Open Graph card; its text is in `social-card.sh` |
| `theme.tape` | | Shared settings: the Tokyo Night palette and the Ghostty font, sourced by the others |

Besides VHS (`brew install vhs`), the shots need the [Symbols Nerd Font](https://github.com/ryanoasis/nerd-fonts) (`brew install --cask font-symbols-only-nerd-font`): `theme.tape` lists it after JetBrains Mono as a fallback, so the file icons `eza` draws render as they do in Ghostty. Without it they show as blanks, and `make screenshots` warns.

## The demo environment

`make screenshots` runs on macOS only: the `sbx` shot needs Seatbelt, and the demo is only checked there. `scripts/screenshots.sh` gives each tape a throwaway home in `$TMPDIR` and deletes it afterwards. The `sbx` and `tour` tapes' home is `/Users/Shared/NAME` instead: strict lets `sbx` write to `$TMPDIR`, so a home there would make the "write outside the project" denial false, and `/Users/Shared/NAME` shows no real user in the error paths (the script refuses to run if it already exists). The `agents` and `sbx` tapes source `demo-env.sh`, hidden, which:

- builds that home with `demo-setup.sh`: three projects (`myapp`, `api`, `web`), fake `~/.ssh/id_ed25519`, `~/.aws/credentials` and `~/.zshrc` for `sbx` to protect, a `make test` target in `myapp`, a `~/.claude/settings.json`, and the state `agents` reads (a keep-awake record and a Herdr socket);
- sets `HOME` to it and draws a two-line prompt shaped like the shipped Starship one, without Starship (the `shell` and `tour` tapes start the real one, below);
- puts `bin/agents` (the demo wrapper) and the repo's `bin/sbx` first on `PATH`.

The `shell` and `tour` tapes source `demo-shell.sh` instead, which sources `demo-env.sh` and then, with `demo-shell-setup.sh`:

- makes `~/api`, a small repo with a staged change, an unstaged one and an untracked file, with fixed file times;
- installs the shipped `starship.toml` as a managed block and applies the Tokyo Night palette with `scripts/theme.sh`, as an install would, then starts the real Starship (the prompt shows `~/api` and the branch, never a user or host);
- sets the git defaults tuidev ships (`delta` as the pager) in the demo home, and reads the `cat`, `ls` and `ll` aliases from `configs/zsh/.zshrc`, so they can't drift. The one override is `ll`: it adds `--no-user --no-permissions`, because the owner column would show whoever renders it. The shipped Starship config has no branch icon (its `symbol` is a plain space), so the prompt shows none either.

There is no Herdr shot: its UI shows live panes from a running server, and a truthful one would need real agent sessions, which the demo never starts. The `agents` shot shows Herdr's session status through a fixture instead.

`sbx` is the real one. The demo `agents` is the real `bin/agents`, sourced, with these swapped in:

| Real | Demo |
|------|------|
| `ps`, `lsof` (listeners) | `fixtures/ps.txt`, `fixtures/listeners.txt` |
| working directories (`lsof`, or `/proc` on Linux) | `fixtures/cwds.tsv`, read by the wrapper's own `_agents_cwds` |
| `herdr agent list` | `fixtures/herdr.tsv` (session status: blocked, working, idle) |
| `sysctl`, `memory_pressure`, `pmset`, `notifyutil`, `launchctl` | fixed answers in `demo-stub.sh` |
| `kill` | a no-op: the demo never signals anything |
| `AGENTS_UID`, `AGENTS_SELF` | the fixture's uid 501, and a pid that isn't in the table (`AGENTS_TESTING=1`, the test harness's hook) |

`awake on|off|agents` and `open-term` are refused, because they would start real processes. Paths inside command lines in `ps.txt` use `/Users/NAME`; working directories in `cwds.tsv` and `herdr.tsv` use `@HOME@`, which becomes the demo home so the `CWD` column shows `~/myapp`.

To try the demo by hand, from the repo root in bash:

```bash
source docs/assets/tapes/demo-env.sh
agents
agents ps 1201
sbx -- cat ~/.ssh/id_ed25519
```

Without `DEMO_HOME` set, `demo-env.sh` makes the home with `mktemp` and leaves it there: when you're done, close that shell and `rm -rf "$(dirname "$DEMO_HOME")"` (run it in the demo shell first to see the path, `echo "$DEMO_HOME"`). Set `DEMO_HOME` before sourcing to choose the place yourself.

To change a shot, edit the fixtures or the tape, run `make screenshots`, and look at the result before committing it. Keep names generic (`myapp`, `api`, `web`, user `NAME`, host `devbox`); CI's no-hardcoded-paths scan reads this folder too.

## The SwiftBar menu, by hand

SwiftBar draws a native macOS menu, which VHS can't record, so there is no tape for it and no menu image in the README yet. To capture one by hand from the same fixtures, on macOS:

1. Write a demo plugin into an empty folder:

   ```bash
   bash docs/assets/tapes/swiftbar-demo.sh "$TMPDIR/swiftbar-demo"
   ```

2. In SwiftBar's settings, note your plugin folder, then choose the demo folder. After the second refresh (about 10 s) the title shows three sessions and `· 1 blocked`.
3. Open the menu, press `⌘⇧4` then `Space`, and click the menu to capture it with its shadow. Hover a session first to capture its submenu too.
4. Set SwiftBar's plugin folder back, and delete the demo folder.

Every action in the demo menu fails safe. SwiftBar runs a menu action in its own environment, without the plugin's `DEMO_HOME`, so an action that calls the demo `agents` directly stops at its `DEMO_HOME` check before doing anything. One that goes back through the demo plugin reaches the demo `agents`, which never signals and refuses keep-awake and new windows. Check the capture for anything from your own menu bar (other items, the clock) and crop it out.
