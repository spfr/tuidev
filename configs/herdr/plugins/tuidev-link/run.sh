#!/bin/sh
# The tuidev.link plugin's commands (herdr-plugin.toml): each hands over to
# `agents` (the monitoring pack), which owns the behavior.
#   click       the clicked link (HERDR_PLUGIN_CLICKED_URL) -> agents link click
#   board       open the Board popup, over the pane you are in
#   board-tab   open the Board as a tab; the one it opened, while it is open
#   board-pane, board-tab-pane  the board itself: agents board [--popup]
#               (the tab's pane is kept in the plugin's state dir)
#   map         open the Map popup
#   map-pane    the popup itself: agents map
#   ports       open the Ports popup
#   ports-pane  the popup itself: agents ports --pick
#   palette     open the palette popup
#   palette-pane  the popup itself: tuidev palette
#   update      open the Updates popup
#   update-pane the popup itself: tuidev update --ask, kept up until a key
#   startup     Herdr started: the daily update check when it is due (one
#               toast for a new release), then sync
#   sync        an event hook: agents herdr sync (nothing, quietly, without agents)
#   sync-poke   an agent's event hook: the same, and the menu bar refreshes
#               (macOS with SwiftBar; elsewhere the same as sync)
#   Both reload an open board too (agents board --poke, in the background).
agents="${AGENTS_BIN:-$HOME/.local/bin/agents}"
tuidev="${TUIDEV_BIN:-$HOME/.local/bin/tuidev}"
herdr="${HERDR_BIN_PATH:-herdr}"
plugin="${HERDR_PLUGIN_ID:-tuidev.link}"
case "${1:-}" in
    startup)
        # The sync starts the check itself when it is due (lib/agents/release.sh).
        [ ! -x "$agents" ] || exec "$agents" herdr sync -q </dev/null
        [ ! -x "$tuidev" ] || "$tuidev" latest --if-due --notify </dev/null >/dev/null 2>&1 &
        exit 0 ;;
    palette|update)
        exec "$herdr" plugin pane open --plugin "$plugin" --entrypoint "$1" ;;
    palette-pane|update-pane)
        if [ ! -x "$tuidev" ]; then
            echo "tuidev.link: $tuidev is missing (re-run the installer)" >&2; exit 1
        fi
        # An update re-links this plugin; a hangup from that must not stop it
        # halfway (an ignored signal stays ignored in what this starts).
        trap '' HUP
        TUIDEV_PLUGIN_PANE=1; export TUIDEV_PLUGIN_PANE
        [ "$1" = update-pane ] || TUIDEV_PALETTE_POPUP=1 exec "$tuidev" palette
        "$tuidev" update --ask
        printf '\n[enter closes]'; read -r _
        exit 0 ;;
esac
case "${1:-}" in
    sync|sync-poke)
        [ -x "$agents" ] || exit 0
        # An open board reloads now: one listens while its record is in the
        # run dir's board/ (config.sh's AGENTS_RUN_DIR default). No record, no
        # process; the poke runs beside the sync, so a hook never waits on it.
        for f in "${AGENTS_RUN_DIR:-${TUIDEV_STATE_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/tuidev}/run}"/board/ui.*.listen; do
            if [ -e "$f" ]; then "$agents" board --poke </dev/null >/dev/null 2>&1 & fi
            break
        done
        [ "$1" = sync ] || exec "$agents" herdr sync -q --poke </dev/null
        exec "$agents" herdr sync -q </dev/null ;;
esac
if [ ! -x "$agents" ]; then
    echo "tuidev.link: $agents is missing (tuidev install --pack monitoring)" >&2
    exit 1
fi
case "${1:-}" in
    click)
        [ -n "${HERDR_PLUGIN_CLICKED_URL:-}" ] || { echo "tuidev.link: no clicked link" >&2; exit 1; }
        exec "$agents" link click "$HERDR_PLUGIN_CLICKED_URL" ;;
    board|board-tab)
        # One board tab: the one open already is focused (a plugin pane of
        # ours still called Board; Herdr focuses no other by this call).
        tab="${HERDR_PLUGIN_STATE_DIR:+$HERDR_PLUGIN_STATE_DIR/board-tab}"
        if [ "$1" = board-tab ] && [ -n "$tab" ] && [ -r "$tab" ] && IFS= read -r p < "$tab"; then
            case "$p" in
                ""|*[!A-Za-z0-9:_-]*) ;;
                *) case "$("$herdr" pane get "$p" 2>/dev/null)" in
                       *'"label":"Board"'*) "$herdr" plugin pane focus "$p" >/dev/null 2>&1 && exit 0 ;;
                   esac ;;
            esac
        fi
        # The pane you were in goes along: the board's "-" comes back to it.
        case "${HERDR_PANE_ID:-}" in
            ""|*[!A-Za-z0-9:_-]*) exec "$herdr" plugin pane open --plugin "$plugin" --entrypoint "$1" ;;
        esac
        exec "$herdr" plugin pane open --plugin "$plugin" --entrypoint "$1" --env "AGENTS_BOARD_FROM=$HERDR_PANE_ID" ;;
    board-pane|board-tab-pane)
        # ctrl-p can start an update, which re-links this plugin: as for the
        # palette, a hangup from that must not end the board halfway.
        trap '' HUP
        TUIDEV_PLUGIN_PANE=1; export TUIDEV_PLUGIN_PANE
        [ "$1" = board-tab-pane ] || exec "$agents" board --popup
        case "${HERDR_PANE_ID:-}" in
            ""|*[!A-Za-z0-9:_-]*) ;;
            *) [ -z "${HERDR_PLUGIN_STATE_DIR:-}" ] || { mkdir -p "$HERDR_PLUGIN_STATE_DIR" && printf '%s\n' "$HERDR_PANE_ID" > "$HERDR_PLUGIN_STATE_DIR/board-tab"; } 2>/dev/null ;;
        esac
        exec "$agents" board ;;
    map)
        exec "$herdr" plugin pane open --plugin "$plugin" --entrypoint map ;;
    map-pane)
        exec "$agents" map ;;
    ports)
        exec "$herdr" plugin pane open --plugin "$plugin" --entrypoint ports ;;
    ports-pane)
        exec "$agents" ports --pick ;;
    *)
        echo "usage: run.sh click|board|board-tab|palette|update|map|ports|startup|sync|sync-poke" >&2; exit 2 ;;
esac
