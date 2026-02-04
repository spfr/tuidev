#!/bin/bash

# ============================================================================
# macOS Developer Productivity Setup - Automated Installer
# ============================================================================
#
# A comprehensive setup for engineering and design teams including:
# - Terminal multiplexer and modern CLI tools
# - Window management for productivity
# - System utilities and enhancements
# - AI-ready development environment
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/spfr/tuidev/main/install.sh | bash
#
# Or clone and run:
#   git clone https://github.com/spfr/tuidev.git
#   cd tuidev
#   ./install.sh
#
# Dry-run mode (preview without installing):
#   ./install.sh --dry-run
#   ./install.sh -d
#
# ============================================================================

set -e

# Dry-run mode
DRY_RUN=false
if [[ "$1" == "--dry-run" ]] || [[ "$1" == "-d" ]]; then
    DRY_RUN=true
    shift
fi

# Wrapper function for dry-run
run_cmd() {
    local cmd="$*"
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${YELLOW}[DRY RUN]${NC} $cmd"
    else
        "$@"
    fi
}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ============================================================================
# Helper Functions
# ============================================================================

print_header() {
    echo ""
    echo -e "${PURPLE}============================================================================${NC}"
    echo -e "${PURPLE}$1${NC}"
    echo -e "${PURPLE}============================================================================${NC}"
    echo ""
}

print_step() {
    echo -e "${CYAN}>>> ${NC}$1"
}

print_success() {
    echo -e "${GREEN}✓ ${NC}$1"
}

print_warning() {
    echo -e "${YELLOW}⚠ ${NC}$1"
}

