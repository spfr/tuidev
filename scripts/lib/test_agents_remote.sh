#!/bin/bash
# Unit tests for the other-machines commands: lib/agents/remote.sh (machines,
# `agents ports`, push, open), forward.sh (`agents forward`) and link.sh
# (`agents link`: the fifo, a click, the watcher's requests), and the Herdr
# plugin that calls them (configs/herdr/plugins/tuidev-link).
# Run: bash scripts/lib/test_agents_remote.sh  -> exit 0 on pass.
#
# No network and no real ssh: AGENTS_SSH is a stand-in that records its
# arguments and plays the far end, AGENTS_OPEN records what would have been
# opened, AGENTS_BUSY_PORTS says which local ports are taken.

# Tests change variables inside ( … ) on purpose; the stand-ins for
# _agents_listeners, _agents_cwds and ps are called by the code under test;
# a $( ) in single quotes is a path that must stay unexpanded.
# shellcheck disable=SC2030,SC2031,SC2034,SC2329,SC2016,SC2013,SC2153,SC2010,SC2143
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/tuidev-test.XXXXXX")"
bg=""
drop_tmp=""
trap '[[ -z "$bg" ]] || kill $bg 2>/dev/null; rm -rf "$tmp"; [[ -z "$drop_tmp" ]] || rm -rf "$drop_tmp"' EXIT
for v in XDG_CONFIG_HOME XDG_STATE_HOME TUIDEV_STATE_DIR AGENTS_HISTORY AGENTS_LINK; do unset "$v"; done
export HOME="$tmp/home" NO_COLOR=1 TZ=UTC AGENTS_CONF="$tmp/none.conf" AGENTS_DATA_DIR="$tmp/data" AGENTS_RUN_DIR="$tmp/run"
export AGENTS_TESTING=1 AGENTS_NO_HERDR=1 AGENTS_REMOTE_HOSTS="devbox workbox"
NOW=1792170000
export AGENTS_NOW="$NOW" FAKE="$tmp/fake"
mkdir -p "$HOME" "$FAKE"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "PASS: $1"; }
T=$'\t'

# The stand-in ssh. It logs each call's arguments ($FAKE/ssh.log, one line a
# call) and answers by what it was asked: a control command (-O), a forward
# (-L: "up" is a marker file per control socket), or a remote command.
cat > "$tmp/ssh" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$FAKE/ssh.log"
sock="" op="" fwd="" args=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        -o|-S|-O|-L) [[ "$1" == -S ]] && sock="$2"; [[ "$1" == -O ]] && op="$2"; [[ "$1" == -L ]] && fwd="$2"; shift 2 ;;
        -*) shift ;;
        *)  args+=("$1"); shift ;;
    esac
done
target="${args[0]}" cmd="${args[1]:-}"
mark="$FAKE/up.${sock##*/}"
case "$op" in
    check) [[ -e "$mark" ]]; exit ;;
    exit)  rm -f "$mark"; exit 0 ;;
esac
if [[ -n "$fwd" ]]; then
    if [[ -e "$FAKE/refuse" ]]; then echo "Permission denied (publickey)." >&2; exit 255; fi
    : > "$mark"; exit 0
fi
case "$cmd" in
    *"link serve"*)  cat "$FAKE/serve.$target" 2>/dev/null || exit 255 ;;
    *"ports --tsv"*) cat "$FAKE/ports.$target" 2>/dev/null || exit 255 ;;
    *"map --rows"*)  cat "$FAKE/map.$target" 2>/dev/null || exit 255 ;;
    *'.local/bin/agents"'*) printf '%s|%s\n' "$target" "${args[*]:1}" >> "$FAKE/remote.log" ;;
    *"cat > "*)      name="${cmd##*/}"; cat > "$FAKE/pushed.$name"; echo "/srv/u/.cache/tuidev/drop/$name" ;;
    # A far end that swallows whatever stdin it is given, and sends its file
    # whole: the size cap and the caller's own stdin are this side's to keep.
    *"cat < "*)      cat >/dev/null; printf '%s\n' "$cmd" >> "$FAKE/fetch.log"; cat "$FAKE/file.$target" 2>/dev/null || exit 1 ;;
    *) exit 0 ;;
esac
EOF
cat > "$tmp/open" <<'EOF'
#!/bin/bash
printf '%s\n' "$1" >> "$FAKE/opened"
EOF
chmod +x "$tmp/ssh" "$tmp/open"
export AGENTS_SSH="$tmp/ssh" AGENTS_OPEN="$tmp/open" AGENTS_BUSY_PORTS=""

# shellcheck source=../../bin/agents disable=SC1091
. "$REPO_DIR/bin/agents"

opened() { cat "$FAKE/opened" 2>/dev/null || true; }
reset() { rm -f "$FAKE/opened" "$FAKE/ssh.log"; }

# --- 1. Machines -------------------------------------------------------------------------
[[ "$(_agents_machines)" == "devbox${T}devbox${T}0"$'\n'"workbox${T}workbox${T}0" ]] || fail "machines: $(_agents_machines)"
_agents_machine devbox && [[ "$_AGENTS_M_TARGET" == devbox ]] || fail "a machine by its label"
_agents_machine me@otherbox && [[ "$_AGENTS_M_LABEL" == me_otherbox && "$_AGENTS_M_TARGET" == me@otherbox ]] || fail "any ssh host is a machine"
out="$(_agents_machine 2>&1)" && fail "two machines and no name was not a question"
[[ "$out" == *"which machine? (devbox workbox)"* ]] || fail "which machine: $out"
( AGENTS_REMOTE_HOSTS=devbox; _agents_machine && [[ "$_AGENTS_M_LABEL" == devbox ]] ) || fail "the only machine is the default"
for bad in "-oProxyCommand=x" "a b" 'x;y' ""; do
    [[ -z "$bad" ]] || { _agents_machine "$bad" 2>/dev/null && fail "accepted the ssh target '$bad'"; }
done
_agents_conf_valid AGENTS_REMOTE_HOSTS "devbox me@workbox ssh://me@box:2222" || fail "valid AGENTS_REMOTE_HOSTS refused"
_agents_conf_valid AGENTS_REMOTE_HOSTS "-oProxyCommand=x" && fail "an option as a host passed the config check"
if command -v jq >/dev/null 2>&1; then
    mkdir -p "$tmp/bin"
    cat > "$tmp/bin/herdr" <<'EOF'
#!/bin/bash
[[ "$*" == "machine list --json" ]] || exit 1
echo '[{"id":"1","label":"Build box","target":"me@build","enabled":true,"selected":true},
       {"id":"2","label":"off","target":"off","enabled":false,"selected":false},
       {"id":"3","label":"evil","target":"-oProxyCommand=x","enabled":true,"selected":false}]'
EOF
    chmod +x "$tmp/bin/herdr"
    out="$(PATH="$tmp/bin:$PATH" AGENTS_NO_HERDR="" AGENTS_REMOTE_HOSTS="devbox" _agents_machines)"
    [[ "$out" == "Build_box${T}me@build${T}1"$'\n'"devbox${T}devbox${T}0" ]] || fail "Herdr's machines: $out"
    ( PATH="$tmp/bin:$PATH"; AGENTS_NO_HERDR=""; _agents_machine && [[ "$_AGENTS_M_LABEL" == Build_box ]] ) \
        || fail "the machine Herdr's window shows is not the default"
fi
pass "machines: Herdr's enabled ones and AGENTS_REMOTE_HOSTS; a target that could be an option is never one"

# --- 2. Forwards ---------------------------------------------------------------------------
out="$(agents_forward open devbox 5173)" || fail "forward open failed: $out"
[[ "$out" == "http://localhost:5173  ->  devbox:5173" ]] || fail "forward open said: $out"
[[ "$(opened)" == "http://localhost:5173" ]] || fail "the forwarded port was not opened: $(opened)"
grep -q -- "-L 127.0.0.1:5173:localhost:5173 devbox" "$FAKE/ssh.log" || fail "not loopback to loopback: $(cat "$FAKE/ssh.log")"
grep -q -- "-o BatchMode=yes" "$FAKE/ssh.log" || fail "ssh could prompt"
grep -q -- "-o ForwardAgent=no -o ForwardX11=no" "$FAKE/ssh.log" || fail "the tunnel could forward your ssh agent"
! grep -q -- "ClearAllForwardings" "$FAKE/ssh.log" || fail "the tunnel's own -L would be cleared"
grep -q -- "-o ExitOnForwardFailure=yes" "$FAKE/ssh.log" || fail "ssh could hide a failed forward"
[[ "$(cat "$AGENTS_RUN_DIR/forward/f.5173")" == "5173${T}devbox${T}devbox${T}5173${T}$NOW" ]] || fail "the record: $(cat "$AGENTS_RUN_DIR/forward/f.5173")"
reset
out="$(agents_forward open --no-open devbox 'http://127.0.0.1:5173/docs?a=1')" || fail "reuse failed"
[[ "$out" == "http://localhost:5173/docs?a=1  ->  devbox:5173" ]] || fail "a URL keeps its path: $out"
! grep -q -- "-L" "$FAKE/ssh.log" || fail "a live forward was opened again"
[[ -z "$(opened)" ]] || fail "--no-open opened"
# The same port of another machine: the next free local port. One in use
# here (3000) is skipped, and a port under 1024 starts at 10000 + PORT.
out="$(agents_forward open --no-open workbox 5173)"; [[ "$out" == "http://localhost:5174  ->  workbox:5173" ]] || fail "second machine: $out"
out="$(AGENTS_BUSY_PORTS="3000 3001" agents_forward open --no-open devbox 3000)"; [[ "$out" == "http://localhost:3002  ->  devbox:3000" ]] || fail "a busy local port: $out"
out="$(agents_forward open --no-open devbox https://localhost/)"; [[ "$out" == "https://localhost:10443/  ->  devbox:443" ]] || fail "a privileged port: $out"
for bad in "http://example.com:80/" "http://localhost:5173/a'b" "ftp://localhost/" "70000" "localhost:1" \
    "http://localhost:1@example.com/" "HTTP://localhost/" "http://localhost./" "http://[::ffff:127.0.0.1]/" \
    "http://localhost:0/" "http://localhost:123456/" "http://%6cocalhost/" 'http://localhost/$(id)' "http://localhost/a b"; do
    agents_forward open --no-open devbox "$bad" >/dev/null 2>&1 && fail "forwarded '$bad'"
