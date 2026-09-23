#!/bin/bash
#
# check_links.sh — every relative Markdown link in the repo resolves.
#
# Scans tracked *.md files (git ls-files), extracts `](target)` links, skips
# URLs, mail links and pure #anchors, and resolves the rest against the
# linking file's directory. Anchors and query strings are ignored — this checks
# that the file or directory exists, not the heading.
#
# Usage: scripts/check_links.sh        (exit 1 if any link is broken)
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=./lib/ui.sh disable=SC1091
. "$SCRIPT_DIR/lib/ui.sh"

cd "$REPO_ROOT"

broken=0
checked=0
while IFS= read -r md; do
    [[ -f "$md" ]] || continue   # tracked but deleted in the working tree
    dir="$(dirname "$md")"
    # One link target per line; `|| true` because most files have none.
    while IFS= read -r target; do
        case "$target" in
            http://*|https://*|mailto:*|\#*|'') continue ;;
        esac
        path="${target%%#*}"
        path="${path%%\?*}"
        [[ -n "$path" ]] || continue
        checked=$((checked + 1))
        if [[ ! -e "$dir/$path" ]]; then
            print_error "$md → $target"
            broken=$((broken + 1))
        fi
    done < <(grep -oE '\]\([^) ]+\)' "$md" | sed -E 's/^\]\(//; s/\)$//' || true)
done < <(git ls-files '*.md')

if [[ $broken -gt 0 ]]; then
    print_error "$broken broken link(s) out of $checked"
    exit 1
fi
print_success "$checked relative links resolve"
