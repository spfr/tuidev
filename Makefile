# ============================================================================
# Makefile for macOS TUI Development Environment
# ============================================================================
# Provides convenient commands for testing, building, and managing the setup.

.PHONY: help install test check clean docker docker-test docker-clean docker-build \
        update update-check update-packages update-configs update-all brew-upgrade \
        uninstall lint format validate-configs test-clean test-dirty fix-completions

# Default target
.DEFAULT_GOAL := help

# Colors for output
BLUE := \033[0;34m
GREEN := \033[0;32m
YELLOW := \033[1;33m
RED := \033[0;31m
NC := \033[0m

# ============================================================================
# Help
# ============================================================================

help: ## Show this help message
	@echo -e "${BLUE}macOS TUI Development Environment - Available Commands${NC}"
	@echo ""
	@echo -e "${GREEN}Installation & Management:${NC}"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  ${BLUE}%-20s${NC} %s\n", $$1, $$2}'
	@echo ""
	@echo -e "${GREEN}Testing:${NC}"
	@echo "  make test               - Run full test suite"
	@echo "  make check              - Run health check"
	@echo "  make test-clean         - Test clean install (requires VM)"
	@echo "  make test-dirty         - Test install on existing setup"
	@echo ""
	@echo -e "${GREEN}Docker:${NC}"
	@echo "  make docker-build       - Build Docker test image"
	@echo "  make docker-test        - Run tests in Docker"
	@echo "  make docker-clean       - Clean Docker artifacts"
	@echo ""
	@echo -e "${GREEN}Validation:${NC}"
	@echo "  make lint               - Lint shell scripts"
	@echo "  make validate-configs   - Validate configuration files"
	@echo ""
	@echo -e "${GREEN}Utilities:${NC}"
	@echo "  make fix-completions  - Fix insecure zsh completion directories"
	@echo ""

# ============================================================================
# Installation
# ============================================================================

install: ## Run the installation script
	@echo -e "${BLUE}Running installation...${NC}"
	@./install.sh

uninstall: ## Run the uninstallation script
	@echo -e "${YELLOW}Running uninstallation...${NC}"
	@./uninstall.sh

update: ## Update everything (packages + configs) interactively
	@./scripts/update.sh

update-check: ## Check for available updates (no changes)
	@./scripts/update.sh --check

update-packages: ## Update brew packages only
	@./scripts/update.sh --packages

update-configs: ## Sync configs from repo only
	@./scripts/update.sh --configs

update-all: ## Update everything non-interactively
	@./scripts/update.sh --all

brew-upgrade: ## Raw brew upgrade (all packages)
	@echo -e "${BLUE}Upgrading all brew packages...${NC}"
	@brew update && brew upgrade
	@echo -e "${GREEN}Upgrade complete!${NC}"

# ============================================================================
# Testing
# ============================================================================

test: ## Run full test suite
	@echo -e "${BLUE}Running full test suite...${NC}"
	@./scripts/test_suite.sh

check: ## Run health check
	@echo -e "${BLUE}Running health check...${NC}"
	@./scripts/health_check.sh

test-clean: ## Test clean install (CAUTION: destructive)
	@echo -e "${RED}WARNING: This will perform a clean install test${NC}"
	@echo -e "${RED}This may modify your system. Backup your configs first.${NC}"
	@read -p "Continue? (y/N) " -n 1 -r; \
	echo ""; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		echo -e "${BLUE}Creating backup...${NC}"; \
		BACKUP_DIR="$$(mktemp -d)"; \
		cp -r ~/.zshrc ~/.config "$$BACKUP_DIR/" 2>/dev/null || true; \
		echo "Backup: $$BACKUP_DIR"; \
		echo -e "${BLUE}Testing clean install...${NC}"; \
		./install.sh; \
		./scripts/test_suite.sh; \
		echo -e "${GREEN}Clean install test complete${NC}"; \
	fi

test-dirty: ## Test install on top of existing setup
	@echo -e "${BLUE}Testing dirty install...${NC}"
	@echo -e "${YELLOW}This will run install on your current setup${NC}"
	@read -p "Continue? (y/N) " -n 1 -r; \
	echo ""; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		./install.sh; \
		./scripts/health_check.sh; \
		echo -e "${GREEN}Dirty install test complete${NC}"; \
	fi

# ============================================================================
# Docker
# ============================================================================

docker-build: ## Build Docker test image
	@echo -e "${BLUE}Building Docker test image...${NC}"
	@docker build -t mactui-test .

docker-test: docker-build ## Run tests in Docker
	@echo -e "${BLUE}Running tests in Docker...${NC}"
	@docker run --rm mactui-test

docker-clean: ## Clean Docker artifacts
	@echo -e "${BLUE}Cleaning Docker artifacts...${NC}"
	@docker rmi mactui-test 2>/dev/null || true
	@echo -e "${GREEN}Docker cleanup complete${NC}"

# ============================================================================
# Validation & Linting
# ============================================================================

lint: ## Lint shell scripts with shellcheck
	@echo -e "${BLUE}Linting shell scripts...${NC}"
	@command -v shellcheck >/dev/null 2>&1 || (echo "shellcheck not found. Install with: brew install shellcheck" && exit 1)
	@shellcheck install.sh uninstall.sh scripts/*.sh
	@echo -e "${GREEN}Linting complete!${NC}"

validate-configs: ## Validate all configuration files
	@echo -e "${BLUE}Validating configuration files...${NC}"
	@./scripts/validate_configs.sh

validate: validate-configs ## Alias for validate-configs

fix-completions: ## Fix insecure zsh completion directories
	@echo -e "${BLUE}Fixing insecure completion directories...${NC}"
	@./scripts/fix_completions.sh

# ============================================================================
# Cleanup
# ============================================================================

clean: ## Clean test results and temporary files
	@echo -e "${BLUE}Cleaning test results...${NC}"
	@rm -rf test_results/
	@rm -f *.log
	@echo -e "${GREEN}Cleanup complete!${NC}"

# ============================================================================
# Utility
# ============================================================================

backup: ## Create backup of current configs
	@echo -e "${BLUE}Creating backup...${NC}"
	@BACKUP_DIR="backup_$$(date +%Y%m%d_%H%M%S)"; \
	mkdir -p "$$BACKUP_DIR"; \
	cp -r ~/.zshrc ~/.config "$$BACKUP_DIR/" 2>/dev/null || true; \
	echo "Backup created: $$BACKUP_DIR"

restore: ## Restore from backup (usage: make restore BACKUP=backup_YYYYMMDD_HHMMSS)
	@echo -e "${YELLOW}Restoring from $(BACKUP)...${NC}"
	@if [ -z "$(BACKUP)" ]; then \
		echo "Usage: make restore BACKUP=backup_YYYYMMDD_HHMMSS"; \
		echo "Available backups:"; \
		ls -d backup_* 2>/dev/null || echo "No backups found"; \
		exit 1; \
	fi; \
	if [ -d "$(BACKUP)" ]; then \
		cp -r $(BACKUP)/.zshrc $(BACKUP)/.config ~ 2>/dev/null || true; \
		echo -e "${GREEN}Restored from $(BACKUP)${NC}"; \
	else \
		echo -e "${RED}Backup $(BACKUP) not found${NC}"; \
		exit 1; \
	fi

# ============================================================================
# Quick Actions
# ============================================================================

quick-zellij: ## Launch zellij with dev layout
	@command -v zellij >/dev/null 2>&1 || (echo "zellij not installed. Run: make install" && exit 1)
	@zellij --layout dev

quick-lazygit: ## Launch lazygit
	@command -v lazygit >/dev/null 2>&1 || (echo "lazygit not installed. Run: make install" && exit 1)
	@lazygit

quick-lazydocker: ## Launch lazydocker
	@command -v lazydocker >/dev/null 2>&1 || (echo "lazydocker not installed. Run: make install" && exit 1)
	@lazydocker

quick-nnn: ## Launch nnn file manager
	@command -v nnn >/dev/null 2>&1 || (echo "nnn not installed. Run: make install" && exit 1)
	@nnn

quick-sysinfo: ## Show system info
	@command -v fastfetch >/dev/null 2>&1 || (echo "fastfetch not installed. Run: make install" && exit 1)
	@fastfetch

quick-check: ## Quick health check (less verbose)
	@./scripts/health_check.sh 2>&1 | grep -E "✓|✗|⚠" || ./scripts/health_check.sh

# ============================================================================
# CI/CD Helpers
# ============================================================================

ci-test: ## Run CI tests (no interaction)
	@echo -e "${BLUE}Running CI tests...${NC}"
	@./scripts/test_suite.sh
	@./scripts/health_check.sh
