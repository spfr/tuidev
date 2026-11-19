# FAQ

Short answers: first to what people ask before they install, then to what they hit afterwards. Each topic's full reference is in its own doc: [profiles](profiles.md), [sandboxing](sandboxing.md), [agent workflows](agent-workflows.md), [remote](remote.md), [updating](updating.md).

## Before you install

**How is this different from Herdr?** Herdr runs the panes. It knows which pane holds an agent and whether that agent is working, blocked or done, on every machine you add, and its phone app has an inbox of the agents that need you. It does that better than tuidev could, and tuidev doesn't try. tuidev installs Herdr (`--pack herdr`) and adds what sits around it: tabs named after the task, the board, the map of what runs where, the Ctrl-click that opens another machine's preview here, and `agents hc run` to put an agent on the phone. `agents`, the menu bar and notifications don't need Herdr: they work with tmux or a plain Ghostty tab too. [Which agent needs you](agent-workflows.md#fleet-attention--herdr---pack-herdr).

**And from Rex?** Rex, Superlogical's terminal, has been in public testing since October 2026 (macOS, by invitation). tuidev has no integration with it. It stays on the [watch-list](roadmap.md#watch-list) until a stable release has held up in daily use. `agents`, the sandbox settings, `secret` and the installer don't depend on which terminal or multiplexer you use.

**And from what Claude Code and Codex do themselves?** The CLIs keep adding their own parts: sandboxes, background sessions (`claude --bg`, `claude agents`), remote control from a phone. tuidev turns those on and configures them; it doesn't wrap or replace them ([background sessions](agent-workflows.md#background-sessions)). What it adds is the view across both CLIs and every machine: which session needs you, what each runs, costs and leaves behind, one credential list for both sandboxes and `sbx`, and an install you can preview and undo.

