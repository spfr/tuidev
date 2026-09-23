#!/bin/bash
# scripts/lib/gitconfig.sh — opinionated global git defaults, set only where
# the user has not chosen a value.
#
# Called by install.sh and by `update.sh --configs`, so a default added in a
# later release reaches existing machines too. Every key is set only while it
# is unset — including values from [include]d files — and each one we set is
# recorded in the manifest so uninstall can remove exactly those.
#
# Source after ui.sh and manifest.sh. Honors DRY_RUN.

# tuidev_git_default KEY VALUE
tuidev_git_default() {
    local key="$1" value="$2"
    [[ -n "$(git config --global --includes --get "$key" 2>/dev/null)" ]] && return 0
    run_cmd git config --global "$key" "$value" || return 0
    tuidev_manifest_record gitconfig "$key" "$value"
    [[ "${DRY_RUN:-false}" == true ]] || print_success "git $key = $value"
}

# _tuidev_git_at_least VERSION — the installed git is VERSION or newer.
_tuidev_git_at_least() {
    local have
    have="$(git --version | awk '{print $3}')"
    [[ "$(printf '%s\n%s\n' "$have" "$1" | sort -V | head -n1)" == "$1" ]]
}

tuidev_git_defaults() {
    command_exists git || return 0
    print_step "git defaults (only keys you have not set)"

    tuidev_git_default init.defaultBranch main
    tuidev_git_default column.ui auto
    tuidev_git_default branch.sort -committerdate
    tuidev_git_default tag.sort version:refname
    tuidev_git_default help.autocorrect prompt
    tuidev_git_default commit.verbose true

    # Diffs and merges: better hunks, moved-code highlighting, rename detection.
    tuidev_git_default diff.algorithm histogram
    tuidev_git_default diff.colorMoved default
    tuidev_git_default diff.renames true
    # zdiff3 needs git >= 2.35 (Jan 2022); older git rejects the value.
    _tuidev_git_at_least 2.35 && tuidev_git_default merge.conflictStyle zdiff3
    tuidev_git_default rerere.enabled true

    # Stacked, agent-heavy branch work: fixup!/squash! commits land where they
    # belong, dirty trees survive a rebase, and stacked branch refs follow.
    tuidev_git_default rebase.autoSquash true
    tuidev_git_default rebase.autoStash true
    tuidev_git_default rebase.updateRefs true

    tuidev_git_default push.autoSetupRemote true
    tuidev_git_default push.followTags true
    tuidev_git_default fetch.prune true

    if command_exists delta; then
        tuidev_git_default core.pager delta
        tuidev_git_default interactive.diffFilter "delta --color-only"
        tuidev_git_default delta.navigate true
        tuidev_git_default delta.line-numbers true
        # Not side-by-side: agent panes are often ~80 columns wide. Toggle it
        # per run with `git -c delta.side-by-side=true diff` or `delta -s`.
    fi
    print_info "tip: in a large repo, 'git maintenance start' schedules background prefetch/gc"
}
