#!/bin/bash
# Re-render the README images, the clips and the social preview: the VHS
# tapes (docs/assets/tapes/*.tape) and the menu-bar picture
# (scripts/render_menu.sh) into docs/assets/.
#
# Usage: scripts/screenshots.sh [NAME...]     e.g. scripts/screenshots.sh sbx menu
#
# NAME is a tape (docs/assets/tapes/NAME.tape), `menu`, `clip-menu` (the
# menu's clip, rendered with it), `clip-remote` (cut from the remote
# screencast) or `clips` (every clip); none means all. A clip (clip-*.tape)
# writes docs/assets/clips/NAME.mp4; then its caption from
# docs/assets/tapes/clips.txt is burned in at the bottom (CLIP_CAPTIONS=0
# leaves it out) and NAME.gif is made from it, with ffmpeg and ImageMagick. Each
# tape gets a throwaway HOME, built by docs/assets/tapes/demo-setup.sh (and
# demo-shell-setup.sh for the shell shots), and `agents` reads fixture process
# tables, so nothing from this machine reaches an image. The herdr tape also
# starts two Linux containers as SSH machines (herdr-demo.sh) and removes
# them afterwards. macOS only (the sbx shots need Seatbelt, and the demo is
# only checked there); needs VHS (brew install vhs). See
# docs/assets/tapes/README.md.
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/ui.sh disable=SC1091
. "$SCRIPT_DIR/lib/ui.sh"

TAPES_DIR="docs/assets/tapes"
CLIPS_DIR="docs/assets/clips"

is_macos || die "make screenshots runs on macOS only: the sbx shot needs Seatbelt (sandbox-exec)"
command_exists vhs || die "VHS is not installed: brew install vhs (https://github.com/charmbracelet/vhs)"

# The shots show eza's file icons, which JetBrains Mono lacks. Ghostty draws
# them out of the box; VHS needs the Symbols Nerd Font installed to fall back to.
# (ls fails when either glob is unmatched, so look in each place on its own.)
if ! ls "$HOME"/Library/Fonts/SymbolsNerdFont* >/dev/null 2>&1 && ! ls /Library/Fonts/SymbolsNerdFont* >/dev/null 2>&1; then
    print_warning "Symbols Nerd Font not found: icons in the shots will render as blanks (brew install --cask font-symbols-only-nerd-font)"
fi

cd "$REPO_DIR"

# The herdr tape needs a container runtime and Herdr; without them it is
# skipped when every tape runs, and an error when asked for by name.
# shellcheck source=lib/container.sh disable=SC1091
. "$SCRIPT_DIR/lib/container.sh"
herdr_ready() {
    command_exists herdr || return 1
    case "$(tuidev_container_runtime)" in
        container) container system status >/dev/null 2>&1 ;;
        podman) podman info >/dev/null 2>&1 ;;
        *) return 1 ;;
    esac
}

# The remote clip is not a tape: it is cut from the screencast remote.tape
# records, with the browser shot cut in (remote-cut.mp4, made by hand:
# docs/assets/tapes/README.md), at these seconds: the three machines, the
# map forwarding atlas's preview, the page, the review fetched and read.
REMOTE_CUT="docs/assets/remote-cut.mp4"
REMOTE_SEGMENTS="0-3 16-21 23.5-27 41-43 50.5-54"

tapes=() menu=0 remote=0
if [[ $# -gt 0 ]]; then
    for name in "$@"; do
        name="${name%.tape}"; name="${name##*/}"
        case "$name" in
            menu|clip-menu) menu=1; continue ;;
            clip-remote)
                [[ -f "$REMOTE_CUT" ]] || die "the remote clip is cut from $REMOTE_CUT, which is not here (docs/assets/tapes/README.md says how it is made)"
                remote=1; continue ;;
            clips)
                for tape in "$TAPES_DIR"/clip-*.tape; do tapes+=("$tape"); done
                menu=1 remote=1; continue ;;
        esac
        [[ -f "$TAPES_DIR/$name.tape" ]] || die "no tape $TAPES_DIR/$name.tape (or: menu, clip-menu, clip-remote, clips)"
        [[ "$name" != herdr ]] || herdr_ready || die "the herdr tape needs herdr and a running Apple container (container system start) or podman (podman machine start; TUIDEV_CONTAINER_RUNTIME=podman picks it)"
        tapes+=("$TAPES_DIR/$name.tape")
    done
