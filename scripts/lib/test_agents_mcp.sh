#!/bin/bash
# Unit tests for the MCP inventory (lib/agents/mcp.sh, awk/mcp.awk,
# awk/mcp_toml.awk) and the names MCP-server processes go by
# (awk/lib_activity.awk's mcp_name).
# Run: bash scripts/lib/test_agents_mcp.sh  -> exit 0 on pass.
#
# Fixture configs in a throwaway HOME: Claude Code's .claude.json (user and
# local scope), a project's .mcp.json, an enabled and a disabled plugin,
# Codex's config.toml. Every one carries secrets (env, headers, tokens in
# args, URLs) that must never reach the cache or any output.

# Tests change settings inside ( … ) on purpose; stubs are called indirectly.
# shellcheck disable=SC2030,SC2031,SC2016,SC2329
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/tuidev-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home" NO_COLOR=1
unset CLAUDE_CONFIG_DIR CODEX_HOME
mkdir -p "$HOME"
export AGENTS_TESTING=1 AGENTS_SELF=7000 AGENTS_UID=501 AGENTS_CONF="$tmp/none.conf"
export AGENTS_RUN_DIR="$tmp/run" AGENTS_DATA_DIR="$tmp/data"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "PASS: $1"; }

# shellcheck source=../../bin/agents disable=SC1091
. "$REPO_DIR/bin/agents"

SECRETS="sk-live-SECRET1 ghp_SECRET2 SECRET3-header SECRET4-env SECRET5-url SECRET6-codex SECRET7-from"

# --- awk/mcp.awk: the needle of a command line, from raw records ----------------------
needle_of() {   # COMMAND ARG... — the needle awk/mcp.awk picks
    local IFS=$'\037'
    printf 'claude\tuser\tx\tsrc\t-\t-\tstdio\t%s\t%s\n' "$1" "${*:2}" | _agents_awk mcp | cut -f8
}
[[ "$(needle_of npx -y @playwright/mcp@latest --headless)" == @playwright/mcp ]]          || fail "npx scoped package"
[[ "$(needle_of npx -y chrome-devtools-mcp@latest)" == chrome-devtools-mcp ]]             || fail "npx package"
[[ "$(needle_of /usr/local/bin/npx --registry https://r.example -y mcp-x@1.2)" == mcp-x ]] || fail "npx with a flag that takes a value"
[[ "$(needle_of npm exec @scope/srv@2)" == @scope/srv ]]                                    || fail "npm exec"
[[ "$(needle_of uvx mcp-server-fetch==1.0)" == mcp-server-fetch ]]                          || fail "uvx with a version spec"
[[ "$(needle_of uvx --from "git+https://u:SECRET7-from@h/r" mcp-git)" == mcp-git ]]         || fail "uvx --from a URL is skipped"
[[ "$(needle_of uv tool run mcp-y)" == mcp-y ]]                                              || fail "uv tool run"
[[ "$(needle_of node /opt/srv/dist/index.js --token sk-live-SECRET1)" == /opt/srv/dist/index.js ]] || fail "node script"
[[ "$(needle_of python3 -m my_server --key x)" == my_server ]]                               || fail "python -m"
[[ "$(needle_of docker run -i --rm -e GITHUB_TOKEN ghcr.io/github/github-mcp-server)" == ghcr.io/github/github-mcp-server ]] || fail "docker image"
[[ "$(needle_of "/Applications/X.app/Contents/MacOS/SkyClient" mcp)" == SkyClient ]]        || fail "a program's own name"
[[ "$(needle_of node)" == - && "$(needle_of npx -y)" == - ]]                                 || fail "an interpreter alone names nothing"
[[ "$(needle_of node index.js)" == - ]]                                                      || fail "a generic script name names nothing"
[[ "$(needle_of npx "--api-key=sk-live-SECRET1")" == - ]]                                    || fail "a flag is never a needle"
printf 'claude\tplugin\tp\tp@m\t-\t/plug/root\tstdio\tnode\t${CLAUDE_PLUGIN_ROOT}/server.js\n' | _agents_awk mcp | grep -q $'\t/plug/root/server.js\t1$' \
    || fail "\${CLAUDE_PLUGIN_ROOT} is the plugin's install path"
pass "needles: npx/uvx/npm exec packages without versions, scripts, python -m, docker images, programs; flags, URLs and interpreters never"

# --- Fixture configs -----------------------------------------------------------------
proj="$tmp/work/app"; other="$tmp/work/other"
mkdir -p "$proj" "$other" "$HOME/.claude/plugins/cache/m/pw/1" "$HOME/.claude/plugins/cache/m/off/1" "$HOME/.codex"
jq -n --arg proj "$proj" --arg other "$other" '{
  numStartups: 3,
  mcpServers: {
    "chrome-devtools": {type: "stdio", command: "npx", args: ["-y", "chrome-devtools-mcp@latest", "--token", "sk-live-SECRET1"], env: {API_KEY: "SECRET4-env"}},
    "remote": {type: "http", url: "https://mcp.example.com/mcp?key=SECRET5-url", headers: {Authorization: "Bearer SECRET3-header"}}
  },
  projects: {
    ($proj): {mcpServers: {"app-db": {command: "node", args: ["/srv/app-db/index.js", "ghp_SECRET2"]}}},
    ($other): {mcpServers: {}}
  }}' > "$HOME/.claude.json"
jq -n '{mcpServers: {"files": {command: "npx", args: ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"]}}}' > "$proj/.mcp.json"
jq -n '{enabledPlugins: {"pw@m": true, "off@m": false}}' > "$HOME/.claude/settings.json"
jq -n --arg r "$HOME/.claude/plugins/cache/m" '{version: 2, plugins: {
  "pw@m": [{scope: "user", installPath: ($r + "/pw/1")}],
  "off@m": [{scope: "user", installPath: ($r + "/off/1")}]}}' > "$HOME/.claude/plugins/installed_plugins.json"
