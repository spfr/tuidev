#!/bin/bash
# scripts/lib/config_write.sh - non-destructive config writer.
#
# Provides:
#   write_managed_block FILE BLOCK_ID CONTENT_OR_STDIN
#   read_managed_block  FILE BLOCK_ID
#   remove_managed_block FILE BLOCK_ID
#   install_config     DEST  SOURCE [--overwrite|--adopt-existing|--managed-block BLOCK_ID
#                                    |--upgrade-shipped HASHFILE [--shipped-name NAME]
#                                                                [--merge-json]]
#   tuidev_is_shipped  FILE  SOURCE HASHFILE [NAME]
#   tuidev_json_merge3           BASE OURS THEIRS   merged JSON, pretty-printed
#   tuidev_json_merge3_conflicts BASE OURS THEIRS   paths where OURS was kept
#                                                   over a new THEIRS value
#   tuidev_block_begin / tuidev_block_end BLOCK_ID [FILE]   the marker lines themselves
#   tuidev_backup      PATH [PREFIX]
#
# The managed-block strategy wraps repo-owned content in paired markers:
#   # >>> tuidev managed (BLOCK_ID) >>>
#   ...content...
#   # <<< tuidev managed (BLOCK_ID) <<<
# (in Markdown, `<!-- >>> tuidev managed (BLOCK_ID) >>> -->`, since a `#` line
# there is a heading the agent reads) and rewrites only the region between
# markers on subsequent installs. User
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
# block (this lib, update.sh's duplication checks) builds markers here. FILE,
# when given, picks the comment syntax: HTML comments for *.md, `#` otherwise.
tuidev_block_begin() {
    case "${2-}" in
        *.md) printf '<!-- >>> tuidev managed (%s) >>> -->' "$1" ;;
        *)    printf '# >>> tuidev managed (%s) >>>' "$1" ;;
    esac
}
tuidev_block_end() {
    case "${2-}" in
        *.md) printf '<!-- <<< tuidev managed (%s) <<< -->' "$1" ;;
        *)    printf '# <<< tuidev managed (%s) <<<' "$1" ;;
    esac
}

