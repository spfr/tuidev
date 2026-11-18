# Remote and Mobile

Read this to set up an always-on machine you connect to from your laptop or phone, and to make its agents, previews and files reachable from where you sit. The host runs the terminal, tmux, the editor and the agents. You connect from any client and re-attach. Work survives disconnects because tmux does. Tailscale, SSH, mosh and phone apps are only transport.

> **Only need to steer an agent from your phone?** Claude Code's native Remote Control covers that without SSH (see [agent-workflows.md](agent-workflows.md#remote-control-from-a-phone)). This doc covers the full-terminal path underneath it.

## Setup

On the machine you'll connect to:

```bash
curl -fsSL https://github.com/spfr/tuidev/releases/latest/download/get.sh | bash -s -- --profile remote --pack ai-clis
tailscale up && tailscale status  # join the tailnet
```

The same install is the third choice ("A headless box that stays on") when you run the one-liner without flags. On a Mac you also sit at, add the pieces to what it has: `tuidev install --remote --pack tmux`. With a clone, run `./install.sh` with the same flags. Once the box has `tuidev`, `tuidev update` keeps it current.

`remote` = core + remote + sandbox + `--pack tmux`, so a single `--profile remote` install gets Tailscale, mosh, SSH and a durable tmux session together — you don't add `--pack tmux` yourself. `--remote` on its own installs Tailscale (a cask on macOS; on Linux it links to the official installer), mosh, the SSH client config as a managed block, and sshd hardening snippets: key-only auth, no root login, modern ciphers. The snippets are copied into `/etc/ssh/sshd_config.d/` only when that directory is writable. Otherwise the installer prints the `sudo cp` commands. On macOS, turn on Remote Login in System Settings → General → Sharing, or run `sudo systemsetup -setremotelogin on`.

`remote-status` shows SSH, Tailscale and tmux at a glance. `ts-ip` prints the node's Tailscale address.

## Connect and re-attach

```bash
ssh devbox                  # or: tailscale ssh devbox
t myproject                 # attach-or-create a named tmux session
# ...network drops, laptop sleeps...
ssh devbox && t myproject
```

Detach with `Ctrl+a d`. `tls` lists sessions on the box. tmux-continuum saves every 15 minutes and tmux-resurrect restores sessions when tmux starts, so sessions survive a reboot too. There's no prebuilt layout anymore — `t myproject` gives you a plain session, and you run your editor of choice (`nvim`, or split a second SSH session for it) inside it.