jq -n '{playwright: {command: "npx", args: ["@playwright/mcp@latest"]}}' > "$HOME/.claude/plugins/cache/m/pw/1/.mcp.json"
jq -n '{mcpServers: {offsrv: {command: "off-mcp"}}}' > "$HOME/.claude/plugins/cache/m/off/1/.mcp.json"
cat > "$HOME/.codex/config.toml" <<'EOF'
model = "x"

[mcp_servers.playwright]
command = "npx"
args = ["-y", "@playwright/mcp@latest", "--cdp-endpoint=chrome"]

[mcp_servers.playwright.tools.browser_click]
approval_mode = "approve"

[mcp_servers."node repl"]
command = "/Applications/Some.app/Contents/Resources/node_repl"   # a comment
args = [
  "--secret", "SECRET6-codex",
]

[mcp_servers.node_repl.env]
TOKEN = "SECRET6-codex"
enabled = false   # a sub-table key: not the server's

[mcp_servers.docs]
url = "https://docs.example.com/mcp?k=SECRET5-url"
enabled = false   # off, but still configured

[profiles.fast]
command = "not-a-server"
EOF

if ! command -v jq >/dev/null 2>&1; then
    echo "SKIP: jq not installed (the fixtures and Claude Code's configs need it)"
    echo "All agents MCP tests passed."
    exit 0
fi

# --- The inventory --------------------------------------------------------------------
want="$(printf '%s\n' \
    "claude	local	app-db	$HOME/.claude.json:$proj	1" \
    "claude	user	chrome-devtools	$HOME/.claude.json	1" \
    "claude	project	files	$proj/.mcp.json	1" \
    "claude	plugin	playwright	pw@m	1" \
    "claude	user	remote	$HOME/.claude.json	1" \
    "codex	user	docs	$HOME/.codex/config.toml	0" \
    "codex	user	node repl	$HOME/.codex/config.toml	1" \
    "codex	user	playwright	$HOME/.codex/config.toml	1" | LC_ALL=C sort)"
got="$(agents_mcp_configured | LC_ALL=C sort)"
[[ "$got" == "$want" ]] || fail "configured servers:"$'\n'"$got"$'\n'"want:"$'\n'"$want"
[[ "$(agents_mcp_configured "$other" | cut -f3 | LC_ALL=C sort | tr '\n' ' ')" == "chrome-devtools docs node repl playwright playwright remote " ]] \
    || fail "a session in another project loads only user and plugin servers: $(agents_mcp_configured "$other" | cut -f3 | tr '\n' ' ')"
[[ "$(agents_mcp_configured "$proj" | cut -f3 | grep -c -e app-db -e files)" == 2 ]] || fail "a session in the project loads its local and project servers"
[[ "$(agents_mcp_configured | awk -F '\t' '$5 == 0 { printf "%s ", $3 }')" == "docs " ]] || fail "only Codex's docs (enabled = false) is off; a sub-table's enabled is not its server's"
pass "inventory: user, local, project and enabled-plugin servers from Claude Code, Codex's [mcp_servers.NAME] tables with their enabled flag; a disabled plugin left out"

