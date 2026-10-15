# shellcheck shell=bash
# lib/agents/mcp.sh — the MCP servers you configured, and which process is
# which.
#
# Claude Code reads its servers from .claude.json ($HOME's, or
# $CLAUDE_CONFIG_DIR's): mcpServers (user scope) and projects[DIR].mcpServers
# (local scope); from a project's DIR/.mcp.json (project scope); and from each
# enabled plugin's .mcp.json and its .claude-plugin/plugin.json's mcpServers
# (servers inline, or the plugin's JSON files that hold them), the plugins
# being settings.json's enabledPlugins, located through
# plugins/installed_plugins.json. Codex reads its own from config.toml's
# [mcp_servers.NAME] tables ($CODEX_HOME, default ~/.codex). Of a server,
# agents keeps its name, scope, where it is configured, its transport (stdio
# or http) and its needle: the one word of its command line that names it in
# ps (an npx or uvx package without its version, a program's name, a
# script's path; awk/mcp.awk picks it). Never the rest of its args, its env,
# headers or URL: those hold tokens. jq reads the JSON; without jq only
# Codex's servers are known.
#
# The inventory is cached in the run dir (mcp.tsv, private) with the files it
# came from, and rebuilt once one of them changes, appears or goes away.
# Claude Code rewrites .claude.json all the time, so classifying (every menu
# refresh) never waits for a rebuild: it reads the cache it has and rebuilds
# it in the background, at most every 30 s. Only the first build, with no
# cache yet, is waited for.
#
# Owns: the inventory (the one place MCP servers are read from config; the
#   context view builds on it) and mcp.tsv; `agents mcp`.
# Uses: config.sh (AGENTS_RUN_DIR), util.sh (_agents_awk, _agents_now,
#   _agents_detach, _agents_lock, _agents_replace); awk/mcp.awk,
#   awk/mcp_toml.awk. awk/lib_activity.awk names the processes
#   (mcp_known, mcp_name) from _agents_mcp_needles.
# Public: agents_mcp_configured [DIR] — "cli<TAB>scope<TAB>name<TAB>source<TAB>
#   enabled" for each configured server (cli: claude, codex; scope: user,
#   local, project, plugin; source: the file it is in, ".claude.json:DIR" for
#   local scope, NAME@MARKETPLACE for a plugin's; enabled: 0 for a Codex
#   server set `enabled = false`, else 1); with DIR, only those a session
#   started in DIR loads (user, plugin, and DIR's local and project ones);
#   agents_mcp (`agents mcp`); _agents_mcp_needles VAR; _agents_mcp_lookup.

# Where each CLI keeps its configuration: sets the caller's cj (.claude.json),
# cdir (Claude Code's config dir) and codex (config.toml).
# shellcheck disable=SC2034  # it sets the caller's variables
_agents_mcp_paths() {
    cdir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
    if [[ -n "${CLAUDE_CONFIG_DIR:-}" ]]; then cj="$CLAUDE_CONFIG_DIR/.claude.json"; else cj="$HOME/.claude.json"; fi
    codex="${CODEX_HOME:-$HOME/.codex}/config.toml"
}

