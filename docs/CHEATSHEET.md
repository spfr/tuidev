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
| `agents [name]`      | claude + codex in 2 panes (needs --pack ai-clis)                 |
| `worktrees [name]`   | One git worktree per agent, one window each — default `<repo>-wt` |
| `tls`                | List sessions                                                    |
| `tk [name]`          | Kill named session                                               |
| `tka`                | Kill all sessions (`tmux kill-server`)                           |

> Legacy `ta` / `tdev` / `tai` / `tai-triple` still work but emit a one-time deprecation notice. Use the canonical names above.

---

## Best usage patterns

Quick answers to "what do I actually run, day to day."

| Situation | Do this |
|-----------|---------|
| Start work | `work` / `dev` / `ai` / `agents` — attach-or-create, pick the layout you need |
| See what's running | `tls` |
| Clean up | `tk NAME` (one session) or `tka` (kill server) |
| Parallel agents | `worktrees -n 3 --cmd cc`, then `worktrees --clean` when merged — see [Worktree-per-agent](#worktree-per-agent-worktrees) above |
| Run an AI CLI | `cc` (sbx-wrapped, `strict` profile, by default) |
| One-shot sandbox bypass | `CC_NO_SANDBOX=1 cc` |
| Need network (npm, git push, PyPI) | `sbx --profile standard -- <cmd>` |
| See/change theme | `make theme-list`, `make theme NAME=...` — fresh installs ship themed as of 2.2.0 |
| Check for updates | `make update-check` (weekly is plenty) |
| Apply updates | `make update-all` — migrations run automatically, no separate step |
| Something feels off | `make check` after any failed install step, manual config edit, or unexpected error |
| Working from a remote box | Tailscale hostname + a named tmux session + `remote` for narrow terminals; personal hostnames only in `~/.ssh/config.local` (gitignored), never in this repo |

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
| `oc`  | OpenCode       | Open-source, multi-model      |

Aliases ship in the opt-in `--pack ai-clis`; all three auto-route through `sbx`
(`strict` profile) when `--pack sandbox` is present. Escape hatches:

```bash
sbx --profile off -- cc          # explicit one-shot bypass
CC_NO_SANDBOX=1 cc               # env-var bypass honored by the wrappers
```

### Fleet attention — Herdr (opt-in `--pack herdr`)

```bash
herdr                    # attach locally (first attach starts the server)
herdr --remote workbox   # thin client over SSH (placeholder host)
herdr server             # headless server; clients attach with `herdr`
herdr agent list         # who is working / blocked / done — scriptable
herdr status             # local client + server health
```

Prefix is `ctrl+b` (tmux is `ctrl+a`). Installs via Homebrew only; with no
formula the pack prints the official installer command rather than piping a
remote script into your shell. tmux stays the default for `work` / `dev` / `ai`.

> **Never nest.** If `HERDR_ENV=1` you are already inside a Herdr pane — use
> `herdr agent list` or the socket API, not the TUI. Agents should never script
> the TUI. See [`agent-workflows.md`](agent-workflows.md).

### Claude agent teams

```bash
claude                           # in-process teammates (any terminal)
ai myproject                     # tmux split-pane layout (nvim + 2 agents)
claude --teammate-mode tmux      # split-pane agent teams
```

---

## Worktree-per-agent (`worktrees`)

One git worktree per agent, one tmux window per worktree, so parallel agents
never fight over the index or each other's half-finished edits. Window `main`
stays on the original repo for review and merging.

```bash
worktrees                          # 2 worktrees (agent/1, agent/2), session "<repo>-wt"
worktrees feat -n 3 --cmd cc       # session "feat", 3 agents each running cc
worktrees -n 2 --cmd codex --branch-prefix wip/
worktrees --base develop -n 2      # branch off develop instead of current HEAD
worktrees --list                   # path, branch, dirty?, commits ahead
worktrees --clean                  # remove only clean, fully-merged worktrees
make quick-worktrees N=3 CMD=cc    # same thing from the Makefile
```

| Flag                | Meaning                                                |
|---------------------|--------------------------------------------------------|
| `-n N`              | Number of worktrees/agents (default 2, max 8)          |
| `--branch-prefix P` | Branch prefix (default `agent/` → `agent/1`, `agent/2`)|
| `--base REF`        | Branch off `REF` (default: current branch)             |
| `--cmd CMD`         | Command to run in each worktree window (default: shell)|
| `--list`            | Status of this repo's agent worktrees                  |
| `--clean`           | Remove clean + fully-merged worktrees, keep the rest — "merged" is relative to the current branch (or `--base`) |

Worktrees live at `../<repo>-wt/<branch>` (slashes become dashes), never inside
the repo. The default session name is `<repo>-wt`, so two different repos get
two different sessions. Re-running attaches and reuses existing worktrees.
`--clean` **never** removes a worktree with uncommitted changes or with commits
not yet in the base branch — it prints what is blocking so you can merge or
cherry-pick first. It judges merged-ness against the main checkout's *current*
branch unless you pass `--base REF`, so run it from the branch the agents forked
off; work merged somewhere else reads as unmerged and is kept (the safe
direction, but surprising if you switched branches in between).

> **A worktree isolates git state only.** Ports collide (give each worktree its
> own `PORT`), `node_modules` / `.venv` / `target` are not shared or copied
> (each worktree needs its own install), gitignored files like `.env` do not
> follow the worktree (copy or symlink them in), and one shared dev database or
> cloud project is still shared.

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

## Theming

One palette (`configs/themes/<name>/palette.toml`) drives tmux, Ghostty and
Starship. Neovim is out of scope — LazyVim owns its colorscheme.

```bash
./scripts/theme.sh list                 # available themes, active marked with *
./scripts/theme.sh show tokyo-night     # print the palette (swatches on a TTY)
./scripts/theme.sh apply catppuccin-mocha
./scripts/theme.sh apply tokyo-night --dry-run
make theme-list                         # same as `theme.sh list`
make theme NAME=catppuccin-mocha        # same as `theme.sh apply` (default: tokyo-night)
```

Shipped: `tokyo-night` (default), `catppuccin-mocha`. Apply writes
`tuidev-theme` managed blocks — your edits outside the markers survive — and
reloads a running tmux server so open panes re-theme immediately.

A fresh `./install.sh` run auto-applies `tokyo-night` at the end, so a stock
install ships pre-themed with no manual step. Use `theme.sh apply` /
`make theme NAME=...` to switch themes afterward.

Two things that make `apply` skip starship rather than corrupt it: the
`tuidev-starship` block must already exist (run `./install.sh` first), and
`palette = "tuidev"` must sit at the **top level** of `~/.config/starship.toml`,
above the first `[table]`. It prints the exact fix in both cases. The theme
block is always moved back to the end of a file if something else was appended
after it, since the last definition wins.

Adding a theme: copy a `palette.toml`, keep all 26 contract keys. See
[`theming.md`](theming.md).

---

## Updating & migrations

```bash
make update-check         # preview: packages, pending migrations, config drift
make update               # interactive menu
make update-packages      # brew upgrade, scoped to your active packs
make update-configs       # pending migrations, then re-apply managed blocks
make update-migrations    # only the one-shot migrations
make update-all           # non-interactive: packages + configs + repo
make update-security      # audit Tailscale + SSH perms + Seatbelt drift
```

Every mode honors `--dry-run` on `./scripts/update.sh`. Migrations are
timestamped scripts in `scripts/migrations/`, run **at most once per machine**;
applied ids land in `~/.config/tuidev/migrations`. A failure stops the run and
stays unrecorded, so the next update retries it.

`~/.config/tuidev/manifest` records what was actually installed (one
`<kind> <value>` per line — `grep '^formula '` it). `./uninstall.sh` purges only
those records, so a `ripgrep` you had before this repo survives. See
[`updating.md`](updating.md).

---

## Remote & always-on nodes

```bash
tailscale up && tailscale status   # bring the node onto the tailnet
ssh devbox                         # placeholder host — see below
tmux attach -t main                # your session survived the disconnect
work myproject                     # or create a fresh named session
```

Detach with `C-a d`; the session keeps running. mosh for flaky links
(`--pack mosh`). iOS clients: Blink, Moshi.

A cheap always-on box (Raspberry Pi, NUC, VM) is a node, not a second product.
`--profile remote` installs there; on Debian/arm64 the core pack falls back to
`apt-get` because Homebrew has no build for it, skipping what your release
doesn't package and printing the upstream install command instead.

> `devbox` / `workbox` are **placeholders**. Real hostnames, mDNS names, and
> usernames go in `~/.ssh/config.local` — never in this repo. The shipped SSH
> snippet `Include`s `~/.ssh/config.local*` unconditionally.

Full setup: [`remote.md`](remote.md). Fleet control: [`agent-workflows.md`](agent-workflows.md).

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
| `http`  | `curl`   | HTTPie with pretty output                |

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
make install            # interactive (desktop on macOS, minimal on Linux)
make install-dry PROFILE=desktop   # preview every mutation, change nothing
make check              # health check against the installed profile
make test               # tests for the active profile   (test-core / test-ui / test-all)
make lint               # shellcheck install/scripts/lib/tmux/packs/bin
make validate-configs   # KDL / TOML / Lua / JSON syntax
make ci-test            # what CI runs: core tests + lint
make update             # interactive, profile-aware update
make sbx-test           # verify sandbox blocks creds, allows project writes
make theme NAME=…       # re-theme tmux / Ghostty / Starship
make quick-worktrees    # one worktree + tmux window per agent (N=, CMD=)
make help               # authoritative target list
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
