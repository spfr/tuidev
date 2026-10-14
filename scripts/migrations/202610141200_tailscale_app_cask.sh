#!/bin/bash
# Migration: the Tailscale cask is now `tailscale-app` (3.3.0).
#
# Homebrew renamed the `tailscale` cask to `tailscale-app` and moves existing
# installs over on its own. This renames the `cask tailscale` manifest record
# so uninstall names the cask the way Homebrew now lists it.

set -eo pipefail

MIGRATION_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/ui.sh disable=SC1091
. "$MIGRATION_DIR/../lib/ui.sh"
# shellcheck source=../lib/manifest.sh disable=SC1091
. "$MIGRATION_DIR/../lib/manifest.sh"

manifest="$TUIDEV_MANIFEST_FILE"
[[ -f "$manifest" ]] || exit 0
tuidev_manifest_has cask tailscale "$manifest" || exit 0

tmp="$manifest.tmp.$$"
if tuidev_manifest_has cask tailscale-app "$manifest"; then
    grep -vxF 'cask tailscale' "$manifest" > "$tmp" || true
else
    awk '$0 == "cask tailscale" { print "cask tailscale-app"; next } { print }' "$manifest" > "$tmp"
fi
mv "$tmp" "$manifest"
print_success "renamed the tailscale cask record to tailscale-app in $manifest"
