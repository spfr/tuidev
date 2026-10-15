# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

A notification that an agent needs you now takes you to it: click the banner
and you land in that session's Herdr pane, tmux pane or Ghostty tab.

### Added

- **Click a notification to jump to its session.** On a Mac, `notify.sh`
  posts its banner through terminal-notifier, which the `monitoring` pack now
  installs (macOS only: `pkg_install` skips it on Linux). When the hook runs
  under a `claude` or `codex` process, `agents root-of` pins that session as
  `PID@START` when the hook runs, and a click runs `agents jump PID@START`:
  the Herdr pane, the tmux pane, or the Ghostty (1.3+), iTerm2 or Terminal
  tab, worked out at the click and refused if the pid has been reused. The
  banner also brings the session's terminal app forward (`-activate`, by its
  bundle id), and a newer notification from the same session replaces the
  older one. What a click runs is only `agents` by its absolute path, the
  hook's `PATH` and the checked token, built and quoted in one place
  (`agents`) and handed to `notify.sh`; titles and messages reach
  terminal-notifier as arguments, never a shell, escaped where it would
  misread them (a leading `[`, `(`, `{`, `<`, quote or `-`). The first click
  asks to let terminal-notifier control the terminal app; declined, a click
  still selects the pane but only brings the app forward. Without
  terminal-notifier, the banner is `osascript`'s as before; when
  terminal-notifier times out, it is not repeated through `osascript`.
- **`agents root-of PID`**: the agent session a process runs under, as
  `PID@START`, with its terminal app, that app's bundle id (for tmux and
  Herdr, the app their clients run in) and the command a click on its
  notification runs. It takes one `ps` and calls neither tmux nor Herdr.
- **The menu's notifications** (`--notify`) use terminal-notifier too, and
  the cleanup hooks' "Stopped N background commands" notification jumps to
  its session, in a group of its own, so it never replaces that session's
  "Needs your approval" banner.

### Changed

- **On a Mac, the banner also fires inside Herdr and tmux**, next to the
  toast or status line, which can't be seen from another app. Over ssh the
  toast or status line is still the only channel, unless `agents root-of`
  finds the session in a terminal app on the Mac (a tmux server started
  over ssh and attached locally keeps a stale `SSH_CONNECTION`). Linux is
  unchanged.
- **`notify.sh` bounds the commands it waits on** (the Herdr toast, tmux,
  `agents root-of`, terminal-notifier, `osascript`, `notify-send`; the ntfy
  push has `curl --max-time`) with a timeout, so a hung notifier can't hold
  a hook, and passes the `osascript` banner's text as arguments instead of
  escaping it into the script.

### Fixed

- **A timeout stops everything the command started.** `agents` (tmux,
  Herdr, `lsof`, AppleScript) and `notify.sh` killed only the command
  itself: a process it had started kept a `$( )` waiting past the timeout,
  and the timer's own `sleep` was left behind when the command finished
  first. The command and the timer now run in process groups of their own.

## [3.8.1] - 2026-10-15

CI is green again for 3.8: the new tests pass where fzf is installed and
under shellcheck 0.9. No change to what `agents` does.

### Fixed

- **Tests:** `agents pick`'s "without fzf" test no longer finds the Alpine
  image's fzf (a test names a missing one through `AGENTS_FZF`, read only
  under `AGENTS_TESTING`), and the MCP and show tests are clean under
  shellcheck 0.9 (stubs marked, no `A && B || C`).

## [3.8.0] - 2026-10-15

Every process the menu lists now has a detail view and one click to the session
it belongs to (Herdr, tmux or the terminal tab), MCP servers go by the names you
gave them, and the token report learns what the tokens would cost at API list
prices, who drove them, and which MCP servers, skills and plugins your sessions
load but never use. The menu refreshes in half the time, and the
minute-by-minute sample stays cheap on a heavy machine.

### Added