# tuidev_backup PATH [PREFIX]
# Copy PATH (file or dir) into $TUIDEV_BACKUP_DIR with a timestamped name.
# After writing, retain only the most recent $TUIDEV_BACKUP_KEEP entries
# that share the same PREFIX (or basename) to bound disk growth.
#
# A file is copied by content (a symlink is followed, so the backup is a real
# copy even when PATH is a dotfiles link), keeping its mode; a directory is
# copied as a tree with `cp -R`.
#
# Echoes the backup target path on success. On failure, echoes nothing and
# returns non-zero.
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

    mkdir -p "$TUIDEV_BACKUP_DIR" || return 1
    if [[ -f "$src" ]]; then
        # -L: follow a symlink; -p: keep the mode (and times).
        cp -L -p "$src" "$target" || { rm -f "$target"; return 1; }
    else
        cp -R "$src" "$target" || { rm -rf "$target"; return 1; }
    fi

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
    begin="$(tuidev_block_begin "$block_id" "$file")"
    end="$(tuidev_block_end "$block_id" "$file")"

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
#   --merge-json         (with --upgrade-shipped, JSON only) a DEST the user
#                        edited is three-way merged instead of kept as is:
#                        base = the SOURCE last applied, stored at
#                        $TUIDEV_STATE_DIR/shipped/NAME.json (`{}` before the
#                        first merge, so only additions arrive), ours = DEST,
#                        theirs = SOURCE. See tuidev_json_merge3. Where both
#                        sides changed a value, the user's wins and the path is
#                        reported. DEST is backed up before it is rewritten.
#                        Invalid JSON or no jq: kept as is, with a warning.
# On --overwrite, a differing DEST is backed up to $TUIDEV_BACKUP_DIR first.
install_config() {
    local dest="$1"; shift
    local source="$1"; shift
    local mode="managed-block"
    local block_id="" hash_file="" shipped_name="" merge_json=false

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
            --merge-json)
                merge_json=true
                shift
                ;;
            *)
                print_error "install_config: unknown flag $1"
                return 2
                ;;
        esac
    done

    [[ -f "$source" ]] || { print_error "install_config: source missing: $source"; return 2; }
    if [[ "$merge_json" == true && "$mode" != upgrade-shipped ]]; then
        print_error "install_config: --merge-json needs --upgrade-shipped"
        return 2
    fi

    case "$mode" in
        managed-block)
            [[ -z "$block_id" ]] && { print_error "install_config: --managed-block needs ID"; return 2; }
            write_managed_block "$dest" "$block_id" "$(cat "$source")"
            ;;
        upgrade-shipped)
            [[ -z "$hash_file" ]] && { print_error "install_config: --upgrade-shipped needs HASHFILE"; return 2; }
            # With --merge-json, the SOURCE last applied is kept as the base
            # of the next three-way merge.
            local base=""
            [[ "$merge_json" == true ]] && base="$(_tuidev_shipped_base "$source" "$shipped_name")"
            if [[ ! -e "$dest" ]]; then
                install_config "$dest" "$source" --adopt-existing
            elif [[ -f "$dest" ]] && cmp -s "$dest" "$source"; then
                # Identical to what we ship: ours, so record it (this also
                # rebuilds records on installs that predate the manifest).
                tuidev_manifest_record file "$dest"
                print_success "$dest (up to date)"
            elif tuidev_is_shipped "$dest" "$source" "$hash_file" "$shipped_name"; then
                install_config "$dest" "$source" --overwrite
            elif [[ "$merge_json" == true ]]; then
                _tuidev_merge_json "$dest" "$source" "$base"
                return
            else
                print_info "keeping your edited $dest (compare: diff $dest $source)"
            fi
            [[ -z "$base" ]] || _tuidev_store_base "$source" "$base"
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
                if ! tuidev_backup "$dest" >/dev/null; then
                    print_warning "could not back up $dest: left as it is"
                    return 0
                fi
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

# ---------------------------------------------------------------------------
# Three-way JSON merge (install_config --upgrade-shipped --merge-json)
# ---------------------------------------------------------------------------

# The merge as one jq program (jq 1.6+). Every value travels wrapped: [] is
# "absent", [v] is "present, with value v" (--slurpfile hands files over that
# way), so a deleted key is told apart from a null one. Recursively, with
# base B, ours O (the user's file) and theirs T (the shipped file):
#   O == B               -> T  (the user never touched it: follow upstream,
#                               including dropping a key upstream removed)
#   T == B, or O == T    -> O  (upstream never touched it: the user's value,
#                               including a key the user deleted)
#   both objects         -> per key over the union: O's keys in O's order,
#                           then T's new ones
#   both arrays          -> O in order, minus entries upstream removed (in B,
#                           not in T), plus T's entries neither in B nor in
#                           O, appended. Whole elements compare with jq
#                           equality, so hook objects work.
#   anything else        -> O, and the path is a conflict (both sides changed
#                           it differently; the user's value is kept)
# $mode: "merged" prints the result; "conflicts" prints one conflict path per
# line; "changed" prints the paths (two levels deep) where the result differs
# from OURS, one per line.
# shellcheck disable=SC2016  # $vars below are jq's, not the shell's
_TUIDEV_JSON_MERGE3_JQ='
def present: length > 0;
def isobj: present and (.[0] | type) == "object";
def isarr: present and (.[0] | type) == "array";
def sub($k): if isobj and (.[0] | has($k)) then [.[0][$k]] else [] end;
def union_keys($a; $b): ($a | keys_unsorted) + (($b | keys_unsorted) - ($a | keys_unsorted));
def m3($p; $b; $o; $t):
  if $o == $b then {v: $t, c: []}
  elif $t == $b or $o == $t then {v: $o, c: []}
  elif ($o | isobj) and ($t | isobj) then
    reduce union_keys($o[0]; $t[0])[] as $k ({v: {}, c: []};
      m3($p + [$k]; $b | sub($k); $o | sub($k); $t | sub($k)) as $r
      | .c += $r.c
      | if ($r.v | present) then .v += {($k): $r.v[0]} else . end)
    | .v |= [.]
  elif ($o | isarr) and ($t | isarr) then
    (if ($b | isarr) then $b[0] else [] end) as $ba
    | $t[0] as $ta
    | [$o[0][] | . as $x
        | select((any($ba[]; . == $x) and (any($ta[]; . == $x) | not)) | not)]
    | reduce $ta[] as $x (.;
        if any($ba[]; . == $x) or any(.[]; . == $x) then . else . + [$x] end)
    | {v: [.], c: []}
  else {v: $o, c: [$p]}
  end;
