# MCP Servers Guide

> Model Context Protocol (MCP) servers extend AI coding assistants with external capabilities.

This setup pre-configures MCP servers for Claude Code, OpenCode, and Gemini CLI.

---

## Quick Start

```bash
# 1. Copy and configure environment variables
cp ~/.config/mcp-env.template ~/.config/mcp-env
nvim ~/.config/mcp-env
source ~/.config/mcp-env

# 2. Verify MCP servers (Claude Code)
claude mcp list
```

---

## Server Overview

| Server | Purpose | Dependencies | API Key Required |
|--------|---------|--------------|------------------|
| **filesystem** | File system access | Node.js | No |
| **git** | Git operations | Node.js | No |
| **memory** | Persistent memory | Node.js | No |
| **fetch** | HTTP requests | Python (uv) | No |
| **github** | GitHub API | Docker | Yes |
| **brave-search** | Web search | Node.js | Yes |
| **figma** | Design-to-code | Node.js | Yes |
| **playwright** | Browser automation | Node.js | No |
| **postgres** | PostgreSQL queries | Node.js | Yes (connection string) |
| **sqlite** | SQLite queries | Python (uv) | No |

---

## Core Servers (Enabled by Default)

### filesystem
Full file system access for reading/writing files.

```json
{
  "command": "npx",
  "args": ["-y", "@modelcontextprotocol/server-filesystem", "/"]
}
```

**Capabilities:**
- Read files and directories
- Write and create files
- Search file contents
- Move/copy/delete files

### git
Git repository operations.

```json
{
  "command": "npx",
  "args": ["-y", "@modelcontextprotocol/server-git"]
}
```

**Capabilities:**
- View git status, diff, log
- Stage and commit changes
- Branch operations
- View file history

### memory
Persistent memory across sessions.

```json
{
  "command": "npx",
  "args": ["-y", "@modelcontextprotocol/server-memory"],
  "env": {
    "MEMORY_FILE_PATH": "$HOME/.local/share/claude/memory.jsonl"
  }
}
```

**Capabilities:**
- Remember context between sessions
- Store project-specific knowledge
- Recall previous conversations

### fetch
HTTP requests for web content.

```json
{
  "command": "uvx",
  "args": ["mcp-server-fetch"]
}
```

**Requires:** Python with `uv` installed (`brew install uv`)

**Capabilities:**
- Fetch web pages
- Call REST APIs
- Download content

---

## Browser Automation (Playwright)

The **Playwright MCP server** enables AI agents to control a browser for:
- Web scraping and data extraction
- Automated testing
- Form filling and submissions
- Screenshot capture
- Interactive debugging

### Setup

```bash
# Install Playwright browsers (one-time)
npx playwright install
```

### Configuration

Already configured in your AI tool configs:

```json
{
  "playwright": {
    "command": "npx",
    "args": ["-y", "@anthropic-ai/mcp-server-playwright"]
  }
}
```

### Usage Examples

Once enabled, you can ask your AI agent to:

```
"Open https://example.com and take a screenshot"
"Fill out the login form with test@example.com"
"Click the submit button and wait for the page to load"
"Extract all product prices from this e-commerce page"
"Navigate to the settings page and toggle dark mode"
```

### Capabilities

| Action | Description |
|--------|-------------|
| `navigate` | Go to a URL |
| `click` | Click elements by selector |
| `fill` | Fill form inputs |
| `screenshot` | Capture page screenshots |
| `evaluate` | Run JavaScript in page |
| `wait` | Wait for elements/conditions |

### Best Practices

1. **Start simple** - Let the agent navigate and explore first
2. **Use descriptive selectors** - "the blue submit button" works
3. **Handle popups** - Mention if you expect dialogs
4. **Check screenshots** - Ask for screenshots to verify state

---

## Design-to-Code (Figma)

The **Figma MCP server** enables AI agents to:
- Read Figma designs and extract components
- Generate code from design specs
- Access design tokens (colors, typography, spacing)
- Understand component hierarchy

### Setup

1. **Get Figma Access Token:**
   - Go to: https://www.figma.com/developers/api#access-tokens
   - Click "Create a new personal access token"
   - Copy the token

2. **Configure environment:**
   ```bash
   # Add to ~/.config/mcp-env
   export FIGMA_PERSONAL_ACCESS_TOKEN="your-token-here"
   source ~/.config/mcp-env
   ```

3. **Enable in your AI tool config** (already pre-configured but disabled)

### Configuration

```json
{
  "figma": {
    "command": "npx",
    "args": ["-y", "@anthropic-ai/mcp-server-figma"],
    "env": {
      "FIGMA_PERSONAL_ACCESS_TOKEN": "${FIGMA_PERSONAL_ACCESS_TOKEN}"
    }
  }
}
```

### Usage Examples

```
"Get the design specs for this Figma file: [paste Figma URL]"
"Extract the color palette from this design"
"Generate React components from the Button component in Figma"
"What are the spacing values used in this layout?"
"Convert this Figma frame to Tailwind CSS"
```

### Capabilities

