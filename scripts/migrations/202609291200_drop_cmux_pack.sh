#!/bin/bash
# Migration: the cmux pack was removed (3.2.4).
#
# tmux is the multiplexer tuidev ships. This drops `cmux` from extra_packs so
# update, health check and uninstall stop looking for a pack script that no
# longer exists. The cmux app is left installed: removing a brew package on
# the user's behalf is uninstall.sh's job, not a migration's, so we print the
# command instead.

set -eo pipefail

MIGRATION_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/ui.sh disable=SC1091
. "$MIGRATION_DIR/../lib/ui.sh"
# shellcheck source=../lib/profile.sh disable=SC1091
. "$MIGRATION_DIR/../lib/profile.sh"

profile="$TUIDEV_PROFILE_FILE_DEFAULT"
if [[ -f "$profile" ]]; then
    rc=0
    tuidev_profile_remove_pack cmux "$profile" || rc=$?
    case "$rc" in
        0) print_success "dropped cmux from extra_packs in $profile" ;;
        1) ;;
        *) print_error "could not update $profile"; exit 1 ;;
    esac
fi

if command -v cmux >/dev/null 2>&1 || [[ -d /Applications/cmux.app ]]; then
    print_info "cmux left in place — remove it with: brew uninstall --cask cmux"
fi
