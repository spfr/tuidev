# Roadmap — 2027/2028 Readiness

*Last updated: August 2026.*

This is not a feature list. It is groundwork for a landscape that keeps
moving faster than most tools can absorb — multiplexers, sandboxing, and
fleet-scale agent orchestration are all mid-shift right now. The goal is a
repo that can adopt what wins without a rewrite, and ignore what doesn't
without regret. Where a claim below is a prediction rather than a fact, it
says so.

## a. The multiplexer landscape is splitting into layers

Three things are true at once in mid-2026:

- **tmux** is 20 years old, boring, and durable. It has no concept of agent
  state, but it does not need to — that's not its job.
- **[Herdr](https://herdr.dev/)** (`--pack herdr`, currently pre-1.0 at
  ~v0.8.x) adds the layer tmux lacks: it *knows* which pane is an agent and
  whether that agent is working, blocked, or done, exposed over a CLI and a
  local socket API. It's a second multiplexer, not a tmux replacement — see
  [`agent-workflows.md`](agent-workflows.md).
- **[Superlogical](https://www.superlogical.com/)** — a new company from
  Mitchell Hashimoto (Ghostty, HashiCorp) with Jack Pearkes, Alasdair Monk,
  and Hector Simpson — announced in July 2026. Their stated plan: a
  server-side terminal multiplexer with durable, long-lived sessions first,
  expanding toward a single system for interactive work, background jobs,
  and production — local, remote, and CI unified. Backed by Notable Capital
  and Amplify Partners; promises an open-source release during development.
  As of this writing there is **no public binary**, only a beta waitlist.

**This repo's posture:** tmux stays the durability substrate for every
profile. Herdr stays an opt-in pack — it earns its `ctrl+b` prefix (deliberately
distinct from tmux's `ctrl+a`) by solving *attention*, not *durability*.
Superlogical stays a watch-list entry with zero code committed to it. A
`--pack superlogical` is plausible once there is a public artifact that has
held up under real use — see the adopt criteria below. Until then, adding
speculative integration code against an unreleased product would mean
maintaining a moving target with no users on the other end.

## b. macOS sandboxing succession

Apple's `sandbox-exec` (Seatbelt) has been informally deprecated in Apple's
own documentation for years, yet it remains the only kernel-enforced,
zero-install sandboxing primitive macOS ships. It is also what production
tools actually use today: Codex CLI's sandboxing and Anthropic's
`sandbox-runtime` for Claude Code both build on Seatbelt on macOS (with
`bubblewrap` as the Linux equivalent). "Deprecated" here means "no new API
surface," not "about to disappear" — vendors with more leverage than this
project are still building on it in 2026.

The likely long-term successor is Apple's **containerization framework**
(the `container` CLI / `Containerization.framework` introduced for macOS 26),
which gives per-container lightweight VMs with real kernel isolation instead
of a single shared-kernel profile file. It is heavier (a VM boot per
container) and newer, which is exactly why it isn't Tier 1 yet — the
project already has a heavier tier for people who want VM isolation today:
Podman machine, via `--pack sandbox-container`.

**This repo's posture:** `bin/sbx` is the insulation layer, by design.
Scripts, wrappers, and docs never call `sandbox-exec` directly; they call
`sbx`. If Seatbelt is ever replaced as the Tier 1 backend — by Apple's
containerization framework or something else — the change is contained to
`bin/sbx` and the `.sb` profiles in `configs/sandbox/profiles/`. The
`--profile strict|standard|off` contract in `docs/sandboxing.md` should not
need to change for callers.

## c. Fleet-scale agents: three horizons, not one leap

1. **Today — worktree-per-agent.** Parallel implementors work in isolated
   git worktrees (see the `delegation` skill and `docs/engineering.md`).
   This is cheap, needs no new tooling, and is already how this repo
   recommends running more than one agent against the same codebase.
2. **Next — attention-state APIs.** Herdr's socket API
   (`herdr.dev/docs/socket-api/`) lets agents query and react to *other*
   agents' state (`working` / `blocked` / `done`) instead of polling panes
   or guessing. This is the near-term unlock: agents coordinating without a
   human relaying status between tmux panes.
3. **After — remote fleets over the existing transport.** The always-on
   Linux node pattern in [`remote.md`](remote.md) and
   [`agent-workflows.md`](agent-workflows.md) — Tailscale/SSH plus tmux or
   Herdr on a box that never sleeps — is already the shape a real fleet
   takes. Scaling it further (more nodes, more repos) is an extension of
   that pattern, not a new architecture.

None of this requires a Kubernetes-shaped rewrite. The bet is that
"SSH to a durable session, know what needs attention" scales further than
it looks like it should, precisely because it degrades gracefully — worst
case you're back to tmux and a terminal.

## d. What makes this repo change-ready

These are existing design decisions, not proposals — restated here because
they are *why* (a)–(c) above don't require rewrites:

- **Everything optional is a pack.** One file, one entrypoint
  (`<pack>_install`), self-discovered by `install.sh` — see "The pack
  contract" in [`engineering.md`](engineering.md#the-pack-contract). Adopting
  or dropping a tool is adding or deleting a file, not touching the
  installer.
- **Managed blocks keep user state separable.** `scripts/lib/config_write.sh`
  writes `~/.zshrc`, SSH config, etc. inside `# >>> tuidev managed >>>`
  fences. User edits outside the fence survive every re-run and every
  future migration.
- **Drift-detecting updates, growing toward one-shot migrations.**
  `scripts/update.sh` already separates package updates from config-drift
  detection per profile. `make migrate` exists today for the Zellij→tmux
  transition; the pattern (detect drift → offer a scripted, reversible
  migration) generalizes to future transitions instead of asking users to
  hand-edit dotfiles again.
- **Manifest-driven uninstall.** `uninstall.sh` already reads
  `~/.config/tuidev/` to know which packs and configs it owns before
  touching anything, rather than guessing from what's on disk. This is the
  same shape Omacosy uses (see [`inspiration.md`](inspiration.md)) and it's
  what makes "cleanly remove one pack" tractable as the pack count grows.
- **CLI-agnostic core.** AI CLIs (`claude`, `codex`, `opencode`) are an
  opt-in pack behind a common `sbx`-routed wrapper shape (`cc`/`cx`/`oc`).
  When a CLI is deprecated (as happened to Gemini CLI, succeeded by
  Antigravity) or a new one appears, the core install doesn't move.

## e. Watch-list: adopt / hold criteria

| Project | Status | Adopt when | Hold because |
|---|---|---|---|
| **Superlogical** | Pre-product, beta waitlist only | A public binary exists, has been usable daily for a real project for ~3 months, and its durable-session model doesn't require abandoning tmux for local work | No artifact to integrate against yet; anything built today would target a moving, undocumented API |
| **Herdr → 1.0** | `--pack herdr`, currently ~v0.8.x | Already adopted as opt-in. Treat its socket API as semi-stable once herdr ships 1.0 and it has held for ~6 months of point releases without a breaking API change | Pre-1.0 software can and does break its own API; the pack stays opt-in, not default, until then |
| **Apple containerization framework as Tier 1 sandbox** | Available on macOS 26, VM-per-container | It ships a stable CLI story with acceptable cold-start latency for a per-command sandbox, and `bin/sbx` can wrap it with the same `strict/standard/off` contract | Today it means a VM boot per invocation — wrong latency shape for "sandbox every `cc` call"; Seatbelt via `sbx` is unchanged |
| **omarchy-style executable theme/plugin pipelines** | Adopting the single-palette *pattern*, not their plugin runtime | Never wholesale — see the cautionary note in [`inspiration.md`](inspiration.md) | Executable theme/plugin systems are a supply-chain surface (see `basecamp/omarchy` discussion #5946 on hardening against exactly this); this repo's theming stays static config files, not scripts fetched and run at theme-switch time |
| **Tailcat (tailscale.com/tailcat)** | New open-source CLI: accountless, encrypted point-to-point connections — no tailnet, no login flow | An agent or CI job needs to reach a machine for one task without joining the tailnet, and tailcat has a few months of releases behind it; would slot into `--remote` as an *addition* for ephemeral peers | The remote pack's model is a persistent personal fleet — a tailnet with identity is the right shape for that; tailcat solves the adjacent problem (short-lived, accountless links), not this one |
| **In-editor ACP agents in Neovim** | Mature enough to work, still not adopted | A concrete workflow need outweighs the "AI runs in external panes" principle — unlikely to change soon | Conscious non-goal, not a capability gap — see `VISION.md` |

## Honest uncertainty

This document will be wrong in places by 2027. Herdr may reach 1.0 sooner or
later than expected; Superlogical may ship something that makes Herdr
redundant, or may pivot before shipping anything local-first at all; Apple
may ship containerization improvements that make Tier 2 obsolete faster than
this doc assumes. The design principles in section (d) are the actual bet —
they're meant to make being wrong about any one prediction cheap to correct.
