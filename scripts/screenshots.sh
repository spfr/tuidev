#!/bin/bash
# Re-render the README images and the social preview: the VHS tapes
# (docs/assets/tapes/*.tape) and the menu-bar picture (scripts/render_menu.sh)
# into docs/assets/.
#
# Usage: scripts/screenshots.sh [NAME...]     e.g. scripts/screenshots.sh sbx menu
#
# NAME is a tape (docs/assets/tapes/NAME.tape) or `menu`; none means all. Each
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
herdr_ready() { command_exists container && command_exists herdr && container system status >/dev/null 2>&1; }

tapes=() menu=0
if [[ $# -gt 0 ]]; then
    for name in "$@"; do
        name="${name%.tape}"; name="${name##*/}"
        if [[ "$name" == menu ]]; then menu=1; continue; fi
        [[ -f "$TAPES_DIR/$name.tape" ]] || die "no tape $TAPES_DIR/$name.tape (or: menu)"
        [[ "$name" != herdr ]] || herdr_ready || die "the herdr tape needs Apple's container CLI, running (container system start), and herdr"
        tapes+=("$TAPES_DIR/$name.tape")
    done
else
    menu=1
    for tape in "$TAPES_DIR"/*.tape; do
        [[ "$(basename "$tape")" == theme.tape ]] && continue   # shared settings, not a shot
        if [[ "$(basename "$tape")" == herdr.tape ]] && ! herdr_ready; then
            print_warning "skipping herdr.tape: it needs Apple's container CLI, running (container system start), and herdr"
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

for tape in "${tapes[@]}"; do
    name="$(basename "$tape" .tape)"
    print_step "rendering $tape"
    # A fresh demo home per tape. The sbx and tour tapes run `sbx` in it, and
    # its home can't live in $TMPDIR (strict lets sbx write there, so the
    # "write outside the project" denial would be false) or under the real
    # home (its path would show the user). /Users/Shared is neither, and
    # /Users/Shared/NAME reads as a home in error messages.
    demo_home="$work/$name/NAME"
    if [[ "$name" == sbx || "$name" == tour ]]; then
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
    print_step "rendering the menu-bar picture (scripts/render_menu.sh)"
    bash "$SCRIPT_DIR/render_menu.sh"
fi

print_success "screenshots rendered:"
for tape in "${tapes[@]}"; do
    tape_outputs "$tape" | while IFS= read -r out; do
        printf '  %s  %s KB\n' "$out" "$(( $(wc -c < "$out") / 1024 ))"
    done
done
if [[ $menu == 1 ]]; then
    for out in docs/assets/menu-light.webp docs/assets/menu-dark.webp docs/assets/menu.gif; do
        if [[ -f "$out" ]]; then printf '  %s  %s KB\n' "$out" "$(( $(wc -c < "$out") / 1024 ))"; fi
    done
fi
