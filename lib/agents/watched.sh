# shellcheck shell=bash
# lib/agents/watched.sh — the files polling loops wait on.
#
# Owns: whether a watched file has gone quiet, its modification time and
#   last line (the evidence agents_assess reads), and the credential files
#   that are never read for one.
# Uses: config.sh (AGENTS_WAIT_STUCK).
# Public: _agents_watched, _agents_watch_info, _agents_last_line,
#   _agents_cred_path, _agents_mtimes, _AGENTS_CRED_PATHS (the same list as
#   configs/sandbox/credential-paths.txt; test_contract.sh checks it).

# _agents_watched "PID<TAB>PATH[<TAB>MODE]" lines — "pid<TAB>quiet" for each polling loop
# whose watched file has not changed for AGENTS_WAIT_STUCK minutes, and
# "pid<TAB>fresh" for one whose file changed since. One find for all of them
# (-mmin works the same on macOS and Linux); a missing file says nothing, and
# the loop is then judged by its age alone.
_agents_watched() {
    local pid path paths=() old
    [[ -n "$1" && "$AGENTS_WAIT_STUCK" -gt 0 ]] || return 0
    while IFS=$'\t' read -r pid path _; do
        [[ "$pid" =~ ^[0-9]+$ && "$path" == /* && -e "$path" ]] && paths+=("$path")
    done <<<"$1"
    [[ ${#paths[@]} -gt 0 ]] || return 0
    old="$(find "${paths[@]}" -maxdepth 0 -mmin "+$AGENTS_WAIT_STUCK" -print 2>/dev/null)"
    while IFS=$'\t' read -r pid path _; do
        [[ "$pid" =~ ^[0-9]+$ && "$path" == /* && -e "$path" ]] || continue
        if [[ $'\n'"$old"$'\n' == *$'\n'"$path"$'\n'* ]]; then printf '%s\tquiet\n' "$pid"; else printf '%s\tfresh\n' "$pid"; fi
    done <<<"$1"
    return 0
}

# _agents_mtimes PATH... — "epoch<TAB>path" lines, one stat for all of them.
_agents_mtimes() {
    if [[ "${OSTYPE:-}" == darwin* ]]; then
        LC_ALL=C /usr/bin/stat -f '%m%t%N' -- "$@" 2>/dev/null
    else
        LC_ALL=C stat -c '%Y	%n' -- "$@" 2>/dev/null
    fi
    return 0
}

# Credential files and directories, relative to $HOME (a trailing / is a
# directory): never read for a last line, whatever a loop watches. The same
# list as configs/sandbox/credential-paths.txt (test_contract.sh checks it;
# agents runs without the repo, so it carries its own copy).
_AGENTS_CRED_PATHS='.ssh/ .aws/ .gnupg/ Library/Keychains/ .config/gh/ .config/gcloud/ .config/op/ .azure/ .docker/ .kube/ .terraform.d/ .password-store/ .netrc .git-credentials .npmrc .pypirc .cargo/credentials .cargo/credentials.toml .vault-token .pgpass .config/git/credentials .config/containers/auth.json .gem/credentials'

# _agents_cred_path PATH [HOME2] — true when PATH is one of those files or
# lies under one of those directories, in $HOME or in HOME2 (its physical
# path). Compared without case: macOS volumes ignore it.
_agents_cred_path() {
    local p="$1" h c rc=1 nc=0
    shopt -q nocasematch && nc=1
    shopt -s nocasematch
    for h in "$HOME" ${2:+"$2"}; do
        for c in $_AGENTS_CRED_PATHS; do
            case "$c" in
                */) [[ "$p/" == "${h%/}/$c"* ]] && { rc=0; break 2; } ;;
                *)  [[ "$p" == "${h%/}/$c" ]] && { rc=0; break 2; } ;;
            esac
        done
    done
    [[ $nc -eq 1 ]] || shopt -u nocasematch
    return $rc
}

# _agents_last_line FILE — its last non-blank line, read from the last 2 KB
# only, control characters blanked (terminal colors, tabs), at most 300
# characters. Only regular files are read (never a FIFO), never a symlink,
# and never a credential file (_agents_cred_path, by its path as given and as
# its directory resolves).
_agents_last_line() {
    local s="" l="" d h
    [[ -f "$1" && -r "$1" && ! -L "$1" && "$1" == /* ]] || return 0
    _agents_cred_path "$1" && return 0
    d="$(cd -P -- "${1%/*}/" 2>/dev/null && pwd -P)" || return 0
    h="$(cd -P -- "$HOME" 2>/dev/null && pwd -P)"
    _agents_cred_path "${d%/}/${1##*/}" "$h" && return 0
    { s="$(tail -c 2048 -- "$1")"; } 2>/dev/null
    while [[ -n "$s" ]]; do
        l="${s##*$'\n'}"
        [[ "$l" == *[![:space:]]* ]] && break
        l=""
        [[ "$s" == *$'\n'* ]] || break
        s="${s%$'\n'*}"
    done
    l="${l//[[:cntrl:]]/ }"
    printf '%s' "${l:0:300}"
}

# _agents_watch_info "PID<TAB>PATH[<TAB>MODE]" lines — for each polling loop's
# watched file: "watched PID PATH MTIME LAST MODE" (MTIME "-" when the file is
# gone; LAST "-" when there is none; MODE read, or exists for a loop that only
# tests that the file exists, whose last line is not read). One stat for all
# files, one tail per file.
_agents_watch_info() {
    local pid path mode paths=() stats m e p last n=0
    [[ -n "$1" ]] || return 0
    while IFS=$'\t' read -r pid path _; do
        [[ "$pid" =~ ^[0-9]+$ && "$path" == /* && -e "$path" ]] && paths+=("$path")
    done <<<"$1"
    [[ ${#paths[@]} -eq 0 ]] || stats="$(_agents_mtimes "${paths[@]}")"
    while IFS=$'\t' read -r pid path mode; do
        [[ "$pid" =~ ^[0-9]+$ && "$path" == /* ]] || continue
        n=$((n + 1)); [[ $n -le 16 ]] || break
        m=-
        while IFS=$'\t' read -r e p; do
            [[ "$p" == "$path" && "$e" =~ ^[0-9]+$ ]] && { m="$e"; break; }
        done <<<"${stats:-}"
        last=""
        if [[ "$mode" != exists ]]; then mode="read"; last="$(_agents_last_line "$path")"; fi
        printf 'watched\t%s\t%s\t%s\t%s\t%s\n' "$pid" "$path" "$m" "${last:--}" "$mode"
    done <<<"$1"
}
