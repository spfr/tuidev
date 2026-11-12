#!/bin/bash
# Tests for bin/sbx and the strict and standard Seatbelt profiles: what a
# command under sbx may write in the AI CLIs' own dirs, and which project dirs
# sbx refuses. Everything runs against a throwaway HOME, never the real one.
#   - static: the profiles' write rules, evaluated in bash, deny every path a
#     later session loads as instructions, config or code, and leave session
#     state writable (runs everywhere);
#   - the project-dir guard, through `sbx --dry-run` (macOS);
#   - live: the same writes under sandbox-exec (macOS, and only outside another
#     Seatbelt sandbox: profiles do not nest, so inside one this part SKIPs).
# Run: bash scripts/lib/test_sbx.sh  -> exit 0 on pass.
# shellcheck disable=SC2016  # the sandboxed sh scripts expand their own "$1"
set -eo pipefail
unset XDG_CONFIG_HOME TUIDEV_SANDBOX_DIR SBX_ALLOW_HERDR

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$LIB_DIR/../.." && pwd)"
PROFILES="$REPO_DIR/configs/sandbox/profiles"
SBX="$REPO_DIR/bin/sbx"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/tuidev-test.XXXXXX")"; trap 'rm -rf "$tmp"' EXIT
tmp="$(cd "$tmp" && pwd -P)"   # Seatbelt matches real paths (/private/var/...)

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

# Files a later, possibly unsandboxed, session loads as instructions, config or
# code: a command under sbx must not write them. Relative to $HOME.
DENIED="
.claude/settings.json
.claude/settings.local.json
.claude/keybindings.json
.claude/launch.json
.claude/scheduled_tasks.json
.claude/CLAUDE.md
.claude/loop.md
.claude/imported-from-claude-md.md
.claude/statusline.sh
.claude/statusline.py
.claude/hooks/pre.sh
.claude/commands/c.md
.claude/agents/a.md
.claude/skills/s/SKILL.md
.claude/plugins/installed_plugins.json
.claude/rules/tuidev-orchestration.md
.claude/output-styles/o.md
.claude/agent-memory/reviewer/MEMORY.md
.claude/workflows/w.js
.claude/routines/r.json
.claude/dev-mods/m.js
.claude/cowork_plugins/p.json
.claude/chrome/chrome-native-host
.claude/local/claude
.claude/downloads/claude-9.9.9-darwin-arm64
.claude/projects/-work-app/memory/MEMORY.md
.claude/projects/-work-app/memory/notes.md
.codex/config.toml
.codex/work.config.toml
.codex/managed_config.toml
.codex/.env
.codex/hooks.json
.codex/AGENTS.md
.codex/AGENTS.override.md
.codex/herdr-agent-state.sh
.codex/hooks/stop.sh
.codex/rules/tuidev.rules
.codex/agents/x.toml
.codex/prompts/p.md
.codex/skills/s/SKILL.md
.codex/skills/.system/s/SKILL.md
.codex/plugins/cache/p/plugin.json
.codex/memories/MEMORY.md
.codex/automations/watch/automation.toml
.codex/computer-use/config.json
.codex/packages/standalone/codex
.local/share/claude/versions/9.9.9
"
# (~/.zshrc, ~/.local/bin and ~/Library/LaunchAgents are denied by default,
# not by a rule; the throwaway HOME lives in a temp dir the profiles open, so
# the live run cannot show that. The project-dir guard below covers them.)

# Session state, transcripts, logs, caches and auth: the CLIs write these
# while they run, so they must stay writable under sbx.
WRITABLE="
.claude.json
.claude.json.backup
.claude/history.jsonl
.claude/.credentials.json
.claude/stats-cache.json
.claude/projects/-work-app/0b1c.jsonl
.claude/projects/-work-app/0b1c/subagents/agent-1.jsonl
.claude/todos/t.json
.claude/plans/plan.md
.claude/shell-snapshots/snapshot-zsh-1.sh
.claude/session-env/e/hook-0.sh
.claude/file-history/f/1
.claude/debug/d.txt
.claude/statsig/s
.claude/teams/t/config.json
.claude/tasks/t/1.json
.claude/cache/changelog.md
.local/share/claude/x
.local/state/claude/locks/l
.cache/claude/staging/x
.codex/auth.json
.codex/history.jsonl
.codex/sessions/2026/11/12/rollout-1.jsonl
.codex/archived_sessions/rollout-0.jsonl
.codex/log/codex-tui.log
.codex/.codex-global-state.json
.codex/models_cache.json
.codex/version.json
.codex/state_5.sqlite
.codex/memories.lock
.codex/shell_snapshots/s.sh
.codex/tmp/x
.codex/.tmp/plugins/x
"

# ---------------------------------------------------------------------------
# Static: evaluate the profiles' file-write rules for a HOME of /H.
# ---------------------------------------------------------------------------
H=/H
# write_section PROFILE: the AI-CLI write rules, from the allow to the network.
write_section() {
    awk '/^;; --- File writes: AI CLI state/{f=1} /^;; --- Network ---/{f=0} f' "$PROFILES/$1.sb"
}
[[ -n "$(write_section strict)" ]] || fail "strict.sb: no AI-CLI write section found"
[[ "$(write_section strict)" == "$(write_section standard)" ]] \
    || fail "strict.sb and standard.sb disagree on the AI-CLI write rules"
