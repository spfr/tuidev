---
name: delegation
description: How to hand work to subagents and bring it back — what a delegation prompt must carry, preferring executable references (failing tests, schemas, mockups, rubrics) over prose acceptance criteria, what implementors report, when to run executor verification against integrated state, when to route a change set to an independent reviewer, how to parallelize in isolated worktrees and harvest a scratch branch, and how to run a review-fix loop with a findings ledger. Load before spawning implementors for a multi-step task, when integrating parallel workstreams, or when working through user review findings.
---

## Delegation contract

A delegation prompt carries what the subagent cannot cheaply rediscover: the purpose (what larger task this serves and what the output enables — agents perform better knowing the intent than inferring it), file paths and line anchors, applicable project rules, acceptance criteria, the targeted verification expected, the required report format, and any operational or safety constraint its own definition does not already cover.

Prefer executable references over prose acceptance criteria wherever one exists — a failing test, a schema, a type signature, an HTML mockup, a function in another codebase to port. They are higher-fidelity than description and the subagent can check itself against them. A rubric file does the same job for taste-driven review: hand it to the reviewer instead of describing the standard in prose.

Implementors report: changed files and behavior; verification performed and results; unresolved risks or assumptions; and a concise technical summary usable as draft commit or PR text.

## Verification timing

Full-suite and verbose verification goes to an `executor` spawned by the orchestrator, timed deliberately: with parallel workstreams in flight, gather their reports, integrate, then run one executor round against the integrated state rather than a run per implementor. Spin up fix agents only if that round fails.

For risky or large change sets, order independent review before accepting. The bundled `/code-review` skill is the bug hunt on the current diff; the `reviewer` tier is the spec-compliance pass against the acceptance criteria and the plan — fresh context, read-only, ranked findings, never fixes. Tell it to report only gaps that affect correctness or the stated requirements, since a reviewer asked for gaps will find some even in sound work. The reviewer is never the implementor that wrote the change.

## Integration and git

The orchestrator reviews reports and evidence, resolves integration decisions, and synthesizes the final commit or PR text when several implementors contributed. An executor performing an authorized git or platform operation acts mechanically from the orchestrator's exact approved metadata — it never reinterprets the diff or invents commit, PR, merge, or release descriptions.

When implementation and verification are done, stop review-ready: changes uncommitted and unstaged, with a report of what changed, where, how it was verified, and what deserves close review.

## Parallel work and worktrees

Parallelize only independent workstreams, in isolated worktrees when write-heavy streams could interfere. Serialize anything touching the same files, shared behavior, or overlapping test surfaces. Conflict resolution requires orchestrator judgment.

In Claude Code, spawn the agent with `isolation: worktree`; the harness creates the worktree and removes it if nothing changed. Where that is not available, the manual procedure below applies.

A scratch commit on a throwaway branch inside such a worktree is the one permitted version-control write — never pushed, never merged into a real branch. Harvest: confirm the main tree's index is clean (if it is not, stop and ask — never clear or stash the user's staged state), `git merge --squash <scratch-branch>`, `git reset` to unstage while preserving pre-existing unstaged changes, then delete the worktree and branch. The harvest is mechanical and executor-delegable; on squash conflict it stops and escalates. Where permission rules gate `git commit` and `git merge`, the scratch commit and the harvest each prompt the user: that approval is expected, not something to route around. Headless, where nobody can approve, leave the work uncommitted in the worktree and report its path.

## Review-fix loop

User review findings get a ledger (`open`, `in-fix`, `verified`, `user-confirmed`). Re-anchor each finding to current file state, route edits through fresh fix agents reading the integrated tree, serialize overlapping fixes, and end every round review-ready with updated verification evidence. If a fix round grows large enough to need isolated parallel implementation, ask before checkpointing the accepted state.