**Why Tailscale SSH:** ACLs live in the tailnet rather than in `authorized_keys` files on every host, check mode can force re-authentication, access follows your identity provider, and a revoked device loses access immediately. Plain SSH still works as a fallback. Cloudflare and ngrok tunnels are a last resort, not the architecture; to reach a dev server on another machine, use [`agents forward`](#remote-feels-local-ports-links-and-files).

## mosh for flaky networks

Use mosh on cellular, roaming Wi-Fi, or a laptop that sleeps a lot. It comes with `--remote`.

```bash
mosh devbox -- tmux attach -t myproject
```

mosh needs UDP 60000–61000 open on the server. Its scrollback is only partially synced, so use tmux copy mode (`Ctrl+a [`) for history. A server reboot kills mosh but not tmux: always run mosh around tmux.

## Always-on nodes

A cheap box that stays awake (a Raspberry Pi, NUC or VM) is a **node**, not a second product. Put work there that must outlive your laptop lid. `--profile remote` installs on Debian/Ubuntu without Homebrew (see [profiles.md](profiles.md)). Herdr adds a sidebar that spans machines:

```bash
herdr machine add workbox                   # once, interactively; pick the session
herdr --machine workbox agent list          # from the Mac, no TUI
herdr --remote workbox                      # one-off thin client
```

On a node, `~/.local/bin` must be on `PATH` for *non-interactive* SSH too, which means adding it to `~/.profile`, not only `.zshrc`. Fleet practices are in [agent-workflows.md](agent-workflows.md#fleet-attention--herdr---pack-herdr).

## Remote feels local: ports, links and files

A dev server on another machine prints `http://localhost:5173`, and that is the other machine's localhost. With `--pack monitoring` on both machines and `--pack herdr` on the one that runs the panes, you don't have to think about it:

```bash
agents map                         # what runs where, on every machine; in Herdr: prefix+m
agents ports                       # what listens where: this machine and your others
agents ports --pick                # the same in fzf; enter opens the port in your browser
agents forward open workbox 5173   # bring that port here and open it
agents forward                     # the forwards: active, nothing answers, or dead
agents forward close --all         # or --dead: only the dead and the unanswered ones
agents push -m workbox shot.png    # into workbox's ~/.cache/tuidev/drop; prints (and copies) the path
agents open workbox /srv/app/report.html   # fetch one file and open it here
```

Your machines are the ones saved in Herdr (`herdr machine list`) plus any ssh hosts in `AGENTS_REMOTE_HOSTS` (`~/.config/agents.conf`); any ssh host works by name too.

**Use just this.** Each piece stands alone; take the one you need.

| Feature | Needs | Works without Herdr? |
|---|---|---|
| `agents map`, `agents ports`, `agents forward` | `--pack monitoring` on both machines, and ssh between them | Yes: list the hosts in `AGENTS_REMOTE_HOSTS` |
| `agents push`, `agents open` | `--pack monitoring` on this machine and ssh; `push` needs nothing of tuidev on the other end | Yes |
| The click on a link in a pane | Herdr with the `tuidev.link` plugin (`--pack herdr`) and `--pack monitoring` on both machines; the watcher on the machine you sit at | No: the click is Herdr's |
| Dropping a file onto a session | Claude Code on the other machine, `--pack monitoring` on both, the watcher and a Mac (for the dialog) where you sit | Yes: the watcher follows `AGENTS_REMOTE_HOSTS` hosts too |

**The map: what runs where, and one key to stop it.** `agents map` (prefix+m in Herdr, a popup over whatever you are doing) is one list for this machine and your others, grouped by what you would do with a thing rather than by where it is:

- **Previews and dev servers** come first: every port something was started to be looked at on, with its machine, command, project, CPU, memory and age, whether a session still owns it or it was left behind, and where it opens. A remote one that is already forwarded shows its local URL.
- **Files sessions just wrote**: the reports, pages and images an agent session wrote in the last day (from its Write and Edit calls), on any machine. Enter opens one on the machine you sit at, fetched first when it lives elsewhere, so reading what a remote agent produced takes no copying and no path typing.
- **Left behind**: stale processes and hogs nobody is using.
- **Sessions**: one line per agent session, with the mark of its kind (✳ claude, ⬡ codex, and the rest of [`AGENTS_GLYPHS`](agent-workflows.md)), its status and a count of what it runs (`ctrl-e` lists those). A server a session started says `by ✳ claude app`.
- **Machines**: each machine's CPU, free memory and counts.

The other machines answer over one shared ssh connection each, so the list comes up in a second or two.

| Key | On a preview or dev server | On something left behind | On a session | On a machine |
|---|---|---|---|---|
| `enter` | open it in your browser, forwarding first when it is remote | | go to its pane (here) or peek at it (elsewhere) | |
| `ctrl-k` (also `ctrl-x` and `delete`) | stop the process that holds it | stop its tree | stop its tree | |
| `ctrl-s` | sweep its machine | sweep its machine | | sweep it: `agents reap` stops what sessions left behind, asked first |
| `ctrl-p` | | | peek at its pane | |
| `ctrl-e` | | | list what each session runs | |
| `ctrl-r` | reload the list | | | |

On a forward, `enter` opens it and `ctrl-k` closes it. On a port row of another machine, `ctrl-k` stops the process and closes any forward to that port at once. A sweep (`ctrl-s`) or a stop there also closes click-made forwards to that machine that have nothing behind them. A cancelled or failed stop or sweep leaves every forward alone. `esc` quits.

A stop is `agents kill` on the machine that runs the thing, with its refusals and its y/N question. A dev server here is a listener started in a project directory: not an agent's own port, not an app or system service, not a daemon in your home directory (`agents ports` lists every listener).

So nothing needs `pkill`, and nothing needs you to remember which machine a dev server was started on. `agents map workbox` or `agents map local` narrows it to one machine; piped, it prints the list.

**Ctrl-click opens it here.** Ctrl-click a `localhost` URL in a Herdr pane of another machine and it opens in the browser of the machine you sit at, through a tunnel made on the spot. Ctrl-click a file link an agent printed (a `.md`, `.html`, image or PDF) and the file is fetched and opened here. Pieces:

- **The plugin** (`tuidev.link`, linked by `--pack herdr`). Herdr runs a plugin on the machine that owns the pane, so the click is handled over there, where there is no browser. The plugin hands it to `agents link click`.
- **The watcher** (`agents link watch`; a LaunchAgent on macOS, a tmux pane or systemd user service on Linux). The machine you sit at keeps one ssh to each of your machines and reads requests from it. Nothing listens anywhere, and the other machine never connects to yours.
- With no watcher connected, a click opens on the machine itself: a `localhost` URL in its browser, a file link when it is a format a viewer shows. "Connected" is the watcher, not you: sitting at a Mac that another of your Macs follows, a click there goes to the other one. Turn the watcher off on a machine you don't work from (`AGENTS_LINK=0`).

**Drop a file onto a session on another machine.** Drag a screenshot or a document from Finder onto a pane where Claude Code runs on another machine, and send your prompt as usual. The terminal only pastes the file's path, which exists on your Mac alone; the session's prompt hook notices a path that is not there and asks your machine for it. Your Mac shows one dialog (which machine, which file, from which folder, how big), and on **Send** copies the file into that machine's `~/.cache/tuidev/drop` and tells the session where to read it. Cancel, or no answer in 30 seconds, sends nothing, and the session is told you did not send it. A path your Mac has no file for (one the prompt only mentions, such as where to write a report) is not a dropped file: nobody is asked and the session hears nothing.

- A request is another machine asking for one of your files, so nothing is ever sent without that click, and some files are never even offered: anything with a hidden folder (`~/.ssh`, `~/.aws`, `~/.config`…) or a `Library` folder on its path, however either is spelled; anything reached through a symlink; anything outside your own home directory, the temp folders and mounted volumes; and anything over 50 MB. What is sent is the file the dialog showed, by its real path, and only if it is still that file when you click.
- A machine can't wear you down: after a request you did not approve, it is not asked about again for five minutes, and it gets three dialogs in five minutes at most.
- The prompt hook waits 50 seconds in all, so with several dropped files in one prompt, answer quickly or drop them one prompt at a time; a file approved after the hook gave up is still copied, and the session is not told.
- macOS may ask once to let the watcher read `Desktop`, `Documents` or `Downloads`; until you allow it, a file there is reported as unreadable in `~/Library/Logs/tuidev-link.log`.
- The dialog needs the Mac you sit at; from a Linux desktop use `agents push FILE`, which does the same copy by hand.
- The hook ships in Claude Code's settings (`UserPromptSubmit`) and starts `agents` only while a watcher is attached. Codex has no prompt hook to carry it: there, `agents push`.

`agents link` shows the watcher and each machine it follows. `--pack herdr` binds the plugin's keys as a managed block in `~/.config/herdr/config.toml`: prefix+m for the map and prefix+shift+o for the ports popup (`agents ports --pick`), beside prefix+space for the [board](agent-workflows.md#the-board-every-session-one-screen), prefix+a for the [palette and prefix+u for updates](agent-workflows.md#fleet-attention--herdr---pack-herdr). A binding of your own outside the block is yours to keep.

**What a forward is.** One `ssh -N -L` of its own, from this machine's `127.0.0.1` to the other machine's `localhost`: nothing is bound to a public address at either end. One you open yourself takes the same port number when that is free here, so the URL a program printed works as it stands; otherwise the next free one. ssh runs with `BatchMode`, so a machine that needs a password is reported, never prompted for: load the key (`ssh-add`) or reconnect it (`herdr machine reconnect workbox`) first. These connections carry nothing your ssh config would add for the host: no agent or X11 forwarding, and none of its `LocalForward` lines.

A forward is **active** (the server answers), **nothing answers** (the ssh is up but no server holds the port over there) or **dead** (its ssh is gone); `agents forward` and `agents map` show which. The check is a bare TCP connect through the tunnel, so nothing shows in the dev server's log. A forward you opened yourself with `agents forward open` stays for when the server comes up; it is only marked. A forward a click made closes itself: the link watcher (`agents link watch`, which wakes every 60 s) closes it after two checks in a row, at least 50 s apart, found nothing behind it, so about one to two minutes after the server stopped (a watcher restart cannot shorten that). The wait is deliberate, because dev servers restart all the time and a restart should not break your tab. A click-made forward whose ssh died is cleared too, and at the cap (eight click-made ones a machine) stale ones are cleared before a click is refused. A click on a port you already forwarded yourself reuses your forward, and it stays yours; a click-made forward you then open with `agents forward open` becomes yours, so it is no longer closed on its own. A click never closes a forward you opened yourself, even when nothing answers on it: it gets the banner and the forward stays. `agents forward close --dead` closes the dead ones and those where nothing answers. The menu bar lists a forward with nothing behind it as `localhost:PORT → MACHINE:PORT · nothing answers`: a click still opens it, and a `Close localhost:PORT` item under it closes it (a dead one closes on a click). It never probes, so it shows that only from a watcher check under 150 s old; with no watcher running, live forwards show as active. After an upgrade, a watcher that is already running keeps the old code until `agents link restart`. Limits: if the server comes back after its forward was closed, the old tab stays broken until you click the URL again (the new forward usually gets the same local port, so a reload then works); and without the watcher running nothing closes on its own, though the map's stop and `close --dead` still work.

**What leaves my machine.** Nothing goes to a service of tuidev's: there is none, and no telemetry. Between your own machines, over your own ssh:

| Feature | What crosses the wire | Who sends it |
|---|---|---|
| The map, `agents ports` and the menu's Machines row | The other machine's process list: command line, directory, ports | The other machine, when you ask |
| A click | The other machine sends a URL or a file path; your machine makes the tunnel or fetches the file | The other machine; the tunnel and the fetch are yours |
| A dropped file | That one file, after you click **Send** | You, to the machine that asked |
| `agents push` | The files you name | You |

The map shows other machines' command lines, so a secret passed as an argument shows up there. Pass secrets in the environment of one command ([secrets.md](secrets.md)).

**What another machine may ask for.** The watcher treats each line as a request and decides itself:

- a URL must be `http(s)` on `localhost`, `127.0.0.1`, `0.0.0.0` or `[::1]`; it becomes a tunnel to that machine's `localhost` and a tab on your `127.0.0.1`. Nothing else is opened;
- the local port is the watcher's choice, from 47000 up, never the port asked for: no request can put another machine behind a port your own tools use (`localhost:5432` while your database is down). At most eight click-made forwards a machine (the ones you open yourself with `agents forward open` do not count);
- a file must be an absolute path with a viewer's extension (Markdown, text, JSON, CSV, HTML, PDF, images), at most 50 MB, a cap applied on your machine; it lands in `~/.local/state/tuidev/agents/remote/MACHINE/`, where a requested file is kept a day and the folder at most 500 MB. Scripts and apps are never opened;
- at most five requests a machine in ten seconds.

What another machine sends is untrusted text. One set of checks (`lib/agents/awk/lib_maprows.awk`) decides, for the list and for the menu bar's board alike, whether a row is one: an id only in the shape of a process id (up to 10 digits, `@` and a start of up to 48 plain characters), a port a number, a file an absolute path of plain characters (up to 400), a forward only from this machine and with every field of its shape. No control character reaches your terminal: C0 and DEL, C1 (as UTF-8 writes it), and the bidi and line-separator characters (U+202A to U+202E, U+2066 to U+2069, U+2028, U+2029) become spaces. A long path is shortened so its recognisable part stays: a temp-directory binary shows its name first, and a file's path is cut in the middle.

Any process on the other machine can send a request, not only your click, so treat the watcher as "that machine may open a tab or a document here". The page it opens is that machine's content in your browser: the tab is on `127.0.0.1` so it shares no cookies with what you run on `localhost`, but like any forwarded dev server it can make requests to other loopback ports. Don't follow a machine you would not open a dev server from (`AGENTS_LINK=0`, or disable it in Herdr).

**When another tool is better.**

- **VS Code Remote-SSH** forwards the ports it sees in its terminal. If an editor is attached to the remote machine, use that. tuidev is for agents in a terminal or Herdr, where no editor is.
- **Tailscale Serve** publishes a service to your tailnet under a name, so a phone or a teammate can open it too. A tuidev forward is the opposite: loopback to loopback, on the machine you sit at, open while you need it, with nothing new reachable on the network.
- **Plain `ssh -L`** does the tunnel. `agents forward` adds a free local port (the same number when it is free), a list of what is open and whether each is active, unanswered or dead, forwards a click made that close themselves when the server stops, no password prompt, no agent forwarding, and `agents forward close --all`.

<details>
<summary>Limits worth knowing</summary>

- A click on a file link that can't open says why in a notification: the file is gone (moved or deleted since the link was printed, as with a file in a git worktree that was removed), or it is not a kind of file a click opens.
- The click needs Herdr's mouse capture on (`ui.mouse_capture`, the default) and is Ctrl-click on every platform. In saved-machine panes Herdr does not open OSC 8 links yet ([herdr#4447](https://github.com/herdrdev/herdr/issues/4447)), so there a link has to be on screen as its URL; `agents ports --pick` and `agents forward open` need no click.
- A forwarded server sees `Host: localhost:PORT`. One that checks the host name, or serves TLS for the machine's own name, may refuse.
- Herdr itself already bridges a pasted clipboard image; a dropped file is the section above.
- After your laptop sleeps, the other machine can take a while to notice the watcher is gone; a click in that window is lost. The watcher reconnects on its own.
- The LaunchAgent uses the ssh agent macOS gives every login session. A key that only an agent named in your shell's rc files holds (`SSH_AUTH_SOCK` set there) is not available to it: `agents link` then shows the machine as unreachable.
- `AGENTS_LINK=0` turns the watcher off; `agents link restart` applies a changed setting.

</details>

## Personal hosts stay local

`devbox` and `workbox` are placeholders. Real hostnames, Tailscale IPs and usernames go in `~/.ssh/config.local`. The shipped SSH block starts with `Match all` and then `Include ~/.ssh/config.local*`, so the include applies even when the block lands after your own `Host` stanzas, and a missing file is ignored. You can also put hosts outside the tuidev markers in `~/.ssh/config`. The shipped block keeps connections alive (`ServerAliveInterval 60`) and adds `IgnoreUnknown UseKeychain`, so the same file works with Linux OpenSSH.

## Herdr's phone app: `agents hc`

Herdr has a free phone app (iPhone, iPad, Android) with an inbox of the agents that need you, a key bar, dictation, and a compose box that pastes text, screenshots and photos. It talks over SSH to **herdr-core** (`hc`), the runtime under Herdr's desktop app, with no account and no server in between. It lists what runs in herdr-core. It does not see a program that a Herdr TUI pane owns, which is where your agents are when you type `claude` in a pane.

`agents hc run` closes that gap: it starts the agent in herdr-core and puts the pane on it.

```bash
tuidev install --pack monitoring --pack herdr-core   # agents hc, and herdr-core started at login
agents hc                      # is herdr-core running, and in your desktop login?
agents hc run claude           # in a Herdr pane: the agent, hosted in herdr-core
agents hc run --name api codex --no-daemon
```

The same agent is now in three places: the pane, Herdr's sidebar (each status the agent reports to herdr-core is passed on for that pane), and the phone's inbox. `ctrl+\` detaches and leaves it running; closing the pane does too. `agents hc attach NAME` comes back to it, `herdr-core ls` lists what runs, and `herdr-core kill NAME` ends one.

**Mirrors of the agents you already run (experimental, off by default).** With `AGENTS_HC_MIRROR=1` in `agents.conf`, while herdr-core is up, every agent pane of this machine's Herdr gets a mirror in it: a core terminal attached to the pane. The phone lists it, typing there reaches the agent in the pane, and the inbox has its state. Herdr's own events start and end the mirrors; `agents hc mirror` shows each pane and its mirror. It is off by default because of one fault: a pane takes its mirror's size, and Herdr's phone app sets that size when it shows a terminal. After the phone looked at a session, its pane at your desk can stay at the phone's size, with the agent's input out of view. `agents hc mirror end` ends every mirror and the panes take their own size again; setting `AGENTS_HC_MIRROR` back to 0 ends them at the next sync. A mirror is a view: ending one leaves the agent in its pane.

On the phone: install Tailscale and Herdr's app, then add the machine by its Tailscale name. Tailscale SSH needs no key; plain SSH needs Remote Login on and the phone's key in `authorized_keys`, as [below](#iphone-and-ipad).

Things to know:

- **macOS: the core must run in your desktop login.** A core that the phone starts over SSH runs outside it, and Claude Code there says "Not logged in", because it cannot reach the Keychain. The pack's LaunchAgent (`dev.tuidev.hc`) starts the core at login so the phone finds that one. `agents hc` says when the running core is the wrong kind, and `agents hc run` refuses to start a program in it. tuidev never stops a core by itself: `agents hc up --restart`, at the Mac and not over SSH, replaces it, which ends the terminals it holds.
- **The agent gets herdr-core's environment, not the pane's.** It starts in the pane's directory, but a variable you exported in that shell is not there. `herdr-core server restart --fresh`, from a terminal outside Herdr, gives the core that shell's environment for new terminals.
- **Typing from the phone takes the terminal's size.** The last viewer that types sets it, so the pane redraws at phone width until you type at the desk again, which gives it the desk's size back. Watching from the phone changes nothing.
- **Each machine has its own herdr-core.** The phone app adds machines one by one over SSH (it suggests your SSH hosts and Tailscale devices).
- **A machine with no desktop** (a Linux node) has no Keychain to miss: log Claude Code in there with `claude setup-token`.
- herdr-core is a 0.1 preview and is not installed by tuidev: [herdr.dev/core](https://herdr.dev/core/) has its installer, and Herdr's desktop app brings it too.
- **What was tested.** On one Mac (herdr-core 0.1.21, Herdr 0.9.5) with one phone: an agent started with `agents hc run` appeared in the phone's inbox, and with mirrors on, five agent panes were listed there. The mirrors then showed the size fault above. The login item was not tested across a real logout and login, and on Linux only the unit tests ran, with no real herdr-core.

The rest of this section is the terminal-app path, which needs none of the above and shows the whole TUI.

## iPhone and iPad

| Client | Why pick it |
|--------|-------------|
| **Blink Shell** | Power users: native mosh, a full local shell, a customizable keyboard, iCloud sync |
| **Moshi** | Agent-first: native mosh, an agent inbox, Live Activities and Apple Watch actions, voice input for prompts |
| Termius | Cross-platform host and key sync, SFTP, snippets |
| a-Shell / Prompt | Lightweight options for occasional local-network SSH |

Setup is the same for every client:

1. Install Tailscale on the phone and sign in to the same tailnet.
2. Generate an **Ed25519** key in the app, and append its public key to `~/.ssh/authorized_keys` on the host (`chmod 600` the file, `chmod 700 ~/.ssh`). The shipped sshd snippet disables password login.
3. Add a host with the node's Tailscale name or `100.x` address (`ts-ip`), your user, port 22, and **mosh** as the protocol if the app offers it.
4. Connect and run `t myproject`, or `herdr` to join the node's Herdr session (`herdr session attach NAME` for a named one). Save it as the host's startup command to land there directly.

Tips:

- The prefix `Ctrl+a` comes from the app's extra key row. Map a snippet to `Ctrl+a d` to detach quickly.
- Herdr's `Ctrl+b` is awkward on a phone keyboard. Herdr ≥ 0.9.2 takes several prefixes, e.g. `prefix = ["ctrl+b", "ctrl+s"]` under `[keys]` in `~/.config/herdr/config.toml`.
- Bigger fonts help on a phone screen; a single tmux pane reads better than a cramped split.
- A Bluetooth keyboard makes every tmux and nvim binding usable.
- *Connection refused:* check that Remote Login is on (`sudo systemsetup -getremotelogin`) and that the Mac isn't asleep.
- *Laggy over cellular:* switch the host to mosh. *Keeps dropping:* the shipped keepalives help, and mosh plus tmux makes drops irrelevant.

## Anti-patterns

- Hand-rolled key rotation when Tailscale SSH already owns access control.
- `screen`. tmux-resurrect and continuum target tmux.
- Agents on the host filesystem with no sandbox. See [sandboxing.md](sandboxing.md).
- Committing real hostnames or IPs. See [CONTRIBUTING.md](../CONTRIBUTING.md#personal-vs-published).
