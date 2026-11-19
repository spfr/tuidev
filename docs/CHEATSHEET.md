# Cheatsheet

Look commands and keys up here: tmux, shell aliases, `sbx`, `secret`, `agents`, Herdr and `tuidev`. Run `tuidev` for the searchable palette and `<command> --help` for any command; in a clone, `make help` lists the Makefile targets.

## tmux (`--pack tmux`)

tmux is optional now (in the `remote` profile, or add it yourself with `--pack tmux`). `.zshrc` ships one attach-or-create helper:

| Command | Default name | Effect |
|---------|--------------|--------|
| `t [NAME]` | `main` | Attach to a tmux session, creating it if it doesn't exist. Inside tmux it switches client instead of nesting. |
| `tls` | | List sessions |

tmux turns `.` and `:` in session names into `_`.

## tmux keys (`--pack tmux`)

Prefix: `Ctrl+a`. Press it, release, then press the key. Press `Ctrl+a Ctrl+a` to send a literal `Ctrl+a`, for example to jump to the start of a shell line.

| Keys | Action |
|------|--------|
| `\|` / `-` | Split right / split below (in the current directory) |
| `h` `j` `k` `l` | Focus left / down / up / right |
| `H` `J` `K` `L` | Resize by 5 cells |
| `o` / `z` / `x` | Next pane / zoom toggle / kill pane |
| `Space` | Cycle pane layouts |
| `c` / `n` / `p` / `1`–`9` | New window / next / previous / window N (windows start at 1) |
| `,` / `$` | Rename window / session |
| `s` / `w` | Session tree / window tree |
| `d` | Detach (the session keeps running) |
| `g` | lazygit in a 90% popup, in the pane's directory |
| `r` | Reload `~/.config/tmux/tmux.conf` |
| `Ctrl+s` / `Ctrl+r` | Save / restore sessions (tmux-resurrect; continuum also saves every 15 min) |
| `I` | Install TPM plugins |
| `?` | List every binding |

Copy mode (vi keys): `Ctrl+a [` enters it. `v` starts a selection, `Ctrl+v` toggles rectangle mode, `y` copies to the system clipboard (pbcopy, wl-copy or xclip, with OSC 52 over SSH), `/` and `?` search, `n` and `N` jump between matches, and `q` exits. A mouse drag copies too.

A window whose agent rings the bell, or has new activity, is flagged in the status bar. Killing a session's last window moves you to another session instead of exiting tmux.

## Shell

<img src="assets/shell.png" width="720" alt="A terminal in a demo repo under the Starship prompt: ll src lists four Python files with icons and a git status column (new, staged, modified), rg finds three highlighted TODO matches across files, and git diff shows a change in delta, with line numbers and the changed words highlighted.">

