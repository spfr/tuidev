# Sandboxing

## Why a sandbox

Running AI coding agents (Claude Code, Codex, OpenCode) locally means handing a non-deterministic process broad shell access to your machine. Even with permission prompts, it is easy for a confused or prompt-injected agent to read `~/.ssh`, exfiltrate a token from `~/.aws`, or reach out to an unexpected host. A sandbox is a thin, always-on safety net that constrains what the agent can do — even if the agent itself decides to misbehave.

## Tier 1 default: Seatbelt

Tier 1 is **macOS-native**, **zero-install**, and **FOSS**: we wrap Apple's built-in `sandbox-exec` (Seatbelt) with a small CLI called `sbx`. There is no daemon, no VM, no container runtime. The cost is a limitation on network filtering (see the matrix below). For stronger isolation, see the Tier 2 pointer at the end.

Claude Code and Codex ship their own native sandboxing (Seatbelt on macOS, bubblewrap on Linux); `sbx` is a uniform-UX wrapper so every agent invocation goes through the same policy file, regardless of tool. The agent CLIs' own sandbox flags remain canonical for their own concerns.

## `sbx` vs. Claude Code's built-in sandbox — pick one

Seatbelt profiles do not nest. A process already running under `sandbox-exec` cannot apply a second profile (`sandbox_apply: Operation not permitted`), and Claude Code's built-in Bash sandbox (`/sandbox`, `sandbox.enabled` in `~/.claude/settings.json`) *is* `sandbox-exec`. So for Claude Code it is one or the other:

| | `sbx -- claude` (tuidev default) | Claude's native sandbox (`sandbox.enabled`) |
|---|---|---|
| What is confined | The whole CLI process: every tool, every child, the CLI's own file reads | Only the Bash tool and its children; `Read`/`Edit` are governed by permission rules, not the kernel |
| Credential dirs | Kernel-denied by the profile | Denied only if you list them under `sandbox.credentials` or `permissions.deny` |
| Network | Port-level only (Seatbelt limitation) | Per-domain allowlist through Claude's proxy |
| Prompts | Unchanged; Claude still asks per its permission mode | `autoAllowBashIfSandboxed` skips prompts for sandboxed commands |

The shipped `cc` wrapper resolves the conflict automatically: when `~/.claude/settings.json` has `"sandbox": {"enabled": true}` it calls `claude` directly instead of through `sbx`, so Claude's own sandbox can apply. Flip it back by disabling the native sandbox. The shipped `configs/claude/settings.json` does not enable the native sandbox; it adds `permissions.deny` rules for the same credential directories `sbx` blocks, so the `Read` tool honors the boundary even when you run `CC_NO_SANDBOX=1 cc`. Codex's `sandbox_mode = "workspace-write"` has the same nesting constraint under `cx`; Codex detects it and falls back to approval-only mode, which is the intended layering.

## Profile matrix

| Profile    | Filesystem reads       | Filesystem writes         | Network (enforced at kernel) | Use when |
|------------|------------------------|---------------------------|------------------------------|----------|
| `strict`   | `$HOME` minus creds, system, Homebrew | Project tree + `/tmp` only | TCP :443 out, DNS, loopback  | Default for agent runs. LLM API calls work; package installs don't. |
| `standard` | Same as strict         | Same as strict            | + TCP :80, :22, :9418        | Agent needs `npm ci`, `pip install`, `git push`, etc. |
| `off`      | unrestricted           | unrestricted              | unrestricted                 | Escape hatch. Trusted tool, or profiles are misbehaving. |

**Honest limitation (Tier 1 only):** Apple's Seatbelt does not support per-hostname network rules — only `*` or `localhost` at the socket layer. The "allow LLM providers, block everything else" design goal is *not* kernel-enforced at Tier 1; only port-level filtering is. If that matters, use `--pack sandbox-container` (Tier 2).

## Usage

```bash
sbx -- cc                              # Claude Code under the default (strict) profile
sbx --profile standard -- npm ci       # wider network for package installs
sbx --profile off -- some-tool         # escape hatch: no sandbox at all
sbx --project ~/code/api -- make test  # override the project dir (default: $PWD)
sbx --dry-run -- make test             # print the sandbox-exec command, don't run
sbx --help                             # full option list
```

The `cc` / `cx` / `oc` shell functions (installed by `--pack ai-clis`) auto-route through `sbx` automatically when both are on `PATH`. Without `sbx` they call the CLI directly; without the pack, wrap manually: `sbx -- claude`.

## Escape hatch

Two ways to bypass the sandbox when you need to:

```bash
sbx --profile off -- <cmd>   # explicit, one-shot
CC_NO_SANDBOX=1 cc           # honored by the agent wrappers (added in a later phase)
```

Both are documented, auditable, and leave the command running with your full host privileges. Use deliberately.

## What's locked down

Even with `strict` or `standard`, these directories are **explicitly denied** for both read and write:

```
~/.ssh
~/.aws
~/.gnupg
~/Library/Keychains
~/.config/gh
~/.docker
~/.kube
~/.netrc
```

If you need one of these (e.g., the agent legitimately needs to push via SSH), step up to `--profile off` or the Tier 2 pack for that invocation — don't poke holes in the shipped profile.

## Customizing

Drop a replacement profile at `~/.config/tuidev/sandbox/<name>.sb` and `sbx` will prefer it over the shipped copy. Lookup order (first hit wins):

1. `$TUIDEV_SANDBOX_DIR/<name>.sb` (for ad-hoc overrides)
2. `~/.config/tuidev/sandbox/<name>.sb`
3. `<repo>/configs/sandbox/profiles/<name>.sb`

The shipped profiles are deliberately verbose; copy one and edit rather than writing from scratch. Seatbelt syntax is TinyScheme; `;` is the comment character. Parameters are passed as `-D NAME=value`; the wrapper supplies `PROJECT_DIR` and `HOME_DIR` automatically.

## Tier 2 pointer

When per-host egress rules, kernel-namespace isolation, or a truly disposable filesystem matter, reach for the Tier 2 pack: `./install.sh --pack sandbox-container`. It uses whichever runtime is present, in this order: Apple's native `container` CLI (macOS 26+, Containerization.framework, one lightweight VM per container) → Podman → Docker. Force one with `TUIDEV_CONTAINER_RUNTIME`. `make sandbox-up` / `make sandbox-down` start and stop the backend regardless of which one you have.

## Troubleshooting

- **`sandbox-exec: invalid data type of path filter; expected pattern, got boolean`** — a `(param "…")` reference in the profile is unset. Make sure `sbx` is passing `-D` for every parameter the profile uses.
- **`Operation not permitted` from a tool inside the sandbox** — Seatbelt is denying a syscall. Read the system log to find the specific rule that tripped:
  ```bash
  log stream --predicate 'sender == "sandboxd"' --info --debug
  ```
  Re-run the command in another terminal and watch for the deny line; it will name the operation and path.
- **Network call mysteriously fails** — remember Tier 1 only filters by port. If a tool needs anything other than 443 (strict) or 443/80/22/9418 (standard), either widen the profile locally or switch to `--profile off` for that command.
- **Profile edits have no effect** — check the lookup order above; a stale copy in `~/.config/tuidev/sandbox/` will shadow the repo version.

## Non-goals

- **Kernel exploits:** Seatbelt is a policy layer on top of the same kernel. If the kernel is compromised, the sandbox is too.
- **Linux namespaces:** different model, different guarantees. Not covered here.
- **VM-level isolation:** that's Tier 2.
- **Keylogger / clipboard protection:** the sandbox controls the process's view of files and sockets, not input devices or the pasteboard.
