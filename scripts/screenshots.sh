#!/bin/bash
# Re-render the README images and the social preview from their VHS tapes
# (docs/assets/tapes/*.tape) into docs/assets/.
#
# Usage: scripts/screenshots.sh [TAPE...]     e.g. scripts/screenshots.sh sbx
#
# Each tape gets a throwaway HOME, built by docs/assets/tapes/demo-setup.sh
# (and demo-shell-setup.sh for the shell shots), and `agents` reads fixture
# process tables, so nothing from this machine reaches an image. macOS only
# (the sbx shots need Seatbelt, and the demo is only checked there); needs VHS
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
    # Remove the old images, so a shot VHS fails to write can't pass as fresh.
    tape_outputs "$tape" | while IFS= read -r out; do rm -f "$out"; done
    # A tape without its own Output also gets a GIF we don't keep.
    vhs_out=(-o "$work/$name.gif")
    if grep -q '^Output ' "$tape"; then vhs_out=(); fi
    if ! DEMO_HOME="$demo_home" vhs ${vhs_out[@]+"${vhs_out[@]}"} "$tape" >"$work/$name.log" 2>&1; then
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
    if [[ -n "$sbx_home" ]]; then rm -rf "$sbx_home"; sbx_home=""; fi
done

print_success "screenshots rendered:"
for tape in "${tapes[@]}"; do
    tape_outputs "$tape" | while IFS= read -r out; do
        printf '  %s  %s KB\n' "$out" "$(( $(wc -c < "$out") / 1024 ))"
    done
done
