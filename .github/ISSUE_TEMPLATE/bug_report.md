---
name: Bug Report
about: Report a bug or unexpected behavior
title: '[BUG] '
labels: bug
assignees: ''
---

## Description

A clear description of the bug.

## Environment

- **tuidev version**: (`git describe --tags` in your checkout, e.g. v2.3.1-12-gabc1234)
- **OS**: (e.g. macOS 27.0, Debian 13 arm64)
- **Profile and packs**: (`cat ~/.config/tuidev/profile`: profile, built-in packs, extra_packs)
- **Install method**: git clone
- **Terminal and shell**: (e.g. Ghostty 1.3.1, zsh 5.9, inside tmux?)
- **Sandboxed?**: (did it happen under a CLI's native sandbox, `sbx`, or unsandboxed? which sbx profile, if any?)

## Steps to Reproduce

1. Step one
2. Step two
3. ...

## Expected Behavior

What you expected to happen.

## Actual Behavior

What actually happened.

## Relevant Output

```
Paste error messages, `make check` output, or `--dry-run` output here.
Redact hostnames, usernames and tokens.
```

## Checklist

- [ ] I ran `make check`
- [ ] I searched existing issues for duplicates
- [ ] I reproduced it on the latest `main` (`git pull`, then `make update-configs`)
