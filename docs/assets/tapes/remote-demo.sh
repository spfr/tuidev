#!/bin/bash
# The fleet for the "remote feels local" screencast (docs/assets/tapes/README.md):
# herdr-demo.sh's fleet, a Herdr server on this Mac in a throwaway home and two
# Linux containers saved as SSH machines, with tuidev on every one of them:
# `agents`, the tuidev.link Herdr plugin and its keys, and on this Mac the link
# watcher, so a Ctrl-click on a container's localhost URL opens in this Mac's
# browser through a real ssh tunnel. The machines are atlas and kepler; the
# cast is a storefront preview on atlas, an API server on kepler that its
# session left behind, and four more sessions.
#
#   remote-demo.sh up HOME     start everything (HOME: a short path under /tmp)
#   remote-demo.sh env HOME    print the environment for a Herdr client (eval it)
#   remote-demo.sh down HOME   stop the watcher and the forwards, then the fleet
#
# Nothing reads this machine's ~/.ssh, SSH agent, Herdr config or agents
# state: ssh is herdr-demo.sh's wrapper, and every path is under HOME. What a
# click opens is real: this Mac's own browser, on a 127.0.0.1 port.
set -eo pipefail

cmd="${1:-}" home="${2:-}"
[[ -n "$cmd" && -n "$home" ]] || { echo "usage: remote-demo.sh up|env|down HOME" >&2; exit 2; }
tapes="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$tapes/../../.." && pwd)"
export TUIDEV_DEMO_MACHINES="atlas kepler" TUIDEV_DEMO_NO_POPULATE=1
PREFIX=tuidev-demo-

die() { echo "remote-demo: $*" >&2; exit 1; }
fleet() { bash "$tapes/herdr-demo.sh" "$@"; }

# run_demo CMD... — CMD in the demo's environment (herdr-demo.sh env), plus
# ~/.local/bin, where the demo home's agents is.
# shellcheck disable=SC2030,SC2031  # the subshell is the point: nothing leaks out
run_demo() {
    ( eval "$(fleet env "$home")"
      export PATH="$home/.local/bin:$PATH" AGENTS_MAP_ROOT="$home"
      "$@" )
}
herdr_demo() { run_demo herdr "$@"; }
on() { local m="$1"; shift; run_demo ssh "$PREFIX$m" "$@"; }

# tuidev_here — agents and the plugin for the demo home, from this checkout.
tuidev_here() {
    mkdir -p "$home/.local/bin"
    ln -sf "$repo/bin/agents" "$home/.local/bin/agents"
    ln -sf "$repo/bin/agents" "$home/.demo/bin/agents"
    # TUIDEV_DEMO_NO_BROWSER=1 (remote.tape): `open` only records what it was
    # given, in ~/.demo/opened, so rendering a tape opens no tab on this Mac.
    if [[ -n "${TUIDEV_DEMO_NO_BROWSER:-}" ]]; then
        printf '%s\n' '#!/bin/sh' "printf '%s\\n' \"\$1\" >> '$home/.demo/opened'" > "$home/.demo/bin/open"
        chmod 755 "$home/.demo/bin/open"
    fi
    herdr_demo plugin link "$repo/configs/herdr/plugins/tuidev-link" >/dev/null \
        || die "could not link the plugin into the demo Herdr"
    { echo; cat "$repo/configs/herdr/keys.toml"; } >> "$home/.config/herdr/config.toml"
    herdr_demo server reload-config >/dev/null
}

# tuidev_on MACHINE — the same on a container: this checkout's agents and
# plugin copied into ~/.local/share/tuidev, linked into its Herdr.
# shellcheck disable=SC2016  # the remote shell expands ~ and $HOME
tuidev_on() {
    local m="$1"
    (cd "$repo" && COPYFILE_DISABLE=1 tar -cf - bin/agents lib/agents configs/herdr/plugins configs/herdr/keys.toml 2>/dev/null) \
        | on "$m" 'mkdir -p ~/.local/share/tuidev ~/.local/bin ~/.config/herdr && tar -xf - -C ~/.local/share/tuidev 2>/dev/null
            ln -sf ~/.local/share/tuidev/bin/agents ~/.local/bin/agents
            herdr plugin link ~/.local/share/tuidev/configs/herdr/plugins/tuidev-link >/dev/null
            { echo; cat ~/.local/share/tuidev/configs/herdr/keys.toml; } >> ~/.config/herdr/config.toml
            herdr server reload-config >/dev/null
            grep -q "local/bin" ~/.bashrc || echo "export PATH=\$HOME/.local/bin:\$PATH" >> ~/.bashrc' \
        || die "could not set up tuidev on $m"
}

