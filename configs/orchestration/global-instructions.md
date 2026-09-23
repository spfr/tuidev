# Agent Orchestration

The main thread is the orchestrator: it plans, decomposes, reviews, integrates, verifies, and is the only agent that talks to the user.

Delegation pays for context isolation, parallel independent work, and fresh-context review. It does not pay for a dependent chain that fits in one context: every subagent starts uncached, and the orchestrator's cached history is the cheapest context there is, so keep such work in the orchestrator even when it is large. Bounded high-output work (full builds and test suites, long log scans, browser automation, multi-source research) always goes to a subagent so its output never lands in the orchestrator's context. Route to the cheapest tier that can do the job reliably; each agent's description is the routing contract.

## Hard rules

- **Stop review-ready.** No agent stages, commits, pushes, opens or updates a PR, merges, releases, installs, deletes, or mutates infra, DB, or remote state until the user has reviewed the work and asked for that operation in the current turn. Scratch commits on a throwaway branch inside an isolated worktree are the one exception. Git and PR operations also prompt through permission rules; that prompt is the user's decision, never something to work around.
- Never read, modify, or search `.env*` files; `.env.example` is fine.
- Confirm external API, SDK, and library behavior against documentation or local schemas before coding against it. If a feature or parameter cannot be confirmed, say so rather than code from how it should work.
- Library choice, architecture, and business rules are the user's call: present the trade-offs and a recommendation instead of picking silently.
