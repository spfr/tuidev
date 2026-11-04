#!/bin/bash
# Migration: the ui pack no longer installs Maccy (3.18.0).
#
# It is not a pack, so there is nothing to drop from the profile. The app is
# left installed: removing a brew package on the user's behalf is uninstall.sh's
# job, not a migration's, so this only says how.

set -eo pipefail

MIGRATION_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/ui.sh disable=SC1091
. "$MIGRATION_DIR/../lib/ui.sh"

if [[ -d /Applications/Maccy.app ]]; then
    print_info "tuidev no longer ships Maccy; it was left in place. Remove it with: brew uninstall --cask maccy"
fi
