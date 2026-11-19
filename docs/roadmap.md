# Roadmap

*As of 19 November 2026 (3.27.2).*

What already works for running agents anywhere and seeing what they do, what comes next, what tuidev will deliberately not do, and which outside projects it watches. The why behind these choices is in [VISION.md](../VISION.md).

## Done

**Run agents anywhere.**

- One-line install with a preview, a recorded manifest, `tuidev update` with rollback, and `tuidev uninstall` ([updating.md](updating.md)).
- Profiles for a Mac you sit at, a headless box that stays on and a bare shell ([profiles.md](profiles.md)).
- Another machine's ports, links and files here, over plain ssh: `agents map`, `agents forward`, and Ctrl-click in a Herdr pane ([remote.md](remote.md#remote-feels-local-ports-links-and-files)).
- Agents on the phone through Herdr's phone app: `agents hc run`, opt-in hosting of a plain `claude`, and herdr-core kept running on macOS and on an always-on Linux box ([remote.md](remote.md#herdrs-phone-app-agents-hc)).

**See everything they do.**

- Who needs you, across machines: Herdr's sidebar with named tabs, `agents board`, the SwiftBar menu and clickable notifications ([agent-workflows.md](agent-workflows.md#fleet-attention--herdr---pack-herdr)).
- What they run and leave behind: a verdict with evidence for every flagged process, and `agents reap`, which stops only what is safe to stop ([agent-workflows.md](agent-workflows.md#flagged-is-it-safe-to-stop)).
- What it costs: CPU by project and job, tokens at API list prices, usage limits, from a sampler that runs with or without the menu bar ([agent-workflows.md](agent-workflows.md#history-and-agents-report)).
- A memory guard on macOS and Linux, and `agents doctor` and `tuidev check --fix` to say whether all of it is running ([agent-workflows.md](agent-workflows.md#memory-guard-agents-mem)).

**Keep agents away from your keys.**

- Both CLIs' own sandboxes on, one credential list for them and `sbx`, token variables (model providers' keys included) unset in agents' commands, and `secret` for API tokens ([sandboxing.md](sandboxing.md), [secrets.md](secrets.md)).

**Around the agents.**

- Tiered subagents for Claude Code and Codex ([orchestration.md](orchestration.md)), fan control for a MacBook under agent load, a 3-day wait for new package versions, and audits of what the OS does behind your agents and what they leave on disk ([performance.md](performance.md)).

## Next

- **Read the shared status signal.** The Program Status Protocol ([OSC 7501](https://github.com/ghostty-org/ghostty/pull/14560)) lets a program tell its terminal whether it is idle, working, blocked on the user, done or failed. Claude Code and [Codex](https://github.com/openai/codex/pull/52725) emit it, and herdr-core stores it. tuidev intends to read it, so agent state works under any terminal that carries it, not only under the hosts it integrates with today. No date.
- **Finish the checks on real hardware** that [remote.md](remote.md#herdrs-phone-app-agents-hc) lists as open: a mirrored pane getting its size back when the phone app lets go, so far checked only with a stand-in viewer (mirrors are experimental and off by default), herdr-core's login item across a real logout and login, and herdr-core on Linux with a real core.
- **Keep host glue thin.** `agents` holds the logic, and a host (Herdr, the menu bar) supplies panes and a place to show state, so a host that does something better can take it over and tuidev's version can go.

Open to contributions: a `bubblewrap` backend for `sbx` on Linux, and wider `dnf` and `pacman` coverage ([CONTRIBUTING.md](../CONTRIBUTING.md#where-changes-go)).

## Not planned

- **A terminal, a multiplexer or a phone app of its own.** Ghostty, tmux and Herdr do that.
- **Installing the agent CLIs.** Claude Code and Codex update themselves.
- **A hosted service, accounts or telemetry.** Everything reads local files; the one request tuidev makes is the daily release check.
- **Codex cleanup hooks.** Codex says its transcript format is not a stable interface for hooks, and its hook input doesn't list the background commands still running, so a command can't be tied to the subagent that started it ([agent-workflows.md](agent-workflows.md#cleanup-hooks-claude-code)).
- The rest of what tuidev will not become (a terminal IDE, in-editor agents, a team secret manager, non-FOSS defaults) is in [VISION.md](../VISION.md#what-tuidev-will-not-become).

## Watch-list

| Project | Status | Adopt when | Hold because |
|---|---|---|---|
| **Superlogical's Rex** | In [public testing](https://www.superlogical.com/updates/public-testing-beginning) since 5 October 2026: a macOS app, by invitation | A stable public release has been usable daily for a real project for about 3 months, and its durable sessions don't require giving up tmux for local work | Testing is invite-only and macOS-only; anything built today would target a moving API |
| **Herdr 1.0** | `--pack herdr`, the TUI at v0.9.5. The desktop app and phone app, on herdr-core, are a second line; whether the TUI moves onto herdr-core is [still open](https://github.com/herdrdev/herdr-app/issues/63) | Already adopted as opt-in. Treat its socket API as stable once 1.0 has held for about 6 months of point releases without a breaking change | Pre-1.0 software can break its own API; the pack stays opt-in until then |
| **Apple's containerization as the Tier 1 sandbox** | On macOS 26, a lightweight VM per container. Already the first Tier 2 backend: `--pack sandbox-container` and `make container-test` try Apple's `container`, then Podman, then Docker | It has a stable CLI and a cold start fast enough for a per-command sandbox, and `bin/sbx` can wrap it with the same `strict`/`standard`/`off` contract | A VM boot per command is the wrong latency for sandboxing every agent command; Seatbelt through `sbx` stays |

**Seatbelt.** Apple's `sandbox-exec` has been marked deprecated for years and is still the only kernel-enforced sandbox macOS ships without an install. Codex's sandbox and Anthropic's `sandbox-runtime` for Claude Code both build on it on macOS (`bubblewrap` on Linux). Scripts and docs call `sbx`, never `sandbox-exec`, so a change of backend stays inside `bin/sbx` and `configs/sandbox/profiles/`.

## Why changes stay cheap

- **Everything optional is a pack:** one file, one entrypoint, found by `install.sh` ([the pack contract](engineering.md#the-pack-contract)). Adopting or dropping a tool is adding or deleting a file.
- **Managed blocks** keep your edits outside tuidev's markers through every update.
- **Migrations** repair what past releases left behind, once per machine, so a change never asks you to edit dotfiles by hand ([updating.md](updating.md#migrations)).
- **The manifest** makes uninstall remove exactly what was installed.
- **The core is CLI-agnostic:** the AI CLIs are one opt-in pack, so the core install doesn't move when a CLI is deprecated (as Gemini CLI was) or a new one appears.

This page will be wrong in places. The design above is the bet: it makes being wrong about any one prediction cheap to correct.