# The jq that turns an object of servers into raw records for awk/mcp.awk:
#   cli scope name source project root type command args(\037-joined)
# Args go to awk, which keeps one word of them, and nowhere else.
# shellcheck disable=SC2016  # jq source
_AGENTS_MCP_JQ_ROWS='def rows($cli; $scope; $src; $proj; $root):
    to_entries[] | select(.value | type == "object")
    | [$cli, $scope, .key, $src, $proj, $root,
       (.value.type // (if .value.url then "http" else "stdio" end)),
       (.value.command // "-"),
       ((.value.args // []) | if type == "array" then map(tostring | gsub("[[:cntrl:]]"; " ")) | join("\u001f") else "" end)]
    | map(tostring | gsub("[\t\n\r]"; " ")) | join("\t");'

# _agents_mcp_build — the inventory: "dep 1|0 PATH" for every file read or
# looked for (whether it existed), then awk/mcp.awk's srv rows.
_agents_mcp_build() {
    local cj cdir codex jq="" raw="" deps="" line p f out
    _agents_mcp_paths
    command -v jq >/dev/null 2>&1 && jq=1
    for f in "$cj" "$cdir/settings.json" "$cdir/plugins/installed_plugins.json" "$codex"; do
        if [[ -f "$f" ]]; then deps+="dep"$'\t'"1"$'\t'"$f"$'\n'; else deps+="dep"$'\t'"0"$'\t'"$f"$'\n'; fi
    done
    if [[ -n "$jq" && -f "$cj" ]]; then
        # User and local scope, and the projects whose .mcp.json to look for.
        out="$(jq -r --arg src "$cj" "$_AGENTS_MCP_JQ_ROWS"'
            (.mcpServers // {} | objects | rows("claude"; "user"; $src; "-"; "-")),
            (.projects // {} | objects | to_entries[] | .key as $p
                | ((.value.mcpServers // {}) | objects | rows("claude"; "local"; $src + ":" + $p; $p; "-")),
                  "dir\t" + ($p | gsub("[\t\n\r]"; " ")))' "$cj" 2>/dev/null)" || out=""
        while IFS= read -r line; do
            case "$line" in
                # A project that is not here (a path from another machine,
                # where even a stat of /home can wait on the automounter)
                # is not watched for a .mcp.json.
                dir$'\t'*) p="${line#dir$'\t'}"; f="$p/.mcp.json"
                           if [[ -f "$f" ]]; then
                               deps+="dep"$'\t'"1"$'\t'"$f"$'\n'
                               raw+="$(_agents_mcp_file "$f" project "$f" "$p" -)"$'\n'
                           elif [[ -d "$p" ]]; then
                               deps+="dep"$'\t'"0"$'\t'"$f"$'\n'
                           fi ;;
                ?*)        raw+="$line"$'\n' ;;
            esac
        done <<<"$out"
    fi
    if [[ -n "$jq" && -f "$cdir/settings.json" && -f "$cdir/plugins/installed_plugins.json" ]]; then
        while IFS=$'\t' read -r p f; do
            [[ -n "$p" && "$f" == /* ]] || continue
            _agents_mcp_plugin "$p" "$f"
        done < <(_agents_mcp_plugins "$cdir")
    fi
    [[ ! -f "$codex" ]] || raw+="$(_agents_awk mcp_toml -v src="$codex" < "$codex" 2>/dev/null)"$'\n'
    printf '%s' "$deps"
    printf '%s' "$raw" | _agents_awk mcp
}

# _agents_mcp_plugin NAME ROOT — a plugin's servers, into the caller's deps
# and raw: its .mcp.json, and what its .claude-plugin/plugin.json's
# mcpServers holds: servers (an object), or paths of JSON files in the
# plugin that hold them (a string, or an array of them; never one outside
# it). A server both name is one (awk/mcp.awk keeps the first).
_agents_mcp_plugin() {
    local p="$1" root="$2" pj="$2/.claude-plugin/plugin.json" line rel files=("$2/.mcp.json") f
    if [[ -f "$pj" ]]; then
        deps+="dep"$'\t'"1"$'\t'"$pj"$'\n'
        while IFS= read -r line; do
            case "$line" in
                file$'\t'*) rel="${line#file$'\t'}"; rel="${rel#./}"
                            [[ -n "$rel" && "$rel" != /* && "$rel" != *..* ]] && files+=("$root/$rel") ;;
                ?*)         raw+="$line"$'\n' ;;
            esac
        done < <(jq -r --arg src "$p" --arg root "$root" "$_AGENTS_MCP_JQ_ROWS"'
            .mcpServers | if type == "object" then rows("claude"; "plugin"; $src; "-"; $root)
                elif type == "string" then "file\t" + gsub("[\t\n\r]"; " ")
                elif type == "array" then .[] | strings | "file\t" + gsub("[\t\n\r]"; " ")
                else empty end' "$pj" 2>/dev/null)
    else
        deps+="dep"$'\t'"0"$'\t'"$pj"$'\n'
    fi
    for f in "${files[@]}"; do
        if [[ -f "$f" ]]; then
            deps+="dep"$'\t'"1"$'\t'"$f"$'\n'
            raw+="$(_agents_mcp_file "$f" plugin "$p" - "$root")"$'\n'
        else
            deps+="dep"$'\t'"0"$'\t'"$f"$'\n'
        fi
    done
}

# _agents_mcp_file FILE SCOPE SOURCE PROJECT ROOT — a .mcp.json's raw records
# (its servers under mcpServers, or at the top level as plugins write them).
_agents_mcp_file() {
    jq -r --arg scope "$2" --arg src "$3" --arg proj "$4" --arg root "$5" "$_AGENTS_MCP_JQ_ROWS"'
        (if has("mcpServers") then .mcpServers else . end) | objects
        | rows("claude"; $scope; $src; $proj; $root)' "$1" 2>/dev/null
    return 0
}

# _agents_mcp_plugins CDIR — "NAME@MARKETPLACE<TAB>INSTALL_PATH" for every
# plugin settings.json enables and installed_plugins.json has installed.
_agents_mcp_plugins() {
    jq -rn --slurpfile s "$1/settings.json" --slurpfile i "$1/plugins/installed_plugins.json" '
        ($s[0].enabledPlugins // {}) as $on
        | ($i[0].plugins // {}) | objects | to_entries[] | select($on[.key] == true)
        | (.value | if type == "array" then .[0] else . end | objects | .installPath // empty) as $root
        | (.key | gsub("[\t\n\r]"; " ")) + "\t" + $root' 2>/dev/null
    return 0
}

# The cache's format: a cache of another (an older agents', whose needles
# were picked by other rules) is never read, only rebuilt.
_AGENTS_MCP_CACHE_V=v2

# _agents_mcp_refresh [VAR] — rebuild mcp.tsv (private; one rebuild at a
# time), and with VAR set it to the srv rows built (also when the cache
# could not be written). The cache takes the mtime the build began at
# (mcp.start's, made before a config is read), so a config written while it
# ran is not older than the cache, which is then stale (_agents_mcp_load).
_agents_mcp_refresh() {
    local _lock="$AGENTS_RUN_DIR/mcp.lock" _start="$AGENTS_RUN_DIR/mcp.start" _now _out _locked="" _line _rows=""
    mkdir -p "$AGENTS_RUN_DIR" 2>/dev/null && _agents_lock "$_lock" && _locked=1
    [[ -n "$_locked" || -n "${1:-}" ]] || return 0
    _agents_now _now
    [[ -z "$_locked" ]] || ( umask 077; : > "$_start" ) 2>/dev/null || true
    _out="$(_agents_mcp_build)"
    if [[ -n "$_locked" ]]; then
        if ( umask 077; _agents_replace "$AGENTS_RUN_DIR/mcp.tsv" "$_AGENTS_MCP_CACHE_V"$'\t'"$_now"$'\n'"$_out" ) \
            && ! touch -r "$_start" "$AGENTS_RUN_DIR/mcp.tsv" 2>/dev/null; then
            rm -f "$AGENTS_RUN_DIR/mcp.tsv"   # no start time: rebuilt next time rather than trusted
        fi
        rm -f "$_start"
        _agents_unlock "$_lock"
    fi
    [[ -n "${1:-}" ]] || return 0
    while IFS= read -r _line; do [[ "$_line" == srv$'\t'* ]] && _rows+="$_line"$'\n'; done <<<"$_out"
    printf -v "$1" '%s' "$_rows"
}

# _agents_mcp_load [sync] — set _AGENTS_MCP_ROWS to the inventory's srv rows,
# from mcp.tsv while the files it came from are older than it (a config
# written in the second the build began counts as changed: bash 3.2's -ot
# compares whole seconds, and one more rebuild is cheap). A stale cache is
# rebuilt now with sync (or when there is none yet, or it is another
# format's), else in the background (at most every 30 s) while the rows it
# has are used. Reads with bash alone.
_agents_mcp_load() {
    local cache="$AGENTS_RUN_DIR/mcp.tsv" line flag path built="" stale="" now rows=""
    # shellcheck disable=SC2094  # -ot only compares mtimes
    if [[ -f "$cache" ]]; then
        while IFS= read -r line; do
            case "$line" in
                srv$'\t'*) rows+="$line"$'\n' ;;
                dep$'\t'*) line="${line#dep$'\t'}"; flag="${line%%$'\t'*}"; path="${line#*$'\t'}"
                           if [[ "$flag" == 1 ]]; then
                               [[ -f "$path" && "$path" -ot "$cache" ]] || stale=1
                           else
                               [[ ! -e "$path" ]] || stale=1
                           fi ;;
                "$_AGENTS_MCP_CACHE_V"$'\t'*) built="${line#*$'\t'}" ;;
            esac
        done < "$cache"
    fi
    if [[ ! "$built" =~ ^[0-9]+$ ]]; then
        stale=1 rows=""; [[ "${1:-}" == sync ]] || set -- sync
    fi
    if [[ -n "$stale" ]]; then
        if [[ "${1:-}" == sync ]]; then
            _agents_mcp_refresh rows
        else
            _agents_now now
            [[ $((now - built)) -lt 30 ]] || _agents_detach _agents_mcp_refresh
        fi
    fi
    _AGENTS_MCP_ROWS="$rows"
}

# _agents_mcp_needles VAR — set VAR to the AGENTS_MCP that
# awk/lib_activity.awk reads: "needle<TAB>name<TAB>cli" lines, longest
# needle first (servers without a needle, such as http ones, left out).
_agents_mcp_needles() {
    local _l _out="" cli scope name src proj type nd en
    _agents_mcp_load
    while IFS=$'\t' read -r _l cli scope name src proj type nd en; do
        [[ "$_l" == srv && -n "$nd" && "$nd" != - ]] && _out+="$nd"$'\t'"$name"$'\t'"$cli"$'\n'
    done <<<"$_AGENTS_MCP_ROWS"
    printf -v "$1" '%s' "$_out"
}

# agents_mcp_configured [DIR] — see the header.
agents_mcp_configured() {
    local dir="${1:-}" l cli scope name src proj type nd en
    _agents_mcp_load sync
    while IFS=$'\t' read -r l cli scope name src proj type nd en; do
        [[ "$l" == srv ]] || continue
        case "$scope" in local|project) [[ -z "$dir" || "$proj" == "$dir" ]] || continue ;; esac
        printf '%s\t%s\t%s\t%s\t%s\n' "$cli" "$scope" "$name" "$src" "${en:-1}"
    done <<<"$_AGENTS_MCP_ROWS"
}

# _agents_mcp_lookup NAME [CLI] — "cli<TAB>scope<TAB>source<TAB>type<TAB>
# needle" for each configured server called NAME (those of CLI first).
_agents_mcp_lookup() {
    local l cli scope name src proj type nd en mine="" rest=""
    _agents_mcp_load
    while IFS=$'\t' read -r l cli scope name src proj type nd en; do
        [[ "$l" == srv && "$name" == "$1" ]] || continue
        if [[ "$cli" == "${2:-}" ]]; then mine+="$cli"$'\t'"$scope"$'\t'"$src"$'\t'"$type"$'\t'"$nd"$'\n'
        else rest+="$cli"$'\t'"$scope"$'\t'"$src"$'\t'"$type"$'\t'"$nd"$'\n'; fi
    done <<<"$_AGENTS_MCP_ROWS"
    printf '%s%s' "$mine" "$rest"
}

# agents_mcp [DIR] — `agents mcp`: the configured servers (with DIR, those a
# session started in DIR loads), what starts each and where it is configured.
agents_mcp() {
    local dir="" l cli scope name src proj type nd en t='~' n=0
    case "${1:-}" in
        -*) echo "usage: agents mcp [DIR]" >&2; return 2 ;;
        ?*) dir="$(cd "$1" 2>/dev/null && pwd -P)" || { echo "agents: no such directory: $1" >&2; return 2; } ;;
    esac
    _agents_mcp_load sync
    printf '%s%-22s %-6s %-8s %-6s %-34s %s%s\n' "$C_DIM" NAME CLI SCOPE TYPE "STARTS WITH" SOURCE "$C_0"
    while IFS=$'\t' read -r l cli scope name src proj type nd en; do
        [[ "$l" == srv ]] || continue
        case "$scope" in local|project) [[ -z "$dir" || "$proj" == "$dir" ]] || continue ;; esac
        [[ "$nd" == - && "$type" == http ]] && nd="(a URL)"
        printf '%-22s %-6s %-8s %-6s %-34s %s\n' "$name" "$cli" "$scope" "$type" "${nd/#"$HOME"/$t}" "${src//"$HOME"/$t}"
        n=$((n + 1))
    done <<<"$_AGENTS_MCP_ROWS"
    [[ $n -gt 0 ]] || echo "no MCP servers configured${dir:+ for $dir}$(command -v jq >/dev/null 2>&1 || echo " (install jq to read Claude Code's)")"
}