done
out="$(agents_forward ls)"
[[ "$out" == *"http://localhost:5173   devbox:5173   active  0m"* && "$out" == *"workbox:5173  active"* ]] || fail "ls: $out"
# A forward whose ssh died is reported, replaced on the next open, and pruned.
rm -f "$FAKE/up.f.5173.sock"
[[ "$(agents_forward ls)" == *"devbox:5173   dead"* ]] || fail "a dead forward not shown as dead"
reset; agents_forward open --no-open devbox 5173 >/dev/null
grep -q -- "-L 127.0.0.1:5173:localhost:5173 devbox" "$FAKE/ssh.log" || fail "a dead forward was not reopened"
rm -f "$FAKE/up.f.5174.sock"
[[ "$(agents_forward close --dead)" == "closed localhost:5174 (workbox:5173)" ]] || fail "close --dead"
[[ "$(agents_forward close devbox 3000)" == "closed localhost:3002 (devbox:3000)" ]] || fail "close MACHINE PORT"
[[ "$(agents_forward close 5173)" == "closed localhost:5173 (devbox:5173)" ]] || fail "close LOCALPORT"
agents_forward close 5173 >/dev/null 2>&1 && fail "closing nothing succeeded"
agents_forward close --all >/dev/null
[[ "$(agents_forward ls)" == "no forwards"* ]] || fail "close --all left some: $(agents_forward ls)"
# ssh's own words when the tunnel does not come up; nothing recorded.
: > "$FAKE/refuse"
out="$(agents_forward open devbox 8080 2>&1)" && fail "a refused forward succeeded"
[[ "$out" == *"no tunnel to devbox:8080: Permission denied (publickey)."* && ! -e "$AGENTS_RUN_DIR/forward/f.8080" ]] || fail "refused: $out"
rm -f "$FAKE/refuse"
pass "forward: loopback only, the same port when free, reuse, dead ones replaced, close, ssh's error passed on"

# --- 3. A click with nobody attached opens here ---------------------------------------------------
reset
agents_link_click "http://localhost:5173/x" >/dev/null || fail "local click failed"
printf '# notes\n' > "$tmp/notes.md"; printf 'x\n' > "$tmp/run.command"; printf 'x\n' > "$tmp/my notes.md"
agents_link_click "file://thishost$tmp/notes.md" >/dev/null || fail "local file click failed"
agents_link_click "file://$tmp/my%20notes.md" >/dev/null || fail "a %20 in a file link"
[[ "$(opened)" == "http://localhost:5173/x"$'\n'"$tmp/notes.md"$'\n'"$tmp/my notes.md" ]] || fail "opened locally: $(opened)"
agents_link_click "file://$tmp/run.command" >/dev/null 2>&1 && fail "opened a .command file"
agents_link_click "file://$tmp/missing.md" >/dev/null 2>&1 && fail "opened a missing file"
agents_link_click "javascript:alert(1)" >/dev/null 2>&1 && fail "accepted a javascript: link"
agents_link_click "file:///a%zz.md" >/dev/null 2>&1 && fail "accepted a bad escape"
pass "link click, nobody attached: the URL or a viewer's file opens here; nothing else does"

# --- 4. serve and click: the request reaches the attached watcher ---------------------------
bash "$REPO_DIR/bin/agents" link serve > "$tmp/serve.out" 2>&1 &
bg=$!
for _ in $(seq 1 50); do [[ -s "$tmp/serve.out" ]] && break; sleep 0.1; done
[[ "$(head -1 "$tmp/serve.out")" == "tuidev-link 1" ]] || fail "serve did not say its protocol: $(cat "$tmp/serve.out")"
[[ -p "$AGENTS_RUN_DIR/link/l.$bg" ]] || fail "no fifo for the listener: $(ls "$AGENTS_RUN_DIR/link")"
reset
out="$(agents_link_click "http://localhost:5173/")" || fail "click with a listener failed"
[[ "$out" == "sent to the machine you are attached from" && -z "$(opened)" ]] || fail "attached: opened here instead ($out)"
agents_link_click "$tmp/notes.md" >/dev/null
# A URL no watcher would act on is not sent (and so not reported as sent).
out="$(agents_link_click 'https://example.com/' 2>&1)" || true
[[ "$out" != *"sent to"* ]] || fail "a URL the watcher refuses was reported as sent"
for _ in $(seq 1 50); do [[ "$(wc -l < "$tmp/serve.out")" -ge 3 ]] && break; sleep 0.1; done
[[ "$(sed -n 2,3p "$tmp/serve.out")" == "open-url${T}http://localhost:5173/"$'\n'"open-file${T}$tmp/notes.md" ]] || fail "requests: $(cat "$tmp/serve.out")"
! grep -q example.com "$tmp/serve.out" || fail "a refused URL reached the listener"
[[ "$(_agents_link_status)" == *"attached to this machine: 1"* ]] || fail "status does not count the listener"
kill "$bg"; wait "$bg" 2>/dev/null || true; bg=""
[[ ! -e "$AGENTS_RUN_DIR/link/l.$!" ]] || fail "the fifo outlived its listener"
# A fifo whose reader is gone is cleaned up, and the click opens here again.
mkfifo "$AGENTS_RUN_DIR/link/l.999999"
reset; agents_link_click "http://localhost:1/" >/dev/null
[[ "$(opened)" == "http://localhost:1/" && ! -e "$AGENTS_RUN_DIR/link/l.999999" ]] || fail "a dead listener swallowed the click"
pass "link serve: a fifo per listener; a click goes to it, and comes back here when it is gone"

# --- 5. The watcher: what a machine may ask for ---------------------------------------------------
reset
# The file request comes first: its fetch must not eat the requests after it.
printf '%s\n' "tuidev-link 1" ping "open-file${T}/srv/u/notes.md" "open-url${T}http://localhost:4000/app" "open-url${T}http://localhost:5432/" "open-url${T}http://example.com/" \
    "open-url${T}http://localhost:4000/\$(id)" "open-url${T}http://localhost:1@example.com/" "run${T}rm -rf /" "open-file${T}/srv/u/x.command" \
    "open-file${T}relative.md" "open-file${T}/srv/u/it's.md" > "$FAKE/serve.devbox"
printf '# remote notes\n' > "$FAKE/file.devbox"
_agents_link_session devbox devbox 2>"$tmp/err" || fail "session failed: $(cat "$tmp/err")"
[[ "$(opened)" == "$AGENTS_DATA_DIR/remote/devbox/notes.md"$'\n'"http://127.0.0.1:47000/app"$'\n'"http://127.0.0.1:47001/" ]] || fail "the watcher opened: $(opened)"
[[ "$(cat "$AGENTS_DATA_DIR/remote/devbox/notes.md")" == "# remote notes" ]] || fail "the fetched file"
# A port it asks for never becomes the same port here: localhost:5432 stays yours.
grep -q -- "-L 127.0.0.1:47001:localhost:5432 devbox" "$FAKE/ssh.log" || fail "a requested forward took the same local port: $(grep -- ' -L ' "$FAKE/ssh.log")"
[[ "$(grep -c -- ' -L ' "$FAKE/ssh.log")" -eq 2 ]] || fail "tunnels for refused requests: $(cat "$FAKE/ssh.log")"
[[ "$(wc -l < "$FAKE/fetch.log" | tr -d ' ')" -eq 1 ]] || fail "fetched a refused file: $(cat "$FAKE/fetch.log")"
[[ "$(cat "$FAKE/fetch.log")" == "[ -f '/srv/u/notes.md' ] && cat < '/srv/u/notes.md'" ]] || fail "the path is not quoted for the far shell: $(cat "$FAKE/fetch.log")"
[[ "$(cut -f1 "$AGENTS_RUN_DIR/link/h.devbox")" == disconnected ]] || fail "state after a session: $(cat "$AGENTS_RUN_DIR/link/h.devbox")"
agents_forward close --all >/dev/null
# A port nobody holds over there: no tab, and its forward is not kept.
cat > "$tmp/curl" <<'EOF2'
#!/bin/bash
exit 56
EOF2
chmod +x "$tmp/curl"
( reset; AGENTS_CURL="$tmp/curl"; AGENTS_NOW=$((NOW + 60)); _agents_link_handle devbox devbox "open-url${T}http://localhost:4100/" 2>/dev/null
  [[ -z "$(opened)" && "$(agents_forward ls)" == "no forwards"* ]] ) || fail "a tab was opened onto a port nothing answers on"
out="$(AGENTS_CURL="$tmp/curl" agents_forward open devbox 4101 2>&1)" || fail "your own forward to a quiet port failed"
[[ "$out" == *"nothing answers on devbox:4101 yet"* && "$(agents_forward ls)" == *"devbox:4101"* ]] || fail "a quiet port of your own forward: $out"
agents_forward close --all >/dev/null
# Five requests in ten seconds, then none until the window passes.
reset; { echo "tuidev-link 1"; for i in 1 2 3 4 5 6 7 8; do printf 'open-url\thttp://localhost:400%s/\n' "$i"; done; } > "$FAKE/serve.devbox"
_agents_link_session devbox devbox 2>/dev/null
[[ "$(opened | wc -l | tr -d ' ')" -eq 5 ]] || fail "rate limit: opened $(opened | wc -l)"
( _AGENTS_LINK_T="$NOW" _AGENTS_LINK_N=9; AGENTS_NOW=$((NOW + 11)); reset
  _agents_link_handle devbox devbox "open-url${T}http://localhost:4009/" 2>/dev/null
  [[ "$(opened)" == "http://127.0.0.1:47005/" ]] ) || fail "the rate limit's window did not pass"
