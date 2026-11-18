#!/usr/bin/env bash
# No hardcoded user paths, personal mDNS hosts or tailnet names in shipped
# configs, scripts and docs, and none of the terms you list as private. Run
# by CI's `check-paths` job and by `make check-paths` (part of `make
# ci-test`), so the local gate and CI agree. Exit 1 lists the hits.
set -euo pipefail

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

failed=0
roots=(configs scripts bin lib templates .github .gitignore .gitleaksignore get.sh VERSION install.sh uninstall.sh Makefile Dockerfile docs README.md VISION.md CLAUDE.md AGENTS.md CONTRIBUTING.md SECURITY.md CHANGELOG.md)

# Placeholder spellings docs use to *describe* the rule rather than
# violate it — including the mDNS examples in docs/remote.md, and the
# screenshot demo's home (/Users/Shared/NAME, see docs/assets/tapes).
filter_placeholders() {
    grep -vE '/Users/NAME|/home/NAME|/Users/Shared/NAME|/Users/username|/home/username|@(hostname|HOSTNAME|host|machine|example|your-[A-Za-z0-9-]+)\.local\b' || true
}

# scan LABEL PATTERN [EXTRA_EXCLUDE_PATTERN]
# Matches are captured ONCE and reused for both the test and the
# printed list. The old form piped grep into `grep -q .`, which exits
# on the first match and SIGPIPEs the upstream grep (141); under
# `pipefail` that made the pipeline non-zero, so beyond a few thousand
# matching lines the check silently "passed" while violations existed.
scan() {
    local label="$1" pattern="$2" extra="${3:-}"
    local hits
    # This file names the patterns it looks for.
    hits="$(grep -rE "$pattern" "${roots[@]}" 2>/dev/null | grep -v '/\.git/' | grep -v '^scripts/check_paths\.sh:' || true)"
    if [[ -n "$extra" ]]; then
        hits="$(printf '%s\n' "$hits" | grep -vE "$extra" || true)"
    fi
    hits="$(printf '%s\n' "$hits" | filter_placeholders | grep -v '^[[:space:]]*$' || true)"
    if [[ -n "$hits" ]]; then
        echo "✗ $label"
        printf '%s\n' "$hits"
        failed=1
    fi
    return 0
}

scan "hardcoded /Users/USER path found" '/Users/[a-zA-Z0-9_-]+/'
# The same at the end of a line or a quoted string, where no slash follows.
scan "hardcoded /Users/USER path found" "/Users/[a-zA-Z0-9_-]+([\"'[:space:]]|\$)" '/Users/(NAME|Shared|username)\b'
# /home/linuxbrew is Homebrew's fixed Linux prefix, not a person.
scan "hardcoded /home/USER path found"  '/home/[a-zA-Z0-9_-]+/' 'testuser|/home/linuxbrew/'
# user@hostname.local mDNS — do not ban ~/.local/bin or config.local
scan "personal mDNS host (user@ + hostname) found — keep those in gitignored *.local overlays" \
     '@[A-Za-z0-9._-]+\.local\b'

# A tailnet's name or address says whose network this is.
scan "Tailscale tailnet name or address found" '[A-Za-z0-9-]+\.ts\.net\b|fd7a:115c:a1e0'

# Your own list, never in the repo: names only you know are private (your
# login, hosts, internal projects), one extended regex a line, in the
# gitignored .local/private-terms. CI has no such file, so this guards the
# machine that makes the commits.
if [[ -r .local/private-terms ]]; then
    while IFS= read -r term || [[ -n "$term" ]]; do
        case "$term" in ""|"#"*) continue ;; esac
        scan "a term from .local/private-terms found" "$term"
    done < .local/private-terms
fi

if [[ "$failed" -eq 0 ]]; then
    echo "✓ clean"
fi
exit "$failed"
