#!/bin/sh
# The tuidev.link plugin's commands (herdr-plugin.toml): each hands over to
# `agents` (the monitoring pack), which owns the behavior.
#   click       the clicked link (HERDR_PLUGIN_CLICKED_URL) -> agents link click
#   map         open the Map popup
#   map-pane    the popup itself: agents map
#   ports       open the Ports popup
#   ports-pane  the popup itself: agents ports --pick
#   sync        an event hook: agents herdr sync (nothing, quietly, without agents)
#   sync-poke   an agent's event hook: the same, and the menu bar refreshes
#               (macOS with SwiftBar; elsewhere the same as sync)
agents="${AGENTS_BIN:-$HOME/.local/bin/agents}"
case "${1:-}" in
    sync|sync-poke)
        [ -x "$agents" ] || exit 0
        [ "$1" = sync ] || exec "$agents" herdr sync -q --poke </dev/null
        exec "$agents" herdr sync -q </dev/null ;;
esac
if [ ! -x "$agents" ]; then
    echo "tuidev.link: $agents is missing (./install.sh --pack monitoring)" >&2
    exit 1
fi
case "${1:-}" in
    click)
        [ -n "${HERDR_PLUGIN_CLICKED_URL:-}" ] || { echo "tuidev.link: no clicked link" >&2; exit 1; }
        exec "$agents" link click "$HERDR_PLUGIN_CLICKED_URL" ;;
    map)
        exec "${HERDR_BIN_PATH:-herdr}" plugin pane open --plugin "${HERDR_PLUGIN_ID:-tuidev.link}" --entrypoint map ;;
    map-pane)
        exec "$agents" map ;;
    ports)
        exec "${HERDR_BIN_PATH:-herdr}" plugin pane open --plugin "${HERDR_PLUGIN_ID:-tuidev.link}" --entrypoint ports ;;
    ports-pane)
        exec "$agents" ports --pick ;;
    *)
        echo "usage: run.sh click|map|map-pane|ports|ports-pane|sync|sync-poke" >&2; exit 2 ;;
esac
