# ============================================================================
# Makefile — tuidev
# ============================================================================
# Convenient targets for install, update, test, lint, and day-to-day use.
# Run `make` with no args to see the help.

.PHONY: help \
        install install-minimal install-desktop install-remote install-dry \
        uninstall \
        update update-check update-packages update-configs update-migrations update-all \
        update-security \
        test test-core test-ui test-all test-lib \
        check check-minimal check-desktop check-remote \
        lint validate-configs validate check-links \
        sbx-test sandbox-up sandbox-down \
        adopt fix-completions clean \
        container-runtime container-build container-test container-clean \
        docker-build docker-test docker-clean \
        brew-upgrade ci-test \
        quick-lazygit quick-sysinfo \
        theme theme-list

.DEFAULT_GOAL := help
# Recipes use bash (echo -e, [[ ]]); /bin/sh is dash on Debian.
SHELL := bash

BLUE   := \033[0;34m
GREEN  := \033[0;32m
YELLOW := \033[1;33m
RED    := \033[0;31m
NC     := \033[0m

# ----------------------------------------------------------------------------
# Help
# ----------------------------------------------------------------------------

help: ## Show this help message
	@echo -e "${BLUE}tuidev — available targets${NC}"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	  | sort \
	  | awk 'BEGIN {FS = ":.*?## "}; {printf "  ${GREEN}%-24s${NC} %s\n", $$1, $$2}'

# ----------------------------------------------------------------------------
# Install
# ----------------------------------------------------------------------------

install: ## Interactive install (defaults to desktop on macOS, minimal on Linux)
	@./install.sh

install-minimal: ## Install the minimal profile (core only)
	@./install.sh --profile minimal

install-desktop: ## Install the desktop profile (core + ui + sandbox)
	@./install.sh --profile desktop

install-remote: ## Install the remote profile (core + remote + sandbox + tmux pack)
	@./install.sh --profile remote

install-dry: ## Preview install for a profile (PROFILE=desktop make install-dry)
	@./install.sh --dry-run --profile $(if $(PROFILE),$(PROFILE),desktop)

uninstall: ## Run the uninstaller
	@./uninstall.sh

# ----------------------------------------------------------------------------
# Update
# ----------------------------------------------------------------------------

update: ## Update everything interactively (profile-aware)
	@./scripts/update.sh

update-check: ## Preview available updates (no changes)
	@./scripts/update.sh --check

update-packages: ## Update brew packages for the installed profile only
	@./scripts/update.sh --packages

update-configs: ## Re-apply managed blocks and pack-owned configs
	@./scripts/update.sh --configs

update-migrations: ## Run pending one-shot migrations
	@./scripts/update.sh --migrations

update-all: ## Non-interactive: packages + configs + repo
	@./scripts/update.sh --all

update-security: ## Audit Tailscale + SSH perms + Seatbelt profile drift
	@./scripts/update.sh --security

brew-upgrade: ## Raw `brew update && brew upgrade` (bypasses profile)
	@brew update && brew upgrade

# ----------------------------------------------------------------------------
# Test + health check (profile-aware)
# ----------------------------------------------------------------------------

test: ## Run tests for the active profile (default tags)
	@./scripts/test_suite.sh

test-core: ## Run only the core-tag tests
	@./scripts/test_suite.sh --tag core

test-ui: ## Run only the ui-tag tests (macOS GUI)
	@./scripts/test_suite.sh --tag ui

test-all: ## Run all tags including ui
	@./scripts/test_suite.sh --all

test-lib: ## Run the scripts/lib unit-test harnesses
	@for t in scripts/lib/test_*.sh; do bash "$$t" || exit 1; done

check: ## Health check for the active profile
	@./scripts/health_check.sh

check-minimal: ## Health check against the minimal profile
	@./scripts/health_check.sh --profile minimal

check-desktop: ## Health check against the desktop profile
	@./scripts/health_check.sh --profile desktop

check-remote: ## Health check against the remote profile
	@./scripts/health_check.sh --profile remote

# ----------------------------------------------------------------------------
# Lint + validate
# ----------------------------------------------------------------------------

# One file list for `make lint` and CI.
SHELL_FILES := install.sh uninstall.sh scripts/*.sh scripts/lib/*.sh \
               scripts/install/*.sh scripts/install/packs/*.sh \
               scripts/migrations/*.sh bin/sbx

lint: ## Shellcheck every shell script (install, scripts, libs, packs, migrations, sbx)
	@command -v shellcheck >/dev/null 2>&1 || { echo "shellcheck not found. brew install shellcheck"; exit 1; }
	@shellcheck -x $(SHELL_FILES)
	@echo -e "${GREEN}shellcheck clean${NC}"

validate-configs: ## Validate JSON, TOML, Lua and shell config syntax
	@./scripts/validate_configs.sh

check-links: ## Check every relative link in the Markdown docs
	@./scripts/check_links.sh

validate: validate-configs ## Alias for validate-configs

# ----------------------------------------------------------------------------
# Sandbox
# ----------------------------------------------------------------------------

sbx-test: ## Smoke-test the Seatbelt wrapper: deny ~/.ssh, allow project
	@command -v sbx >/dev/null 2>&1 || { echo "sbx not installed. Run make install-desktop or ./install.sh --sandbox"; exit 1; }
	@echo -e "${BLUE}sbx smoke test${NC}"
	@echo -e "1. ${YELLOW}sbx -- ls $$PWD${NC}  (should succeed)"
	@sbx -- ls $$PWD >/dev/null 2>&1 && echo -e "   ${GREEN}PASS${NC}" || echo -e "   ${RED}FAIL${NC}"
	@echo -e "2. ${YELLOW}sbx -- cat ~/.ssh/id_ed25519${NC}  (should FAIL — sandbox blocks credentials)"
	@! sbx -- cat ~/.ssh/id_ed25519 2>/dev/null && echo -e "   ${GREEN}PASS${NC} (correctly denied)" || echo -e "   ${RED}FAIL${NC} (should have been denied)"

sandbox-up: ## Start the Tier 2 container backend (Apple container → podman → docker)
	@./scripts/container.sh up

sandbox-down: ## Stop the Tier 2 container backend
	@./scripts/container.sh down || true

# ----------------------------------------------------------------------------
# Migration helpers
# ----------------------------------------------------------------------------

adopt: ## Convert existing dotfiles to tuidev managed-block form (one-time)
	@echo -e "${BLUE}Adopting existing dotfiles into managed-block format...${NC}"
	@./scripts/update.sh --configs

fix-completions: ## Fix insecure zsh completion directories
	@./scripts/fix_completions.sh

clean: ## Remove test results and transient files
	@rm -rf test_results/ *.log
	@echo -e "${GREEN}cleaned${NC}"

# ----------------------------------------------------------------------------
# Containers (Linux parity smoke test). Runtime order: Apple `container`
# (macOS 26+) → podman → docker. Force one with TUIDEV_CONTAINER_RUNTIME=…
# ----------------------------------------------------------------------------

container-runtime: ## Print which container runtime the targets below will use
	@./scripts/container.sh runtime

container-build: ## Build the Alpine test image
	@./scripts/container.sh build

container-test: ## Run the core-tagged tests inside a container
	@./scripts/container.sh test

container-clean: ## Remove the test image
	@./scripts/container.sh clean

# Back-compat aliases (older docs / muscle memory).
docker-build: container-build
docker-test: container-test
docker-clean: container-clean

# ----------------------------------------------------------------------------
# Quick launchers
# ----------------------------------------------------------------------------

quick-lazygit: ## Launch lazygit
	@command -v lazygit >/dev/null 2>&1 && lazygit || echo "lazygit not installed"

quick-sysinfo: ## Show system info
	@command -v fastfetch >/dev/null 2>&1 && fastfetch || uname -a

theme-list: ## List available color themes
	@./scripts/theme.sh list

theme: ## Apply a theme: make theme NAME=catppuccin-mocha
	@./scripts/theme.sh apply $(or $(NAME),tokyo-night)

# ----------------------------------------------------------------------------
# CI
# ----------------------------------------------------------------------------

ci-test: ## Everything CI runs that works locally (lint, validate, links, unit tests)
	@$(MAKE) lint
	@$(MAKE) validate-configs
	@$(MAKE) check-links
	@$(MAKE) test-lib