| Keys | Action |
|------|--------|
| `Up` / `Down` | History entries that start with what you have typed |
| `Ctrl+r` | atuin history search (zsh's own search if atuin is absent) |
| `Ctrl+t` / `Alt+c` | fzf: insert a file / cd into a directory |
| `Ctrl+a`* / `Ctrl+e` | Start / end of line (*press `Ctrl+a` twice inside tmux) |
| `Ctrl+u` / `Ctrl+k` / `Ctrl+w` | Delete to start / to end / previous word |
| `Alt+b` / `Alt+f` | Word back / forward (Option acts as Alt in Ghostty) |

Line editing uses the Emacs keymap. Put `bindkey -v` in `~/.zshrc.local` for vi mode.

### Aliases and functions

| Command | Runs |
|---------|------|
| `v`, `vi`, `vim` | `nvim` with `--pack nvim`; without it, `vi` and `vim` are the system commands and `v` is undefined |
| `ls`, `ll`, `la`, `lt`, `tree` | `eza --icons=auto` (long, all, tree variants with git status) |
| `cat` | `bat` |
| `cd` | `z` (zoxide) in interactive shells; `zi` picks interactively |
| `lg` | `lazygit` |
| `hunk diff`, `hunk show` | review the working tree or a commit in hunk (`--pack hunk`); `--watch` reloads on change |
| `gs` `ga` `gc` `gp` `gl` `gd` `gco` `gb` | `git status` / `add` / `commit` / `push` / `pull` / `diff` / `checkout` / `branch` |
| `top` | `btm` at a terminal (`--pack monitoring`) |
| `agents`, `agents watch` | agent sessions, stale processes, hogs; `agents why` (verdicts), `agents reap` (what is safe to stop; `--all` the rest), `agents awake on 2h` (`--pack monitoring`) |
| `md`, `mdp FILE` | glow (`--extras`) |
| `help CMD` | `tldr` (`--extras`) |
| `loc` | tokei (`--extras`) |
| `fcd`, `fif TEXT`, `fshow` | fzf: cd into a directory / grep files / browse commits |
| `mkcd DIR`, `bench CMD` | mkdir+cd / hyperfine |
| `ts-status`, `ts-ip`, `remote-status` | Tailscale and SSH status |
| `tui-update`, `tui-check` | `scripts/update.sh` / `tuidev update --check` |
| `reload`, `zshconfig` | Re-source / edit `~/.zshrc` |

`procs` and `dust` keep their own names: they are never aliased over `ps` or `du`, because their flags differ. Personal aliases go in `~/.zshrc.local`.

## AI CLIs

| Command | Runs | Pack |
|---------|------|------|
| `claude` | Claude Code, sandboxed by its own native settings | |
| `claude -w NAME` | Claude Code in its own worktree (`.claude/worktrees/NAME`) | |
| `codex` | Codex, sandboxed by its own native settings | |

```bash
CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 claude   # agent teams, off by default
```

`claude` and `codex` are no longer routed through wrapper functions — plain binaries, confined by the sandbox settings each CLI ships with. Details: [sandboxing.md](sandboxing.md). Setup, agent teams and the instruction files each CLI reads: [agent-workflows.md](agent-workflows.md).

## Sandbox (`sbx`)

`sbx` is a general-purpose Seatbelt wrapper, not tied to any AI CLI — use it to sandbox any command.

| Invocation | Effect |
|------------|--------|
| `sbx -- CMD` | Run a binary under `strict`: TCP 443, DNS and loopback only |
| `sbx --profile standard -- CMD` | Also TCP 80, 22 and 9418 (package mirrors, git over ssh) |
| `sbx --profile off -- CMD` | No sandbox |
| `sbx --project DIR -- CMD` | Writable project directory (default: `$PWD`) |
| `sbx --allow-herdr -- CMD` | `strict`, plus access to the herdr socket |
| `sbx --dry-run -- CMD` | Print the `sandbox-exec` command without running it |
| `make sbx-test` (in a clone) | Check that the project is readable and `~/.ssh` is denied |

`sbx` runs binaries, not shell functions or aliases. Seatbelt doesn't nest, so plain `claude` already runs under its native sandbox; to run it under `sbx` instead, turn that off for the run: `sbx -- claude --settings '{"sandbox":{"enabled":false}}'`. Details: [sandboxing.md](sandboxing.md).

## Secrets (`secret`)

API tokens in the macOS Keychain (or libsecret, or `pass`), never in a dotfile. The value is read from a hidden prompt or stdin, never from the command line.

| Command | Effect |
|---------|--------|
| `secret set NAME` | Store a value (hidden prompt; `pbpaste \| secret set NAME` works too) |
| `secret run -n NAME -- CMD` | Run CMD with NAME in its environment only (repeat `-n`; `--all` for every secret) |
| `secret get NAME` | Print it, for `$(...)` |
| `eval "$(secret export A B)"` | Export into this shell and everything it starts, agents included |
| `secret ls` / `secret rm NAME` | List names / delete one |
| `secret scan` | Token-looking `export` lines in your shell files (name and line, never the value) |
| `secret import --dry-run --remove FILE` | What `import --remove` would move out of FILE; drop `--dry-run` to do it |

Details: [secrets.md](secrets.md).

## Herdr (`--pack herdr`)

```bash
herdr                                   # attach locally (starts the server)
herdr machine add workbox               # save an SSH node; pick its session (once)
herdr machine status                    # saved nodes reachable? (no prompts)
herdr --machine workbox agent list      # agents on a saved node: working / blocked / done
herdr --remote workbox --session NAME   # one-off thin client over SSH
herdr session list                      # sessions on this machine (one server each)
herdr session attach NAME               # join a named session (e.g. from a phone over SSH)
herdr session stop NAME                 # stop a session: kills its panes
herdr status                            # versions; server_binary_stale: the new version starts with the next server restart (fine meanwhile)
herdr integration status                # after every upgrade: reinstall anything outdated
```

Other machines, over ssh (`--pack monitoring`; [remote.md](remote.md#remote-feels-local-ports-links-and-files)):

```bash
agents board                            # every session on every machine, by who needs you; ? lists its keys (Herdr: prefix+space)
agents map                              # what runs where on every machine; enter go, ctrl-k stop, ctrl-s sweep (Herdr: prefix+m)
agents ports [--pick]                   # what listens where, here and on your machines (Herdr: prefix+shift+o)
agents forward open workbox 5173        # that port, here, in your browser
agents forward                          # the forwards; close --all | --dead | PORT
agents push -m workbox FILE             # into its drop folder; the path is copied
agents open workbox /PATH/report.html   # fetch one file and open it here
agents link                             # the watcher behind Ctrl-click on a remote localhost link
agents herdr                            # tab names and sidebar roll-ups: each tab's label and whose it is
agents herdr reset                      # every tab a sync named gets its number back (AGENTS_HERDR_NAMES=0 keeps it so)
agents herdr reset TAB_ID               # one tab back to auto-naming, one you renamed too (ids: agents herdr)
```

Herdr's phone app, through herdr-core (`--pack herdr-core`; [remote.md](remote.md#herdrs-phone-app-agents-hc)):

```bash
agents hc                               # is herdr-core running, and in your desktop login?
agents hc run claude                    # in a Herdr pane: the agent, hosted in herdr-core, listed on the phone
agents hc attach NAME                   # come back to one; ctrl+\ detaches and leaves it running
claude                                  # with AGENTS_HC_AUTO=1, in a Herdr pane: hosted in herdr-core by itself
agents hc mirror                        # experimental (AGENTS_HC_MIRROR=1): each agent pane and its mirror in herdr-core
agents hc mirror fit                    # the focused pane takes its size back from a phone that still shows it (focusing does it too)
agents hc mirror end                    # end every mirror; the agents stay in their panes
agents hc mirror off                    # in a Herdr pane: no mirror for this one (on brings it back; PANE for another)
agents hc ls                            # what the phone lists from here, and the agent panes it cannot reach
agents hc up --restart                  # at the Mac, not over SSH: replace a core outside the desktop login (ends its terminals)
```

Herdr's prefix is `Ctrl+b`. Detach with `Ctrl+b q`. Plain `herdr` is the `default` session; keep one per machine and split projects into workspaces. Upgrade with `herdr update --handoff` from outside Herdr: the server keeps its panes. A server a systemd unit runs upgrades with `tuidev update --packages` (the unit's reload hands over), never `--handoff`. `workbox` is a placeholder: real hosts go in `~/.ssh/config.local`. Practices: [agent-workflows.md](agent-workflows.md#fleet-attention--herdr---pack-herdr).

## macOS hotkeys (desktop profile)

Rectangle owns `Ctrl+Alt` plus arrows and letters for window snapping (its "Recommended" layout).

| Keys | Action |
|------|--------|
| `Ctrl+Alt+←` / `→` / `↑` / `↓` | Snap window to a half |
| `Ctrl+Alt+Return` | Maximize |
| ``Ctrl+` `` | Ghostty quick terminal (global) |
| `Cmd+P` | tuidev palette in Herdr (sends `ctrl+b a`; outside Herdr the app in front gets `ctrl+b` and `a`; `keybind = cmd+p=unbind` turns it off) |

Ghostty keeps its macOS defaults (`Cmd+T`, `Cmd+D`, and so on) and adds `Ctrl+Shift+T/W/D/N/C/V` for Linux habits.

## Neovim (`--pack nvim`)

| Keys | Action |
|------|--------|
| `Space Space` / `Space f f` | Find files |
| `Space /` | Grep the project |
| `Space ,` / `Space f r` | Buffers / recent files |
| `Space e` | File explorer |
| `Space g g` | lazygit |
| `g d` / `g r` / `K` | Definition / references / hover |
| `Space c a` / `Space c r` / `Space c f` | Code action / rename / format |
| `Ctrl+/` | Floating terminal |

The full guide is in [nvim.md](nvim.md).

## Vim (`--pack vim`)

| Keys | Action |
|------|--------|
| `Space Space` | Find files (fzf) |
| `Space /` / `Space *` | Grep the project / the word under the cursor (ripgrep, into quickfix) |
| `Space b` / `Space r` | Buffers / recent files |
| `Space e` | netrw file explorer |
| `gcc` / `gc{motion}` | Toggle comment |
| `]q` / `[q`, `]b` / `[b` | Next/previous quickfix entry, buffer |

The full guide is in [vim.md](vim.md).

## Theming

```bash
tuidev theme                   # themes; * marks the active one
tuidev theme catppuccin-mocha  # apply (the default is tokyo-night)
tuidev theme show tokyo-night  # palette swatches
tuidev theme apply tokyo-night --dry-run
```

Themes are written to tmux (`~/.config/tmux/theme.conf`, when `--pack tmux` is installed), Ghostty and Starship. The details are in [theming.md](theming.md).

## tuidev

```bash
tuidev                             # the palette: everything here, searchable (Herdr: prefix+a)
tuidev install --pack NAME         # add a pack; --dry-run previews
tuidev update                      # the latest release, its migrations and configs (Herdr: prefix+u asks first)
tuidev update --check | --packages | --all | --rollback
tuidev latest [on|off]             # the latest release known; the daily check on or off
tuidev whatsnew [FROM]             # this release's changelog, or all since FROM
tuidev md [FILE]                   # read Markdown in the pager (rendered with glow from --extras)
tuidev check | perf | disk         # health check and the two audits
tuidev check --fix [--dry-run]     # repair what runs (jobs, tuidev's files, the manifest), then check again
agents doctor [--fix]              # are the sampler, the memory guard and the hooks' agents working (--pack monitoring)
tuidev theme [NAME]                # list themes, or apply one
tuidev uninstall                   # remove what the manifest records
```

## Makefile

In a clone. Each of the first rows has a `tuidev` twin above.

```bash
make install-dry PROFILE=desktop   # preview an install
make check                         # health check for the installed profile
make test                          # tests for the installed profile (test-core / test-ui / test-all)
make update-check / make update    # preview / apply updates (update-all is non-interactive)
make update-migrations             # pending one-shot migrations only
make update-security               # Tailscale, SSH permissions, Seatbelt drift
make perf | perf-fix               # performance audit; then the fixes that need no root
make disk | disk-fix | disk-agent  # what dev tools left on disk, grouped by what to do; a plan with one question each; an agent's plan
make lint                          # shellcheck every shell script
make validate-configs              # JSON / TOML / Lua / shell syntax
make test-lib                      # unit harnesses
make check-links                   # relative links in every tracked .md
make ci-test                       # lint + validate + links + unit tests
make container-test                # core-tag tests in an Alpine container
make sandbox-up / sandbox-down     # Tier 2 container runtime
```

Updates and migrations are covered in [updating.md](updating.md).