cache="$AGENTS_RUN_DIR/mcp.tsv"
[[ -f "$cache" ]] || fail "no cache written"
[[ "$(stat -c %a "$cache" 2>/dev/null || stat -f %Lp "$cache")" == 600 ]] || fail "the cache is not private"
for s in $SECRETS; do
    ! grep -q -- "$s" "$cache" || fail "the cache holds a secret: $s"
done
! grep -q 'mcp.example.com\|docs.example.com' "$cache" || fail "the cache holds a URL"
out="$(agents_mcp 2>&1; agents_mcp_configured; _agents_mcp_needles n; printf '%s\n' "$n")"
for s in $SECRETS; do
    [[ "$out" != *"$s"* ]] || fail "output shows a secret: $s"
done
pass "the cache is private, and no arg past the needle, env, header or URL reaches it or any output"

_agents_mcp_needles n
[[ "$(printf '%s\n' "$n" | head -1)" == $'@modelcontextprotocol/server-filesystem\tfiles\tclaude' ]] \
    || fail "needles: longest first: $(printf '%s\n' "$n" | head -1)"
printf '%s\n' "$n" | grep -q $'^@playwright/mcp\tplaywright\tclaude$' || fail "plugin needle"
printf '%s\n' "$n" | grep -q $'^@playwright/mcp\tplaywright\tcodex$' || fail "codex needle"
! printf '%s\n' "$n" | grep -q -e $'\tremote\t' -e $'\tdocs\t' || fail "an http server has a needle"
pass "needles for classify: longest first, one per CLI, none for http servers"

# --- Cache: rebuilt when a config changes, appears or goes away -------------------------
# builds: how many times the inventory was built (it runs in a subshell).
eval "$(declare -f _agents_mcp_build | sed '1s/_agents_mcp_build/_agents_mcp_build_real/')"
_agents_mcp_build() { echo x >> "$tmp/builds"; _agents_mcp_build_real; }
builds() { build_count=0; [[ ! -f "$tmp/builds" ]] || build_count="$(grep -c . "$tmp/builds")"; }
_agents_mcp_load sync; builds; [[ $build_count == 0 ]] || fail "an unchanged cache was rebuilt"
sleep 1; touch "$proj/.mcp.json"
_agents_mcp_load sync; builds; [[ $build_count == 1 ]] || fail "a changed project .mcp.json did not rebuild the cache"
jq -n '{mcpServers: {late: {command: "late-mcp"}}}' > "$other/.mcp.json"
_agents_mcp_load sync; builds; [[ $build_count == 2 ]] || fail "a new project .mcp.json did not rebuild the cache"
printf '%s' "$_AGENTS_MCP_ROWS" | grep -q $'\tlate\t' || fail "the new server is missing"
# Classifying never waits: a stale cache is used as is, rebuilt in the background,
# at most every 30 s.
detached=""
_agents_detach() { detached+="$* "; }
sleep 1; touch "$HOME/.claude.json"
_agents_mcp_load; builds; [[ $build_count == 2 && -z "$detached" ]] || fail "a cache built under 30 s ago was rebuilt ($build_count, $detached)"
( export AGENTS_TESTING=1 AGENTS_NOW=$(( $(date +%s) + 60 )); _agents_mcp_load; builds; [[ $build_count == 2 && "$detached" == "_agents_mcp_refresh " ]] ) \
    || fail "an old stale cache was not rebuilt in the background"
printf '%s' "$_AGENTS_MCP_ROWS" | grep -q $'\tlate\t' || fail "the stale rows were not used meanwhile"
unset -f _agents_detach; . "$REPO_DIR/lib/agents/util.sh"
rm -f "$cache"
_agents_mcp_load; builds; [[ $build_count == 3 ]] || fail "the first build is not waited for"
pass "cache: rebuilt when a config changes or appears; classify uses a stale one and rebuilds it in the background, at most every 30 s"

# --- Without jq: Codex's servers only ----------------------------------------------------
mkdir -p "$tmp/nojq"
for t in awk sed sort cat mkdir mv rm ps date chmod head sh; do
    p="$(command -v "$t")" && ln -sf "$p" "$tmp/nojq/$t"
