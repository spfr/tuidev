## Codex mechanics

The delegate tiers are the custom-agent profiles in `~/.codex/agents/` (`implementor-complex`, `implementor-standard`, `executor`, `reviewer`); each pins its model and reasoning effort. Prefer them over the built-in `worker` and `explorer` whenever model routing or a structured report matters, and use the built-in `explorer` for cheap read-only discovery. The root orchestrator spawns every agent directly; delegates don't spawn agents of their own. Depth loads on demand from `~/.agents/skills/` (`delegation`, `verification`).