| Action | Description |
|--------|-------------|
| `get_file` | Fetch entire Figma file structure |
| `get_node` | Get specific frame/component |
| `get_styles` | Extract design tokens |
| `get_components` | List all components |
| `get_images` | Export images/icons |

### Design-to-Code Workflow

1. **Share Figma link** with your AI agent
2. **Ask for analysis** - "Analyze this design's structure"
3. **Request code** - "Generate a React component for the header"
4. **Iterate** - "Make the button more rounded like the Figma design"

---

## GitHub Integration

### Setup

**Requires Docker** - The GitHub MCP server runs in a container.

1. **Create GitHub Token:**
   - Go to: https://github.com/settings/tokens
   - Create token with scopes: `repo`, `read:org`, `read:user`

2. **Configure:**
   ```bash
   export GITHUB_PERSONAL_ACCESS_TOKEN="ghp_your_token_here"
   ```

### Configuration

```json
{
  "github": {
    "command": "docker",
    "args": ["run", "-i", "--rm", "-e", "GITHUB_PERSONAL_ACCESS_TOKEN", "ghcr.io/github/github-mcp-server"],
    "env": {
      "GITHUB_PERSONAL_ACCESS_TOKEN": "${GITHUB_PERSONAL_ACCESS_TOKEN}"
    }
  }
}
```

### Capabilities

- Create/read/update issues and PRs
- Search repositories
- Read file contents from repos
- Create branches and commits
- Manage labels and milestones

---

## Web Search (Brave)

### Setup

1. **Get Brave API Key:**
   - Go to: https://brave.com/search/api/
   - Sign up for API access

2. **Configure:**
   ```bash
   export BRAVE_API_KEY="your-api-key"
   ```

### Configuration

```json
{
  "brave-search": {
    "command": "npx",
    "args": ["-y", "@modelcontextprotocol/server-brave-search"],
    "env": {
      "BRAVE_API_KEY": "${BRAVE_API_KEY}"
    }
  }
}
```

### Usage

```
"Search for the latest React 19 features"
"Find documentation for Zellij keyboard shortcuts"
"Look up how to configure Neovim LSP"
```

---

## Database Servers

### PostgreSQL

```json
{
  "postgres": {
    "command": "npx",
    "args": ["-y", "@modelcontextprotocol/server-postgres"],
    "env": {
      "POSTGRES_CONNECTION_STRING": "postgresql://user:pass@localhost:5432/mydb"
    }
  }
}
```

**Capabilities:** Query, insert, update, delete, schema inspection

### SQLite

```json
{
  "sqlite": {
    "command": "uvx",
    "args": ["mcp-server-sqlite", "--db-path", "./database.db"]
  }
}
```

**Requires:** Python with `uv` installed

---

## Enabling/Disabling Servers

### Claude Code (~/.claude.json)

Add `"disabled": true` to disable a server:

```json
{
  "mcpServers": {
    "playwright": {
      "command": "npx",
      "args": ["-y", "@anthropic-ai/mcp-server-playwright"],
      "disabled": false  // Set to true to disable
    }
  }
}
```

### OpenCode (~/.config/opencode/opencode.json)

Use `"enabled": false`:

```json
{
  "mcp": {
    "playwright": {
      "type": "local",
      "command": ["npx", "-y", "@anthropic-ai/mcp-server-playwright"],
      "enabled": true  // Set to false to disable
    }
  }
}
```

---

## Troubleshooting

### Server Not Starting

```bash
# Check if Node.js is available
node --version

# Check if npx works
npx --version

# Test server manually
npx -y @modelcontextprotocol/server-filesystem /
```

### Docker Server Issues (GitHub)

```bash
# Check Docker is running
docker ps

# Pull the image manually
docker pull ghcr.io/github/github-mcp-server

# Test with token
echo $GITHUB_PERSONAL_ACCESS_TOKEN | docker run -i --rm -e GITHUB_PERSONAL_ACCESS_TOKEN ghcr.io/github/github-mcp-server
```

### Python Server Issues (fetch, sqlite)

```bash
# Install uv if missing
brew install uv

# Test uvx
uvx mcp-server-fetch --help
```

### Environment Variables Not Loading

```bash
# Verify env file exists and is sourced
cat ~/.config/mcp-env
source ~/.config/mcp-env
echo $FIGMA_PERSONAL_ACCESS_TOKEN
```

---

## Dependencies Summary

| Dependency | Required For | Install |
|------------|--------------|---------|
| Node.js | Most servers | `brew install node` |
| Python + uv | fetch, sqlite | `brew install python uv` |
| Docker | github | `brew install --cask docker` |
| Playwright browsers | playwright | `npx playwright install` |

---

## Security Notes

1. **API tokens** - Store in `~/.config/mcp-env`, never commit to git
2. **File access** - filesystem server has full access to specified paths
3. **Browser automation** - Playwright can access any website
4. **Database access** - Connection strings contain credentials

---

## See Also

- [MCP Protocol Spec](https://modelcontextprotocol.io/)
- [Claude Code MCP Docs](https://docs.anthropic.com/claude-code/mcp)
- [Playwright Docs](https://playwright.dev/)
- [Figma API Docs](https://www.figma.com/developers/api)