# Eight forwards a machine by request; the ninth is refused. Yours are not capped.
( reset; for i in 1 2 3 4; do AGENTS_NOW=$((NOW + 20 * i)) _agents_link_handle devbox devbox "open-url${T}http://localhost:500$i/" 2>/dev/null; done
  [[ "$(grep -c -- ' -L ' "$FAKE/ssh.log")" -eq 2 ]] ) || fail "more than eight requested forwards for one machine"
agents_forward open --no-open devbox 6001 >/dev/null || fail "your own forward was capped"
agents_forward close --all >/dev/null
# The size cap is kept here: a far end that sends more is cut off and nothing is kept.
( reset; _AGENTS_OPEN_MAX=4; rm -rf "$AGENTS_DATA_DIR/remote"
  AGENTS_NOW=$((NOW + 200)) _agents_link_handle devbox devbox "open-file${T}/srv/u/big.md" 2>/dev/null
  [[ -z "$(opened)" && -z "$(ls "$AGENTS_DATA_DIR/remote/devbox" 2>/dev/null)" ]] ) || fail "a file past the cap was kept or opened"
# A line without an end is cut at 2048 characters and is no request.
reset; { echo "tuidev-link 1"; printf 'open-url\thttp://localhost:4000/'; head -c 5000 /dev/zero | tr '\0' a; echo; } > "$FAKE/serve.devbox"
_agents_link_session devbox devbox 2>/dev/null
[[ -z "$(opened)" ]] || fail "a 5000-character line was acted on: $(opened | cut -c1-80)"
# Not agents at the far end, or no answer: said so, nothing acted on.
reset; printf 'Welcome to devbox\nopen-url\thttp://localhost:1/\n' > "$FAKE/serve.devbox"
_agents_link_session devbox devbox 2>/dev/null && fail "a banner was taken for the protocol"
[[ -z "$(opened)" && "$(cut -f1 "$AGENTS_RUN_DIR/link/h.devbox")" == "no agents there" ]] || fail "wrong protocol: $(cat "$AGENTS_RUN_DIR/link/h.devbox")"
printf 'tuidev-link none\n' > "$FAKE/serve.devbox"
_agents_link_session devbox devbox 2>/dev/null && fail "a machine without agents link counted as a session"
[[ "$(cut -f1 "$AGENTS_RUN_DIR/link/h.devbox")" == "needs tuidev there"* ]] || fail "no link there: $(cat "$AGENTS_RUN_DIR/link/h.devbox")"
_agents_link_session workbox workbox 2>/dev/null && fail "an unreachable machine counted as a session"
[[ "$(cut -f1 "$AGENTS_RUN_DIR/link/h.workbox")" == unreachable ]] || fail "unreachable state"
[[ "$(AGENTS_LINK=0 _agents_link_watch)" == *"link is off"* ]] || fail "AGENTS_LINK=0 did not end the watcher"
# A watcher killed while it took its lock leaves a half-written holder file:
# after a minute the lock is taken over all the same, not held for ever.
mkdir -p "$tmp/stuck.lock"; : > "$tmp/stuck.lock/holder.4242"; touch -t 202601010000 "$tmp/stuck.lock/holder.4242" "$tmp/stuck.lock"
_agents_lock "$tmp/stuck.lock" || fail "a lock with only a half-written holder file is held for ever"
_agents_unlock "$tmp/stuck.lock"
agents_forward close --all >/dev/null
pass "link watch: loopback URLs on a port of its own choosing, viewers' files under a cap kept here, five in ten seconds, eight forwards, never a command"

# --- 6. Ports ------------------------------------------------------------------------------
_agents_listeners() { printf '%s 5173\n%s 9229\n' "$$" "$$"; }
_agents_cwds() { printf '%s\t%s\n' "$$" "$HOME/proj"; }
ps() { printf '%6s /usr/local/bin/node\n' "$$"; }   # as ps -o pid=,comm= prints it
out="$(agents_ports --tsv)"
[[ "$out" == "5173${T}$$${T}"*"${T}$HOME/proj"$'\n'"9229${T}$$${T}"* ]] || fail "ports --tsv: $out"
printf '8000\t77\tpython3\t/srv/app\n9000\tx;y\tev\033]0;PWNED\007il\t/srv/a\thttp://localhost:3000\nbad\t1\tsh\t/\n' > "$FAKE/ports.devbox"
agents_forward open --no-open devbox 8000 >/dev/null
out="$(agents_ports)"
[[ "$out" == *"MACHINE"*"PORT"*"OPEN AT"* ]] || fail "ports header: $out"
[[ "$out" == *"local     5173  node"*"http://localhost:5173"*"~/proj"* ]] || fail "local row: $out"
[[ "$out" == *"devbox    8000  python3"*"http://localhost:8000"*"/srv/app"* ]] || fail "remote row with its forward: $out"
[[ "$out" == *"workbox      -  no answer (ssh workbox)"* ]] || fail "a machine that did not answer: $out"
# What another machine says about itself is text: no escape reaches the
# terminal, and a column it adds does not become where the port opens.
[[ "$out" != *$'\033'* && "$out" != *$'\007'* && "$out" == *"devbox    9000  ev]0;PWNEDil"* ]] || fail "control characters from a machine's row: $(printf '%s' "$out" | cat -v)"
[[ "$(printf '%s\n' "$out" | grep ' 9000 ')" != *"http://"* && "$out" != *bad* ]] || fail "a machine's row faked its OPEN AT column: $out"
( AGENTS_REMOTE_HOSTS="local .."; [[ "$(_agents_machines | cut -f1 | tr '\n' ' ')" == "m-local " ]] ) || fail "a machine could be labelled local, or be the host .."
l=""; _agents_label l ".."; [[ "$l" == "m-.." ]] || fail "a label could be the directory .."
! agents_ports devbox | grep -q '^local ' || fail "ports MACHINE listed this machine"
# A port a forward holds here is not one of this machine's servers.
_agents_listeners() { printf '%s 5173\n%s 8000\n' "$$" "$$"; }
[[ "$(agents_ports --tsv)" != *8000* ]] || fail "a forward listed as a local server"
reset; agents_ports --go devbox 8000 >/dev/null; agents_ports --go local 5173 >/dev/null
[[ "$(opened)" == "http://localhost:8000"$'\n'"http://localhost:5173" ]] || fail "ports --go: $(opened)"
agents_forward close --all >/dev/null
pass "ports: this machine and the others, each with where it opens; --go forwards and opens"

# --- 7. Files ------------------------------------------------------------------------------
printf 'png-bytes' > "$tmp/shot 1.png"
out="$(agents_push -m devbox "$tmp/shot 1.png" 2>/dev/null)" || fail "push failed"
[[ "$out" == "/srv/u/.cache/tuidev/drop/shot_1.png" && "$(cat "$FAKE/pushed.shot_1.png")" == "png-bytes" ]] || fail "push: $out"
agents_push -m devbox "$tmp/absent" >/dev/null 2>&1 && fail "pushed a missing file"
agents_push "$tmp/shot 1.png" >/dev/null 2>&1 && fail "pushed without knowing which machine"
reset; printf 'hello\n' > "$FAKE/file.devbox"
out="$(agents_remote_open devbox /srv/app/report.html)" || fail "open failed"
[[ "$out" == "$AGENTS_DATA_DIR/remote/devbox/report.html" && "$(opened)" == "$out" ]] || fail "open: $out / $(opened)"
reset; out="$(agents_remote_open devbox /srv/app/tool.sh 2>&1)"
[[ -z "$(opened)" && "$out" == *"fetched, not opened"* ]] || fail "a script was opened: $out"
out="$(agents_push -m devbox "$tmp/"'$(id) -rf;.png' 2>/dev/null)" || true
: > "$tmp/"'$(id) -rf;.png'; out="$(agents_push -m devbox "$tmp/"'$(id) -rf;.png' 2>/dev/null)"
[[ "$out" == "/srv/u/.cache/tuidev/drop/__id__-rf_.png" ]] || fail "a hostile file name reached the far shell: $out"
for bad in 'relative.md' '/a/$(id).md' "/a/b'c.md" '/a/dir/'; do
    agents_remote_open devbox "$bad" >/dev/null 2>&1 && fail "fetched the path '$bad'"
done
( _AGENTS_OPEN_MAX=3; agents_remote_open devbox /srv/big.txt >/dev/null 2>&1 ) && fail "fetched past the size cap"
[[ ! -e "$AGENTS_DATA_DIR/remote/devbox/big.txt" && ! -e "$AGENTS_DATA_DIR/remote/devbox/big.txt.part" ]] || fail "an oversized file was kept"
pass "push and open: plain names in the drop folder; only a viewer's formats open, under the size cap"

