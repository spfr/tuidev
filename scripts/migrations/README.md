# scripts/migrations/

One-shot fixups for machines that were installed by an older tuidev.

Managed blocks and idempotent packs converge *current* state — they cannot undo
the past. When a release renames a path, drops a helper, or changes the shape of
a state file, already-installed machines keep the old artifact forever. That is
what a migration is for.

Run by `scripts/update.sh` (`--migrations`, and as the first step of `--configs`
and `--all`); previewed by `--check` and `--dry-run`. Applied ids are recorded
one per line in `~/.config/tuidev/migrations`.

## Naming

```
scripts/migrations/YYYYMMDDHHMM_short_slug.sh
```

The UTC timestamp prefix makes lexical sort chronological, which is the order
migrations run in. The id is the filename without `.sh`.

## Contract

1. `#!/bin/bash` + `set -eo pipefail`, and source the libs you need:
   ```bash
   MIGRATION_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
   . "$MIGRATION_DIR/../lib/ui.sh"
   ```
   It runs as its own `bash` process, so it cannot leak state into the caller.
2. **Exit 0 means applied** and the id gets recorded. Any non-zero exit stops
   the whole update run and the id is *not* recorded, so the next update
   retries it. Exit non-zero only for a genuine failure — "nothing to do here"
   is a success.
3. **Check before you mutate.** The runner promises at most one run per machine;
   that is not a licence to be destructive. A migration a user invokes by hand a
   second time should be a no-op.
4. **Non-destructive.** Back up with `tuidev_backup` before removing anything a
   user could still want, and leave anything ambiguous alone (see how
   `202608310900_prune_pre2_orphans.sh` treats a non-empty `~/.local/share/mcp`).
5. **Say what you did**, via `print_success` / `print_info`. The update output is
   the only record the user sees.
6. Never call `run_cmd` expecting a dry-run preview — migrations are not invoked
   under `--dry-run` at all; the runner lists them instead.

Fresh installs never run historical migrations: `install.sh` baselines the state
file, marking everything present at install time as already applied.
