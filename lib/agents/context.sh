# shellcheck shell=bash
# lib/agents/context.sh — what the agents' sessions are set up to load, for
# `agents report --view context` (report.sh; what they used comes from the
# token scan's uses.tsv): the Claude Code plugins in settings.json's
# enabledPlugins, with what each enabled one contributes, and the MCP
# servers in Codex's config.toml.
#
# Names and counts only. A config's values (an MCP server's command, args,
# env or headers) may hold secrets: they are never printed, stored or even
# selected. jq reads the JSON (without it the plugins are left out, and a
# note says so); awk reads only config.toml's table names and enabled
# flags. Only files under the Claude Code and Codex config directories are
# read, never a .env file or a credential path.
#
# Owns: the inventory, as lines report_context.awk reads (tab-separated):
#   plugin   NAME@MARKETPLACE ENABLED INSTALLED SKILLS AGENTS COMMANDS MCP HOOKS MCP_NAMES
#   codexmcp NAME ENABLED
#   note     TEXT
#   ENABLED, INSTALLED: 1 or 0; the counts, an enabled and installed
#   plugin's only ("-" otherwise); MCP_NAMES: its MCP servers,
#   comma-separated, or "-".
# Uses: config.sh (CLAUDE_CONFIG_DIR, CODEX_HOME defaults as tokens.sh has
#   them).
# Public: _agents_context_inventory.

# _agents_context_inventory — the inventory lines; nothing for what is not
# there.
_agents_context_inventory() {
    local cdir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}" toml="${CODEX_HOME:-$HOME/.codex}/config.toml" name on path counts inst
    if [[ -r "$cdir/settings.json" ]]; then
        if command -v jq >/dev/null 2>&1; then
            while IFS=$'\t' read -r name on path; do
                [[ -n "$name" ]] || continue
                # What a plugin brings is counted only while it is enabled.
                inst=0 counts=$'-\t-\t-\t-\t-\t-'
                ! _agents_context_installed "$cdir/plugins" "$path" || inst=1
                [[ "$on" != 1 || $inst != 1 ]] || counts="$(_agents_context_plugin "$cdir/plugins" "$path")"
                printf 'plugin\t%s\t%s\t%s\t%s\n' "$name" "$on" "$inst" "$counts"
            done < <(_agents_context_plugins "$cdir")
        else
            printf 'note\tjq not found: the Claude Code plugins are not listed\n'
        fi
    fi
    [[ ! -r "$toml" ]] || LC_ALL=C awk '
        # A server table: [mcp_servers.NAME] or [mcp_servers."NAME"]; its
        # sub-tables (.env, .headers) are never read.
        /^[ \t]*\[/ {
            t = $0; sub(/^[ \t]*\[[ \t]*/, "", t); sub(/[ \t]*\][ \t]*(#.*)?$/, "", t); cur = ""
            if (t !~ /^mcp_servers[.]/) next
            t = substr(t, 13)
            if (t ~ /^"[^"]*"$/) t = substr(t, 2, length(t) - 2)
            else if (index(t, ".")) next
            if (t !~ /^[A-Za-z0-9_.@:-]+$/ || length(t) > 64) next
            cur = t; if (!(t in on)) { o[++n] = t; on[t] = 1 }
            next
        }
        cur != "" && /^[ \t]*enabled[ \t]*=[ \t]*false/ { on[cur] = 0 }
        END { for (i = 1; i <= n; i++) printf "codexmcp\t%s\t%d\n", o[i], on[o[i]] }' "$toml" 2>/dev/null
    return 0
}

# _agents_context_plugins CLAUDE_DIR — "name<TAB>enabled<TAB>install path"
# for each plugin settings.json's enabledPlugins names (enabled 1 or 0; the
# path from plugins/installed_plugins.json, "-" when it has none). Plain
# names only.
_agents_context_plugins() {
    local inst="$1/plugins/installed_plugins.json"
    [[ -r "$inst" ]] || inst=/dev/null
    jq -r --slurpfile inst "$inst" '
        ($inst[0].plugins // {}) as $p
        | (.enabledPlugins // {}) | to_entries[]
        | select(.key | type == "string" and test("^[A-Za-z0-9._@+-]{1,128}$"))
        | [.key, (if .value == true then "1" else "0" end),
           ((($p[.key] // []) | if type == "array" then .[0].installPath else null end) // "-" | tostring)]
        | @tsv' "$1/settings.json" 2>/dev/null
}

# _agents_context_installed PLUGINS_DIR PATH — true when PATH is a plugin's
# directory inside PLUGINS_DIR (the only place a plugin is read).
_agents_context_installed() {
    case "$2" in "$1"/*) [[ -d "$2" && "$2" != */../* ]] ;; *) return 1 ;; esac
}

# _agents_context_plugin PLUGINS_DIR PATH — what the plugin installed at PATH
# (_agents_context_installed, else nothing is read) contributes:
#   SKILLS AGENTS COMMANDS MCP HOOKS MCP_NAMES
# skills: skills/*/SKILL.md; agents: agents/*.md; commands: commands/*.md
# (and a level deeper); MCP: the servers .mcp.json and plugin.json name;
# hooks: the events hooks/hooks.json hooks.
_agents_context_plugin() {
    local p="$2" n_sk n_ag n_cm n_mcp=0 mcp hooks
    _agents_context_installed "$1" "$p" || { printf -- '-\t-\t-\t-\t-\t-'; return 0; }
    n_sk="$(find "$p/skills" -mindepth 2 -maxdepth 2 -name SKILL.md 2>/dev/null | wc -l | tr -d ' ')"
    n_ag="$(find "$p/agents" -mindepth 1 -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')"
    n_cm="$(find "$p/commands" -mindepth 1 -maxdepth 2 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')"
    # Server names only: the keys of mcpServers (or of the whole .mcp.json).
    mcp="$(for f in "$p/.mcp.json" "$p/.claude-plugin/plugin.json"; do
            [[ -r "$f" ]] || continue
            jq -r 'if (.mcpServers | type) == "object" then .mcpServers | keys[]
                   elif (input_filename | test("[.]mcp[.]json$")) then (if type == "object" then keys[] else empty end)
                   else empty end' "$f" 2>/dev/null
        done | LC_ALL=C grep -E '^[A-Za-z0-9_.@:-]{1,64}$' | LC_ALL=C sort -u | paste -sd, -)"
    hooks="$( [[ -r "$p/hooks/hooks.json" ]] && jq -r '(.hooks // {}) | if type == "object" then keys | length else 0 end' "$p/hooks/hooks.json" 2>/dev/null)"
    [[ "$hooks" =~ ^[0-9]+$ ]] || hooks=0
    [[ -z "$mcp" ]] || n_mcp=$(( $(printf '%s' "$mcp" | tr -cd , | wc -c) + 1 ))
    printf '%s\t%s\t%s\t%s\t%s\t%s' "$n_sk" "$n_ag" "$n_cm" "$n_mcp" "$hooks" "${mcp:--}"
}
