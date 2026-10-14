#!/bin/bash
# Render the README's menu-bar picture from the SwiftBar plugin's real output:
#
#   scripts/render_menu.sh          (also run by `make screenshots`)
#
# It runs configs/swiftbar/agents.10s.sh over the screenshot fixtures (the demo
# `agents` in docs/assets/tapes/bin, a throwaway home, made-up history), then
# draws that output as a macOS menu with docs/assets/menu/menu.html, the SF
# Symbols it names rendered by docs/assets/menu/symbols.swift, and captures it
# with headless Chrome at 2x:
#
#   docs/assets/menu-light.webp, menu-dark.webp the menu, with the submenu of
#                                               its first stuck command open
#   docs/assets/menu.gif                        the menu, then four submenus
#
# So when the plugin's output changes, re-running this redraws the picture.
# Nothing is read from this machine's processes or menu bar. macOS only; needs
# Google Chrome or Chromium (CHROME=/path/to/binary to choose) and Swift (the
# Xcode command-line tools). See docs/assets/tapes/README.md.
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/ui.sh disable=SC1091
. "$SCRIPT_DIR/lib/ui.sh"

TAPES="$REPO_DIR/docs/assets/tapes"
TEMPLATE="$REPO_DIR/docs/assets/menu"
OUT="$REPO_DIR/docs/assets"

is_macos || die "render_menu.sh runs on macOS only (SF Symbols and the menu it draws are macOS's)"
command_exists swift || die "Swift is not installed: xcode-select --install"
command_exists jq || die "jq is not installed: brew install jq"
chrome="${CHROME:-}"
if [[ -z "$chrome" ]]; then
    for c in "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
             "$HOME/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
             "/Applications/Chromium.app/Contents/MacOS/Chromium"; do
        [[ -x "$c" ]] && { chrome="$c"; break; }
    done
fi
[[ -n "$chrome" && -x "$chrome" ]] || die "Google Chrome or Chromium not found (set CHROME=/path/to/binary)"

work="$(mktemp -d "${TMPDIR:-/tmp}/tuidev-menu.XXXXXX")"
trap 'rm -rf "$work"' EXIT
page="$work/page"
mkdir -p "$page"
cp "$TEMPLATE/menu.html" "$page/"

# 1. The plugin's output over the fixtures. The first run starts the Herdr
#    status cache; the second shows it (as SwiftBar's second refresh would).
(
    export DEMO_HOME="$work/home/NAME"
    # shellcheck source=../docs/assets/tapes/demo-env.sh disable=SC1091
    source "$TAPES/demo-env.sh" >/dev/null
    export AGENTS_BIN="$TAPES/bin/agents" USER=NAME
    /bin/bash "$REPO_DIR/configs/swiftbar/agents.10s.sh" >/dev/null 2>&1 || true
    sleep 1
    /bin/bash "$REPO_DIR/configs/swiftbar/agents.10s.sh" > "$work/menu.txt"
)
[[ -s "$work/menu.txt" ]] || die "the plugin printed nothing"
grep -q '^Needs you' "$work/menu.txt" || die "the plugin's output has no Needs you section; check the fixtures"

# 2. Every SF Symbol it names (sfimage=, and :name: in the text), plus the
#    menu's own chevron and checkmark.
symbols="$( { grep -oE 'sfimage=[A-Za-z0-9.]+' "$work/menu.txt" | cut -d= -f2
             grep -oE ':[a-z0-9]+(\.[a-z0-9]+)+:|:[a-z]+:' "$work/menu.txt" | tr -d ':'
             echo chevron.right; echo checkmark; } | sort -u)"
# shellcheck disable=SC2086 # one symbol name per word
swift "$TEMPLATE/symbols.swift" "$page" 13 $symbols 2>"$work/symbols.log" \
    || { cat "$work/symbols.log" >&2; die "symbols.swift failed"; }

