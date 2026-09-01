#!/usr/bin/env bash
# layout-worktrees.sh — one git worktree per agent, one tmux window per worktree.
#
# The worktree-per-agent pattern: each agent gets its own checkout on its own
# branch so parallel agents never fight over the index, the working tree, or
# each other's half-finished edits. Window 0 ("main") stays on the original
# repo for review/harvest; every additional window is one agent's worktree.
#
# Windows, not panes: an agent CLI wants full terminal height, and N>2 stacked
# panes get unusable fast. The sibling multi-context layouts (layout-multi.sh,
# layout-fullstack.sh) use windows for the same reason.
#
# Worktrees live in a predictable sibling directory so they never pollute the
# repo and are trivial to spot:
#
#   <parent>/<repo>-wt/<branch-with-slashes-as-dashes>
#
# RUNTIME ISOLATION CAVEAT — a worktree isolates *git state only*. It does not
# isolate anything the code needs at runtime:
#   - Ports: two agents running `npm run dev` will collide on the same port.
#     Give each worktree its own PORT (e.g. PORT=300$i) or only run one server.
#   - Dependencies: node_modules / .venv / target are NOT shared or copied.
#     Each worktree needs its own install, which costs disk and time.
#   - Untracked config: .env, local sqlite files, and other gitignored files do
#     not follow the worktree. Copy or symlink them in deliberately.
#   - Shared external state: one dev database, one Redis, one cloud project is
#     still shared. Namespace it per agent or accept the interference.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Repo-scoped default so bare `worktrees` in two different repos does not land
# both in one session. Re-derived from the repo root once it is known.
# shellcheck disable=SC2034
LAYOUT_DEFAULT_NAME="$(basename "$PWD")-wt"
# shellcheck disable=SC2034
LAYOUT_USAGE="[SESSION_NAME] [-n N] [--branch-prefix P] [--base REF] [--cmd CMD] | --list | --clean"
# shellcheck source=./_lib.sh disable=SC1091
. "$SCRIPT_DIR/_lib.sh"

WT_MAX=8

usage() {
    cat <<EOF
Usage: $(basename "$0") [SESSION_NAME] [OPTIONS]
       $(basename "$0") --list
       $(basename "$0") --clean

Create N git worktrees (one per agent) and a tmux session with one window per
worktree. Attach-or-create: re-running reuses existing worktrees and attaches.
SESSION_NAME defaults to "<repo>-wt", so each repo gets its own session.

Options:
  -n N                 number of worktrees/agents (default 2, max $WT_MAX)
  --branch-prefix P    branch name prefix (default "agent/") -> agent/1, agent/2
  --base REF           branch off REF (default: current branch)
  --cmd CMD            command to run in each worktree window (default: shell)
  --list               list this repo's agent worktrees and their status
  --clean              remove worktrees that are clean AND have no unmerged
                       commits; never touches dirty or ahead worktrees.
                       "Merged" is judged against the main checkout's current
                       branch (or --base REF), so run it from the branch the
                       agents forked off — work merged elsewhere reads as
                       unmerged and is kept.
  -h, --help           this help

Examples:
  $(basename "$0")                          # 2 worktrees, session "<repo>-wt"
  $(basename "$0") feat -n 3 --cmd cc       # 3 agents each running Claude Code
  $(basename "$0") -n 2 --cmd codex --branch-prefix wip/
  $(basename "$0") --list
  $(basename "$0") --clean
EOF
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
SESSION_ARG=""
WT_COUNT=2
BRANCH_PREFIX="agent/"
BASE_REF=""
AGENT_CMD=""
ACTION="session"

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        --list)    ACTION="list"; shift ;;
        --clean)   ACTION="clean"; shift ;;
        -n)               WT_COUNT="${2:?-n needs a number}"; shift 2 ;;
        --branch-prefix)  BRANCH_PREFIX="${2:?--branch-prefix needs a value}"; shift 2 ;;
        --base)           BASE_REF="${2:?--base needs a value}"; shift 2 ;;
        --cmd)            AGENT_CMD="${2:?--cmd needs a value}"; shift 2 ;;
        -*) print_error "unknown option: $1"; usage; exit 2 ;;
        *)
            if [[ -n "$SESSION_ARG" ]]; then
                print_error "unexpected argument: $1"
                exit 2
            fi
            SESSION_ARG="$1"; shift
            ;;
    esac
