# AI Agent Orchestration Guide

This guide covers autonomous AI agent orchestration using the Ralph Wiggum technique and multi-agent workflows.

## Overview

Traditional AI coding workflows require constant human supervision. Ralph Wiggum changes this by running AI agents in autonomous loops until tasks complete.

```
┌─────────────────────────────────────────────────────────────┐
│                     Ralph Loop                               │
│  ┌─────────┐    ┌─────────────┐    ┌──────────────────┐    │
│  │  Prompt │───▶│  AI Agent   │───▶│ Check Completion │    │
│  └─────────┘    └─────────────┘    └──────────────────┘    │
│       ▲                                      │              │
│       │              Not Complete            │              │
│       └──────────────────────────────────────┘              │
│                      Complete ───▶ Exit                     │
└─────────────────────────────────────────────────────────────┘
```

## Quick Start

```bash
# Simple task
ralph "Fix all TypeScript errors in src/"

# With specific agent
ralph --agent opencode "Build REST API for users"

# With iteration limit
ralph --agent aider --max-iterations 10 "Add unit tests"

# From task file
ralph --file PRD.md --max-iterations 30
```

## Available AI Agents

### Claude Code (Default)
Anthropic's official CLI. Best for complex reasoning tasks.

```bash
ralph "Refactor auth module with improved error handling"
ralph --agent claude "Implement OAuth2 flow"
```

### OpenCode
Open-source alternative supporting 75+ model providers.

```bash
ralph --agent opencode "Migrate database schema"
ralph --agent opencode "Add GraphQL resolvers"
```

## Ralph Wiggum Technique

Named after The Simpsons character, Ralph embodies persistent iteration:

1. **Give a task** with clear completion criteria
2. **Agent works** until it thinks it's done
3. **Check completion** - if not done, loop back
4. **Exit** when complete or max iterations reached

### Completion Markers

Ralph looks for `RALPH_COMPLETE` in agent output. You can customize this:

```bash
# Agent should output RALPH_COMPLETE when truly done
ralph "Build feature X and output RALPH_COMPLETE when all tests pass"
```

## Task File Format

For complex projects, use a task file:

```markdown
# tasks.md

## Objective
Build a user authentication system

## Requirements
1. JWT-based authentication
2. Password hashing with bcrypt
3. Rate limiting on login endpoint
4. Unit tests with >80% coverage

## Acceptance Criteria
- All tests pass
- No TypeScript errors
- Lint checks pass

## Notes
- Use existing User model in src/models/
- Follow project conventions in CLAUDE.md
```

Then run:
```bash
ralph --file tasks.md --max-iterations 25
```

## Multi-Agent Workflows

### Sequential Agents

Run different agents for different phases:

```bash
# Phase 1: Architecture with Claude (better reasoning)
ralph --agent claude --max-iterations 5 "Design the database schema for task management"

# Phase 2: Implementation with OpenCode (faster)
ralph --agent opencode --max-iterations 15 "Implement the designed schema"

# Phase 3: Testing with Aider (git-integrated)
ralph --agent aider --max-iterations 10 "Write comprehensive tests"
```

### Parallel Agents with Zellij

Use your Zellij layout for parallel work:

```bash
# Terminal 1 (left pane)
ralph --agent claude "Build frontend components"

# Terminal 2 (right pane)
ralph --agent opencode "Build API endpoints"
```

## Best Practices

### 1. Start Small
```bash
# Good: Specific, bounded task
ralph --max-iterations 5 "Fix the login form validation"

# Risky: Vague, unbounded task
ralph --max-iterations 50 "Make the app better"
```

### 2. Set Iteration Limits
Always use `--max-iterations` as a safety mechanism:

```bash
ralph --max-iterations 10 "Task here"  # Safe default
ralph --max-iterations 30 "Complex task"  # For bigger work
```

### 3. Use Logging
```bash
ralph -v -l session.log "Complex refactoring task"
# Review logs if something goes wrong
```

### 4. Dry Run First
```bash
ralph --dry-run "Potentially risky task"
# See what would execute before committing
```

### 5. Clear Completion Criteria
```bash
# Good: Clear criteria
ralph "Add login endpoint. Complete when: 1) POST /auth/login works 2) Returns JWT 3) Tests pass"

# Bad: Vague criteria
ralph "Add authentication"
```

## Safety Considerations

### API Costs
- Each iteration uses API tokens
- Set reasonable `--max-iterations`
- Monitor usage in provider dashboard

### Code Review
- Ralph commits code, but review before pushing
- Use `git diff HEAD~N` to review changes
- Aider creates atomic commits for easy review

### Interrupting
- Press `Ctrl+C` to stop the loop
- Work is saved (agents commit incrementally)

## Troubleshooting

### Agent Not Found
```bash
# Install missing agent
npm install -g @anthropic-ai/claude-code  # Claude
curl -fsSL https://opencode.ai/install | bash  # OpenCode
pipx install aider-chat  # Aider
```

### Task Never Completes
1. Check if criteria are achievable
2. Review logs with `--verbose`
3. Lower `--max-iterations` and iterate manually

### API Key Issues
```bash
# Set keys in environment
export ANTHROPIC_API_KEY="sk-..."
export OPENAI_API_KEY="sk-..."

# Or use ~/.config/mcp-env
source ~/.config/mcp-env
```

## Example Sessions

### Bug Fix Session
```bash
ralph --agent aider --max-iterations 5 \
  "Fix issue #42: Login fails for users with special characters in password"
```

### Feature Development
```bash
ralph --agent claude --max-iterations 20 \
  --file features/user-dashboard.md \
  --log dashboard-dev.log
```

### Overnight Refactoring
```bash
# Start before leaving
ralph --agent opencode --max-iterations 50 \
  "Migrate from React 16 to React 19. Update all components and fix breaking changes." \
  --log overnight.log
```

## Integration with Zellij

Launch ralph in your AI workflow layout:

```bash
# Start AI session
ai

# In Agent-1 pane, run ralph
ralph --agent claude "Your task"

# In Agent-2 pane, work on something else
ralph --agent opencode "Another task"
```

## Related Resources

- [Ralph Wiggum Technique](https://awesomeclaude.ai/ralph-wiggum)
- [Open Ralph Wiggum](https://github.com/Th0rgal/open-ralph-wiggum)
- [Aider Documentation](https://aider.chat/docs/)
- [Claude Code Plugins](https://github.com/anthropics/claude-code/tree/main/plugins)