pass "strict.sb and standard.sb share one set of AI-CLI write rules"

# rules KIND PROFILE: one "type value" line per filter in the first
# `(allow file-write*` or `(deny file-write*` block of the write section.
rules() {
    write_section "$2" | awk -v kind="$1" '
        $0 ~ "^\\(" kind " file-write\\*" { f = 1; next }
        f && /^ *\((literal|subpath|prefix) +\(string-append \(param "HOME_DIR"\) "/ {
            t = $0; sub(/^ *\(/, "", t); sub(/ .*/, "", t)
            v = $0; sub(/^.*\(param "HOME_DIR"\) "/, "", v); sub(/".*/, "", v); print t, v
        }
        f && /^ *\(regex \(string-append "\^" \(param "HOME_DIR"\) "/ {
            v = $0; sub(/^.*\(param "HOME_DIR"\) "/, "", v); sub(/"\)\)*$/, "", v)
            gsub(/\\\\/, "\\", v); print "regex", v
        }
        f && /\)\)\)$/ { exit }'
}
# matches PATH RULES: does any rule match /H/PATH?
matches() {
    local path="$H/$1" type value
    while read -r type value; do
        case "$type" in
            literal) [[ "$path" == "$H$value" ]] && return 0 ;;
            prefix)  [[ "$path" == "$H$value"* ]] && return 0 ;;
            subpath) [[ "$path" == "$H$value" || "$path" == "$H$value/"* ]] && return 0 ;;
            regex)   [[ "$path" =~ ^$H$value ]] && return 0 ;;
        esac
    done <<<"$2"
    return 1
}
for sb in strict standard; do
    allow="$(rules allow "$sb")"; deny="$(rules deny "$sb")"
    [[ "$(grep -c . <<<"$deny")" -ge 30 ]] || fail "$sb.sb: the steering deny list did not parse ($(grep -c . <<<"$deny") rules)"
    for p in $DENIED; do
        matches "$p" "$allow" || fail "$sb.sb: $p is not in the AI-CLI write allow at all (probe list out of date?)"
        matches "$p" "$deny" || fail "$sb.sb: a command under sbx could write ~/$p, which a later session loads"
    done
    for p in $WRITABLE; do
        matches "$p" "$allow" || fail "$sb.sb: ~/$p (session state) is not writable"
        if matches "$p" "$deny"; then fail "$sb.sb: ~/$p is session state but denied"; fi
    done
done
pass "the profiles deny every instruction, config and code path under ~/.claude and ~/.codex, and keep session state writable"

# Every steering dir or file the profiles deny is documented.
for name in $(rules deny strict | awk '$1 != "regex" {n = $2; sub(/.*\//, "", n); print n}' | sort -u); do
    grep -qE "[/{,]${name//./\\.}([/},[:space:]]|$)" "$REPO_DIR/docs/sandboxing.md" || fail "docs/sandboxing.md does not list ~/…/$name, which the profiles deny"
done
pass "docs/sandboxing.md lists every path the profiles keep read-only"

# ---------------------------------------------------------------------------
# The project-dir guard (bin/sbx is macOS-only).
# ---------------------------------------------------------------------------
if [[ "$(uname -s)" != Darwin ]]; then
    echo "SKIP: bin/sbx and sandbox-exec are macOS-only"
    exit 0
fi

home="$tmp/home" proj="$tmp/proj"
mkdir -p "$home/sub" "$proj" "$tmp/home2"
ln -s "$home" "$tmp/homelink"

# sbx_rc [DIR] -- ARGS: sbx's exit code (dry run), run from DIR, HOME=$home.
sbx_rc() {
    local dir="$1"; shift
    (cd "$dir" && HOME="${SBX_HOME:-$home}" "$SBX" --dry-run "$@" -- /usr/bin/true >"$tmp/out" 2>&1) && echo 0 || echo $?
}
expect_refused() {
    local rc; rc="$(sbx_rc "$@")"
    [[ "$rc" == 2 ]] || fail "sbx $* (from $1) should refuse with exit 2, got $rc: $(cat "$tmp/out")"
    grep -qF -- '--allow-home' "$tmp/out" || fail "sbx $*: the refusal should name --allow-home"
    rc="$(sbx_rc "$@" --allow-home)"
    [[ "$rc" == 0 ]] || fail "sbx $* --allow-home should run, got $rc: $(cat "$tmp/out")"
}
expect_refused "$proj" --project "$home"
expect_refused "$proj" --project "$home/"
expect_refused "$proj" --project /
expect_refused "$proj" --project "$tmp"
expect_refused "$proj" --project "$home/sub/.."
expect_refused "$proj" --project "$tmp/homelink"
expect_refused "$proj" --project="$home"
expect_refused "$home"
expect_refused "$home/sub/.."
expect_refused /
SBX_HOME="$tmp/homelink" expect_refused "$proj" --project "$home"
pass "sbx refuses \$HOME, a dir above it and / as the project (given or the cwd), and --allow-home overrides"

