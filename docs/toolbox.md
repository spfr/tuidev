# The Toolbox

What tuidev installs, what each tool is for, why it was picked over the default, and how an agent ends up using it. For where each tool is installed from, see [profiles.md](profiles.md); for keys and aliases, the [cheatsheet](CHEATSHEET.md).

## At a glance

What `--profile full` puts on a machine, by what it replaces. The [tables below](#the-tools) have the detail.

**[Search and files](#search-and-files)**

- `rg` replaces `grep -r`: recursive by default, and it skips what `.gitignore` lists, hidden files and binaries.
- `fd` replaces `find`: the same ignore rules, and a pattern instead of `-name`.
- `fzf` is a fuzzy picker: Ctrl-T for a file with a preview, Alt-C for a directory.
- `bat` replaces `cat`: syntax highlighting, line numbers and git change marks.
- `eza` replaces `ls` and `tree`: a git status column, icons and a tree view (`ll`, `la`, `lt`).
- `zoxide` replaces long `cd` paths: `z api` jumps to the directory you use most.
- `broot` and `dust` replace `tree` and `du` with output you can read.

**[Git and review](#git-and-review)**

- `delta` is git's pager: diffs with syntax highlighting and the changed words marked.
- `gh` handles PRs, reviews and CI logs from the terminal.
- `lazygit` (`lg`) stages hunks, rebases and stashes in one screen.
- Git gets better defaults: histogram diffs, `zdiff3` conflicts, `rerere`, a remote set up on first push, prune on fetch.

**[CI and secrets](#ci-and-secrets)**

- `actionlint` lints GitHub Actions workflows, `zizmor` audits them for security problems, and `betterleaks` scans for committed secrets. Agents run them before a commit.

**[Data, HTTP and quality](#data-http-and-quality)**

- `jq` and `yq` query JSON and YAML instead of grepping them.
- `shellcheck` catches shell script bugs before they run.
- `xh` replaces `curl` for APIs, with formatted JSON.
- `hyperfine` benchmarks a command properly (`bench CMD`).
- `procs`, `tokei`, `tealdeer` and `glow` replace `ps`, `cloc`, `man` and a Markdown preview.

**[Languages](#languages)**

- `uv` replaces pyenv, virtualenv, pip and pipx with one binary.

**[Shell, sessions and machines](#shell-sessions-and-machines)**

- Ghostty, zsh with autosuggestions and syntax highlighting, and a Starship prompt.
- `atuin` gives searchable shell history on Ctrl-R.
- `tmux` keeps sessions alive: `t NAME` attaches or creates.
- Herdr shows every agent across machines as working, blocked or done.

**[Monitoring and agents](#tuidevs-own-commands)**

- `btm` replaces `top`.
- `agents` shows who needs you, what sessions left running, and where the CPU, the memory and the tokens went.
- `sbx -- CMD` runs anything with no access to your credentials.
- `mcp-lazy` starts an MCP server on its first use, not once per session.
- Fans that keep an Apple Silicon MacBook cool to the touch, a 3-day minimum age for new package releases, and subagents on the cheapest model that works.

**Not in `full`:** `fnm` (Node versions), `hunk` (a review-first diff viewer), Neovim, Vim and the container sandbox are each a `--pack NAME` away. See [profiles.md](profiles.md).

At your prompt, `cat`, `ls` and `top` run the modern tools. An agent, a pipe or a script gets the real commands, so the flags they already use keep working ([why](#how-agents-know-which-tool-to-use)).

## Two users, one terminal

A terminal on a tuidev machine has two kinds of user, and they want opposite things.

- **You** want color, previews, fuzzy search and a view that updates. A TUI is fine. Flags you have to remember are not.
- **An agent** wants a command that takes the flags it already knows, prints plain text or JSON, respects `.gitignore`, and exits. It pays for every line of output in tokens, and for every failed command in a turn.

So every tool here is picked for one of three roles, and the setup keeps them apart:

| Role | Tools | Rule |
|------|-------|------|
| **Both** | `rg`, `fd`, `jq`, `yq`, `git`, `gh`, `shellcheck`, `uv`, `hyperfine`, `actionlint`, `zizmor`, `betterleaks` | Scriptable, stable flags, quiet output. Agents call them by their own names. |
| **Yours** | `bat`, `eza`, `fzf`, `zoxide`, `delta`, `atuin`, `lazygit`, `btm`, `broot`, `glow`, `tokei`, `xh`, Starship | Interactive or decorative. They never stand between an agent and the command it typed. |
| **About agents** | `agents`, Herdr, `sbx`, `mcp-lazy`, `notify.sh`, `hunk` | They watch, confine or review what agents do. |

## The tools

### Search and files

| Tool | Instead of | Why it is here | How it is used |
|------|-----------|----------------|----------------|
| [ripgrep](https://github.com/BurntSushi/ripgrep) (`rg`) | `grep -r` | Recursive by default, and it skips what `.gitignore` lists, hidden files and binaries. A search of a repo never walks `node_modules`. `--json` for tools. | You: `rg TODO`, `fif TEXT` (rg into fzf). Agents: `rg` is on Claude Code's allow list, so it runs without a prompt. |
| [fd](https://github.com/sharkdp/fd) | `find` | The same ignore rules, a pattern instead of `-name '*x*'`, and results in parallel. | You: Ctrl-T and Alt-C use it under fzf. Agents: `fd -e ts . src`. |
| [fzf](https://github.com/junegunn/fzf) | scrolling | A fuzzy picker over any list. | Yours: Ctrl-T (file, with a `bat` preview), Alt-C (directory), `fshow` (commits), `agents pick`. |
| [bat](https://github.com/sharkdp/bat) | `cat`, `less` | Syntax highlighting, line numbers and git change marks. | Yours: `cat FILE` at a terminal runs it. |
| [eza](https://github.com/eza-community/eza) | `ls`, `tree` | A git status column, icons, and a tree view. | Yours: `ls`, `ll`, `la`, `lt`. |
| [zoxide](https://github.com/ajeetdsouza/zoxide) | `cd` with long paths | Jumps to the directory you use most that matches a few letters. | Yours: `z api`. Interactive shells only. |
| [broot](https://github.com/Canop/broot), [dust](https://github.com/bootandy/dust) (extras) | `tree`, `du` | A navigable tree, and disk use you can read at a glance. | Yours. They keep their own names. |

### Git and review

| Tool | Instead of | Why it is here | How it is used |
|------|-----------|----------------|----------------|
| git, with [tuidev's defaults](profiles.md#git-defaults) | git's defaults | `histogram` diffs, `zdiff3` conflicts, `rerere`, `autoSquash`, `push.autoSetupRemote`, `fetch.prune`: fewer surprises for you and for an agent that reads a conflict. Only keys you have not set. | Both. Git writes from an agent ask first (`--pack ai-clis`). |
| [delta](https://github.com/dandavison/delta) | git's pager | Diffs with syntax highlighting and the changed words marked. | Yours. It is a pager, so an agent's `git diff` (not a terminal) still gets a plain patch. |
| [gh](https://cli.github.com) | the GitHub website | PRs, reviews and CI logs without leaving the terminal. | Both. `gh pr view`, `gh run view` and their `list` forms are allowed for agents; `gh pr create`, `merge`, `release` and `api` ask. |
| [lazygit](https://github.com/jesseduffield/lazygit) (extras) | `git add -p` by hand | Staging hunks, rebases and stashes in one screen. | Yours: `lg`, or `Ctrl+a g` in tmux. |
| [hunk](https://hunk.dev) (`--pack hunk`) | scrolling a long `git diff` | A review-first viewer for a change set an agent wrote, with `--watch` while it works. | Yours. |

### CI and secrets

| Tool | Instead of | Why it is here | How it is used |
|------|-----------|----------------|----------------|
| [actionlint](https://github.com/rhysd/actionlint) (`--pack ci`) | finding a broken workflow after the push | Checks workflow syntax, `${{ }}` expressions and the shell in `run:` steps. Agents write CI files, and a failed run costs a round trip. | Both: `actionlint` before committing a workflow. |
| [zizmor](https://github.com/zizmorcore/zizmor) (`--pack ci`) | reading a workflow for injection by eye | Audits workflows for script injection, over-broad `permissions` and actions pinned to a tag instead of a commit. | Both: `zizmor .github/workflows`. |
| [betterleaks](https://github.com/betterleaks/betterleaks) (`--pack ci`) | hoping no key was committed | Scans the working tree and git history for secrets, and reads a repo's `.gitleaks.toml`. Agents commit code, and a pushed key is already leaked. | Both: `betterleaks git` before a push. |

### Data, HTTP and quality

| Tool | Instead of | Why it is here | How it is used |
|------|-----------|----------------|----------------|
| [jq](https://jqlang.org), [yq](https://github.com/mikefarah/yq) | `grep` and `sed` over JSON and YAML | A query reads the structure, so it does not break when the formatting changes. | Both. `jq` is allowed for agents; `agents json | jq` is how other tools read agent state. |
| [shellcheck](https://www.shellcheck.net) | finding the bug at run time | Catches unquoted variables, wrong tests and unportable syntax in shell scripts. Agents write a lot of shell. | Both; allowed for agents. |
| [xh](https://github.com/ducaale/xh) (extras) | `curl` with flags | `xh :3000/health` prints formatted, colored JSON. | Yours. Agents keep to `curl`. |
| [hyperfine](https://github.com/sharkdp/hyperfine) (extras) | `time`, once | Runs a command many times, with warm-up, and reports the spread. "Is it faster?" gets a number. | Both: `bench CMD`. |
| [procs](https://github.com/dalance/procs), [tokei](https://github.com/XAMPPRocky/tokei), [tealdeer](https://github.com/tealdeer-rs/tealdeer), [glow](https://github.com/charmbracelet/glow) (extras) | `ps`, `cloc`, `man`, a Markdown preview | Simpler syntax and faster answers. | Yours (`help CMD`, `md FILE`, `loc`). `tokei` is scriptable, but agents keep to `wc`. |

### Languages

| Tool | Instead of | Why it is here | How it is used |
|------|-----------|----------------|----------------|
| [uv](https://docs.astral.sh/uv/) (extras) | pyenv, virtualenv, pip, pipx | One binary for Python versions, venvs, lockfiles and tools. It links packages from one cache instead of copying them into every venv, which is what makes a venv per worktree cheap. | Both: `uv sync`, `uv run`, `uvx TOOL`. `update.sh --packages` patches uv and the Pythons it manages. |
| [fnm](https://github.com/Schniz/fnm) (`--pack fnm`) | nvm | Switches Node per `.nvmrc` on `cd`, without nvm's shell start-up cost. | Both. Agents never edit `PATH` for Node. `update.sh --packages` keeps each installed major on its latest patch. |

### Shell, sessions and machines

| Tool | Why it is here |
|------|----------------|
| [Ghostty](https://ghostty.org) | A fast native terminal with tabs and splits, the one tuidev's features are checked on first. |
| zsh with autosuggestions, syntax highlighting and completions; [Starship](https://starship.rs) | A shell that shows the branch, the exit status and the command you are about to repeat. One [palette](theming.md) colors Ghostty, tmux and Starship. |
| [atuin](https://atuin.sh) (extras) | History you can search by directory and exit code. Its database is on the credential deny list, so agents cannot read what you typed. |
| [tmux](https://github.com/tmux/tmux) (`--pack tmux`) | Sessions that outlive a dropped connection: `t NAME` attaches or creates. |
| [Herdr](https://herdr.dev) (`--pack herdr`) | A runtime that knows which pane is an agent and whether it is working, blocked or done, across machines. |
| Tailscale, mosh, SSH config (`--remote`) | An always-on box you reach from a laptop or a phone. See [remote.md](remote.md). |

### tuidev's own commands

| Command | What it answers |
|---------|-----------------|
| [`agents`](agent-workflows.md#local-processes-agents---pack-monitoring) | Who needs me? What did sessions leave running, and is it safe to stop? Where did the CPU, the memory and the tokens go? How close am I to a usage limit? |
| [`agents why PID`](agent-workflows.md#flagged-is-it-safe-to-stop) | Why is this process flagged, and on what evidence? |
| [`agents report`](agent-workflows.md#history-and-agents-report) | What should I change? Top insights first, then runs, waste, tokens, waits and denials. |
| [`agents mem`](agent-workflows.md#memory-guard-agents-mem), [`agents cool`](agent-workflows.md#fans---pack-cooling) | Who holds the memory, and what did the guard stop? How hard do the fans work? |
| [`sbx -- CMD`](sandboxing.md#sbx-the-general-purpose-tool) | Run anything with no access to credentials and no writes outside the project. |
| [`mcp-lazy`](agent-workflows.md#mcp-servers-by-name) | Start an MCP server on its first tool call instead of once per session. |
| [`notify.sh`](agent-workflows.md#notifications) | Tell me an agent needs me, once, where I am looking. |
| `make check`, `make update`, `./uninstall.sh` | Is the install healthy? What drifted? Remove exactly what was installed. See [updating.md](updating.md). |

## How agents know which tool to use

Not by a long list of instructions. Every line in an instruction file is loaded into every session, and a model already knows `rg`, `jq` and `gh`. tuidev uses five layers, cheapest first.

1. **The CLI does it already.** Claude Code's search tool is ripgrep, and inside its shell it replaces `grep` and `find` with versions that honor ignore files while taking the same flags (checked on Claude Code 2.1.322). tuidev adds nothing here, on purpose.

2. **The shell stays honest.** Claude Code captures your aliases and functions into the shell its commands run in. An alias that changes a command's flags is then a trap: `ls -lt`, `cat -v` and `top -l 1` are all errors under `eza`, `bat` and `btm`. So the shipped `.zshrc` makes `cat`, `ls` and `top` functions that use the modern tool only when stdout is a terminal, and the real command otherwise (an agent, a pipe, a script). `procs` and `dust` are never aliased over `ps` and `du` for the same reason, and `cd` is zoxide only in an interactive shell.

   The rule: **replace a command for an agent only with something that takes the same flags.** Everything else keeps its own name.

3. **The easy path is the good path.** `rg`, `jq`, `shellcheck` and the read-only `gh` commands are on Claude Code's allow list, so they run without a prompt. Git and gh writes ask. Credential paths are denied to the sandbox. An agent that takes the path with no prompts is using the right tools.

4. **A few lines it cannot guess.** The [`AGENTS.md` template](../templates/AGENTS_TEMPLATE.md) has one Environment section for your projects: which tools are scriptable, which are TUIs for the human, where long-running processes go, how Node and worktrees work here. The `orchestration` pack adds six rules, none of them a tool list: leave work uncommitted, don't poll in a sleep loop, stop what you start. Its subagent definitions put search on the cheapest model and review on the strongest ([orchestration.md](orchestration.md)).

5. **The machine corrects what instructions miss.** Hooks stop the background commands a subagent left running. The memory guard stops a runaway test. And `agents report` reads what your agents did, not what they were told: `--view denials` lists the commands you or auto mode keep refusing, `--view context` the MCP servers and skills every session loads and never uses, `--view waste` the duplicate test runs and stuck loops, each with the one thing to change.

That last layer is how the second one was found. A search of six weeks of local transcripts showed 46 sessions where an agent's `ls -t` had failed on eza's `--time <FIELD>`; each cost a turn. The fix was two functions in `.zshrc`, not a paragraph telling agents to avoid `ls -t`.

## Engineering with agents, on a Mac and on Linux

The tools above serve one loop. Each step has a default that works on both systems.

| Step | Practice | With |
|------|----------|------|
| **Confine** | Agents run in a sandbox by default: writes to the project only, and no reads of your credentials. | Claude Code's and Codex's own sandboxes (`--pack ai-clis`); `sbx` on macOS; a container for the rest ([sandboxing.md](sandboxing.md)) |
| **Isolate** | One git worktree per parallel task, never a shared dirty index. | `claude -w NAME`, subagent `isolation: worktree`, the `delegation` skill |
| **Route** | Search and command runs on the cheapest model, review on the strongest. | `--pack orchestration` |
| **Keep it running** | Work that must outlive the lid runs on a box that stays on. | tmux or Herdr on a `--profile remote` machine |
| **Watch** | One place says who is blocked, on which machine. | Herdr's sidebar, `agents`, the menu bar, `notify.sh` |
| **Verify** | Done means the checks ran, and the result is pasted, not claimed. | The definition of done in `AGENTS.md`; `hyperfine` when the claim is "faster" |
| **Review** | A person reads the diff before it is committed. | `hunk`, `delta`, `lazygit`, the git and gh ask rules |
| **Clean up** | What a session started is stopped when it ends, with evidence for the rest. | Cleanup hooks, `agents why`, `agents reap` |
| **Stay current and safe** | Updates are one command, and a release younger than three days does not install. | `make update`, `--pack release-age` |
| **Keep the machine fast** | The OS does not index, back up or scan what agents churn. | [performance.md](performance.md) |

What differs by system:

| | macOS | Linux |
|---|-------|-------|
| Sandbox | Seatbelt: the CLIs' own, and `sbx` | The CLIs' own (bubblewrap); no `sbx` |
| Packages | Homebrew | Homebrew if present, else `apt-get`, `dnf` or `pacman` |
| Menu bar, fans, Ghostty config | `monitoring`, `cooling`, `ui` | `agents` in the terminal; the rest is macOS only |
| Memory guard | A LaunchAgent the pack installs | `agents mem guard` in a tmux pane or a systemd user service |
| Typical role | The desk: where you review and answer | The box that stays on: where long work runs |
