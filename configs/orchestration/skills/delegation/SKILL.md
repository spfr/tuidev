---
name: delegation
description: Running implementors in parallel, each in its own git worktree, and bringing their work back into the main checkout. Use when splitting a change into parallel workstreams.
---

Parallelize only independent streams, and serialize anything that touches the same files or behavior. Verify once, on the integrated result, not once per implementor.

In Claude Code, `isolation: worktree` gives each agent its own worktree. Elsewhere, implementors commit to a throwaway branch in their own worktree, and you harvest: check that the main index is clean (if not, stop and ask), `git merge --squash <branch>`, `git reset` to unstage, then delete the worktree and branch. Where permission rules gate `git commit` and `git merge`, the scratch commit and the harvest prompt the user: that's expected. Headless, leave the work uncommitted in the worktree and report its path.