# --- 7b. A dropped file: asked for, consented to, sent -------------------------------------
unset -f ps   # the ports test's stand-in: a listener is told from its real command line
# The pasted paths of a prompt: quoted, or with escaped spaces, anywhere in it.
out="$(_agents_link_drop_paths "see /Users/NAME/Desktop/Shot\\ 1\\ at\\ 10.00.png and '/Users/NAME/My Docs/plan v2.pdf', then /etc/passwd /home/dev/a.txt, /tmp/x.md. src/app.ts /Users/NAME/noext")"
[[ "$out" == "/Users/NAME/My Docs/plan v2.pdf"$'\n'"/Users/NAME/Desktop/Shot 1 at 10.00.png"$'\n'"/home/dev/a.txt"$'\n'"/tmp/x.md" ]] || fail "dropped paths: $out"
# A path inside another word is not an absolute path: src/tmp/x.json names no /tmp/x.json.
[[ -z "$(_agents_link_drop_paths "look at src/tmp/cache.json and app/home/user.ts, see docs(/tmp/a.md) x=/tmp/b.md")" ]] || fail "a relative path was read as absolute: $(_agents_link_drop_paths "look at src/tmp/cache.json and app/home/user.ts")"
# What may be offered at all: a plain file of yours, by its real path, nowhere hidden.
real_home="$(cd -P "$HOME" && pwd)"
# These files must be somewhere a file may be sent from. A test home under a
# hidden folder or a Library (a CI runner's cache directory) is not: then a
# folder under /tmp stands in for it as HOME, and without one this part is
# skipped.
drop_ok=true
case "$(printf '%s' "$real_home" | tr '[:upper:]' '[:lower:]')" in
    */.*|*/library/*)
        if alt="$(mktemp -d /tmp/tuidev-drop.XXXXXX 2>/dev/null)"; then
            real_home="$(cd -P "$alt" && pwd)"; drop_tmp="$alt"
        else
            drop_ok=false; echo "SKIP: what may be sent (the test home is under a hidden folder, and /tmp is not writable)"
        fi ;;
esac
if [[ "$drop_ok" == true ]]; then
    keep_home="$HOME"; HOME="$real_home"
    mkdir -p "$real_home/Desktop" "$real_home/.ssh" "$real_home/Library/Keychains" "$real_home/.config/gh"
    printf 'png' > "$real_home/Desktop/shot 1.png"; printf 'key' > "$real_home/.ssh/id_ed25519.pub"
    printf 'k' > "$real_home/Library/Keychains/login.db"; printf 't' > "$real_home/.config/gh/hosts.yml"
    ln -s "$real_home/.ssh/id_ed25519.pub" "$real_home/Desktop/innocent.txt"; ln -s "$real_home/.ssh" "$real_home/Desktop/dir"
    _agents_link_may_send "$real_home/Desktop/shot 1.png" || fail "a file on the Desktop may not be sent: $_AGENTS_LINK_WHY"
    mkdir -p "$real_home/Documents/Library"; printf 'x' > "$real_home/Documents/Library/notes.txt"
    lower="$(dirname "$real_home")/$(basename "$real_home" | tr '[:lower:]' '[:upper:]')"   # the same home, spelled in capitals
    for bad in "$real_home/.ssh/id_ed25519.pub" "$real_home/Library/Keychains/login.db" "$real_home/.config/gh/hosts.yml" \
        "$real_home/library/Keychains/login.db" "$real_home/LIBRARY/Keychains/login.db" "$real_home/Documents/Library/notes.txt" \
        "$lower/.SSH/id_ed25519.pub" "$tmp/../$(basename "$tmp")/${real_home##*/}/Desktop/shot 1.png" \
        "$real_home/Desktop/innocent.txt" "$real_home/Desktop/dir/id_ed25519.pub" "$real_home/Desktop/../.ssh/id_ed25519.pub" \
        "$real_home/Desktop/absent.png" "/etc/hosts" "relative.png" "$real_home/Desktop"; do
        _agents_link_may_send "$bad" && fail "may send '$bad'"
    done
    ( _AGENTS_OPEN_MAX=2; _agents_link_may_send "$real_home/Desktop/shot 1.png" ) && fail "a file past the size cap may be sent"
    # The watcher: nothing leaves without a yes; a yes sends it and answers where it landed.
    reset; rm -f "$FAKE/remote.log" "$FAKE"/pushed.*
    AGENTS_CONSENT=no _agents_link_handle devbox devbox "want-file${T}dabc123${T}$real_home/Desktop/shot 1.png" 2>/dev/null
    [[ -z "$(ls "$FAKE"/pushed.* 2>/dev/null)" && "$(sed 's/"$HOME\/.local\/bin\/agents" //' "$FAKE/remote.log")" == "devbox|link reply dabc123 no" ]] || fail "a declined file: $(cat "$FAKE/remote.log" 2>&1)"
    rm -f "$FAKE/remote.log"
    # After a no, that machine is not asked about again for five minutes: no dialog, whatever the answer would be.
    rm -f "$FAKE/remote.log"; _AGENTS_LINK_ASKED=0
    AGENTS_CONSENT=yes AGENTS_CONSENT_SLEEP=1 AGENTS_NOW=$((NOW + 100)) _agents_link_handle devbox devbox "want-file${T}dabc12a${T}$real_home/Desktop/shot 1.png" 2>/dev/null
    [[ "$_AGENTS_LINK_ASKED" -eq 0 && -z "$(ls "$FAKE"/pushed.* 2>/dev/null)" && "$(cat "$FAKE/remote.log")" == *"link reply dabc12a no" ]] || fail "asked again within five minutes of a no: asked=$_AGENTS_LINK_ASKED $(cat "$FAKE/remote.log" 2>&1)"
    rm -f "$FAKE/remote.log"
    AGENTS_CONSENT=yes AGENTS_NOW=$((NOW + 400)) _agents_link_handle devbox devbox "want-file${T}dabc124${T}$real_home/Desktop/shot 1.png" 2>/dev/null
    [[ "$(cat "$FAKE/pushed.shot_1.png")" == png ]] || fail "an approved file was not sent"
    [[ "$(sed 's/"$HOME\/.local\/bin\/agents" //' "$FAKE/remote.log")" == "devbox|link reply dabc124 ok /srv/u/.cache/tuidev/drop/shot_1.png" ]] || fail "the answer to an approved file: $(cat "$FAKE/remote.log")"
    # A file that may not be offered is refused before anyone is asked, whatever the answer would be.
    rm -f "$FAKE/remote.log" "$FAKE"/pushed.*
    _AGENTS_LINK_ASKED=0
    AGENTS_CONSENT=yes AGENTS_CONSENT_SLEEP=1 AGENTS_NOW=$((NOW + 600)) _agents_link_handle devbox devbox "want-file${T}dabc125${T}$real_home/.ssh/id_ed25519.pub" 2>/dev/null
    AGENTS_CONSENT=yes AGENTS_CONSENT_SLEEP=1 AGENTS_NOW=$((NOW + 600)) _agents_link_handle devbox devbox "want-file${T}BAD;id${T}$real_home/Desktop/shot 1.png" 2>/dev/null
    [[ "$_AGENTS_LINK_ASKED" -eq 0 && -z "$(ls "$FAKE"/pushed.* 2>/dev/null)" && "$(sed 's/"$HOME\/.local\/bin\/agents" //' "$FAKE/remote.log")" == "devbox|link reply dabc125 skip" ]] || fail "a hidden file or a bad id: $(cat "$FAKE/remote.log" 2>&1; ls "$FAKE")"
    # Three dialogs in five minutes from one machine, whatever you answer; the fourth request is not shown.
    ( _AGENTS_LINK_ASKED=0 _AGENTS_LINK_WMUTE=0 _AGENTS_LINK_WT=0 _AGENTS_LINK_WN=0; rm -f "$FAKE/remote.log"
      for i in 1 2 3 4 5; do
          AGENTS_CONSENT=yes AGENTS_CONSENT_SLEEP=1 AGENTS_NOW=$((NOW + 1000 + 20 * i)) _agents_link_handle devbox devbox "want-file${T}dflood$i${T}$real_home/Desktop/shot 1.png" 2>/dev/null
      done
      [[ "$_AGENTS_LINK_ASKED" -eq 3 && "$(grep -c 'reply dflood. ok' "$FAKE/remote.log")" -eq 3 && "$(grep -c 'reply dflood. no' "$FAKE/remote.log")" -eq 2 ]] ) || fail "more than three dialogs in five minutes: $(cat "$FAKE/remote.log")"
    # The dialog's answers, as osascript gives them: Send, Cancel (-128), and no answer.
    mkdir -p "$tmp/osa"
    osa() { printf '#!/bin/sh\n%s\n' "$1" > "$tmp/osa/osascript"; chmod +x "$tmp/osa/osascript"; }
    osa 'echo "button returned:Send, gave up:false"'
    ( PATH="$tmp/osa:$PATH"; AGENTS_CONSENT=osascript _agents_link_consent devbox "$real_home/Desktop/shot 1.png" ) || fail "Send was not a yes"
    osa 'echo "execution error: User canceled. (-128)" >&2; exit 1'
    ( PATH="$tmp/osa:$PATH"; AGENTS_CONSENT=osascript _agents_link_consent devbox "$real_home/Desktop/shot 1.png"; [[ $? -ne 0 && "$_AGENTS_LINK_WHY" == declined ]] ) || fail "Cancel was not a no"
    osa 'echo "button returned:, gave up:true"'
    ( PATH="$tmp/osa:$PATH"; AGENTS_CONSENT=osascript _agents_link_consent devbox "$real_home/Desktop/shot 1.png"; [[ $? -ne 0 && "$_AGENTS_LINK_WHY" == "no answer in 30 s" ]] ) || fail "no answer was not a no"
    osa 'echo "no window server" >&2; exit 1'
    ( PATH="$tmp/osa:$PATH"; AGENTS_CONSENT=osascript _agents_link_consent devbox "$real_home/Desktop/shot 1.png"; [[ $? -ne 0 && "$_AGENTS_LINK_WHY" == "the dialog could not be shown: no window server" ]] ) || fail "a dialog that could not be shown: $_AGENTS_LINK_WHY"
    HOME="$keep_home"
fi
# The answer, on the machine that asked: only an id and a path of the right shape.
mkdir -p "$AGENTS_RUN_DIR/link"
# (Only while a hook waits for it: an answer that comes too late is not kept.)
_agents_link_reply dabc126 ok /srv/u/.cache/tuidev/drop/a.png 2>/dev/null && fail "an answer nobody waits for was written"
: > "$AGENTS_RUN_DIR/link/w.dabc126"; : > "$AGENTS_RUN_DIR/link/w.dabc127"
_agents_link_reply dabc126 ok /srv/u/.cache/tuidev/drop/a.png && [[ "$(cat "$AGENTS_RUN_DIR/link/r.dabc126")" == "ok${T}/srv/u/.cache/tuidev/drop/a.png" ]] || fail "reply ok"
for bad in "../x ok /a" "dabc127 ok relative" 'dabc127 ok /a/$(id)' "dabc127 maybe /a" "D ok /a"; do
    # shellcheck disable=SC2086
    _agents_link_reply $bad 2>/dev/null && fail "reply accepted: $bad"
