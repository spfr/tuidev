# shellcheck shell=bash
# lib/agents/lazy.sh — `agents mcp lazy|eager`: put configured MCP servers
# behind mcp-lazy, so a session starts one on its first tool call instead of
# with the session, or take them from behind it.
#
# mcp-lazy (bin/mcp-lazy, installed beside agents) stands where a server's
# command was. lazy makes a stdio server's command mcp-lazy and its args
# ["--name", NAME, "--", COMMAND, ARGS...] (with "--env", its env's names,
# for a server whose config sets env: mcp-lazy keys its cache by their
# values); eager puts back what follows the "--". Only the files a server is defined in that are this machine's own:
# Claude Code's .claude.json (user and local scope, through jq) and Codex's
# config.toml (awk/mcp_toml_launch.awk). Never a project's .mcp.json (it
# goes with the repo, where a path on this machine does not belong) nor a
# plugin's. A file is copied to AGENTS_DATA_DIR/backups/ first (the last 10
# of each kept), then replaced in one rename, and only if nothing wrote to
# it meanwhile. Sessions running keep the servers they started with.
#
# Owns: agents mcp lazy|eager.
# Uses: mcp.sh (_agents_mcp_paths, _agents_mcp_load, _agents_mcp_refresh),
#   config.sh (AGENTS_PATH, AGENTS_DATA_DIR), util.sh (_agents_awk);
#   awk/mcp_toml_launch.awk.
# Public: agents_mcp_launch.

