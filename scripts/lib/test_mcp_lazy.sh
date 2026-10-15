#!/bin/bash
# Unit tests for bin/mcp-lazy, the stand-in that starts a stdio MCP server
# on its first tool call, against a fake server
# (testdata/mcp_fake_server.pl) that logs what it is sent.
# Run: bash scripts/lib/test_mcp_lazy.sh  -> exit 0 on pass.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
LAZY="$REPO_DIR/bin/mcp-lazy"
FAKE="$SCRIPT_DIR/testdata/mcp_fake_server.pl"

if ! perl -MJSON::PP -MDigest::SHA -e 1 2>/dev/null; then
    echo "SKIP: mcp-lazy needs perl with JSON::PP and Digest::SHA"
    exit 0
fi

tmp="$(mktemp -d "${TMPDIR:-/tmp}/tuidev-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
export MCP_LAZY_CACHE="$tmp/cache" MCP_LAZY_GRACE=0.3 FAKE_LOG="$tmp/log"
unset MCP_LAZY MCP_LAZY_DEBUG FAKE_TOOLS FAKE_CHILD FAKE_STUBBORN FAKE_INIT_FAIL

fail() { echo "FAIL: $1" >&2; [[ -f "$tmp/out" ]] && sed 's/^/  out: /' "$tmp/out" | cut -c1-200 >&2; exit 1; }
pass() { echo "PASS: $1"; }

# A newer client's probe first (the fake answers it "no such method").
DISCOVER='{"jsonrpc":"2.0","id":"probe-1","method":"server/discover","params":{"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28"}}}'
INIT='{"jsonrpc":"2.0","id":0,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"t","version":"1"}}}'
INITED='{"jsonrpc":"2.0","method":"notifications/initialized"}'
LIST='{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
call() { printf '{"jsonrpc":"2.0","id":%s,"method":"tools/call","params":{"name":"%s","arguments":{"q":"hi"}}}' "$1" "$2"; }

# session LINE... — one session of mcp-lazy over the fake server: each line
# sent in turn ("@N" waits N seconds), its output in $tmp/out.
session() {
    local l
    { for l in "$@"; do
          case "$l" in @*) sleep "${l#@}" ;; *) printf '%s\n' "$l" ;; esac
      done; } | perl "$LAZY" --name fake -- perl "$FAKE" --token SECRET1 > "$tmp/out"
}
starts() { grep -c '^start' "$FAKE_LOG" 2>/dev/null || true; }
has() { grep -q -- "$1" "$tmp/out"; }

