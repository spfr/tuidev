#!/bin/bash
# Migration: the bosun, yazi and nnn packs were removed (tuidev 3.0).
#
# Drops them from extra_packs so update, health check and uninstall stop
# looking for pack scripts that no longer exist. The tools themselves stay
# installed: tuidev never uninstalls a user's tools.

set -eo pipefail

MIGRATION_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/profile.sh disable=SC1091
. "$MIGRATION_DIR/../lib/profile.sh"

profile="$TUIDEV_PROFILE_FILE_DEFAULT"

if [[ ! -f "$profile" ]]; then
    print_info "no tuidev profile — nothing to drop"
    exit 0
fi

dropped=""
for pack in bosun yazi nnn; do
    rc=0
    tuidev_profile_remove_pack "$pack" "$profile" || rc=$?
    case "$rc" in
        0) dropped="${dropped:+$dropped }$pack" ;;
        1) ;;
        *) print_error "could not update $profile"; exit 1 ;;
    esac
done

if [[ -z "$dropped" ]]; then
    print_info "bosun, yazi and nnn were not recorded — nothing to drop"
    exit 0
fi

print_success "removed from extra_packs: $dropped"
print_info "Those packs no longer exist; the tools themselves were left installed."
