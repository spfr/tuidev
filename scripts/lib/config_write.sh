#!/bin/bash
# scripts/lib/config_write.sh - non-destructive config writer.
#
# Provides:
#   write_managed_block FILE BLOCK_ID CONTENT_OR_STDIN
#   read_managed_block  FILE BLOCK_ID
#   remove_managed_block FILE BLOCK_ID
#   install_config     DEST  SOURCE [--overwrite|--adopt-existing|--managed-block BLOCK_ID
#                                    |--upgrade-shipped HASHFILE [--shipped-name NAME]]
#   tuidev_is_shipped  FILE  SOURCE HASHFILE [NAME]
#   tuidev_block_begin / tuidev_block_end BLOCK_ID   the marker lines themselves
#   tuidev_backup      PATH [PREFIX]
#
# The managed-block strategy wraps repo-owned content in paired markers:
#   # >>> tuidev managed (BLOCK_ID) >>>
#   ...content...
#   # <<< tuidev managed (BLOCK_ID) <<<
# and rewrites only the region between markers on subsequent installs. User
# edits outside the block survive. A header comment points the user at the
# marker pattern so it's self-documenting.
#
# Requires scripts/lib/ui.sh sourced for print_* helpers and DRY_RUN.

if [[ -n "${_TUIDEV_CFGW_LOADED:-}" ]]; then
    return 0
fi
_TUIDEV_CFGW_LOADED=1

# shellcheck source=./ui.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/ui.sh"
# Manifest recording. A no-op unless a caller enabled it (install.sh does):
# every block and file written through this lib is recorded so uninstall can
# remove exactly what this machine got.
# shellcheck source=./manifest.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/manifest.sh"

# Where --overwrite and the install.sh nvim path park their backups, and how
# many to keep. 10 covers a few months of active use without unbounded growth.
: "${TUIDEV_BACKUP_DIR:=$TUIDEV_STATE_DIR/backups}"
: "${TUIDEV_BACKUP_KEEP:=10}"

# The marker format, defined once. Everything that reads or writes a managed
# block (this lib, update.sh's duplication checks) builds markers here.
tuidev_block_begin() { printf '# >>> tuidev managed (%s) >>>' "$1"; }
tuidev_block_end()   { printf '# <<< tuidev managed (%s) <<<' "$1"; }

# tuidev_backup PATH [PREFIX]
# Copy PATH (file or dir) into $TUIDEV_BACKUP_DIR with a timestamped name.
# After writing, retain only the most recent $TUIDEV_BACKUP_KEEP entries
# that share the same PREFIX (or basename) to bound disk growth.
#
# Echoes the backup target path on success.
tuidev_backup() {
    local src="$1"
    local prefix="${2:-$(basename "$src")}"
    [[ -e "$src" ]] || return 1

    local stamp target
    stamp="$(date +%Y%m%d-%H%M%S)"
    target="$TUIDEV_BACKUP_DIR/$prefix.$stamp"

    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY RUN] would back up $src -> $target"
        echo "$target"
        return 0
    fi

    mkdir -p "$TUIDEV_BACKUP_DIR"
    cp -R "$src" "$target"

    # Retention: drop everything past the N most-recent entries for this prefix.
    # Backup names include sortable timestamps, which keeps this portable across
    # BSD and GNU userlands without relying on incompatible stat flags.
    find "$TUIDEV_BACKUP_DIR" -mindepth 1 -maxdepth 1 -name "${prefix}.*" -print \
        2>/dev/null |
        sort -r |
        awk -v keep="$TUIDEV_BACKUP_KEEP" 'NR>keep {print}' |
        while IFS= read -r old; do
            rm -rf -- "$old"
        done

    echo "$target"
}