else
    menu=1 remote=1
    for tape in "$TAPES_DIR"/*.tape; do
        [[ "$(basename "$tape")" == theme.tape ]] && continue   # shared settings, not a shot
        if [[ "$(basename "$tape")" == herdr.tape ]] && ! herdr_ready; then
            print_warning "skipping herdr.tape: it needs herdr and a running Apple container or podman (TUIDEV_CONTAINER_RUNTIME)"
            continue
        fi
        tapes+=("$tape")
    done
fi

# Under /tmp, not $TMPDIR: a demo home holds the fake Herdr socket `agents`
# looks for, and macOS's long $TMPDIR would push its path past the 104 bytes
# a Unix socket path may have (`agents` would then show no Herdr status).
work="$(mktemp -d /tmp/tuidev-shots.XXXXXX)"
sbx_home="" fleet=""
cleanup() {
    rm -rf "$work"
    [[ -z "$sbx_home" ]] || rm -rf "$sbx_home"
    if [[ -n "$fleet" ]]; then
        bash "$TAPES_DIR/herdr-demo.sh" down "$fleet/NAME" || true
        rm -rf "$fleet"
    fi
}
trap cleanup EXIT

# The files a tape writes: its Screenshot lines and its Output lines.
tape_outputs() { sed -n -e 's/^Screenshot //p' -e 's/^Output //p' "$1"; }

# The clips: a caption burned in at the bottom, then a GIF.
CLIP_MAX_W=1200   # px: README, release notes and social posts show them smaller
CLIP_BAR_H=56     # px: the caption's strip, under the terminal
CLIP_FPS=10       # the GIF's frame rate (VHS records the clips at it too)
# The caption is set in the shots' font, JetBrains Mono, when it is installed.
clip_font() {
    local f
    for f in "$HOME/Library/Fonts/JetBrainsMono-Medium.ttf" /Library/Fonts/JetBrainsMono-Medium.ttf \
             "$HOME/Library/Fonts/JetBrainsMono-Regular.ttf" /Library/Fonts/JetBrainsMono-Regular.ttf; do
        [[ -f "$f" ]] && { echo "$f"; return 0; }
    done
    return 0
}
# clip_caption NAME — its line in clips.txt, without the name; nothing with
# CLIP_CAPTIONS=0.
clip_caption() {
    [[ "${CLIP_CAPTIONS:-1}" != 0 ]] || return 0
    awk -v n="$1" '$1 == n { sub(/^[^ \t]+[ \t]+/, ""); print; exit }' "$TAPES_DIR/clips.txt"
}
# clip_finish NAME — docs/assets/clips/NAME.mp4 as it was recorded: at most
# CLIP_MAX_W wide, its caption in a strip under it (the margin's color, so it
# reads as part of the frame), re-encoded small; then NAME.gif from it.
clip_finish() {
    local name="$1" mp4="$CLIPS_DIR/$1.mp4" gif="$CLIPS_DIR/$1.gif" tmp="$work/clip-$1" caption font w vf
    command_exists ffmpeg || { print_warning "ffmpeg not found: $mp4 is left as recorded, without its caption or GIF (brew install ffmpeg)"; return 0; }
    mkdir -p "$tmp"
    caption="$(clip_caption "$name")"
    if [[ -n "$caption" ]] && ! command_exists magick; then
        print_warning "ImageMagick not found: $mp4 gets no caption (brew install imagemagick)"; caption=""
    fi
    w="$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of csv=p=0 "$mp4")"
    [[ "$w" =~ ^[0-9]+$ ]] || die "could not read the width of $mp4"
    [[ $w -le $CLIP_MAX_W ]] || w=$CLIP_MAX_W
    w=$((w / 2 * 2))
    vf="scale=$w:-2:flags=lanczos"
    if [[ -n "$caption" ]]; then
        font="$(clip_font)"
        # The text fits the strip's width (smaller type in a narrow clip), at
        # most 26 px tall; % is ImageMagick's escape, so it is doubled.
        magick -background none -fill "#c0caf5" ${font:+-font "$font"} -size "$((w - 48))x$((CLIP_BAR_H - 30))" \
            -gravity center caption:"${caption//%/%%}" "$tmp/text.png"
        magick -size "${w}x$CLIP_BAR_H" xc:"#16161e" "$tmp/text.png" -gravity center -composite "$tmp/bar.png"
        ffmpeg -v error -y -i "$mp4" -i "$tmp/bar.png" \
            -filter_complex "[0:v]$vf,pad=iw:ih+$CLIP_BAR_H:0:0:color=0x16161e[v];[v][1:v]overlay=0:main_h-overlay_h" \
            -c:v libx264 -preset slow -crf 26 -pix_fmt yuv420p -movflags +faststart -an "$tmp/out.mp4"
    else
        ffmpeg -v error -y -i "$mp4" -vf "$vf" -c:v libx264 -preset slow -crf 26 -pix_fmt yuv420p -movflags +faststart -an "$tmp/out.mp4"
    fi
    mv -f "$tmp/out.mp4" "$mp4"
    # Flat terminal colors: a 64-color palette, no dither, only what changed.
    ffmpeg -v error -y -i "$mp4" \
        -vf "fps=$CLIP_FPS,split[a][b];[a]palettegen=max_colors=64:stats_mode=diff[p];[b][p]paletteuse=dither=none:diff_mode=rectangle" \
        -loop 0 "$gif"
    if command_exists gifsicle; then gifsicle -b -O3 --lossy=30 "$gif" 2>/dev/null || print_warning "gifsicle could not optimize $gif"; fi
}
# clip_remote — docs/assets/clips/remote.mp4: REMOTE_SEGMENTS of REMOTE_CUT
# end to end, the last frame held 2 s as the tapes do; then clip_finish.
clip_remote() {
    local seg a b i=0 graph="" ins=""
    command_exists ffmpeg || { print_warning "ffmpeg not found: no remote clip (brew install ffmpeg)"; return 0; }
    for seg in $REMOTE_SEGMENTS; do
        a="${seg%-*}" b="${seg#*-}"
        graph+="[0:v]trim=start=$a:end=$b,setpts=PTS-STARTPTS[s$i];"
        ins+="[s$i]"; i=$((i + 1))
    done
    graph+="${ins}concat=n=$i:v=1:a=0,fps=$CLIP_FPS,tpad=stop_mode=clone:stop_duration=2[out]"
    ffmpeg -v error -y -i "$REMOTE_CUT" -filter_complex "$graph" -map "[out]" \
        -c:v libx264 -preset slow -crf 20 -pix_fmt yuv420p -an "$CLIPS_DIR/remote.mp4"
    clip_finish remote
}

mkdir -p "$CLIPS_DIR"
for tape in "${tapes[@]}"; do
    name="$(basename "$tape" .tape)"
    print_step "rendering $tape"
    # A fresh demo home per tape. The sbx and tour tapes run `sbx` in it, and
    # its home can't live in $TMPDIR (strict lets sbx write there, so the
    # "write outside the project" denial would be false) or under the real
    # home (its path would show the user). /Users/Shared is neither, and
    # /Users/Shared/NAME reads as a home in error messages.
    demo_home="$work/$name/NAME"
    if [[ "$name" == sbx || "$name" == tour || "$name" == clip-keys || "$name" == clip-install ]]; then
        demo_home="/Users/Shared/NAME"
        [[ ! -e "$demo_home" ]] || die "$demo_home already exists; remove it (a leftover demo home) and re-run"
        sbx_home="$demo_home"
    fi
    # The Herdr fleet's home holds its sockets, so its path must be short.
    if [[ "$name" == herdr ]]; then
        fleet="$(mktemp -d /tmp/tuidev-herdr.XXXXXX)"
        demo_home="$fleet/NAME"
        print_info "starting the Herdr fleet: this Mac plus devbox and workbox (containers)"
        bash "$TAPES_DIR/herdr-demo.sh" up "$demo_home" >"$work/herdr-demo.log" 2>&1 \
            || { tail -20 "$work/herdr-demo.log" >&2; die "herdr-demo.sh up failed (its log is above)"; }
    fi
    # Remove the old images, so a shot VHS fails to write can't pass as fresh.
    tape_outputs "$tape" | while IFS= read -r out; do rm -f "$out"; done
    # A tape without its own Output also gets a GIF we don't keep.
    vhs_out=(-o "$work/$name.gif")
    if grep -q '^Output ' "$tape"; then vhs_out=(); fi
    # Nothing from a Herdr pane this runs in reaches the demo's own Herdr.
    if ! env -u HERDR_ENV -u HERDR_SOCKET_PATH -u HERDR_PANE_ID -u HERDR_TAB_ID -u HERDR_WORKSPACE_ID -u HERDR_SESSION \
        DEMO_HOME="$demo_home" vhs ${vhs_out[@]+"${vhs_out[@]}"} "$tape" >"$work/$name.log" 2>&1; then
        tail -20 "$work/$name.log" >&2
        if grep -qiE 'randomPort|bind|operation not permitted' "$work/$name.log"; then
            print_info "VHS could not listen on a local port: a sandbox that blocks binding one (Claude Code's native sandbox, by default) does this; run it outside"
        fi
        die "vhs failed on $tape (its log is above)"
    fi
    # VHS drops a Screenshot that is the tape's last command: end tapes with a Sleep.
    tape_outputs "$tape" | while IFS= read -r out; do
        [[ -s "$out" ]] || { tail -20 "$work/$name.log" >&2; die "$tape did not write $out (end the tape with a Sleep after its Screenshot)"; }
    done
    # A clip gets its caption and its GIF.
    if [[ "$name" == clip-* ]]; then clip_finish "${name#clip-}"; fi
    # Smaller GIFs, when gifsicle is installed (brew install gifsicle).
    if command_exists gifsicle; then
        tape_outputs "$tape" | while IFS= read -r out; do
            [[ "$out" != *.gif ]] || gifsicle -b -O3 --lossy=30 "$out" 2>/dev/null || print_warning "gifsicle could not optimize $out"
        done
    fi
    if [[ -n "$sbx_home" ]]; then rm -rf "$sbx_home"; sbx_home=""; fi
    if [[ -n "$fleet" ]]; then
        bash "$TAPES_DIR/herdr-demo.sh" down "$demo_home" || true
        rm -rf "$fleet"; fleet=""
    fi
done

if [[ $menu == 1 ]]; then
    print_step "rendering the menu-bar picture and its clip (scripts/render_menu.sh)"
    bash "$SCRIPT_DIR/render_menu.sh"
    if [[ -s "$CLIPS_DIR/menu.mp4" ]]; then clip_finish menu; fi
fi
if [[ $remote == 1 ]]; then
    if [[ -f "$REMOTE_CUT" ]]; then
        print_step "cutting the remote clip from $REMOTE_CUT"
        clip_remote
    else
        print_warning "skipping the remote clip: $REMOTE_CUT is not here (it is made by hand: docs/assets/tapes/README.md)"
        remote=0
    fi
fi

print_success "screenshots rendered:"
for tape in "${tapes[@]}"; do
    tape_outputs "$tape" | while IFS= read -r out; do
        printf '  %s  %s KB\n' "$out" "$(( $(wc -c < "$out") / 1024 ))"
    done
done
if [[ $menu == 1 ]]; then
    for out in docs/assets/menu-light.webp docs/assets/menu-dark.webp docs/assets/menu.gif "$CLIPS_DIR/menu.mp4" "$CLIPS_DIR/menu.gif"; do
        if [[ -f "$out" ]]; then printf '  %s  %s KB\n' "$out" "$(( $(wc -c < "$out") / 1024 ))"; fi
    done
fi
if [[ $remote == 1 ]]; then
    for out in "$CLIPS_DIR/remote.mp4" "$CLIPS_DIR/remote.gif"; do
        if [[ -f "$out" ]]; then printf '  %s  %s KB\n' "$out" "$(( $(wc -c < "$out") / 1024 ))"; fi
    done
fi
