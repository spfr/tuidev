# Cheatsheet

Commands, keys and layouts in one place. Run `make help` for every Makefile target and `<command> --help` for any script.

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
| `gs` `ga` `gc` `gp` `gl` `gd` `gco` `gb` | `git status` / `add` / `commit` / `push` / `pull` / `diff` / `checkout` / `branch` |
| `lzd` | `lazydocker` (`--pack monitoring`) |
| `top`, `bottom` | `btm` (`--pack monitoring`) |
| `md`, `mdp FILE` | glow (`--extras`) |
| `help CMD` | `tldr` (`--extras`) |
| `sys`, `loc` | fastfetch / tokei (`--extras`) |
| `fcd`, `fif TEXT`, `fshow` | fzf: cd into a directory / grep files / browse commits |
| `mkcd DIR`, `serve`, `bench CMD` | mkdir+cd / `python3 -m http.server` / hyperfine |
| `ts-status`, `ts-ip`, `remote-status` | Tailscale and SSH status |
| `tui-update`, `tui-check` | `scripts/update.sh` / `update.sh --check` |
| `reload`, `zshconfig` | Re-source / edit `~/.zshrc` |

`sd`, `procs`, `dust` and `duf` keep their own names: they are never aliased over `sed`, `ps`, `du` or `df`, because their flags differ. Personal aliases go in `~/.zshrc.local`.

## AI CLIs

| Command | Runs | Pack |
|---------|------|------|
| `claude` | Claude Code, sandboxed by its own native settings | |
| `claude -w NAME` | Claude Code in its own worktree (`.claude/worktrees/NAME`) | |
| `codex` | Codex, sandboxed by its own native settings | |
| `oc` | `command opencode` | `opencode` |

```bash
claude --teammate-mode in-process       # agent team in one terminal instead of tmux panes
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
| `make sbx-test` | Check that the project is readable and `~/.ssh` is denied |

`sbx` runs binaries, not shell functions (`sbx -- opencode`, not `sbx -- oc`). Seatbelt doesn't nest, so plain `claude` already runs under its native sandbox; to run it under `sbx` instead, turn that off for the run: `sbx -- claude --settings '{"sandbox":{"enabled":false}}'`. Details: [sandboxing.md](sandboxing.md).

## Herdr (`--pack herdr`)

```bash
herdr                                   # attach locally (starts the server)
herdr machine add workbox --label workbox   # save an SSH node (interactive, once)
herdr --machine workbox agent list      # agents on a saved node: working / blocked / done
herdr --remote workbox                  # one-off thin client over SSH
herdr status                            # versions; server_binary_stale means restart when idle
herdr integration status                # after every upgrade: reinstall anything outdated
```

Herdr's prefix is `Ctrl+b`. Detach with `Ctrl+b q`. `workbox` is a placeholder: real hosts go in `~/.ssh/config.local`. Practices: [agent-workflows.md](agent-workflows.md#fleet-attention--herdr---pack-herdr).

## macOS hotkeys (desktop profile)

Rectangle owns `Ctrl+Alt` plus arrows and letters for window snapping (its "Recommended" layout).

| Keys | Action |
|------|--------|
| `Ctrl+Alt+←` / `→` / `↑` / `↓` | Snap window to a half |
| `Ctrl+Alt+Return` | Maximize |
| `Cmd+Shift+C` | Maccy clipboard history |
| ``Ctrl+` `` | Ghostty quick terminal (global) |

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

## Theming

```bash
make theme-list                   # themes; * marks the active one
make theme NAME=catppuccin-mocha  # apply (the default is tokyo-night)
scripts/theme.sh show tokyo-night # palette swatches
scripts/theme.sh apply tokyo-night --dry-run
```

Themes are written to tmux (`~/.config/tmux/theme.conf`, when `--pack tmux` is installed), Ghostty and Starship. The details are in [theming.md](theming.md).

## Makefile

```bash
make install-dry PROFILE=desktop   # preview an install
make check                         # health check for the installed profile
make test                          # tests for the installed profile (test-core / test-ui / test-all)
make update-check / make update    # preview / apply updates (update-all is non-interactive)
make update-migrations             # pending one-shot migrations only
make update-security               # Tailscale, SSH permissions, Seatbelt drift
make lint                          # shellcheck every shell script
make validate-configs              # JSON / TOML / Lua / shell syntax
make test-lib                      # unit harnesses
make check-links                   # relative links in every tracked .md
make ci-test                       # lint + validate + links + unit tests
make container-test                # core-tag tests in an Alpine container
make sandbox-up / sandbox-down     # Tier 2 container runtime
```

Updates and migrations are covered in [updating.md](updating.md).
