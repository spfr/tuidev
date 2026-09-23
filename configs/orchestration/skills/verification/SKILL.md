---
name: verification
description: Which evidence a change needs and how cheaply to get it — the typecheck → unit → integration → live-browser ladder, when browser or desktop automation is actually warranted, how to batch and script browser validation instead of driving it interactively, and how to keep verbose build, test, log, and research output out of the orchestrator's context. Load when deciding how to verify a change, before driving a browser or desktop, or before a multi-source research pass.
---

## Verification ladder

Use the cheapest rung that produces the evidence the change needs, and escalate only when it cannot answer: typecheck/lint → targeted unit test → integration/E2E test → live browser. Do not re-verify what a lower rung already established. Prefer a check the agent can run to a criterion it has to judge: a failing test, a build exit code, a script that diffs output against a fixture. Show the evidence (the command and its output) rather than asserting success.

Browser and desktop automation are the last rung. Reach for them when rendered, user-visible behavior is itself the acceptance criterion — visual layout, interactive flows, front-end bug reproduction — not to re-confirm logic or backend changes that tests already cover.

## Browser discipline

- Validate once per implementation round against the integrated state, not after every edit.
- If a check will run more than once, script it (Playwright or equivalent) so it becomes a repeatable test. Interactive browser driving is for exploration and one-off diagnosis, not regression.
- Browser and desktop runs are bounded high-output work: delegate them to `executor` so screenshots, DOM dumps, and console noise stay out of the orchestrator's context. The report is a digest — what was checked, pass/fail, and the specific failing evidence.

## Research and output volume

- Research goes search-first: web search and direct page fetch. Drive a live browser only when content needs interaction, authentication, or client-side rendering that fetch cannot reach. Desktop or computer control is the last resort, for when no CLI, API, or file-based path exists.
- Deep multi-source research is bounded high-output work like any other: delegate it and take back a synthesis with citations and confidence notes. Raw pages never enter the orchestrator's context, and the orchestrator judges the synthesis rather than re-reading the sources.
- Filter verbose command output at the shell before it reaches any agent: scoped flags, targeted test selection, `tail`/`grep` on logs, background runs with filtered reads. A nested agent is not the tool for log noise — delegation is for work and judgment, shell filtering is for output.
