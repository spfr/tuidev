# Terminal Navigation Guide

> Fix keyboard issues and learn the pane-navigation keys you need.

---

## tmux (primary)

Prefix is `Ctrl+a`. Release the prefix, then press the action key.

### Pane navigation

| Keys | Action |
|------|--------|
| `Ctrl+a \|` | split pane vertically (new pane right) |
| `Ctrl+a -` | split pane horizontally (new pane below) |
| `Ctrl+a h/j/k/l` | move left/down/up/right |
| `Ctrl+a o` | cycle to next pane |
| `Ctrl+a z` | zoom (toggle) current pane |
| `Ctrl+a x` | close current pane |
| `Ctrl+a Space` | cycle pane layouts |

### Session & window management

| Keys | Action |
|------|--------|
| `Ctrl+a d` | detach (session keeps running) |
| `Ctrl+a c` | new window |
| `Ctrl+a n` / `p` | next / previous window |
| `Ctrl+a 0-9` | jump to window by number |
| `Ctrl+a ,` | rename window |
| `Ctrl+a $` | rename session |
| `Ctrl+a s` | pick session from list |
| `Ctrl+a ?` | show every binding |

### Copy / scroll mode

| Keys | Action |
|------|--------|
| `Ctrl+a [` | enter scroll/copy mode |
| `v` / `y` | start selection / yank (vi keys) |
| `q` | exit copy mode |

### Shell wrappers

```bash
work [name]        # attach or create bare session (default: $PWD basename)
dev [name]         # nvim | agent | runner
ai [name]          # nvim + 2 agents
ai-triple [name]   # nvim + 3 agents
agents [name]      # claude + codex + gemini
remote [name]      # minimal for mosh / SSH

tls                # list sessions
tk [name]          # kill one
tka                # kill server (all sessions)
```

---

## Shell line editing (inside any pane)

| Keys | Action |
|------|--------|
| `Ctrl+a` / `Ctrl+e` | start / end of line (inside a cell, not tmux prefix) |
| `Ctrl+u` / `Ctrl+k` | delete to start / end |
| `Ctrl+w` | delete word back |
| `Alt+b` / `Alt+f` | word back / forward |
| `Ctrl+r` | history search (atuin) |
| `Ctrl+l` | clear screen |

> Note on the `Ctrl+a` overlap: tmux uses it as the prefix, so to send a literal `Ctrl+a` to the shell (line-start), press `Ctrl+a` twice.

---

## Common Issues

### Arrow keys output garbage, not word-jump on Option+Arrow

Already fixed if you're on Ghostty with the shipped config. The key bits:

```
macos-option-as-alt = true
keybind = fn+left=text:\x1b[1~
keybind = fn+right=text:\x1b[4~
keybind = home=text:\x1b[1~
keybind = end=text:\x1b[4~
```

iTerm2: Preferences → Profiles → Keys → Left/Right Option Key = `Esc+`.

### fn+Delete triggers Caps Lock

Already configured in the shipped Ghostty config.

### Keys look fine in plain zsh but break inside tmux

tmux may be eating them. Check `~/.config/tmux/tmux.conf` for `set -g xterm-keys on` and confirm `TERM=tmux-256color` or `screen-256color` is set. Reload config with `Ctrl+a r` (or `tmux source ~/.config/tmux/tmux.conf`).

### Debugging key sequences

```bash
cat -v         # then press keys; Ctrl+c to exit
```

---

## Zellij (opt-in pack)

If you installed the Zellij pack (`./install.sh --pack zellij`), its key model is different from tmux.

### Zellij modes

| Mode | Enter | Exit | Purpose |
|------|-------|------|---------|
| **Normal** | default | — | `Alt+h/j/k/l` between panes |
| **Locked** | `Ctrl+g` | `Ctrl+g` | pass every key to the terminal |
| **Pane** | `Alt+p` | `Esc` | manage panes |
| **Tab** | `Ctrl+t` | `Esc` | manage tabs |
| **Scroll** | `Ctrl+s` | `Esc` | scroll / search |

### Prefix key conflict

Zellij's default `Ctrl+g` lock mode plus the tab/pane mode prefixes (`Ctrl+t`, `Alt+p`) can clash with app bindings (git `Ctrl+g`, shell tab-completion on some setups). Options:

- Press `Ctrl+g` to enter Locked Mode when you need all keys to pass through.
- Or remap in `~/.config/zellij/config.kdl` (see [ZELLIJ_TROUBLESHOOTING.md](ZELLIJ_TROUBLESHOOTING.md)).

### Zellij shell wrappers

Installed only with the pack:

```bash
zwork / zdev / zai / zai-triple / zfullstack / zmulti / zremote
```

---

## Troubleshooting Workflow

1. Look at the status bar — which multiplexer / mode are you in?
2. Try `Esc` to exit any mode (Zellij) or the prefix (tmux).
3. Verify Ghostty: `cat ~/.config/ghostty/config`
4. Verify tmux: `cat ~/.config/tmux/tmux.conf`
5. Still stuck? [FAQ.md](FAQ.md) or open an issue with `tmux -V`, `tmux info`, and a `cat -v` trace.

---

## See Also

- [CHEATSHEET.md](CHEATSHEET.md) — full keybinding reference
- [ZELLIJ_TROUBLESHOOTING.md](ZELLIJ_TROUBLESHOOTING.md) — for the opt-in Zellij pack
- [remote.md](remote.md) — keyboard quirks when SSHing from iOS clients
