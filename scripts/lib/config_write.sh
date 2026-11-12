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
# marker pattern so it's self-documenting. A file whose markers do not pair
# up is never rewritten (see _tuidev_block_check).
#
# Every rewrite follows a symlinked file to its target, writes a temp file in
# the target's own directory, keeps the target's mode and renames the temp
# file into place; a file a managed-block write changes is backed up first.
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
# copied as a tree with `cp -R`. A second backup of the same prefix within
# the same second gets a `-2`, `-3`, ... suffix instead of replacing the first.
#
# Echoes the backup target path on success. On failure, echoes nothing and
# returns non-zero.
tuidev_backup() {
    local src="$1"
    local prefix="${2:-$(basename "$src")}"
    [[ -e "$src" ]] || return 1

    local stamp target n=1
    stamp="$(date +%Y%m%d-%H%M%S)"
    target="$TUIDEV_BACKUP_DIR/$prefix.$stamp"

    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY RUN] would back up $src -> $target"
        echo "$target"
        return 0
    fi

    mkdir -p "$TUIDEV_BACKUP_DIR" || return 1
    while [[ -e "$target" || -L "$target" ]]; do
        n=$((n + 1))
        target="$TUIDEV_BACKUP_DIR/$prefix.$stamp-$n"
    done
    if [[ -f "$src" ]]; then
        # -L: follow a symlink; -p: keep the mode (and times).
        cp -L -p "$src" "$target" || { rm -f "$target"; return 1; }
    else
        cp -R "$src" "$target" || { rm -rf "$target"; return 1; }
    fi

    # Retention: drop everything past the N most-recent entries for this prefix.
    # Backup names include sortable timestamps, which keeps this portable across
    # BSD and GNU userlands without relying on incompatible stat flags. The
    # timestamp starts with a digit, so prefix `config` never rotates away the
    # backups of prefix `config.toml`.
    find "$TUIDEV_BACKUP_DIR" -mindepth 1 -maxdepth 1 -name "${prefix}.[0-9]*" -print \
        2>/dev/null |
        sort -r |
        awk -v keep="$TUIDEV_BACKUP_KEEP" 'NR>keep {print}' |
        while IFS= read -r old; do
            rm -rf -- "$old"
        done

    echo "$target"
}

# ---------------------------------------------------------------------------
# Safe file replacement, shared by every writer below
# ---------------------------------------------------------------------------
# A rewrite never goes through $TMPDIR and never replaces a symlink: the new
# content is written to a temp file in the real target's own directory (same
# filesystem, so the final rename is atomic), given the target's mode, and
# renamed over the target. A dotfiles link stays a link and its target gets
# the content.