done
# The hook: a pasted path that is not here is asked for, and the session is told where it landed.
if command -v jq >/dev/null 2>&1; then
    bash "$REPO_DIR/bin/agents" link serve > "$tmp/serve2.out" 2>&1 &
    bg=$!
    for _ in $(seq 1 50); do [[ -s "$tmp/serve2.out" ]] && break; sleep 0.1; done
    printf 'here\n' > "$tmp/landed.png"
    ( _AGENTS_LINK_DROP_BUDGET=8
      printf '{"prompt":"what is in /Users/NAME/Desktop/shot\\\\ 9.png and %s"}' "$tmp/notes.md" | _agents_link_drop > "$tmp/hook.out" 2>&1 ) &
    hook=$!
    for _ in $(seq 1 50); do [[ "$(wc -l < "$tmp/serve2.out")" -ge 2 ]] && break; sleep 0.1; done
    req="$(sed -n 2p "$tmp/serve2.out")"
    [[ "$req" == "want-file${T}d"*"${T}/Users/NAME/Desktop/shot 9.png" ]] || fail "the hook asked: $(cat "$tmp/serve2.out")"
    [[ "$(wc -l < "$tmp/serve2.out" | tr -d ' ')" -eq 2 ]] || fail "the hook asked for a file that is here"
    _agents_link_reply "$(printf '%s' "$req" | cut -f2)" ok "$tmp/landed.png" || fail "could not answer the hook"
    wait "$hook"
    [[ "$(cat "$tmp/hook.out")" == "[tuidev] The file /Users/NAME/Desktop/shot 9.png is on the user's own machine, not this one. It has been copied here: read it at $tmp/landed.png" ]] || fail "the hook said: $(cat "$tmp/hook.out")"
    # Declined: the session is told so, and how the user can send it.
    ( _AGENTS_LINK_DROP_BUDGET=8; printf '{"prompt":"/Users/NAME/b.pdf"}' | _agents_link_drop > "$tmp/hook.out" 2>&1 ) &
    hook=$!
    for _ in $(seq 1 50); do [[ "$(wc -l < "$tmp/serve2.out")" -ge 3 ]] && break; sleep 0.1; done
    _agents_link_reply "$(sed -n 3p "$tmp/serve2.out" | cut -f2)" no
    wait "$hook"
    [[ "$(cat "$tmp/hook.out")" == *"the user did not send it"*"agents push FILE"* ]] || fail "the hook after a no: $(cat "$tmp/hook.out")"
    # No such file on your machine (a path the prompt only mentions): the session hears nothing.
    ( _AGENTS_LINK_DROP_BUDGET=8; printf '{"prompt":"write the report to /tmp/tuidev-absent-out.md"}' | _agents_link_drop > "$tmp/hook.out" 2>&1 ) &
    hook=$!
    for _ in $(seq 1 50); do [[ "$(wc -l < "$tmp/serve2.out")" -ge 4 ]] && break; sleep 0.1; done
    _agents_link_reply "$(sed -n 4p "$tmp/serve2.out" | cut -f2)" skip
    wait "$hook"
    [[ ! -s "$tmp/hook.out" ]] || fail "the hook spoke about a path that was never a dropped file: $(cat "$tmp/hook.out")"
    [[ -z "$(ls "$AGENTS_RUN_DIR/link" | grep -E '^[wr]\.d[0-9]')" ]] || fail "the hook left its wait files: $(ls "$AGENTS_RUN_DIR/link")"
    kill "$bg"; wait "$bg" 2>/dev/null || true; bg=""
    # Nobody attached: the hook says nothing and asks nobody.
    [[ -z "$(printf '{"prompt":"/Users/NAME/c.pdf"}' | _agents_link_drop 2>&1)" ]] || fail "the hook spoke with nobody attached"
    # The shipped hook command starts agents only when a watcher is attached.
    hookcmd="$(jq -r '.hooks.UserPromptSubmit[1].hooks[0].command' "$REPO_DIR/configs/claude/settings.json")"
    [[ "$hookcmd" == *"link drop"* ]] || fail "no drop hook in the shipped settings"
    [[ "$hookcmd" == "$(jq -r '.hooks.UserPromptSubmit[1].hooks[0].command' "$REPO_DIR/configs/claude/settings.linux.json")" ]] || fail "the Linux settings' drop hook differs"
    mkdir -p "$tmp/hk/.local/bin" "$tmp/hk/run/link"
    printf '#!/bin/sh\necho ran >> "%s/hk/ran"\n' "$tmp" > "$tmp/hk/.local/bin/agents"; chmod +x "$tmp/hk/.local/bin/agents"
    HOME="$tmp/hk" AGENTS_RUN_DIR="$tmp/hk/run" sh -c "$hookcmd" </dev/null || fail "the hook command failed with nobody attached"
    [[ ! -e "$tmp/hk/ran" ]] || fail "the hook command started agents with nobody attached"
    mkfifo "$tmp/hk/run/link/l.1"
    HOME="$tmp/hk" AGENTS_RUN_DIR="$tmp/hk/run" sh -c "$hookcmd" </dev/null
    [[ -e "$tmp/hk/ran" ]] || fail "the hook command did not start agents with a watcher attached"
fi
pass "a dropped file: asked for by the session's hook, refused when hidden, sent only on your yes, and the session is told where it is"

# --- 8. The map ------------------------------------------------------------------------------
# The marks of kinds of sessions are tested below; the rows here are read without them.
export AGENTS_GLYPHS=off
_agents_map_rows() {
    printf 'sys\tcpu 12%% · memory 60%% free · 1 session · 1 left behind\n'
    printf 'proc\t500@Mon_1\tclaude         500    3.0   1.0G   1h00m  app                    working · claude\n'
    printf 'proc\t501@Mon_1\t  mcp          501    0.0    30M   1h00m  chrome-devtools        npm exec chrome-devtools-mcp\n'
    printf 'proc\t502@Mon_1\t  tool         502    1.0    20M      2m  main                   npm run dev\n'
    printf 'port\t5173\t%s\tnode\t%s/proj\n' "$$" "$HOME"
}
{ printf 'sys\tcpu 40%% · memory 20%% free · 2 sessions · 0 left behind\n'
  printf 'proc\t77@Tue_2\tcodex           77   90.0   2.0G   3h00m  api                    tests\n'
  printf 'proc\t78;reboot\tstale           78    0.0     1M     1m  x                      evil\n'
  printf 'proc\t79@Tue_3\tstale           79    0.0     1M     1m  x                      es\033]0;T\007c\n'
  printf 'port\t8000\t91\tpython3\t/srv/app\n'
  printf 'fwd\t31337\tdevbox\t8000\tactive\t1\n'
  printf 'fwd\t1234\033]0;T\007\tfake\t1\tactive\t1\n'
  printf 'file\t/srv/app/report.html\tapi\n'
  printf 'file\t/srv/app/$(id).html\tapi\n'
  printf 'port\t80;id\t91\tsh\t/srv\n'; } > "$FAKE/map.devbox"
printf 'sys\tneeds tuidev there (./install.sh --pack monitoring)\n' > "$FAKE/map.workbox"
agents_forward open --no-open devbox 8000 >/dev/null
# (Runs of spaces squeezed: the columns' widths are not what is tested.)
list="$(NO_COLOR=1 agents_map --list | tr -s ' ')"
# Grouped by what you would do: previews and dev servers first, then what was
# left behind, the sessions (one line each), and the machines.
order="$(NO_COLOR=1 agents_map --list | cut -f4 | grep -E '^[A-Z]{4}' | sed 's/  .*//' | tr '\n' '|')"
[[ "$order" == "PREVIEWS AND DEV SERVERS|FILES SESSIONS JUST WROTE|LEFT BEHIND|SESSIONS|MACHINES|" ]] || fail "map: the groups: $order"
# A file a session wrote: enter fetches it from its machine and opens it here; a path of another shape is no row.
[[ "$list" == *"devbox${T}file${T}/srv/app/report.html${T} devbox report.html"*"api"* && "$list" != *'$(id)'* ]] || fail "map: the files group: $list"
reset; printf '<h1>report</h1>\n' > "$FAKE/file.devbox"
agents_map --act go devbox file /srv/app/report.html || fail "map: enter on a remote file failed"
[[ "$(opened)" == "$AGENTS_DATA_DIR/remote/devbox/report.html" ]] || fail "map: a remote file was not fetched and opened: $(opened)"
for bad in '/srv/app/run.command' '/srv/$(id).html' 'relative.md'; do
    agents_map --act go devbox file "$bad" >/dev/null 2>&1 && fail "map: opened the file '$bad'"
