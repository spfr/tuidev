#!/bin/bash
# Migration: OpenCode moved out of --pack ai-clis into its own --pack opencode
# (tuidev 3.0).
#
# The ai-clis shell fragment no longer defines `oc`, and ~/.zshrc no longer
# puts ~/.opencode/bin on PATH — the new opencode fragment does both. So:
#   - OpenCode installed and ai-clis recorded: add `opencode` to extra_packs
#     so `update.sh --configs` (which re-reads the profile after migrations)
#     places the new fragment in the same run and `oc` keeps working.
#   - OpenCode not installed: nothing to do; it stays opt-in.
# ~/.config/opencode is never touched — it is the user's config either way.

set -eo pipefail

MIGRATION_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/profile.sh disable=SC1091
. "$MIGRATION_DIR/../lib/profile.sh"

profile="$TUIDEV_PROFILE_FILE_DEFAULT"

if ! command -v opencode >/dev/null 2>&1 && [[ ! -x "$HOME/.opencode/bin/opencode" ]]; then
    print_info "OpenCode not installed — --pack opencode stays opt-in"
    exit 0
fi

if [[ ! -f "$profile" ]] || ! grep -q '^extra_packs=' "$profile"; then
    print_info "no extra_packs recorded — nothing to carry over"
    exit 0
fi

load_tuidev_profile "$profile"
case " $TUIDEV_EXTRA_PACKS " in
    *" ai-clis "*) ;;
    *) print_info "ai-clis not recorded — nothing to carry over"; exit 0 ;;
esac

if tuidev_profile_add_pack opencode "$profile"; then
    print_success "added opencode to extra_packs in $profile (keeps the oc wrapper)"
    print_info "Apply it with: ./scripts/update.sh --configs"
else
    print_info "opencode pack already recorded"
fi