- **`agents show PID`**: one process in detail, like Activity Monitor's
  inspector: what and whose it is, its verdict and evidence (as `agents why`),
  its session (id, name, model, version, from Claude Code's
  `sessions/PID.json` or Codex's open rollout file), what that session is
  doing now (the last tool call and its target, the last line it wrote, read
  from the transcript's last 256 KiB), where it lives, its runtime, CPU, CPU
  time, memory, threads, ports, open files and children. `--watch` redraws it
  every 2 s; `--json` gives a versioned object.
- **`agents jump PID`** goes to where a process runs so you can answer it: its
  Herdr pane (by session id or processes, else by directory; `herdr agent focus`) or
  tmux pane, then the terminal tab that shows it (Ghostty 1.3+, iTerm2 and
  Terminal by tty; any other app is brought forward). **`agents peek PID`**
  prints the last lines of its tmux or Herdr pane.
- **`agents pick`**: everything in fzf, with `agents show` as the preview;
  enter jumps, ctrl-p peeks, ctrl-d opens the details live, ctrl-k kills. The
  list reloads every 2 s where fzf has `every()` (0.70+).
- **MCP servers by name.** `agents mcp [DIR]` lists the servers Claude Code
  (user, local, project and plugin scope) and Codex are configured with, and
  every MCP-server process goes by its configured name in `agents ls`, `ps`,
  `json`, `tsv` and the menu (`playwright · api · 0% · 211M` under MCP
  servers), else by its package (`@playwright/mcp` → `playwright`). Only names,
  scopes, sources and the word that starts each server are kept: never args,
  env, headers or URLs, and never a flag's value (`node --token VALUE x.js`
  keeps `x.js`). A configured server whose command line does not say `mcp`
  now counts as an MCP server; it is matched by a whole word of the command
  line, never part of one, and a word too common to name one (`ssh`,
  `cargo`, `dist/index.js`) is not used.
- **Menu:** every session and Needs-you submenu starts with **Jump to
  session**, and sessions, Needs-you items, stale processes and every row under
  Where the CPU goes get a summary (status, where it lives, busiest command)
  with Peek and Details.
- **API-equivalent cost.** `agents report` (the summary's Tokens line, the
  tokens view and their JSON) shows what the tokens would cost at API list
  prices, which now ship with `agents` (`lib/agents/prices.tsv`, Anthropic's
  and OpenAI's list prices as of 2026-09-29, with their sources). One-hour
  cache writes cost their own price, apart from 5-minute ones. A model takes
  the longest price prefix that names it up to a version boundary, so
  `claude-opus-4-8` never takes `claude-opus-4`'s price; a model without a
  price shows as `unpriced`, never `$0`. `AGENTS_PRICES` now changes or adds
  prices over the shipped ones (its old five-column lines still work), and
  `AGENTS_PRICES=off` hides costs. Costs never appear in the menu bar.
- **Tokens by session and by origin.** The tokens view adds a session table
  and splits sessions and tokens by who drove them: `you` (the CLI, desktop
  app or an IDE), `headless` (the Agent SDK, `claude -p`, `codex exec`),
  `subagent` or `fork`. `tokens.tsv` rows gain two columns,
  `cache_write_1h` and `origin`; rows written before stay valid.
- **`agents report --view context`**: per window (default 7d), the MCP
  servers sessions call and the ones their deferred tool lists load (with
  how many tools each lists, a proxy for the context it takes), skills and
  subagent types used, the enabled Claude Code plugins with what each brings
  (skills, agents, commands, MCP servers, hook events), every configured MCP
  server (Claude Code's user, local, project and plugin ones, Codex's, all
  from `mcp.sh`'s inventory) with its calls, and cleanup candidates: what is
  loaded or enabled but unused, with where to remove it. Names and
  counts only; no config value is ever printed or stored. The scan records
  what it needs in `uses.tsv`.
- `agents_session_tokens` (`lib/agents/report.sh`): one session's origin,
  CLI, project, model, calls, tokens, API-equivalent cost and the tokens no
  price names, for a view of a single session. `agents show` says
  `$3.40 API-equivalent (part unpriced)` when some of them have no price.

### Changed

- **The menu refreshes in about 0.15 s instead of 0.3 s** on a Mac with 900
  processes: the plugin forks 3 times instead of about 60, and `agents tsv`
  runs `lsof`, `launchctl`, tmux and the machine's probes alongside `ps`,
  looks up the cwds the last refresh asked about early, and classifies with
  `index()` where it used regexes.
- MCP servers' names lose their `-mcp` suffix when no config names them
  (`chrome-devtools-mcp` → `chrome-devtools`), in `agents json` too. `agents
  ls` shows the names on each session's `mcp:` line.
- **The run ledger no longer searches transcripts.** Finding which agent
  started a background command used to `grep` the session's whole main and
  subagent transcripts each time commands ended (10 s on a 395 MB session).
  The token scan, which reads every new line anyway, now notes each task id
  and whose transcript named it (`tasks.idx`), and runs before the ledger:
  the lookup takes 25 ms, with the same answers. An id not indexed yet is
  searched for only in the transcripts changed since the run started, in
  their last 8 MiB.
- **The scan state stays put.** `tokens.state` (800 KB on a heavy machine)
  was rewritten every minute. A sample now rewrites only `tokens.hot`, the
  few transcripts active within the hour, and only when it changed; the cold
  majority is rewritten when 64 lines have gone cold and once a day. A
  sample also lists only the transcripts changed since the last one and the
  hot ones; every hour it lists them all, and so does every sample while a
  first catch-up still has transcripts to read.
- **A month of tokens reads in a fraction of the time.** Once a day, the
  token rows from before yesterday become one row per day and name, at the
  top of `tokens.tsv` (some fortyfold fewer rows). `agents report --view
  tokens --since 30d` goes from 1.3 s to 0.2 s on 123,000 rows; windows of
  up to 24 hours still count each row by its time, and longer ones count
  their first day whole (the view says from when).

### Migration

- **`AGENTS_PRICES` prefixes now match only at a version boundary.** A line
  from 3.7.1 such as `claude-sonnet` no longer applies to
  `claude-sonnet-4-5`, which then takes the price that ships with `agents`,
  or shows as `unpriced` when none does: write full model ids
  (`claude-sonnet-4-5`), or end a prefix in `-` to name a whole family
  (`claude-sonnet-`). Your file only needs what the shipped prices leave
  out or what you price differently. Models whose list
  price could not be checked (such as `gpt-5-codex`, `gpt-5.1-codex`,
  `gpt-5.2-codex`) are left out on purpose: add them to your file to price
  them.

## [3.7.1] - 2026-10-15

A process that has exited is gone, even before its parent reaps it.

### Fixed

- `agents` treats a zombie (a process that has exited but whose parent has
  not reaped it yet) as gone. In a container whose init reaps late, `agents
  kill` used to wait out the whole grace period and send a pointless SIGKILL,
  and a lock or keep-awake holder that had died could look alive. This was
  also the cause of the occasional live kill test failure in containers.

## [3.7.0] - 2026-10-14

`agents` now shows where your tokens go: by model, CLI, subagent type and
project, how much the prompt cache saves, what polling and compactions cost,
and which commands you or auto mode keep denying. It reads the transcripts
Claude Code and Codex already write. Nothing is sent anywhere, and nothing
needs setting up.

### Added
- **Token telemetry.** Each `agents sample` reads what is new in the Claude
  Code transcripts (`~/.claude/projects`, subagents included) and the Codex
  session logs (`~/.codex/sessions`). It records one row per model call in
  `tokens.tsv`: model, CLI, project, session, agent type, input, cache write,
  cache read, output, and whether the call only waited on something
  (polling). It also records context compactions (`compacts.tsv`), denied
  tool calls (`denials.tsv`) and the Codex plan's rate-limit window
  (`limits.tsv`).
  - Each message counts once: the repeated lines of one message, forks'
    copies of their parent's history, and resumed or rewound sessions are
    skipped.
  - The scan reads at most 64 MiB per sample and resumes where it stopped,
    newest files first. Today's numbers arrive within minutes; a heavy
    month's history fills in over the first hour or two.
  - It works with BSD, GNU and BusyBox tools. Rows are kept for
    `AGENTS_HISTORY_DAYS` like the rest of the history; `AGENTS_HISTORY=0`
    turns it off.
- **`agents report --view tokens`.**
  - Totals and the cache hit rate, then the same columns by model, by CLI, by
    agent type (`main`, `Explore`, `implementor-complex`, `fork`…) and by
    project. Subagent worktrees count toward their repo.
  - Tokens spent polling, by agent; compactions, auto and manual; the Codex
    plan's used share and when it resets.
  - `--json`, with `schema_version` 1.
- **`agents report --view denials`.** Tool calls denied by you, by Claude
  Code's auto-mode classifier (with its reason) or by a safety check, grouped
  by command, agent and project. For a command that keeps being denied, a
  hint says what to change: an allow rule, an instruction, or nothing, when
  the classifier is holding it for you on purpose.
  - A command is recorded by its program and a known subcommand only
    (`git push`, `kubectl apply`), never an argument or option value. In a
    compound command it is the program that acts, not the `cd` or `grep`
    around it. A web fetch is recorded by host only.
- **Insights for tokens and denials.** The report's Top insights (and the
  menu's) now also flag:
  - a CLI below 70% cache hits on 1M+ input tokens;
  - polling above 5% of tokens;
  - a session that filled its context and compacted automatically 3 or more
    times;
  - a command you denied 3 or more times.
- **The menu shows today's tokens:** `12.4M tokens today · 94% cached`, under
  today's CPU. A click opens the tokens view.
- **An optional cost estimate.** Copy
  `configs/agents/agents-prices.example.tsv` to
  `~/.config/tuidev/agents-prices.tsv` (or set `AGENTS_PRICES`) and fill in
  your prices per million tokens. The tokens view and the summary then show
  an estimated dollar figure, labelled as an estimate. tuidev ships no
  prices: without the file, you see tokens only.

### Changed
- The summary report gains a Tokens line (total, cache hits, polling share,
  compactions, and the estimate when priced) and a Denials line.

## [3.6.0] - 2026-10-14

`agents` now remembers every command your agents run and tells you what to
change: a run ledger, report views with top insights (in the menu too), on a
modular codebase. And the README finally shows it: Herdr across machines,
cleanup with evidence, the menu bar and the shell, each with a picture.

### Added
- **Run ledger and `agents runs`.** Every finished command (a tool shell and
  everything under it, or a stale tree) gets one row in `runs.tsv`: when, how
  long, CPU, peak memory, exit code (from Claude Code's task output), project,
  session, the agent type that started it (`main`, `Explore`, a named
  subagent, `fork`), and whether it was a duplicate or stopped by agents. The
  menu's 10 s refresh feeds the ledger from the snapshot it already takes, so
  runs shorter than a minute count too, and `history.tsv` no longer loses a
  command's last minute. Names only, never arguments. `agents runs [--since
  24h|7d|30d|today] [--json]` lists them, newest first.
- **`agents report --view runs|waste|trends|agents`.** The most repeated and
  slowest commands (median, p90, failure rate); waste (duplicate runs, runs
  left running until a cleanup, polling time, failed runs re-run at once);
  trends against the window before, with regressions flagged; and all of it
  per agent type. `--json` for each (additive, `schema_version` 1); the
  summary adds `insights` and `runs` (`count`, `failed`, `dup`, `cleaned`).
- **Top insights.** The report opens with the three findings worth acting
  on, ranked by the CPU at stake, each saying what to do: "agentic-vms: `go`
  test runs ×281 in 7d, 50 duplicates (9.5 CPU-h) — consider a shared test
  cache or serializing them". Each sample refreshes today's top one, and the
  menu shows it under Today (the full sentence as its tooltip); a click opens
  that view.
- **`./uninstall.sh --purge-history`** deletes the agents history; in a
  terminal uninstall asks (default: keep), `--all` keeps it.
- **`AGENTS_HOOK_LOG=1`** logs each cleanup-hook run (event, agent id,
  handback seen, tasks, matches; no command lines) to a private `hooks.log`,
  with a "Verify the cleanup hooks" guide.
- **The README tells the story, with proof:** `herdr.gif` (a real Herdr
  driving three machines, with scripted agent stand-ins), `cleanup.gif` (a
  loop stuck on a finished task, `agents why`, the report's Top insights),
  `cli.gif` (the shipped zsh and tools), and the menu bar in light and dark,
  drawn from the plugin's real output by `scripts/render_menu.sh`. All of it
  regenerates with `make screenshots`, on demo data only.

### Changed
- **`agents` is modular:** a thin `bin/agents` and `lib/agents/*.sh` plus
  `lib/agents/awk/*.awk`, one responsibility each, shared helpers in one
  place (map in docs/engineering.md). The monitoring pack installs the
  modules to `~/.local/lib/tuidev/agents`, each recorded for `uninstall.sh`;
  the health check catches a missing one. Output is byte-identical to 3.5.1
  (checked by 73 golden files under BSD awk, gawk, mawk and BusyBox), except
  durations, which now read the same everywhere: `42s`, `7m03s`, `1h05m`.
- The menu refresh forks less: one clock per refresh, and the run feed is
  skipped when nothing runs.

### Security
- Names that come from transcripts (agent types) or directories (projects)
  are reduced to plain text before they are stored or shown: no control
  characters reach your terminal, the menu or a notification.
- Locks record their holder and are taken over only when it is gone, and a
  run releases only its own lock. A sample commits its history before the run
  ledger, so a ledger failure can't make the next sample count CPU twice.
- `agents` started through a symlink to a checkout loads that checkout's
  modules, even next to an older install, and checks every awk program is
  present before it runs anything.
- `AGENTS_NOW` is honored only under `AGENTS_TESTING`, so a stray export can't
  freeze the caches.
- The screenshot tapes run in a clean environment and can't pick up the
  renderer's shell history, zoxide database or zsh config.

### Fixed
- A bad `AGENTS_JOB_*` pattern no longer prints bash's regex error.
- A sample with nothing running no longer prints an `mv` error.
- `agents report` pairs failed runs with their re-runs in the order the runs
  ended, not the order `runs.tsv` stored them.
- `uninstall.sh`: a prompt that gets no answer counts as no instead of
  aborting.
- Tests no longer depend on the length of `$TMPDIR` or its trailing slash.
- `make screenshots`: demo homes live under `/tmp`, so the demo Herdr
  socket fits the 104-byte limit.

## [3.5.1] - 2026-10-14

### Fixed
- **`agents json` and `agents report --json` on Debian and Ubuntu.** Their
  default awk (mawk) caps a single `sprintf` at 8 KiB, so a busy machine
  (many flagged commands, each with its verdict and evidence) aborted the
  JSON. Lists are now joined, not formatted.
- **Ties sort the same everywhere.** Job, project and cleanup lists that
  tie on CPU or count are ordered by name, so BSD, GNU, mawk and BusyBox
  agree (`today.tsv`, the menu and `agents report`).
- No `/proc/PID/cgroup` noise on Linux when a process exits mid-scan.
- CI: the new test harnesses are clean under the runner's shellcheck.

## [3.5.0] - 2026-10-14

Needs you now explains itself, agents stop leaving processes behind, and
`agents` shows where your CPU goes, today and over time.

### Added
- **`agents why PID`: is a Needs-you item safe to stop?** Every stale tree and
  every command flagged `stuck`, `long` or `dup` comes with its evidence and a
  verdict. The evidence: who owns it (or that its session ended), its age,
  CPU and ports, and for a polling loop the file it watches, that file's last
  line and how long ago it changed. The verdicts: **safe to stop** (a helper of
  an ended session; a loop whose file already says `[exited with code 0]`,
  `ok`, `FAIL`, `--- FAIL`…, or stayed quiet), **check first** (anything
  listening on a port; a loop judged by its age alone), **leave it** (its file
  is still changing) and **informational** (a long build or server of a live
  session). One function makes the verdict for `why`, `agents json`
  (additive `verdict` and `evidence` fields, schema 1) and the menu.
- **Menu: each Needs-you item shows its verdict** (`· safe to stop`,
  `· check first`, `· informational`) and, in its submenu, the evidence, then
  Stop command…, Copy details and Show session. Stale items get the same.
- **Claude Code cleanup hooks.** The shipped settings run `agents hook` on
  `SubagentStop` and on `SessionEnd` (`/clear`, `/resume`). Once a subagent
  hands back its final report, the background commands it left running (test
  runs, dev servers, `until …; do sleep; done` loops) are stopped; on `/clear`
  or `/resume`, the session's own polling loops and its finished subagents'
  leftovers are. Each command is matched to its process by its
  `tasks/<id>.output` file, only under the
  `claude` that ran the hook, and stopped through the usual start-time-pinned
  kill. Never another subagent's or session's work, the main conversation's
  servers, or anything under tmux or Herdr. The hook always exits 0, is a
  no-op without the `monitoring` pack, logs and notifies each stop;
  `AGENTS_HOOK_REAP=0` turns it off and `agents hook … -n` shows what it would
  stop. Even on 80 MB transcripts a hook takes about 2 s. Existing installs get the hooks with `make update-configs` (the
  settings are three-way merged). Codex isn't covered: its hook transcripts
  aren't a stable interface yet.
- **Opt-in auto-reap (`AGENTS_AUTO_REAP=1`)** stops, without asking, only the
  leftovers of ended sessions that listen on no port and polling loops stuck
  on a file quiet for twice `AGENTS_WAIT_STUCK`; never a server, a long
  command or a loop stuck by age alone. The menu runs it in the background at
  most once a minute; `agents reap --auto` does the same from cron (`-n` shows
  what it would stop). One notification sums up each run.
- **Where the CPU goes: job types.** Every process in an agent's tree (and in
  a stale one) counts toward one job: `test`, `build`, `server`, `browser`,
  `mcp`, `agent`, `wait` or `other`. A command and everything it starts share
  its job (a `go test` and the binaries it compiles are `test`); agents and
  browsers keep their own. The built-in patterns cover go, cargo, pytest,
  jest/vitest, npm/pnpm/yarn scripts, make, tsc, webpack/vite/next, dev
  servers, headless Chrome and Playwright; `AGENTS_JOB_TEST`, `_BUILD`,
  `_SERVER`, `_BROWSER` and `_MCP` add your own. `agents json` gives each
  entry its `job` and adds a `jobs` list. The menu's new Where the CPU goes
  section (`jobs` in `AGENTS_BAR_SECTIONS`) lists CPU by job, busiest first,
  each with the sessions behind it, then `Today: 3.4 CPU-h · tests 40%` and
  Open report.
- **Local history and `agents report`.** With `AGENTS_HISTORY=1` (the default)
  `agents sample` records, once a minute, the CPU time each job used per
  project and session (from per-process CPU time keyed by pid and start time)
  in `~/.local/state/tuidev/agents/history.tsv`, and every cleanup (`kill`,
  `reap`, `auto`, `hook`) in `events.tsv`. Names only, never command lines;
  nothing leaves the machine; kept `AGENTS_HISTORY_DAYS` (30). The menu starts
  the sample in the background; `agents watch` does too, and elsewhere a cron
  line does. `agents report [--since 24h|7d|30d|today] [--json]` shows
  CPU-hours by job, the top projects, CPU by session kind, the busiest hours,
  and the cleanups with the projects that leave things behind most.
- **A new orchestration rule against leaked background processes:** run tests
  and builds in the foreground or as a background task the harness reports
  on, never poll in a `sleep` loop, keep wanted servers in tmux, and stop
  everything else you started before reporting done. AGENTS.md says the same.

### Security
- **Every automatic stop needs proof, not a guess.** The cleanup hooks match
  a task to a process only by its `tasks/<id>.output` file; if that can't be
  read, nothing is stopped. Auto-reap stops a stale tree only if `agents
  sample` saw it under an agent before its session ended, only when the port
  check worked, never a `caffeinate` without `-t`, and never a loop that only
  tests that a file exists (`while [ -f lock ]`). Overlapping menu refreshes
  can't start two reaps.
- **History is private**: `~/.local/state/tuidev/agents` is 700 and its files
  600. `agents why` and the menu never show the last line of a symlink or of
  a file under the sandbox credential paths (`~/.ssh`, `~/.netrc`, …);
  `test_contract.sh` keeps that list in step with `credential-paths.txt`.
- `AGENTS_JOB_*` patterns are rejected unless both the shell and awk accept
  them.

### Fixed
- `test_agents.sh` runs the live lid tests on macOS only, so the Alpine CI
  job passes again (3.4.0's CI run failed there; the release itself was
  unaffected).

## [3.4.0] - 2026-10-14

### Added
- **`agents reap --stuck`** also stops the polling loops flagged `stuck`
  (dry run with `-n`; the same start-time checks as every kill). Plain
  `reap` still kills stale trees only.
- **`AGENTS_WAIT_STUCK`** (minutes, default 60; `0` turns it off) in
  `~/.config/agents.conf`. A bad value for it, or for the `AGENTS_LID*` keys,
  set in the environment falls back to the default with one warning, as one
  in the file is ignored.
- **Keep awake with the lid closed (macOS): Awake › Lid closed too… in the
  menu, or `agents awake lid 3h`.**
  `caffeinate` can't keep a closed lid awake, so this runs `pmset -a
  disablesleep 1` after macOS's own admin dialog, every time. No sudo rights
  are stored. It is always time-boxed (`AGENTS_LID_MAX`, default 8h). The
  same root command starts a small root-owned guard in a session of its own
  (perl's `setsid`), which turns lid sleep back on when the time is up, below `AGENTS_LID_MIN_BATTERY` (20%) off AC, or
  when thermal pressure reaches heavy. The usual `caffeinate -di` holder
  runs alongside for the same time. `agents awake off` ends it early (one more
  dialog), and `agents awake restore` turns lid sleep back on whatever
  disabled it; `awake on` and `awake agents` replace only the `caffeinate`
  holder and leave lid mode running. The dialog comes from
  `/usr/bin/osascript` started with an empty environment, and the root
  command uses absolute paths only. A guard is signalled, or counted as
  running, only while it is root's (real uid) and named `agents-lid-guard`.
  Lid mode is never left without a guard: the root command checks the guard
  two seconds after starting it and restores sleep itself if it is gone, and
  `agents` checks again after the dialog returns ("lid mode failed to start;
  sleep restored"). macOS keeps the setting across a reboot that kills the
  guard, so `agents`, `agents awake status`, the menu (a red Restore lid
  sleep…) and `make check` warn: "lid sleep is disabled and nothing will
  restore it"; `awake off` then restores it too. The menu's Lid closed too…
  group (1h, 3h, 8h) shows by default (`AGENTS_LID=0` hides it), End lid mode
  now… appears while it is on, and its results come back as notifications.
  Linux reports it as unsupported. `agents json` gains a `lid` object, and
  `awake.mode` can be `lid` (still `schema_version` 1).

### Changed
- **The README presents tuidev as a terminal dev environment for AI coding
  agents, not a process monitor.** It opens with a short GIF tour (the shell,
  `agents`, `sbx`) and seven pillars: the modern terminal and its tools (with
  a table by category), sandboxed agents, tiered orchestration, agent
  workflow support (worktrees, notifications, Herdr, `hunk`), `agents` and the
  menu bar, remote sessions, and an undoable install. VISION, the quick start
  and CONTRIBUTING open with the same description, and the social preview
  card's subtitle is no longer monitoring-centric.
- **New images:** `docs/assets/tour.gif` (the hero) and `shell.png` (the real
  Starship prompt with the shipped config and palette, `ll src` with icons
  and a git column, `rg`, and `git diff` through delta, in a demo repo), from
  `tour.tape` and `shell.tape`. The tapes' font falls back to the Symbols
  Nerd Font so the icons render; `make screenshots` warns when it is missing
  (`brew install --cask font-symbols-only-nerd-font`).
- **The `sbx` screenshot tells a before/after story.** It reads a made-up key
  without a sandbox, then shows `sbx` refusing that read, the AWS credentials
  and a write to `~/.zshrc`, while `make test` still runs. Its demo home is
  now `/Users/Shared/NAME` (strict lets `sbx` write to `$TMPDIR`, which would
  have made the write denial false).
- **`make screenshots` is stricter.** It deletes each tape's old images first
  and fails if one is not written: VHS can drop a `Screenshot` that is a
  tape's last command, so the tapes now end with a `Sleep`.
- **`make check-paths`, and `make ci-test` runs it.** CI's "no hardcoded
  paths" scan moved into `scripts/check_paths.sh`, which the workflow and the
  new target both call, so the local gate catches what CI would. The
  screenshot demo's home, `/Users/Shared/NAME`, is an accepted placeholder.

### Fixed
- **A polling loop that never ends no longer reads as a calm "waiting".**
  Claude Code ends a background task's `.output` with `[exited with code N]`,
  so a subagent's `until tail -1 $F | grep -q ok; do sleep 5; done` spins
  forever, and `agents` showed it as a gray hourglass for hours. A `wait`
  loop is now also flagged `stuck` once it has run `AGENTS_WAIT_STUCK`
  minutes, unless the file it watches changed within that time (a long
  build's log: the producer is alive). The watched file is the first absolute
  path its condition gives to `tail`, `head`, `grep`, `cat`, `test`, `[` or
  `[[`, directly or through `F=/path` before the loop; one `find -mmin`
  checks every such file.
  `agents ps` shows `stuck`, `agents json` adds it to the tool's `flags`
  (still `schema_version` 1: the flag is added next to `wait`), and the menu
  shows an orange hourglass with Stop command… under Needs you, which tints
  the icon but doesn't count as blocked. `docs/agent-workflows.md` tells
  agent authors to match the exit line or cap their tries.
- **The Starship prompt shows its Nerd Font icons again.** The shipped
  `starship.toml` had lost every glyph in the Unicode private-use area: the
  git branch, Python, Node, Rust, Go, Java and Docker symbols were plain
  spaces; `~/Downloads`, `Music`, `Pictures`, `workspace` and `projects`
  showed as a blank instead of an icon; and the conflicted, stashed, renamed
  and deleted git states were empty, so they never showed. They are glyphs
  again (the branch is U+F418), and the four git states use Starship's
  defaults (`=`, `$`, `»`, `✘`). `./install.sh` or `make update-configs`
  refreshes the managed block.

## [3.3.3] - 2026-10-14

### Added
- **Reproducible screenshots: `make screenshots` (macOS).**
  `docs/assets/agents.png`, `sbx.png` and the 1280×640 `social-preview.png`
  are rendered with VHS from tapes in `docs/assets/tapes/`, in the Tokyo
  Night palette and the Ghostty font. The `agents` and `sbx` tapes run in a
  throwaway home, and `agents` reads fixture process tables and working
  directories through stubbed `ps`, `lsof` and friends (and never signals),
  so no image shows the machine that rendered it. The SwiftBar menu can't be
  recorded headlessly; `docs/assets/tapes/README.md` has a by-hand recipe
  over the same fixtures. How and when to re-render is in
  `docs/engineering.md`.

### Changed
- **A README for newcomers.** One-line value proposition, a screenshot of
  `agents` up top, "Why tuidev" as outcomes (credentials kept from agents,
  agent processes in view, tiered subagents, an install you can undo,
  durable remote sessions, one palette, Linux), who it is and isn't for,
  and a packs-at-a-glance table. The docs index is unchanged, plus a row
  for the screenshot tapes; a release badge joins CI and license.
- **The quick start says to install Claude Code and Codex first** (tuidev
  configures them, it doesn't install them) **and installs `--pack ai-clis`
  in step 1**, so `claude` and `codex` are sandboxed in step 2 as the guide
  says. VISION, the quick start and CONTRIBUTING open with the same
  positioning as the README.

### Fixed
- **`agents` uses the full width of a wide terminal.** It asked `tput cols`
  for the width inside `$( )` with stderr silenced, where `tput` sees no
  terminal and answers 80, so the CWD column and long commands were cut
  unless `COLUMNS` was exported. It now reads the size from the tty.

## [3.3.2] - 2026-10-14

### Changed
- **The `ui` pack no longer installs Stats.** The `monitoring` pack's
  SwiftBar menu shows CPU, memory, load, battery, thermal pressure and the
  energy mode, so a second stats app only duplicated it, and the health
  check stops requiring `Stats.app`. Stats stays installed where it is;
  remove it with `brew uninstall --cask stats` if you use the agents menu.

## [3.3.1] - 2026-10-14

### Fixed
- **Duplicate counts in the agents menu read `2×` again.** Under macOS's
  `/bin/bash` 3.2, which SwiftBar runs the plugin with, "Stop duplicates"
  and the Needs you line showed a garbled character instead of the count.
- **CI is green on macOS again.** The apt package-update test now runs on a
  Mac too, and the shellcheck job accepts the runner's older shellcheck.

## [3.3.0] - 2026-10-14

### Added
- **`agents`: see and clean up agent processes (`--pack monitoring`).**
  Every `claude` session starts its own MCP servers, and a session that dies
  badly leaves them running under launchd. `agents` lists each `claude` and
  `codex` tree (CPU, memory, cwd, ports, Herdr status; the Codex app-server
  daemon gets its own row), flags orphaned MCP servers, npx helpers,
  `caffeinate` and dev servers as stale, and shows CPU hogs of any owner.
  `agents kill`/`reap`/`term` signal descendants first, re-check each
  process's start time before every signal, and refuse pid 1, their own
  parents, other users' processes, system and session processes (Finder,
  loginwindow, your terminal, `/System/Library`) and running as root. Nothing
  that hosts a session (a shell, tmux, screen, zellij, Herdr, an agent), no
  launchd job and no systemd service is ever called stale. `agents awake`
  keeps the Mac awake with `caffeinate -di` (for a duration, or while agents run), and `agents thermal`
  shows thermal pressure and the energy mode. `agents watch` redraws live;
  `agents json`/`tsv` are machine-readable. Standalone bash 3.2, no sudo.
- **SwiftBar menu for agents and the system (macOS).** The `monitoring` pack
  installs SwiftBar and an `agents` plugin that also covers a stats app. The
  title is an SF Symbol, the session count and `· N blocked` when sessions
  wait for you, tinted only when something needs a look. The menu leads
  with what needs you (blocked sessions), then one line per session
  (project, status dot, CPU, memory; path, Copy path, Open in Finder and a
  dialog-confirmed Kill session… in its submenu), stale processes and hogs
  only when there are any, keep-awake with the active choice checked, and a
  two-line system view (CPU, memory, load with the busiest processes;
  battery, thermal pressure, energy mode). Actions report their result as a
  notification, and windows open in your terminal (`agents open-term`,
  `AGENTS_TERMINAL`: Ghostty, iTerm, WezTerm, kitty or Terminal) rather than
  SwiftBar's Terminal.app. A refresh takes 0.2–0.6 s depending on load;
  Herdr's answer is cached and never waited on. A plugin folder you already
  set is kept.
- **What each agent session runs.** `agents ls` and `watch` list under each
  session its MCP servers on one line and its busiest commands: the real
  command of each tool shell (`go test -race ./internal/web`, not the
  `zsh -c … eval` wrapper), how long it has run, its CPU and the worktree
  subagent it runs for. Commands running twice are flagged `dup`, over 20
  minutes `long`, and a full core or more `hot` (polling loops agents
  wait on are marked `wait` instead). `agents ps PID` lists
  everything. In the menu, a session shows how much of its CPU its commands
  use, lists them under Running with Stop command…, and duplicates and
  long-running commands appear under Needs you with Stop duplicates (keep
  newest)…. `agents json` gains `schema_version` 1 and an `activity` object
  per session, documented as a stable contract.
- **`~/.config/agents.conf`.** Thresholds, the menu-bar title tokens and
  icon, which sections show and in what order, and the refresh interval, in
  a commented file placed once and never overwritten. It is read as
  `KEY=value`, never sourced: unknown keys and bad values are reported and
  ignored. `agents config` prints the settings in effect.
- **Package updates on Linux.** `update.sh --packages` (and `make update`)
  stopped at "brew not found" on apt, dnf and pacman machines. It now checks
  the pack packages the native manager installed and upgrades the outdated
  ones in one batch, never installing anything new. Without root or
  passwordless sudo it reports from the cached lists and prints the
  `sudo` command instead of prompting. A failed probe reads "status
  unknown", apt keeps auto/manual marks, and pacman gets `sudo pacman -Syu`
  rather than a partial upgrade.

### Changed
- **Tailscale installs as the `tailscale-app` cask.** Homebrew renamed the
  cask and moves existing installs itself; a migration renames the record in
  `~/.config/tuidev/manifest` so uninstall uses the new name.
- **CI's macOS job runs on `macos-26`, and the Linux test image on Alpine
  3.24.**

### Fixed
- **Repo check no longer claims "up to date" after a failed fetch.**
  `update.sh --check` compared against the stale upstream when `git fetch`
  failed (or under `--dry-run`) and reported success. It now says the status
  is unknown, fetches the branch's own remote, reports a missing upstream,
  and tells ahead from behind.
- **A moved checkout's old path no longer sticks.** Re-running `install.sh`
  read the profile's old `repo=` path over its own location and wrote it back
  to the profile and `~/.config/tuidev/env`, so repo sync kept skipping a
  directory that no longer existed. The installer now records where it runs
  from, and `update.sh` falls back to its own checkout when the recorded path
  isn't one.
- **`dust` and `bottom` install on Debian.** apt ships them as `du-dust` and
  `btm`; `pkg_install` reported both as unavailable. apt probes also run
  under `LC_ALL=C` and ignore removed-but-configured packages.

## [3.2.8] - 2026-10-07

### Fixed
- **No install hint for packages the distribution lacks.** Without
  passwordless sudo, `pkg_install` put every missing package in its
  `sudo apt-get install` hint, including ones apt can't supply (Debian has no
  `zsh-completions`). It now probes the cached lists first and reports those
  as unavailable.

## [3.2.7] - 2026-10-07

### Fixed
- **No sudo warning for packages already present.** Without passwordless
  sudo, `pkg_install` warned and printed an install command before checking
  what was installed, so packs on such Linux boxes flagged tools they had
  (`vim not installed`). It now asks for root only for missing packages.

### Changed
- **Clickable file paths.** The orchestration policy asks agents to write
  file paths as Markdown links to absolute `file://` URLs, which Claude Code
  emits as OSC 8 links: Ctrl-click in Herdr or Cmd-click in Ghostty opens the
  exact file, where plain-path matching grabs stray dots and words.
- **Herdr link clicks documented.** `agent-workflows.md` says Herdr opens pane
  links on Ctrl-click (Cmd-click never reaches it), Shift-Cmd-click hands the
  click to Ghostty, which also opens plain file paths, panes from before the
  `FORCE_HYPERLINK` fix need `exec zsh`, and OSC 8 clicks on saved-machine
  panes don't work yet (herdr#4447).

## [3.2.6] - 2026-10-02

### Changed
- **Herdr docs cover sessions and devices.** `agent-workflows.md` explains
  one session per machine versus named sessions, which session a saved
  machine joins, the `HERDR_SOCKET_PATH`-wins-in-a-pane pitfall, and a
  systemd user unit plus linger for always-on nodes. The cheatsheet gains
  `session list/attach/stop` and `machine status`; `remote.md` shows joining
  Herdr from a phone and a phone-friendly second prefix (Herdr 0.9.2).
  `machine add` examples drop the now-optional `--label`, and the docs note
  that `herdr update` must run outside Herdr.

## [3.2.5] - 2026-10-02

### Fixed
- **Clickable links in Herdr panes.** Herdr 0.9.2 sets `TERM_PROGRAM=herdr`,
  so Claude Code stopped emitting OSC 8 links; `.zshrc` now exports
  `FORCE_HYPERLINK=1` inside Herdr panes unless it is already set.

### Changed
- **`update.sh --packages` names Apple `container`.** It is pkg-installed, so
  no pack tracks it; the run now prints its version and Apple's
  `update-container.sh` path (checked against container 1.5.0 and Podman 6.1.3,
  neither of which changes a command tuidev uses).

## [3.2.4] - 2026-09-29

### Added
- **`uv` and `xh` in `--extras`.** uv for Python versions, venvs and tools;
  xh replaces httpie.
- **One credential list.** `configs/sandbox/credential-paths.txt` is the
  canonical deny set; `test_contract.sh` fails when `bin/sbx`, the `.sb`
  profiles, the Claude deny rules or the docs drift from it.

### Changed
- **`.zshrc` loads Node only through fnm.** The nvm fallback is gone; a
  migration warns machines still on nvm and leaves `~/.nvm` alone.
- **`--pack monitoring` is `lazydocker` and `bottom`;** `k9s` is out.
- **`health_check.sh` recognizes `--pack orchestration`** by its rule file.
- **`test_theme.sh` skips the live tmux check** when a sandbox denies the
  socket, instead of failing the gate.

### Removed
- **`--pack cmux`** (tmux is the multiplexer) and **`--pack mosh`**
  (`--remote` already installs it). Migrations drop both from your recorded
  packs; the apps stay installed.
- **Hidden Bar** from `--ui`; macOS hides menu-bar items natively.
- **`ncdu`, `bandwhich`, `fastfetch`, `httpie`** from `--extras`, with the
  `sys` and `http` aliases, and the pyenv shims line from `.zshrc`.
- **`scripts/setup_agent_configs.sh`.** Claude Code and Codex read
  `AGENTS.md` natively.

## [3.2.3] - 2026-09-28

### Added
- **`--pack hunk`.** Installs [hunk](https://hunk.dev), a review-first diff
  viewer for agent-written changesets (`hunk diff --watch`, `hunk show`), from
  Homebrew. Opt-in because upstream is 0.x; it writes nothing to `$HOME` and
  prints the `git config --global core.pager "hunk pager"` opt-in.
- **Background sessions in `docs/agent-workflows.md`:** `claude --bg`,
  `claude agents`, `attach|logs|stop|respawn|rm`, `/bg` and `/fork` (each in
  its own worktree), Codex's worktrees-by-default, and how background
  sessions treat git and the `ask` rules.
- **Recent sandbox behavior in `docs/sandboxing.md`:** `!` commands run
  outside Claude Code's sandbox, `sandbox.network.strictAllowlist` for
  unattended runs, `sandbox.ripgrep` and `excludedCommands` scope, and
  Codex's background server relative to `sbx`.

### Changed
- **tmux: the current window keeps its plain style on tmux 3.8+,** which
  underlines it by default. `window-status-current-style` is pinned to
  `default` in `tmux.conf` and the generated `theme.conf`.
- **`implementor-standard` finishes what it starts and stays in scope.** On
  Sonnet 5.5 at `medium`, Anthropic notes it can stop to check in before a
  task is done and add unrequested tests or docs; one body line covers both.
  `docs/orchestration.md` also names the env vars to set where the model
  aliases lag (Amazon Bedrock, Google Cloud, Claude Platform on AWS).

### Removed
- **The `opencode` pack.** tuidev supports Claude Code and Codex only. A
  migration drops `opencode` from your recorded packs and removes the `oc`
  wrapper fragment (backup first); `~/.config/opencode` and the `opencode`
  binary are yours and stay. The `strict` and `standard` Seatbelt profiles
  no longer make OpenCode's state dirs writable, so `sbx -- opencode` now
  fails on start.

## [3.2.2] - 2026-09-28

### Fixed
- **Settings merges keep a symlinked `~/.claude/settings.json` a symlink on
  BusyBox systems (Alpine).** BusyBox `cp` replaced the link with a plain
  file; the merge now writes through it with a redirect.
- **CI is green again.** The hardcoded-path check allows Homebrew's Linux
  prefix `/home/linuxbrew/`, which the vim pack's fzf lookup names.

## [3.2.1] - 2026-09-28

### Changed
- **Leaner orchestration policy for Opus 5.5 and GPT-6.** Both vendors now
  say leftover scaffolding hurts, and Anthropic says Claude over-delegates.
  The always-on text drops its delegation guidance, which Claude Code's
  harness and the agent descriptions already give, and keeps only the rules
  neither CLI applies by default (uncommitted work, commit style, `.env`,
  your decisions). Implementor bodies keep only the uncommitted-work rule,
  and the reviewer only its verdict format: the method and report templates
  are gone. The `delegation` skill is cut to worktree parallelism and the
  harvest. The Codex block, where delegation stays opt-in, sends high-output
  runs to `executor`.
- **Agent teams are off in the shipped Claude Code settings.** While teams
  are on, every subagent Claude names launches as a full teammate session,
  unasked. Turn them on with `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`;
  `teammateMode: "auto"` stays. The settings merge drops the old value from
  an edited `~/.claude/settings.json` unless you changed it.

### Removed
- **The `verification` skill.** Current models check their own work, and
  verification reminders now cause over-verification. A migration backs up
  and removes `~/.claude/skills/verification/` and
  `~/.agents/skills/verification/`.

## [3.2.0] - 2026-09-25

### Added
- **Updates now merge into an edited `~/.claude/settings.json`.**
  `--pack ai-clis` (and `update.sh --configs`) used to leave a file you'd
  edited alone, so shipped policy changes never reached it. Now it does a
  three-way merge with `jq` against the version it last applied, stored in
  `~/.config/tuidev/shipped/settings.json`:
  - values you never changed follow the release;
  - your values, keys and deletions stay;
  - lists keep your entries, drop the ones a release removed, and gain new
    ones.
  
  When both sides changed a value, yours is kept and reported. The file is
  backed up before any write, and `--dry-run` only previews. The first merge
  on an existing install only adds. Your own sandbox exceptions (such as
  `"git *"` in `sandbox.excludedCommands`) now belong in that file and
  survive updates. Codex's `config.toml` still keeps your copy and shows a
  diff.

### Fixed
- **Backups of symlinked configs are real copies.** A dotfiles symlink used
  to be backed up as a link, which then pointed at the rewritten file. A
  failed backup now stops the write instead of going ahead.
- **Test harnesses honor `TMPDIR`**, so `make test-lib` runs inside Claude
  Code's and Codex's sandboxes.

### Changed
- **No attribution, brief commits.** The shipped Claude Code settings add
  `attribution.sessionUrl: false`, so cloud and Remote Control commits don't
  carry a claude.ai session link either. The orchestration instructions
  (Claude rules file and Codex `AGENTS.md` block) ask for a punchy
  conventional-commit subject, a body only when the why isn't obvious, and
  no `Co-Authored-By`, "Generated with" or session-link lines. A link to
  the session, when wanted, goes in `git notes` instead.

## [3.1.4] - 2026-09-25

### Fixed
- **Claude Code on Linux stalled on large repos.** Linux installs of
  `--pack ai-clis` now get `configs/claude/settings.linux.json`. It's
  `settings.json` with the `**/.env` deny rules written as literal paths
  (`./.env`, `./.env.local`, `./.env.production`, …). Claude Code's
  bubblewrap sandbox can't enforce a pattern, so it walked the whole project,
  including `node_modules` and `.git`, again and again while the model
  worked. That kept one core busy and made typing lag. An unmodified earlier
  copy upgrades on `./scripts/update.sh --configs`. For a copy you edited,
  the pack warns when it still has `**/.env` rules. On Linux, `.env` files
  in subdirectories are no longer denied. macOS keeps the patterns. See
  docs/sandboxing.md.

## [3.1.3] - 2026-09-24

### Changed
- **`delegation` skill:** the `reviewer` is now offered as a fresh-context
  check for changes where a plausible-but-wrong result would be costly, not
  prescribed for every risky or large change. Anthropic's Claude 5 guidance
  says instructions to verify through a subagent cause over-verification.

## [3.1.2] - 2026-09-23

### Added
- **`--pack vim`**: plain Vim with a zero-plugin vimrc, the lightweight
  alternative to `--pack nvim` for servers and small boxes. It uses only Vim
  9.1's built-in packages (`comment`, `editorconfig`, `matchit`, `hlyank`,
  `nohlsearch`), fzf's own Vim plugin, ripgrep as `:grep`, persistent undo
  under `~/.local/state/vim`, and OSC 52 yanks over SSH. Deployed as
  `~/.vim/vimrc` with `--upgrade-shipped`, so a `~/.vimrc` of your own wins.
  On macOS the system Vim is used. See docs/vim.md.

## [3.1.1] - 2026-09-23

### Fixed
- **Claude Code settings:** `Read(~/.cargo/credentials*)` is now two literal
  rules, `~/.cargo/credentials` and `~/.cargo/credentials.toml`, the same pair
  `sbx` denies. Claude Code's Linux sandbox warned about the glob. The
  remaining warning about the `.env` rules is expected and is explained in
  docs/sandboxing.md. `test_contract.sh` now fails if any other Read/Edit
  rule uses a glob the Linux sandbox can't enforce.

## [3.1.0] - 2026-09-23

### Added
- **`--pack orchestration`**: one multi-agent policy for Claude Code and
  Codex, merged in from the standalone agents-orchestration repo. The
  always-on policy as `~/.claude/rules/tuidev-orchestration.md` (your
  `~/.claude/CLAUDE.md` is left alone) and a managed block
  `tuidev-orchestration` in `~/.codex/AGENTS.md`; tiered subagents in
  `~/.claude/agents/` and `~/.codex/agents/` (Codex tiers on `gpt-6-sol` and
  `gpt-6-luna`); the `delegation` and `verification` skills in
  `~/.claude/skills/` and `~/.agents/skills/`. Installs on its own, for teams
  and CI runners that don't use the rest of tuidev
  (`bash scripts/install/packs/orchestration.sh`), and `./uninstall.sh` then
  removes just that. It removes the symlinks the agents-orchestration
  installer left, and restores the files that installer set aside. See
  [docs/orchestration.md](docs/orchestration.md).
- The policy, agents and skills were re-audited against current Anthropic and
  OpenAI guidance (current models need less direction, and leftover
  scaffolding hurts), which cut them to under half their agents-orchestration
  length. The Codex standard implementor runs `gpt-6-luna` at `high`, OpenAI's
  starting point for Luna.
- `--pack ai-clis` installs `~/.codex/rules/tuidev.rules`: Codex prompts
  before git and gh writes, matching Claude Code's `ask` rules.

### Changed
- Managed blocks in Markdown files use HTML-comment markers
  (`<!-- >>> tuidev managed (ID) >>> -->`): a `#` marker line is a heading
  the agent reads.
- The shipped Claude Code settings also ask before `git add`, `git commit`,
  `git merge`, `git tag`, `gh pr create` and `gh release`, so agents stop
  review-ready. In headless `claude -p` these deny.

## [3.0.1] - 2026-09-23

### Fixed
- CI's Linux container job: `scripts/lib/profile.sh` passes the profile name
  to `tuidev_extra_packs` explicitly (shellcheck 0.10 flagged SC2120), and
  `test_theme.sh` skips its starship TOML check when `python3` is absent, as it
  already did without `tomllib`. No change to installed behavior.

## [3.0.0] - 2026-09-23

A repositioning release. Five months of shell history showed the real
workflow: `claude` and `codex` in a terminal tab, a GUI editor for review,
and tmux durability used only on always-on remote nodes — never the ten
layout wrappers. 3.0 moves tmux and Neovim from core to optional packs,
deletes the `cc`/`cx` wrappers and every tmux layout script, and turns on
the AI CLIs' own native sandboxes by default so plain `claude` and `codex`
are safe without a wrapper. `sbx` stays as a general-purpose Seatbelt tool.
The correctness and hardening work queued for 2.4.0 ships in this release
too (folded into the sections below).

### Breaking
- **tmux and Neovim are optional packs now**, not part of core:
  `--pack tmux` (formulae, the `tuidev-tmux` managed block, TPM bootstrap)
  and `--pack nvim` (formula, the LazyVim config, `--upgrade-shipped` per
  file). `minimal` no longer installs either. `remote` still gets tmux
  (`core + remote + sandbox + --pack tmux`); `desktop` gets neither by
  default — add `--pack nvim --pack tmux` yourself, or let migration
  `202609231200_v3_optional_nvim_tmux` carry over a tree tuidev already
  owns.
- **Every tmux layout is gone**: `work`, `dev`, `ai`, `ai-single`,
  `ai-triple`, `fullstack`, `multi`, `remote`, `agents`, `worktrees`, plus
  `tk`/`tka`, `scripts/tmux/`, and the `test-layouts` / `quick-dev` /
  `quick-ai` / `quick-agents` / `quick-worktrees` Make targets. `.zshrc`
  keeps a plain `t [NAME]` (attach-or-create) and `tls` (list). For
  parallel agents, use `claude -w NAME` (worktrees under
  `.claude/worktrees/`) or a subagent with `isolation: worktree`.
- **The `cc` and `cx` wrappers are gone**, along with
  `configs/zsh/ai-clis.zsh`. Plain `claude` and `codex` are sandboxed by
  their own **native** sandboxes: `configs/claude/settings.json` now ships
  `sandbox.enabled = true` (with `autoAllowBashIfSandboxed`,
  `excludedCommands` for `docker`/`gh`, and `filesystem.denyRead` for the
  CLIs' own token files), and `configs/codex/config.toml` keeps
  `sandbox_mode = "workspace-write"` with `approval_policy = "on-request"`.
  `sbx` remains, unchanged in spirit, as a general Seatbelt wrapper for
  anything (`sbx -- ./script.sh`), including an optional kernel-level mode
  for Codex (`sbx -- codex -s danger-full-access -a on-request`). Codex's
  `workspace-write` limits writes and network but not reads, so use that
  mode for credential-sensitive Codex work. An unmodified 2.x
  `~/.claude/settings.json` is upgraded by `./scripts/update.sh --configs`;
  a user-edited one is left as-is (`--upgrade-shipped` keeps your edits):
  merge the sandbox block yourself, see
  [docs/sandboxing.md](docs/sandboxing.md). Until one of those happens,
  plain `claude` runs unsandboxed.
- **`bosun`, `yazi` and `nnn` packs are removed.** Installed binaries are
  left alone. Migration `202609231210_v3_drop_tui_packs` drops them from
  your recorded profile.
- **`EDITOR` no longer defaults to `nvim`.** It now prefers a GUI editor
  locally (`code --wait`, then `cursor --wait`), and otherwise (always over
  SSH) takes the first of `nvim`, `vim`, `vi`, `nano` that exists, leaving
  `EDITOR` alone if none does. Override in `~/.zshrc.local`.
- **`core` no longer installs `tmux`, `neovim`, `lazygit` or `httpie`.**
  `lazygit` and `httpie` moved to `--extras`.
- **Upgrade with `./scripts/update.sh --configs`** (`make
  update-configs`): it runs the three migrations
  (`202609231200_v3_optional_nvim_tmux`, `202609231210_v3_drop_tui_packs`,
  `202609231220_v3_drop_ai_wrappers`, which backs up and removes
  `$TUIDEV_STATE_DIR/shell.d/ai-clis.zsh`) and then re-applies every
  recorded pack's configs: the `tuidev-tmux` block, the Neovim config and
  `nvim.zsh`, the sandboxed Claude settings. `./install.sh` alone runs the
  migrations but only the packs named on its command line. See
  [docs/updating.md](docs/updating.md).

### Fixed
- **Interactive CLIs under `sbx`.** The Seatbelt profiles denied the agent's
  own terminal (`/dev/tty*`, tty ioctls, listing `/dev`), so `sbx -- claude`
  could not enter raw mode: keys
  arrived as literal escape codes and Ctrl+C could not quit. Present since
  2.0. The profiles now allow exactly the terminal devices, plus listening
  on Claude Code's `/tmp/cc-socks/` message socket.
- **Neovim config reaches existing machines.** It was copied once at install
  and never updated, so config fixes (like this release's LazyVim cleanup)
  never arrived. The install now deploys it file by file with
  `--upgrade-shipped` (`configs/nvim/shipped.sha256`, keyed by relative path):
  unmodified files upgrade with a backup, edited ones are kept, your own files
  are untouched. Only a tree tuidev owns is managed (absent, or its `init.lua`
  is ours / recorded): your own Neovim config is never mixed with our specs.
  `lazy.nvim` luarocks support is off (nothing needs it). In 3.0 this
  mechanism moved from `core` into the new `--pack nvim`.
- **fzf key bindings** load only with a terminal, so agent tool shells and
  `ssh host cmd` no longer print `can't change option: zle`.
- **tmux theme vs. tmux-continuum:** `theme.sh` appended its block after TPM's
  `run` line, which reset `status-right` and silently stopped continuum's
  autosave. The theme now goes into `~/.config/tmux/theme.conf`, which
  `tmux.conf` sources above the TPM block. In 3.0 both the managed block and
  the TPM bootstrap moved from `install.sh` into the new `--pack tmux`.
- **`sbx` under the AI CLIs:** `strict` and `standard` now allow writes to the
  CLIs' own state (`~/.claude`, `~/.claude.json*`,
  `~/.local/{share,state}/claude`, `~/.cache/claude`, `~/.codex`,
  `~/.local/share/opencode`, `~/.cache/opencode`) and name resolution through
  the mDNSResponder socket, but not to the files that steer a CLI from
  outside the sandbox (see Security).
- **Shipped configs reach existing installs:** `install_config
  --upgrade-shipped HASHFILE` replaces a Seatbelt profile,
  `~/.claude/settings.json` or `~/.codex/config.toml` only when it is
  byte-identical to a version tuidev shipped (listed in each source dir's
  `shipped.sha256`), after a backup. A file you edited is kept, with a `diff`
  hint. Before, `--adopt-existing` left the tightened Claude settings off
  every existing install.
- **Git defaults** honor `[include]`d files (`git config --global --includes`),
  so tuidev no longer appends a key that overrides one you set in an include.
- **TPM bootstrap can't hang the installer:** the clone and `install_plugins`
  run with `GIT_TERMINAL_PROMPT=0`, stdin from `/dev/null` and a 120 s
  watchdog; any failure only warns.
- The cached shell init scripts are written to a temp file and moved into
  place, so a shell starting in parallel never sources a half-written cache.
- The `.env` deny rules in the shipped Claude settings match at any depth
  (`Read(**/.env)`, `Read(**/.env.*)`, and the same for `Edit`), not only in
  the project root.
- CI's Seatbelt parse step fails on any profile, not just the last, and also
  parses each one with `ALLOW_HERDR=1`.
- **Ghostty:** dropped the `term = ghostty` override (TERM is the default
  `xterm-ghostty` again; tmux gets RGB and extended keys via
  `terminal-features`), and `scrollback-limit` is now in bytes (50 MB).
- **Claude Code hooks** call `$HOME/.local/bin/notify.sh` by absolute path.
- `update.sh` runs under macOS's stock bash 3.2.
- The ssh config sets `IgnoreUnknown UseKeychain`, so the same file works with
  Linux OpenSSH.
- eza aliases use `--icons=auto`; a bare `--icons` swallowed the next word
  (`ls DIR` failed for agents that capture aliases).

### Changed
- **`--pack cmux`** installs the cask from Homebrew's own repository and no
  longer adds the `manaflow-ai/cmux` tap, which Homebrew now ignores unless
  you trust it. Remove an old one with `brew untap manaflow-ai/cmux`.
- **Native sandboxes are the default for the AI CLIs.**
  `configs/claude/settings.json` ships `sandbox.enabled = true`
  (`autoAllowBashIfSandboxed`, `excludedCommands` for `docker`/`gh`,
  `filesystem.denyRead` for the CLIs' own token files); Claude Code's
  `Read`/`Edit` deny rules merge into it automatically.
  `configs/codex/config.toml` keeps `sandbox_mode = "workspace-write"` /
  `approval_policy = "on-request"`, and `file_opener` is now `"vscode"`
  (alternatives in a comment: `cursor`, `vscode-insiders`, `windsurf`,
  `none`). `--pack ai-clis` no longer installs a shell wrapper; it only
  adopts/upgrades the two settings files.
- **`sbx` is now the general-purpose tool, not an AI-CLI wrapper.** Run
  anything under it directly (`sbx -- ./script.sh`), including an optional
  kernel-level mode for Codex (`sbx -- codex -s danger-full-access -a
  on-request`). Never run `sbx` around a CLI whose native sandbox is also
  on — Seatbelt doesn't nest: Claude Code under `sbx` is
  `sbx -- claude --settings '{"sandbox":{"enabled":false}}'`, and still needs `CLAUDE_CODE_OAUTH_TOKEN` (the
  Keychain is denied).
- **`EDITOR` picks a GUI editor first.** Locally: `code --wait` if VS Code's
  `code` is on `PATH`, else `cursor --wait`. Otherwise, and always over SSH,
  the first of `nvim`, `vim`, `vi`, `nano` that exists (Debian minimal and
  Raspberry Pi OS Lite have only `vi`). Override in `~/.zshrc.local`.
- **`oc` (OpenCode) is a plain `command opencode`**, no longer routed through
  `sbx` via the `ai-clis` dispatcher (which no longer exists).
- **`core` formulae:** `bat eza fd fzf gh git git-delta jq ripgrep
  shellcheck starship yq zoxide` plus the zsh plugins, and the Ghostty cask
  on macOS. `tmux`, `neovim`, `lazygit` and `httpie` moved out (to the new
  `nvim`/`tmux` packs and `--extras`).
- **OpenCode is fully optional, split out of `--pack ai-clis` into its own
  `--pack opencode`.** `--pack ai-clis` covers Claude Code (primary) and
  Codex (secondary), adopting `~/.claude/settings.json` and
  `~/.codex/config.toml`. `--pack opencode`
  (`scripts/install/packs/opencode.sh`) installs `configs/zsh/opencode.zsh`,
  which puts `~/.opencode/bin` on `PATH` and defines `oc`, and adopts
  `opencode.json` + `tui.json`. It prints OpenCode's official installer
  instead of running it.
- **One package path:** new `scripts/lib/pkg.sh` (`pkg_install`: Homebrew →
  apt-get → dnf → pacman, with per-distro name mapping; system managers run
  only as root or via `sudo -n`, otherwise the command is printed). Every pack
  uses it, replacing core's apt-only fallback.
- **One pack-discovery path:** new `scripts/lib/packs.sh` (`pack_script`,
  `pack_entrypoint`, `pack_run`, `pack_array`) shared by install, update,
  uninstall, health check and the test suite. Package arrays are only
  `<PACK>_FORMULAE` / `<PACK>_CASKS`; the other historical spellings are gone.
- **One state dir:** `TUIDEV_STATE_DIR` (`${XDG_CONFIG_HOME:-~/.config}/tuidev`),
  defined once in `ui.sh`. New profile helpers `tuidev_profile_write`,
  `tuidev_profile_add_pack` and `tuidev_profile_remove_pack`.
- `--pack NAME` is validated before anything runs. Packs warn and continue on
  failure instead of dying.
- **Uninstall** removes only manifest-recorded paths (plus the git keys tuidev
  set, while they still hold its value), backs up every config it removes,
  and never deletes a whole CLI home, so auth and session state survive.
  Installs that predate the manifest get only the safe subset.
- **Git defaults** (`scripts/lib/gitconfig.sh`), set only where you have no
  value — `[include]`d files count — by install *and* `update.sh --configs`, so
  existing machines get new defaults too: `init.defaultBranch main`,
  `merge.conflictStyle zdiff3` (git 2.35 or later), `diff.algorithm histogram`,
  `diff.colorMoved`, `diff.renames`, `rerere`, `rebase.autoSquash/autoStash/updateRefs`,
  `push.autoSetupRemote`, `push.followTags`, `fetch.prune`, `branch.sort`,
  `tag.sort`, `column.ui`, `commit.verbose`, `help.autocorrect prompt`, and delta
  as pager (not side-by-side: agent panes are narrow). `git maintenance start`
  is printed as a tip.
- **brew packages** whose command is already on PATH from elsewhere (e.g. the
  `tldr` formula for tealdeer) are left alone instead of failing on a conflict;
  macOS system copies (`/usr/bin/git`, `/usr/bin/jq`) don't count.
- **tmux:** `prefix g` opens lazygit in a popup, bell monitoring flags agent
  windows, `detach-on-destroy off`, and Claude Code's documented tmux block
  (`allow-passthrough`, `extended-keys` in csi-u form, `extkeys`). In 3.0
  this config moved from `install.sh` into the new `--pack tmux`.
- **Claude Code settings:** a read-only `allow` list (`gh pr/run view|list`,
  `rg`, `jq`, `shellcheck`); `ask` for `git push`, `gh pr merge` and `gh api`;
  no `Stop` hook; `attribution.pr` is empty too.
- **notify.sh** picks the first channel that works: Herdr toast → tmux status
  line → macOS banner → `notify-send` → ntfy (when `NTFY_URL` is set) →
  silent.
- The wrappers set `HERDR_AGENT` inside a Herdr pane (`HERDR_ENV=1`), so
  Herdr still recognizes a sandboxed agent.
- `setup_agent_configs.sh` creates nothing by default: Claude Code v2.1.277+
  reads `AGENTS.md` when no `CLAUDE.md` exists. `--all` adds the `CLAUDE.md`
  symlink and the legacy per-vendor files.
- `bosun` installed from the `yetidevworks/bosun` Homebrew tap. Removed in
  3.0 (see Breaking above).
- **Shell startup went from about 320 ms to about 70 ms:** tool init scripts
  are cached and regenerate when the binary changes, jenv loads lazily, and
  compinit runs a full check at most once a day. atuin runs with
  `--disable-up-arrow` (Up recalls prefix history; `Ctrl+R` opens atuin).
- **Lean configs:** Ghostty and Starship keep only non-defaults; Ghostty
  prompts before a program reads the clipboard (`clipboard-read = ask`).
  LazyVim drops the telescope and neo-tree overrides (snacks picker and
  explorer; `<leader>gg` is lazygit via snacks).
- **Hammerspoon** uses Hyper (`Ctrl+Alt+Cmd`) for every binding, leaving
  `Ctrl+Alt` to Rectangle: `Hyper+V` opens Maccy, `Hyper+E` opens Ghostty
  running nvim.
- The lazydocker alias is `lzd`; `ld` shadowed the linker.
- **Codex config:** the commented example model pin is `gpt-6-sol`, effort
  levels `low | medium | high | xhigh | max | ultra`, and the `notify`
  example uses a `bash -c` shim. **OpenCode config:** dropped the redundant
  `instructions: ["CLAUDE.md"]`.
- **Docs restructured, one owner per topic:** README is the index;
  `AGENTS.md` is agent-facing (verify commands, engineering rules, sandbox
  boundary); `CLAUDE.md` imports it with `@AGENTS.md`; the terminal-navigation
  guide merged into `CHEATSHEET.md`; the iPhone client guide was cut down into
  `remote.md`; `ARCHITECTURE.md` was replaced by the architecture section of
  `engineering.md`; `inspiration.md` merged into `VISION.md` (now principles
  and non-goals) and `CONTRIBUTING.md`; `agent-primer.md` merged into
  `templates/AGENTS_TEMPLATE.md`.

### Added
- **`--pack nvim`** (`scripts/install/packs/nvim.sh`): `neovim`, plus the
  LazyVim config deployed exactly as `core` used to (per-file
  `--upgrade-shipped`, only while tuidev owns the tree).
- **`--pack tmux`** (`scripts/install/packs/tmux.sh`): `tmux`, the
  `tuidev-tmux` managed block, and the TPM bootstrap (tmux-resurrect,
  tmux-continuum) — moved out of `install.sh`'s cross-cutting section.
  Included by the `remote` profile: `update.sh`, `health_check.sh` and
  `test_suite.sh` treat `profile=remote` as including it even when
  `extra_packs` doesn't list it (`tuidev_extra_packs` in
  `scripts/lib/profile.sh`). Re-run by `update.sh --configs`, it creates
  `tmux.conf` or refreshes the `tuidev-tmux` block but never appends one to
  a `tmux.conf` of your own; `./install.sh --pack tmux` does. `t NAME`
  switches the client when run inside tmux instead of failing to nest.
- Migration `202609231200_v3_optional_nvim_tmux`: adds `nvim` and/or `tmux`
  to `extra_packs` when tuidev already owns the config it finds (and `tmux`
  on every `remote` profile), so an existing install keeps working exactly
  as before.
- Migration `202609231210_v3_drop_tui_packs`: drops `bosun`, `yazi` and
  `nnn` from `extra_packs` (tools stay installed).
- Migration `202609231220_v3_drop_ai_wrappers`: backs up and removes
  `$TUIDEV_STATE_DIR/shell.d/ai-clis.zsh`, so `cc`/`cx` disappear, and says
  whether `~/.claude/settings.json` has the `sandbox` block yet (and if not,
  whether `update.sh --configs` upgrades it or you merge it by hand).
- Migration `202609221800_split_opencode_pack`: on a machine with `ai-clis`
  recorded and OpenCode installed, adds `opencode` to `extra_packs` so the next
  `update.sh --configs` keeps `oc` working. `~/.config/opencode` is never
  touched.
- Migration `202609222000_tmux_theme_file`: moves an existing `tuidev-theme`
  block out of `tmux.conf` into `theme.conf`, after a backup. A `tmux.conf`
  that is your own (no `tuidev-tmux` block) also gets a commented
  `source-file -q ~/.config/tmux/theme.conf` line above TPM's `run` line (or
  at the end), so the theme keeps applying.
- `make test-lib` and `make check-links` (`scripts/check_links.sh` checks
  every relative link in every tracked `.md`); `make ci-test` runs them plus
  lint and validate-configs. `scripts/lib/test_pkg.sh`.
- `sbx --allow-herdr` / `SBX_ALLOW_HERDR=1`.
- `scripts/validate_configs.sh --strict` (a missing validator fails).
- CI: a macOS job (Seatbelt profiles, `sbx` smoke test, lib tests under bash
  3.2, desktop dry-run), plus minimal and remote dry-runs, a
  documentation-links job over all Markdown, and a summary job that fails on
  any failure. The shellcheck file list lives in the Makefile.

### Removed
- **The `cc` / `cx` wrappers, `configs/zsh/ai-clis.zsh`, and every tmux
  layout** (`work`, `dev`, `ai`, `ai-single`, `ai-triple`, `fullstack`,
  `multi`, `remote`, `agents`, `worktrees`, `tk`, `tka`, `scripts/tmux/`,
  and the `test-layouts` / `quick-*` Make targets). See Breaking above for
  the replacements.
- **`bosun`, `yazi` and `nnn` packs.** Binaries already installed are left
  alone.
- **Hammerspoon** is no longer part of the ui pack (cask and `init.lua`).
  Its hotkeys duplicated Spotlight, Ghostty's quick terminal and Rectangle,
  and the config never loaded anyway: since 2.0 it was a managed block whose
  `#` markers are not Lua comments. Existing installs keep the app and
  `~/.hammerspoon/`; remove them with
  `brew uninstall --cask hammerspoon && rm -r ~/.hammerspoon`.
- The `ta` / `tdev` / `tai` / `tai-triple` aliases (deprecated since 2.0).
- `update.sh --sandbox-image` and `make update-sandbox-image`. The
  `sandbox-container` pack provides a runtime only.
- The CI `script-syntax` job (shellcheck already parses every file).
- Hammerspoon's `Ctrl+Alt` window-snapping bindings, which collided with
  Rectangle.
- `docs/ARCHITECTURE.md`, `docs/TERMINAL_NAVIGATION.md`,
  `docs/IPHONE_SSH_CLIENTS.md`, `docs/inspiration.md`,
  `docs/agent-primer.md`, and `docs/screenshots/` (unreferenced images from
  the Zellij era).

### Security
- **The credential deny list** (Seatbelt and Claude `permissions.deny`) now
  also covers `~/.config/gcloud`, `~/.azure`, `~/.npmrc`, `~/.pypirc`,
  `~/.cargo/credentials[.toml]`, `~/.terraform.d`, `~/.git-credentials`,
  `~/.config/op` (1Password CLI), `~/.password-store`, `~/.vault-token`,
  `~/.pgpass`, `~/.config/git/credentials`, `~/.config/containers/auth.json`
  and `~/.gem/credentials`.
- **No persistent escape through the CLIs' state dirs:** under `strict` and
  `standard` a sandboxed agent can't write Claude's `settings.json`,
  `settings.local.json`, `CLAUDE.md`, `keybindings.json`, `hooks/`,
  `commands/`, `agents/`, `skills/` or `plugins/`, Codex's `config.toml`,
  `*.config.toml`, `rules/` or `packages/`, `~/.local/share/claude/versions/`,
  `~/.config/opencode/`, or rename the `~/.claude`, `~/.codex` and
  `~/.local/share/claude` directories. Each of these runs or is loaded
  unsandboxed later. Update and configure the CLIs outside `sbx`.
  `~/.claude.json` stays writable (Claude rewrites it on every start), a
  documented residual risk.
- Claude's native sandbox is controlled only by your user-level
  `~/.claude/settings.json`; a cloned repo's `./.claude/settings*.json` can
  weaken it (see below) but never disable the read-only rules `sbx` also
  enforces. `sandboxing.md` gives the tested native-sandbox block (no
  unsandboxed fallback, token files denied) and the project-level settings
  that can weaken it. In 3.0 this block ships enabled by default (see
  Breaking above), superseding the `cc`-wrapper opt-in described here.
- **The Herdr socket** (which can spawn panes outside the sandbox) is closed
  under `strict` unless `--allow-herdr` is passed. `standard` still opens it.
- Claude Code asks before `git push`, `gh pr merge` and `gh api`, and no
  longer auto-allows `git *`, `gh *`, `make *` or `tmux *`.
- Documented: `gh` can't authenticate under `sbx` under either profile; on
  macOS, Claude Code under `sbx` needs `claude setup-token` +
  `CLAUDE_CODE_OAUTH_TOKEN`, because the Keychain is denied; and
  `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=1` keeps credentials out of subprocess
  environments.
- GitHub Actions are pinned to commit SHAs and kept current by Dependabot.

---

## [2.3.1] - 2026-09-17

Herdr 0.9.x fleet practices and one zsh fix.

### Changed
- **Herdr docs and pack hints track Herdr 0.9.x.** 0.9.0 moved the TUI into
  each client and 0.9.1 added `herdr --machine <label> <cmd>`, so the
  fleet docs (`agent-workflows.md`, `remote.md`, `CHEATSHEET.md`,
  `agent-primer.md`, `AGENTS.md`) now show `herdr machine add` as the way to
  keep an always-on node in the sidebar and `herdr --machine NODE agent list`
  instead of `ssh node -- herdr agent list`. New practices: upgrade the client
  and leave a compatible server running (`herdr status` reports
  `server_binary_stale`), restart servers only when agents are idle or with
  `--handoff`, keep one `herdr` binary per node, and re-run
  `herdr integration status` after every upgrade. The pack prints the matching
  upgrade path (`brew upgrade herdr` vs `herdr update`) and the integration
  reminder.

### Removed
- zsh: the `alias ssh='TERM=xterm-256color ssh'` "Ghostty SSH fix". It shadowed Ghostty's own `ssh` wrapper (the `ssh-terminfo` shell-integration feature already copies `xterm-ghostty` terminfo to remote hosts), so every hop lost truecolor and the automatic terminfo install.

---

## [2.3.0] - 2026-09-15

Opinionated and current. tmux is the only multiplexer, the AI-CLI configs
match the September 2026 docs, containers prefer Apple's native runtime, and
the Linux parity image builds in seconds instead of tens of minutes.

### Removed

- **The Zellij pack.** tmux is the only multiplexer: Claude Code's agent-team
  split panes, Herdr, bosun and cmux all target or sit beside tmux, and every
  Zellij layout already existed as a tmux script. Gone: `--pack zellij`,
  `configs/zellij/` (config + 7 KDL layouts), the `z*` shell wrappers, the KDL
  validator, `scripts/clean-zellij.sh`, `docs/ZELLIJ_TROUBLESHOOTING.md`,
  `docs/migration.md` and `make migrate` (the 2.0 zellij→tmux guide), and the
  Ghostty `ctrl+p` pass-through that existed for Zellij. Migration
  `202609151300_remove_zellij_pack` backs up and removes `~/.config/zellij`
  only where the manifest shows tuidev installed it, drops `zellij` from the
  recorded `extra_packs`, and leaves the brew formula for you to remove.
- The repo's own tracked copies of the per-vendor instruction symlinks
  (`.cursorrules`, `.windsurfrules`, `.aider.md`, `.clinerules`, Roo, Copilot,
  and the Codex `instructions.md` that Codex never read).

### Changed

- **Ghostty on macOS 27:** shipped `macos-titlebar-style` is now `transparent`.
  The `tabs` style collapses the tab strip on macOS 27 with stable 1.3.1
  (ghostty-org/ghostty#13070; fix #13069 is on the tip channel until 1.4.0).
  Opting back into titlebar tabs via `auto-update-channel = tip` is documented
  in the config and `docs/FAQ.md`.
- **Claude Code settings refreshed against the Sept 2026 docs:** permission
  rules use the canonical `Bash(git *)` form, credential directories and
  `.env*` get `permissions.deny` rules (so `Read`/`Edit` honor the same boundary
  `sbx` enforces in the kernel), `teammateMode = "auto"` (tmux panes per
  teammate when already inside tmux), `attribution.commit = ""` (no
  `Co-Authored-By` trailer), `Notification` hook scoped to
  `permission_prompt|idle_prompt`. Dropped the undocumented `projects`,
  `MCP_CONNECTION_NONBLOCKING`, and the `if` filter on `Stop`.
- **Codex config:** `model` is no longer pinned (`gpt-5-codex` is retired
  upstream; the CLI's own default tracks the current lineup),
  `file_opener = "none"` (`nvim` was never a valid value),
  `disable_response_storage` removed (no such key), `web_search = "cached"`,
  and `[tui]` notifications for turn-complete / approval-requested.
- **OpenCode config:** model `anthropic/claude-sonnet-5`; the deprecated `theme` and
  `tui` keys moved out and the legacy `tools` boolean map folded into `permission` — TUI settings now ship in a sibling
  `configs/opencode/tui.json` the pack installs alongside `opencode.json`;
  `permission` gains `external_directory` / `doom_loop`; `share = "manual"`.
- `cc` steps aside for Claude Code's built-in sandbox: Seatbelt does not nest,
  so when `~/.claude/settings.json` has `sandbox.enabled = true` the wrapper
  calls `claude` directly instead of through `sbx`. `docs/sandboxing.md` gains
  a "pick one" comparison.
- `AGENTS.md` documents which CLI reads which instruction file (Claude Code →
  `CLAUDE.md`; Codex / OpenCode → `AGENTS.md`) and the current agent-teams UX
  (agent panel, `teammateMode`). `setup_agent_configs.sh` no longer creates a
  Codex `instructions.md` symlink — Codex reads `AGENTS.md` natively.
- `setup_agent_configs.sh` now creates only `CLAUDE.md` by default; the legacy
  per-vendor files (Cursor, Windsurf, Aider, Cline, Roo, Copilot) moved behind
  `--all`, and the repo's own copies of those symlinks were removed.

- **Container runtime order: Apple `container` → Podman → Docker.** New
  `scripts/lib/container.sh` picks the first runtime present (override with
  `TUIDEV_CONTAINER_RUNTIME`) and shims the CLI differences; `make
  container-build/test/clean` (the `docker-*` names remain as aliases),
  `make sandbox-up/down`, `make update-sandbox-image`, and the
  `sandbox-container` pack all go through it. The pack no longer installs
  Podman when a runtime already exists, and on macOS 26+ without one it points
  at Apple's signed pkg before falling back to Podman. Unit-tested by
  `scripts/lib/test_container.sh` (CI `lib-tests`).
- **Test image rebuilt for speed: Alpine, one package layer, no compiling.**
  The old `Dockerfile` (Ubuntu 22.04) ran `cargo install` for six Rust tools,
  which took tens of minutes on an arm64 builder. Every tool the core suite
  probes is an Alpine package (neovim, ripgrep, fd, bat, fzf, zoxide, delta,
  eza, starship, zellij, bottom, lazygit, yq-go, gh, shellcheck, httpie), so
  the toolchain is a single cached `apk add` layer; no rustup, no
  build-essential, no GitHub downloads, and lazygit is native for the running
  architecture (the old image always pulled the x86_64 tarball). The repo is
  copied last so edits only rebuild the final layer, the entrypoint is the real
  `scripts/test_suite.sh --tag core` instead of an inline ad-hoc script, and a
  `.dockerignore` keeps `.git` and screenshots out of the context. Apple's
  builder VM is sized to the host (`TUIDEV_BUILDER_CPUS` /
  `TUIDEV_BUILDER_MEMORY`, default half the cores / 4g) instead of its 2-CPU
  default. The Debian/Ubuntu apt installer path is validated on a real Debian
  box, not by this image.

### Fixed

- `--pack ai-clis` installed Claude Code settings to `~/.claude.json`, which is
  the CLI's *state* file (OAuth, onboarding, per-project state), so the shipped
  hooks and permissions were never read. It now targets
  `~/.claude/settings.json`; migration `202609151200_claude_settings_path`
  backs up the legacy keys to `~/.config/tuidev/backups/` on machines that got
  the old path (leaving `~/.claude.json` untouched) and lets the pack install
  the current file, and `uninstall.sh` no longer removes `~/.claude.json`.

- `scripts/lib/migrate.sh` no longer honors `XDG_CONFIG_HOME` for its state
  paths — every other tuidev state file lives literally under
  `~/.config/tuidev`, and the mismatch made an installed machine read as a
  fresh one (baselining away its pending migrations) wherever
  `XDG_CONFIG_HOME` points elsewhere.
- Docker test image builds Rust tools with `cargo install --locked`, so
  transitive crate drift (e.g. `palette`) can't break the build.
- Two `shellcheck disable=SC2119` annotations in `install.sh` for
  optional-arg lib calls (shellcheck 0.9.0 flags them; newer versions don't).

---

## [2.2.0] - 2026-09-01

Elite agent-orchestration layer. tmux stays the durability backbone; **Herdr**
is an opt-in fleet runtime. Personal LAN hosts stay in gitignored `*.local`
overlays.

### Added

- **`--pack herdr`** — [Herdr](https://herdr.dev/) agent-aware runtime (sidebar
  states, CLI + socket API). Homebrew-only install; without brew it prints the
  official installer command rather than piping a remote script to a shell. tmux
  wrappers (`work` / `dev` / `ai`) are unchanged. Prefix `ctrl+b` vs tmux
  `ctrl+a`.
- **`docs/inspiration.md`** — Omarchy/Omacosy practices
  we steal vs desktop systems we refuse; the `.local` split.
- Shipped SSH snippet `Include`s `~/.ssh/config.local*` (glob; missing file is
  ignored). Generic `Host always-on` / `workbox` examples only.
- First-fleet walkthrough and detach/verify practices in
  [`docs/agent-workflows.md`](docs/agent-workflows.md).
- CI `check-paths` also scans docs and fails on mDNS `user@` + hostname forms.
- **Worktree-per-agent layout** — `scripts/tmux/layout-worktrees.sh`, the
  `worktrees` shell wrapper, and `make quick-worktrees`. One git worktree per
  agent under `../<repo>-wt/<branch>` on `agent/N` branches, one tmux window
  each, with window `main` kept on the original repo for review and merging.
  Attach-or-create and idempotent; `--list` reports status; `--clean` removes
  only worktrees that are clean and fully merged (relative to the current or
  `--base` branch), printing what blocks the rest, and warns-and-continues when
  git refuses a branch delete instead of aborting the run. Bare `worktrees`
  defaults to a per-repo `<repo>-wt` session.
- **Palette-driven theming** — `scripts/theme.sh list|show|apply`, a 26-key
  palette contract under `configs/themes/`, and two shipped themes
  (`tokyo-night`, `catppuccin-mocha`). Applying writes `tuidev-theme` managed
  blocks into tmux/Ghostty/Starship configs; user edits outside the blocks
  survive. `apply` skips starship (with the fix to run) until `install.sh` has
  written its own block and a top-level `palette = "tuidev"` selector, rather
  than appending a table that would swallow the rest of the file, and it moves
  the theme block back to the end of any file it is no longer last in so the
  palette actually wins. `make theme NAME=…` / `make theme-list` wrap it.
  See [`docs/theming.md`](docs/theming.md).
- **Versioned one-shot migrations** — `scripts/migrations/` holds timestamped
  scripts run at most once per machine (applied ids in
  `~/.config/tuidev/migrations`); `update.sh --migrations` runs them, and they
  run first in `--configs` / `--all`. A failure stops the run and stays
  unrecorded so the next update retries it. Re-running `install.sh` on an
  existing machine applies pending migrations before the packs run; only a
  machine tuidev has never touched baselines history without running it.
  Inaugural migration prunes orphaned pre-2.0 files
  (`~/.local/bin/ai-workflow.sh`, `~/.config/mcp-env.template`) with backups.
  See [`docs/updating.md`](docs/updating.md).
- **Install manifest** — installs record packs, formulae, casks, managed
  blocks, and files to `~/.config/tuidev/manifest` (opt-in, append-only,
  recorded via the shared libs). `uninstall.sh` consults it when present and
  purges only what *we* installed — a pre-existing `ripgrep` now survives;
  pre-manifest installs fall back to the old behavior with a warning.
- **[`docs/roadmap.md`](docs/roadmap.md)** — 2027/28 readiness groundwork:
  multiplexer landscape (tmux/Herdr/Superlogical posture), Seatbelt →
  Apple-containerization succession, fleet-scale agent horizons, and explicit
  adopt/hold criteria for the watch-list.
- **Linux/apt support** — `minimal` and `remote` install on Debian/Ubuntu
  without Homebrew, including arm64 boards like a Raspberry Pi. See
  [`docs/profiles.md`](docs/profiles.md).
- New Makefile targets: `update-migrations`, `theme`, `theme-list`,
  `quick-worktrees`.
- CI `lib-tests` also runs `test_profile.sh`, `test_contract.sh`,
  `test_theme.sh`, and `test_migrations.sh`.

### Fixed

- Linux install: the core pack no longer hard-requires Homebrew. On apt-only
  systems (Debian/Raspberry Pi — Homebrew has no aarch64 Linux build) it probes
  `apt-cache policy` per tool, installs what the release actually packages,
  shims Debian's renamed binaries (`fdfind`→`fd`, `batcat`→`bat`) into
  `~/.local/bin`, declines Debian's incompatible `yq` v3, and prints official
  install commands for the rest instead of piping remote installers. Extras
  warn-and-skip on brewless Linux instead of aborting. The apt path records the
  `fd`/`bat` compat shims it drops in `~/.local/bin` as manifest `file` records
  (so `uninstall.sh` removes them) and the apt packages it installs under a new
  `apt` manifest kind (recorded but not yet purged — inert until a future
  uninstall step consumes it).
- Login shell: `chsh` needs a TTY for its PAM password prompt, so a piped or
  CI install silently left the shell as bash. The installer now detects the
  cases it cannot win (no TTY, no `chsh`, `zsh` absent from `/etc/shells`) and
  prints the exact command to run by hand instead of failing quietly.
- SSH managed block: prefix the `Include ~/.ssh/config.local*` with
  `Match all` — appended after a user config ending in a `Host` stanza, a bare
  `Include` was scoped to that host and `config.local` was never read.
- Sandbox: `strict.sb` / `standard.sb` now allow outbound AF_UNIX connects
  under `~/.config/herdr` only, so sandboxed agents can use the Herdr socket
  API the docs point them at. Credential paths stay denied.
- Health check: the `ai-clis` probe was a literal `true`; it now checks that at
  least one of claude/codex/opencode is on `PATH`.
- CI `check-paths`: capture matches once instead of piping into `grep -q .`
  (SIGPIPE under `pipefail` silently passed above ~5k matching lines); also
  scan `bin/`, `uninstall.sh`, and `Makefile`.
- `install.sh` now auto-applies the `tokyo-night` theme on a fresh, non-dry-run
  install with no existing `~/.config/tuidev/theme`. Previously the shipped
  `starship.toml` selected `palette = "tuidev"` with no `[palettes.tuidev]`
  table until you ran `make theme` by hand, so every prompt warned `Could not
  find color palette: tuidev`. An already-themed machine is left alone.
- `install.sh`'s profile record is now additive: a pack-only run (e.g.
  `./install.sh --pack herdr`) merges with any existing
  `~/.config/tuidev/profile` instead of rewriting it from scratch — group
  booleans (core/remote/sandbox/ui/extras) only ever flip true, `extra_packs`
  is a set union, and a previously recorded profile name (minimal/desktop/
  remote) survives unless `--profile` is explicitly passed this run.
- `scripts/health_check.sh`: `profile=custom` (recorded by pack-only installs)
  no longer exits 2 with "Invalid profile" — it now checks the minimal
  baseline and prints an info line explaining why.

### Changed

- [`docs/agent-workflows.md`](docs/agent-workflows.md) is a control-plane guide
  (attention queue, machine roles, decision table, verification-as-done).
- Agent primer: Herdr nesting, don't script the Herdr TUI, done means verified.
- `docs/inspiration.md` now distinguishes adopted vs
  watched practices (manifest-driven uninstall, in-progress theming pipeline),
  adds an omarchy executable-theme supply-chain caution, and OpenClaw 2.0
  lessons.
- `uninstall.sh` also strips `tuidev-theme` managed blocks from tmux, Ghostty
  and Starship configs, and removes the theme state file.

---

## [2.1.0] - 2026-06-01

Modernization for the 2026 agentic stack. **The core install is now a pure,
continuously-updatable terminal-tools bundle**; AI CLIs, faster Node, and
parallel-agent tooling are opt-in packs. tmux stays the durable backbone.

> **Heads-up (behavior change):** AI CLI wrappers (`cc`/`cx`/`oc`) moved out of
> the default install into `--pack ai-clis`. If you relied on them, add the pack
> — see [Migration](#migration-2-0--2-1).

### Added

- **`--pack ai-clis`** — opt-in AI coding-CLI integration: the `cc`/`cx`/`oc`
  wrappers (sbx auto-routing) + adopt-existing claude/codex/opencode configs.
  Keeps the repo CLI-agnostic as CLIs churn. Pairs with `--pack sandbox`.
- **`--pack fnm`** — fnm (Fast Node Manager, Rust): ~1ms shell init, auto-switch
  Node per project from `.nvmrc`/`.node-version`, Node 24 (LTS) default. The
  shipped `~/.zshrc` prefers fnm when present and falls back to nvm.
- **`--pack cmux`** — native macOS GUI terminal for agents side-by-side
  (notification rings, built-in browser, Claude Teams). A desk-side tmux complement.
- **`--pack bosun`** — tmux-native Rust orchestrator for agent sessions on a
  dedicated `tmux -L bosun` socket; never touches your main tmux state.
- **`shell.d/` loader** — the managed `~/.zshrc` sources opt-in pack fragments
  from `~/.config/tuidev/shell.d/`, so packs can add shell hooks cleanly.
- **New docs:** `agent-workflows.md` (remote control, cmux, bosun),
  `agent-primer.md` (copy-paste brief for any agentic CLI),
  `engineering.md` (shared libs, pack contract, package-array convention).
- TPM (tmux plugin manager) is **bootstrapped on install**.

### Changed

- **Core = terminal tools only.** AI-CLI wrappers/configs no longer install on
  every profile; the cross-cutting installer is "shell + editor", nothing else.
- **Node works from the first prompt in every shell** — the default version's bin
  is on `PATH` immediately, so `node`/`npx` and global Node CLIs resolve on the
  very first command; the heavy manager stays lazy.
- `update.sh --packages` rewritten around one shared discovery path — every
  pack's formulae **and** casks are tracked.
- DRY pass: plural `brew_install_formulae`/`brew_install_casks` helpers; deduped
  install loops across 11 pack scripts.
- `agents` layout is now **claude | codex** (two panes).
- Remote/mobile docs reframed tmux-first; **Moshi** added to the iOS client list.
- opencode model bumped to `anthropic/claude-sonnet-4-6`; CI `seatbelt-profiles`
  pinned to `macos-15`.

### Deprecated

- **Gemini CLI** is no longer shipped (deprecated upstream; succeeded by
  Antigravity, `agy`). The repo stays CLI-agnostic — add your own wrapper in
  `~/.config/tuidev/shell.d/` if you use it.

### Fixed

- `update.sh --packages` silently skipped `fnm`/`cmux` (extra-pack loop ignored
  casks and most array-name conventions).
- `--pack bosun` now actually usable: correct `cargo install --git` + `~/.cargo/bin`
  on `PATH`. Removed dead `collect_active_*` helpers.

### Removed

- `docs/REMOTE_SESSIONS.md` — deprecated stub, superseded by `remote.md` +
  `agent-workflows.md`.

### Migration (2.0 → 2.1)

- Want the `cc`/`cx`/`oc` wrappers back? `./install.sh --pack ai-clis`
  (add `--pack sandbox` for Seatbelt routing).
- Want fnm? `./install.sh --pack fnm` — your existing nvm setup keeps working
  either way.

---

## [2.0.0] - 2026-04-14

Major rewrite. tmux becomes the primary multiplexer; Zellij demoted to an
opt-in pack. Installer is now layered and non-destructive. AI agents run
sandboxed by default on macOS. See [VISION.md](VISION.md) for the full
product rationale, especially the "2026 Amendments" section.

### Added

- **Layered installer** with profiles (`minimal`, `desktop`, `remote`) and
  composable packs (`--core`, `--remote`, `--sandbox`, `--ui`, `--extras`,
  `--pack NAME`). Pack scripts live under `scripts/install/`.
- **macOS Seatbelt sandbox** (Tier 1): `configs/sandbox/profiles/{strict,standard,off}.sb`
  plus `bin/sbx` wrapper. `cc`/`cx`/`gem`/`oc` auto-route through `sbx` when
  both are on `PATH`. Credentials (`~/.ssh`, `~/.aws`, `~/.gnupg`, keychains,
  `~/.config/gh`, `~/.docker`, `~/.kube`, `~/.netrc`) are denied.
- **Podman sandbox-container pack** (Tier 2) for VM-backed isolation
  (`--pack sandbox-container`). Docker Desktop / OrbStack explicitly excluded
  (not FOSS).
- `scripts/lib/ui.sh` — shared shell library (colors, printers, `run_cmd`).
- `scripts/lib/config_write.sh` — non-destructive managed-block writer with
  9-case unit test suite (`scripts/lib/test_config_write.sh`).
- `scripts/tmux/layout-*.sh` — nine reusable tmux layout helpers
  (work / dev / ai / ai-single / ai-triple / fullstack / multi / remote / agents).
- `configs/codex/config.toml` — opinionated Codex defaults
  (`sandbox_mode = "workspace-write"`, `approval_policy = "on-request"`).
- Managed-block config writes: `~/.zshrc`, `~/.config/starship.toml`,
  `~/.config/tmux/tmux.conf` now write under `# >>> tuidev managed (...) >>>`
  markers that preserve user edits outside the block.
- `~/.config/tuidev/profile` manifest + `~/.config/tuidev/env` sourceable
  env file written at install time.
- tmux plugins: `tmux-resurrect` + `tmux-continuum` declared in `tmux.conf`
  for durable session state across reboots.
- New docs: `docs/profiles.md`, `docs/sandboxing.md`, `docs/remote.md`,
  `docs/migration.md`.
- Claude Code hooks refreshed for 2.1.x: `PermissionDenied` event,
  conditional `if` filter on `Stop` hook, `MCP_CONNECTION_NONBLOCKING=true`,
  baseline `permissions.allow` seeded for common tools.
- New Makefile targets: `install-{minimal,desktop,remote}`,
  `check-{minimal,desktop,remote}`, `test-{core,ui,all}`, `sbx-test`,
  `sandbox-up`/`sandbox-down`, `adopt`, `migrate`,
  `update-sandbox-image`, `update-security`.
- Health check and test suite now use profile-aware tag system
  (`core`/`remote`/`sandbox`/`ui`/`extras`/`packs`); missing GUI apps no
  longer fail the suite.
- CI: macOS-runner job validates every Seatbelt profile with
  `sandbox-exec -n`; Linux Docker job narrowed to `--tag core`.

### Changed

- **Default multiplexer: tmux.** The ergonomic commands `work`, `dev`,
  `ai`, `ai-single`, `ai-triple`, `fullstack`, `multi`, `remote`,
  `agents` now launch tmux via the layout helpers. Zellij versions are
  namespaced `zdev`, `zwork`, `zai`, ... and only activate when
  `command -v zellij` succeeds (i.e., after `./install.sh --pack zellij`).
- Installer no longer overwrites `~/.zshrc`, `~/.config/starship.toml`,
  or `~/.config/tmux/tmux.conf` — managed-block writes preserve user edits.
- `~/.config/nvim` is **backed up** (timestamped, under
  `~/.config/tuidev/backups/`) before a new config lands — no more
  `rm -rf` of user state.
- AI CLI configs (`~/.claude.json`, `~/.config/opencode/opencode.json`,
  `~/.codex/config.toml`) use `--adopt-existing` by default: if present,
  tuidev leaves them alone.
- README trimmed from 403 → 154 lines; leads with tmux/sandbox/layered narrative.
- Default package set shrunk: `nnn`, `lazydocker`, `k9s`, `atuin`, `broot`,
  `bandwhich`, `dust`, `duf`, `hyperfine`, `tokei` moved to `--extras`.
- Rectangle/Stats/Maccy/Hidden Bar/Hammerspoon now require
  `--profile desktop` or `--pack ui`.
- `update.sh` is profile-aware: updates only packs the user installed,
  diffs managed blocks instead of blindly copying.

### Fixed

- `update.sh` now detects the **pre-managed-block duplication** foot-gun
  (an older installer wrote the raw source into the file; a newer run
  wrapped the same content in markers, producing TOML duplicate-key
  errors in starship, `parse error near '()'` in zsh when a legacy
  `alias cc=...` collided with the managed-block `cc()` function, and
  redundant `set -g` directives in tmux.conf). `detect_outside_duplication`
  categorizes matches as `exact-*` (safe to auto-clean with backup) or
  `partial-*` (signature match, warn only). Surfaced in both
  `make update-check` and interactive `make update-configs`.
- `configs/zsh/.zshrc`: `unalias cc cx gem oc` is now issued before the
  function definitions, making the managed block robust against stale
  aliases from pre-2.0 installs.
- `scripts/lib/config_write.sh`: `write_managed_block` passes content via
  a sidecar file instead of `awk -v`; BSD awk on macOS rejects literal
  newlines in `-v` values and was silently emptying the destination on
  in-place replacement.

### Deprecated

- `ta`, `tdev`, `tai`, `tai-triple` shell functions — still work, but emit
  a one-time deprecation notice (stamped in `~/.config/tuidev/deprecations`).
  Use `work`, `dev`, `ai`, `ai-triple` instead.

### Removed

- `install.sh.legacy` backup copy (superseded; git history preserves the
  old installer).
- `scripts/ai-workflow.sh` — zellij-only launcher, superseded by
  `scripts/tmux/layout-*.sh`.
- Old README's multi-pane "hero box" framing and Zellij-first command tables.

### Migration

Existing users: on next update, `make update` will show drift on your
shell dotfiles. Run `make adopt` to convert them to managed-block form.
The full cutover guide, `docs/migration.md`, was removed in 2.3.0.

---

## [1.3.0] - 2026-03-26

### Added

#### Multi-Agent CLI Support
- Shell aliases for all AI CLIs: `cc` (Claude), `cx` (Codex), `gem` (Gemini), `oc` (OpenCode)
- **`agents` function** — launches Claude, Codex, and Gemini in 3 tmux panes with one command
- Health checks for Codex CLI and Gemini CLI presence
- No custom configs shipped — all CLIs are self-updating and manage their own configuration

#### Ghostty Modernization
- Enabled font ligatures (`+calt`) for operator readability (`=>`, `!=`, `>=`)
- Added `scrollback-limit = 100000` for AI agent output
- Added `link-url = true` for clickable URLs
- Added `auto-update = check`
- Added quick terminal keybinding (`Ctrl+\``) for system-wide dropdown terminal

### Changed
- AI CLI tool ordering: Claude Code primary, Codex secondary, Gemini optional, OpenCode community
- Updated README, CLAUDE.md, AGENTS.md with 4-CLI architecture and `agents` function
- Updated ASCII diagrams to show 3 agent panes (Claude/Codex/Gemini)
- Documentation across all guides updated for multi-agent workflow

### Fixed
- Cleaned stale permission entries in `.claude/settings.local.json` (removed refs to deleted mcp.json, gemini, ralph)

---

## [1.2.0] - 2026-02-25

### Added

#### Tmux Support (First-Class)
- **`configs/tmux/tmux.conf`** - Full Tokyo Night themed tmux configuration
  - `Ctrl+a` prefix (ergonomic), true color, mouse, base index 1, vi copy mode
  - Pane splits: `|` / `-`, navigation: `h/j/k/l`, resize: `H/J/K/L`
  - Status bar matching Tokyo Night palette (`#1a1b26` bg, `#7aa2f7` accent)
- **Tmux shell functions** in `.zshrc` — mirror Zellij session pattern with `t` prefix:
  - `ta [name]` — attach or create bare session
  - `tdev [name]` — 3-column: nvim (55%) | agent (25%) | runner (20%)
  - `tai [name]` — nvim (60%) + 2 stacked agent panes (40%)
  - `tai-triple [name]` — nvim (55%) + 3 stacked agent panes (45%)
  - `tls`, `tk [name]`, `tka` — session management
- **Health check** (`scripts/health_check.sh`): Tmux Check section (version, config, true color hint)
- **Config validation** (`scripts/validate_configs.sh`): tmux.conf validation + required files
- **Update sync** (`scripts/update.sh`): tmux.conf included in config change detection and apply
- **Install/uninstall**: backup, mkdir, copy, and remove `~/.config/tmux/`

#### Documentation
- `docs/CHEATSHEET.md` — full tmux section (key bindings, session functions, agent teams), tmux in Quick Reference Card, tmux in Config Locations; removed duplicate blocks
- `README.md` — dual session tables, tmux in Core Tools and Theme, `configs/tmux/` in project structure
- `docs/ARCHITECTURE.md` — side-by-side Zellij + tmux in Layer 2, dual orchestrator in Design Philosophy, tmux in Config Flow and File Locations
- `docs/QUICK_START_GUIDE.md` — step 9 "Tmux for Claude Agent Teams" with key bindings and agent teams workflow
- `AGENTS.md` — "Working with Tmux Sessions" section with why tmux, key bindings, session commands, agent teams integration
- `CLAUDE.md` — architecture table, shell functions split into Zellij/tmux subsections, Key Design Decision #6

### Changed
- `CLAUDE.md` and `AGENTS.md` updated to reflect dual-multiplexer architecture
- Zellij positioned as primary for manual workspace layouts; tmux as companion for Claude agent teams

### Context
Claude Code's experimental agent teams feature (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`) requires tmux or iTerm2 for split-pane mode. Zellij is explicitly unsupported. tmux was already installed by `install.sh` but had no config, shell functions, or documentation.

---

## [1.1.0] - 2026-01-29

### Added

#### New CLI Tools
- **sd** - Intuitive find & replace (sed alternative)
- **yazi** - Modern async terminal file manager
- **broot** - Directory navigator for large codebases
- **tealdeer** - Fast tldr pages in Rust

### Changed
- Updated README with new tools
- Enhanced .zshrc with aliases for new tools (y, br, tldr, sd)

---

## [1.0.0] - 2026-01-29

### Added

#### Core Tools
- **Neovim** with LazyVim - Full IDE experience with LSP
- **Zellij** - Terminal multiplexer with 7 pre-built layouts
- **Ghostty** - Fast terminal emulator configuration
- **Starship** - Modern shell prompt with Tokyo Night theme

#### Modern CLI Replacements
- **ripgrep** - Fast grep replacement (10x faster)
- **fd** - Simple find replacement
- **eza** - Modern ls with icons and git status
- **bat** - cat with syntax highlighting
- **zoxide** - Smart cd that learns from usage
- **delta** - Beautiful git diffs

#### TUI Applications
- **lazygit** - Git TUI interface
- **lazydocker** - Docker management TUI
- **nnn** - Fastest TUI file manager
- **k9s** - Kubernetes cluster management
- **ncdu** - Interactive disk usage analyzer
- **bottom** - System monitor

#### System Tools
- **fastfetch** - Fast system info display
- **bandwhich** - Network bandwidth monitor by process
- **fzf** - Fuzzy finder for files and history
- **atuin** - Enhanced shell history

#### macOS Applications
- **Rectangle** - Window snapping and management
- **Hammerspoon** - macOS automation with Lua
- **Stats** - Menu bar system monitor
- **Maccy** - Clipboard history manager
- **Hidden Bar** - Hide menu bar icons

#### AI CLI Tools
- **OpenCode** configuration with MCP servers
- **Claude Code** configuration with MCP servers
- **Gemini CLI** configuration with MCP servers

> Note: Gemini CLI and MCP server configs were removed in the v1.2.0 cleanup. Gemini CLI re-added minimally in v1.3.0. MCP configs are managed separately per-project.

#### MCP Servers (Pre-configured, removed in v1.2.0)
- `filesystem` - File system access
- `git` - Git operations
- `fetch` - HTTP requests
- `memory` - Persistent memory across sessions
- `github` - GitHub API (requires API key)
- `brave-search` - Web search (requires API key)
- `figma` - Design-to-code workflows (requires API key)
- `playwright` - Browser automation
- `postgres` - PostgreSQL access
- `sqlite` - SQLite database access

#### Zellij Layouts
- `dual.kdl` - Editor + 2 AI agents (default)
- `single.kdl` - Editor + 1 AI agent
- `triple.kdl` - Editor + 3 AI agents
- `multi-agent.kdl` - Full workflow with monitoring
- `fullstack.kdl` - 5-tab full-stack development
- `remote.kdl` - Remote access with tunnel
- `dev.kdl` - Classic development layout

#### Documentation
- Quick Start Guide
- Architecture overview
- MCP Servers guide
- Neovim quickstart
- Complete cheatsheet
- Terminal navigation fixes
- Remote sessions guide
- FAQ

#### Infrastructure
- GitHub Actions CI/CD pipeline
- Docker test environment
- Makefile with common commands
- Health check script
- Comprehensive test suite
- Configuration validation
- Dry-run mode for installer

### Changed
- All configurations use `$HOME` variables (no hardcoded paths)
- Consistent Tokyo Night theme across all tools

### Security
- No sensitive data in repository
- API keys stored in environment variables
- MCP servers requiring authentication disabled by default

---

## Pre-release Development

Iterative build-up to 1.0.0 (all folded into the 1.0.0 entry above): the
modern-CLI tool set, macOS automation, the test/CI/Docker harness, the docs set,
and the first AI-CLI + MCP integration.
- Created AGENTS.md for AI assistants