done
got="$(PATH="$tmp/nojq" AGENTS_RUN_DIR="$tmp/run-nojq" agents_mcp_configured | cut -f1,3 | LC_ALL=C sort | tr '\t\n' ': ')"
[[ "$got" == "codex:docs codex:node repl codex:playwright " ]] || fail "without jq: $got"
pass "without jq only Codex's servers are known (its TOML is read by awk)"

# --- Which process is which ----------------------------------------------------------------
psl() { printf '%5s %5s   501 me    0.0  90000  0:00.50 50:00 Wed Oct 14 08:10:00 2026     %s\n' "$@"; }
snap="$(
    psl 900 1 "-zsh"
    psl 1000 900 "claude"
    psl 1001 1000 "npm exec @playwright/mcp@latest"
    psl 1002 1000 "node /srv/app-db/index.js"
    psl 1003 1000 "npm exec @modelcontextprotocol/server-filesystem /tmp"
    psl 1004 1000 "/Users/NAME/.npm/_npx/x/node_modules/.bin/mcp-server-fetch"
    psl 2000 900 "codex"
    psl 2001 2000 "npx -y @playwright/mcp@latest --cdp-endpoint=chrome"
    psl 2002 2000 "/Applications/Some.app/Contents/Resources/node_repl --x"
    psl 3000 1 "npm exec chrome-devtools-mcp@latest"
)"
recs="$(printf '%s\n' "$snap" | agents_classify "" "")"
name_of() { printf '%s\n' "$recs" | awk -F '\t' -v p="$1" '$1 == "act" && $2 == p { print $3 ":" $12 }'; }
[[ "$(name_of 1001)" == mcp:playwright ]] || fail "plugin server: $(name_of 1001)"
[[ "$(name_of 1002)" == mcp:app-db ]]     || fail "a configured server without mcp in its command line: $(name_of 1002)"
[[ "$(name_of 1003)" == mcp:files ]]      || fail "project server: $(name_of 1003)"
[[ "$(name_of 1004)" == mcp:fetch ]]      || fail "an unconfigured server by its package: $(name_of 1004)"
[[ "$(name_of 2001)" == mcp:playwright ]] || fail "codex server: $(name_of 2001)"
[[ "$(name_of 2002)" == "mcp:node repl" ]] || fail "codex program server: $(name_of 2002)"
printf '%s\n' "$recs" | awk -F '\t' '$1 == "job" && $3 == "mcp" && $11 == 3000 { f = ($14 == "chrome-devtools") } END { exit !f }' \
    || fail "a stale server's job row does not carry its name"
printf '%s\n' "$recs" | awk -F '\t' '$1 == "job" && $11 == 1002 { f = ($3 == "mcp" && $14 == "app-db") } END { exit !f }' \
    || fail "a configured server's job is not mcp"
pass "MCP processes go by their configured name (the owner's CLI first), else their package's (fetch, chrome-devtools); job rows carry it"

# The fallback names, without any configuration.
tidy() { _agents_awk_eval "lib_proc lib_activity" 'BEGIN { print mcp_name(ENVIRON["A"], "") }'; }
for pair in "npm exec @playwright/mcp@latest=playwright" "npm exec chrome-devtools-mcp@latest=chrome-devtools" \
            "npx -y @modelcontextprotocol/server-filesystem /tmp=filesystem" "uvx mcp-server-fetch=fetch" \
            "node /h/.local/lib/example-agent-mcp.cjs=example-agent" "node /h/_npx/a/node_modules/@scope/mcp/cli.js=scope" \
            "/usr/local/bin/github-mcp-server stdio=github" "/opt/bin/mcp-server=mcp-server"; do
    [[ "$(AGENTS_MCP="" A="${pair%=*}" tidy)" == "${pair##*=}" ]] || fail "fallback name of ${pair%=*}: $(AGENTS_MCP="" A="${pair%=*}" tidy)"
done
pass "fallback names: @scope/mcp → scope, -mcp and mcp-server- trimmed, node_modules paths by package"

out="$(agents_main mcp 2>&1)"
[[ "$out" == *"$(printf '%-22s %-6s %-8s %-6s %-34s %s' playwright claude plugin stdio @playwright/mcp pw@m)"* ]] || fail "agents mcp: $out"
[[ "$out" == *"$(printf '%-22s %-6s %-8s %-6s %-34s' remote claude user http "(a URL)")"* ]] || fail "agents mcp: an http server"
[[ "$(agents_main mcp "$other")" != *app-db* ]] || fail "agents mcp DIR shows another project's server"
pass "agents mcp lists the servers, what starts each and where it is configured"

echo "All agents MCP tests passed."
