#!/bin/bash
# A scripted stand-in for an agent session, for the Herdr screenshot
# (docs/assets/tapes/README.md): demo-agent KIND SCENARIO [TITLE]. It prints a
# short, made-up transcript and reports its state to the Herdr server it runs
# under through Herdr's hook API (`herdr pane report-agent`), the same call an
# agent integration makes. No model runs and nothing is changed.
#   KIND      the agent label Herdr shows: claude or codex
#   SCENARIO  tests (keeps working), ratelimit (keeps working), approve
#             (blocked on a y/n question, then done), review (done), deploy
#             (keeps working), idle (waiting); for remote-demo.sh: preview
#             (starts a real web server on localhost:5173 and writes a
#             review), leftover (starts a server on :8080 that outlives it,
#             then ends)
#             SCENARIO+N works until `herdr-demo.sh go` (at most 60 s),
#             then N seconds more (DEMO_AGENT_WORK=N)
#   TITLE     the session's task, set as the terminal title (for claude the
#             way Claude Code sets its own, `✳ TITLE`), so `agents herdr sync`
#             names the tab after it
# DEMO_AGENT_NAMED=1 (remote-demo.sh) runs it under KIND as its argv[0], so
# `agents` lists the stand-in as that agent's session.
set -u

kind="${1:-claude}" scenario="${2:-idle}" title="${3:-}"
case "$scenario" in *+*) DEMO_AGENT_WORK="${scenario#*+}" scenario="${scenario%%+*}" ;; esac
if [[ -n "${DEMO_AGENT_NAMED:-}" && -z "${_DEMO_AGENT_RENAMED:-}" ]]; then
    _DEMO_AGENT_RENAMED=1 exec -a "$kind" bash "$0" "$@"
fi
B=$'\033[1m' D=$'\033[2m' G=$'\033[32m' Y=$'\033[33m' C=$'\033[36m' N=$'\033[0m'

report() {
    [[ -n "${HERDR_PANE_ID:-}" ]] || return 0
    herdr pane report-agent "$HERDR_PANE_ID" --source tuidev-demo --agent "$kind" --state "$1" ${2:+--message "$2"} >/dev/null 2>&1 || true
}
# session_record FILE — what Claude Code keeps about a running session, for
# this stand-in: ~/.claude/sessions/PID.json and a transcript whose one Write
# call names FILE, so `agents map` lists FILE among the files sessions wrote
# (remote-demo.sh). Only under DEMO_AGENT_NAMED; nothing real is recorded.
session_record() {
    [[ -n "${DEMO_AGENT_NAMED:-}" && "$kind" == claude ]] || return 0
    local sid="standin-$$" dir="$HOME/.claude"
    mkdir -p "$dir/sessions" "$dir/projects/standin"
    printf '{"sessionId":"%s","name":"storefront","status":"idle","version":"0","procStart":"%s"}\n' \
        "$sid" "$started" > "$dir/sessions/$$.json"
    { echo '{"type":"summary"}'
      printf '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":"%s"}}]}}\n' "$1"
    } > "$dir/projects/standin/$sid.jsonl"
}
started="$(LC_ALL=C TZ=UTC date '+%a %b %d %H:%M:%S %Y')"
step() { printf '  %s✓%s %s\n' "$G" "$N" "$1"; sleep "${2:-0.15}"; }

trap 'report idle; exit 0' INT TERM
clear
if [[ -n "$title" ]]; then
    [[ "$kind" != claude ]] || title="✳ $title"
    printf '\033]0;%s\007' "$title"
fi
tilde='~'   # (a literal ~ in the replacement is expanded by bash 4.3+)
printf '%sdemo-agent · %s stand-in · %s%s\n' "$D" "$kind" "${PWD/#$HOME/$tilde}" "$N"
printf '%sscripted transcript; state reported with herdr pane report-agent%s\n\n' "$D" "$N"
report working
# A moment at work first, so the sync sees the state change that follows and
# can say since when the agent has waited (its $tuidev_since). With
# DEMO_AGENT_WORK=N, until herdr-demo.sh's go mark (~/.demo/go, set just
# before herdr.tape's client attaches) and N seconds more: Herdr's client shows
# "done" only for a completion it saw happen, and "idle" for one from before.
if [[ -n "${DEMO_AGENT_WORK:-}" ]]; then
    w=0
    while [[ ! -e "$HOME/.demo/go" && $w -lt 60 ]]; do sleep 1; w=$((w + 1)); done
    sleep "$DEMO_AGENT_WORK"
else
    sleep 1.5
fi

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
    ratelimit)
        printf '%s›%s add a per-client rate limit to the API and test it\n\n' "$C" "$N"
        step "read internal/http/middleware.go"
        step "edit internal/http/ratelimit.go  ${D}(+42)${N}"
        printf '  %s●%s go test ./...  %s(running)%s\n' "$Y" "$N" "$D" "$N"
        i=12
        while :; do
            printf '\r    %s%d/57 packages ok%s ' "$D" "$i" "$N"
            i=$(( i < 54 ? i + 3 : 54 )); sleep 1
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
    preview)
        printf '%s›%s start the storefront preview and review the checkout page\n\n' "$C" "$N"
        step "read src/pages/checkout.html, src/styles/shop.css"
        step "edit src/pages/checkout.html  ${D}(+18 −4)${N}"
        python3 -m http.server 5173 --bind 127.0.0.1 >/dev/null 2>&1 &
        sleep 1
        printf '  %s●%s preview server  %s(running)%s\n\n' "$Y" "$N" "$D" "$N"
        printf '    %s➜%s  Local:   %shttp://localhost:5173/%s\n\n' "$G" "$N" "$B" "$N"
        step "wrote review.md  ${D}(3 findings)${N}"
        session_record "$PWD/review.md"
        printf '    %sfile://%s%s/review.md%s\n' "$D" "$(hostname)" "$PWD" "$N"
        report idle "preview ready" ;;
    leftover)
        printf '%s›%s run the orders API locally and try the new endpoint\n\n' "$C" "$N"
        step "pip install -r requirements.txt  ${D}(cached)${N}"
        ( setsid python3 -m http.server 8080 --bind 127.0.0.1 >/dev/null 2>&1 & )
        step "started the API on http://localhost:8080"
        step "curl /orders/42  ${D}200 OK${N}"
        printf '\n  done: the endpoint answers\n'
        report idle "done"
        exit 0 ;;
    *)
        printf '%s›%s %s\n' "$C" "$N" "ready"
        report idle ;;
esac

# Hold the pane, like an agent waiting at its prompt.
while :; do sleep 3600; done