done
[[ "$list" == *"local${T}port${T}5173:$$${T} local :5173 node proj"*"http://localhost:5173"* ]] || fail "map: a local server row: $list"
# A remote server with a forward already here says where it opens; one session's command says whose it is.
[[ "$list" == *"devbox${T}port${T}8000:91${T} devbox :8000 python3 app"*"http://localhost:8000 (forwarded)"* ]] || fail "map: a remote server with its forward: $list"
[[ "$list" == *"local${T}proc${T}500@Mon_1${T} local claude app working"*"1.0G 1h00m 1 mcp · 1 command"* ]] || fail "map: a session row: $list"
[[ "$list" == *"devbox${T}proc${T}77@Tue_2${T} devbox codex api"* ]] || fail "map: another machine's session: $list"
[[ "$list" == *"devbox${T}proc${T}79@Tue_3${T} devbox stale x"* ]] || fail "map: what was left behind: $list"
[[ "$list" != *"501@Mon_1"* ]] || fail "map: a session's helpers are listed without --all"
[[ "$(NO_COLOR=1 agents_map --list --all | tr -s ' ')" == *"local${T}proc${T}501@Mon_1${T} "*"mcp chrome-devtools"* ]] || fail "map --all: no helpers: $(NO_COLOR=1 agents_map --list --all)"
[[ "$list" == *"local${T}head${T}-${T} local cpu 12% · memory 60% free · 1 session · 1 left behind"* ]] || fail "map: this machine's line: $list"
[[ "$list" == *"workbox${T}head${T}-${T} workbox needs tuidev there"* ]] || fail "map: a machine without it: $list"
[[ "$list" != *FORWARDS* ]] || fail "map: a forward shown on its server's row is listed again"
# A forward is this machine's to report: one another machine sends changes nothing here.
[[ "$list" != *31337* && "$list" != *fake* ]] || fail "map: another machine's fwd row was taken: $list"
# The menu bar's copy of the board: the same rows under the same checks, written
# only when asked (the menu opening), and not again while it is fresh.
bar="$(_agents_map_bar)"
[[ "$bar" == *"mach${T}local${T}cpu 12% · memory 60% free"* && "$bar" == *"mach${T}workbox${T}needs tuidev there"* ]] || fail "map bar: the machines: $bar"
[[ "$bar" == *"port${T}local${T}5173${T}node${T}proj${T}-${T}-"* && "$bar" == *"port${T}devbox${T}8000${T}python3${T}app${T}8000${T}-"* ]] || fail "map bar: the servers: $bar"
[[ "$bar" == *"left${T}devbox${T}1"* && "$bar" == *"fwd${T}8000${T}devbox${T}8000${T}active"* ]] || fail "map bar: leftovers and forwards: $bar"
[[ "$bar" != *31337* && "$bar" != *reboot* && "$bar" != *"80;id"* && "$bar" != *$'\033'* && "$bar" != *$'\007'* ]] || fail "map bar: a hostile row got through: $(printf '%s' "$bar" | cat -v)"
[[ -z "$(_agents_map_tsv)" ]] || fail "map tsv: rows before anything was loaded"
AGENTS_NOW=1000 agents_map --cache
[[ "$(sed -n 1p "$AGENTS_RUN_DIR/map.tsv")" == "at${T}1000" && ! -e "$AGENTS_RUN_DIR/map.lock" ]] || fail "map --cache: $(cat "$AGENTS_RUN_DIR/map.tsv" 2>&1)"
AGENTS_NOW=1010 agents_map --cache
[[ "$(sed -n 1p "$AGENTS_RUN_DIR/map.tsv")" == "at${T}1000" ]] || fail "map --cache: loaded again while fresh"
AGENTS_NOW=1030 agents_map --cache
[[ "$(_agents_map_tsv | sed -n 1p)" == "map${T}at${T}1030" && "$(_agents_map_tsv)" == *"map${T}port${T}devbox${T}8000${T}"* ]] || fail "map tsv: $(_agents_map_tsv)"
mkdir "$AGENTS_RUN_DIR/map.lock"; printf '%s %s\n' "$$" "$(_agents_start "$$" 2>/dev/null || echo -)" > "$AGENTS_RUN_DIR/map.lock/holder"
AGENTS_NOW=2000 agents_map --cache
[[ "$(sed -n 1p "$AGENTS_RUN_DIR/map.tsv")" == "at${T}1030" ]] || fail "map --cache: wrote while another run held the lock"
rm -rf "$AGENTS_RUN_DIR/map.lock"
agents_forward open --no-open devbox 9999 >/dev/null
[[ "$(NO_COLOR=1 agents_map --list | tr -s ' ')" == *"FORWARDS"*"local${T}fwd${T}9999${T} devbox :9999 http://localhost:9999"* ]] || fail "map: a forward to no listed server: $(NO_COLOR=1 agents_map --list)"
agents_forward close 9999 >/dev/null
[[ "$(unset NO_COLOR; agents_map --list)" == *$'\033[1m'"PREVIEWS"* ]] || fail "map: no bold group titles with colors on"
# What another machine sends is text: an id of another shape is no row, and no escape gets through.
[[ "$list" != *reboot* && "$list" != *"80;id"* && "$list" != *$'\033'* && "$list" != *$'\007'* ]] || fail "map: a hostile row got through: $(printf '%s' "$list" | cat -v)"
[[ "$(agents_map | head -1)" == "PREVIEWS AND DEV SERVERS"* ]] || fail "map without a terminal is not the plain list"
# The keys: each acts on the row's own machine, and only on an id of the right shape.
reset; rm -f "$FAKE/remote.log"
agents_map --act stop devbox proc 77@Tue_2 >/dev/null; agents_map --act sweep devbox head - >/dev/null; agents_map --act stop devbox port 8000:91 >/dev/null
[[ "$(sed 's/"$HOME\/.local\/bin\/agents" //' "$FAKE/remote.log")" == "devbox|kill 77@Tue_2"$'\n'"devbox|reap"$'\n'"devbox|kill 91" ]] || fail "map: stop and sweep on another machine: $(cat "$FAKE/remote.log")"
[[ "$(grep -c -- ' -t ' "$FAKE/ssh.log")" -eq 3 ]] || fail "map: a stop elsewhere had no terminal for its question"
for bad in '77;reboot' '$(id)' '77@a b' ''; do
    agents_map --act stop devbox proc "$bad" >/dev/null 2>&1 && fail "map: acted on the id '$bad'"
done
agents_map --act stop devbox port '8000:-' >/dev/null 2>&1 && fail "map: stopped a server without knowing its process"
[[ "$(wc -l < "$FAKE/remote.log" | tr -d ' ')" -eq 3 ]] || fail "map: refused ids reached a machine: $(cat "$FAKE/remote.log")"
reset; agents_map --act go devbox port 8000:91 >/dev/null; agents_map --act go local fwd 8000 >/dev/null
[[ "$(opened)" == "http://localhost:8000"$'\n'"http://localhost:8000" ]] || fail "map: enter on a server and a forward: $(opened)"
[[ "$(agents_map --act stop local fwd 8000)" == "closed localhost:8000 (devbox:8000)" ]] || fail "map: ctrl-k on a forward"
[[ -z "$(agents_map --preview - head -)" && "$(agents_map --preview devbox head -)" == *"sweep"* && "$(agents_map --preview devbox port 8000:91)" == *"forward it here"* ]] || fail "map: preview text"
# One copy of the checks: the list and the menu bar's board take a row, or
# refuse it, the same way (awk/lib_maprows.awk). Every row here is from devbox.
(
    big=""; i=0; while [[ $i -lt 49 ]]; do big+="a"; i=$((i + 1)); done
    ok48="${big%a}"
    # id<TAB>what: the stale rows' ids; each valid one is a row of LEFT BEHIND and counts in the bar's "left".
    {
        printf 'sys\tcpu 1%% \342\200\256evil\342\200\250 \342\201\247x\342\201\251 \302\233[31m ok\n'
        for id in 11@a 22@Mon_1:2 33 "44@$ok48"; do printf 'proc\t%s\tstale          1    0.0     1M     1m  x                      ok\n' "$id"; done
        for id in 12345678901 "55@$big" 66@ '66@a b' '77;x' '@88' 'ab' '99@a/b' "5$(printf '\033')"; do printf 'proc\t%s\tstale          1    0.0     1M     1m  x                      bad\n' "$id"; done
        # A row whose text starts with a control character is no stale row of its own in either.
        printf 'proc\t111@z\t\001  stale        1    0.0     1M     1m  x                      child\n'
        for p in 3000 4000; do printf 'port\t%s\t12\tnode\t/srv/p%s\n' "$p" "$p"; done
        for p in 123456 99x; do printf 'port\t%s\t12\tnode\t/srv/bad\n' "$p"; done
        printf 'port\t5000\t12345678901\tnode\t/srv/p5000\n'
        # A forward from this machine (local) needs every field; devbox's own are no rows.
        printf 'fwd\t31337\tdevbox\t8000\tactive\t1\n'
    } | awk '{ print "devbox\t" $0 }' > "$tmp/hostile.rows"
    {
        printf 'local\tfwd\t41000\tdevbox\t8000\tactive\t5\n'
        printf 'local\tfwd\t41001\tdevbox\t8001\tdead\n'
        printf 'local\tfwd\t41002\tdevbox\t8002\tactive\tx\n'
        printf 'local\tfwd\t41003\tdev box\t8003\tactive\t5\n'
        printf 'local\tfwd\t41004\tdevbox\t8004\tsideways\t5\n'
        printf 'local\tfwd\t410050\tdevbox\t8005\tactive\t5\n'
        printf 'local\tfwd\t41006\tdevbox\t8006\tactive\t1234567890\n'
    } >> "$tmp/hostile.rows"
    _agents_map_all() { cat "$tmp/hostile.rows"; }
    h_list="$(NO_COLOR=1 _agents_map_list | LC_ALL=C tr -d '\r')"
    h_bar="$(_agents_map_bar)"
    # procs: the same ids in both (the bar counts what the list shows under LEFT BEHIND)
    got="$(printf '%s\n' "$h_list" | awk -F '\t' '$2 == "proc" { print $3 }' | tr '\n' ' ')"
    [[ "$got" == "11@a 22@Mon_1:2 33 44@$ok48 " ]] || fail "map: ids the list took: $got"
    [[ "$h_bar" == *"left${T}devbox${T}4"$'\n'* || "$h_bar" == *"left${T}devbox${T}4" ]] || fail "map bar: not the same four stale rows: $h_bar"
    # ports: 3000 and 4000 (and 5000 with no process id); neither takes 123456 or 99x
    lp="$(printf '%s\n' "$h_list" | awk -F '\t' '$2 == "port" { sub(/:.*/, "", $3); print $3 }' | tr '\n' ' ')"
    bp="$(printf '%s\n' "$h_bar" | awk -F '\t' '$1 == "port" { print $3 }' | tr '\n' ' ')"
    [[ "$lp" == "3000 4000 5000 " && "$bp" == "$lp" ]] || fail "map: ports differ: list '$lp', bar '$bp'"
    [[ "$h_list" == *"5000:-"* ]] || fail "map: a process id of the wrong shape was kept: $h_list"
    # forwards: only local's own, with every field of its shape: 41000 alone
    lf="$(printf '%s\n' "$h_list" | awk -F '\t' '$2 == "fwd" { print $3 }' | tr '\n' ' ')"
    bf="$(printf '%s\n' "$h_bar" | awk -F '\t' '$1 == "fwd" { print $2 }' | tr '\n' ' ')"
    [[ "$lf" == "41000 " && "$bf" == "$lf" ]] || fail "map: forwards differ: list '$lf', bar '$bf'"
    [[ "$h_list" != *31337* && "$h_bar" != *31337* ]] || fail "map: a forward devbox sent was taken"
    # text: no control character, no C1, no bidi or line separator, in either
    for out in "$h_list" "$h_bar"; do
        [[ "$(printf '%s' "$out" | LC_ALL=C grep -c $'\342\200[\250-\256]\\|\342\201[\246-\251]\\|\302[\200-\237]\\|[\001-\010\013-\037\177]')" -eq 0 ]] \
            || fail "map: a control or bidi character got through: $(printf '%s' "$out" | cat -v)"
    done
    [[ "$(printf '%s\n' "$h_list" | tr -s ' ')" == *"cpu 1% evil x [31m ok"* ]] || fail "map: the machine's line: $h_list"
    [[ "$(printf '%s\n' "$h_bar" | tr -s ' ')" == *"mach${T}devbox${T}cpu 1% evil x [31m ok"* ]] || fail "map bar: the machine's line: $h_bar"
)
unset AGENTS_GLYPHS
# Marks: the table's own, one display column each, in front of the session's kind and of "by KIND" on a
# server it owns; the columns stay where they are (a mark is several bytes: padded by display width).
dwidth() { printf '%s' "$1" | LC_ALL=C tr -d '\200-\277' | wc -c | tr -d ' '; }
g_rows() { printf '%s\n' "$1" | cut -f4; }
glist="$(unset AGENTS_GLYPHS; NO_COLOR=1 agents_map --list)"
[[ "$(g_rows "$glist" | tr -s ' ')" == *"local ✳ claude app"* ]] || fail "map: no mark on the claude session: $(g_rows "$glist")"
[[ "$(g_rows "$glist" | tr -s ' ')" == *"devbox ⬡ codex api"* ]] || fail "map: marks: $(g_rows "$glist")"
# Aligned: the project column starts at the same display column in the header and in every session row,
# with a mark, with an empty one, and with the marks off.
for g in "" "agent=" "claude=C codex=" "off"; do
    gl2="$(AGENTS_GLYPHS="$g" NO_COLOR=1 agents_map --list | cut -f4)"
    want=""
    while IFS= read -r line; do
        case "$line" in
            *MACHINE*AGENT*PROJECT*) pre="${line%%PROJECT*}" ;;
            *claude*" app "*working*) pre="${line%% app *} " ;;
            *codex*" api "*) pre="${line%% api *} " ;;
            *) continue ;;
        esac
        w="$(dwidth "$pre")"
        [[ -n "$want" ]] || want="$w"
        [[ "$w" == "$want" ]] || fail "map: the project column moved ($w, not $want) with AGENTS_GLYPHS='$g': $line"
    done <<<"$gl2"
    [[ -n "$want" ]] || fail "map: no session rows with AGENTS_GLYPHS='$g'"