# _tuidev_real_path FILE — FILE with every symlink followed, to the final
# target (which may not exist). Fails on a link loop.
_tuidev_real_path() {
    local path="$1" link hops=0
    while [[ -L "$path" ]]; do
        hops=$((hops + 1))
        [[ $hops -le 40 ]] || return 1
        link="$(readlink "$path")" || return 1
        case "$link" in
            /*) path="$link" ;;
            *)  path="$(dirname "$path")/$link" ;;
        esac
    done
    printf '%s\n' "$path"
}

# _tuidev_mktemp_beside REAL — an empty temp file in REAL's directory; prints
# its path. Hidden, and named after REAL, so a leftover is recognisable.
_tuidev_mktemp_beside() {
    mktemp "$(dirname "$1")/.$(basename "$1").tuidev.XXXXXX"
}

# _tuidev_umask_mode [MODE] — MODE (octal, default 666) less the umask: what
# a plain `>` or `cp` would give a new file.
_tuidev_umask_mode() {
    printf '%o\n' "$(( 0${1:-666} & ~$(umask) ))"
}

# _tuidev_rename_into TMP REAL [NEWMODE]
# Give TMP REAL's mode (or NEWMODE, default the umask's, when REAL does not
# exist yet) and rename it over REAL. TMP is removed on failure.
_tuidev_rename_into() {
    local tmp="$1" real="$2" mode="${3-}"
    if [[ -e "$real" ]]; then
        mode="$(file_mode "$real")" || mode=""
    fi
    [[ -n "$mode" ]] || mode="$(_tuidev_umask_mode)"
    if chmod "$mode" "$tmp" && mv -f "$tmp" "$real"; then
        return 0
    fi
    rm -f "$tmp"
    return 1
}

# _tuidev_commit TMP FILE REAL
# Put TMP (the new content of FILE, whose resolved path is REAL) in place.
# Identical content: TMP is dropped and FILE not touched. Otherwise a
# non-empty REAL is backed up first; when the backup or the rename fails,
# FILE is left as it was, with a warning, and this fails.
_tuidev_commit() {
    local tmp="$1" file="$2" real="$3"
    if [[ -f "$real" ]] && cmp -s "$tmp" "$real"; then
        rm -f "$tmp"
        return 0
    fi
    if [[ -s "$real" ]] && ! tuidev_backup "$file" "$(_tuidev_backup_prefix "$file")" >/dev/null; then
        rm -f "$tmp"
        print_warning "could not back up $file, so it was left as it is" >&2
        return 1
    fi
    if ! _tuidev_rename_into "$tmp" "$real"; then
        print_warning "could not write $file, so it was left as it is" >&2
        return 1
    fi
}

# _tuidev_backup_prefix FILE — the backup name for a managed-block file: its
# path under $HOME with `/` as `_` (.config_ghostty_config), so files that
# share a basename never share a backup slot or its rotation.
_tuidev_backup_prefix() {
    printf '%s\n' "${1#"$HOME"/}" | tr '/' '_'
}

# _tuidev_place_copy SOURCE DEST
# Copy SOURCE onto DEST the safe way (links followed, temp file beside the
# target, atomic rename). An existing target keeps its mode; a new one gets
# SOURCE's mode less the umask, as `cp` would give it. A DEST that is a
# dangling symlink fails: its target's place is not ours to create.
_tuidev_place_copy() {
    local source="$1" dest="$2" real tmp mode=""
    [[ -L "$dest" && ! -e "$dest" ]] && return 1
    real="$(_tuidev_real_path "$dest")" || return 1
    if [[ ! -e "$real" ]] && mode="$(file_mode "$source")"; then
        mode="$(_tuidev_umask_mode "$mode")"
    fi
    mkdir -p "$(dirname "$real")" || return 1
    tmp="$(_tuidev_mktemp_beside "$real")" || return 1
    if ! cat "$source" > "$tmp"; then
        rm -f "$tmp"
        return 1
    fi
    _tuidev_rename_into "$tmp" "$real" "$mode"
}

# ---------------------------------------------------------------------------
# Managed blocks
# ---------------------------------------------------------------------------

# _tuidev_block_check FILE BLOCK_ID
# Do FILE's markers for BLOCK_ID pair up? Prints `none` (no marker at all) or
# `one` (exactly one begin line, then exactly one end line) and succeeds.
# Anything else (a begin without an end, an end without a begin, duplicates,
# the wrong order, or a marker line with extra text such as trailing spaces
# or a CR) prints what is wrong and fails: the writers then change nothing,
# because rewriting a half-marked file drops the user's lines after it.
_tuidev_block_check() {
    local begin end
    begin="$(tuidev_block_begin "$2" "$1")"
    end="$(tuidev_block_end "$2" "$1")"
    awk -v b="$begin" -v e="$end" '
        $0 == b { nb++; if (!fb) fb = NR; next }
        $0 == e { ne++; if (!fe) fe = NR; next }
        index($0, b) || index($0, e) { bad++ }
        END {
            if (bad) { print "a marker line with extra text on it (trailing spaces or Windows line endings?)"; exit 1 }
            if (!nb && !ne) { print "none"; exit 0 }
            if (nb == 1 && ne == 1 && fb < fe) { print "one"; exit 0 }
            if (!ne)                 print "a begin marker with no end marker"
            else if (!nb)            print "an end marker with no begin marker"
            else if (nb > 1 || ne > 1) print nb " begin and " ne " end markers"
            else                     print "its end marker above its begin marker"
            exit 1
        }' "$1"
}

# _tuidev_block_refuse FILE BLOCK_ID PROBLEM — the warning for a file whose
# markers do not pair up. On stderr: callers often silence stdout.
_tuidev_block_refuse() {
    print_warning "$1: tuidev's managed block '$2' has ${3:-markers tuidev could not read}, so the file was left as it is.
   Fix it by hand: tuidev's lines go between one '$(tuidev_block_begin "$2" "$1")' line
   and one '$(tuidev_block_end "$2" "$1")' line below it (or delete the markers and those lines), then re-run." >&2
}

# _tuidev_block_body CONTENT — CONTENT as the lines between the markers: one
# trailing newline at most, nothing at all for empty CONTENT.
_tuidev_block_body() {
    case "$1" in
        "")      ;;
        *$'\n')  printf '%s' "$1" ;;
        *)       printf '%s\n' "$1" ;;
    esac
}

# _tuidev_block_render FILE STATE BEGIN END CONTENT
# Print FILE with the block set to CONTENT. STATE is _tuidev_block_check's:
# `one` replaces the block where it stands, `none` appends one (after a blank
# line, unless FILE is empty or already ends in one).
_tuidev_block_render() {
    local file="$1" state="$2" begin="$3" end="$4" content="$5"
    if [[ "$state" == one ]]; then
        awk -v b="$begin" '{ print } $0 == b { exit }' "$file" || return 1
        _tuidev_block_body "$content"
        awk -v e="$end" 'p { print; next } $0 == e { p = 1; print }' "$file" || return 1
        return 0
    fi
    if [[ -s "$file" ]]; then
        cat "$file" || return 1
        if [[ "$(tail -c1 "$file" | wc -l | tr -d ' ')" -eq 0 || "$(tail -n1 "$file")" != "" ]]; then
            echo ""
        fi
    fi
    printf '%s\n' "$begin"
    _tuidev_block_body "$content"
    printf '%s\n' "$end"
}

# write_managed_block FILE BLOCK_ID [CONTENT]
# If CONTENT is omitted, reads from stdin. Creates FILE if missing. Replaces
# the existing block with matching BLOCK_ID; appends one if absent. A FILE
# whose markers for BLOCK_ID do not pair up (see _tuidev_block_check) is left
# byte-identical, with a warning on stderr, and this returns 1; so does a
# failed backup or write. A FILE that changes is backed up first.
write_managed_block() {
    local file="$1"
    local block_id="$2"
    local content="${3-}"

    [[ -z "$file" || -z "$block_id" ]] && {
        print_error "write_managed_block: FILE and BLOCK_ID required"
        return 2
    }

    local begin end state=none
    begin="$(tuidev_block_begin "$block_id" "$file")"
    end="$(tuidev_block_end "$block_id" "$file")"

    if [[ -z "$content" ]]; then
        content="$(cat)"
    fi

    if [[ -L "$file" && ! -e "$file" ]]; then
        print_warning "$file is a symlink to a missing file, so it was left as it is (fix or remove the link, then re-run)" >&2
        return 1
    fi
    if [[ -e "$file" && ! -f "$file" ]]; then
        print_warning "$file is not a regular file, so no managed block was written to it" >&2
        return 1
    fi
    if [[ -f "$file" ]] && ! state="$(_tuidev_block_check "$file" "$block_id")"; then
        _tuidev_block_refuse "$file" "$block_id" "$state"
        return 1
    fi

    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY RUN] would write managed block '${block_id}' to ${file}"
        return 0
    fi

    local real tmp
    if ! { real="$(_tuidev_real_path "$file")" \
            && mkdir -p "$(dirname "$real")" \
            && tmp="$(_tuidev_mktemp_beside "$real")"; }; then
        print_warning "could not create a temp file next to $file, so it was left as it is" >&2
        return 1
    fi

    if ! _tuidev_block_render "$file" "$state" "$begin" "$end" "$content" > "$tmp"; then
        rm -f "$tmp"
        print_warning "could not write $file, so it was left as it is" >&2
        return 1
    fi
    _tuidev_commit "$tmp" "$file" "$real" || return 1

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
            # A refused write (markers that do not pair up, a failed backup)
            # has left DEST as it was and said why; the install goes on.
            write_managed_block "$dest" "$block_id" "$(cat "$source")" || true
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
                elif _tuidev_place_copy "$source" "$dest"; then
                    tuidev_manifest_record file "$dest"
                    print_success "overwrote $dest (backup in $TUIDEV_BACKUP_DIR)"
                else
                    print_warning "could not write $dest: left as it is"
                fi
            else
                if [[ "$DRY_RUN" == true ]]; then
                    print_info "[DRY RUN] would copy $source -> $dest"
                elif _tuidev_place_copy "$source" "$dest"; then
                    tuidev_manifest_record file "$dest"
                    print_success "installed $dest"
                else
                    print_warning "could not write $dest"
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
        # Written through a symlinked DEST to its target, keeping the mode,
        # and renamed into place (atomic). Not cp: BusyBox cp replaces the
        # link with a regular file.
        if ! _tuidev_place_copy "$tmp" "$dest"; then
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
# Removes the block (and its markers) if present. No-op if absent. FILE is
# backed up first. A FILE whose markers for BLOCK_ID do not pair up is left
# byte-identical, with a warning on stderr, and this returns 1; so does a
# failed backup or write.
remove_managed_block() {
    local file="$1"
    local block_id="$2"
    local begin end state
    begin="$(tuidev_block_begin "$block_id" "$file")"
    end="$(tuidev_block_end "$block_id" "$file")"

    [[ -f "$file" ]] || return 0
    if ! state="$(_tuidev_block_check "$file" "$block_id")"; then
        _tuidev_block_refuse "$file" "$block_id" "$state"
        return 1
    fi
    [[ "$state" == one ]] || return 0

    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY RUN] would remove managed block '${block_id}' from ${file}"
        return 0
    fi

    local real tmp
    if ! { real="$(_tuidev_real_path "$file")" && tmp="$(_tuidev_mktemp_beside "$real")"; }; then
        print_warning "could not create a temp file next to $file, so it was left as it is" >&2
        return 1
    fi
    if ! awk -v begin="$begin" -v end="$end" '
        $0 == begin { in_block=1; next }
        $0 == end   { in_block=0; next }
        !in_block   { print }
    ' "$file" > "$tmp"; then
        rm -f "$tmp"
        print_warning "could not write $file, so it was left as it is" >&2
        return 1
    fi
    _tuidev_commit "$tmp" "$file" "$real" || return 1
    print_success "removed managed block '${block_id}' from ${file}"
    # Nothing but our block was in it: drop the now-empty file. Not a
    # symlink: the link and its target (a dotfiles repo) are the user's.
    if [[ ! -L "$file" ]] && ! grep -q '[^[:space:]]' "$file"; then
        rm -f "$file"
        print_info "removed ${file} (only held the tuidev block)"
    fi
}

# tuidev_install_notify REPO — ~/.local/bin/notify.sh, which the Claude Code
# hooks call, from REPO's scripts/notify.sh. tuidev owns the file. Called by
# install.sh and by `update.sh --configs`, so a new notify.sh reaches
# machines that only update.
tuidev_install_notify() {
    [[ -f "$1/scripts/notify.sh" ]] || return 0
    install_config "$HOME/.local/bin/notify.sh" "$1/scripts/notify.sh" --overwrite
    [[ "${DRY_RUN:-false}" == true ]] || chmod +x "$HOME/.local/bin/notify.sh"
}
