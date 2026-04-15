# ============================================================================
# Modern ZSH Configuration for AI-Powered Development
# Optimized for multi-agent workflows and TUI productivity
# Created: 2026-01-05
# ============================================================================

# tuidev env: written by install.sh, exports TUIDEV_REPO and TUIDEV_PROFILE.
# Kept at the top so every downstream block (session wrappers, sandbox
# integration, update helpers) can rely on these.
[[ -f "$HOME/.config/tuidev/env" ]] && . "$HOME/.config/tuidev/env"

# ============================================================================
# Environment Variables
# ============================================================================

export EDITOR='nvim'
export VISUAL='nvim'
export REACT_EDITOR=idea

# ============================================================================
# PATH Configuration
# ============================================================================

# Homebrew (supports both Apple Silicon and Intel Macs)
if [[ -f "/opt/homebrew/bin/brew" ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -f "/usr/local/bin/brew" ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
fi

# Ruby (if installed)
[[ -d "/opt/homebrew/opt/ruby" ]] && export PATH="/opt/homebrew/opt/ruby/bin:/opt/homebrew/lib/ruby/gems/3.0.0/bin:$PATH"
[[ -d "/opt/homebrew/opt/ruby" ]] && export LDFLAGS="-L/opt/homebrew/opt/ruby/lib"
[[ -d "/opt/homebrew/opt/ruby" ]] && export CPPFLAGS="-I/opt/homebrew/opt/ruby/include"

# Java (jenv) - if installed
[[ -d "$HOME/.jenv" ]] && export PATH="$HOME/.jenv/bin:$PATH"
command -v jenv &>/dev/null && eval "$(jenv init -)"

# Python (pyenv) - if installed
[[ -d "$HOME/.pyenv" ]] && export PATH="${HOME}/.pyenv/shims:${PATH}"

# Node.js (nvm) - if installed (lazy loaded at bottom for fast shell startup)
export NVM_DIR="$HOME/.nvm"

# Yarn - if installed
[[ -d "$HOME/.yarn" ]] && export PATH="$HOME/.yarn/bin:$HOME/.config/yarn/global/node_modules/.bin:$PATH"

# RVM (Ruby Version Manager) - if installed
[[ -d "$HOME/.rvm/bin" ]] && export PATH="$PATH:$HOME/.rvm/bin"

# Local binaries
[[ -d "$HOME/.local/bin" ]] && export PATH="$PATH:$HOME/.local/bin"

# opencode AI CLI
[[ -d "$HOME/.opencode/bin" ]] && export PATH="$HOME/.opencode/bin:$PATH"

# Android SDK - if installed
[[ -d "$HOME/Library/Android/sdk" ]] && export ANDROID_HOME="$HOME/Library/Android/sdk"
[[ -n "$ANDROID_HOME" ]] && export PATH="$PATH:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$ANDROID_HOME/tools:$ANDROID_HOME/tools/bin"

# Custom tool paths (add your own here)
# Example: [[ -d "$HOME/.antigravity/antigravity/bin" ]] && export PATH="$HOME/.antigravity/antigravity/bin:$PATH"

# ============================================================================
# Completions
if type brew &>/dev/null; then
  FPATH=$(brew --prefix)/share/zsh-completions:$FPATH
  FPATH=$(brew --prefix)/share/zsh/site-functions:$FPATH

  autoload -Uz compinit

  # Initialize completions (use -i to ignore insecure directories)
  compinit -i
fi

# ============================================================================
# Modern CLI Tools Integration
# ============================================================================

# Starship Prompt (replaces oh-my-zsh themes)
command -v starship &>/dev/null && eval "$(starship init zsh)"

# fzf - Fuzzy Finder
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh
eval "$(fzf --zsh)" 2>/dev/null

# Set fzf to use ripgrep for faster searches
export FZF_DEFAULT_COMMAND='rg --files --hidden --follow --glob "!.git/*"'
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
export FZF_ALT_C_COMMAND="fd --type d --hidden --follow --exclude .git"

# fzf color scheme (match terminal theme)
export FZF_DEFAULT_OPTS='
  --color=fg:#c0caf5,bg:#1a1b26,hl:#bb9af7
  --color=fg+:#c0caf5,bg+:#1a1b26,hl+:#7dcfff
  --color=info:#7aa2f7,prompt:#7dcfff,pointer:#7dcfff
  --color=marker:#9ece6a,spinner:#9ece6a,header:#9ece6a
  --height 50% --layout=reverse --border
  --preview "bat --style=numbers --color=always --line-range :500 {}"
'

# zoxide - Smarter cd
eval "$(zoxide init zsh)"

# atuin - Better shell history
command -v atuin &>/dev/null && eval "$(atuin init zsh)"

# GitHub CLI completion
if command -v gh &> /dev/null; then
  eval "$(gh completion -s zsh)"
fi

# ============================================================================
# ZSH Plugins (Homebrew-installed)
# ============================================================================

# Syntax highlighting (must be near the end)
[[ -f "$(brew --prefix)/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]] && \
    source "$(brew --prefix)/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"

# Autosuggestions (must be at the end)
[[ -f "$(brew --prefix)/share/zsh-autosuggestions/zsh-autosuggestions.zsh" ]] && \
    source "$(brew --prefix)/share/zsh-autosuggestions/zsh-autosuggestions.zsh"

# Autosuggestion behavior
ZSH_AUTOSUGGEST_STRATEGY=(history completion)
ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=20

# ============================================================================
# Aliases - Modern TUI Tools
# ============================================================================

# Editor
alias vim='nvim'
alias vi='nvim'
alias v='nvim'

# Modern replacements
alias cat='bat'
alias ls='eza --icons'
alias ll='eza -l --icons --git'
alias la='eza -la --icons --git'
alias lt='eza --tree --level=2 --icons'
alias tree='eza --tree --icons'

# Git
alias lg='lazygit'
alias gs='git status'
alias ga='git add'
alias gc='git commit'
alias gp='git push'
alias gl='git pull'
alias gd='git diff'
alias gco='git checkout'
alias gb='git branch'

# Elite TUI Tools
alias ld='lazydocker'
alias sys='fastfetch'
alias k9s='k9s'

# File managers (nnn = classic, yazi = modern)
alias nnn='nnn'
command -v yazi &>/dev/null && alias y='yazi'
# Note: broot uses its own shell function 'br' (installed via `broot --install`)

# Disk tools
alias ncdu='ncdu'

# tldr pages
command -v tldr &>/dev/null && alias help='tldr'

# sed replacement (intuitive syntax)
command -v sd &>/dev/null && alias sed='sd'

# Navigation
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
[[ -o interactive ]] && alias cd='z'  # Use zoxide (only in interactive shells)

# System
alias top='btm'     # bottom system monitor
alias bottom='btm'  # explicit bottom command
command -v procs &>/dev/null && alias ps='procs'
command -v dust &>/dev/null && alias du='dust'
command -v duf &>/dev/null && alias df='duf'

# Markdown viewer
command -v glow &>/dev/null && alias md='glow'

# Development
alias http='http --pretty=all --style=monokai'
alias serve='python3 -m http.server'

# Utility
alias reload='source ~/.zshrc'
alias zshconfig='nvim ~/.zshrc'
alias cleanup='brew cleanup && brew autoremove'

# Code stats
command -v tokei &>/dev/null && alias loc='tokei'

# ============================================================================
# AI CLI Tool Wrappers
# ============================================================================
# Invocations auto-route through the Seatbelt sandbox (sbx) when both are
# installed. Escape hatches:
#   CC_NO_SANDBOX=1 cc ...          one-shot, per invocation
#   sbx --profile off -- claude     explicit, documented profile bypass
#   unalias cc                      nuclear option
#
# Claude Code and Codex also ship their own native sandboxing; sbx is a
# uniform-UX layer on top. See docs/sandboxing.md.

_tuidev_run_ai() {
  # Dispatch CLI through sbx unless the escape hatch is active.
  local cli="$1"; shift
  if [[ -n "${CC_NO_SANDBOX:-}" ]] || ! command -v sbx >/dev/null 2>&1; then
    command "$cli" "$@"
  else
    command sbx -- "$cli" "$@"
  fi
}

command -v claude   >/dev/null 2>&1 && cc()  { _tuidev_run_ai claude   "$@"; }
command -v codex    >/dev/null 2>&1 && cx()  { _tuidev_run_ai codex    "$@"; }
command -v gemini   >/dev/null 2>&1 && gem() { _tuidev_run_ai gemini   "$@"; }
command -v opencode >/dev/null 2>&1 && oc()  { _tuidev_run_ai opencode "$@"; }

# ============================================================================
# Functions
# ============================================================================

# Quick directory navigation with fzf
fcd() {
  local dir
  dir=$(fd --type d --hidden --follow --exclude .git | fzf +m) && cd "$dir"
}

# nnn with cd on quit
n() {
  if [[ -n $NNNPIPE ]]; then
    echo "nnn is already running!"
    return
  fi

  export NNN_FIFO=/tmp/nnn-fifo-$$
  mkfifo "$NNN_FIFO"
  nnn -P n </dev/tty > "$NNN_FIFO" &

  while read -r selection; do
    if [[ -n "$selection" ]]; then
      cd "$selection"
    fi
  done < "$NNN_FIFO"

  rm -f "$NNN_FIFO"
  unset NNN_FIFO
}

# Search in files with fzf + ripgrep
fif() {
  if [ ! "$#" -gt 0 ]; then echo "Need a string to search for!"; return 1; fi
  rg --files-with-matches --no-messages "$1" | fzf --preview "bat --color=always {} 2> /dev/null | rg --colors 'match:bg:yellow' --ignore-case --pretty --context 10 '$1' || rg --ignore-case --pretty --context 10 '$1' {}"
}

# Create directory and cd into it
mkcd() {
  mkdir -p "$1" && cd "$1"
}

# Git commit browser with fzf
fshow() {
  git log --graph --color=always \
      --format="%C(auto)%h%d %s %C(black)%C(bold)%cr" "$@" |
  fzf --ansi --no-sort --reverse --tiebreak=index --bind=ctrl-s:toggle-sort \
      --bind "ctrl-m:execute:
                (grep -o '[a-f0-9]\{7\}' | head -1 |
                xargs -I % sh -c 'git show --color=always % | less -R') << 'FZF-EOF'
                {}
FZF-EOF"
}

# Preview markdown files (uses glow or bat)
mdp() {
  if command -v glow &>/dev/null; then
    glow -p "$1"
  elif command -v bat &>/dev/null; then
    bat --language=markdown "$1"
  else
    cat "$1"
  fi
}

# Open markdown in nvim with preview
mde() {
  nvim "$1"
}

# Quick project stats
pstats() {
  echo "📊 Project Statistics"
  echo "===================="
  if command -v tokei &>/dev/null; then
    tokei .
  else
    find . -type f -name "*.py" -o -name "*.js" -o -name "*.ts" -o -name "*.java" -o -name "*.scala" | wc -l | xargs -I {} echo "Source files: {}"
  fi
  echo ""
  echo "📁 Directory size:"
  if command -v dust &>/dev/null; then
    dust -d 1
  else
    du -sh . 2>/dev/null
  fi
}

# Quick benchmark command
bench() {
  if command -v hyperfine &>/dev/null; then
    hyperfine "$@"
  else
    time "$@"
  fi
}

# Start tunnel for remote access
tunnel() {
  local port=${1:-22}

  # Show Tailscale info if available
  if command -v tailscale &>/dev/null; then
    local ts_ip
    ts_ip=$(tailscale ip -4 2>/dev/null)
    if [[ -n "$ts_ip" ]]; then
      echo "Tailscale IP: $ts_ip (direct access via: ssh $(whoami)@$ts_ip)"
      echo "For mobile: use mosh $(whoami)@$ts_ip"
      echo ""
      echo "If Tailscale access is sufficient, no tunnel needed."
      echo "Starting public tunnel anyway..."
      echo ""
    fi
  fi

  if command -v cloudflared &>/dev/null; then
    echo "Starting Cloudflare tunnel on port $port..."
    cloudflared tunnel --url tcp://localhost:$port
  elif command -v ngrok &>/dev/null; then
    echo "Starting ngrok tunnel on port $port..."
    ngrok tcp $port
  else
    echo "No tunnel tool found. Install cloudflared or ngrok."
    echo "Or use Tailscale for direct access (recommended)."
  fi
}

# ============================================================================
# Session Wrappers — tmux-first
# ============================================================================
# The default ergonomic commands (work/dev/ai/...) launch tmux via the
# reproducible layout helpers under $TUIDEV_REPO/scripts/tmux/. Zellij is
# opt-in: install `--pack zellij` to activate the z* variants below.
#
# Every wrapper accepts an optional session name; default is the layout's
# name or the current directory's basename. All are attach-or-create.

_tuidev_layout() {
  local name="$1"; shift
  local repo="${TUIDEV_REPO:-$HOME/.local/share/tuidev}"
  local script="$repo/scripts/tmux/layout-$name.sh"
  if [[ -x "$script" ]]; then
    "$script" "$@"
  else
    echo "layout '$name' not found at $script" >&2
    echo "set TUIDEV_REPO to the repo root or run: ./install.sh --profile minimal" >&2
    return 127
  fi
}

work()        { _tuidev_layout work "$@"; }
dev()         { _tuidev_layout dev "$@"; }
ai()          { _tuidev_layout ai "$@"; }
ai-single()   { _tuidev_layout ai-single "$@"; }
ai-triple()   { _tuidev_layout ai-triple "$@"; }
fullstack()   { _tuidev_layout fullstack "$@"; }
multi()       { _tuidev_layout multi "$@"; }
remote()      { _tuidev_layout remote "$@"; }
agents()      { _tuidev_layout agents "$@"; }

# One-time deprecation warning for old t* aliases. Writes a stamped file so
# the warning prints only once per machine per rename.
_tuidev_deprecated() {
  local flag_dir="$HOME/.config/tuidev"
  local flag_file="$flag_dir/deprecations"
  local key="$1"
  mkdir -p "$flag_dir" 2>/dev/null
  if ! grep -qFx "$key" "$flag_file" 2>/dev/null; then
    echo "tuidev: '$key' — the t* aliases are deprecated and will be removed in the next release." >&2
    echo "$key" >> "$flag_file"
  fi
}

ta()         { _tuidev_deprecated "ta → work"; work "$@"; }
tdev()       { _tuidev_deprecated "tdev → dev"; dev "$@"; }
tai()        { _tuidev_deprecated "tai → ai"; ai "$@"; }
tai-triple() { _tuidev_deprecated "tai-triple → ai-triple"; ai-triple "$@"; }

# Session management (tmux-native).
tls() { tmux list-sessions 2>/dev/null || echo "no tmux sessions"; }
tk()  {
  local name=${1:-$(basename "$PWD")}
  tmux kill-session -t "$name" 2>/dev/null && echo "killed: $name" || echo "no session: $name"
}
tka() { tmux kill-server 2>/dev/null && echo "killed all tmux sessions"; }

# ============================================================================
# Zellij wrappers (opt-in, activated when zellij is on PATH)
# ============================================================================
# Installed via `./install.sh --pack zellij`. Namespaced under z* to avoid
# colliding with the tmux-first defaults above.

if command -v zellij >/dev/null 2>&1; then
  zdev()       { zellij --session "${1:-zdev}"       --layout dev; }
  zwork()      { zellij --session "${1:-$(basename "$PWD")}"; }
  zai()        { zellij --session "${1:-zai}"        --layout dual; }
  zai-single() { zellij --session "${1:-zai-single}" --layout single; }
  zai-triple() { zellij --session "${1:-zai-triple}" --layout triple; }
  zfullstack() { zellij --session "${1:-zfullstack}" --layout fullstack; }
  zmulti()     { zellij --session "${1:-zmulti}"     --layout multi-agent; }
  zremote()    { zellij --session "${1:-zremote}"    --layout remote; }
  zk()         { zellij kill-all-sessions 2>/dev/null; }
fi

# ============================================================================
# Update helpers
# ============================================================================

tui-update() {
  local repo_dir="${TUIDEV_REPO:-$HOME/tuidev}"
  if [[ -d "$repo_dir" ]]; then
    "$repo_dir/scripts/update.sh" "$@"
  else
    echo "tuidev repo not found at $repo_dir"
    echo "set TUIDEV_REPO or re-run the installer from your checkout."
  fi
}

tui-check() { tui-update --check; }

# ============================================================================
# Remote Access Functions
# ============================================================================

# Show Tailscale connection status
ts-status() {
  if command -v tailscale &>/dev/null; then
    tailscale status
  else
    echo "Tailscale is not installed. Install with: brew install --cask tailscale"
  fi
}

# Show Tailscale IPv4 address
ts-ip() {
  if command -v tailscale &>/dev/null; then
    tailscale ip -4
  else
    echo "Tailscale is not installed. Install with: brew install --cask tailscale"
  fi
}

# Remote access dashboard - SSH, Tailscale, and Zellij status
remote-status() {
  echo "Remote Access Status"
  echo "===================="
  echo ""

  # SSH status
  echo "SSH Server:"
  if [[ "$(uname)" == "Darwin" ]]; then
    local ssh_status
    ssh_status=$(sudo systemsetup -getremotelogin 2>/dev/null || echo "unknown")
    echo "  $ssh_status"
  else
    if systemctl is-active sshd &>/dev/null; then
      echo "  SSH: running"
    else
      echo "  SSH: not running"
    fi
  fi
  echo ""

  # Tailscale status
  echo "Tailscale:"
  if command -v tailscale &>/dev/null; then
    local ts_ip
    ts_ip=$(tailscale ip -4 2>/dev/null)
    local ts_state
    ts_state=$(tailscale status --json 2>/dev/null | jq -r '.Self.Online // "unknown"' 2>/dev/null || echo "unknown")
    echo "  IP: ${ts_ip:-not connected}"
    echo "  Online: $ts_state"
  else
    echo "  Not installed"
  fi
  echo ""

  # tmux sessions (primary multiplexer)
  echo "tmux Sessions:"
  if command -v tmux &>/dev/null; then
    local sessions
    sessions=$(tmux list-sessions 2>/dev/null)
    if [[ -n "$sessions" ]]; then
      echo "$sessions" | sed 's/^/  /'
    else
      echo "  no active sessions"
    fi
  else
    echo "  tmux not installed"
  fi
  echo ""

  # Zellij sessions (opt-in via --pack zellij)
  if command -v zellij &>/dev/null; then
    echo "Zellij Sessions:"
    local zsessions
    zsessions=$(zellij list-sessions 2>/dev/null)
    if [[ -n "$zsessions" ]]; then
      echo "$zsessions" | sed 's/^/  /'
    else
      echo "  no active sessions"
    fi
  fi
}

# ============================================================================
# Tool-Specific Configuration
# ============================================================================

# Google Cloud SDK - if installed
if [ -f "$HOME/tools/google-cloud-sdk/path.zsh.inc" ]; then
  . "$HOME/tools/google-cloud-sdk/path.zsh.inc"
fi
if [ -f "$HOME/tools/google-cloud-sdk/completion.zsh.inc" ]; then
  . "$HOME/tools/google-cloud-sdk/completion.zsh.inc"
fi

# iTerm2 integration (if using iTerm)
test -e "${HOME}/.iterm2_shell_integration.zsh" && source "${HOME}/.iterm2_shell_integration.zsh"

# Ghostty SSH fix
if [[ -n "$GHOSTTY_RESOURCES_DIR" ]]; then
  alias ssh='TERM=xterm-256color ssh'
fi

# tabtab source for electron-forge - if exists (will use the actual path when available)
# This is generated dynamically, the path below is just an example
# [[ -f "$HOME/.npm/_npx/*/node_modules/tabtab/.completions/electron-forge.zsh" ]] && . "$HOME/.npm/_npx/*/node_modules/tabtab/.completions/electron-forge.zsh"

# ============================================================================
# History Configuration
# ============================================================================

HISTSIZE=50000
SAVEHIST=50000
HISTFILE=~/.zsh_history

setopt EXTENDED_HISTORY          # Write timestamp to history
setopt HIST_EXPIRE_DUPS_FIRST   # Expire duplicates first
setopt HIST_IGNORE_DUPS         # Don't record duplicates
setopt HIST_IGNORE_SPACE        # Don't record commands starting with space
setopt HIST_VERIFY              # Show command with history expansion before running
setopt SHARE_HISTORY            # Share history between sessions

# ============================================================================
# ZSH Options
# ============================================================================

setopt AUTO_CD                  # cd by typing directory name
setopt AUTO_PUSHD              # Make cd push old directory onto directory stack
setopt PUSHD_IGNORE_DUPS       # Don't push duplicates
setopt PUSHD_SILENT            # Don't print directory stack after pushd/popd
setopt CORRECT                 # Spelling correction
setopt INTERACTIVE_COMMENTS    # Allow comments in interactive shells

# ============================================================================
# Key Bindings
# ============================================================================

# Use vim key bindings (optional - comment out if you prefer emacs mode)
# bindkey -v

# Better history search
bindkey '^R' atuin-search
bindkey '^[[A' history-search-backward  # Up arrow
bindkey '^[[B' history-search-forward   # Down arrow

# ============================================================================
# Welcome Message
# ============================================================================

# Show system info on shell start (optional)
# echo "🚀 TUI Development Environment Ready"
# echo "  Terminal: Ghostty | Shell: zsh | Editor: nvim"
# echo "  Multiplexer: zellij | Tools: fzf, ripgrep, bat, eza"
# echo ""

# ============================================================================
# Performance Optimization
# ============================================================================

# Lazy load nvm (speeds up shell startup significantly)
if [ -s "$NVM_DIR/nvm.sh" ]; then
  # Setup nvm function to load nvm on first use
  nvm() {
    unfunction nvm
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    nvm "$@"
  }

  # Lazy load npm, node, npx
  for cmd in npm node npx; do
    eval "${cmd}() { unfunction ${cmd}; [ -s '$NVM_DIR/nvm.sh' ] && . '$NVM_DIR/nvm.sh'; ${cmd} \$@; }"
  done
fi

# ============================================================================
# End of Configuration
# ============================================================================

# Load local customizations (if any)
[ -f ~/.zshrc.local ] && source ~/.zshrc.local