done
# A mark of your own; the kind of the row is only a key into the table.
[[ "$(AGENTS_GLYPHS="claude=C" NO_COLOR=1 agents_map --list | cut -f4 | tr -s ' ')" == *"local C claude app"* ]] || fail "map: AGENTS_GLYPHS=claude=C"
off="$(AGENTS_GLYPHS=off NO_COLOR=1 agents_map --list | cut -f4)"
[[ "$off" != *✳* && "$off" != *⬡* && "$(printf '%s\n' "$off" | tr -s ' ')" == *"local claude app"* ]] || fail "map: marks off is not today's list: $off"
(
    # A server a session started says whose it is, with that session's mark.
    _agents_map_all() {
        printf 'local\tproc\t500@a\tclaude         500    3.0   1.0G   1h00m  app                    working · claude\n'
        printf 'local\tproc\t502@a\t  tool         502    1.0    20M      2m  main                   npm run dev\n'
        printf 'local\tport\t5173\t502\tnode\t/srv/proj\n'
    }
    [[ "$(NO_COLOR=1 _agents_map_list | cut -f4 | tr -s ' ')" == *"· by ✳ claude app"* ]] || fail "map: the mark on a server's owner"
    [[ "$(AGENTS_GLYPHS=off NO_COLOR=1 _agents_map_list | cut -f4 | tr -s ' ')" == *"· by claude app"* ]] || fail "map: a server's owner without marks"
)
(
    # A kind the table does not name takes the "agent" mark; one that tries to be more than a key stays a word.
    _agents_map_all() {
        printf 'devbox\tproc\t7@a\tmystery         7    0.0     1M     1m  proj                   working · x\n'
        printf 'devbox\tproc\t8@a\t$(id)           8    0.0     1M     1m  proj2                  working · x\n'
    }
    [[ "$(NO_COLOR=1 _agents_map_list | cut -f4 | tr -s ' ')" == *"devbox ◆ mystery proj"* ]] || fail "map: the mark of a kind the table lacks"
    [[ "$(AGENTS_GLYPHS=off NO_COLOR=1 _agents_map_list | cut -f4 | tr -s ' ')" == *"devbox mystery proj"* ]] || fail "map: no mark, a kind the table lacks"
    [[ "$(AGENTS_GLYPHS='mystery=$(id)' NO_COLOR=1 _agents_map_list | cut -f4)" != *"uid="* ]] || fail "map: the table's text was run"
)
# A long path, a recognisable end first: a binary in a temp directory shows its name, then where it is; a file its
# name, its session, and a path cut in the middle.
(
    _agents_map_all() {
        printf 'local\tproc\t9@a\tstale           9    0.0     1M     1m  x                      /var/folders/vr/abcdef123/T/go-build3158750540/b001/web.test ··\n'
        printf 'local\tproc\t10@a\tstale          10    0.0     1M     1m  x                      /usr/bin/short -v\n'
        printf 'local\tfile\t/srv/some/deeply/nested/project/directory/with/many/levels/reports/final-report.html\tapi\n'
    }
    t="$(NO_COLOR=1 _agents_map_list | cut -f4)"
    [[ "$t" == *"  web.test  /var/folders/"*"/b001/ ··"* && "$t" != *"/var/folders/vr/abcdef123/T/go-build3158750540/b001/web.test"* ]] || fail "map: the temp binary: $t"
    [[ "$t" == *"/usr/bin/short -v"* ]] || fail "map: a short path was changed: $t"
    line="$(printf '%s\n' "$t" | grep 'final-report.html .*api ')" || fail "map: the file row: $t"
    last="${line##* }"
    [[ "$last" == /srv/*…*/reports/final-report.html && "$(dwidth "$last")" -eq 50 ]] || fail "map: the file path is not cut in the middle: $line"
)
unset AGENTS_GLYPHS
# This machine's own rows: a session, and of the listeners only the dev server
# (not the session's own port, not an app's).
# shellcheck source=../../lib/agents/map.sh disable=SC1091
. "$REPO_DIR/lib/agents/map.sh"
agents_collect() { printf 'agent\t900\tclaude\t3600\t3.0\t-\t1048576\t-\tMon_1\t-\t-\tworking\t-\tclaude\tapp\t-\n'; }
agents_system() { printf '1.0\t8\t60\tnormal\t-\t-\n'; }
_agents_cpu_pct() { echo 12; }
_agents_listeners() { printf '900 5000\n%s 5173\n4242 7000\n' "$$"; }
_agents_cwds() { printf '900\t%s/app\n%s\t%s/proj\n4242\t%s/x\n' "$HOME" "$$" "$HOME" "$HOME"; }
ps() { printf '  900 /usr/local/bin/claude\n%6s /usr/local/bin/node\n 4242 /Applications/Thing.app/Contents/MacOS/Thing\n' "$$"; }
# Files this machine's sessions wrote: from the transcript's Write and Edit calls.
if command -v jq >/dev/null 2>&1; then
    mkdir -p "$tmp/w"; printf '# plan\n' > "$tmp/w/plan.md"; printf 'x\n' > "$tmp/w/build.sh"
    { echo '{"type":"user"}'
      printf '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":"%s"}}]}}\n' "$tmp/w/plan.md" "$tmp/w/build.sh" "$tmp/w/gone.md" "$tmp/w/plan.md"
    } > "$tmp/tx.jsonl"
    _agents_session_of() { printf 'session\tabc\ntranscript\t%s\n' "$tmp/tx.jsonl"; }
    [[ "$(agents_collect | _agents_map_files)" == "file${T}$tmp/w/plan.md${T}app" ]] || fail "map files: $(agents_collect | _agents_map_files)"
fi
rows="$(_agents_map_rows)"
[[ "$(printf '%s\n' "$rows" | sed -n 1p)" == "sys${T}cpu 12% · memory 60% free · 1 session · 0 left behind" ]] || fail "map rows: the machine's line: $rows"
[[ "$rows" == *"proc${T}900@Mon_1${T}claude"* ]] || fail "map rows: the session: $rows"
[[ "$(printf '%s\n' "$rows" | grep -c '^port')" -eq 1 && "$rows" == *"port${T}5173${T}$$${T}node${T}$HOME/proj"* ]] || fail "map rows: only the dev server is a server: $rows"
pass "map: every machine's sessions, leftovers and servers in one list; stop and sweep run on the row's machine, on checked ids only"

# --- 9. The Herdr plugin ---------------------------------------------------------------------
plugin="$REPO_DIR/configs/herdr/plugins/tuidev-link"
[[ -f "$plugin/herdr-plugin.toml" && -f "$plugin/run.sh" ]] || fail "the plugin's files are missing"
# Its link pattern claims no more than the watcher will act on.
pat="$(sed -n '/id = "localhost"/,/action/s/^pattern = "\(.*\)"$/\1/p' "$plugin/herdr-plugin.toml" | sed 's/\\\\/\\/g')"
[[ -n "$pat" ]] || fail "no localhost pattern in the manifest"
for u in http://localhost:5173/ https://127.0.0.1:8443/a http://0.0.0.0:3000 'http://[::1]:8080/x'; do
    [[ "$u" =~ $pat ]] || fail "the plugin does not claim $u"
    [[ "$u" =~ $_AGENTS_FORWARD_URL_RE ]] || fail "the watcher refuses $u, which the plugin claims"
