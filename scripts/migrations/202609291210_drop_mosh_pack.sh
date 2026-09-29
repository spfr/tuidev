#!/bin/bash
# Migration: the mosh pack was removed (3.2.4).
#
# --remote already installs mosh, so the pack only duplicated it. This drops
# `mosh` from extra_packs so update, health check and uninstall stop looking
# for a pack script that no longer exists. The mosh binary is left installed.

set -eo pipefail

MIGRATION_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/ui.sh disable=SC1091
. "$MIGRATION_DIR/../lib/ui.sh"
# shellcheck source=../lib/profile.sh disable=SC1091
. "$MIGRATION_DIR/../lib/profile.sh"

profile="$TUIDEV_PROFILE_FILE_DEFAULT"
[[ -f "$profile" ]] || exit 0

rc=0
tuidev_profile_remove_pack mosh "$profile" || rc=$?
case "$rc" in
    0)
        print_success "dropped mosh from extra_packs in $profile"
        if ! grep -qx 'remote=true' "$profile"; then
            print_info "mosh stays installed; ./install.sh --remote now owns it"
        fi
        ;;
    1) ;;
    *) print_error "could not update $profile"; exit 1 ;;
esac
