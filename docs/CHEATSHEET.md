# Cheatsheet

tmux-first reference for sessions, keybindings, and daily commands. Print this.

---

## Sessions (tmux)

All wrappers create **named sessions** with attach-or-create semantics.
Default name is the current directory basename.

| Command              | What it does                                                    |
|----------------------|------------------------------------------------------------------|
| `work [name]`        | Bare tmux session — one pane                                     |
| `dev [name]`         | 3-column: nvim (55%) \| agent (25%) \| runner (20%)              |
| `ai [name]`          | nvim (60%) + 2 stacked agent panes (40%)                         |
| `ai-single [name]`   | nvim + 1 agent pane                                              |
| `ai-triple [name]`   | nvim (55%) + 3 stacked agent panes (45%)                         |
| `fullstack [name]`   | 5-tab full-stack layout                                          |
| `multi [name]`       | Dev + Monitor + Git tabs                                         |
| `remote [name]`      | Minimal remote layout (nvim + terminal)                          |
| `agents [name]`      | claude + codex + gemini in 3 panes                               |
| `tls`                | List sessions                                                    |
| `tk [name]`          | Kill named session                                               |
| `tka`                | Kill all sessions (`tmux kill-server`)                           |

> Legacy `ta` / `tdev` / `tai` / `tai-triple` still work but emit a one-time deprecation notice. Use the canonical names above.

---

## tmux Keybindings

**Prefix:** `Ctrl-a` — press, release, then the key.

### Panes

| Chord              | Action                        |
|--------------------|-------------------------------|
| `C-a \|`           | Split vertically (pane right) |
| `C-a -`            | Split horizontally (pane below) |
| `C-a h / j / k / l`| Focus left / down / up / right |
| `C-a H / J / K / L`| Resize pane by 5 cells         |
| `C-a z`            | Zoom pane (toggle fullscreen)  |
| `C-a x`            | Kill pane                      |

### Windows & sessions

| Chord              | Action                        |
|--------------------|-------------------------------|
| `C-a c`            | New window                    |
| `C-a 1` … `C-a 9`  | Switch to window N            |
| `C-a ,`            | Rename window                 |
| `C-a $`            | Rename session                |
| `C-a d`            | Detach                        |
| `C-a r`            | Reload `~/.config/tmux/tmux.conf` |

### Copy mode (vi keys)

| Chord              | Action                        |
|--------------------|-------------------------------|
| `C-a [`            | Enter copy mode               |
| `v`                | Begin selection               |
| `C-v`              | Toggle rectangle selection    |
| `y`                | Yank to clipboard (pbcopy)    |
| `/` then text      | Search forward                |
| `?` then text      | Search backward               |
| `n` / `N`          | Next / previous match         |
| `q` or `Esc`       | Exit copy mode                |

---

## AI CLIs

| Alias | Tool           | Purpose                       |
|-------|----------------|-------------------------------|
| `cc`  | Claude Code    | Anthropic, primary            |
| `cx`  | Codex CLI      | OpenAI                        |
| `gem` | Gemini CLI     | Google, optional              |
| `oc`  | OpenCode       | Open-source, multi-model      |

All four auto-route through `sbx` with the `strict` profile once the
sandbox pack is installed. Escape hatches:

```bash
sbx --profile off -- cc          # explicit one-shot bypass
CC_NO_SANDBOX=1 cc               # env-var bypass honored by the wrappers
```

### Claude agent teams

```bash
claude                           # in-process teammates (any terminal)
ai myproject                     # tmux split-pane layout (nvim + 2 agents)
claude --teammate-mode tmux      # split-pane agent teams
```

---

## Sandbox (`sbx`)

| Invocation                           | Effect                                          |
|--------------------------------------|-------------------------------------------------|
| `sbx -- <cmd>`                       | Run under default `strict` profile              |
| `sbx --profile standard -- <cmd>`    | Adds :80, :22, :9418 (for `npm ci`, `git push`) |
| `sbx --profile off -- <cmd>`         | No sandbox — documented escape hatch            |
| `sbx --project <dir> -- <cmd>`       | Override project root (default: `$PWD`)         |
| `sbx --dry-run -- <cmd>`             | Print the `sandbox-exec` command, don't run     |
| `CC_NO_SANDBOX=1 cc`                 | Bypass via env var                              |

Credentials stay denied in every profile: `~/.ssh`, `~/.aws`,
`~/.gnupg`, `~/Library/Keychains`, `~/.config/gh`, `~/.docker`,
`~/.kube`, `~/.netrc`. See [`sandboxing.md`](sandboxing.md).