def pathstr: if length == 0 then "(top level)" else map(tostring) | join(".") end;
def diffkeys($a; $b):
  union_keys($a; $b)[] as $k
  | select(($a | has($k)) != ($b | has($k)) or $a[$k] != $b[$k]) | $k;
m3([]; $base; $ours; $theirs) as $r
| if $mode == "merged" then $r.v[0]
  elif $mode == "conflicts" then $r.c[] | pathstr
  else
    $ours[0] as $o | $r.v[0] as $m
    | if $o == $m then empty
      elif ($o | type) == "object" and ($m | type) == "object" then
        diffkeys($o; $m) as $k
        | if ($o[$k] | type) == "object" and ($m[$k] | type) == "object"
          then "\($k).\(diffkeys($o[$k]; $m[$k]))"
          else $k end
      else "(top level)" end
  end
'

# _tuidev_json_merge3_run MODE BASE OURS THEIRS
# A BASE that is empty or missing stands for `{}`. $raw is deliberately
# unquoted: empty for "merged" (JSON out), -r for the path listings.
# shellcheck disable=SC2086
_tuidev_json_merge3_run() {
    local mode="$1" base="$2" ours="$3" theirs="$4" raw=-r
    [[ "$mode" == merged ]] && raw=""
    if [[ -n "$base" && -f "$base" ]]; then
        jq -n $raw --arg mode "$mode" --slurpfile base "$base" \
            --slurpfile ours "$ours" --slurpfile theirs "$theirs" "$_TUIDEV_JSON_MERGE3_JQ"
    else
        jq -n $raw --arg mode "$mode" --argjson base '[{}]' \
            --slurpfile ours "$ours" --slurpfile theirs "$theirs" "$_TUIDEV_JSON_MERGE3_JQ"
    fi
}

# tuidev_json_merge3 BASE OURS THEIRS
# Print the three-way merge of the JSON files OURS and THEIRS against BASE,
# pretty-printed (2-space indent). BASE may be missing: `{}` then, so THEIRS
# only adds keys and list entries and nothing of OURS changes or goes.
tuidev_json_merge3() { _tuidev_json_merge3_run merged "$@"; }

# tuidev_json_merge3_conflicts BASE OURS THEIRS
# Print, one per line, the dotted paths where both sides changed a value
# differently and the merge kept OURS.
tuidev_json_merge3_conflicts() { _tuidev_json_merge3_run conflicts "$@"; }

# _tuidev_json_valid FILE — true when FILE holds exactly one JSON value.
_tuidev_json_valid() {
    [[ -f "$1" ]] && jq -e -s 'length == 1' "$1" >/dev/null 2>&1
}

# _tuidev_shipped_base SOURCE [NAME] — where the base of SOURCE's merge lives.
# NAME defaults to SOURCE's basename without its extension, as in
# tuidev_is_shipped.
_tuidev_shipped_base() {
    local name="${2:-}"
    if [[ -z "$name" ]]; then
        name="$(basename "$1")"
        name="${name%.*}"
    fi
    printf '%s/shipped/%s.json\n' "$TUIDEV_STATE_DIR" "$name"
}

# _tuidev_store_base SOURCE BASE — remember SOURCE as the version applied.
# tuidev's own state (uninstall.sh clears $TUIDEV_STATE_DIR), so no manifest
# record. A no-op under --dry-run.
_tuidev_store_base() {
    [[ "$DRY_RUN" == true ]] && return 0
    { mkdir -p "$(dirname "$2")" && cp "$1" "$2"; } \
        || print_warning "could not record the shipped version at $2 (the next update merges additions only)"
}

