#!/bin/bash
# Run the scripts/lib/test_*.sh harnesses in parallel, one per core.
#
#   scripts/test_lib.sh [-j N] [FILE...]
#
# Each harness works in its own throwaway HOME, so they do not share state.
# Output is kept per harness and printed in name order when all are done, so a
# run reads the same as a serial one. Exit 1 if any failed; the failures are
# named last, slowest harnesses with their times before them.
# TUIDEV_TEST_JOBS (or -j) sets the number at once; 1 is the old serial run.
# TUIDEV_TEST_BASH is the bash that runs each harness (CI: /bin/bash, 3.2).

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

# --one FILE OUTDIR: one harness (how this script runs each of them): its
# output, exit code and seconds go to files named after it.
if [[ "${1:-}" == --one ]]; then
    name="$(basename "$2" .sh)"; start="$(date +%s)"; rc=0
    "${TUIDEV_TEST_BASH:-bash}" "$2" > "$3/$name.log" 2>&1 || rc=$?
    printf '%s\n' "$rc" > "$3/$name.rc"
    printf '%s\n' "$(( $(date +%s) - start ))" > "$3/$name.secs"
    exit 0
fi

jobs="${TUIDEV_TEST_JOBS:-}"
if [[ "${1:-}" == -j ]]; then jobs="${2:-}"; shift 2; fi
if [[ -z "$jobs" ]]; then
    jobs="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)"
fi
case "$jobs" in ''|*[!0-9]*|0) echo "test_lib.sh: -j needs a number above 0" >&2; exit 2 ;; esac

if (( $# > 0 )); then files=("$@"); else files=(scripts/lib/test_*.sh); fi

out="$(mktemp -d "${TMPDIR:-/tmp}/tuidev-test-lib.XXXXXX")" || exit 1
trap 'rm -rf "$out"' EXIT

began="$(date +%s)"
printf '%s\n' "${files[@]}" | xargs -P "$jobs" -I{} "$BASH" "$ROOT/scripts/test_lib.sh" --one {} "$out"

failed=()
for f in "${files[@]}"; do
    name="$(basename "$f" .sh)"
    cat "$out/$name.log" 2>/dev/null
    if [[ "$(cat "$out/$name.rc" 2>/dev/null || echo 1)" != 0 ]]; then failed+=("$f"); fi
done

echo
echo "${#files[@]} harness(es), $jobs at once, $(( $(date +%s) - began )) s. Slowest:"
for f in "${files[@]}"; do
    name="$(basename "$f" .sh)"
    printf '%s %s\n' "$(cat "$out/$name.secs" 2>/dev/null || echo 0)" "$name"
done | sort -rn | head -5 | while read -r secs name; do printf '  %4s s  %s\n' "$secs" "$name"; done

if (( ${#failed[@]} > 0 )); then
    echo
    echo "FAILED:"
    printf '  %s\n' "${failed[@]}"
    exit 1
fi