[[ "$(sbx_rc "$proj")" == 0 ]] || fail "sbx from a project dir should run: $(cat "$tmp/out")"
grep -qF -- "PROJECT_DIR=$proj " "$tmp/out" || fail "sbx should pass the project to the profile: $(cat "$tmp/out")"
grep -qF -- "HOME_DIR=$home " "$tmp/out" || fail "sbx should pass the home to the profile: $(cat "$tmp/out")"
[[ "$(sbx_rc "$proj" --project "$home/sub")" == 0 ]] || fail "a dir under \$HOME is a fine project: $(cat "$tmp/out")"
[[ "$(sbx_rc "$proj" --project "$tmp/home2")" == 0 ]] || fail "\$HOME2 is not above \$HOME: $(cat "$tmp/out")"
SBX_HOME="$tmp/homelink" sbx_rc "$proj" >/dev/null
grep -qF -- "HOME_DIR=$home " "$tmp/out" || fail "sbx should pass \$HOME with symlinks resolved: $(cat "$tmp/out")"
[[ "$(sbx_rc "$home" --profile off)" == 0 ]] || fail "--profile off has no write sandbox to guard: $(cat "$tmp/out")"
pass "sbx runs normally inside a project, and passes the resolved home"

# ---------------------------------------------------------------------------
# Live: the writes under sandbox-exec.
# ---------------------------------------------------------------------------
if ! sandbox-exec -p '(version 1)(allow default)' /usr/bin/true 2>/dev/null; then
    echo "SKIP: sandbox-exec cannot apply a profile here (inside another Seatbelt sandbox?): run this file outside any sandbox for the live checks"
    exit 0
fi

# try PROFILE SCRIPT ARG: run `sh -c SCRIPT sh ARG` under PROFILE, exit code.
try() {
    sandbox-exec -f "$PROFILES/$1.sb" -D "HOME_DIR=$home" -D "PROJECT_DIR=$proj" -- \
        /bin/sh -c "$2" sh "$3" 2>/dev/null && echo 0 || echo 1
}
for p in $DENIED $WRITABLE; do mkdir -p "$(dirname "$home/$p")"; done
mkdir -p "$tmp/evil/memory"
for sb in strict standard; do
    for p in $DENIED; do
        [[ "$(try "$sb" 'printf x >> "$1"' "$home/$p")" == 1 ]] || fail "$sb.sb (live): wrote ~/$p"
    done
    for p in $WRITABLE; do
        [[ "$(try "$sb" 'printf x >> "$1"' "$home/$p")" == 0 ]] || fail "$sb.sb (live): could not write ~/$p"
    done
    [[ "$(try "$sb" 'printf x > "$1"' "$proj/out")" == 0 ]] || fail "$sb.sb (live): could not write the project"
    [[ "$(try "$sb" 'mkdir "$1" && printf x > "$1/s.jsonl"' "$home/.claude/projects/-$sb-new")" == 0 ]] \
        || fail "$sb.sb (live): could not start a new project's transcripts"
    [[ "$(try "$sb" 'mv "$1" "$1.old"' "$home/.claude/projects/-work-app")" == 1 ]] \
        || fail "$sb.sb (live): moved a project folder (and its memory) away"
    [[ "$(try "$sb" "ln -s '$tmp/evil' \"\$1\"" "$home/.claude/projects/-$sb-link")" == 1 ]] \
        || fail "$sb.sb (live): made a project folder a symlink to a writable memory"
    [[ "$(try "$sb" 'mv "$1" "$1.old"' "$home/.claude/rules")" == 1 ]] || fail "$sb.sb (live): renamed ~/.claude/rules"
    [[ "$(try "$sb" 'mv "$1" "$1.old"' "$home/.codex/agents")" == 1 ]] || fail "$sb.sb (live): renamed ~/.codex/agents"
done
pass "under sandbox-exec, strict and standard deny the steering paths and allow session state (live)"

# And through sbx itself, as a user runs it.
# shellcheck disable=SC2015,SC2016  # fail on either step; expands in the sandboxed shell
(cd "$proj" && HOME="$home" TUIDEV_SANDBOX_DIR="$PROFILES" "$SBX" -- /bin/sh -c 'printf ok > "$1"' sh "$proj/via-sbx") \
    && [[ "$(cat "$proj/via-sbx")" == ok ]] || fail "sbx -- CMD could not write the project (live)"
# shellcheck disable=SC2016
if (cd "$proj" && HOME="$home" TUIDEV_SANDBOX_DIR="$PROFILES" "$SBX" -- /bin/sh -c 'printf x >> "$1"' sh "$home/.codex/agents/y.toml") 2>/dev/null; then
    fail "sbx -- CMD wrote ~/.codex/agents (live)"
fi
pass "sbx -- CMD writes the project and not ~/.codex/agents (live)"
