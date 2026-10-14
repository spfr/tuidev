#!/bin/bash
# A scripted stand-in for an agent session, for the Herdr screenshot
# (docs/assets/tapes/README.md): demo-agent KIND SCENARIO. It prints a short,
# made-up transcript and reports its state to the Herdr server it runs under
# through Herdr's hook API (`herdr pane report-agent`), the same call an agent
# integration makes. No model runs and nothing is changed.
#   KIND      the agent label Herdr shows: claude or codex
#   SCENARIO  tests (keeps working), approve (blocked on a y/n question, then
#             done), review (done), deploy (keeps working), idle (waiting)
set -u

kind="${1:-claude}" scenario="${2:-idle}"
B=$'\033[1m' D=$'\033[2m' G=$'\033[32m' Y=$'\033[33m' C=$'\033[36m' N=$'\033[0m'

report() {
    [[ -n "${HERDR_PANE_ID:-}" ]] || return 0
    herdr pane report-agent "$HERDR_PANE_ID" --source tuidev-demo --agent "$kind" --state "$1" ${2:+--message "$2"} >/dev/null 2>&1 || true
}
step() { printf '  %s✓%s %s\n' "$G" "$N" "$1"; sleep "${2:-0.15}"; }

trap 'report idle; exit 0' INT TERM
clear
tilde='~'   # (a literal ~ in the replacement is expanded by bash 4.3+)
printf '%sdemo-agent · %s stand-in · %s%s\n' "$D" "$kind" "${PWD/#$HOME/$tilde}" "$N"
printf '%sscripted transcript; state reported with herdr pane report-agent%s\n\n' "$D" "$N"
report working

case "$scenario" in
    tests)
        printf '%s›%s fix the flaky cache test and run the suite\n\n' "$C" "$N"
        step "read src/cache.ts, tests/cache.test.ts"
        step "edit src/cache.ts  ${D}(+6 −2)${N}"
        printf '  %s●%s npm test  %s(running)%s\n' "$Y" "$N" "$D" "$N"
        i=180
        while :; do
            printf '\r    %s%d/412 tests passed%s ' "$D" "$i" "$N"
            i=$(( i < 405 ? i + 7 : 405 )); sleep 1
        done ;;
    approve)
        printf '%s›%s return a 404 for unknown routes, then push the branch\n\n' "$C" "$N"
        step "edit src/routes.py  ${D}(+3 −1)${N}"
        step "pytest -q  ${D}12 passed in 0.41s${N}"
        step "git commit -m \"fix: 404 for unknown routes\""
        printf '\n  %s%s? Allow:%s git push origin fix-404\n' "$B" "$Y" "$N"
        printf '    %s(y) yes   (n) no, tell the agent what to do instead%s\n\n  ' "$D" "$N"
        report blocked "Allow git push origin fix-404?"
        read -r -n 1 answer
        echo
        report working
        if [[ "$answer" == y ]]; then
            step "git push origin fix-404" 0.6
            step "opened a draft PR: fix: 404 for unknown routes"
        else
            printf '  %s✗%s push skipped\n' "$Y" "$N"
        fi
        report idle "done" ;;
    review)
        printf '%s›%s review the diff on this branch\n\n' "$C" "$N"
        step "read 7 changed files"
        step "ran make lint test  ${D}all passed${N}"
        printf '\n  2 findings: an unchecked error in sync.go:88,\n  and a test that sleeps instead of waiting\n'
        report idle "2 findings" ;;
    deploy)
        printf '%s›%s plan the staging rollout for api 1.5\n\n' "$C" "$N"
        step "read deploy/staging.yml"
        step "make plan  ${D}3 to change, 0 to destroy${N}"
        printf '  %s●%s waiting for the canary  %s(health checks)%s\n' "$Y" "$N" "$D" "$N" ;;
    *)
        printf '%s›%s %s\n' "$C" "$N" "ready"
        report idle ;;
esac

# Hold the pane, like an agent waiting at its prompt.
while :; do sleep 3600; done