done
for u in https://example.com/ http://localhost.evil.com/ http://127.0.0.1.evil.com:80/ http://localhost:1@example.com/; do
    [[ ! "$u" =~ $pat ]] || fail "the plugin claims $u"
done
grep -q 'id = "ports"' "$plugin/herdr-plugin.toml" || fail "no ports action"
grep -q 'id = "map"' "$plugin/herdr-plugin.toml" || fail "no map action"
# Every key the pack binds names an action the manifest has.
for act in $(sed -n 's/^command = "tuidev\.link\.\(.*\)"$/\1/p' "$REPO_DIR/configs/herdr/keys.toml"); do
    grep -q "^id = \"$act\"\$" "$plugin/herdr-plugin.toml" || fail "keys.toml binds tuidev.link.$act, which the plugin does not have"
done
[[ -n "$(sed -n 's/^command = "tuidev\.link\.\(.*\)"$/\1/p' "$REPO_DIR/configs/herdr/keys.toml")" ]] || fail "keys.toml binds nothing"
reset
mkdir -p "$HOME/.local/bin"; ln -s "$REPO_DIR/bin/agents" "$HOME/.local/bin/agents"
HERDR_PLUGIN_CLICKED_URL="http://localhost:5173/" sh "$plugin/run.sh" click >/dev/null || fail "run.sh click failed"
[[ "$(opened)" == "http://localhost:5173/" ]] || fail "run.sh click opened: $(opened)"
sh "$plugin/run.sh" click >/dev/null 2>&1 && fail "run.sh click without a link succeeded"
AGENTS_BIN="$tmp/nope" sh "$plugin/run.sh" click >/dev/null 2>&1 && fail "run.sh without agents succeeded"
# A loopback URL with characters the watcher refuses still opens when nobody is attached.
reset; HERDR_PLUGIN_CLICKED_URL='http://localhost:5173/a[1]' sh "$plugin/run.sh" click >/dev/null || fail "an odd local URL did not open here"
[[ "$(opened)" == 'http://localhost:5173/a[1]' ]] || fail "odd URL: $(opened)"
pass "the Herdr plugin: claims only loopback URLs and file links, and hands them to agents link click"

# --- 10. The menu bar: closed reads this machine, open loads the rest ------------------------------
menu_sh="$REPO_DIR/configs/swiftbar/agents.10s.sh"
mkdir -p "$tmp/mbin" "$tmp/sbcache"
{ printf 'sys\t5\t1.0\t8\t60\tnormal\t-\t-\n'
  printf 'map\tat\t%s\n' "$(date +%s)"
  printf 'map\tmach\tlocal\tcpu 5%% · 1 session\nmap\tmach\tdevbox\tcpu 40%% · 2 sessions\nmap\tmach\tbad|box;x\tevil\n'
  printf 'map\tport\tlocal\t5173\tnode\tshop\t-\t-\nmap\tport\tdevbox\t8000\tpython3\tapp\t-\tstale\nmap\tport\tdevbox\t80;id\tsh\tx\t-\t-\n'
  printf 'map\tleft\tdevbox\t2\nmap\tfwd\t47000\tdevbox\t3000\tactive\n'; } > "$tmp/menu.tsv"
# shellcheck disable=SC2016  # the stub's own variables
printf '#!/bin/bash\necho "$*" >> "%s/calls"\n[[ "$1" != tsv ]] || cat "%s/menu.tsv"\n' "$tmp/mbin" "$tmp" > "$tmp/mbin/agents"
printf '#!/bin/bash\necho "$*" >> "%s/calls"\n' "$tmp/mbin" > "$tmp/mbin/open"
chmod +x "$tmp/mbin/agents" "$tmp/mbin/open"
mbar() { PATH="$tmp/mbin:$PATH" AGENTS_BIN="$tmp/mbin/agents" SWIFTBAR_PLUGIN_CACHE_PATH="$tmp/sbcache" SWIFTBAR_PLUGIN_PATH="$menu_sh" "$@" bash "$menu_sh"; }
menu="$(mbar env)"
[[ "$menu" == *"Machines (1) · 2 dev servers · 2 left behind"* ]] || fail "menu: the machines header: $(printf '%s\n' "$menu" | grep -i machines)"
[[ "$menu" == *"shop :5173 · node | sfimage=globe href=http://localhost:5173"* ]] || fail "menu: a local server is not a link: $menu"
[[ "$(printf '%s\n' "$menu" | grep 'app :8000')" == "app :8000 · python3 · on devbox · left behind |"*"param1=forward param2=open param3=devbox param4=8000"* ]] || fail "menu: a remote server does not forward: $(printf '%s\n' "$menu" | grep 8000)"
[[ "$menu" == *"--localhost:47000 → devbox:3000 | href=http://localhost:47000"* && "$menu" == *"param2=map param3=devbox"* ]] || fail "menu: forwards and the machine's row: $menu"
[[ "$menu" != *"80;id"* && "$menu" != *"box;x"* ]] || fail "menu: a row of another shape got in"
# Its timer asked agents for the snapshot and nothing else.
[[ "$(cat "$tmp/mbin/calls")" == tsv ]] || fail "menu: a timed refresh ran more than agents tsv: $(cat "$tmp/mbin/calls")"
# Opening it prints the last output without asking anything, then loads the board and refreshes.
[[ -s "$tmp/sbcache/last" ]] || fail "menu: the last output was not kept"
: > "$tmp/mbin/calls"
[[ "$(mbar env SWIFTBAR_PLUGIN_REFRESH_REASON=MenuOpen)" == "$menu" ]] || fail "menu: opening did not print the last output"
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do [[ "$(wc -l < "$tmp/mbin/calls" | tr -d ' ')" -ge 2 ]] && break; sleep 0.1; done
[[ "$(cat "$tmp/mbin/calls")" == "map --cache"$'\n'"-g swiftbar://refreshplugin?name=agents" ]] || fail "menu: opening did not load the board and refresh: $(cat "$tmp/mbin/calls")"
# A machine's long summary is cut, a label that reads as an option is no row, and a
# run that ends in a refusal is shown but never kept for the next open.
long="$(printf 'x%.0s' 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 43 44 45 46 47 48 49 50 51 52 53 54 55 56 57 58 59 60 61 62 63 64 65 66 67 68 69 70)"
printf 'map\tmach\tworkbox\t%s\nmap\tmach\t--rows\tevil\n' "$long" >> "$tmp/menu.tsv"
menu2="$(mbar env)"
[[ "$menu2" == *"workbox · xxxxx"*"xxx... |"* && "$menu2" != *"$long"* && "$menu2" != *"--rows"* ]] || fail "menu: a long summary or an option-like label got through: $(printf '%s\n' "$menu2" | grep -e workbox -e rows)"
[[ ! -e "$tmp/sbcache/last.nomap" ]] || fail "menu: the section is on, yet the next open is told not to load"
printf 'conf\tAGENTS_BAR_SECTIONS\tneeds system\n' >> "$tmp/menu.tsv"; mbar env >/dev/null; : > "$tmp/mbin/calls"
[[ -e "$tmp/sbcache/last.nomap" ]] || fail "menu: no marker with the machines section turned off"
mbar env SWIFTBAR_PLUGIN_REFRESH_REASON=MenuOpen >/dev/null; sleep 0.5
[[ ! -s "$tmp/mbin/calls" ]] || fail "menu: opening asked the machines with their section off: $(cat "$tmp/mbin/calls")"
grep -v 'AGENTS_BAR_SECTIONS' "$tmp/menu.tsv" > "$tmp/menu.tsv.n" && mv "$tmp/menu.tsv.n" "$tmp/menu.tsv"; mbar env >/dev/null
kept="$(cat "$tmp/sbcache/last")"
# shellcheck disable=SC2016  # the stub's own variables
printf '#!/bin/bash\n[[ "$1" != tsv ]] || exit 1\n' > "$tmp/mbin/agents-down"; chmod +x "$tmp/mbin/agents-down"
[[ "$(PATH="$tmp/mbin:$PATH" AGENTS_BIN="$tmp/mbin/agents-down" SWIFTBAR_PLUGIN_CACHE_PATH="$tmp/sbcache" bash "$menu_sh")" == *"agents tsv failed"* && ! -e "$tmp/sbcache/last" ]] || fail "menu: a failed run left a last output for the next open"
[[ -n "$kept" && -z "$(ls "$tmp/sbcache" | grep '^last\.[0-9]')" ]] || fail "menu: a temporary output file was left: $(ls "$tmp/sbcache")"
# The saved stdout does not reach a background job: the output ends when the run does.
# shellcheck disable=SC2016  # the stub's own variables
printf '#!/bin/bash\ncase "$1" in tsv) printf "sys\\t5\\t1.0\\t8\\t60\\tnormal\\t-\\t-\\nhist\\tdue\\t0\\t-\\t0\\n" ;; sample) sleep 5 ;; esac\n' > "$tmp/mbin/agents-slow"; chmod +x "$tmp/mbin/agents-slow"
SECONDS=0
out="$(PATH="$tmp/mbin:$PATH" AGENTS_BIN="$tmp/mbin/agents-slow" SWIFTBAR_PLUGIN_CACHE_PATH="$tmp/sbcache" bash "$menu_sh")"
[[ -n "$out" && $SECONDS -lt 4 ]] || fail "menu: its output waited ${SECONDS}s for a background job"
# Without a board (nothing loaded yet) there is no section, and no last output means a full run.
grep -v '^map' "$tmp/menu.tsv" > "$tmp/menu.tsv.n" && mv "$tmp/menu.tsv.n" "$tmp/menu.tsv"; rm -f "$tmp/sbcache/last"
[[ "$(mbar env SWIFTBAR_PLUGIN_REFRESH_REASON=MenuOpen)" != *"Machines"* ]] || fail "menu: a machines section with nothing loaded"
pass "the menu bar: its timer reads this machine only; opening shows the last output at once and loads the machines behind it"

echo "All agents remote tests passed."
