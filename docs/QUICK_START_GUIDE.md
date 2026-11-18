# Quick Start

Read this once after installing tuidev: it takes you from the one-line install to a sandboxed Claude Code or Codex session next to your editor, and shows where the tmux, Neovim and token steps fit. For what each installed tool replaces, see [toolbox.md](toolbox.md); for keys and commands, [CHEATSHEET.md](CHEATSHEET.md).

## 1. Install

tuidev configures Claude Code and Codex but doesn't install them, since they update themselves. Install whichever you use first, with its official instructions: [Claude Code](https://code.claude.com/docs/en/setup), [Codex](https://github.com/openai/codex). Then install tuidev. You need `curl` and `tar`, and on macOS [Homebrew](https://brew.sh); you don't need git:

```bash
curl -fsSL https://github.com/spfr/tuidev/releases/latest/download/get.sh | bash
exec zsh -l
```

It downloads the latest release, checks it against its sha256, and asks what this machine should get. Pick "Shell and sandboxed agents" (`--profile desktop --pack ai-clis`) for what this guide walks through, or "Everything for agent work" (`--profile full`). It then asks once more before it changes anything; answer `p` to preview every change first. To skip the questions, name the flags: `… | bash -s -- --profile desktop --pack ai-clis`. Every install gives you the `tuidev` command. If you cloned the repo instead, the same flags go to `./install.sh` (`--dry-run` previews); [updating.md](updating.md#installed-with-getsh-or-from-a-clone) says how the two differ.

`--pack ai-clis` writes the Claude Code and Codex settings that turn on their native sandboxes. Without it, `claude` and `codex` run with the settings you already have. Both of the first two choices include it.

| Profile   | Packs                   | Use when                        |
|-----------|-------------------------|----------------------------------|
| `minimal` | core                    | Server, VM, CI runner            |
| `desktop` | core + ui + sandbox     | Your Mac (recommended)           |
| `remote`  | core + remote + sandbox + `--pack tmux` | A headless box you SSH into |
| `full`    | desktop + extras + the agent packs | The whole agent setup on a Mac |

Add optional packs at any time: `tuidev install --pack monitoring` (the `agents` command and, on macOS, its menu bar), `--pack cooling` (a fan curve for Apple Silicon MacBooks) or `--pack orchestration` (tiered subagents). Re-running is safe. [profiles.md](profiles.md) lists every pack.

To get everything on a Mac later, add `--dry-run` first if you like; `cooling` asks for your password once:

```bash
tuidev install --profile full   # desktop + extras + ai-clis, orchestration, monitoring, cooling, herdr, tmux, release-age, ci
```

Check the result:

```bash
tuidev check    # health check against the installed profile
```

## 2. Your first session

Open a Ghostty tab in your project and run an agent. `claude` and `codex` are sandboxed automatically by their own settings — no wrapper needed:

```bash
claude    # or: codex
```

Review what the agent produces as a diff in your editor. `/ide` inside a `claude` session connects it to VS Code or Cursor (see [agent-workflows.md](agent-workflows.md#editor-integration)).

If you installed `--pack tmux` (included in the `remote` profile), you also get a tiny attach-or-create helper for durable sessions over SSH:

```bash
t myproject   # attach, or create a session named "myproject"
tls           # list sessions
```

Detach with `Ctrl+a d`; the session keeps running. Full key table: [CHEATSHEET.md#tmux---pack-tmux](CHEATSHEET.md#tmux---pack-tmux) (only relevant once `--pack tmux` is installed).

Optional, once an agent runs: move API tokens out of your shell. `secret scan` lists token-looking `export` lines in your startup files (name and line, never the value), and `secret import --remove` stores them in the Keychain, libsecret or `pass`. Then use `secret run -n NAME -- CMD`, so only that command gets the token and not every agent you start. See [secrets.md](secrets.md).

## 3. tmux keys (if you installed `--pack tmux`)

The prefix is `Ctrl+a`: press it, release, then press the key. The full table is in [CHEATSHEET.md#tmux-keys---pack-tmux](CHEATSHEET.md#tmux-keys---pack-tmux); the essentials:

| Keys | Action |
|------|--------|
| `Ctrl+a \|` / `Ctrl+a -` | Split right / split below |
| `Ctrl+a h/j/k/l` | Move between panes |
| `Ctrl+a d` | Detach |
| `Ctrl+a ?` | List every binding |

## 4. Run an agent in the sandbox

`claude` and `codex` are sandboxed automatically, by the settings `--pack ai-clis` writes (`sandbox.enabled` for Claude Code, `sandbox_mode = "workspace-write"` for Codex). If you skipped it in step 1, add it now; then just run them:

```bash
tuidev install --pack ai-clis
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

Neovim is optional now. Install it with `tuidev install --pack nvim`. The leader key is `Space`. Press it and wait: which-key shows the menu.

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

With `--pack monitoring`, `agents` shows every session, what it runs and what a crashed one left behind (`agents reap` cleans that up). For parallel agents, see [agent-workflows.md](agent-workflows.md). To work from another machine or your phone (a terminal app, or Herdr's phone app with `--pack herdr-core`), see [remote.md](remote.md). When something breaks, check [FAQ.md](FAQ.md).