print_error() {
    echo -e "${RED}✗ ${NC}$1"
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

app_installed() {
    [[ -d "/Applications/$1.app" ]] || [[ -d "$HOME/Applications/$1.app" ]]
}

# ============================================================================
# Pre-flight Checks
# ============================================================================

print_header "macOS Developer Productivity Setup"

cat << 'EOF'
This script will install and configure:

TERMINAL & CLI
  • Zellij         - Terminal multiplexer for multi-pane workflows
  • Starship       - Fast, customizable shell prompt
  • fzf            - Fuzzy finder for files, history, and more
  • ripgrep        - Lightning-fast code search
  • bat            - cat with syntax highlighting
  • eza            - Modern ls replacement with icons
  • fd             - Fast file finder
  • zoxide         - Smart directory navigation
  • nnn            - TUI file manager (fastest)
  • lazygit        - Beautiful git TUI
  • lazydocker     - TUI for Docker management
  • delta          - Better git diffs
  • glow           - Markdown TUI viewer
  • ncdu           - Interactive disk usage
  • bandwhich      - Network bandwidth monitor
  • fastfetch      - System info (fast neofetch)
  • k9s            - Kubernetes TUI

WINDOW MANAGEMENT
  • Rectangle      - Window snapping and management (free)
  • Hammerspoon    - macOS automation powerhouse

SYSTEM PRODUCTIVITY (All Open Source)
  • Stats          - Menu bar system monitor
  • Maccy          - Clipboard manager
  • Hidden Bar     - Hide menu bar icons

REMOTE ACCESS
  • Tailscale      - Mesh VPN for secure remote access
  • Mosh           - Mobile shell (resilient SSH)

DEVELOPMENT
  • Neovim         - Modern text editor
  • GitHub CLI     - GitHub from the command line

EOF

# Check if running on macOS
if [[ "$(uname)" != "Darwin" ]]; then
    print_error "This script is designed for macOS only."
    exit 1
fi

print_success "Running on macOS $(sw_vers -productVersion)"

read -p "Do you want to continue? (y/n) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_warning "Installation cancelled."
    exit 0
fi

# ============================================================================
# Install Homebrew
# ============================================================================

print_header "Step 1/7: Installing Homebrew"

if command_exists brew; then
    print_success "Homebrew already installed"
    run_cmd brew update
else
    print_step "Installing Homebrew..."
    if [[ "$DRY_RUN" == true ]]; then
        print_warning "Would install Homebrew (skipped in dry-run)"
    else
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

        if [[ -f "/opt/homebrew/bin/brew" ]]; then
            eval "$(/opt/homebrew/bin/brew shellenv)"
        fi

        print_success "Homebrew installed"
    fi
fi

# ============================================================================
# Install Terminal & CLI Tools
# ============================================================================

print_header "Step 2/7: Installing Terminal & CLI Tools"

CLI_TOOLS=(
    "zellij"           # Terminal multiplexer
    "fzf"              # Fuzzy finder
    "ripgrep"          # Fast grep
    "bat"              # Better cat
    "eza"              # Better ls
    "starship"         # Shell prompt
    "gh"               # GitHub CLI
    "git-delta"        # Better git diff
    "lazygit"          # Git TUI
    "lazydocker"       # Docker TUI
    "zoxide"           # Smart cd
    "fd"               # Fast find
    "jq"               # JSON processor
    "yq"               # YAML processor
    "httpie"           # HTTP client
    "bottom"           # System monitor
    "atuin"            # Shell history
    "neovim"           # Text editor
    "glow"             # Markdown TUI viewer
    "nnn"              # TUI file manager
    "ncdu"             # Interactive disk usage
    "bandwhich"        # Network bandwidth monitor
    "fastfetch"        # System info (fast neofetch)
    "k9s"              # Kubernetes TUI
    "tealdeer"         # tldr pages (fast Rust implementation)
    "sd"               # Intuitive find & replace (sed alternative)
    "broot"            # Directory navigator for large codebases
    "yazi"             # Modern terminal file manager (async, fast)
    "cloudflared"      # Cloudflare tunnel for remote access
    "mosh"             # Mobile shell for resilient remote connections
    "shellcheck"       # Shell script linter (for make lint)
    "tmux"             # Alternative terminal multiplexer
    "procs"            # Better ps
    "dust"             # Better du (disk usage)
    "duf"              # Better df (disk free)
    "tokei"            # Code statistics
    "hyperfine"        # Command benchmarking
    "zsh-autosuggestions"
    "zsh-syntax-highlighting"
    "zsh-completions"
)

for tool in "${CLI_TOOLS[@]}"; do
    if brew list "$tool" &>/dev/null; then
        print_success "$tool already installed"
    else
        print_step "Installing $tool..."
        run_cmd brew install "$tool" || print_warning "Failed to install $tool"
    fi
done

# ============================================================================
# Install Window Manager
# ============================================================================

print_header "Step 3/7: Installing Window Manager"

# Rectangle - Free, simple, excellent
if app_installed "Rectangle"; then
    print_success "Rectangle already installed"
else
    print_step "Installing Rectangle..."
    run_cmd brew install --cask rectangle || print_warning "Failed to install Rectangle"
    print_success "Rectangle installed"
fi

# Stats - Menu bar system monitor
if app_installed "Stats"; then
    print_success "Stats already installed"
else
    print_step "Installing Stats..."
    run_cmd brew install --cask stats || print_warning "Failed to install Stats"
fi

# Maccy - Clipboard manager
if app_installed "Maccy"; then
    print_success "Maccy already installed"
else
    print_step "Installing Maccy..."
    run_cmd brew install --cask maccy || print_warning "Failed to install Maccy"
fi

# Hidden Bar - Hide menu bar icons
if app_installed "Hidden Bar"; then
    print_success "Hidden Bar already installed"
else
    print_step "Installing Hidden Bar..."
    run_cmd brew install --cask hiddenbar || print_warning "Failed to install Hidden Bar"
fi

# Hammerspoon - macOS automation
if app_installed "Hammerspoon"; then
    print_success "Hammerspoon already installed"
else
    print_step "Installing Hammerspoon..."
    run_cmd brew install --cask hammerspoon || print_warning "Failed to install Hammerspoon"
fi

# Tailscale - Mesh VPN for secure remote access
if app_installed "Tailscale"; then
    print_success "Tailscale already installed"
else
    print_step "Installing Tailscale..."
    run_cmd brew install --cask tailscale || print_warning "Failed to install Tailscale"
fi

# ============================================================================
# Backup Existing Configs
# ============================================================================

print_header "Step 4/7: Backing Up Existing Configurations"

BACKUP_DIR="$HOME/.config-backup-$(date +%Y%m%d_%H%M%S)"

backup_if_exists() {
    if [[ -f "$1" ]] || [[ -d "$1" ]]; then
        mkdir -p "$BACKUP_DIR"
        cp -r "$1" "$BACKUP_DIR/"
        print_warning "Backed up $(basename "$1")"
    fi
}

backup_if_exists "$HOME/.zshrc"
backup_if_exists "$HOME/.config/starship.toml"
backup_if_exists "$HOME/.config/zellij"
backup_if_exists "$HOME/.config/ghostty"
backup_if_exists "$HOME/.config/nvim"
backup_if_exists "$HOME/.hammerspoon"

if [[ -d "$BACKUP_DIR" ]]; then
    print_success "Backups saved to: $BACKUP_DIR"
else
    print_success "No existing configs to backup"
fi

# ============================================================================
# Create Configuration Files
# ============================================================================

print_header "Step 5/7: Creating Configuration Files"

mkdir -p "$HOME/.config/zellij/layouts"
mkdir -p "$HOME/.config/ghostty"

# --- ZSH Configuration ---
print_step "Creating shell configuration..."

if [[ -f "$SCRIPT_DIR/configs/zsh/.zshrc" ]]; then
    run_cmd cp "$SCRIPT_DIR/configs/zsh/.zshrc" "$HOME/.zshrc"
else
cat > "$HOME/.zshrc" << 'ZSHRC_EOF'
# ============================================================================
# Modern ZSH Configuration
# Generated by macos-dev-setup
# ============================================================================

export EDITOR='nvim'
export VISUAL='nvim'

# Homebrew
if [[ -f "/opt/homebrew/bin/brew" ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -f "/usr/local/bin/brew" ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
fi

export PATH="$HOME/.local/bin:$PATH"

# Optional: Uncomment and customize these paths if you use these tools
# Ruby (if installed)
# [[ -d "/opt/homebrew/opt/ruby" ]] && export PATH="/opt/homebrew/opt/ruby/bin:/opt/homebrew/lib/ruby/gems/3.0.0/bin:$PATH"
# [[ -d "/opt/homebrew/opt/ruby" ]] && export LDFLAGS="-L/opt/homebrew/opt/ruby/lib"
# [[ -d "/opt/homebrew/opt/ruby" ]] && export CPPFLAGS="-I/opt/homebrew/opt/ruby/include"

# Java (jenv) - if installed
# [[ -d "$HOME/.jenv" ]] && export PATH="$HOME/.jenv/bin:$PATH"
# command -v jenv &>/dev/null && eval "$(jenv init -)"

# Python (pyenv) - if installed
# [[ -d "$HOME/.pyenv" ]] && export PATH="${HOME}/.pyenv/shims:${PATH}"

# Node.js (nvm) - if installed
# export NVM_DIR="$HOME/.nvm"
# [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
# [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

# Yarn - if installed
# [[ -d "$HOME/.yarn" ]] && export PATH="$HOME/.yarn/bin:$HOME/.config/yarn/global/node_modules/.bin:$PATH"

# RVM (Ruby Version Manager) - if installed
# [[ -d "$HOME/.rvm/bin" ]] && export PATH="$PATH:$HOME/.rvm/bin"

# Local binaries
[[ -d "$HOME/.local/bin" ]] && export PATH="$PATH:$HOME/.local/bin"

# opencode AI CLI
[[ -d "$HOME/.opencode/bin" ]] && export PATH="$HOME/.opencode/bin:$PATH"

# Android SDK - if installed
# [[ -d "$HOME/Library/Android/sdk" ]] && export ANDROID_HOME="$HOME/Library/Android/sdk"
# [[ -n "$ANDROID_HOME" ]] && export PATH="$PATH:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$ANDROID_HOME/tools:$ANDROID_HOME/tools/bin"

# Completions
if type brew &>/dev/null; then
    FPATH="$(brew --prefix)/share/zsh-completions:$FPATH"
    FPATH="$(brew --prefix)/share/zsh/site-functions:$FPATH"
    autoload -Uz compinit

    # Initialize completions (use -i to ignore insecure directories)
    compinit -i
fi

# Starship Prompt
command -v starship &>/dev/null && eval "$(starship init zsh)"

# fzf
if command -v fzf &>/dev/null; then
    eval "$(fzf --zsh)" 2>/dev/null
    command -v rg &>/dev/null && export FZF_DEFAULT_COMMAND='rg --files --hidden --follow --glob "!.git/*"'
    export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
    command -v fd &>/dev/null && export FZF_ALT_C_COMMAND="fd --type d --hidden --follow --exclude .git"
    export FZF_DEFAULT_OPTS='--height 50% --layout=reverse --border --preview "bat --style=numbers --color=always --line-range :500 {} 2>/dev/null || cat {}"'
fi

# zoxide
command -v zoxide &>/dev/null && eval "$(zoxide init zsh)"

# atuin
command -v atuin &>/dev/null && eval "$(atuin init zsh)"

# gh
command -v gh &>/dev/null && eval "$(gh completion -s zsh)"

# Plugins
[[ -f "$(brew --prefix)/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]] && source "$(brew --prefix)/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
[[ -f "$(brew --prefix)/share/zsh-autosuggestions/zsh-autosuggestions.zsh" ]] && source "$(brew --prefix)/share/zsh-autosuggestions/zsh-autosuggestions.zsh"
ZSH_AUTOSUGGEST_STRATEGY=(history completion)

# Aliases
alias vim='nvim' vi='nvim' v='nvim'
command -v bat &>/dev/null && alias cat='bat'
command -v eza &>/dev/null && alias ls='eza --icons' ll='eza -l --icons --git' la='eza -la --icons --git' lt='eza --tree --level=2 --icons' tree='eza --tree --icons'
alias lg='lazygit' gs='git status' ga='git add' gc='git commit' gp='git push' gl='git pull' gd='git diff'
alias ..='cd ..' ...='cd ../..' ....='cd ../../..'
command -v zoxide &>/dev/null && alias cd='z'
command -v btm &>/dev/null && alias top='btm'
alias reload='source ~/.zshrc' zshconfig='${EDITOR:-nvim} ~/.zshrc'

# Functions
fcd() { local dir; dir=$(fd --type d --hidden --follow --exclude .git | fzf +m) && cd "$dir"; }
mkcd() { mkdir -p "$1" && cd "$1"; }

# History
HISTSIZE=50000 SAVEHIST=50000 HISTFILE=~/.zsh_history
setopt EXTENDED_HISTORY HIST_EXPIRE_DUPS_FIRST HIST_IGNORE_DUPS HIST_IGNORE_SPACE HIST_VERIFY SHARE_HISTORY

# Options
setopt AUTO_CD AUTO_PUSHD PUSHD_IGNORE_DUPS PUSHD_SILENT CORRECT INTERACTIVE_COMMENTS

# Key bindings
bindkey '^[[A' history-search-backward
bindkey '^[[B' history-search-forward

# Local customizations
[[ -f ~/.zshrc.local ]] && source ~/.zshrc.local
ZSHRC_EOF
fi
print_success "Shell configuration created"

# --- Starship Configuration ---
print_step "Creating prompt configuration..."

if [[ -f "$SCRIPT_DIR/configs/starship/starship.toml" ]]; then
    run_cmd cp "$SCRIPT_DIR/configs/starship/starship.toml" "$HOME/.config/starship.toml"
else
cat > "$HOME/.config/starship.toml" << 'STARSHIP_EOF'
format = "$directory$git_branch$git_status$python$nodejs$rust$golang$docker_context$cmd_duration$character"

[character]
success_symbol = "[❯](bold green)"
error_symbol = "[❯](bold red)"

[directory]
truncation_length = 3
truncate_to_repo = true
style = "bold cyan"

[git_branch]
symbol = " "
format = "on [$symbol$branch]($style) "
style = "bold purple"

[git_status]
format = '([\[$all_status$ahead_behind\]]($style) )'
style = "bold red"

[python]
symbol = " "

[nodejs]
symbol = " "

[rust]
symbol = " "

[golang]
symbol = " "

[docker_context]
symbol = " "

[cmd_duration]
min_time = 500
format = "took [$duration]($style) "
STARSHIP_EOF
fi
print_success "Prompt configuration created"

# --- Zellij Configuration ---
print_step "Creating terminal multiplexer configuration..."

if [[ -f "$SCRIPT_DIR/configs/zellij/config.kdl" ]]; then
    run_cmd cp "$SCRIPT_DIR/configs/zellij/config.kdl" "$HOME/.config/zellij/config.kdl"
else
cat > "$HOME/.config/zellij/config.kdl" << 'ZELLIJ_EOF'
theme "default"
default_shell "zsh"
copy_command "pbcopy"
copy_on_select true
scrollback_editor "nvim"
mouse_mode true
pane_frames true
auto_layout true
session_serialization true

keybinds {
    normal { unbind "Ctrl q" }
    locked {
        bind "Ctrl g" { SwitchToMode "Normal"; }
    }
    pane {
        bind "Alt p" { SwitchToMode "Normal"; }
        bind "h" "Left" { MoveFocus "Left"; }
        bind "l" "Right" { MoveFocus "Right"; }
        bind "j" "Down" { MoveFocus "Down"; }
        bind "k" "Up" { MoveFocus "Up"; }
        bind "n" { NewPane; SwitchToMode "Normal"; }
        bind "d" { NewPane "Down"; SwitchToMode "Normal"; }
        bind "r" { NewPane "Right"; SwitchToMode "Normal"; }
        bind "x" { CloseFocus; SwitchToMode "Normal"; }
    }
    shared_except "locked" {
        bind "Ctrl g" { SwitchToMode "Locked"; }
        bind "Ctrl q" { Quit; }
        bind "Alt n" { NewPane; }
        bind "Alt h" "Alt Left" { MoveFocusOrTab "Left"; }
        bind "Alt l" "Alt Right" { MoveFocusOrTab "Right"; }
        bind "Alt j" "Alt Down" { MoveFocus "Down"; }
        bind "Alt k" "Alt Up" { MoveFocus "Up"; }
        bind "Alt =" { Resize "Increase"; }
        bind "Alt -" { Resize "Decrease"; }
    }
}

ui { pane_frames { rounded_corners true } }
ZELLIJ_EOF
fi

# --- Zellij Layouts ---
if [[ -d "$SCRIPT_DIR/configs/zellij/layouts" ]]; then
    run_cmd cp "$SCRIPT_DIR/configs/zellij/layouts/"*.kdl "$HOME/.config/zellij/layouts/"
else
cat > "$HOME/.config/zellij/layouts/dev.kdl" << 'LAYOUT_EOF'
layout {
    default_tab_template {
        pane size=1 borderless=true { plugin location="zellij:tab-bar" }
        children
        pane size=2 borderless=true { plugin location="zellij:status-bar" }
    }
    tab name="Code" {
        pane split_direction="vertical" {
            pane size="65%" { name "Editor"; command "nvim" }
            pane size="35%" { name "Terminal" }
        }
    }
    tab name="Git" { pane { name "Git"; command "lazygit" } }
    tab name="Monitor" { pane { name "System"; command "btm" } }
}
LAYOUT_EOF

cat > "$HOME/.config/zellij/layouts/multi-agent.kdl" << 'LAYOUT_EOF'
layout {
    default_tab_template {
        pane size=1 borderless=true { plugin location="zellij:tab-bar" }
        children
        pane size=2 borderless=true { plugin location="zellij:status-bar" }
    }
    tab name="Development" {
        pane split_direction="vertical" {
            pane size="60%" { name "Editor"; command "nvim" }
            pane split_direction="horizontal" size="40%" {
                pane size="50%" { name "Agent-1" }
                pane size="50%" { name "Agent-2" }
            }
        }
    }
    tab name="Monitor" {
        pane split_direction="vertical" {
            pane size="50%" { name "System"; command "btm" }
            pane size="50%" { name "Logs" }
        }
    }
    tab name="Git" { pane { name "Git"; command "lazygit" } }
}
LAYOUT_EOF

cat > "$HOME/.config/zellij/layouts/fullstack.kdl" << 'LAYOUT_EOF'
layout {
    default_tab_template {
        pane size=1 borderless=true { plugin location="zellij:tab-bar" }
        children
        pane size=2 borderless=true { plugin location="zellij:status-bar" }
    }
    tab name="Editor" { pane { name "Editor"; command "nvim" } }
    tab name="Servers" {
        pane split_direction="horizontal" {
            pane size="50%" { name "Frontend" }
            pane size="50%" { name "Backend" }
        }
    }
    tab name="Database" { pane { name "Database" } }
    tab name="Git" { pane { name "Git"; command "lazygit" } }
}
LAYOUT_EOF
fi
print_success "Terminal multiplexer configuration created"

# --- Ghostty Configuration (if installed) ---
if [[ -d "/Applications/Ghostty.app" ]] || command_exists ghostty; then
    print_step "Creating terminal emulator configuration..."
    if [[ -f "$SCRIPT_DIR/configs/ghostty/config" ]]; then
        run_cmd cp "$SCRIPT_DIR/configs/ghostty/config" "$HOME/.config/ghostty/config"
    else
cat > "$HOME/.config/ghostty/config" << 'GHOSTTY_EOF'
term = ghostty
font-family = "JetBrains Mono"
font-size = 14

background = 1a1b26
foreground = c0caf5
cursor-color = c0caf5
cursor-style = block

palette = 0=#15161e
palette = 1=#f7768e
palette = 2=#9ece6a
palette = 3=#e0af68
palette = 4=#7aa2f7
palette = 5=#bb9af7
palette = 6=#7dcfff
palette = 7=#a9b1d6
palette = 8=#414868
palette = 9=#f7768e
palette = 10=#9ece6a
palette = 11=#e0af68
palette = 12=#7aa2f7
palette = 13=#bb9af7
palette = 14=#7dcfff
palette = 15=#c0caf5

window-padding-x = 8
window-padding-y = 8
window-theme = dark
shell-integration = detect

# Navigation keys (fn+arrows for Home/End/PageUp/PageDown)
keybind = fn+left=text:\x1b[1~
keybind = fn+right=text:\x1b[4~
keybind = fn+up=text:\x1b[5~
keybind = fn+down=text:\x1b[6~

# Home/End keys
keybind = home=text:\x1b[1~
keybind = end=text:\x1b[4~

# Ctrl+p pass-through (for Zellij)
keybind = ctrl+p=text:\x10

macos-option-as-alt = true
macos-titlebar-style = tabs
GHOSTTY_EOF
    fi
    print_success "Ghostty configuration created"
fi

# --- Hammerspoon Configuration (if installed) ---
if app_installed "Hammerspoon"; then
    print_step "Creating Hammerspoon automation configuration..."
    if [[ -f "$SCRIPT_DIR/configs/hammerspoon/init.lua" ]]; then
        run_cmd mkdir -p "$HOME/.hammerspoon"
        run_cmd cp "$SCRIPT_DIR/configs/hammerspoon/init.lua" "$HOME/.hammerspoon/init.lua"
    else
        print_warning "Hammerspoon config not found"
    fi
    print_success "Hammerspoon configuration created"
fi

# --- Neovim Configuration (LazyVim) ---
if command_exists nvim; then
    print_step "Setting up Neovim with LazyVim..."

    # Backup existing nvim config
    if [[ -d "$HOME/.config/nvim" ]]; then
        backup_if_exists "$HOME/.config/nvim"
        rm -rf "$HOME/.config/nvim"
    fi

    # Clean up old nvim data (recommended for fresh LazyVim install)
    rm -rf "$HOME/.local/share/nvim"
    rm -rf "$HOME/.local/state/nvim"
    rm -rf "$HOME/.cache/nvim"

    # Copy LazyVim config
    if [[ -d "$SCRIPT_DIR/configs/nvim" ]]; then
        mkdir -p "$HOME/.config/nvim"
        run_cmd cp -r "$SCRIPT_DIR/configs/nvim/"* "$HOME/.config/nvim/"
        print_success "LazyVim configuration installed"
        print_step "LazyVim will auto-install plugins on first launch"
    else
        print_warning "Neovim config directory not found in configs/nvim"
    fi
fi

# --- Copy AI Workflow Script ---
if [[ -f "$SCRIPT_DIR/scripts/ai-workflow.sh" ]]; then
    run_cmd cp "$SCRIPT_DIR/scripts/ai-workflow.sh" "$HOME/.local/bin/ai-workflow.sh"
    run_cmd chmod +x "$HOME/.local/bin/ai-workflow.sh"
    print_success "AI workflow script installed"
fi

# --- Copy Notification Script ---
if [[ -f "$SCRIPT_DIR/scripts/notify.sh" ]]; then
    mkdir -p "$HOME/.local/bin"
    run_cmd cp "$SCRIPT_DIR/scripts/notify.sh" "$HOME/.local/bin/notify.sh"
    run_cmd chmod +x "$HOME/.local/bin/notify.sh"
    print_success "Notification script installed"
fi

# ============================================================================
# AI CLI Tool Configurations
# ============================================================================

print_header "Step 5b/7: Configuring AI CLI Tools"

# --- Create directories ---
mkdir -p "$HOME/.config/opencode"
mkdir -p "$HOME/.gemini"
mkdir -p "$HOME/.local/share/opencode"
mkdir -p "$HOME/.local/share/claude"
mkdir -p "$HOME/.local/share/gemini"
mkdir -p "$HOME/.local/share/mcp"

# --- OpenCode Configuration ---
if [[ -f "$SCRIPT_DIR/configs/opencode/opencode.json" ]]; then
    print_step "Installing OpenCode configuration..."
    run_cmd cp "$SCRIPT_DIR/configs/opencode/opencode.json" "$HOME/.config/opencode/opencode.json"
    print_success "OpenCode configuration installed"
else
    print_warning "OpenCode config not found in configs/opencode/"
fi

# --- Claude Code Configuration ---
if [[ -f "$SCRIPT_DIR/configs/claude/settings.json" ]]; then
    print_step "Installing Claude Code configuration..."
    # Only copy if no existing config (preserve user customizations)
    if [[ ! -f "$HOME/.claude.json" ]]; then
        run_cmd cp "$SCRIPT_DIR/configs/claude/settings.json" "$HOME/.claude.json"
        print_success "Claude Code configuration installed"
    else
        print_warning "Existing ~/.claude.json found - skipping (backup if needed)"
    fi
else
    print_warning "Claude Code config not found in configs/claude/"
fi

# --- Gemini CLI Configuration ---
if [[ -f "$SCRIPT_DIR/configs/gemini/settings.json" ]]; then
    print_step "Installing Gemini CLI configuration..."
    run_cmd cp "$SCRIPT_DIR/configs/gemini/settings.json" "$HOME/.gemini/settings.json"
    print_success "Gemini CLI configuration installed"
else
    print_warning "Gemini CLI config not found in configs/gemini/"
fi

# --- MCP Environment Template ---
if [[ -f "$SCRIPT_DIR/configs/mcp/env.template" ]]; then
    print_step "Installing MCP environment template..."
    run_cmd cp "$SCRIPT_DIR/configs/mcp/env.template" "$HOME/.config/mcp-env.template"
    print_success "MCP environment template installed to ~/.config/mcp-env.template"
    print_warning "Edit and source this file to enable MCP servers requiring API keys"
fi

# --- SSH Client Configuration ---
if [[ -f "$SCRIPT_DIR/configs/ssh/config" ]]; then
    print_step "Installing SSH client configuration..."
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    if [[ ! -f "$HOME/.ssh/config" ]]; then
        run_cmd cp "$SCRIPT_DIR/configs/ssh/config" "$HOME/.ssh/config"
        run_cmd chmod 600 "$HOME/.ssh/config"
        print_success "SSH client config installed"
    else
        print_warning "Existing ~/.ssh/config found - skipping (see configs/ssh/config for reference)"
    fi
fi

# --- Ralph Wiggum Orchestration ---
if [[ -f "$SCRIPT_DIR/scripts/ralph.sh" ]]; then
    print_step "Installing Ralph Wiggum orchestration script..."
    run_cmd cp "$SCRIPT_DIR/scripts/ralph.sh" "$HOME/.local/bin/ralph"
    run_cmd chmod +x "$HOME/.local/bin/ralph"
    print_success "Ralph orchestration installed (run 'ralph --help' for usage)"
fi

# ============================================================================
# Configure Git
# ============================================================================

print_header "Step 6/7: Configuring Git"

if command_exists delta; then
    run_cmd git config --global core.pager "delta"
    run_cmd git config --global interactive.diffFilter "delta --color-only"
    run_cmd git config --global delta.navigate "true"
    run_cmd git config --global delta.light "false"
    run_cmd git config --global delta.line-numbers "true"
    run_cmd git config --global delta.side-by-side "true"
    run_cmd git config --global merge.conflictstyle "diff3"
    run_cmd git config --global diff.colorMoved "default"
    print_success "Git configured with delta for beautiful diffs"
fi

# ============================================================================
# Final Setup
# ============================================================================

print_header "Step 7/7: Final Setup"

if [[ "$SHELL" != *"zsh"* ]]; then
    print_step "Setting zsh as default shell..."
    run_cmd chsh -s "$(which zsh)" || print_warning "Could not change default shell"
fi

# ============================================================================
# Summary
# ============================================================================

print_header "Installation Complete!"

cat << EOF
${GREEN}Your macOS development environment is ready!${NC}

${CYAN}TERMINAL TOOLS${NC}
  zellij       - Terminal multiplexer    ${YELLOW}zellij --layout dev${NC}
  fzf          - Fuzzy finder             ${YELLOW}Ctrl+T${NC} files, ${YELLOW}Ctrl+R${NC} history
  nnn          - TUI file manager        ${YELLOW}nnn${NC}
  lazygit      - Git interface            ${YELLOW}lg${NC}
  lazydocker   - Docker TUI               ${YELLOW}ld${NC}
  ncdu         - Disk usage               ${YELLOW}ncdu${NC}
  bandwhich    - Network monitor          ${YELLOW}sudo bandwhich${NC}
  fastfetch    - System info              ${YELLOW}fastfetch${NC}
  bat          - Better cat               ${YELLOW}cat file.txt${NC}
  eza          - Better ls                ${YELLOW}ls${NC}, ${YELLOW}ll${NC}, ${YELLOW}la${NC}
  glow         - Markdown viewer           ${YELLOW}glow README.md${NC}
  nvim         - Modern editor             ${YELLOW}nvim file.py${NC}

${CYAN}WINDOW MANAGEMENT${NC}
  Rectangle    - Window snapping          Open from Applications
  Hammerspoon  - macOS automation          ~/.hammerspoon/init.lua

${CYAN}PRODUCTIVITY APPS (Open Source)${NC}
  Stats        - System monitor           Menu bar
  Maccy        - Clipboard history        ${YELLOW}⌘ + Shift + C${NC} (default)
  Hidden Bar   - Hide menu bar icons      Menu bar

${CYAN}QUICK START${NC}
  1. Restart terminal or run: ${YELLOW}source ~/.zshrc${NC}
  2. Try zellij: ${YELLOW}zellij --layout dev${NC}
  3. Open Rectangle, Stats, Maccy, Hammerspoon from Applications
  4. Grant accessibility permissions when prompted
  5. Learn Neovim: ${YELLOW}nvim +Tutor${NC} or see docs/NEOVIM_QUICKSTART.md

${CYAN}ZELLIJ KEYBINDINGS${NC}
  Alt+n       New pane
  Alt+h/j/k/l Navigate panes
  Ctrl+p      Pane mode
  Ctrl+t      Tab mode
  Ctrl+q      Quit

${CYAN}REMOTE ACCESS${NC}
  tailscale    - Mesh VPN for secure access  Open from Applications
  mosh         - Resilient mobile shell       ${YELLOW}mosh user@100.x.x.x${NC}
  notify.sh    - macOS notifications          ${YELLOW}notify.sh "Title" "Message"${NC}

${CYAN}NEW ELITE TOOLS${NC}
  nnn         - Fastest TUI file manager, vim-like
  lazydocker  - Beautiful Docker management
  ncdu        - Interactive disk cleanup
  bandwhich   - Which process is using bandwidth?
  fastfetch   - System info at your fingertips
  k9s         - Kubernetes clusters in style
  hammerspoon - Automate everything on macOS

EOF

if [[ -d "$BACKUP_DIR" ]]; then
    echo -e "${YELLOW}Backups saved to: $BACKUP_DIR${NC}"
    echo ""
fi

echo -e "${GREEN}Happy coding! 🚀${NC}"
