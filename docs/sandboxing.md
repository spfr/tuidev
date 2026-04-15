# Sandboxing

## Why a sandbox

Running AI coding agents (Claude Code, Codex, Gemini, OpenCode) locally means handing a non-deterministic process broad shell access to your machine. Even with permission prompts, it is easy for a confused or prompt-injected agent to read `~/.ssh`, exfiltrate a token from `~/.aws`, or reach out to an unexpected host. A sandbox is a thin, always-on safety net that constrains what the agent can do — even if the agent itself decides to misbehave.

## Tier 1 default: Seatbelt

Tier 1 is **macOS-native**, **zero-install**, and **FOSS**: we wrap Apple's built-in `sandbox-exec` (Seatbelt) with a small CLI called `sbx`. There is no daemon, no VM, no container runtime. The cost is a limitation on network filtering (see the matrix below). For stronger isolation, see the Tier 2 pointer at the end.

Claude Code and Codex already ship their own native sandboxing; `sbx` is a uniform-UX wrapper so every agent invocation goes through the same policy file, regardless of tool. The agent CLIs' own sandbox flags remain canonical for their own concerns.

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

The `cc` / `cx` / `gem` / `oc` shell functions will pick up `sbx` automatically once the zsh integration lands (added in a later phase). Today you can wrap invocations manually.

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

When per-host egress rules, kernel-namespace isolation, or a truly disposable filesystem matter, reach for the Tier 2 pack: `mactui --pack sandbox-container` (Podman machine). That's a separate opt-in install with its own lifecycle and its own docs — not duplicated here.

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
