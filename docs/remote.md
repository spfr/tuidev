# Remote and Mobile

Run your agents anywhere: on your laptop, on a VM or a box that stays on, and pick them up from your phone. This doc sets up an always-on machine you connect to, makes its agents' previews, links and files open on the machine you sit at, and puts its agents in your phone's inbox. It is all plain SSH between your own machines: nothing listens on a public address, and there is no service in between. Seeing what those agents do is the other half: [agent-workflows.md](agent-workflows.md).

The host runs the terminal, the agents and their sessions; you connect from any client and re-attach. Work survives a dropped connection because Herdr or tmux keeps it. Tailscale, SSH, mosh and phone apps are only transport.

## Setup

On the machine you'll connect to:

```bash
curl -fsSL https://github.com/spfr/tuidev/releases/latest/download/get.sh | bash -s -- --profile remote --pack ai-clis
tailscale up && tailscale status  # join the tailnet
```

The same install is the third choice ("A headless box that stays on") when you run the one-liner without flags. On a Mac you also sit at, add the pieces to what it has: `tuidev install --remote --pack tmux`. Once the box has `tuidev`, `tuidev update` keeps it current.

`--profile remote` is core, remote, the sandbox and `--pack tmux`: Tailscale, mosh, SSH and a durable tmux session in one install. `--remote` on its own installs Tailscale (a cask on macOS; on Linux it links to the official installer), mosh, the SSH client config as a managed block, and sshd hardening snippets: key-only auth, no root login, modern ciphers. The snippets are copied into `/etc/ssh/sshd_config.d/` only when that directory is writable; otherwise the installer prints the `sudo cp` commands. On macOS, turn on Remote Login in System Settings → General → Sharing, or run `sudo systemsetup -setremotelogin on`.

`remote-status` shows SSH, Tailscale and tmux at a glance. `ts-ip` prints the machine's Tailscale address.

## Connect and re-attach

```bash
ssh devbox                  # or: tailscale ssh devbox
t myproject                 # attach-or-create a named tmux session
# ...network drops, laptop sleeps...
ssh devbox && t myproject
```

Detach with `Ctrl+a d`; `tls` lists sessions. tmux-continuum saves every 15 minutes and tmux-resurrect restores sessions when tmux starts, so sessions survive a reboot too. `t myproject` gives you a plain session; run your editor inside it.

