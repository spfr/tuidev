#!/bin/bash
# Re-render the README screenshots and the social preview from their VHS
# tapes (docs/assets/tapes/*.tape) into docs/assets/.
#
# Usage: scripts/screenshots.sh [TAPE...]     e.g. scripts/screenshots.sh sbx
#
# Each tape gets a throwaway HOME; the agents and sbx tapes build it with
# docs/assets/tapes/demo-setup.sh, and `agents` reads fixture process tables,
# so nothing from this machine reaches an image. macOS only (the sbx shot
# needs Seatbelt, and the demo is only checked there); needs VHS
# (brew install vhs). See docs/assets/tapes/README.md.
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/ui.sh disable=SC1091
. "$SCRIPT_DIR/lib/ui.sh"

TAPES_DIR="docs/assets/tapes"

is_macos || die "make screenshots runs on macOS only: the sbx shot needs Seatbelt (sandbox-exec)"
command_exists vhs || die "VHS is not installed: brew install vhs (https://github.com/charmbracelet/vhs)"

cd "$REPO_DIR"

tapes=()
if [[ $# -gt 0 ]]; then
    for name in "$@"; do
        name="${name%.tape}"; name="${name##*/}"
        [[ -f "$TAPES_DIR/$name.tape" ]] || die "no tape $TAPES_DIR/$name.tape"
        tapes+=("$TAPES_DIR/$name.tape")
    done
else
    for tape in "$TAPES_DIR"/*.tape; do
        [[ "$(basename "$tape")" == theme.tape ]] && continue   # shared settings, not a shot
        tapes+=("$tape")
    done
fi

work="$(mktemp -d "${TMPDIR:-/tmp}/tuidev-screenshots.XXXXXX")"
sbx_home=""
trap 'rm -rf "$work"; [[ -z "$sbx_home" ]] || rm -rf "$sbx_home"' EXIT

for tape in "${tapes[@]}"; do
    name="$(basename "$tape" .tape)"
    print_step "rendering $tape"
    # A fresh demo home per tape; VHS also writes a GIF we don't keep. The
    # sbx tape's home can't live in $TMPDIR (strict lets sbx write there, so
    # the "write outside the project" denial would be false) or under the real
    # home (its path would show the user). /Users/Shared is neither, and
    # /Users/Shared/NAME reads as a home in error messages.
    # VHS silently keeps an existing PNG, so remove the old one first.
    sed -n 's/^Screenshot //p' "$tape" | while IFS= read -r png; do rm -f "$png"; done
    demo_home="$work/$name/NAME"
    if [[ "$name" == sbx ]]; then
        demo_home="/Users/Shared/NAME"
        [[ ! -e "$demo_home" ]] || die "$demo_home already exists; remove it (a leftover demo home) and re-run"
        sbx_home="$demo_home"
    fi
    if ! DEMO_HOME="$demo_home" vhs -o "$work/$name.gif" "$tape" >"$work/$name.log" 2>&1; then
        tail -20 "$work/$name.log" >&2
        if grep -qiE 'randomPort|bind|operation not permitted' "$work/$name.log"; then
            print_info "VHS could not listen on a local port: a sandbox that blocks binding one (Claude Code's native sandbox, by default) does this; run it outside"
        fi
        die "vhs failed on $tape (its log is above)"
    fi
done

print_success "screenshots rendered:"
for tape in "${tapes[@]}"; do
    sed -n 's/^Screenshot //p' "$tape" | while IFS= read -r png; do
        printf '  %s  %s KB\n' "$png" "$(( $(wc -c < "$png") / 1024 ))"
    done
done