# cast MACHINE LABEL DIR KIND SCENARIO — a workspace in ~/DIR on MACHINE
# (empty: this Mac) running one stand-in, named as its agent.
cast() {
    local m="$1" label="$2" dir="$3" kind="$4" scenario="$5" pre=() cwd out pane
    if [[ -n "$m" ]]; then
        pre=(--machine "$m")
        cwd="$(on "$m" "mkdir -p ~/$dir && cd ~/$dir && pwd")"
    else
        mkdir -p "$home/$dir"; cwd="$home/$dir"
    fi
    [[ "$cwd" == /* ]] || die "no directory ~/$dir on ${m:-this Mac}"
    out="$(herdr_demo ${pre[@]+"${pre[@]}"} workspace create --cwd "$cwd" --label "$label" --no-focus 2>&1)" \
        || { echo "$out" >&2; die "workspace create $label on ${m:-this Mac} failed"; }
    pane="$(jq -r '.result.root_pane.pane_id' <<<"$out")"
    [[ -n "$pane" && "$pane" != null ]] || die "no pane in: $out"
    herdr_demo ${pre[@]+"${pre[@]}"} pane run "$pane" "DEMO_AGENT_NAMED=1 demo-agent $kind $scenario" >/dev/null
}

# The page the preview serves, and the review the session "wrote".
storefront_files() {
    on atlas 'mkdir -p ~/storefront && cat > ~/storefront/index.html' <<'HTML'
<!doctype html><meta charset="utf-8"><title>Storefront · checkout</title>
<style>body{font:16px/1.5 -apple-system,system-ui,sans-serif;background:#1a1b26;color:#c0caf5;margin:0;display:grid;place-items:center;min-height:100vh}
main{background:#24283b;padding:40px 48px;border-radius:14px;max-width:520px;box-shadow:0 12px 40px #0008}
h1{margin:0 0 4px;font-size:26px;color:#7aa2f7}small{color:#9aa5ce}ul{padding:0;list-style:none}
li{display:flex;justify-content:space-between;padding:10px 0;border-bottom:1px solid #414868}
button{margin-top:22px;width:100%;padding:13px;border:0;border-radius:9px;background:#9ece6a;color:#1a1b26;font-weight:700;font-size:16px}
footer{margin-top:18px;color:#565f89;font-size:13px}</style>
<main><h1>Checkout</h1><small>storefront preview · served from atlas</small>
<ul><li><span>Mechanical keyboard</span><b>$129</b></li><li><span>USB-C cable × 2</span><b>$18</b></li><li><span>Shipping</span><b>free</b></li></ul>
<button>Pay $147</button><footer>This page runs on another machine. You are reading it through an ssh tunnel.</footer></main>
HTML
    on atlas 'cat > ~/storefront/review.md' <<'MD'
# Checkout page review

Three findings from the preview on atlas:

1. **The total ignores discounts.** `checkout.html` sums line items before the coupon is applied.
2. **The pay button has no disabled state** while the request is in flight, so a double click charges twice.
3. **Shipping says "free" for every region.** The estimate call is stubbed.

Suggested order: 2, 1, 3.
MD
}

up() {
    fleet up "$home"
    home="$(cd "$home" && pwd -P)"
    local m
    tuidev_here
    for m in $TUIDEV_DEMO_MACHINES; do tuidev_on "$m"; done
    storefront_files
    cast ""     payments   payments        claude tests
    cast ""     docs-site  docs-site       codex  review
    cast atlas  storefront storefront      claude preview
    cast atlas  search     search          claude approve
    cast kepler orders-api orders-api      claude leftover
    cast kepler infra      platform-infra  codex  deploy
    for m in $TUIDEV_DEMO_MACHINES; do
        herdr_demo --machine "$m" workspace list \
            | jq -r '.result.workspaces[] | select(.label == "~") | .workspace_id' \
            | while IFS= read -r ws; do herdr_demo --machine "$m" workspace close "$ws" >/dev/null 2>&1 || true; done
    done
    # The watcher, as the LaunchAgent would run it, in the demo's environment.
    # shellcheck disable=SC2030,SC2031
    ( eval "$(fleet env "$home")"; export PATH="$home/.local/bin:$PATH"
      nohup agents link watch > "$home/.demo/link.log" 2>&1 < /dev/null &
      echo $! > "$home/.demo/link.pid" )
    sleep 4
    echo "remote-demo: up. Attach with:"
    echo "  eval \"\$(bash $tapes/remote-demo.sh env $home)\" && herdr"
}

down() {
    if [[ -d "$home" ]]; then
        home="$(cd "$home" && pwd -P)"
        [[ ! -f "$home/.demo/link.pid" ]] || kill "$(cat "$home/.demo/link.pid")" 2>/dev/null || true
        [[ ! -x "$home/.local/bin/agents" ]] || run_demo agents forward close --all >/dev/null 2>&1 || true
    fi
    fleet down "$home"
}

case "$cmd" in
    up)   up ;;
    env)  [[ ! -d "$home" ]] || home="$(cd "$home" && pwd -P)"
          fleet env "$home"; echo "export PATH='$home/.local/bin':\"\$PATH\" AGENTS_MAP_ROOT='$home'" ;;
    down) down ;;
    *)    echo "usage: remote-demo.sh up|env|down HOME" >&2; exit 2 ;;
esac