**Why Tailscale SSH:** access rules live in the tailnet rather than in `authorized_keys` on every host, check mode can force re-authentication, access follows your identity provider, and a revoked device loses access at once. Plain SSH still works. Public tunnels are a last resort; to reach a dev server on another machine, use [`agents forward`](#remote-feels-local-ports-links-and-files).

## mosh for flaky networks

Use mosh on cellular, roaming Wi-Fi, or a laptop that sleeps a lot. It comes with `--remote`.

```bash
mosh devbox -- tmux attach -t myproject
```

mosh needs UDP 60000–61000 open on the server. Its scrollback is only partly synced, so use tmux copy mode (`Ctrl+a [`) for history. A server reboot kills mosh but not tmux: always run mosh around tmux.

## Always-on machines

A cheap box that stays awake (a Raspberry Pi, a NUC, a VM) is where work goes that must outlive your laptop lid. `--profile remote` installs on Debian and Ubuntu without Homebrew ([profiles.md](profiles.md)). Herdr adds one sidebar across machines:

```bash
herdr machine add workbox                   # once, interactively; pick the session
herdr --machine workbox agent list          # from the Mac, no TUI
herdr --remote workbox                      # one-off thin client
```

On such a machine, `~/.local/bin` must be on `PATH` for non-interactive SSH too, so add it to `~/.profile`, not only `.zshrc`. Herdr's practices, sessions and a systemd unit that keeps them running: [agent-workflows.md](agent-workflows.md#herdr-which-agent-needs-you---pack-herdr).

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

Your machines are the ones saved in Herdr (`herdr machine list`) plus any ssh hosts in `AGENTS_REMOTE_HOSTS` (`~/.config/agents.conf`); any ssh host works by name too. Each piece stands alone:

| Feature | Needs | Works without Herdr? |
|---|---|---|
| `agents map`, `agents ports`, `agents forward` | `--pack monitoring` on both machines, and ssh between them | Yes: list the hosts in `AGENTS_REMOTE_HOSTS` |
| `agents push`, `agents open` | `--pack monitoring` on this machine and ssh; `push` needs nothing of tuidev on the other end | Yes |
| The click on a link in a pane | Herdr with the `tuidev.link` plugin (`--pack herdr`) and `--pack monitoring` on both machines; the watcher on the machine you sit at | No: the click is Herdr's |
| Dropping a file onto a session | Claude Code on the other machine, `--pack monitoring` on both, the watcher, and a Mac where you sit (for the dialog) | Yes: the watcher follows `AGENTS_REMOTE_HOSTS` hosts too |

### The map: what runs where, and one key to stop it

`agents map` (prefix+m in Herdr, a popup over whatever you are doing) is one list for this machine and your others, grouped by what you would do with a thing:

- **Previews and dev servers** first: every port something was started to be looked at on, with its machine, command, project, CPU, memory and age, whether a session still owns it or it was left behind, and where it opens. A remote one already forwarded shows its local URL.
- **Files sessions just wrote**: the reports, pages and images a session wrote in the last day, on any machine. Enter opens one here, fetched first when it lives elsewhere.
- **Left behind**: stale processes and hogs nobody is using.
- **Sessions**: one line per agent session, with its kind's [mark](agent-workflows.md#marks-by-kind-of-session), its status and a count of what it runs.
- **Machines**: each machine's CPU, free memory and counts.

The other machines answer over one shared ssh connection each, so the list comes up in a second or two. `agents map workbox` or `agents map local` narrows it to one machine; piped, it prints the list.

| Key | On a preview or dev server | On something left behind | On a session | On a machine |
|---|---|---|---|---|
| `enter` | open it in your browser, forwarding first when it is remote | | go to its pane (here) or peek at it (elsewhere) | |
| `ctrl-k` (also `ctrl-x`, `delete`) | stop the process that holds it | stop its tree | stop its tree | |
| `ctrl-s` | sweep its machine | sweep its machine | | sweep it: `agents reap` stops what sessions left behind that is safe to stop, asked first |
| `ctrl-p` | | | peek at its pane | |
| `ctrl-e` | | | list what each session runs | |
| `ctrl-r` | reload the list | | | |

On a forward, `enter` opens it and `ctrl-k` closes it. Stopping a port on another machine also closes any forward to it, and a stop or sweep closes click-made forwards to that machine with nothing behind them. A stop is `agents kill` on the machine that runs the thing, with its refusals and its y/N question. `esc` quits.

### Ctrl-click opens it here

Ctrl-click a `localhost` URL in a Herdr pane of another machine and it opens in the browser of the machine you sit at, through a tunnel made on the spot. Ctrl-click a file link an agent printed (a `.md`, `.html`, image or PDF) and the file is fetched and opened here.

- **The plugin** (`tuidev.link`, linked by `--pack herdr`). Herdr runs a plugin on the machine that owns the pane, so the click is handled over there; the plugin hands it to `agents link click`.
- **The watcher** (`agents link watch`: a LaunchAgent on macOS, a tmux pane or systemd user service on Linux). The machine you sit at keeps one ssh to each of your machines and reads requests from it. Nothing listens anywhere, and the other machine never connects to yours.
- With no watcher connected, a click opens on the machine itself. Turn the watcher off on a machine you don't work from (`AGENTS_LINK=0`).

`agents link` shows the watcher and each machine it follows. `--pack herdr` binds the plugin's keys in `~/.config/herdr/config.toml`: prefix+m for the map and prefix+shift+o for the ports popup, beside prefix+space for the [board](agent-workflows.md#the-board-every-session-one-screen) and prefix+a and prefix+u for the [palette and updates](agent-workflows.md#herdr-which-agent-needs-you---pack-herdr).

### Drop a file onto a session on another machine

Drag a screenshot or a document from Finder onto a pane where Claude Code runs on another machine, and send your prompt as usual. The terminal pastes only the file's path, which exists on your Mac alone; the session's prompt hook notices and asks your machine for it. Your Mac shows one dialog (which machine, which file, how big), and on **Send** copies the file into that machine's `~/.cache/tuidev/drop` and tells the session where to read it. Cancel, or no answer in 30 seconds, sends nothing. A path your Mac has no file for is not a drop: nobody is asked.

- Nothing is sent without that click, and some files are never offered: anything in a hidden folder (`~/.ssh`, `~/.aws`, `~/.config`…) or a `Library` folder, anything reached through a symlink, anything outside your home directory, the temp folders and mounted volumes, and anything over 50 MB. What is sent is the file the dialog showed, if it is still that file.
- After a request you did not approve, a machine is not asked about again for five minutes, and it gets three dialogs in five minutes at most.
- The prompt hook waits 50 seconds in all, so drop several files one prompt at a time.
- macOS may ask once to let the watcher read `Desktop`, `Documents` or `Downloads`; until then, a file there is reported as unreadable in `~/Library/Logs/tuidev-link.log`.
- From a Linux desktop, or for Codex (it has no prompt hook), use `agents push FILE`.

### Forwards

A forward is one `ssh -N -L` of its own, from this machine's `127.0.0.1` to the other machine's `localhost`: nothing is bound to a public address at either end. One you open yourself takes the same port number when that is free here, so the URL a program printed works as it stands. ssh runs with `BatchMode`, so a machine that needs a password is reported, never prompted for: load the key (`ssh-add`) or reconnect it (`herdr machine reconnect workbox`) first. These connections carry no agent or X11 forwarding and none of your config's `LocalForward` lines.

A forward is **active** (the server answers), **nothing answers** (the ssh is up, no server holds the port) or **dead** (its ssh is gone); `agents forward` and `agents map` show which, by a bare TCP connect that leaves nothing in the server's log.

- **One you opened** with `agents forward open` stays until you close it, waiting for the server to come back.
- **One a click made** closes itself about one to two minutes after its server stops (the watcher, which wakes every 60 s, needs two checks in a row with nothing behind it, so a restarting dev server doesn't break your tab). A click on a port you forwarded yourself reuses your forward. At most eight click-made forwards per machine.
- `agents forward close --dead` closes the dead ones and those nothing answers. The menu bar lists a forward with nothing behind it as `localhost:PORT → MACHINE:PORT · nothing answers`, with a Close item.
- After an upgrade, a running watcher keeps the old code until `agents link restart`.

### What leaves your machine

Nothing goes to a service of tuidev's: there is none, and no telemetry. Between your own machines, over your own ssh:

| Feature | What crosses the wire | Who sends it |
|---|---|---|
| The map, `agents ports` and the menu's Machines row | The other machine's process list: command line, directory, ports | The other machine, when you ask |
| A click | A URL or a file path; your machine makes the tunnel or fetches the file | The other machine; the tunnel and the fetch are yours |
| A dropped file | That one file, after you click **Send** | You, to the machine that asked |
| `agents push` | The files you name | You |

The map shows other machines' command lines, so a secret passed as an argument shows up there. Pass secrets in one command's environment ([secrets.md](secrets.md)).

**What another machine may ask for.** The watcher treats each line as a request and decides itself:

- a URL must be `http(s)` on `localhost`, `127.0.0.1`, `0.0.0.0` or `[::1]`; it becomes a tunnel to that machine's `localhost` and a tab on your `127.0.0.1`. Nothing else is opened;
- the local port of a click-made forward is the watcher's choice, from 47000 up, never the port asked for, so no request can put another machine behind a port your own tools use;
- a file must be an absolute path with a viewer's extension (Markdown, text, JSON, CSV, HTML, PDF, images), at most 50 MB; it lands in `~/.local/state/tuidev/agents/remote/MACHINE/`, kept a day, the folder at most 500 MB. Scripts and apps are never opened;
- at most five requests a machine in ten seconds.

What another machine sends is untrusted text. One set of checks (`lib/agents/awk/lib_maprows.awk`) decides, for the map, the board and the menu bar alike, whether a row is valid, and no control character reaches your terminal (C0, DEL, C1 and the bidi and line-separator characters become spaces).

Any process on the other machine can send a request, not only your click, so following a machine means "that machine may open a tab or a document here". The tab is on `127.0.0.1`, so it shares no cookies with what you run on `localhost`, but like any forwarded dev server it can make requests to other loopback ports. Don't follow a machine you would not open a dev server from (`AGENTS_LINK=0`).

**When another tool is better.** VS Code Remote-SSH forwards the ports it sees when an editor is attached to the machine. Tailscale Serve publishes a service to your tailnet under a name, for a phone or a teammate. Plain `ssh -L` does the tunnel; `agents forward` adds a free local port, a list with each forward's state, forwards that close themselves, and no password prompt.

<details>
<summary>Limits worth knowing</summary>

- A click on a file link that can't open says why in a notification: the file is gone, or it is not a kind of file a click opens.
- The click needs Herdr's mouse capture on (`ui.mouse_capture`, the default) and is Ctrl-click on every platform. In saved-machine panes Herdr does not open OSC 8 links yet ([herdr#4447](https://github.com/herdrdev/herdr/issues/4447)), so there a link has to be on screen as its URL; `agents ports --pick` and `agents forward open` need no click.
- A forwarded server sees `Host: localhost:PORT`. One that checks the host name, or serves TLS for the machine's own name, may refuse.
- If the server comes back after its click-made forward closed, the old tab stays broken until you click the URL again. Without the watcher running, nothing closes on its own.
- After your laptop sleeps, a click can be lost until the other machine notices the watcher is gone. The watcher reconnects on its own, so each machine is back within about a minute of waking.
- The LaunchAgent uses the ssh agent macOS gives every login session; a key only an agent named in your shell's rc files holds is not available to it, and `agents link` shows the machine as unreachable.

</details>

## Steer one agent from your phone

<a id="remote-control-from-a-phone"></a>To steer one agent without a terminal, use the CLI's own remote control. **Claude Code Remote Control** connects `claude.ai/code` and the Claude mobile apps to a session running on your machine; code stays local ([plan requirements](https://code.claude.com/docs/en/remote-control)). For an inbox of every agent that needs you, use [Herdr's phone app](#herdrs-phone-app-agents-hc). For a full terminal (editing files, non-agent work, a flaky network), use SSH or mosh from a [phone terminal app](#iphone-and-ipad).

## Herdr's phone app: `agents hc`

Herdr has a free phone app (iPhone, iPad, Android) with an inbox of the agents that need you, a key bar, dictation, and a compose box that pastes text, screenshots and photos. It talks over SSH to **herdr-core**, the runtime under Herdr's desktop app, with no account and no server in between. It lists what runs in herdr-core; it does not see a program a Herdr TUI pane owns, which is where your agents are when you type `claude` in a pane. `agents hc run` closes that gap: it starts the agent in herdr-core and puts the pane on it.

```bash
tuidev install --pack monitoring --pack herdr-core   # agents hc, and herdr-core kept running
agents hc                      # is herdr-core running and in your desktop login; is a phone connected now
agents hc run claude           # in a Herdr pane: the agent, hosted in herdr-core
agents hc run --name api codex --no-daemon
agents hc ls                   # what the phone lists from here, and the agent panes it can't reach
```

The same agent is then in three places: the pane, Herdr's sidebar (each status the agent reports to herdr-core is passed on), and the phone's inbox. `ctrl+\` detaches and leaves it running; closing the pane does too. `agents hc attach NAME` comes back to it, `herdr-core ls` lists what runs, and `herdr-core kill NAME` ends one.

On the phone: install Tailscale and Herdr's app, then add the machine by its Tailscale name. Tailscale SSH needs no key; plain SSH needs Remote Login on and the phone's key in `authorized_keys`, as [below](#iphone-and-ipad). Each machine has its own herdr-core, added one by one.

**Hosted without typing `agents hc run` (opt-in).** With `AGENTS_HC_AUTO=1` in `agents.conf`, a `claude` or `codex` you type in a Herdr pane is hosted in herdr-core by itself. The herdr-core pack's shell fragment defines `claude` and `codex` as functions that call `agents hc auto` in interactive shells in Herdr panes; a new shell picks up a change. It hosts the agent only when all of these hold, and otherwise runs the command as you typed it:

- you typed it at the terminal, in a Herdr pane, not in a terminal of herdr-core's;
- the arguments start an interactive session: none, or options such a session takes (`--continue`, `--resume ID`, `--model opus`, `--add-dir DIR`, `codex resume --last`). `claude -p`, `--help`, a prompt (`claude "fix the test"`), a subcommand (`claude mcp list`, `codex exec …`) or an option it doesn't know run as typed;
- the pane sets no account, provider or network of its own for the agent (`ANTHROPIC_API_KEY`, `CLAUDE_CODE_USE_BEDROCK`, `OPENAI_API_KEY`, `HTTPS_PROXY`, `NODE_EXTRA_CA_CERTS` and the like), which a hosted agent would not get;
- herdr-core already runs (it is never started from here) and, on macOS, runs in your desktop login.

It adds about 20 ms to a start it does not host. When the core doesn't answer within 5 s, or refuses the start, the agent starts in the pane after one line that says why. `codex` is hosted with `--no-daemon`, which herdr-core needs. It hosts nothing started another way (a script, `command claude`, an agent's own shell). `agents hc` says whether it is on.

**What a hosted agent gets.** The pane's directory and `PATH`, and from the pane's environment only `LANG`, `LC_ALL`, `LC_CTYPE`, `LC_MESSAGES`, `TZ`, `EDITOR`, `VISUAL`, `CLAUDE_CONFIG_DIR` and `CODEX_HOME`; everything else comes from herdr-core's environment. A token you exported in that shell is not passed on: it would live on in a core that outlives the pane. `herdr-core server restart --fresh`, from a terminal outside Herdr, gives the core that shell's environment for new terminals.

### Mirrors of the agents you already run (experimental)

With `AGENTS_HC_MIRROR=1` in `agents.conf`, while herdr-core is up, every agent pane of this machine's Herdr gets a mirror in it: a core terminal attached to the pane. The phone lists it, typing there reaches the agent in the pane, and the inbox has its state. A mirror is named after the session's task title when it has one (`fix-login-redirect`). Herdr's own events start and end the mirrors. A mirror is a view: ending one leaves the agent in its pane.

```bash
agents hc mirror           # each agent pane and its mirror (opted-out panes marked); also: status
agents hc mirror fit       # the focused pane takes its size back from a phone that still shows it
agents hc mirror off       # in a Herdr pane: no mirror for this one (on brings it back; PANE for another)
agents hc mirror end       # end every mirror; the panes take their own size again
```

It is off by default because a pane takes its mirror's size, and Herdr's phone app sets that size while it shows the session: the pane at your desk then has the phone's size. When the phone lets go, herdr-core gives the terminal its default size and the mirror gives the pane its own size back within a second or two. Setting `AGENTS_HC_MIRROR` back to 0 ends the mirrors at the next sync.

<a id="a-phone-sized-pane-at-your-desk"></a>**A phone-sized pane at your desk.** Herdr's phone app keeps the last session it opened attached while it shows its Inbox, so that pane can keep the phone's size (about 43x31) while the app stays open. Click into the pane, or switch to its tab, and it takes your desk's size back: the `tuidev.link` plugin's `pane.focused` hook runs `agents hc mirror fit -q`, which sets the mirror's terminal to the pane's place in the layout. `agents hc mirror` shows `phone-sized: 43x31 of 139x48` next to a pane that needs it. The phone then shows the pane's top left until it sets a size again (you open the session again, or turn the phone), and from then the pane is phone-sized until you next focus it at the desk: the desk wins while you are at it, the phone when it acts. `AGENTS_HC_MIRROR_FIT=0` makes the focus hook do nothing (the command still works). Checked with a 43x31 viewer that stayed attached (the pane went to 138x48 within a second and kept it), and once with the phone app itself, on 3.27.0: a pane it was still showing went back to full width when focused at the desk.

**Keep a pane off the phone.** `agents hc mirror off` in a Herdr pane (or `agents hc mirror off PANE`; `agents hc mirror` lists the ids) ends that pane's mirror and keeps later syncs from starting one; `agents hc mirror on [PANE]` takes it back. The list is kept in `~/.config/tuidev/run/hc-mirror.off`, not with your settings, because a pane id names a pane of the Herdr server that runs now: after a Herdr restart the new panes start with mirrors on again. It applies to mirrors only, not to an agent you hosted with `agents hc run`. You can opt a pane out while mirrors are off.

### What the phone reaches, and where it shows

`agents hc ls` lists what the phone lists from this machine: each herdr-core terminal with its name, whether it is hosted (and in which pane) or a mirror (and of which agent), its state as the core has it (`working`, `needs you`, `idle`, `done`, `live`, `finished` or `exited N`) and its directory. A last line counts the agent panes the phone can't reach, and why: opted out, mirrors off, or not mirrored yet. It never starts a core; with none running, or one that doesn't answer within 5 s, it says so and exits 1.

On the [board](agent-workflows.md#the-board-every-session-one-screen), a session the phone reaches has a `☏` (`@` without UTF-8; `AGENTS_GLYPHS="phone=P"` picks your own), and its card says `on the phone: hosted in herdr-core as api` or `on the phone: mirrored as fix-login`; its `ctrl-p` list can turn its pane's mirror off or on. The mark comes from a cache a background check rewrites at most every 30 s, so it can be up to 30 s late.

With herdr-core installed, the palette (`tuidev`) has `Phone: status`, `Phone: mirrors` and `Phone: start an agent here`, and the [menu bar](agent-workflows.md#menu-bar-swiftbar-macos) has one Phone line: the core is up, how many agents are mirrored, or that it is not running. Neither ever starts a core to look.

### Running it

- **The app shows nothing, or stays on "connecting".** `agents hc` says whether a phone is connected now. With none connected and the mirrors listed by `agents hc ls`, the fault is the network between the phone and this machine: look at Tailscale's own warnings on the phone (a stuck one clears when you turn it off and on), then reopen the app.
- **macOS: the core must run in your desktop login.** A core the phone starts over SSH runs outside it, and Claude Code there says "Not logged in": it can't reach the Keychain. The pack's LaunchAgent (`dev.tuidev.hc`) starts the core at login so the phone finds that one. `agents hc`, and the menu bar, say when the running core is the wrong kind, and `agents hc run` refuses to use it. tuidev never stops a core by itself: `agents hc up --restart`, at the Mac and not over SSH, replaces it, which ends its terminals.
- **The core is started again if it stops.** The pack's job runs `agents hc up -q` at login and every 5 minutes (the LaunchAgent on macOS, `tuidev-hc.timer` on Linux): with a core running it changes nothing; with none, it starts one, and with mirrors on it syncs them. A problem it can't fix goes to its log once (`~/Library/Logs/tuidev-hc.log`, or `journalctl --user -u tuidev-hc`). To keep a core you stopped down, set `AGENTS_HC_UP=0`; `agents hc up` still works by hand. Unloading the job lasts only until the next login on macOS, and until the next `tuidev update` or `tuidev check --fix`.
- **On an always-on Linux box**, install the same two packs, and herdr-core with its own installer (it has a linux-aarch64 build). The `tuidev-hc.timer` user timer starts the core and checks it every 5 minutes; a user manager runs without a login only with lingering on (`sudo loginctl enable-linger $USER`, which the pack prints when it is off). herdr-core runs its server in a unit of its own, so stopping the timer never ends its agents. There is no Keychain: log Claude Code in once with `claude` and `/login`, which keeps the login in a file every agent on the box can read (a token exported in your shell does not reach a hosted agent). Without systemd (a container), start the core with `agents hc up`.
- herdr-core is a 0.1 preview and is not installed by tuidev: [herdr.dev/core](https://herdr.dev/core/) has its installer, and Herdr's desktop app brings it too.
- **What was tested.** On one Mac (herdr-core 0.1.21, Herdr 0.9.5) with one phone: an agent started with `agents hc run` appeared in the phone's inbox, and with mirrors on, five agent panes were listed there. Getting a pane's size back was tested on that Mac with a 43x31 viewer attached to a mirror and then closed, and with one that stayed attached while the pane was focused; with the phone app itself, a pane it was still showing went back to full width when focused at the desk (once, on 3.27.0). The login item was not tested across a real logout and login, nor the 5-minute restart with a real core. On Linux only the unit tests ran, with stand-ins for systemd and no real herdr-core.

## iPhone and iPad

The terminal path needs none of the above and shows the whole TUI.

| Client | Why pick it |
|--------|-------------|
| **Blink Shell** | Power users: native mosh, a full local shell, a customizable keyboard, iCloud sync |
| **Moshi** | Agent-first: native mosh, an agent inbox, Live Activities and Apple Watch actions, voice input for prompts |
| Termius | Cross-platform host and key sync, SFTP, snippets |
| a-Shell / Prompt | Lightweight options for occasional local-network SSH |

Setup is the same for every client:

1. Install Tailscale on the phone and sign in to the same tailnet.
2. Generate an **Ed25519** key in the app, and append its public key to `~/.ssh/authorized_keys` on the host (`chmod 600` the file, `chmod 700 ~/.ssh`). The shipped sshd snippet disables password login.
3. Add a host with the machine's Tailscale name or `100.x` address (`ts-ip`), your user, port 22, and **mosh** as the protocol if the app offers it.
4. Connect and run `t myproject`, or `herdr` to join the machine's Herdr session (`herdr session attach NAME` for a named one). Save it as the host's startup command to land there directly.

Tips:

- The prefix `Ctrl+a` comes from the app's extra key row. Map a snippet to `Ctrl+a d` to detach quickly.
- Herdr's `Ctrl+b` is awkward on a phone keyboard. Herdr takes several prefixes: `prefix = ["ctrl+b", "ctrl+s"]` under `[keys]` in `~/.config/herdr/config.toml`.
- Bigger fonts help on a phone screen; a single pane reads better than a cramped split. A Bluetooth keyboard makes every binding usable.
- *Connection refused:* check that Remote Login is on (`sudo systemsetup -getremotelogin`) and that the Mac isn't asleep.
- *Laggy over cellular:* switch the host to mosh. *Keeps dropping:* the shipped keepalives help, and mosh plus tmux makes drops irrelevant.

## Personal hosts stay local

`devbox` and `workbox` are placeholders. Real hostnames, Tailscale addresses and usernames go in `~/.ssh/config.local`. The shipped SSH block starts with `Match all` and then `Include ~/.ssh/config.local*`, so the include applies even when the block lands after your own `Host` stanzas, and a missing file is ignored. You can also put hosts outside the tuidev markers in `~/.ssh/config`. The shipped block keeps connections alive (`ServerAliveInterval 60`) and adds `IgnoreUnknown UseKeychain`, so the same file works with Linux OpenSSH.

## Anti-patterns

- Hand-rolled key rotation when Tailscale SSH already owns access control.
- `screen`: tmux-resurrect and continuum target tmux.
- Agents on the host filesystem with no sandbox. See [sandboxing.md](sandboxing.md).
- Committing real hostnames or IPs. See [CONTRIBUTING.md](../CONTRIBUTING.md#personal-vs-published).
