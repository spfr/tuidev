#!/bin/bash
# Re-render the README screenshots and the social preview from their VHS
# tapes (docs/assets/tapes/*.tape) into docs/assets/.
#
# Usage: scripts/screenshots.sh [TAPE...]     e.g. scripts/screenshots.sh sbx
#
# Every tape runs in a throwaway HOME built by docs/assets/tapes/demo-setup.sh,
# and `agents` reads fixture process tables, so nothing from this machine
# reaches an image. Needs VHS (brew install vhs) and, for the sbx shot, macOS.
# See docs/assets/tapes/README.md.
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/ui.sh disable=SC1091
. "$SCRIPT_DIR/lib/ui.sh"

TAPES_DIR="docs/assets/tapes"

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
trap 'rm -rf "$work"' EXIT

for tape in "${tapes[@]}"; do
    name="$(basename "$tape" .tape)"
    print_step "rendering $tape"
    # A fresh demo home per tape; VHS also writes a GIF we don't keep.
    DEMO_HOME="$work/$name/NAME" vhs -o "$work/$name.gif" "$tape" >"$work/$name.log" 2>&1 \
        || die "vhs failed on $tape (inside a sandbox, VHS can't bind its local port)"
done

print_success "screenshots rendered:"
for tape in "${tapes[@]}"; do
    sed -n 's/^Screenshot //p' "$tape" | while IFS= read -r png; do
        printf '  %s  %s KB\n' "$png" "$(( $(wc -c < "$png") / 1024 ))"
    done
done