---

## Neovim (LazyVim)

Leader is `Space`. Press `Space` and wait — which-key shows the menu.

| Chord          | Action                                   |
|----------------|------------------------------------------|
| `<leader>ff`   | Find files                               |
| `<leader>fg`   | Live grep                                |
| `<leader>fr`   | Recent files                             |
| `<leader>fb`   | Switch buffer                            |
| `<leader>e`    | Toggle file explorer                     |
| `<leader>gg`   | Open lazygit                             |
| `<leader>ca`   | Code actions                             |
| `<leader>cr`   | Rename symbol                            |
| `<leader>cf`   | Format                                   |
| `<leader>qq`   | Quit all                                 |
| `gd` / `gr`    | Go to definition / references            |
| `K`            | Hover docs                               |
| `[d` / `]d`    | Prev / next diagnostic                   |
| `Ctrl-/`       | Toggle floating terminal                 |

Full nvim intro: [`NEOVIM_QUICKSTART.md`](NEOVIM_QUICKSTART.md).

---

## Modern CLI replacements

| Command | Replaces | Notes                                    |
|---------|----------|------------------------------------------|
| `eza`   | `ls`     | `ls`/`ll`/`la`/`lt` aliased with icons + git |
| `bat`   | `cat`    | Syntax highlighting, paging              |
| `rg`    | `grep`   | `rg "pat" -A 3 -B 3`, `--type js`        |
| `fd`    | `find`   | `fd -e js`, `fd -t d`, `fd -H`           |
| `fzf`   | —        | `Ctrl-T` files, `Ctrl-R` history, `Alt-C` cd |
| `zoxide`| `cd`     | `z partial-name`, `zi` interactive       |
| `btm`   | `top`    | aliased as `top` and `bottom`            |

---

## Git & lazygit

```bash
lg            # open lazygit
gs            # git status
ga / gc       # git add / commit
gp / gl       # git push / pull
gd            # git diff
gco / gb      # git checkout / branch
```

Inside lazygit:

| Key        | Action                  |
|------------|-------------------------|
| `1` … `5`  | Jump to panel           |
| `Space`    | Stage / unstage         |
| `a`        | Stage all               |
| `c`        | Commit                  |
| `P`        | Push                    |
| `p`        | Pull                    |
| `e`        | Edit file               |
| `d`        | Discard                 |
| `?`        | Help                    |
| `q`        | Quit                    |

---

## Makefile

The Makefile covers install, update, health checks, linting, and Docker
testing. Run `make help` for the authoritative list. Frequent targets:

```bash
make install            # install everything
make check              # health check
make test               # full test suite
make lint               # shellcheck
make validate-configs   # KDL / TOML / shell syntax
make update             # interactive update
make sbx-test           # verify sandbox blocks creds, allows project writes
```

---

## Zellij (opt-in pack)

These apply only after `./install.sh --pack zellij`. Namespaced under
`z*` (`zdev`, `zwork`, `zai`, …) so they never shadow the tmux defaults.
For install troubleshooting see
[`ZELLIJ_TROUBLESHOOTING.md`](ZELLIJ_TROUBLESHOOTING.md).

### Zellij sessions

| Command          | Layout                                          |
|------------------|-------------------------------------------------|
| `zwork [name]`   | Bare named session                              |
| `zdev [name]`    | 3-column: nvim \| agent \| runner               |
| `zai [name]`     | nvim + 2 AI agent terminals                     |
| `zai-single`     | nvim + 1 terminal                               |
| `zai-triple`     | nvim + 3 agents                                 |
| `zfullstack`     | 5-tab full-stack setup                          |
| `zmulti`         | Dev + Monitor + Git tabs                        |
| `zremote`        | Minimal remote layout                           |

### Zellij keybindings

| Chord            | Action                          |
|------------------|---------------------------------|
| `Alt-n`          | New pane                        |
| `Alt-h/j/k/l`    | Navigate panes                  |
| `Alt-=` / `Alt--`| Grow / shrink pane              |
| `Alt-p`          | Pane mode                       |
| `Ctrl-t`         | Tab mode                        |
| `Ctrl-s`         | Scroll / search mode            |
| `Ctrl-o`         | Session mode (detach with `d`)  |
| `Ctrl-g`         | Locked mode — passthrough keys  |
| `Ctrl-q`         | Quit                            |
