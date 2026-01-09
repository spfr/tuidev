# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 1.x.x   | :white_check_mark: |

## Reporting a Vulnerability

If you discover a security vulnerability in this project, please report it responsibly:

1. **Do not** open a public GitHub issue for security vulnerabilities
2. Email the maintainers or use GitHub's private vulnerability reporting feature
3. Include detailed information about the vulnerability
4. Allow reasonable time for a fix before public disclosure

## Security Considerations

### API Keys and Secrets

This project uses environment variables for sensitive data:

- API keys are **never** stored in configuration files
- Use `~/.config/mcp-env` for local API key storage
- The `.gitignore` excludes common secret file patterns

### MCP Server Security

MCP servers that require authentication are **disabled by default**:

- `github` - Requires `GITHUB_PERSONAL_ACCESS_TOKEN`
- `brave-search` - Requires `BRAVE_API_KEY`
- `figma` - Requires `FIGMA_PERSONAL_ACCESS_TOKEN`
- `postgres` - Requires connection string

Only enable these after configuring appropriate credentials.

### File Permissions

The installer creates configuration files with appropriate permissions. Sensitive files should have restricted access:

```bash
chmod 600 ~/.config/mcp-env
```

### Best Practices

1. **Review scripts before running** - Especially when piping from curl
2. **Use dry-run mode** - Preview changes with `./install.sh --dry-run`
3. **Keep tools updated** - Run `make update-packages` regularly
4. **Audit MCP servers** - Only enable servers you need

## Acknowledgments

We appreciate responsible disclosure of security issues.