# write_managed_block FILE BLOCK_ID [CONTENT]
# If CONTENT is omitted, reads from stdin. Creates FILE if missing. Replaces
# the existing block with matching BLOCK_ID; appends one if absent.
write_managed_block() {
    local file="$1"
    local block_id="$2"
    local content="${3-}"
    local begin end
    begin="$(tuidev_block_begin "$block_id")"
    end="$(tuidev_block_end "$block_id")"

    [[ -z "$file" || -z "$block_id" ]] && {
        print_error "write_managed_block: FILE and BLOCK_ID required"
        return 2
    }

    if [[ -z "$content" ]]; then
        content="$(cat)"
    fi

    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY RUN] would write managed block '${block_id}' to ${file}"
        return 0
    fi

    mkdir -p "$(dirname "$file")"
    touch "$file"

    local tmp
    tmp="$(mktemp "${TMPDIR:-/tmp}/tuidev-cfgw.XXXXXX")"

    if grep -qF "$begin" "$file" 2>/dev/null; then
        # Replace existing block in place. Pass content via a sidecar file
        # because BSD awk on macOS rejects literal newlines in -v values.
        local content_file
        content_file="$(mktemp "${TMPDIR:-/tmp}/tuidev-cfgw-content.XXXXXX")"
        printf '%s' "$content" > "$content_file"
        awk -v begin="$begin" -v end="$end" -v content_file="$content_file" '
            $0 == begin {
                print
                while ((getline line < content_file) > 0) print line
                close(content_file)
                in_block=1
                next
            }
            $0 == end   { in_block=0; print; next }
            !in_block   { print }
        ' "$file" > "$tmp"
        rm -f "$content_file"
        mv "$tmp" "$file"
    else
        # Append (add leading blank line if file is non-empty and does not
        # already end in one).
        {
            cat "$file"
            if [[ -s "$file" ]] && [[ "$(tail -c1 "$file" | wc -l | tr -d ' ')" -eq 0 || "$(tail -n1 "$file")" != "" ]]; then
                echo ""
            fi
            echo "$begin"
            echo "$content"
            echo "$end"
        } > "$tmp"
        mv "$tmp" "$file"
    fi

    tuidev_manifest_record block "$block_id" "$file"
    print_success "managed block '${block_id}' → ${file}"
}

# install_config DEST SOURCE [flags]
# Flags:
#   --managed-block ID   (default) insert SOURCE content as managed block ID
#   --overwrite          full-file replace (destructive, requires consent);
#                        a no-op when DEST is already identical
#   --adopt-existing     if DEST already exists, do not touch it; only a file
#                        this call creates is recorded in the manifest
#   --upgrade-shipped HASHFILE
#                        --adopt-existing, except that a DEST byte-identical to
#                        a version tuidev shipped earlier (see tuidev_is_shipped)
#                        is ours to upgrade: it is backed up and replaced, so
#                        fixes reach existing installs. A DEST the user edited is
#                        kept, with a `diff` hint.
#   --shipped-name NAME  the HASHFILE key when the basename is ambiguous (a
#                        config tree such as nvim keys by relative path).
# On --overwrite, a differing DEST is backed up to $TUIDEV_BACKUP_DIR first.
install_config() {
    local dest="$1"; shift
    local source="$1"; shift
    local mode="managed-block"
    local block_id="" hash_file="" shipped_name=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --managed-block)
                mode="managed-block"
                block_id="$2"
                shift 2
                ;;
            --overwrite)
                mode="overwrite"
                shift
                ;;
            --adopt-existing)
                mode="adopt-existing"
                shift
                ;;
            --upgrade-shipped)
                mode="upgrade-shipped"
                hash_file="$2"
                shift 2
                ;;
            --shipped-name)
                shipped_name="$2"
                shift 2
                ;;
            *)
                print_error "install_config: unknown flag $1"
                return 2
                ;;
        esac
    done

    [[ -f "$source" ]] || { print_error "install_config: source missing: $source"; return 2; }

    case "$mode" in
        managed-block)
            [[ -z "$block_id" ]] && { print_error "install_config: --managed-block needs ID"; return 2; }
            write_managed_block "$dest" "$block_id" "$(cat "$source")"
            ;;
        upgrade-shipped)
            [[ -z "$hash_file" ]] && { print_error "install_config: --upgrade-shipped needs HASHFILE"; return 2; }
            if [[ ! -e "$dest" ]]; then
                install_config "$dest" "$source" --adopt-existing
            elif [[ -f "$dest" ]] && cmp -s "$dest" "$source"; then
                # Identical to what we ship: ours, so record it (this also
                # rebuilds records on installs that predate the manifest).
                tuidev_manifest_record file "$dest"
                print_success "$dest (up to date)"
            elif tuidev_is_shipped "$dest" "$source" "$hash_file" "$shipped_name"; then
                install_config "$dest" "$source" --overwrite
            else
                print_info "keeping your edited $dest (compare: diff $dest $source)"
            fi
            ;;
        adopt-existing)
            if [[ -e "$dest" ]]; then
                print_info "adopt-existing: leaving $dest untouched"
            else
                if [[ "$DRY_RUN" == true ]]; then
                    print_info "[DRY RUN] would copy $source -> $dest"
                else
                    mkdir -p "$(dirname "$dest")"
                    cp "$source" "$dest"
                    tuidev_manifest_record file "$dest"
                    print_success "installed $dest (new)"
                fi
            fi
            ;;
        overwrite)
            if [[ -f "$dest" ]] && cmp -s "$source" "$dest"; then
                # Identical: nothing to back up or copy. Still recorded, so a
                # re-run rebuilds a lost manifest.
                tuidev_manifest_record file "$dest"
                print_success "$dest (up to date)"
            elif [[ -e "$dest" ]]; then
                tuidev_backup "$dest" >/dev/null || true
                if [[ "$DRY_RUN" == true ]]; then
                    print_info "[DRY RUN] would overwrite $dest with $source"
                else
                    cp "$source" "$dest"
                    tuidev_manifest_record file "$dest"
                    print_success "overwrote $dest (backup in $TUIDEV_BACKUP_DIR)"
                fi
            else
                if [[ "$DRY_RUN" == true ]]; then
                    print_info "[DRY RUN] would copy $source -> $dest"
                else
                    mkdir -p "$(dirname "$dest")"
                    cp "$source" "$dest"
                    tuidev_manifest_record file "$dest"
                    print_success "installed $dest"
                fi
            fi
            ;;
    esac
}

