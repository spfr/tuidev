## Description

What changed and why.

## Type of Change

- [ ] Bug fix
- [ ] New feature or pack
- [ ] Breaking change (public command, config path, or behavior)
- [ ] Documentation

## Verification

- [ ] `make ci-test` passes (lint, validate-configs, check-links, test-lib)
- [ ] `make test-core` passes locally
- [ ] Installer changes: `./install.sh --profile <p> --dry-run` reviewed (on macOS, also under `/bin/bash`)
- [ ] Container changes: `make container-test` passes
- [ ] Tested on: macOS / Linux (circle what applies)

## Checklist

- [ ] Follows [docs/engineering.md](../docs/engineering.md) (shared libs, pack contract, managed blocks, bash 3.2)
- [ ] Removing or renaming an installed artifact ships a migration
- [ ] The owning doc and `CHANGELOG.md` are updated
- [ ] No hardcoded home paths, real hostnames, IPs or secrets
- [ ] Conventional commit messages, no `Co-Authored-By` trailers

## Related Issues

Closes #
