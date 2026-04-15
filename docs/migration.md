# Migration Guide: Zellij-to-tmux Inversion

## What Changed

The `ai`, `dev`, `work`, `fullstack`, `multi`, `remote`, `ai-single`, and `ai-triple` shell functions now launch tmux. Zellij moved to the `z*` namespace and is opt-in behind `--pack zellij`. The previous `t*` tmux wrappers (`tdev`, `tai`, `tai-triple`, `ta`) are retained as aliases for now but the bare names are the canonical path. See [`VISION.md`](../VISION.md) §"Multiplexer Strategy".

## Command Rename Table

| Old (Zellij)  | New (tmux)   |
|---------------|--------------|
| `ai`          | `ai`         |
| `ai-single`   | `ai-single`  |
| `ai-triple`   | `ai-triple`  |
| `dev`         | `dev`        |
| `work`        | `work`       |
| `fullstack`   | `fullstack`  |
| `multi`       | `multi`      |
| `remote`      | `remote`     |

The names are unchanged. The backend is different. If you want the Zellij behavior back, use the `z*` forms:

| tmux (default) | Zellij (opt-in) |
|----------------|-----------------|
| `ai`           | `zai`           |
| `ai-single`    | `zai-single`    |
| `ai-triple`    | `zai-triple`    |
| `dev`          | `zdev`          |
| `work`         | `zwork`         |
| `fullstack`    | `zfullstack`    |
| `multi`        | `zmulti`        |
| `remote`       | `zremote`       |

## If You Want Zellij Back

```bash
./install.sh --pack zellij
```

The `z*` wrappers are defined unconditionally in `~/.zshrc` but short-circuit with a helpful message if Zellij is absent.

## Config File Changes

Managed blocks replace full-file overwrites. Each managed section is delimited:

```
# >>> tuidev managed (tuidev-zshrc) >>>
...generated content...
# <<< tuidev managed (tuidev-zshrc) <<<
```

Affected files (and their block IDs):

- `~/.zshrc` — `tuidev-zshrc`
- `~/.config/starship.toml` — `tuidev-starship`
- `~/.config/tmux/tmux.conf` — `tuidev-tmux`

Your hand-edits outside the managed blocks are preserved across updates.

`~/.config/nvim` is no longer `rm -rf`'d. The installer now backs it up to a timestamped directory before writing.

## What to Do on First Update

```bash
make update
```

This diffs every managed block, lists which ones drifted, and prompts once to re-apply them together. Run `./scripts/update.sh --configs --check` first for a read-only preview if you want to inspect the diffs before accepting.

If your existing dotfiles predate the managed-block format, the update reports them as "legacy, no block" and prompts you to run:

```bash
make adopt
```

## Where the Backups Go

```
~/.config/tuidev/backups/YYYY-MM-DD-HHMMSS/
```

Every pre-change copy lands there with the original path preserved under the timestamp directory. Safe to delete once you've confirmed the update stuck.

## Zellij Configs Are Not Deleted

`configs/zellij/` stays in the repo and ships under `--pack zellij`. Your layouts (`dev.kdl`, `dual.kdl`, `triple.kdl`, `multi-agent.kdl`, `fullstack.kdl`, `remote.kdl`) continue to work when the pack is installed. Nothing is being removed; the default is being changed.
