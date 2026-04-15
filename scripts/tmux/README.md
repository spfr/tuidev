# scripts/tmux — reusable tmux layout helpers

Standalone scripts that build named tmux sessions with common pane/window
layouts. Each is safe to invoke directly; each is idempotent (attach if the
session already exists, otherwise create).

*Invoked by*: `ai` / `dev` / `work` / `agents` / ... shell wrappers in
`configs/zsh/.zshrc` (wired up in Wave 3).

## Helpers

| Script                  | Default session | Layout                                                 |
| ----------------------- | --------------- | ------------------------------------------------------ |
| `layout-work.sh`        | `$(basename PWD)` | Bare single pane                                     |
| `layout-dev.sh`         | `dev`           | nvim (55%) \| agent (25%) \| runner (20%)              |
| `layout-ai.sh`          | `ai`            | nvim (60%) + 2 stacked agent panes                     |
| `layout-ai-single.sh`   | `ai-single`     | nvim (60%) + 1 shell                                   |
| `layout-ai-triple.sh`   | `ai-triple`     | nvim (55%) + 3 stacked agent panes                     |
| `layout-fullstack.sh`   | `fullstack`     | 5 windows: code \| web \| api \| db \| logs            |
| `layout-multi.sh`       | `multi`         | 3 windows: dev (3-col) \| monitor (btop) \| git (lazygit) |
| `layout-remote.sh`      | `remote`        | nvim (70%) + shell (30%) — for narrow / high-latency links |
| `layout-agents.sh`      | `agents`        | 3 equal columns: claude \| codex \| gemini             |

## Session-name convention

Every helper takes an optional first argument:

```bash
scripts/tmux/layout-dev.sh                  # -> session "dev"
scripts/tmux/layout-dev.sh myproject        # -> session "myproject"
```

If the named session already exists, the helper re-attaches to it instead
of erroring. `layout-work.sh` defaults its name to `basename "$PWD"`.

## Dry-run

All helpers honor `DRY_RUN=true`: when set, every `tmux` command is printed
instead of executed. Useful for tests and for previewing a layout without
actually spawning a session.

```bash
DRY_RUN=true scripts/tmux/layout-agents.sh scratch
```

## Contract

- `--help` / `-h` prints a one-line usage summary.
- Exits 127 with a clear error if `tmux` isn't installed.
- All scripts pass `shellcheck --severity=warning` and `bash -n`.
- Sources `scripts/lib/ui.sh` for colored output and `run_cmd`.