# 3. Capture. menu.js carries the output and the open submenus; a first,
#    DOM-only pass reads the size the page drew (its title), the second
#    takes the picture at 2x.
chrome_run() {
    "$chrome" --headless=new --disable-gpu --hide-scrollbars --no-first-run --no-default-browser-check \
        --user-data-dir="$work/chrome" --force-device-scale-factor=2 --virtual-time-budget=2000 "$@" 2>/dev/null
}
# capture THEME OUT OPEN_JSON [FIXED_JSON]
capture() {
    local theme="$1" out="$2" open="$3" fixed="${4:-null}" size w h
    { printf 'window.MENU = %s;\n' "$(jq -Rs . < "$work/menu.txt")"
      printf 'window.OPEN = %s;\nwindow.FIXED = %s;\n' "$open" "$fixed"; } > "$page/menu.js"
    size="$(chrome_run --dump-dom "file://$page/menu.html?theme=$theme" | sed -n 's:.*<title>\([0-9]* [0-9]*\)</title>.*:\1:p')"
    read -r w h <<<"$size"
    [[ "$w" =~ ^[0-9]+$ && "$h" =~ ^[0-9]+$ ]] || die "could not lay out the menu (theme $theme)"
    chrome_run --window-size="$w,$h" --default-background-color=00000000 \
        --screenshot="$out" "file://$page/menu.html?theme=$theme" >/dev/null
    [[ -s "$out" ]] || die "Chrome wrote no screenshot to $out"
    echo "$w $h"
}

# The stills: the first stuck or long command's verdict, in both appearances.
first="$(grep -m1 -E '^[^-].* · (stuck|running) [0-9]' "$work/menu.txt" | cut -d'|' -f1 | cut -c1-12)"
[[ -n "$first" ]] || die "no stuck or long command in Needs you"
open="$(jq -cn --arg a "$first" '[$a]')"
# WebP: the desktop gradient behind the menu makes a PNG of it near 1 MB.
for theme in light dark; do
    capture "$theme" "$work/menu-$theme.png" "$open" >/dev/null
    if command_exists cwebp; then
        cwebp -quiet -q 90 "$work/menu-$theme.png" -o "$OUT/menu-$theme.webp"
    elif command_exists magick; then
        magick "$work/menu-$theme.png" -quality 90 "$OUT/menu-$theme.webp"
    else
        die "cwebp or ImageMagick is needed for the WebP stills: brew install webp"
    fi
done

# The GIF: closed, then the verdict, the CPU by job, keep-awake with the lid
# closed, and the system line, all on one canvas (the largest frame's size).
frames=(
    '[]'
    "$open"
    "$(jq -cn --arg a "$(grep -m1 -E '^[a-z ]+ · [0-9<]+% · ' "$work/menu.txt" | cut -d'|' -f1 | cut -c1-8)" '[$a]')"
    '["Awake:", "Lid closed too"]'
    '["CPU "]'
)
maxw=0 maxh=0
for i in "${!frames[@]}"; do
    read -r w h <<<"$(capture dark "$work/probe.png" "${frames[$i]}")"
    [[ $w -gt $maxw ]] && maxw=$w
    [[ $h -gt $maxh ]] && maxh=$h
done
for i in "${!frames[@]}"; do
    capture dark "$work/frame$i.png" "${frames[$i]}" "[$maxw,$maxh]" >/dev/null
done
if command_exists ffmpeg; then
    ffmpeg -v error -y -framerate 1/2.4 -i "$work/frame%d.png" \
        -vf "scale=iw/2:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=256:stats_mode=full[p];[b][p]paletteuse=dither=sierra2_4a" \
        -loop 0 "$OUT/menu.gif"
else
    print_warning "ffmpeg not found: menu.gif not rendered (brew install ffmpeg)"
fi

print_success "menu rendered from the plugin's output: docs/assets/menu-light.webp, menu-dark.webp, menu.gif"
