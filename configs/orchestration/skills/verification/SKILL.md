---
name: verification
description: Choosing the cheapest evidence a change needs and keeping verbose output out of your context — when a browser or desktop run is worth it, and how to delegate builds, suites, logs and research. Use before driving a browser or running a long suite or research pass.
---

- Use the cheapest check that answers the question (typecheck, then a targeted test, then integration), and show the command and its output rather than claiming success.
- A live browser or desktop run is the last resort, for when rendered, user-visible behavior is itself the acceptance criterion. If a check will run more than once, script it (Playwright or equivalent) instead of driving it by hand.
- Full suites, browser runs, long logs and multi-source research are bounded high-output work: hand them to `executor` (or a research subagent) and take back a digest with the failing evidence or citations. Filter at the shell (scoped flags, `tail`, `grep`) before output reaches any agent.
- For research, search and fetch first. Use a browser only for pages that need interaction or client-side rendering.
