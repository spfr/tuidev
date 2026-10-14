# Screenshot tapes

The images in [docs/assets/](..) are rendered from the [VHS](https://github.com/charmbracelet/vhs) tapes here, against made-up data, so they can be re-made after a UI change and never show anything from the machine that rendered them. How to run them, and when, is in [engineering.md](../../engineering.md#screenshots).

```bash
make screenshots                    # every tape
make screenshots TAPES="agents"     # one or more by name
```

| Tape | Image | Shows |
|------|-------|-------|
| `agents.tape` | `agents.png` | `agents` over the fixture process table (the README hero) |
| `sbx.tape` | `sbx.png` | `sbx` reading the project, refused a credential and the CLI's settings |
| `social-preview.tape` | `social-preview.png` | The 1280×640 Open Graph card; its text is in `social-card.sh` |
| `theme.tape` | | Shared settings: the Tokyo Night palette and the Ghostty font, sourced by the others |

## The demo environment

`scripts/screenshots.sh` gives each tape a throwaway home in `$TMPDIR` and deletes it afterwards. Each tape sources `demo-env.sh`, hidden, which:

- builds that home with `demo-setup.sh`: three projects (`myapp`, `api`, `web`), a fake `~/.ssh/id_ed25519` for `sbx` to refuse, a `~/.claude/settings.json`, and the state `agents` reads (a keep-awake record and a Herdr socket);
- sets `HOME` to it and draws a two-line prompt shaped like the shipped Starship one, without Starship (which would show the real user, host and git state);
- puts `bin/agents` (the demo wrapper) and the repo's `bin/sbx` first on `PATH`.

`sbx` is the real one. The demo `agents` is the real `bin/agents`, sourced, with these swapped in:

| Real | Demo |
|------|------|
| `ps`, `lsof` | `fixtures/ps.txt`, `fixtures/cwds.tsv`, `fixtures/listeners.txt` |
| `herdr agent list` | `fixtures/herdr.tsv` (session status: blocked, working, idle) |
| `sysctl`, `memory_pressure`, `pmset`, `notifyutil`, `launchctl` | fixed answers in `demo-stub.sh` |
| `kill` | a no-op: the demo never signals anything |
| `AGENTS_UID`, `AGENTS_SELF` | the fixture's uid 501, and a pid that isn't in the table (`AGENTS_TESTING=1`, the test harness's hook) |

`awake on|off|agents` and `open-term` are refused, because they would start real processes. Paths inside command lines in `ps.txt` use `/Users/NAME`; working directories in `cwds.tsv` and `herdr.tsv` use `@HOME@`, which the stub replaces with the demo home so the `CWD` column shows `~/myapp`.

To try the demo by hand, from the repo root in bash:

```bash
source docs/assets/tapes/demo-env.sh
agents
agents ps 1201
sbx -- cat ../.ssh/id_ed25519
```

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

Every action in the demo menu is harmless: kills go to the demo `agents`, which never signals, and keep-awake and new-window actions are refused. Check the capture for anything from your own menu bar (other items, the clock) and crop it out.