done

if [[ ! "$WT_COUNT" =~ ^[0-9]+$ ]] || (( WT_COUNT < 1 || WT_COUNT > WT_MAX )); then
    die "-n must be between 1 and $WT_MAX (got: $WT_COUNT)"
fi

# ---------------------------------------------------------------------------
# Repo discovery
# ---------------------------------------------------------------------------
command_exists git || die "git is not installed" 127
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" \
    || die "not inside a git repository — run this from a repo checkout"
REPO_NAME="$(basename "$REPO_ROOT")"
WT_ROOT="$(dirname "$REPO_ROOT")/${REPO_NAME}-wt"
# Now that the repo root is known, scope the default session name to the repo
# rather than to $PWD, so invoking from a subdirectory hits the same session.
# (Read by layout_prelude below.)
# shellcheck disable=SC2034
LAYOUT_DEFAULT_NAME="${REPO_NAME}-wt"

git -C "$REPO_ROOT" rev-parse --verify HEAD >/dev/null 2>&1 \
    || die "repository has no commits yet — make one before creating worktrees"

if [[ -z "$BASE_REF" ]]; then
    BASE_REF="$(git -C "$REPO_ROOT" symbolic-ref --quiet --short HEAD || echo HEAD)"
fi

# Directory name for a branch: agent/1 -> agent-1.
wt_dirname() { echo "${1//\//-}"; }

# Display form of a path: $HOME/foo -> ~/foo.
short_path() { echo "${1/#"$HOME"/\~}"; }

# All worktree paths registered with this repo (one per line).
wt_paths() {
    git -C "$REPO_ROOT" worktree list --porcelain \
        | awk '/^worktree /{print substr($0, 10)}'
}

# Branch checked out in a worktree directory ("" if detached).
wt_branch_of() { git -C "$1" symbolic-ref --quiet --short HEAD 2>/dev/null || true; }

