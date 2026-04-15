#!/bin/bash
# scripts/lib/config_write.sh - non-destructive config writer.
#
# Provides:
#   write_managed_block FILE BLOCK_ID CONTENT_OR_STDIN
#   install_config     DEST  SOURCE [--overwrite|--adopt-existing|--managed-block BLOCK_ID]
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

# Where --overwrite and the install.sh nvim path park their backups, and how
# many to keep. 10 covers a few months of active use without unbounded growth.
: "${TUIDEV_BACKUP_DIR:=$HOME/.config/tuidev/backups}"
: "${TUIDEV_BACKUP_KEEP:=10}"

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
    # Uses find -print0 to handle odd filenames, sorts by mtime, keeps N.
    find "$TUIDEV_BACKUP_DIR" -mindepth 1 -maxdepth 1 -name "${prefix}.*" -print0 \
        2>/dev/null |
        xargs -0 stat -f '%m %N' 2>/dev/null |
        sort -rn |
        awk -v keep="$TUIDEV_BACKUP_KEEP" 'NR>keep {sub(/^[0-9]+ /,""); print}' |
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
    local begin="# >>> tuidev managed (${block_id}) >>>"
    local end="# <<< tuidev managed (${block_id}) <<<"

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

    print_success "managed block '${block_id}' → ${file}"
}

# install_config DEST SOURCE [flags]
# Flags:
#   --managed-block ID   (default) insert SOURCE content as managed block ID
#   --overwrite          full-file replace (destructive, requires consent)
#   --adopt-existing     if DEST already exists, do not touch it
# On --overwrite, the existing DEST is backed up to ~/.config/tuidev/backups/.
install_config() {
    local dest="$1"; shift
    local source="$1"; shift
    local mode="managed-block"
    local block_id=""

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
        adopt-existing)
            if [[ -e "$dest" ]]; then
                print_info "adopt-existing: leaving $dest untouched"
            else
                if [[ "$DRY_RUN" == true ]]; then
                    print_info "[DRY RUN] would copy $source -> $dest"
                else
                    mkdir -p "$(dirname "$dest")"
                    cp "$source" "$dest"
                    print_success "installed $dest (new)"
                fi
            fi
            ;;
        overwrite)
            if [[ -e "$dest" ]]; then
                tuidev_backup "$dest" >/dev/null || true
                if [[ "$DRY_RUN" == true ]]; then
                    print_info "[DRY RUN] would overwrite $dest with $source"
                else
                    cp "$source" "$dest"
                    print_success "overwrote $dest (backup in $TUIDEV_BACKUP_DIR)"
                fi
            else
                if [[ "$DRY_RUN" == true ]]; then
                    print_info "[DRY RUN] would copy $source -> $dest"
                else
                    mkdir -p "$(dirname "$dest")"
                    cp "$source" "$dest"
                    print_success "installed $dest"
                fi
            fi
            ;;
    esac
}

# read_managed_block FILE BLOCK_ID
# Prints the block content (without markers) to stdout. Exit 0 if block is
# present, 1 if absent. Used by update.sh for drift detection — single
# source of truth for the marker format.
read_managed_block() {
    local file="$1"
    local block_id="$2"
    local begin="# >>> tuidev managed (${block_id}) >>>"
    local end="# <<< tuidev managed (${block_id}) <<<"

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
    local begin="# >>> tuidev managed (${block_id}) >>>"
    local end="# <<< tuidev managed (${block_id}) <<<"

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
}