# The jq that rewrites .claude.json: the servers named in $names, at user
# and local scope, put behind $lz ($mode lazy) or taken from behind it
# (eager). Exits 3, printing nothing, when nothing changes.
# shellcheck disable=SC2016  # jq source
_AGENTS_LAZY_JQ='
def lazyc: (.command | type) == "string" and (.command | test("(^|/)mcp-lazy$"));
def wrap($n):
    if type == "object" and (.command | type) == "string" and .command != "" and (has("url") | not)
       and ((.type // "stdio") == "stdio") and (lazyc | not)
    then .args = (["--name", $n]
                  + (if (.env | type) == "object" and (.env | length) > 0 then ["--env", (.env | keys | join(","))] else [] end)
                  + ["--", .command] + ((.args // []) | map(tostring)))
         | .command = $lz
    else . end;
def unwrap:
    if type == "object" and lazyc then
        (.args // []) as $a | ($a | indices("--") | first // null) as $i
        | if $i != null and ($a | length) > $i + 1 then .command = $a[$i + 1] | .args = $a[$i + 2:] else . end
    else . end;
def servers:
    if type == "object" then
        with_entries(if (.key | IN($names[])) then .key as $k | .value |= (if $mode == "lazy" then wrap($k) else unwrap end) else . end)
    else . end;
. as $o
| (if has("mcpServers") then .mcpServers |= servers else . end)
| (if (.projects | type) == "object" then
       .projects |= map_values(if type == "object" and has("mcpServers") then .mcpServers |= servers else . end)
   else . end)
| if . == $o then "" | halt_error(3) else . end'

# _agents_lazy_backup FILE — copy FILE to AGENTS_DATA_DIR/backups/, keeping
# the last 10 of its name; print where.
_agents_lazy_backup() {
    local dir="$AGENTS_DATA_DIR/backups" b="${1##*/}" to old n=0
    b="${b#.}"
    to="$dir/$b.$(date +%Y%m%d-%H%M%S).$$"
    ( umask 077; mkdir -p "$dir" && cp -p "$1" "$to" ) || return 1
    # shellcheck disable=SC2012  # names this module made: no odd characters
    ls -1t "$dir/$b".* 2>/dev/null | while IFS= read -r old; do
        n=$((n + 1)); [[ $n -le 10 ]] || rm -f "$old"
    done
    echo "  backup: $to"
}

# _agents_lazy_write FILE NEW — replace FILE with the file NEW (a temp file
# beside it) after a backup, unless FILE changed since the caller's sum (its
# cksum, taken before NEW was made), checked last, right before the rename.
# A FILE that is a symlink (a dotfile manager's): its target is replaced,
# so the callers make NEW beside the target.
_agents_lazy_write() {
    local f="$1" new="$2"
    _agents_lazy_backup "$f" || { rm -f "$new"; echo "agents: could not back up $f: left as it was" >&2; return 1; }
    if [[ "$(cksum < "$f")" != "$sum" ]]; then
        rm -f "$new"
        echo "agents: $f changed while it was rewritten (a session wrote to it): run this again" >&2
        return 1
    fi
    mv -f "$new" "$(_agents_lazy_target "$f")"
}

# _agents_lazy_target FILE — the file FILE's symlinks lead to (FILE itself
# when it is none), so a dotfile manager's link stays a link.
_agents_lazy_target() {
    local f="$1" l n=0
    while [[ -L "$f" && $n -lt 32 ]]; do
        l="$(readlink "$f")" || break
        case "$l" in /*) f="$l" ;; *) f="${f%/*}/$l" ;; esac
        n=$((n + 1))
    done
    printf '%s\n' "$f"
}

# _agents_lazy_claude MODE LZ NAMES — rewrite .claude.json (cj) for the
# servers in NAMES ("\n"-joined).
_agents_lazy_claude() {
    local mode="$1" lz="$2" names sum new rc=0
    [[ -f "$cj" ]] || return 0
    # jq 1.6+ (IN, halt_error): with 1.5 the program would not compile, and
    # its exit code (3) would read as "nothing to change".
    jq -n '1 | IN(1)' >/dev/null 2>&1 || { echo "agents: jq 1.6 or later is needed to edit $cj" >&2; return 1; }
    names="$(printf '%s' "$3" | jq -R . | jq -sc .)"
    sum="$(cksum < "$cj")"
    new="$(_agents_lazy_target "$cj").agents.$$"
    cp -p "$cj" "$new" 2>/dev/null || { echo "agents: cannot write beside $cj" >&2; return 1; }
    jq --arg mode "$mode" --arg lz "$lz" --argjson names "$names" "$_AGENTS_LAZY_JQ" "$cj" > "$new" || rc=$?
    case "$rc" in
        0) _agents_lazy_write "$cj" "$new" ;;
        3) rm -f "$new" ;;
        *) rm -f "$new"; echo "agents: could not rewrite $cj (jq failed): left as it was" >&2; return 1 ;;
    esac
}

# _agents_lazy_codex MODE LZ NAMES — rewrite config.toml (codex) for the
# servers in NAMES; print why any was skipped.
_agents_lazy_codex() {
    local mode="$1" lz="$2" sum new rep what name why
    [[ -f "$codex" ]] || return 0
    sum="$(cksum < "$codex")"
    new="$(_agents_lazy_target "$codex").agents.$$"
    rep="$(cp -p "$codex" "$new" && AGENTS_LAZY_NAMES="$3" AGENTS_LAZY_FILE="$codex" _agents_awk mcp_toml_launch -v mode="$mode" -v lz="$lz" < /dev/null 2>&1 > "$new")" \
        || { rm -f "$new"; echo "agents: could not rewrite $codex: left as it was" >&2; return 1; }
    while IFS=$'\t' read -r what name why; do
        [[ "$what" == skip ]] && echo "  $name (codex): left as it is: $why; edit $codex by hand"
    done <<<"$rep"
    if cmp -s "$codex" "$new"; then rm -f "$new"; return 0; fi
    _agents_lazy_write "$codex" "$new"
}

# agents_mcp_launch lazy|eager NAME...|--all — see the header.
agents_mcp_launch() {
    # shellcheck disable=SC2034  # cdir: _agents_mcp_paths sets it with cj and codex
    local mode="$1" lz="${AGENTS_PATH%/*}/mcp-lazy" all="" a want=$'\n' cj cdir codex
    local l cli scope name src type lw before="" claude_n="" codex_n="" found=$'\n' rc=0 now
    shift
    for a in "$@"; do
        case "$a" in
            --all) all=1 ;;
            -*)    echo "usage: agents mcp $mode NAME...|--all" >&2; return 2 ;;
            *)     want+="$a"$'\n' ;;
        esac
    done
    if [[ -z "$all" && "$want" == $'\n' ]]; then
        echo "usage: agents mcp $mode NAME...|--all" >&2; return 2
    fi
    if [[ "$mode" == lazy ]]; then
        [[ -x "$lz" ]] || { echo "agents: no mcp-lazy beside agents ($lz): ./install.sh --pack monitoring installs it" >&2; return 1; }
        /usr/bin/perl -MJSON::PP -MDigest::SHA -e 1 2>/dev/null \
            || { echo "agents: mcp-lazy needs /usr/bin/perl with JSON::PP and Digest::SHA" >&2; return 1; }
    fi
    _agents_mcp_paths
    _agents_mcp_load sync
    while IFS=$'\t' read -r l cli scope name src _ type _ _ lw; do
        [[ "$l" == srv ]] || continue
        [[ -n "$all" || "$want" == *$'\n'"$name"$'\n'* ]] || continue
        found+="$name"$'\n'
        if [[ "$type" != stdio ]]; then
            [[ -n "$all" ]] || echo "  $name ($cli, $scope): left as it is: not a stdio server"
            continue
        fi
        case "$cli:$scope" in
            claude:user|claude:local) claude_n+="$name"$'\n' ;;
            codex:user)               codex_n+="$name"$'\n' ;;
            *:project) echo "  $name ($cli, project scope): left as it is: $src goes with the repo" ; continue ;;
            *)         echo "  $name ($cli, $scope scope): left as it is: $src's servers are its own" ; continue ;;
        esac
        before+="$cli"$'\t'"$scope"$'\t'"$name"$'\t'"$src"$'\t'"${lw:--}"$'\n'
    done <<<"$_AGENTS_MCP_ROWS"
    for a in $want; do
        [[ "$found" == *$'\n'"$a"$'\n'* ]] || { echo "agents: no MCP server named $a (agents mcp lists them)" >&2; rc=1; }
    done
    [[ -z "$claude_n" ]] || _agents_lazy_claude "$mode" "$lz" "$claude_n" || rc=1
    [[ -z "$codex_n" ]] || _agents_lazy_codex "$mode" "$lz" "$codex_n" || rc=1
    [[ -n "$before" ]] || return "$rc"
    # What each is now, from the files as they are.
    _agents_mcp_refresh now
    while IFS=$'\t' read -r cli scope name src lw; do
        [[ -n "$name" ]] || continue
        a="$(printf '%s' "$now" | awk -F '\t' -v c="$cli" -v s="$scope" -v n="$name" -v f="$src" \
            '$2 == c && $3 == s && $4 == n && $5 == f { print ($10 == "lazy" ? "lazy" : "-"); exit }')"
        if [[ "$a" == "$lw" ]]; then
            [[ "$a" == lazy ]] && l="already lazy" || l="already starts with each session"
        elif [[ "$a" == lazy ]]; then
            l="lazy: new sessions start it on its first tool call"
        else
            l="starts with each session again"
        fi
        printf '  %-22s %-6s %-6s %s\n' "$name" "$cli" "$scope" "$l"
    done <<<"$before"
    echo "Sessions running now keep the servers they started with."
    return "$rc"
}