# tuidev_is_shipped FILE SOURCE HASHFILE [NAME]
# True when FILE is byte-identical to some version of SOURCE that tuidev has
# shipped. HASHFILE holds `<name> <sha256>` lines (`#` comments allowed), one
# per version ever released, where <name> is NAME if given, else SOURCE's
# basename without its extension (strict.sb -> strict, settings.json ->
# settings). Keying by name keeps a copy of one shipped file from "upgrading"
# into another.
tuidev_is_shipped() {
    local file="$1" source="$2" hash_file="$3" name="${4:-}"
    [[ -f "$file" && -f "$hash_file" ]] || return 1
    if [[ -z "$name" ]]; then
        name="$(basename "$source")"
        name="${name%.*}"
    fi
    grep -qx "$name $(file_sha256 "$file")" "$hash_file"
}

# read_managed_block FILE BLOCK_ID
# Prints the block content (without markers) to stdout. Exit 0 if block is
# present, 1 if absent. Used by update.sh for drift detection — single
# source of truth for the marker format.
read_managed_block() {
    local file="$1"
    local block_id="$2"
    local begin end
    begin="$(tuidev_block_begin "$block_id")"
    end="$(tuidev_block_end "$block_id")"

    [[ -f "$file" ]] || return 1
    grep -qF "$begin" "$file" 2>/dev/null || return 1

    awk -v begin="$begin" -v end="$end" '
        $0 == begin { in_block=1; next }
        $0 == end   { in_block=0; next }
        in_block    { print }
    ' "$file"
}

# remove_managed_block FILE BLOCK_ID
# Removes the block (and its markers) if present. No-op if absent.
remove_managed_block() {
    local file="$1"
    local block_id="$2"
    local begin end
    begin="$(tuidev_block_begin "$block_id")"
    end="$(tuidev_block_end "$block_id")"

    [[ -f "$file" ]] || return 0
    grep -qF "$begin" "$file" 2>/dev/null || return 0

    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY RUN] would remove managed block '${block_id}' from ${file}"
        return 0
    fi

    local tmp
    tmp="$(mktemp "${TMPDIR:-/tmp}/tuidev-cfgw.XXXXXX")"
    awk -v begin="$begin" -v end="$end" '
        $0 == begin { in_block=1; next }
        $0 == end   { in_block=0; next }
        !in_block   { print }
    ' "$file" > "$tmp"
    mv "$tmp" "$file"
    print_success "removed managed block '${block_id}' from ${file}"
    # Nothing but our block was in it: drop the now-empty file.
    if ! grep -q '[^[:space:]]' "$file"; then
        rm -f "$file"
        print_info "removed ${file} (only held the tuidev block)"
    fi
}
