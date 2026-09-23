# Quick Start

From a fresh clone to a sandboxed agent running next to your editor, in about ten minutes. For reference material, see [CHEATSHEET.md](CHEATSHEET.md).

## 1. Install

```bash
git clone https://github.com/spfr/tuidev.git
cd tuidev
./install.sh --profile desktop --dry-run   # preview every change
./install.sh --profile desktop
exec zsh -l
```

| Profile   | Packs                   | Use when                        |
|-----------|-------------------------|----------------------------------|
| `minimal` | core                    | Server, VM, CI runner            |
| `desktop` | core + ui + sandbox     | Your Mac (recommended)           |
| `remote`  | core + remote + sandbox + `--pack tmux` | A headless box you SSH into |

Add optional packs at any time: `./install.sh --pack ai-clis`. Re-running is safe. See [profiles.md](profiles.md) for every pack.

Check the result:

```bash
make check      # health check against the installed profile
```

## 2. Your first session

Open a Ghostty tab in your project and run an agent. `claude` and `codex` are sandboxed automatically by their own settings — no wrapper needed:

```bash
claude    # or: codex
```

Work the agent produces, then review the diff in your editor — `/ide` inside a `claude` session connects it to VS Code or Cursor (see [agent-workflows.md](agent-workflows.md#editor-integration)).

If you installed `--pack tmux` (included in the `remote` profile), you also get a tiny attach-or-create helper for durable sessions over SSH:

```bash
t myproject   # attach, or create a session named "myproject"
tls           # list sessions
```

Detach with `Ctrl+a d`; the session keeps running. Full key table: [CHEATSHEET.md#tmux---pack-tmux](CHEATSHEET.md#tmux---pack-tmux) (only relevant once `--pack tmux` is installed).

## 3. tmux keys (if you installed `--pack tmux`)

The prefix is `Ctrl+a`: press it, release, then press the key. The full table is in [CHEATSHEET.md#tmux-keys---pack-tmux](CHEATSHEET.md#tmux-keys---pack-tmux); the essentials:

| Keys | Action |
|------|--------|
| `Ctrl+a \|` / `Ctrl+a -` | Split right / split below |
| `Ctrl+a h/j/k/l` | Move between panes |
| `Ctrl+a d` | Detach |
| `Ctrl+a ?` | List every binding |

## 4. Run an agent in the sandbox

`claude` and `codex` are sandboxed automatically, by settings each CLI ships with and that `--pack ai-clis` turns on (`sandbox.enabled` for Claude Code, `sandbox_mode = "workspace-write"` for Codex). Just run them:

```bash
./install.sh --pack ai-clis
claude
codex
```

**First run on macOS:** if you use Claude Code's native sandbox, the Keychain still works, since nothing wraps the process. If you instead wrap Claude Code in `sbx` (below), the Keychain is denied inside the sandbox: run `claude setup-token` once outside any sandbox, then export the token it prints as `CLAUDE_CODE_OAUTH_TOKEN` in `~/.zshrc.local`.

`sbx` remains as a general-purpose alternative: a Seatbelt wrapper for any command, not only AI CLIs.

```bash
sbx -- claude --settings '{"sandbox":{"enabled":false}}'   # Claude Code under sbx instead of its native sandbox
sbx -- codex -s danger-full-access -a on-request   # optional kernel-level mode for Codex
sbx --profile standard -- npm ci      # adds TCP 80/22/9418 for package installs and git over ssh
```

Never run `sbx` around a CLI whose native sandbox is on — Seatbelt doesn't nest, so pick one boundary per process tree. The profiles, deny list and trade-offs are explained in [sandboxing.md](sandboxing.md).

## 5. Neovim essentials (if you installed `--pack nvim`)

Neovim is optional now. Install it with `./install.sh --pack nvim`. The leader key is `Space`. Press it and wait: which-key shows the menu.

| Keys | Action |
|------|--------|
| `Space Space` / `Space f f` | Find files |
| `Space /` | Grep the project |
| `Space e` | File explorer |
| `Space g g` | lazygit |
| `g d` / `K` | Go to definition / hover docs |

More: [nvim.md](nvim.md).

## 6. A daily loop

Open a Ghostty tab per project, run `claude` or `codex` in it, and keep your editor (VS Code, Cursor, or Neovim if you installed `--pack nvim`) open beside it. Review diffs in the editor as the agent works — `/ide` links a Claude Code session to it directly.

```bash
claude                   # sandboxed automatically, run it in the project directory
# review diffs in VS Code / Cursor, or with /ide from inside the session
```

If you installed `--pack tmux`, `t myproject` gives you a session that survives a disconnect, and tmux-resurrect/tmux-continuum save and restore it automatically (continuum saves every 15 minutes).

For parallel agents, see [agent-workflows.md](agent-workflows.md). To work from another machine or your phone, see [remote.md](remote.md). When something breaks, check [FAQ.md](FAQ.md).