# --- the first session: no cache, so the server starts with it ---------------
session "$DISCOVER" "$INIT" "$INITED" "$LIST" "$(call 2 echo)" @0.5
[[ "$(starts)" == 1 ]]                               || fail "no cache: the server starts once"
{ has '"id":0}' && has '"name":"a"' && has '"q'; }        || fail "no cache: initialize, tools/list and the call are answered"
files=("$MCP_LAZY_CACHE"/fake-*.json)
[[ -f "${files[0]}" && ${#files[@]} == 1 ]]          || fail "no cache: one cache file, named after the server"
grep -q SECRET1 "${files[0]}" && fail "the cache holds no args"
[[ "${files[0]}" != *SECRET1* ]]                     || fail "the cache's name holds no args"
[[ "$(perl -e 'printf "%o", (stat shift)[2] & 07777' "$MCP_LAZY_CACHE")" == 700 ]] || fail "the cache dir is private"
pass "first session: the server starts and fills the cache"

# --- a session that only lists: the server never starts ----------------------
: > "$FAKE_LOG"
session "$DISCOVER" "$INIT" "$INITED" "$LIST" '{"jsonrpc":"2.0","id":9,"method":"ping"}' @0.3
[[ "$(starts)" == 0 ]]                               || fail "cached: the server does not start"
has '"error":{"code":-32601,"message":"no such method"},"id":"probe-1"' || fail "cached: server/discover gets the server's answer"
has '"listChanged":true'                             || fail "cached: initialize promises list_changed"
{ has '"name":"b"' && has '"id":9,"jsonrpc":"2.0","result":{}'; } || fail "cached: tools/list and ping are answered"
pass "cached session: server/discover, initialize, tools/list and ping without a server"

# --- its first call starts the server, which is initialized first ------------
: > "$FAKE_LOG"
session "$INIT" "$INITED" "$LIST" @0.2 "$(call '"c-1"' echo)" @0.8
[[ "$(starts)" == 1 ]]                               || fail "a call starts the server"
[[ "$(grep recv "$FAKE_LOG" | tr '\n' ' ')" == "recv initialize recv notifications/initialized recv tools/list recv tools/call " ]] \
                                                    || fail "the server is initialized before the call: $(tr '\n' ' ' < "$FAKE_LOG")"
{ has '"id":"c-1"' && has 'q'; }                          || fail "the call's answer reaches the session"
has 'mcp-lazy:' && fail "mcp-lazy's own requests never reach the session"
has 'list_changed' && fail "unchanged tools: no list_changed"
pass "first call: the server starts, is initialized, answers"

# --- changed tools: the cache is replaced and the session told ---------------
: > "$FAKE_LOG"
FAKE_TOOLS=a,b,c session "$INIT" "$INITED" "$LIST" @0.2 "$(call 3 echo)" @0.8
has 'notifications/tools/list_changed'               || fail "changed tools: list_changed sent"
session "$INIT" "$INITED" "$LIST" @0.3
has '"name":"c"'                                     || fail "changed tools: the next session gets them from the cache"
pass "changed tools: list_changed, and the cache updated"

# --- another protocol version: passed through, the cache remade --------------
: > "$FAKE_LOG"
session "${INIT/2025-06-18/2099-01-01}" "$INITED" "$LIST" @0.5
{ [[ "$(starts)" == 1 ]] && has '"protocolVersion":"2099-01-01"'; } || fail "another protocol version starts the server"
pass "another protocol version: the server answers itself"

# --- two clients (Claude Code and Codex ask for different versions) share it ---
: > "$FAKE_LOG"
session "$INIT" "$INITED" "$LIST" @0.3
session "${INIT/2025-06-18/2099-01-01}" "$INITED" "$LIST" @0.3
[[ "$(starts)" == 0 ]] || fail "two protocol versions: each session is answered from the cache"
pass "two protocol versions: the cache keeps each one's answers"

# --- a kind of client is its capabilities too --------------------------------------
: > "$FAKE_LOG"
session "${INIT/\"capabilities\":\{\}/\"capabilities\":{\"elicitation\":{}\}}" "$INITED" "$LIST" @0.4
[[ "$(starts)" == 1 ]] || fail "a client with other capabilities is not given another's answers"
pass "a client with other capabilities: the server answers it, and the cache keeps both"

# --- --env: the values of the server's own variables are in the cache's key -------
: > "$FAKE_LOG"
envsession() { { printf '%s\n' "$INIT" "$INITED" "$LIST"; sleep 0.4; } | perl "$LAZY" --name fake --env FAKE_TOOLS -- perl "$FAKE" > "$tmp/out"; }
FAKE_TOOLS=x,y envsession; FAKE_TOOLS=x,y envsession; FAKE_TOOLS=z envsession
{ [[ "$(starts)" == 2 ]] && has '"name":"z"'; } || fail "--env: one cache per value of the variables named"
pass "--env: one cache per value of the server's own variables"

# --- a program found through PATH is known by the file it resolves to ---------
# (fnm gives each shell's node and npx a directory of its own.)
mkdir -p "$tmp/p1" "$tmp/p2" && printf '#!/bin/sh\nexec perl %s "$@"\n' "$FAKE" > "$tmp/fakesrv" && chmod +x "$tmp/fakesrv"
ln -s "$tmp/fakesrv" "$tmp/p1/fakesrv" && ln -s "$tmp/fakesrv" "$tmp/p2/fakesrv"
: > "$FAKE_LOG"
for d in p1 p2; do { printf '%s\n' "$INIT" "$INITED" "$LIST"; sleep 0.4; } | PATH="$tmp/$d:$PATH" perl "$LAZY" --name viapath -- fakesrv > "$tmp/out"; done
[[ "$(starts)" == 1 ]] || fail "a program through another PATH directory, the same file: one cache"
pass "a program found through PATH: one cache for the file it resolves to"

# --- a package or URL arg is no path: one cache whatever the directory ---------
: > "$FAKE_LOG"
mkdir -p "$tmp/d1" "$tmp/d2"
for d in d1 d2; do (cd "$tmp/$d" && { printf '%s\n' "$INIT" "$INITED" "$LIST"; sleep 0.4; } | perl "$LAZY" --name scoped -- perl "$FAKE" @scope/pkg https://x.example/a > "$tmp/out"); done
[[ "$(starts)" == 1 ]] || fail "@scope/pkg and a URL are no relative paths: one cache across directories"
: > "$FAKE_LOG"
printf 'x\n' > "$tmp/d1/here.cfg"; printf 'x\n' > "$tmp/d2/here.cfg"
for d in d1 d2; do (cd "$tmp/$d" && { printf '%s\n' "$INIT" "$INITED" "$LIST"; sleep 0.4; } | perl "$LAZY" --name rel -- perl "$FAKE" here.cfg > "$tmp/out"); done
[[ "$(starts)" == 2 ]] || fail "a file arg relative to the directory: a cache per directory"
pass "relative paths key the cache by directory; packages and URLs do not"

# --- the session closes stdin at once: its answers still come back ----------------
printf '%s\n' "$INIT" "$INITED" "$LIST" '{"jsonrpc":"2.0","id":9,"method":"ping"}' | perl "$LAZY" --name fake -- perl "$FAKE" > "$tmp/out"
{ has '"name":"b"' && has '"id":9,'; }               || fail "stdin's end: the cached answers are still written"
printf '%s\n' "$INIT" "$INITED" "$(call 12 echo)" | perl "$LAZY" --name fake -- perl "$FAKE" > "$tmp/out"
has '"id":12,"jsonrpc":"2.0","result"'                || fail "stdin's end: a request in flight is still answered"
pass "stdin's end: answers cached and in flight still reach the session"

# --- a new initialize answer replaces the cache's ------------------------------
FAKE_INSTR="use me well" session "$INIT" "$INITED" "$(call 13 echo)" @0.8
session "$INIT" "$INITED" @0.3
has '"instructions":"use me well"'                    || fail "the server's new initialize answer reaches the next session"
pass "a server's changed initialize answer replaces the cache's"

# --- a large answer passes whole -----------------------------------------------
session "${INIT/2025-06-18/2099-01-01}" "$INITED" "$(call 4 big)" @2
size="$(grep '"id":4}' "$tmp/out" | wc -c | tr -d ' ')"
[[ "$size" -gt 5242880 ]]                            || fail "a 5 MiB answer passes whole ($size bytes)"
pass "a 5 MiB answer passes through whole"

# --- the server crashes: its request fails, the next one restarts it ---------
: > "$FAKE_LOG"
session "$INIT" "$INITED" "$(call 4 echo)" @0.5 "$(call 5 crash)" @0.8 "$(call 6 echo)" @0.8
[[ "$(grep -c '"id":4,' "$tmp/out")" == 1 ]]         || fail "an answered request (its id first, then jsonrpc) gets no second answer when the server crashes"
has 'mcp-lazy: the server stopped (exit 3).*"id":5,' || fail "a crash fails the request in flight"
has '"id":6,"jsonrpc":"2.0","result"'                || fail "the next request is answered"
[[ "$(starts)" == 2 ]]                               || fail "the next request starts the server again"
session "$INIT" "$INITED" "$(call 14 bigrpc)" @1 "$(call 15 crash)" @0.8
[[ "$(grep -c '"id":14}' "$tmp/out")" == 1 ]]        || fail "a 2 MiB answer (jsonrpc first, the id last) gets no second answer when the server crashes"
pass "a crash fails its request; the next starts the server again"

# --- a server that cannot start or refuses initialize ------------------------
: > "$FAKE_LOG"
FAKE_INIT_FAIL=1 session "$INIT" "$INITED" "$(call 7 echo)" @0.8
has 'refused initialize: nope.*"id":7,'              || fail "a refused initialize fails the call"
{ printf '%s\n' "$INIT" "$INITED" "$(call 8 echo)"; sleep 0.5; } \
    | perl "$LAZY" --name fake -- "$tmp/nope" > "$tmp/out" 2>/dev/null
has 'mcp-lazy: the server stopped.*"id":8,'          || fail "a missing command fails the call"
pass "a server that refuses or is missing fails the call, not the session"

# --- the end of the session stops the server and what it started -------------
FAKE_CHILD="$tmp/child" session "$INIT" "$INITED" "$(call 9 echo)" @0.8
child="$(cat "$tmp/child")"
sleep 0.2
kill -0 "$child" 2>/dev/null && fail "the server's own process is stopped with it"
: > "$FAKE_LOG"
SECONDS=0
FAKE_STUBBORN=1 session "$INIT" "$INITED" "$(call 10 echo)" @0.8
[[ "$(grep -c eof "$FAKE_LOG")" == 1 && $SECONDS -lt 6 ]] || fail "a server that ignores stdin's end and TERM is killed"
pass "the session's end stops the server and its process group"

# --- TERM to mcp-lazy stops its server ------------------------------------------
mkfifo "$tmp/in"
FAKE_CHILD="$tmp/child2" perl "$LAZY" --name fake -- perl "$FAKE" < "$tmp/in" > "$tmp/out" &
lazy=$!
exec 3>"$tmp/in"
printf '%s\n' "$INIT" "$INITED" "$(call 11 echo)" >&3
for _ in 1 2 3 4 5 6 7 8 9 10; do [[ -s "$tmp/child2" ]] && break; sleep 0.2; done
kill "$lazy"
wait "$lazy" || true
exec 3>&-
kill -0 "$(cat "$tmp/child2")" 2>/dev/null && fail "TERM to mcp-lazy stops the server"
pass "TERM to mcp-lazy stops the server"

# --- TERM while it waits for a server to exit: it stops waiting ------------------
# (A client's shutdown: stdin's end, then TERM, then KILL, seconds apart.)
mkfifo "$tmp/in3"
MCP_LAZY_GRACE=6 FAKE_STUBBORN=1 FAKE_CHILD="$tmp/child3" perl "$LAZY" --name fake -- perl "$FAKE" < "$tmp/in3" > "$tmp/out" &
lazy=$!
exec 3>"$tmp/in3"
printf '%s\n' "$INIT" "$INITED" "$(call 16 echo)" >&3
for _ in 1 2 3 4 5 6 7 8 9 10; do [[ -s "$tmp/child3" ]] && grep -q '"id":16,' "$tmp/out" && break; sleep 0.2; done
exec 3>&-
sleep 0.5
SECONDS=0
kill "$lazy"
wait "$lazy" || true
[[ $SECONDS -lt 5 ]] || fail "TERM during the grace wait: stopped waiting (took ${SECONDS}s)"
kill -0 "$(cat "$tmp/child3")" 2>/dev/null && fail "TERM during the grace wait: the server's group is killed"
pass "TERM during the grace wait: the server's group is stopped at once"

# --- MCP_LAZY=0 runs the command itself ---------------------------------------------
: > "$FAKE_LOG"
{ printf '%s\n' "$INIT"; sleep 0.3; } | MCP_LAZY=0 perl "$LAZY" -- perl "$FAKE" > "$tmp/out"
{ [[ "$(starts)" == 1 ]] && has '"id":0}'; }              || fail "MCP_LAZY=0 runs the server directly"
perl "$LAZY" 2>/dev/null && fail "no command: usage, exit 2"
pass "MCP_LAZY=0 and usage"

echo "All mcp-lazy tests passed."
