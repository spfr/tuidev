#!/bin/bash
# Migration: Herdr moves from Homebrew to its release binary (3.12.0).
#
# Homebrew's herdr refuses `herdr update`, so it can never hand a running
# server over to a new binary (`herdr update --handoff`). The herdr pack now
# installs the release binary in ~/.local/bin, checked against the sha256 its
# GitHub release lists. This puts it in place on machines whose pack used
# Homebrew, then says what is left to do by hand:
#
#   - a LaunchAgent or systemd unit that names Homebrew's binary, or that
#     would react badly to a handoff (it is the user's file: never edited);
#   - `brew uninstall herdr`, once no server runs Homebrew's binary.
#
# It never stops a server and never uninstalls anything. A failed download
# is a warning: `install.sh --pack herdr`, `update.sh --packages` and
# `update.sh --configs` (which re-runs the pack) each try again; this
# migration is recorded as applied and does not.
# Safe to re-run; DRY_RUN=true previews it.

set -eo pipefail

MIGRATION_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/ui.sh disable=SC1091
. "$MIGRATION_DIR/../lib/ui.sh"
# shellcheck source=../lib/profile.sh disable=SC1091
. "$MIGRATION_DIR/../lib/profile.sh"
# shellcheck source=../lib/herdr.sh disable=SC1091
. "$MIGRATION_DIR/../lib/herdr.sh"

load_tuidev_profile >/dev/null 2>&1 || exit 0
case " $(tuidev_active_packs | tr '\n' ' ') " in
    *" herdr "*) ;;
    *) exit 0 ;;
esac
# Already a direct install with nothing of Homebrew's left: nothing to do.
if [[ "$(herdr_install_kind)" == direct ]] && ! herdr_brew_installed; then
    exit 0
fi

tuidev_manifest_enable
herdr_switch_to_direct \
    || print_warning "herdr: the release binary is not installed yet; ./install.sh --pack herdr (or ./scripts/update.sh --packages) tries again"
exit 0
