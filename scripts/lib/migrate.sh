#!/bin/bash
# scripts/lib/migrate.sh - versioned one-shot migrations.
#
# Source after ui.sh. Idempotent; safe to source multiple times.
#
#   . "$(dirname "${BASH_SOURCE[0]}")/ui.sh"
#   . "$(dirname "${BASH_SOURCE[0]}")/migrate.sh"
#
# Why this exists: managed blocks and pack re-runs converge *current* state,
# but they cannot undo the past. When a release renames a path, drops a helper,
# or changes a state file's shape, every already-installed machine keeps the old
# artifact forever. A migration is the one-shot fixup for exactly that.
#
# Contract
# --------
# * A migration is `scripts/migrations/<UTC stamp>_<slug>.sh`, where the stamp
#   is `YYYYMMDDHHMM` — e.g. `202608310900_prune_pre2_orphans.sh`. Lexical sort
#   is chronological order, which is the order they run in.
# * Its id is the filename without `.sh`. Applied ids are appended one per line
#   to ~/.config/tuidev/migrations.
# * It runs at most once per machine. It should still be written to be safe if
#   re-run by hand (check before you mutate) — "at most once" is a promise about
#   the runner, not a licence to be destructive.
# * It is executed with `bash <file>` in its own process, so it cannot leak
#   state into the caller. It sources the libs it needs itself.
# * Exit 0 means applied — the id is recorded. Any non-zero exit stops the whole
#   run and the id is NOT recorded, so the next update retries it.
# * It must be non-destructive: back up (tuidev_backup) before removing
#   anything a user could conceivably still want.
#
# Migrations never run under --dry-run; the runner lists them instead.

if [[ -n "${_TUIDEV_MIGRATE_LOADED:-}" ]]; then
    return 0
fi
_TUIDEV_MIGRATE_LOADED=1

# shellcheck source=./ui.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/ui.sh"

_TUIDEV_MIGRATE_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

: "${TUIDEV_MIGRATIONS_DIR:=$(dirname "$_TUIDEV_MIGRATE_LIB_DIR")/migrations}"
# $HOME/.config literally, not ${XDG_CONFIG_HOME:-...}: every other tuidev
# state path (profile, manifest, env, backups) is hardcoded there, and honoring
# XDG only here makes an installed machine read as fresh when the two diverge.
: "${TUIDEV_MIGRATIONS_STATE:=$HOME/.config/tuidev/migrations}"

# tuidev_migration_id PATH — filename without directory or .sh suffix.
tuidev_migration_id() {
    local base
    base="$(basename "$1")"
    printf '%s\n' "${base%.sh}"
}

# tuidev_migration_applied ID — exit 0 if already recorded on this machine.
tuidev_migration_applied() {
    [[ -f "$TUIDEV_MIGRATIONS_STATE" ]] || return 1
    grep -qxF -- "$1" "$TUIDEV_MIGRATIONS_STATE"
}

# tuidev_migration_mark ID — record ID as applied. Honors DRY_RUN.
tuidev_migration_mark() {
    local id="$1"
    [[ -n "$id" ]] || return 2
    [[ "$DRY_RUN" == true ]] && return 0
    tuidev_migration_applied "$id" && return 0

    local dir
    dir="$(dirname "$TUIDEV_MIGRATIONS_STATE")"
    mkdir -p "$dir" || return 1
    printf '%s\n' "$id" >> "$TUIDEV_MIGRATIONS_STATE"
}

# tuidev_migrations_all — every migration file path, chronological.
# `sort` on the timestamp-prefixed names is the ordering guarantee; ls glob
# order is not relied on. Silent when the directory is absent.
tuidev_migrations_all() {
    [[ -d "$TUIDEV_MIGRATIONS_DIR" ]] || return 0
    find "$TUIDEV_MIGRATIONS_DIR" -maxdepth 1 -type f -name '[0-9]*_*.sh' 2>/dev/null | sort
}

# tuidev_migrations_pending — ids of migrations not yet applied, in run order.
tuidev_migrations_pending() {
    local f id
    while IFS= read -r f; do
        [[ -n "$f" ]] || continue
        id="$(tuidev_migration_id "$f")"
        tuidev_migration_applied "$id" || printf '%s\n' "$id"
    done < <(tuidev_migrations_all)
}

# tuidev_is_fresh_install [STATE_DIR]
# Exit 0 when this machine has never had tuidev installed.
#
# MUST be called before anything writes to the state dir: install.sh rewrites
# the profile manifest on every run, so by the end of a run it always exists and
# is worthless as evidence.
#
# The migrations state file alone is NOT a sufficient signal. Every install
# predating the migration framework lacks it, so keying off it would classify
# real upgrades as fresh machines and baseline away the very fixups they need —
# `./install.sh --pack foo` on a year-old install is the common upgrade path.
# An existing profile or manifest is proof the machine was installed to before.
tuidev_is_fresh_install() {
    local dir="${1:-$HOME/.config/tuidev}"
    if [[ -f "$dir/profile" || -f "$dir/manifest" || -f "$TUIDEV_MIGRATIONS_STATE" ]]; then
        return 1
    fi
    return 0
}

# tuidev_migrations_baseline
# Marks every current migration as applied WITHOUT running it. For a brand-new
# install: the machine has no legacy state, so historical fixups are noise.
# Gate this on tuidev_is_fresh_install, never on the state file alone.
tuidev_migrations_baseline() {
    [[ -f "$TUIDEV_MIGRATIONS_STATE" ]] && return 0
    local f count=0
    while IFS= read -r f; do
        [[ -n "$f" ]] || continue
        tuidev_migration_mark "$(tuidev_migration_id "$f")"
        count=$((count + 1))
    done < <(tuidev_migrations_all)
    [[ "$DRY_RUN" == true ]] || printf '%s\n' "$count"
}

# tuidev_run_migrations [--list]
# Runs every pending migration in order. --list (or DRY_RUN) prints what would
# run and changes nothing. Returns 1 if a migration failed — the caller should
# stop; the failed id stays unrecorded so the next run retries it.
tuidev_run_migrations() {
    local list_only=false
    [[ "${1:-}" == "--list" ]] && list_only=true
    [[ "$DRY_RUN" == true ]] && list_only=true

    local pending
    pending="$(tuidev_migrations_pending)"

    if [[ -z "$pending" ]]; then
        print_success "no pending migrations"
        return 0
    fi

    local count
    count="$(printf '%s\n' "$pending" | wc -l | tr -d ' ')"

    if $list_only; then
        print_info "$count pending migration(s) would run:"
        printf '%s\n' "$pending" | sed 's/^/      • /'
        return 0
    fi

    local id file
    while IFS= read -r id; do
        [[ -n "$id" ]] || continue
        file="$TUIDEV_MIGRATIONS_DIR/$id.sh"
        print_step "migration $id"
        if TUIDEV_MIGRATION_ID="$id" bash "$file"; then
            tuidev_migration_mark "$id"
            print_success "migration $id applied"
        else
            print_error "migration $id FAILED — stopping"
            print_info  "  not recorded as applied; it will be retried on the next update"
            print_info  "  inspect: $file"
            return 1
        fi
    done <<EOF
$pending
EOF
}
