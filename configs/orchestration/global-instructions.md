# Agent Orchestration

- Leave finished work uncommitted for the user to review. Staging, committing, pushing, PRs, releases, and changes to remote state or infrastructure wait until the user asks for them.
- Commit messages: a punchy conventional-commit subject; add a body of a line or two only when the why isn't obvious from the diff. No attribution: no `Co-Authored-By`, "Generated with", or session-link lines in commits or PRs. When the user wants a commit traced to its session, attach that with `git notes`, not in the message.
- Don't read `.env*` files other than `.env.example`.
- Library choice, architecture, and business rules are the user's call: bring the trade-offs and a recommendation.