# _tuidev_join_lines — stdin lines joined with ", ".
_tuidev_join_lines() {
    awk 'NR > 1 { printf ", " } { printf "%s", $0 } END { if (NR) print "" }'
}

# _tuidev_merge_json DEST SOURCE BASE
# The user-edited case of --merge-json: merge SOURCE's changes since BASE into
# DEST. Anything unexpected keeps DEST as it is, with a warning.
_tuidev_merge_json() {
    local dest="$1" source="$2" base="$3"
    local hint="compare: diff $dest $source"

    if ! command_exists jq; then
        print_warning "jq not found: keeping your edited $dest as it is ($hint)"
        return 0
    fi
    if ! _tuidev_json_valid "$dest"; then
        print_warning "$dest is not valid JSON: keeping it as it is ($hint)"
        return 0
    fi
    if ! _tuidev_json_valid "$source"; then
        print_warning "$source is not valid JSON: keeping your $dest as it is"
        return 0
    fi
    local note=""
    if [[ ! -f "$base" ]]; then
        note=" (first merge: additions only)"
    elif ! _tuidev_json_valid "$base"; then
        print_warning "$base is not valid JSON: merging additions only"
        base=""
        note=" (additions only)"
    fi

    local tmp changed conflicts
    tmp="$(mktemp "${TMPDIR:-/tmp}/tuidev-merge.XXXXXX")" || {
        print_warning "could not create a temp file: keeping your $dest as it is ($hint)"
        return 0
    }
    if ! tuidev_json_merge3 "$base" "$dest" "$source" > "$tmp" \
        || ! changed="$(_tuidev_json_merge3_run changed "$base" "$dest" "$source" | _tuidev_join_lines)" \
        || ! conflicts="$(tuidev_json_merge3_conflicts "$base" "$dest" "$source" | _tuidev_join_lines)" \
        || ! _tuidev_json_valid "$tmp"; then
        rm -f "$tmp"
        print_warning "could not merge into $dest: keeping it as it is ($hint)"
        return 0
    fi

    if [[ -z "$changed" ]]; then
        rm -f "$tmp"
        print_success "$dest (up to date, your edits kept)"
    elif [[ "$DRY_RUN" == true ]]; then
        rm -f "$tmp"
        print_info "[DRY RUN] would back up $dest and merge in tuidev's changes$note: $changed"
    else
        if ! tuidev_backup "$dest" >/dev/null; then
            rm -f "$tmp"
            print_warning "could not back up $dest: left as it was, nothing merged ($hint)"
            return 0
        fi
        # cp writes through a symlinked DEST and keeps DEST's mode.
        if ! cp "$tmp" "$dest"; then
            rm -f "$tmp"
            print_warning "could not write $dest: left as it was (backup in $TUIDEV_BACKUP_DIR)"
            return 0
        fi
        rm -f "$tmp"
        # No manifest record: an edited DEST may predate tuidev, and uninstall
        # removes what the manifest lists. One tuidev placed is recorded
        # already (from its install), so nothing is lost.
        print_success "merged tuidev's changes into your $dest$note: $changed (backup in $TUIDEV_BACKUP_DIR)"
    fi
    if [[ -n "$conflicts" ]]; then
        print_warning "kept your value where tuidev now ships a different one: $conflicts ($hint)"
    fi
    _tuidev_store_base "$source" "$3"
}

# read_managed_block FILE BLOCK_ID
# Prints the block content (without markers) to stdout. Exit 0 if block is
# present, 1 if absent. Used by update.sh for drift detection — single
# source of truth for the marker format.
read_managed_block() {
    local file="$1"
    local block_id="$2"
    local begin end
    begin="$(tuidev_block_begin "$block_id" "$file")"
    end="$(tuidev_block_end "$block_id" "$file")"

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
    begin="$(tuidev_block_begin "$block_id" "$file")"
    end="$(tuidev_block_end "$block_id" "$file")"

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