**Does it install Claude Code or Codex?** No. They update themselves, so install them with their own instructions ([Claude Code](https://code.claude.com/docs/en/setup), [Codex](https://github.com/openai/codex)). `--pack ai-clis` writes their settings, which turn their sandboxes on. If `claude` or `codex` is not found after installing it, open a new shell.

**Do I need a Mac?** No, but the Mac gets the most. On Linux, `minimal` and `remote` install, with packages from Homebrew when it is there and otherwise `apt-get`, `dnf` or `pacman`; Debian and Ubuntu (arm64 boards such as a Raspberry Pi included) are the tested path. `agents` works there, and its memory guard, its sampler and the herdr-core job run as systemd user units. The `ui` pack, Ghostty, the menu bar, fan control and `sbx` (Seatbelt) are macOS only. Intel Macs work: Homebrew's prefix (`/opt/homebrew` or `/usr/local`) is found at shell start.

**Do I need git?** No. The one-line install downloads a release, checks it and runs the installer; `tuidev update` gets the next one the same way. A clone works too and updates with `git pull`. [How they differ](updating.md#installed-with-getsh-or-from-a-clone).

**Is piping curl into bash safe here?** It runs one script, [`get.sh`](../get.sh), about 230 lines: it downloads the release archive, refuses it unless its sha256 matches or if it holds a symlink, a hard link or a path outside its one directory, and asks before it installs (answer `p` to preview every change; with no terminal it installs only with `--yes`). The checksum catches a broken download, not a hostile release: what you trust is HTTPS to github.com and whoever can publish a tuidev release, much as with a clone. If you would rather read first, download it and run `bash get.sh`, or clone the repo.

**Does it send anything anywhere?** No telemetry. Its only request of its own is a daily check for the latest release tag, which `tuidev latest off` stops. A phone push goes to an [ntfy](https://ntfy.sh) topic only if you set `NTFY_URL`. `agents` reads local files, and the map, the forwards and the Ctrl-click reach your other machines over plain ssh, and the other machine never connects to yours.

**Can I see my agents on my phone?** Two ways. Herdr's phone app has an inbox of the agents that need you; it lists what runs in herdr-core, so install `--pack herdr-core` beside `--pack monitoring`, and start an agent with `agents hc run claude`, or set `AGENTS_HC_AUTO=1` and a plain `claude` typed in a Herdr pane is hosted there by itself. Mirroring the agents already in Herdr panes is experimental and off by default (`AGENTS_HC_MIRROR=1`), because a pane has the phone's size while the phone shows it. Or use a terminal app (Blink, Moshi, Termius) and `herdr session attach` or `t` over SSH, which shows the whole TUI and needs no pack. Both are in [remote.md](remote.md#herdrs-phone-app-agents-hc).

**Can my agents keep running with the laptop shut?** On a machine that stays on, yes. Install `--pack monitoring --pack herdr-core` on a Raspberry Pi or a VM, run `sudo loginctl enable-linger $USER` there once (the pack says when it is needed), log Claude Code in there with `claude` and `/login` (a token exported in your shell does not reach a hosted agent), and add the box in Herdr's phone app. A systemd user timer starts herdr-core at boot and again within 5 minutes if it stops. See [remote.md](remote.md#herdrs-phone-app-agents-hc).

## Install and update

**How do I know there is a new release?** The menu bar gets a row, Herdr shows one toast, `agents` ends with a line, and the palette's first row is the update. With no newer release known, the palette starts with "Check for a new release", which asks at once. Nothing updates on its own; `tuidev update` applies it. [Hearing about a new release](updating.md#hearing-about-a-new-release).

**An update broke something.** Run `tuidev check` (`tuidev check --fix` repairs what it safely can), then `tuidev update --check` for config drift and pending migrations. A failed migration is not recorded, so the next `tuidev update --migrations` retries it. To go back, `tuidev update --rollback` puts the release before it back and re-applies its configs (from a clone, check out the earlier tag and run `./install.sh`).

**apt wants a password and the installer didn't prompt.** By design: system package managers run only as root or through `sudo -n`. The installer prints the exact command to run yourself. Anything the distro doesn't package, such as `starship` or `eza` on older Debian releases, is skipped with a link to the upstream install page; on Debian, `fdfind` and `batcat` are linked as `fd` and `bat` in `~/.local/bin`.

**`--pack foo` fails immediately.** `--pack` names are checked before anything runs. `core`, `remote`, `sandbox`, `ui` and `extras` are flags (`--sandbox`), not `--pack` names. The valid pack names are listed in [profiles.md](profiles.md#optional-packs).

**The installer stopped halfway. How do I retry?** Re-run the same command. Every step is idempotent, and `--dry-run` shows what it would do. A pack that fails to install a tool warns and continues; a failed migration stops the run before any pack runs. The installer ends with the steps left to you, numbered, and how many warnings it printed.

**Where are my backups?** `~/.config/tuidev/backups/` (or `$XDG_CONFIG_HOME/tuidev/backups/`). tuidev backs up a file there before it overwrites or removes it, and keeps the most recent copies of each.

**How do I undo everything?** Run `tuidev uninstall`, or `tuidev uninstall --dry-run` to see first. It removes only what `~/.config/tuidev/manifest` records: the managed blocks, `~/.local/bin` helpers, the git defaults tuidev set (while they still hold tuidev's value) and, if you agree, the configs and Homebrew packages tuidev installed. CLI auth and session state are never touched. See [updating.md](updating.md#uninstall).

## Shell and terminal

**Where did Ruby, jenv, RVM and the Android SDK go?** Out of the shipped `.zshrc` (since 3.21), as personal toolchains. `tuidev update --configs` moved the ones it found into a marked section of `~/.zshrc.local`; on a new machine, set up the ones you use there.

**Up arrow doesn't open atuin.** By design: Up recalls history entries that start with what you have typed. `Ctrl+r` opens atuin.

**The shell is slow to start.** Measure it with `time zsh -i -c exit`. Tool init scripts (starship, zoxide, atuin, fzf) are cached in `~/.cache/zsh/init-*.zsh` and regenerate when the tool's binary changes. Look in `~/.zshrc.local` for anything that sources `nvm.sh` or runs `eval "$(tool init)"` eagerly. After installing new completions, run `rm ~/.cache/zsh/zcompdump-*`.

**Word jumps, Home or End print garbage.** In Ghostty, Option acts as Alt (`macos-option-as-alt = true`), so `Alt+b` / `Alt+f` move by word, and the shipped `.zshrc` binds Home, End and Delete. In iTerm2, set Preferences → Profiles → Keys → Left/Right Option key to `Esc+`. To see what a key actually sends, run `cat -v` and press it.

**Ghostty tabs broke on macOS 27.** Stable Ghostty 1.3.1 collapses the titlebar tab strip (ghostty-org/ghostty#13070). The shipped config keeps the default `transparent` titlebar, which works. For titlebar tabs, add `auto-update-channel = tip` and `macos-titlebar-style = tabs` to `~/.config/ghostty/config`, outside the managed block, then restart Ghostty.

**Where do my own aliases and SSH hosts go?** In `~/.zshrc.local` and `~/.ssh/config.local`. Both are sourced or included, and never overwritten. Keep personal hosts out of the repo.

## tmux

tmux is a pack (`--pack tmux`); the `full` and `remote` profiles include it. These apply once it is installed.

**Keys work in plain zsh but not inside tmux.** Check `echo $TERM`: it should be `tmux-256color` inside tmux and `xterm-ghostty` (or `xterm-*`) outside. Shift+Enter and modified keys depend on `extended-keys`: run `tmux show -s extended-keys`. Reload with `Ctrl+a r`, or restart the tmux server after a tmux upgrade.

**The theme didn't apply to tmux.** Themes live in `~/.config/tmux/theme.conf`, which the shipped `tmux.conf` sources. Run `tuidev update --configs`, then `tuidev theme NAME` again.

**Links agents print aren't clickable inside tmux.** tmux passes OSC 8 links through only with the `hyperlinks` terminal feature (tmux 3.4+), which the shipped `tmux.conf` turns on (`tmux show -s terminal-features` lists `*:hyperlinks`). Claude Code also stops emitting links when `TERM_PROGRAM=tmux`, so the shipped `.zshrc` exports `FORCE_HYPERLINK=1` in tmux panes, as it does in Herdr. After `tuidev update --configs`, restart the tmux server (`tmux kill-server`) or at least run `exec zsh` in each pane, then Cmd-click the link in Ghostty (Shift-Cmd-click if tmux's mouse mode takes the click).

**Agent-team teammates don't open as panes.** Teams are off in the shipped settings, so turn them on first. Split panes need `claude` to run inside tmux (the shipped `teammateMode` is `auto`), which means `--pack tmux` installed and a session already attached. Outside tmux, teammates run in-process. See [agent-workflows.md](agent-workflows.md#agent-teams).

## Sandbox

**Do I still need `sbx` if I run plain `claude` or `codex`?** Usually not: their own sandboxes are on by default (`sandbox.enabled` in `~/.claude/settings.json`, `sandbox_mode = "workspace-write"` in `~/.codex/config.toml`). They differ, though: Claude Code's denies the credential paths to its commands, while Codex's `workspace-write` limits writes and network but not reads, so plain Codex can still read `~/.ssh`. For credential-sensitive Codex work, use `sbx -- codex -s danger-full-access -a on-request`. `sbx` is also the general-purpose wrapper for anything else you want confined.

**Codex or Claude Code reports `sandbox_apply: Operation not permitted`.** Seatbelt profiles don't nest. This happens when you run `sbx -- codex` or `sbx -- claude` without telling the CLI to step aside: pass `-s danger-full-access -a on-request` to Codex, or `--settings '{"sandbox":{"enabled":false}}'` to Claude Code, so `sbx` is the only sandbox. Otherwise run plain `codex` or `claude`, without `sbx`.

**Claude Code asks me to log in.** Under its own sandbox (the shipped default) the Keychain works normally. Under `sbx` the Keychain is denied: run `claude setup-token` once and export the result as `CLAUDE_CODE_OAUTH_TOKEN` in `~/.zshrc.local`. See [sandboxing.md](sandboxing.md#native-sandboxes-the-default).

**`gh` says I'm not logged in.** `~/.config/gh` is on the credential deny list under every `sbx` profile, and `--profile standard` does not change that. Under Claude Code's sandbox, `gh *` is in `excludedCommands`, so it runs outside the sandbox and just needs your normal permission approval. Under `sbx`, run `sbx --profile off -- gh ...`.

**`npm install`, `pip install` or `git push` over ssh fails under `sbx`.** `strict` allows only TCP 443. Use `sbx --profile standard -- CMD`, which adds ports 80, 22 and 9418.

**The sandbox blocks something legitimate.** For `sbx`, edit the installed profile in `~/.config/tuidev/sandbox/<name>.sb`: an edited profile is kept on update. To find the rule that fired, see the [sandboxing troubleshooting](sandboxing.md#troubleshooting). For the CLIs' own sandboxes, adjust `excludedCommands` / `allowedDomains` in `~/.claude/settings.json`, or `[sandbox_workspace_write]` (`writable_roots`, `network_access`) in `~/.codex/config.toml`. Don't punch holes in the credential deny list.

**How do I turn the sandbox off?** For `claude`, set `sandbox.enabled: false` in `~/.claude/settings.json`; for `codex`, `sandbox_mode = "danger-full-access"` in `~/.codex/config.toml`. Do it from your own shell. For `sbx`: `sbx --profile off -- CMD`, or don't install `--sandbox`.

**`secret get` or `secret run` fails inside an agent session.** That is the sandbox and the deny rules doing their job: Claude Code refuses `secret get`, `secret export` and `secret run`, and under `sbx` the Keychain read fails (`the Keychain refused to read NAME`). Run it from your own shell. If a token has to reach an agent, start it as `secret run -n NAME -- claude`. See [secrets.md](secrets.md#what-an-agent-can-reach).

**A test that calls the model API lost its key.** The shipped settings unset `ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN` and `OPENAI_API_KEY` in the commands an agent runs; the CLI keeps its own login. Give the key to that one command (`secret run -n ANTHROPIC_API_KEY -- npm run eval`, run by you), or remove the name from your copy of the settings. See [secrets.md](secrets.md#what-an-agent-can-reach).

## Herdr, remote and the phone

**Which instruction file does each CLI read?** See the table in [agent-workflows.md](agent-workflows.md#instruction-files).

**A Herdr tab name I set keeps changing.** It should not: a sync renames only a tab whose label is still Herdr's number or the one a sync gave it, and a rename you make, or another tool makes through Herdr's `tab.rename`, is left alone. `agents herdr` shows each tab's label and whose it is; `agents herdr reset TAB_ID` hands one back to auto-naming, and `AGENTS_HERDR_NAMES=0` turns the naming off. See [Your names stay yours](agent-workflows.md#tabs-named-after-what-runs-in-them).

**A Ctrl-click on a URL from another machine does nothing.** Run `agents link` on the machine you sit at: it says whether the watcher runs and, per machine, `connected`, `connecting`, `unreachable`, `disconnected` or `no agents there`. The click needs `--pack herdr` and `--pack monitoring` on both machines, and in a saved-machine pane Herdr does not open OSC 8 links yet, so the URL has to be on screen as text. `AGENTS_LINK=0` turns the watcher off, and `agents link restart` applies a change. See [remote.md](remote.md#remote-feels-local-ports-links-and-files).

**Herdr's phone app shows nothing, or stays on "connecting".** `agents hc` says whether a phone is connected now. With none connected and the agents listed by `agents hc ls`, the fault is the network between the phone and this machine: look at Tailscale's warnings on the phone, then reopen the app. See [remote.md](remote.md#herdrs-phone-app-agents-hc).

**Claude Code says "Not logged in" in a session I opened from the phone (macOS).** herdr-core was started over SSH, outside your desktop login, so the agent cannot reach the Keychain. `agents hc` says so. At the Mac itself, not over SSH, run `agents hc up --restart`; it ends the terminals that core holds. `--pack herdr-core` starts the core at login so the phone finds the right one.

**Is anything running at all?** `agents doctor` says whether the sampler is sampling, the memory guard is looking and the hooks call this `agents`; `agents doctor --fix` starts what stopped. `tuidev check` runs the same rows among its own. See [agent-workflows.md](agent-workflows.md#is-it-running-agents-doctor).

## Neovim

Neovim is optional (`--pack nvim`).

**Plugins are broken.** Run `rm -rf ~/.local/share/nvim ~/.local/state/nvim ~/.cache/nvim`, then start `nvim`. LazyVim reinstalls everything.

**The LSP doesn't work.** Run `:LspInfo`, then `:Mason` to install the missing server, then `:checkhealth`.

## Getting help

Open an issue that includes your tuidev version (`tuidev version`), your OS version, your profile and packs (`cat ~/.config/tuidev/profile`) and the output of `tuidev check`. Report security issues through [SECURITY.md](../SECURITY.md).
