---
name: delegation
description: Handing work to subagents and integrating it back — what a delegation prompt carries, parallel work in worktrees and harvesting it, when to verify and when to send a change to the reviewer. Use before spawning implementors for a multi-step task or when merging parallel workstreams.
---

## The prompt

Give a subagent what it can't cheaply rediscover: the purpose, file anchors, the acceptance criteria, the verification you expect, and the report format. Prefer an executable reference to prose where one exists: a failing test, a schema, a type signature, a mockup, code to port.

## Verify and review once, on the integrated state

With parallel workstreams in flight, gather the reports and integrate, then run one `executor` round against the result instead of one per implementor. The `reviewer` is a fresh-context check for changes where a plausible-but-wrong result would be costly; it never reviews its own work. For a plain bug hunt on the current diff, `/code-review` is cheaper.

## Parallel work

Parallelize only independent streams, and serialize anything that touches the same files or behavior. In Claude Code, `isolation: worktree` gives each agent its own worktree. Elsewhere, implementors commit to a throwaway branch in their own worktree, and you harvest: check that the main index is clean (if not, stop and ask), `git merge --squash <branch>`, `git reset` to unstage, then delete the worktree and branch. Where permission rules gate `git commit` and `git merge`, the scratch commit and the harvest prompt the user: that's expected. Headless, leave the work uncommitted in the worktree and report its path.

When it's done, stop review-ready: changes unstaged, with a report of what changed, how it was verified, and what deserves a close look.