# Worktrees this script manages: registered AND under $WT_ROOT.
managed_wt_paths() {
    local p
    while IFS= read -r p; do
        [[ "$p" == "$WT_ROOT"/* ]] && echo "$p"
    done < <(wt_paths)
}

# True if $1 is already a worktree of this repo. Deliberately not
# `managed_wt_paths | grep -q`: grep exits on the first match, the producer
# takes SIGPIPE, and `pipefail` then reports the whole pipeline as failed.
wt_is_managed() {
    local p
    while IFS= read -r p; do
        [[ "$p" == "$1" ]] && return 0
    done < <(managed_wt_paths)
    return 1
}

# Commits in the worktree at $1 that are not reachable from $BASE_REF.
wt_ahead_count() {
    local rev
    rev="$(git -C "$1" rev-parse HEAD 2>/dev/null)" || { echo 0; return 0; }
    git -C "$REPO_ROOT" rev-list --count "${BASE_REF}..${rev}" 2>/dev/null || echo 0
}

wt_is_dirty() { [[ -n "$(git -C "$1" status --porcelain 2>/dev/null)" ]]; }

# ---------------------------------------------------------------------------
# --list
# ---------------------------------------------------------------------------
list_worktrees() {
    local found=0 path branch ahead status
    while IFS= read -r path; do
        found=1
        branch="$(wt_branch_of "$path")"
        ahead="$(wt_ahead_count "$path")"
        status="clean"
        if wt_is_dirty "$path"; then status="DIRTY"; fi
        printf '  %-40s %-20s %s, %s ahead of %s\n' \
            "$(short_path "$path")" "${branch:-(detached)}" "$status" "$ahead" "$BASE_REF"
    done < <(managed_wt_paths)
    if (( found == 0 )); then
        print_info "no agent worktrees under $(short_path "$WT_ROOT")"
    fi
}

# ---------------------------------------------------------------------------
# --clean
# ---------------------------------------------------------------------------
clean_worktrees() {
    local path branch ahead removed=0 blocked=0
    while IFS= read -r path; do
        branch="$(wt_branch_of "$path")"
        if wt_is_dirty "$path"; then
            print_warning "keeping $(short_path "$path") — uncommitted changes"
            blocked=$((blocked + 1))
            continue
        fi
        ahead="$(wt_ahead_count "$path")"
        if (( ahead > 0 )); then
            print_warning "keeping $(short_path "$path") — ${ahead} commit(s) not in ${BASE_REF} (merge or cherry-pick first)"
            blocked=$((blocked + 1))
            continue
        fi
        print_step "removing $(short_path "$path") (${branch:-detached})"
        run_cmd git -C "$REPO_ROOT" worktree remove "$path"
        # `git branch -d` measures merged-ness against HEAD, not against
        # $BASE_REF, so it can refuse a branch this loop already cleared. Keep
        # the safe -d (never -D) and warn instead of aborting the whole run.
        if [[ -n "$branch" ]]; then
            if ! run_cmd git -C "$REPO_ROOT" branch -d "$branch" 2>/dev/null; then
                print_warning "worktree gone but branch ${branch} kept — not merged into HEAD; delete with: git -C $(short_path "$REPO_ROOT") branch -D ${branch}"
            fi
        fi
        removed=$((removed + 1))
    done < <(managed_wt_paths)

    run_cmd git -C "$REPO_ROOT" worktree prune
    # Drop the container dir only if it is now empty.
    if [[ -d "$WT_ROOT" ]]; then
        run_cmd rmdir "$WT_ROOT" 2>/dev/null || true
    fi

    print_success "removed ${removed} worktree(s), kept ${blocked}"
    if (( blocked > 0 )); then
        print_info "harvest kept work with: git -C $(short_path "$REPO_ROOT") merge <branch>  (or cherry-pick)"
    fi
}

# ---------------------------------------------------------------------------
# Worktree creation (idempotent)
# ---------------------------------------------------------------------------
# Ensure one worktree for branch $1 at path $2. Reuses whatever already exists.
ensure_worktree() {
    local branch="$1" dir="$2"

    if wt_is_managed "$dir"; then
        print_info "reusing worktree $(short_path "$dir") (${branch})"
        return 0
    fi
    if [[ -e "$dir" ]]; then
        print_warning "skipping $(short_path "$dir") — path exists but is not a worktree of this repo"
        return 0
    fi

    if git -C "$REPO_ROOT" show-ref --verify --quiet "refs/heads/$branch"; then
        print_step "adding worktree $(short_path "$dir") on existing branch ${branch}"
        run_cmd git -C "$REPO_ROOT" worktree add "$dir" "$branch"
    else
        print_step "adding worktree $(short_path "$dir") on new branch ${branch} (from ${BASE_REF})"
        run_cmd git -C "$REPO_ROOT" worktree add -b "$branch" "$dir" "$BASE_REF"
    fi
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------
case "$ACTION" in
    list)  list_worktrees;  exit 0 ;;
    clean) clean_worktrees; exit 0 ;;
esac

BRANCHES=()
DIRS=()
for ((i = 1; i <= WT_COUNT; i++)); do
    BRANCHES+=("${BRANCH_PREFIX}${i}")
    DIRS+=("$WT_ROOT/$(wt_dirname "${BRANCH_PREFIX}${i}")")
done

run_cmd mkdir -p "$WT_ROOT"
for ((i = 0; i < WT_COUNT; i++)); do
    ensure_worktree "${BRANCHES[$i]}" "${DIRS[$i]}"
done

# layout_prelude attaches and exits if the session already exists, so the
# worktree reconciliation above runs on every invocation.
layout_prelude "$SESSION_ARG"

# First window: the original repo — review, diff, merge, harvest. Its index is
# whatever `base-index` says (this repo's tmux.conf sets 1), so ask tmux.
first_win="$(tmux list-windows -t "$SESSION_NAME" -F '#{window_index}' 2>/dev/null | head -1)"
run_cmd tmux rename-window -t "${SESSION_NAME}:${first_win:-0}" main

for ((i = 0; i < WT_COUNT; i++)); do
    win="$(wt_dirname "${BRANCHES[$i]}")"
    run_cmd tmux new-window -t "$SESSION_NAME" -n "$win" -c "${DIRS[$i]}"
    if [[ -n "$AGENT_CMD" ]]; then
        run_cmd tmux send-keys -t "${SESSION_NAME}:${win}" "$AGENT_CMD" C-m
    fi
done

run_cmd tmux select-window -t "${SESSION_NAME}:main"

tmux_attach
