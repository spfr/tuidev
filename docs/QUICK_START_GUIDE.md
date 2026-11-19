# Quick start

One path, about ten minutes, from install to a waiting agent: install, run two agents, see which one needs you, clean up what they leave behind, and know what the sandbox does. Running agents on another machine or picking them up from your phone comes after, in [remote.md](remote.md). For keys and commands, see [CHEATSHEET.md](CHEATSHEET.md).

## 1. Install

tuidev configures Claude Code and Codex but doesn't install them, since they update themselves. Install whichever you use first, with its official instructions: [Claude Code](https://code.claude.com/docs/en/setup), [Codex](https://github.com/openai/codex). You need `curl` and `tar`, and on macOS [Homebrew](https://brew.sh). You don't need git.

```bash
curl -fsSL https://github.com/spfr/tuidev/releases/latest/download/get.sh | bash
```

It downloads the latest release, checks its sha256 and asks what this machine should get. On a Mac, pick the first choice, "Everything for agent work" (`--profile full`). It is the installer's default and the only one that includes what this guide uses: `agents`, the menu bar, Herdr and the sandbox settings. On a headless box pick the third, "A headless box that stays on" (`--profile remote --pack ai-clis`). [profiles.md](profiles.md) lists what every profile and pack adds, and you can add packs later with `tuidev install --pack NAME`.

It then asks once more before it changes anything. Answer `p` to preview every change first. Nothing is written until you say yes, and `tuidev uninstall` removes what was installed.

## 2. Open a new shell

```bash
exec zsh -l
tuidev check     # health check against what you installed
```

The installer ends with "Next:", then a numbered list of the steps its packs left to you (log in, grant a permission, a command that needs root) and the number of warnings it printed. `tuidev check` shows what still needs attention, and `tuidev check --fix` repairs what it safely can ([below](#8-stay-current-and-leave)).

## 3. Two steps only you can do (macOS)

The monitoring pack installs SwiftBar for the menu bar and terminal-notifier for notifications. macOS wants a person for both:

1. Open SwiftBar once: `open -a SwiftBar`. Turn on Launch at login in its settings.
2. Allow notifications from terminal-notifier when macOS asks, or in System Settings > Notifications. If none appear, `terminal-notifier -diagnose` says why. The first click on a banner asks to let terminal-notifier control your terminal app; allow it, so a click lands on the session's tab.

For agent state in Herdr, also run `herdr integration install claude` (and `codex`) once.

## 4. Start Herdr and two agents

[Herdr](https://herdr.dev/) keeps your agents in panes it can read. Its prefix is `Ctrl+b`.

```bash
herdr          # attach; the first attach starts the server
claude         # in this pane, in a project directory
```

Open a second pane or tab in Herdr and run `codex` there. Give each one a task that will need a permission, such as running a command you have not allowed. Detach with `Ctrl+b q`; the agents keep running.

## 5. See which one needs you

When an agent waits on you, tuidev shows it four ways:

- **The tab and sidebar.** Tabs carry a mark for the kind of session and its task title (`✳` Claude Code, `⬡` Codex, `❯` a shell) instead of `1 2 3`. The sidebar marks the agent `blocked` and puts the time it began on its row.
- **A notification.** A banner on macOS, a Herdr toast when you are looking at its pane. Click the banner to jump to the session.
- **`agents`.** Run it in any terminal. It lists Needs you, To review and Running, one line each, blocked first.
- **The board.** In Herdr, **prefix+space** opens `agents board`: every session on every machine, with the last lines of the one under the cursor. Enter goes there, esc closes it.

Answer the prompt and the session goes back to work. [Which agent needs you](agent-workflows.md#fleet-attention--herdr---pack-herdr) and [the board](agent-workflows.md#the-board-every-session-one-screen) have the rest.

## 6. See what agents left behind

A finished subagent can leave a polling loop; a crashed session can leave MCP servers and a dev server.

```bash
agents stale        # processes whose session ended
agents hogs         # what burns memory or CPU
agents why PID      # why an item is listed, the evidence and a verdict
```

`agents why` ends in a verdict: safe to stop, check first, leave it or informational. Act on it, not on the flag alone: a stale dev server may be the one open in your browser. `agents reap` stops only what is safe to stop and lists what it left for you to check. [Flagged: is it safe to stop?](agent-workflows.md#flagged-is-it-safe-to-stop)

Stale-process detection is best on macOS; on Linux, orphans rarely look stale. In Claude Code's auto mode, hooks also stop the background commands a finished subagent left running ([cleanup hooks](agent-workflows.md#cleanup-hooks-claude-code)).

## 7. The sandbox, in one paragraph

`--pack ai-clis` turns on each CLI's own sandbox. Claude Code's commands can't read `~/.ssh`, `~/.aws`, `~/.gnupg`, the Keychain or the other credential paths, and token variables exported in your shell (`GITHUB_TOKEN`, `ANTHROPIC_API_KEY` and others) are unset in Claude Code's sandboxed commands and in every command Codex runs. Plain `codex` is different: its `workspace-write` mode limits writes and network, not reads, so it can still read `~/.ssh`. On macOS, run Codex under `sbx` when that matters. Never wrap a CLI whose native sandbox is on in `sbx`; Seatbelt doesn't nest. The profiles, the deny list and the trade-offs are in [sandboxing.md](sandboxing.md). To move API tokens out of your shell startup files, see [secrets.md](secrets.md).

## 8. Stay current and leave

```bash
tuidev update      # the latest release, its migrations and configs
tuidev check       # health check: what is installed, and whether its jobs and hooks run
tuidev uninstall   # remove what the manifest records (--dry-run previews)
```

Nothing updates unless you ask: `tuidev update --check` previews, `--rollback` goes back one release. When a new release is out, the menu bar, Herdr and `agents` say so once. What `tuidev check` tests and what its exit code means is in [updating.md](updating.md#checking-the-install-tuidev-check).

## Where next

- [agent-workflows.md](agent-workflows.md): parallel agents, worktrees, notifications, the menu bar, `agents report`.
- [remote.md](remote.md): agents on another machine, their previews in your browser, and your agents on your phone.
- [CHEATSHEET.md](CHEATSHEET.md): keys and commands, including tmux (`--pack tmux`).
- [nvim.md](nvim.md) and [vim.md](vim.md): the editor packs, with their keys.
- [profiles.md](profiles.md) and [toolbox.md](toolbox.md): what is installed, and what each tool replaces.
- [FAQ.md](FAQ.md): when something breaks.
