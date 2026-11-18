# tuidev

**Run many AI coding agents, on more than one machine, and know which one needs you.**

tuidev sets up your terminal for Claude Code and Codex on macOS and Linux. It tells you which agent is waiting for you, opens another machine's previews in your browser, finds the processes agents left running, and runs agents in a sandbox that cannot read `~/.ssh`. One line installs it, you can preview every change, and `tuidev uninstall` removes it.

[![CI](https://github.com/spfr/tuidev/actions/workflows/ci.yml/badge.svg)](https://github.com/spfr/tuidev/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/spfr/tuidev?sort=semver)](https://github.com/spfr/tuidev/releases/latest)
![macOS](https://img.shields.io/badge/macOS-000000?style=flat&logo=apple)
![Linux](https://img.shields.io/badge/Linux-FCC624?style=flat&logo=linux&logoColor=black)
[![License](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

![A short terminal tour in three scenes. First, the Starship prompt in a repo, ll listing files with a git status column, and git diff through delta. Second, the agents command: a blocked Claude Code session first, a finished Codex session to review, a working one, a polling loop flagged stuck, and a line each for stale processes and hogs. Third, cat reading an SSH key without a sandbox, then sbx refusing the same read and a write to ~/.zshrc with "Operation not permitted" while make test still runs and passes.](docs/assets/tour.gif)

<sub>What to look at: the shell shows the repo's state, `agents` puts the blocked session first, and `sbx` refuses a read of an SSH key.</sub>

## Install

```bash
curl -fsSL https://github.com/spfr/tuidev/releases/latest/download/get.sh | bash
```

It asks what this machine should get, then asks once more before it changes anything; answer `p` there to see every change first. No git and no clone: it downloads the latest release and checks it against the release's sha256.

| You pick | You get | To skip the question, end the line with |
|----------|---------|------------------------------------------|
| Everything for agent work | Sandboxed agents, `agents` and the menu bar, Herdr, tiered subagents, the shell, and fan control on Apple Silicon, on a Mac | `bash -s -- --profile full` |
| Shell and sandboxed agents | The shell and Ghostty, with Claude Code and Codex sandboxed | `bash -s -- --profile desktop --pack ai-clis` |
| A headless box that stays on | The shell, tmux, Tailscale and mosh, with sandboxed agents | `bash -s -- --profile remote --pack ai-clis` |
| Just the shell | zsh, the prompt and the CLI tools | `bash -s -- --profile minimal` |

macOS needs [Homebrew](https://brew.sh). tuidev configures [Claude Code](https://code.claude.com/docs/en/setup) and [Codex](https://github.com/openai/codex) but doesn't install them, since they update themselves. Afterwards, restart your shell with `exec zsh -l`. In CI or a container build there is nobody to ask, so name the flags and add `--yes`.

After that, `tuidev` is the entry point:

```bash
tuidev                        # everything you can do, searchable
tuidev install --pack herdr   # add a pack later; --dry-run previews
tuidev update                 # the latest release, when you ask for it
tuidev uninstall              # remove exactly what was installed
```

Rather read it first? `curl -fsSLO https://github.com/spfr/tuidev/releases/latest/download/get.sh`, read it (about 230 lines), then `bash get.sh`. Or clone the repo and run `./install.sh` with the same flags: it is the same installer, and `tuidev update` then pulls instead of downloading.

<details>
<summary>Or hand it to your agent</summary>

Paste this into Claude Code or Codex. It drives the same installer, shows you the plan and waits for your yes:

```text
Set up tuidev (https://github.com/spfr/tuidev) on this machine.

1. Download https://github.com/spfr/tuidev/releases/latest/download/get.sh and run
   `bash get.sh --fetch`. It prints the directory the release is in. Read README.md and AGENTS.md there.
2. Tell me the OS, and which fits: `--profile full` for everything on a Mac I sit at,
   `--profile desktop --pack ai-clis` for less, `--profile remote` on a headless box,
   `--profile minimal` on Linux without Homebrew. Recommend one and ask me once.
3. Run `<that directory>/install.sh <my choice> --dry-run < /dev/null` and summarise what it
   would install and which files in my home it would change. Wait for my yes.
4. Run the same command without `--dry-run`. Use only install.sh: no edits to my dotfiles by
   hand. If it needs sudo, a password, or a path your sandbox denies, stop and give me the
   exact command to run myself.
5. Run `tuidev check` and `tuidev perf`, and report what failed or warned, with the fix each
   one prints. Change nothing else. Remind me to run `exec zsh -l`, and that `tuidev uninstall` undoes it.
```

</details>

## What it fixes

| Without tuidev | With it |
|----------------|---------|
| An agent has waited twenty minutes for your approval, and you don't know which: the tabs read `1 2 3 4`. | One sidebar lists every agent on every machine, the blocked one first, and tabs carry the task's name. [Know which agent needs you](#know-which-agent-needs-you) |
| The agent on another machine says its preview is at `localhost:5173`. That is its localhost, not yours. | Ctrl-click the link and it opens in your browser. [Remote feels local](#remote-feels-local) |
| A subagent that finished hours ago left a loop polling a file. A crashed session left its MCP servers and a dev server running. | `agents` lists what was left behind, each with a verdict and its evidence, so you stop the right thing. [Stop what agents left behind](#stop-what-agents-left-behind) |
| The fan is on, and nothing says which project is burning the CPU or the tokens. | CPU and tokens by project, session and job, in the terminal and in the menu bar. [See it all from the menu bar](#see-it-all-from-the-menu-bar) |
| Any command an agent runs can read `~/.ssh`. | Claude Code and Codex run sandboxed by default. [Agents can't read your keys or your tokens](#agents-cant-read-your-keys-or-your-tokens) |
| The API token you exported in `.zshrc` is in the environment of every agent you start. | Tokens live in the OS keychain and reach one command, when you ask. |

tuidev is shell scripts and configs: a small core, and everything else an opt-in pack you can add later.

## Know which agent needs you

One sidebar for every agent on every machine, sorted by who needs you, with tabs named after the task instead of `1 2 3`. [Herdr](https://herdr.dev/) (`--pack herdr`) is the runtime: a server owns the panes, so agents keep running when you detach, and each one is marked `working`, `blocked`, `done` or `idle`. Save an always-on box once with `herdr machine add workbox` and its agents join the same sidebar, and keep working while your laptop sleeps.

With `--pack monitoring` beside it, a tab bar of `1 2 3` reads `✳ API docs`, `✳ Fix login redirect`, `❯ api`: one mark per kind of session (`✳` Claude Code, `⬡` Codex, `❯` a shell), then the session's own task title. A workspace says in red how many of its agents wait on you (`api · 2 blocked`). A name you typed yourself is never touched. [Fleet attention](docs/agent-workflows.md#fleet-attention--herdr---pack-herdr) · [Tab names and sidebar rows](docs/agent-workflows.md#tabs-named-after-what-runs-in-them)

<img src="docs/assets/herdr.gif" width="800" alt="Herdr in a terminal. The tab bar reads ✳ Fix flaky cache test, ✳ Review diff and ❯ myapp instead of 1, 2, 3. The sidebar lists three machines, Local, devbox and workbox, and under each its workspaces on two lines: the name, then the branch and what runs there, such as fix-cache · ✳2 ❯1 for myapp and canary · ⬡1 for infra; api on devbox adds a red blocked after its name. Below, seven agents sorted by who needs you: first Fix 404 routes on devbox, blocked since 22:43, in red; then Review diff and API docs, done, in blue, each with the time it finished; then Rate limit and Canary 1.5 working on workbox, Fix flaky cache test working, and Sign-up form idle. The view jumps to devbox's api, tab ✳ Fix 404 routes, where the agent asks to allow git push origin fix-404; after a y it pushes and opens a draft PR, its red mark turns green and blocked leaves the workspace row. Then the view opens workbox's infra, tab ⬡ Canary 1.5, where an agent waits for a canary.">

<sub>Seven agents on three machines in one sidebar, sorted by who needs you. The blocked one on `devbox` is first, in red: jump to it, answer, and it goes back to work.</sub>

The same answer on one screen is `agents board`: **prefix+space** in Herdr opens it as a popup over the pane you are in. Every session on every machine is one line, grouped as Needs you, To review and Working. The right-hand side follows the cursor with the last lines of that session's output, so you read what it asks before you go there. Enter goes to the session's pane, tab changes the grouping, and esc closes the popup. [The board](docs/agent-workflows.md#the-board-every-session-one-screen)

<img src="docs/assets/board.gif" width="800" alt="agents board in a terminal, in two columns. On the left, tabs Attention, Tree and Machines with Attention filled in, a line counting 1 needs you, 1 to review and 1 working, each CLI's usage limit, and a yellow warning line. Under them three groups: NEEDS YOU in red with the session Release notes for 2.4, wants permission, 6m; TO REVIEW in blue with Dark mode toggle, finished, 12m; WORKING in green with Fix flaky cache test, tests 3m12s. On the right, tabs Card, Trace, Pane and Details, then the selected session's name, project and state, the command running under it, and the last lines of its pane: for the first session, the git push it asks permission for. The cursor moves down to the finished session and its summary of what changed, then to the working one and its test run. Tab switches the left side to Tree, where each session has the commands it started listed under it.">

<sub>`agents board` over three made-up sessions, in a plain terminal. In Herdr it is a popup over your pane.</sub>

## Remote feels local

The dev server an agent started on another machine prints `http://localhost:5173`, and that is the other machine's localhost. With tuidev on both, **Ctrl-click the URL** in its Herdr pane and it opens in your own browser, through an ssh tunnel made on the spot.

Press **prefix+m** for the map: one list of what runs where, on every machine. Enter opens a preview or a file here, and **ctrl-k stops what is under the cursor on the machine that runs it**, asked first. Drag a file onto a session on another machine and it gets there, after one click on your Mac. It is plain ssh underneath: nothing listens anywhere, what another machine may ask for is decided on yours, and a tunnel closes itself when the server behind it stops. [Remote feels local](docs/remote.md#remote-feels-local-ports-links-and-files)

<img src="docs/assets/remote.gif" width="800" alt="Herdr in a terminal with three machines in its sidebar: Local, atlas and kepler. The storefront session on atlas shows a preview server at http://localhost:5173 and a review it wrote. Back on Local, prefix+m opens the map: under Previews and dev servers, atlas port 5173 by the storefront session and kepler port 8080, left behind; under Files sessions just wrote, review.md on atlas; then sessions and machines. Enter on the atlas row forwards the port, and the checkout page served from atlas appears in a browser. Ctrl-x on the kepler row asks to send SIGTERM to one process; after y the row is gone and Left behind says nothing. Enter on review.md fetches it, and the review is read in the terminal on this Mac.">

<sub>A preview running on `atlas` opens in the browser on this Mac, a server left behind on `kepler` is stopped from the same list, and a review written on `atlas` is read here.</sub>

## Pick up an agent from your phone

Herdr has a free phone app with an inbox of the agents that need you. It reaches your machine over SSH and lists what runs in [herdr-core](https://herdr.dev/core/), Herdr's own runtime; it does not see an agent you started in a Herdr pane. tuidev connects the two:

```bash
tuidev install --pack monitoring --pack herdr-core   # agents hc, and herdr-core started when you log in
agents hc                                            # is herdr-core running, and in your desktop login?
agents hc run claude                                 # in a Herdr pane: the agent, hosted in herdr-core
```

- **An agent started with `agents hc run`** is in the pane, in Herdr's sidebar and in the phone's inbox, and keeps running when the pane closes.
- **The agents you already run show up too.** While herdr-core is up, each agent pane of this machine's Herdr gets a mirror in it. Typing on the phone reaches the agent in the pane. `AGENTS_HC_MIRROR=0` turns the mirrors off.
- **What it needs:** herdr-core on the machine (its own installer, or Herdr's desktop app; tuidev does not install it), Herdr's phone app, and SSH from the phone, which Tailscale gives you. Each machine runs its own herdr-core and is added in the app by itself.

The pack is not part of any of the four install choices: add it with the first command above. Tested so far on one Mac with one phone; the login item across a logout, and Linux with a real herdr-core, are not yet tested. [Herdr's phone app](docs/remote.md#herdrs-phone-app-agents-hc)

## Stop what agents left behind

Every `claude` session starts its own MCP servers, and its subagents start test runs, dev servers and polling loops. When a session crashes, or a subagent hands back its report, some of that keeps running. `agents` (`--pack monitoring`) lists each session with what it runs, flags what was left behind, and gives every flagged process a verdict with its evidence, so you stop the right thing and leave the rest.

<img src="docs/assets/cleanup.gif" width="800" alt="Three commands in a terminal. agents says who needs you; under the Claude Code session in api, a polling loop has waited 5h10m and is flagged stuck, safe to stop. agents why 2120 explains it: verdict, safe to stop, because what it waits for already finished ([exited with code 0], 5h0m ago), with high confidence; the evidence is its owner, its age, the file it watches, that file's last line and how long it has been quiet, then how to look and how to stop it. agents report opens with its top insights (Explore subagents left 3 polling loops running for 7.7 hours; api's CPU is up 147 percent on the day before, mostly its build; myapp's tests ran 4 duplicates), then shows the CPU-hours of agent work in the last 24 hours by job, with tests first, by project and session, the busiest hours, the tokens (17.6M, 94% cache hits, 2% polling), one denial, and the cleanups by reason.">

<sub>Who needs you, why a five-hour polling loop is safe to stop, and where a day of agent work went.</sub>

- **Verdicts, not guesses.** `agents why PID` prints the evidence: "safe to stop: what it waits for already finished", "check first: dev server on :5173, its session is still active". `agents reap --stuck` stops the stuck loops. Kills go descendants first and re-check each process's start time before every signal.
- **Fixed at the source.** Claude Code hooks stop the background commands a subagent left running once it hands back its report.
- **A runaway can't take the Mac.** A test an agent started once grew to 16 GB in 55 seconds. A memory guard now warns past 8 GB, naming the process, its project and session, and stops a runaway in an agent tree at half the RAM. Agents get a 4 GB Node heap cap, so the common case fails fast inside the test.
- **Where the tokens go.** `agents report --view tokens` reads the transcripts already on disk: tokens by model, CLI, subagent and project, the cache hit rate, what polling cost, and what it all would cost at API list prices. All local; nothing is sent anywhere.

[Local processes: `agents`](docs/agent-workflows.md#local-processes-agents---pack-monitoring)

## See it all from the menu bar

On macOS, the same pack adds a [SwiftBar](https://swiftbar.app) menu that answers one question first: who needs you? The title counts only the sessions that are blocked and the ones to review. Open it and what needs an action is flat and first, one row each, with what it waits for and how long (`✳ api · permission · 6m`). Everything else is one row that sums it up: the usage limit closest to its cap, today's CPU and tokens, what was left behind, your other machines. Alerts know which Herdr pane you are looking at, so you are not pinged for the agent in front of you. [Menu bar](docs/agent-workflows.md#menu-bar-swiftbar-macos)

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/assets/menu-dark.webp">
  <img src="docs/assets/menu-light.webp" width="800" alt="The agents menu open under its menu-bar item, which shows a red alert with 1 and a blue check with 1 for what needs you, and a cup for keep-awake. Needs you (1): a Claude Code session in api, permission, 6 minutes. To review (1): a Codex session in web, done 12 minutes. Running (3): myapp with its tests at 3m12s, 2.2 cores and 1.8G; a polling loop in api stuck for 5h10m, safe to stop; pnpm dev in web running 45 minutes, check first. Then one row each: Claude&apos;s weekly limit as a gauge at 83% with a marker for the time gone and +2 more windows; Today, 3.4 h blocked, 17.4 CPU-hours, tests 46%; Stale (2), server-memory and vite; Hogs (1); Awake, while agents run; CPU 27%, memory 59%, thermal nominal; Open agents watch; Refresh. The stuck loop&apos;s submenu is open: its command, Jump to session, then safe to stop, what it waits for already finished ([exited with code 0], 5h0m ago), its owner, how long it has waited, the file it watches and that file&apos;s last line, then Stop command…, Copy details, Show session, Peek and Details.">
</picture>

<sub>Everything that needs you, one click from the menu bar. [More submenus, animated](docs/assets/menu.gif).</sub>

## Agents can't read your keys or your tokens

Without a sandbox, any command an agent runs can read `~/.ssh`. `--pack ai-clis` turns on Claude Code's and Codex's own sandboxes, so plain `claude` and `codex` run confined without a wrapper, and gates git and gh writes behind a prompt. Claude Code's Bash and `Read` tools are denied `~/.ssh`, `~/.aws` and the other 31 paths on one [credential list](configs/sandbox/credential-paths.txt). Codex's sandbox limits writes and network but not reads, so for anything else `sbx` runs a command under a macOS Seatbelt profile that denies the same list. [Sandboxing](docs/sandboxing.md)

<img src="docs/assets/sbx.png" width="800" alt="sbx in a terminal: without a sandbox, cat of ~/.ssh/id_ed25519 prints the key; under sbx the same read and a read of ~/.aws/credentials fail with &quot;Operation not permitted&quot;, so does appending to ~/.zshrc, and make test in the project still runs and passes.">

<sub>Without a sandbox, any command an agent runs can read your keys. Under `sbx`, the same read is refused, so are writes outside the project, and the project's own work still runs.</sub>

A token you export in `.zshrc` is in the environment of every agent you launch, and one `env` in a tool call puts it in a transcript. `secret` keeps tokens in the store your OS already has (the login Keychain, libsecret or `pass`), and a token reaches one command, only when you ask:

```bash
secret scan                                 # tokens in your shell startup files, by name and line, never the value
secret import --dry-run --remove ~/.zshrc   # what moving them into the store would change
secret run -n GITHUB_TOKEN -- ./release.sh  # in that command's environment, and nowhere else
```

It is one person's tokens on one machine, not a team secret manager. What each sandbox stops, store by store: [Secrets](docs/secrets.md#what-an-agent-can-reach)

## Also in the box

- **A modern shell.** Ghostty, zsh with autosuggestions and completions, a Starship prompt, and `rg`, `fd`, `bat`, `eza`, `zoxide`, `fzf`, `delta`, `gh` and `jq` wired in for you at the terminal. An agent's `cat`, `ls` and `top` stay the real commands, so the flags it already knows keep working. One palette colors Ghostty, tmux and Starship. [Toolbox](docs/toolbox.md) · [Theming](docs/theming.md)
- **A palette.** `tuidev` on its own, or **prefix+a** in Herdr, opens a searchable list of what you can do, each row with the command it runs: the map, the reports, the audits, themes, updates. [Cheatsheet](docs/CHEATSHEET.md)
- **Cheaper subagents.** `--pack orchestration` pins Claude Code's subagents to tiers: Haiku for search and command runs, Sonnet for routine implementation, Opus for hard changes and review. Codex gets the same roles. [Orchestration](docs/orchestration.md)
- **A MacBook that stays cool.** Agents keep the chip at 75–85 °C for hours (measured on an M4 Pro) while macOS keeps the fans near their minimum. `--pack cooling` adds the missing fan curve: a small Swift daemon you build from [one readable file](lib/fan/tuidev-fan.swift), which only ever adds air and hands the fans back on any error. [Fans](docs/agent-workflows.md#fans---pack-cooling)
- **No background tax.** tuidev runs when something happens, not on a stopwatch: an idle menu bar refreshes 12 times an hour, and your other machines are asked what runs there only when you open the menu. [What runs in the background](docs/performance.md#what-tuidev-runs-in-the-background)
- **New package versions wait 3 days.** `--pack release-age` makes npm, bun and uv hold off on a version until it is 3 days old, which gives a hijacked release time to be noticed and pulled. Lockfiles still install as pinned.
- **Two audits.** `tuidev perf` checks what the OS does behind your agents (package stores in the Spotlight index, backups, file limits). `tuidev disk` shows what tools and agents left on disk and only ever runs a tool's own cleanup command. [Performance](docs/performance.md)
- **Notifications.** When an agent needs you: a Herdr toast, a tmux message, a macOS banner or an [ntfy](https://ntfy.sh) push, whichever can reach you. Clicking the banner jumps to the session that asked. [Agent workflows](docs/agent-workflows.md)

<img src="docs/assets/cli.gif" width="800" alt="The shipped zsh in a repo under the Starship prompt. z ap jumps to ~/api; lt draws the repo as a tree with file icons; cat src/routes.py shows the file through bat with syntax highlighting and git change marks; Ctrl-T opens fzf, and typing cach narrows the files to src/cache.py with a highlighted preview; Ctrl-R opens atuin's history search filtered to test commands; tokei counts the repo's lines by language.">

## Staying up to date

`tuidev update` fetches the latest release, runs its one-shot migrations and re-applies tuidev's configs. Your own lines and the files you edited are kept, and `tuidev update --rollback` goes back to the release before. Packages are a separate step, `tuidev update --packages`, which also patches what Homebrew can't: each Node major fnm installed, a standalone uv and the Pythons it manages.

A new release shows up as a row in the menu bar, one toast in Herdr and a line under `agents`; **prefix+u** in Herdr shows what is installed and what is out. Nothing updates itself. The check is one request a day to github.com for the latest release's tag (hourly after one that failed), and `tuidev latest off` turns it off. [Updating](docs/updating.md)

## What it changes on your machine

- `~/.zshrc`, `~/.config/starship.toml` and `~/.ssh/config` get `# >>> tuidev managed (...) >>>` blocks. Everything outside the markers is yours.
- AI CLI settings (`~/.claude/settings.json`, `~/.codex/config.toml`) are placed only where absent or unmodified. An edited `~/.claude/settings.json` gets new shipped settings merged in, and your values win ([docs/updating.md](docs/updating.md#shipped-configs-you-may-have-edited)).
- Anything tuidev replaces is backed up to `~/.config/tuidev/backups/` first.
- `~/.config/tuidev/manifest` records what was installed. `tuidev uninstall` removes only those records: a `ripgrep` you already had survives, and so do CLI logins and session state.
- The release itself lives in `~/.local/share/tuidev`, the one before it beside it.
- What runs in the background is listed with its trigger and its off switch in [docs/performance.md](docs/performance.md#what-tuidev-runs-in-the-background).
- tuidev sends no telemetry. Its only request of its own is the daily update check; with `--pack nvim`, Neovim's plugin manager fetches plugins from GitHub when you use it.

## Who it's for

**For you if** you run Claude Code or Codex from a terminal next to a GUI editor, mostly on a Mac, maybe with a Linux box that stays on, and you want agents confined by default and a setup you can preview, read and remove cleanly.

**Not for you if** you want:

- a terminal IDE: there are no prebuilt tmux layouts, and Neovim is an optional pack;
- a personal dotfiles dump, a kitchen-sink Homebrew installer, or a showcase of every modern CLI;
- AI agents running unsandboxed on the host by default;
- in-editor ACP agents shipped for you;
- Docker Desktop or OrbStack (never installed), or third-party installers piped into a shell for you: when a package manager can't supply a tool, tuidev prints the vendor's command and you run it.

The reasoning is in [VISION.md](VISION.md).

## Profiles and packs

| Profile   | Packs                                   | For                                     |
|-----------|-----------------------------------------|-----------------------------------------|
| `minimal` | core (the shell, the CLI tools, `secret`) | Servers, VMs, CI runners                |
| `desktop` | core + ui + sandbox                     | **Default on macOS**: laptop or desktop |
| `remote`  | core + remote + sandbox + `--pack tmux` | Headless machines, Tailscale nodes      |
| `full`    | desktop + extras + every agent pack     | The whole setup on a Mac                |

Add optional packs with `--pack NAME`, at install or later with `tuidev install --pack NAME`. Installs are additive.

| Optional pack | Adds |
|---------------|------|
| `ai-clis` | Claude Code and Codex settings with their native sandboxes on, and git and gh write gates |
| `orchestration` | Tiered subagents and the delegation skill for Claude Code and Codex; installs on its own too |
| `monitoring` | `agents` (cleanup verdicts, the map, port forwards, CPU by job, tokens), its SwiftBar menu (macOS) and `bottom` |
| `tmux`, `herdr` | Durable sessions; Herdr's agent-aware runtime, with named tabs, the palette and the Ctrl-click that opens another machine's link here |
| `nvim`, `vim` | LazyVim, or a zero-plugin vimrc for servers |
| `sandbox-container` | Tier 2 sandboxing in a container runtime (Apple `container`, Podman or Docker) |
| `fnm`, `hunk` | Node via fnm; a review-first diff viewer |
| `ci` | `actionlint` and `zizmor` for GitHub Actions workflows, `betterleaks` for secrets |
| `cooling` | Fans that follow the chip's temperature on Apple Silicon MacBooks |
| `release-age` | npm, bun and uv wait 3 days before installing a new version |
| `herdr-core` | Your agents in Herdr's phone app: `agents hc`, and herdr-core started in your desktop login |

What each one installs is in [docs/profiles.md](docs/profiles.md). On Linux, `minimal` and `remote` also install without Homebrew, through `apt-get`, `dnf` or `pacman`. `sbx` and the `ui` pack are macOS only.

## Everyday commands

```bash
claude | codex                           # AI CLIs, sandboxed by their own native settings
claude -w NAME                           # Claude Code in its own git worktree, for parallel agents
tuidev                                   # the palette: everything below, searchable (Herdr: prefix+a)
agents [why PID | report]                # sessions, what's safe to stop, CPU by job (--pack monitoring)
herdr                                    # every agent on this machine and saved ones (--pack herdr)
agents board                             # every session on every machine, by who needs you (Herdr: prefix+space)
agents map                               # what runs where on every machine; enter opens, ctrl-k stops (Herdr: prefix+m)
agents forward open workbox 5173         # another machine's port, here, in your browser
agents hc run claude                     # an agent you can pick up in Herdr's phone app (--pack herdr-core)
secret run -n NAME -- CMD                # a token from the OS store, in one command's environment
sbx -- CMD                               # any command under the strict Seatbelt profile (macOS)
t [NAME]                                 # attach-or-create a tmux session (--pack tmux)
tuidev check | perf | disk               # health check; what the OS does behind your agents; what was left on disk
tuidev update [--check | --packages]     # the latest release; a preview; packages for the installed profile
tuidev theme catppuccin-mocha            # re-theme tmux, Ghostty and Starship
```

In a clone, `make help` lists the same as Makefile targets. Every key binding and command is in [docs/CHEATSHEET.md](docs/CHEATSHEET.md).

## Documentation

| Doc | Covers |
|-----|--------|
| [Quick start](docs/QUICK_START_GUIDE.md) | Install to first sandboxed agent session |
| [Cheatsheet](docs/CHEATSHEET.md) | Session commands, tmux keys, aliases, Makefile |
| [FAQ](docs/FAQ.md) | Troubleshooting |
| [Profiles and packs](docs/profiles.md) | What each profile and pack installs |
| [Toolbox](docs/toolbox.md) | Every tool: what it replaces, why, who uses it, and how agents come to use the right one |
| [Performance](docs/performance.md) | What macOS and Linux do in the background that competes with agents, measured, and what to change |
| [Sandboxing](docs/sandboxing.md) | Native CLI sandboxes, `sbx`, Seatbelt profiles, credential deny list |
| [Secrets](docs/secrets.md) | API tokens in the Keychain, libsecret or `pass` with `secret`, not in dotfiles; what agents can reach |
| [Agent workflows](docs/agent-workflows.md) | AI CLIs, editor integration, agent teams, worktrees, Herdr, `agents` and the menu bar, notifications |
| [Orchestration](docs/orchestration.md) | The `orchestration` pack: subagent tiers, skills, git gates, CI runners |
| [Remote and mobile](docs/remote.md) | Tailscale, SSH, mosh, always-on nodes, Herdr's phone app, iOS clients |
| [Neovim](docs/nvim.md) | The `nvim` pack: LazyVim essentials |
| [Vim](docs/vim.md) | The `vim` pack: a zero-plugin vimrc for servers |
| [Theming](docs/theming.md) | Palette contract and `theme.sh` |
| [Updating](docs/updating.md) | Updates, migrations, the install manifest, uninstall |
| [Engineering](docs/engineering.md) | Architecture, shared libs, pack contract, verification, screenshots |
| [Roadmap](docs/roadmap.md) | Watch-list and adopt/hold criteria |
| [VISION.md](VISION.md) | Principles and non-goals |
| [AGENTS.md](AGENTS.md) / [CLAUDE.md](CLAUDE.md) | Instructions for AI agents working on this repo |
| [AGENTS template](templates/AGENTS_TEMPLATE.md) | Starter `AGENTS.md` for your own projects |
| [Migrations](scripts/migrations/README.md) | Script-level contract for one-shot migrations |
| [Screenshot tapes](docs/assets/tapes/README.md) | Demo fixtures, VHS tapes, the Herdr fleet and the menu renderer behind the README images |
| [CONTRIBUTING.md](CONTRIBUTING.md) / [SECURITY.md](SECURITY.md) / [Code of Conduct](CODE_OF_CONDUCT.md) | Contributing and reporting |
| [CHANGELOG.md](CHANGELOG.md) | Release history |

## Contributing

Issues and PRs are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) and [VISION.md](VISION.md) first, and run `make ci-test` before you push.

## License

[MIT](LICENSE). Sponsored by [SpiceFactory](https://spfr.co).
