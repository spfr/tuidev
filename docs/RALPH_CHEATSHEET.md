# Ralph Wiggum Cheatsheet

Autonomous AI agent orchestration - let AI work while you sleep.

---

## How It Works

```
You ──▶ ralph "task" ──▶ AI CLI ──▶ Check for RALPH_COMPLETE
                           ▲                    │
                           └── not done ────────┘
                               done ──▶ exit
```

**Ralph wraps your AI CLIs (claude, opencode) in a loop that keeps running until the task is complete.**

---

## Quick Reference

```bash
# Basic usage (uses Claude Code by default)
ralph "Fix the login bug"

# Use OpenCode instead
ralph --agent opencode "Build REST API"

# Limit iterations (safety)
ralph --max-iterations 10 "Add unit tests"

# From task file
ralph --file tasks.md

# With logging
ralph -l session.log "Complex refactoring"

# Dry-run (preview only)
ralph --dry-run "Risky task"
```

---

## Agent Selection

| Agent | Command | Best For |
|-------|---------|----------|
| **Claude Code** | `--agent claude` (default) | Complex reasoning, debugging, architecture |
| **OpenCode** | `--agent opencode` | Speed, cost savings, multi-model flexibility |

---

## Options

| Flag | Short | Description |
|------|-------|-------------|
| `--agent <name>` | `-a` | AI agent: `claude`, `opencode` |
| `--max-iterations <n>` | `-m` | Safety limit (default: 20) |
| `--file <path>` | `-f` | Read prompt from file |
| `--log <path>` | `-l` | Save output to log file |
| `--verbose` | `-v` | Show full agent output |
| `--dry-run` | `-d` | Preview without executing |
| `--help` | `-h` | Show help |

---

## Best Practices

### 1. Always Set Iteration Limits
```bash
# Safe
ralph --max-iterations 10 "Add tests"

# Risky (could run forever on vague tasks)
ralph "Make the app better"
```

### 2. Be Specific About Completion
```bash
# Good - clear criteria
ralph "Fix TypeScript errors. Done when: tsc --noEmit passes"

# Bad - vague
ralph "Fix some bugs"
```

### 3. Use Dry-Run First
```bash
ralph --dry-run "Delete old migrations"  # Preview
ralph "Delete old migrations"             # Execute
```

### 4. Log Long Sessions
```bash
ralph -l overnight.log --max-iterations 50 "Major refactoring"
# Review: cat overnight.log
```

### 5. Start Small
```bash
# First run with low limit
ralph --max-iterations 3 "New feature"

# If working well, increase
ralph --max-iterations 15 "New feature"
```

---

## Example Workflows

### Bug Fix
```bash
ralph "Fix issue #42: login fails for emails with + character"
```

### Feature Development
```bash
ralph --max-iterations 20 "Build user dashboard with:
- Profile section
- Activity feed
- Settings page
Done when all components render without errors"
```

### Code Review & Fix
```bash
ralph --agent opencode "Review src/api/ for security issues and fix them"
```

### PRD-Driven Development
```bash
# Create tasks.md with requirements, then:
ralph --file tasks.md --max-iterations 30 -l feature.log
```

### Overnight Refactoring
```bash
ralph --max-iterations 100 -l overnight.log \
  "Migrate from React 16 to React 19. Update all components."
```

---

## Completion Marker

Ralph looks for `RALPH_COMPLETE` in the agent's output.

The prompt automatically tells the agent:
> "When done, output RALPH_COMPLETE"

You can also add explicit criteria:
```bash
ralph "Fix tests. Output RALPH_COMPLETE only when ALL tests pass."
```

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Task never completes | Lower `--max-iterations`, make criteria clearer |
| Agent not found | Install: `claude` or `opencode` |
| API errors | Check API keys in environment |
| Runaway loop | `Ctrl+C` to stop, work is saved |

---

## Cost Awareness

Each iteration = API calls = money

| Task Type | Suggested Limit |
|-----------|-----------------|
| Simple fix | 3-5 iterations |
| Feature | 10-20 iterations |
| Major refactor | 30-50 iterations |
| Overnight job | 50-100 iterations |

Use `--agent opencode` with cheaper models for cost savings.

---

## Quick Examples

```bash
# Fix lint errors
ralph -m 5 "Fix all eslint errors"

# Add documentation
ralph -m 10 "Add JSDoc comments to src/utils/"

# Write tests
ralph -m 15 "Write unit tests for auth module, aim for 80% coverage"

# Refactor
ralph -m 20 -l refactor.log "Extract duplicate code into shared utilities"
```

---

**Philosophy: Define the task, set limits, let Ralph handle the iterations.**
