# Contributing to macOS TUI Development Setup

Thank you for your interest in contributing! This document provides guidelines for contributing to this project.

## How to Contribute

### Reporting Issues

1. **Search existing issues** first to avoid duplicates
2. **Use issue templates** when available
3. **Include environment details:**
   - macOS version
   - Shell (zsh/bash)
   - Relevant tool versions

### Submitting Pull Requests

1. **Fork the repository** and create your branch from `main`
2. **Follow code style** (see below)
3. **Test your changes:**
   ```bash
   make lint        # Shellcheck all scripts
   make test        # Run full test suite
   make docker-test # Test in clean environment
   ```
4. **Update documentation** if you changed behavior
5. **Write clear commit messages** using conventional commits

### Code Style

#### Shell Scripts

- Use `shellcheck` for linting (run `make lint`)
- Use `$HOME` instead of `~` for portability
- Quote variables: `"$variable"` not `$variable`
- Use `[[ ]]` for conditionals (bash/zsh)
- Add comments for non-obvious code

#### Configuration Files

- Use consistent indentation (2 spaces for TOML/KDL, 4 for Lua)
- No hardcoded user paths (`/Users/username`)
- Test configs with `make validate-configs`

### Development Workflow

```bash
# Clone your fork
git clone https://github.com/YOUR_USERNAME/tuidev.git
cd tuidev

# Create a branch
git checkout -b feature/your-feature

# Make changes and test
make lint
make test

# Commit with conventional message
git commit -m "feat: add new feature"

# Push and create PR
git push origin feature/your-feature
```

### Commit Convention

Use conventional commit format:

- `feat:` New feature
- `fix:` Bug fix
- `docs:` Documentation only
- `style:` Formatting, no code change
- `refactor:` Code restructure, no behavior change
- `test:` Adding or updating tests
- `chore:` Maintenance tasks

Examples:
```
feat: add k9s kubernetes TUI
fix: correct zsh completion path
docs: update remote sessions guide
```

### Testing Requirements

All PRs must pass:

1. **Shellcheck** - No lint errors
2. **Config validation** - Valid KDL/TOML/Lua syntax
3. **No hardcoded paths** - Use `$HOME` variables
4. **Docker tests** - Install works in clean environment

Run all checks:
```bash
make ci-test
```

### Areas for Contribution

- **New tools**: Add useful CLI tools to the installer
- **Layouts**: Create new Zellij layouts for different workflows
- **Documentation**: Improve guides and examples
- **Bug fixes**: Fix reported issues
- **Platform support**: Improve Linux compatibility

### What We're Not Looking For

- GUI application additions (this is terminal-focused)
- Controversial or unstable tools
- Personal preference changes without discussion
- Breaking changes to existing workflows

## Getting Help

- Open an issue for questions
- Check existing docs in `docs/` directory
- Review `FAQ.md` for common questions

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
