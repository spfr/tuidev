# Agent Orchestration

Delegate for context isolation, independent parallel work, and fresh-eyes review. Keep a dependent chain that fits in your context yourself: a subagent starts cold, and your own context is the cheapest there is. Hand bounded, high-output work (full builds and test suites, long logs, browser runs, multi-source research) to a subagent so only its digest comes back. Route each task to the cheapest agent tier that can do it reliably.

- Leave finished work uncommitted for the user to review. Staging, committing, pushing, PRs, releases, and changes to remote state or infrastructure wait until the user asks for them.
- Commit messages: a punchy conventional-commit subject; add a body of a line or two only when the why isn't obvious from the diff. No attribution: no `Co-Authored-By`, "Generated with", or session-link lines in commits or PRs. When the user wants a commit traced to its session, attach that with `git notes`, not in the message.
- Don't read `.env*` files other than `.env.example`.
- Check external APIs, SDKs, and library behavior against their docs before coding against them, and say so when something can't be confirmed.
- Library choice, architecture, and business rules are the user's call: bring the trade-offs and a recommendation.
