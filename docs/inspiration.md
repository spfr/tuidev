# Inspiration and non-goals

Practices this setup *steals*, and desktop systems it *refuses*. Personal
hosts, usernames, and LAN names do not belong in this file — they live in
gitignored `*.local` overlays (`~/.zshrc.local`, `~/.ssh/config.local`).

## Steal

From [Omarchy](https://omarchy.org) (DHH / omacom, now on v4 "Quattro") and
[Omacosy](https://github.com/paulsp94/omacosy):

- **Small core, explicit packs.** If a tool is not essential, it is `--pack NAME`
  or `--extras`, not the default install.
- **One theme, one palette contract.** Tokyo Night across terminal, editor,
  multiplexer, and prompt. Herdr's shipped snippet uses `tokyo-night` when you
  add `--pack herdr`. **Adopted, in progress:** a single-palette theming
  pipeline (one source of truth, generated per-tool config) modeled on
  Omarchy's, and **planned:** versioned, one-shot theme migrations instead of
  hand-edited config diffs — see [`roadmap.md`](roadmap.md#d-what-makes-this-repo-change-ready).
  Omacosy's multi-theme-on-shared-palette-contract (several palettes, one
  interface) is a watch, not yet adopted — this repo ships one theme by design.
- **No telemetry.** Installers and configs in this repo do not phone home.
- **Idempotent install.** Re-run is safe; user edits outside managed blocks
  survive.
- **Manifest-driven uninstall.** Already adopted, following Omacosy's
  approach: `uninstall.sh` reads `~/.config/tuidev/` to know exactly which
  packs and configs it owns before touching the host, rather than guessing
  from what happens to be on disk.

**Cautionary note, not adopted:** Omarchy's theme/plugin system is
executable — themes and plugins can run code at switch time. That is a
supply-chain surface (see the community hardening discussion at
[`basecamp/omarchy#5946`](https://github.com/basecamp/omarchy/discussions/5946)),
and it is why this repo's theming stays static config files distributed with
the repo itself, never scripts fetched or executed at theme-switch time.

Those are *practices*. This is still a terminal-first macOS TUI, not a
Linux distro and not a macOS desktop environment.

## Refuse

- **Omarchy as a product** — Hyprland, a full Arch desktop, distro installer.
  Wrong OS, wrong layer.
- **Omacosy / AeroSpace / Karabiner-as-root** — tiling WM, Super-key remap,
  Accessibility + Input Monitoring + a root DriverKit extension. That is a
  desktop-environment experiment (and Omacosy is pre-1.0 / macOS 26-only).
  This repo's `ui` pack stays lean: Ghostty, Rectangle, Stats, Maccy, Hidden
  Bar, Hammerspoon.
- **Kitchen-sink CLI lists.** Performance comes from Ghostty, a short Rust
  core (`rg`, `fd`, `eza`, `bat`, …), and a *runtime that knows agent state*
  — not from another `ls` replacement.
- **In-editor ACP agents.** AI stays in external panes. See [`VISION.md`](../VISION.md).

## Personal vs published

This repository is public. Clone-and-trust means:

| Belongs in git | Belongs in `*.local` only |
|----------------|---------------------------|
| `ssh user@devbox` | Real mDNS names, Tailscale IPs, account names |
| `herdr --remote workbox` | `Host` stanzas for your LAN |
| `Host always-on` (commented example) | `~/.ssh/config.local` (never shipped) |
| Hardware *class* ("a Raspberry Pi or NUC") | Your board, hostname, or username |

The shipped SSH snippet `Include`s `~/.ssh/config.local*` (glob so a missing
file is ignored). Put personal `Host` lines there, or outside the tuidev
managed block in `~/.ssh/config`.
Shell aliases go in `~/.zshrc.local`. CI `check-paths` fails on hardcoded
home-directory user paths and mDNS `user@` + hostname forms in published trees.

## Lessons from OpenClaw 2.0

OpenClaw's 2.0 rework is a useful case study in *how* a growing pack count
stays maintainable, not a source of packs to import:

- **Progressive complexity.** A first install should look like a small,
  obvious tool; depth (packs, profiles, sandbox tiers) should be discoverable,
  not front-loaded onto a new user.
- **CI rigor scales with pack count, not with project age.** Every new
  optional pack is a new thing that can silently rot; the answer is more CI
  surface per pack (lint, config validation, required-files checks), not
  fewer packs.
- **Agents orchestrate existing tools; they do not replace them.** The
  right layer for "an agent drives tmux/Herdr/git" is orchestration on top of
  those tools' existing interfaces (sockets, CLIs), not a bespoke automation
  layer that reimplements what tmux or Herdr already do. This is the same
  reasoning behind `bin/sbx` wrapping `sandbox-exec` instead of replacing it.

## Horizon

[Superlogical](https://www.superlogical.com/) is the 2027–28 watch: a
durable session around interactive work, agents, jobs, and production,
founded by Mitchell Hashimoto (Ghostty, HashiCorp) with Jack Pearkes,
Alasdair Monk, and Hector Simpson, announced July 2026. No pack until a
public beta exists. Until then the stack is tmux (durability) + Herdr
(fleet attention). See [`agent-workflows.md`](agent-workflows.md) and the
fuller adopt/hold criteria in [`roadmap.md`](roadmap.md#e-watch-list-adopt--hold-criteria).
