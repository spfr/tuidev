# tuidev's shipped zsh config, installed as the managed block `tuidev-zshrc`.
# Your own lines go outside the block or in ~/.zshrc.local, which is sourced last.

# tuidev env: written by install.sh, exports TUIDEV_REPO and TUIDEV_PROFILE.
# Kept at the top so every downstream block (update helpers, pack fragments)
# can rely on these.
_tuidev_state="${XDG_CONFIG_HOME:-$HOME/.config}/tuidev"
[[ -f "$_tuidev_state/env" ]] && . "$_tuidev_state/env"

# Open files: macOS starts every process with a soft limit of 256 and Linux
# with 1024. Node raises its own; file watchers, test runners and databases
# started from this shell may not, and fail with EMFILE once several agents
# run. Raised only when the current limit is a lower number (never lowered,
# never past the hard limit). Everything started from this shell inherits it.
() {
  local soft="$(ulimit -n)" hard="$(ulimit -Hn)" want=65536
  [[ $hard == <-> ]] && (( hard < want )) && want=$hard
  [[ $soft == <-> ]] && (( soft < want )) && ulimit -n $want 2>/dev/null
  return 0
}

# ============================================================================
# Environment Variables
# ============================================================================
# EDITOR/VISUAL are set once PATH is complete (see "Editor" below).

# _cache_init NAME CMD... — source the init script CMD prints, cached in
# $XDG_CACHE_HOME/zsh/init-NAME.zsh. CMD runs again only when its binary is
# replaced (new resolved path, e.g. a Homebrew upgrade) or rewritten in place
# (newer than the cache), or when the command line itself changes. Returns
# non-zero, sourcing nothing, if CMD is missing or fails. The script is written
# to a per-shell temp file and moved into place, so a shell starting in
# parallel never sources a half-written cache.
_cache_init() {
  local name=$1; shift
  local bin=${commands[$1]} cache line tmp
  [[ -n $bin ]] || return 1
  bin=${bin:A}
  cache=${XDG_CACHE_HOME:-$HOME/.cache}/zsh/init-$name.zsh
  [[ -r $cache ]] && read -r line < $cache
  if [[ $line != "# $bin $*" || $bin -nt $cache ]]; then
    mkdir -p -- ${cache:h}
    tmp=$cache.$$
    { { print -r -- "# $bin $*" && "$@" } >| $tmp 2>/dev/null && mv -f -- $tmp $cache } \
      || { rm -f -- $tmp; return 1; }
  fi
  source $cache
}

# ============================================================================
# PATH Configuration
# ============================================================================

# Homebrew (supports both Apple Silicon and Intel Macs)
if [[ -f "/opt/homebrew/bin/brew" ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -f "/usr/local/bin/brew" ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
fi
# Prefix for the fpath/plugin lookups below. Falls back to the brew on PATH
# (<prefix>/bin/brew) so no `brew --prefix` subprocess is ever spawned.
_tuidev_brew_prefix=${HOMEBREW_PREFIX:-}
[[ -z $_tuidev_brew_prefix && -n ${commands[brew]} ]] && _tuidev_brew_prefix=${commands[brew]:h:h}

# Rust (cargo) - if installed; exposes `cargo install`ed tools
[[ -d "$HOME/.cargo/bin" ]] && export PATH="$HOME/.cargo/bin:$PATH"

# Local binaries — tuidev's own install target: sbx, notify.sh, and on Debian
# the fd/bat shims core.sh creates for Debian's renamed binaries.
#
# Unconditional (no -d guard): the directory is often created later in the same
# install run, and a guard would leave PATH stale until the next shell. Prepend
# so our shims win over a same-named system binary. `typeset -U` keeps the
# entry unique, so re-sourcing this file never grows PATH.
typeset -U path PATH
path=("$HOME/.local/bin" $path)
export PATH

# Language toolchains and SDKs (Ruby, Java, Android, Google Cloud, ...) are
# not part of the agent terminal: set them up in ~/.zshrc.local, which is
# sourced last, so its PATH entries come before everything here.

# ============================================================================
# Completions
# ============================================================================
# Homebrew adds its completion dirs; Debian/Ubuntu already ship theirs in
# the default $fpath. compinit itself must run everywhere — the tool inits
# below (fzf, atuin, ...) call compdef and fail without it. Tools that ship
# a _cmd file in site-functions (gh, eza, atuin, ...) need no eval here.
typeset -U fpath
if [[ -n $_tuidev_brew_prefix ]]; then
  fpath=("$_tuidev_brew_prefix/share/zsh-completions" "$_tuidev_brew_prefix/share/zsh/site-functions" $fpath)
fi

# The dump lives in $XDG_CACHE_HOME. The full fpath scan plus security audit
# (-i: skip insecure dirs silently; `make fix-completions` repairs them) runs
# at most once a day; otherwise -C trusts the dump, saving ~100 ms per shell.
# Run `rm "${XDG_CACHE_HOME:-$HOME/.cache}"/zsh/zcompdump-*` after
# installing new completions to pick them up immediately.
autoload -Uz compinit
() {
  setopt local_options extended_glob
  local dump="${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zcompdump-${ZSH_VERSION}"
  if [[ -n $dump(#qN.mh-24) ]]; then
    compinit -C -d "$dump"
  else
    mkdir -p -- "${dump:h}"
    compinit -i -d "$dump" && touch -- "$dump"
  fi
}

zstyle ':completion:*' menu select                              # arrow-key menu
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' 'r:|[._-]=* r:|=*'  # case-insensitive, then partial words
zstyle ':completion:*' use-cache on
zstyle ':completion:*' cache-path "${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zcompcache"
zstyle ':completion:*' group-name ''                            # group matches by type
zstyle ':completion:*:descriptions' format '%F{blue}-- %d --%f'

# ============================================================================
# Modern CLI Tools Integration
# ============================================================================

# Emacs line editing, set explicitly and before any tool binds keys: zsh
# silently starts in vi mode whenever $EDITOR/$VISUAL contain "vi" (nvim or
# vim over SSH, or inherited from a parent shell or tmux). Put `bindkey -v` in
# ~/.zshrc.local for vi.
bindkey -e

# Starship Prompt (replaces oh-my-zsh themes)
_cache_init starship starship init zsh --print-full-init

# fzf - Fuzzy Finder
# `fzf --zsh` needs fzf >= 0.48 (Homebrew); Debian/Ubuntu ship older builds
# that reject the flag, so fall back to their example scripts.
# Key bindings need a terminal: without one (agent tool shells, `ssh host cmd`)
# fzf's option save/restore fails with "can't change option: zle".
if [[ ! -t 0 ]]; then
  :
elif [[ -f ~/.fzf.zsh ]]; then
  source ~/.fzf.zsh
elif (( $+commands[fzf] )) && ! _cache_init fzf fzf --zsh; then
  [[ -f /usr/share/doc/fzf/examples/key-bindings.zsh ]] && source /usr/share/doc/fzf/examples/key-bindings.zsh
  [[ -f /usr/share/doc/fzf/examples/completion.zsh ]]   && source /usr/share/doc/fzf/examples/completion.zsh
fi

# Set fzf to use ripgrep for faster searches
export FZF_DEFAULT_COMMAND='rg --files --hidden --follow --glob "!.git/*"'
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
export FZF_ALT_C_COMMAND="fd --type d --hidden --follow --exclude .git"

# fzf colors (Tokyo Night): bg+ is the highlight row, so it must differ from bg.
export FZF_DEFAULT_OPTS='
  --color=fg:#c0caf5,bg:#1a1b26,hl:#bb9af7
  --color=fg+:#c0caf5,bg+:#292e42,hl+:#7dcfff
  --color=info:#7aa2f7,prompt:#7dcfff,pointer:#7dcfff
  --color=marker:#9ece6a,spinner:#9ece6a,header:#9ece6a
  --color=border:#565f89,gutter:#1a1b26
  --height 50% --layout=reverse --border
'
# Previews per widget: file contents for Ctrl-T, a tree for Alt-C (directories).
export FZF_CTRL_T_OPTS="--preview 'bat --style=numbers --color=always --line-range :500 {}'"
export FZF_ALT_C_OPTS="--preview 'eza --tree --level=2 --color=always {} | head -200'"

# zoxide - Smarter cd
_cache_init zoxide zoxide init zsh

# atuin - Better shell history. Ctrl-R opens atuin's search; Up stays plain
# prefix history (see Key Bindings) instead of opening the full-screen UI.
_cache_init atuin atuin init zsh --disable-up-arrow

# ============================================================================
# ZSH Plugins (Homebrew on macOS, apt on Debian/Ubuntu)
# ============================================================================

# Homebrew installs under <prefix>/share, Debian/Ubuntu under /usr/share.
# Probe both so Linux boxes without brew stay warning-free.
_tuidev_plugin_dirs=(${_tuidev_brew_prefix:+$_tuidev_brew_prefix/share} /usr/share)

# Syntax highlighting (must be near the end)
for _tuidev_dir in "${_tuidev_plugin_dirs[@]}"; do
  if [[ -f "$_tuidev_dir/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]]; then
    source "$_tuidev_dir/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
    break
  fi
done

# Autosuggestions (must be at the end)
for _tuidev_dir in "${_tuidev_plugin_dirs[@]}"; do
  if [[ -f "$_tuidev_dir/zsh-autosuggestions/zsh-autosuggestions.zsh" ]]; then
    source "$_tuidev_dir/zsh-autosuggestions/zsh-autosuggestions.zsh"
    break
  fi
done
unset _tuidev_plugin_dirs _tuidev_dir _tuidev_brew_prefix

# Autosuggestion behavior
ZSH_AUTOSUGGEST_STRATEGY=(history completion)
ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=20

# ============================================================================
# Aliases - Modern TUI Tools
# ============================================================================

# Modern replacements, for a person at a terminal. Claude Code captures aliases
# and functions into the shell its commands run in, and agents write the real
# flags: `ls -lt`, `cat -v` and `top -l 1` all fail under eza, bat and btm. So
# cat, ls and top are functions that hand over to the real command whenever
# stdout is not a terminal (an agent, a pipe, a script). Always `--icons=auto`:
# a bare `--icons` takes the next word as its value.
unalias cat ls top 2>/dev/null
function cat { if [[ -t 1 ]] && (( $+commands[bat] )); then bat "$@"; else command cat "$@"; fi; }
function ls { if [[ -t 1 ]] && (( $+commands[eza] )); then eza --icons=auto "$@"; else command ls "$@"; fi; }
# Complete them as the tools they run, where those tools' completions exist
# (Debian's bat completes as batcat, and compdef complains about a name it
# does not know).
(( $+_comps[bat] )) && compdef cat=bat
(( $+_comps[eza] )) && compdef ls=eza
alias ll='eza -l --icons=auto --git'
alias la='eza -la --icons=auto --git'
alias lt='eza --tree --level=2 --icons=auto'
alias tree='eza --tree --icons=auto'

# Git
command -v lazygit &>/dev/null && alias lg='lazygit'   # --extras
alias gs='git status'
alias ga='git add'
alias gc='git commit'
alias gp='git push'
alias gl='git pull'
alias gd='git diff'
alias gco='git checkout'
alias gb='git branch'

# tldr pages
command -v tldr &>/dev/null && alias help='tldr'

# procs and dust are NOT aliased over ps and du: their flags differ, which
# silently breaks scripts and the agents that inherit this shell. Call them by
# their own names.

# Navigation
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
# cd is zoxide for a person. Agents inherit this shell, and `z` takes none of
# cd's flags, so anything that is not a terminal, or passes a flag, gets cd.
unalias cd 2>/dev/null
if [[ -o interactive ]]; then
  function cd {
    if [[ -t 1 && "${1:-}" != -?* ]] && (( $+functions[z] )); then z "$@"; else builtin cd "$@"; fi
  }
fi

# System
if command -v btm &>/dev/null; then
  function top { if [[ -t 1 ]]; then btm "$@"; else command top "$@"; fi; }   # bottom, for a person
fi

# Markdown viewer. glow wraps at 80 columns whatever the pane; at a terminal
# it gets the pane's width (your own -w, given after, still wins).
if (( $+commands[glow] )); then
  function glow {
    if [[ -t 1 ]]; then command glow -w "${COLUMNS:-80}" "$@"; else command glow "$@"; fi
  }
  alias md='glow'
fi

# Utility
alias reload='source ~/.zshrc'
# Functions, not aliases: $EDITOR may carry arguments (code --wait).
unalias zshconfig 2>/dev/null
function zshconfig { ${=EDITOR} ~/.zshrc; }

# Code stats
command -v tokei &>/dev/null && alias loc='tokei'

# ============================================================================
# Functions
# ============================================================================

# Quick directory navigation with fzf
fcd() {
  local dir
  dir=$(fd --type d --hidden --follow --exclude .git | fzf +m) && cd "$dir"
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

# Quick benchmark command
bench() {
  if command -v hyperfine &>/dev/null; then
    hyperfine "$@"
  else
    time "$@"
  fi
}

# ============================================================================
# tmux (--pack tmux)
# ============================================================================
# Durable sessions for always-on nodes. `t NAME` attaches to session NAME
# (default "main"), creating it if needed; inside tmux it switches the client
# instead (tmux refuses to nest). `tls` lists sessions.
unalias t tls 2>/dev/null
if command -v tmux >/dev/null 2>&1; then
  function t {
    local name="${1:-main}"
    if [[ -n "$TMUX" ]]; then
      tmux has-session -t "=$name" 2>/dev/null || tmux new-session -d -s "$name" || return
      tmux switch-client -t "=$name"
    else
      tmux new-session -A -s "$name"
    fi
  }
  function tls { tmux list-sessions 2>/dev/null || echo "no tmux sessions"; }
fi

# Herdr (>= 0.9.2) and tmux set TERM_PROGRAM=herdr / tmux, which hyperlink
# detection (Claude Code, supports-hyperlinks) doesn't recognize, so agents
# stop emitting OSC 8 links. Herdr renders them (Ctrl+click) and the shipped
# tmux.conf passes them through, so advertise it; an explicit value, including
# 0, wins.
[[ ( -n "$HERDR_ENV" || -n "$TMUX" ) && -z "${FORCE_HYPERLINK+x}" ]] && export FORCE_HYPERLINK=1

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
    echo "Tailscale is not installed. Install with: brew install --cask tailscale-app"
  fi
}

# Show Tailscale IPv4 address
ts-ip() {
  if command -v tailscale &>/dev/null; then
    tailscale ip -4
  else
    echo "Tailscale is not installed. Install with: brew install --cask tailscale-app"
  fi
}

# Remote access dashboard - SSH, Tailscale, and tmux status
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

  # tmux sessions (--pack tmux)
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

}

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
setopt INTERACTIVE_COMMENTS    # Allow comments in interactive shells

# ============================================================================
# Key Bindings (emacs keymap, selected above)
# ============================================================================

# Ctrl-R: atuin's search when present, zsh's incremental search otherwise.
if [[ "${widgets[atuin-search]+set}" == set ]]; then
  bindkey '^R' atuin-search
else
  bindkey '^R' history-incremental-search-backward
fi

# Up/Down: recall history entries that start with what is already typed.
# Both the normal (CSI) and application (SS3) cursor-key forms are bound.
autoload -Uz up-line-or-beginning-search down-line-or-beginning-search
zle -N up-line-or-beginning-search
zle -N down-line-or-beginning-search
bindkey '^[[A' up-line-or-beginning-search   '^[OA' up-line-or-beginning-search
bindkey '^[[B' down-line-or-beginning-search '^[OB' down-line-or-beginning-search

# Home/End/Delete: zsh binds none of them by default. Terminals send CSI/SS3
# H/F; tmux (tmux-256color) sends 1~/4~.
bindkey '^[[H' beginning-of-line '^[OH' beginning-of-line '^[[1~' beginning-of-line
bindkey '^[[F' end-of-line       '^[OF' end-of-line       '^[[4~' end-of-line
bindkey '^[[3~' delete-char

# ============================================================================
# Node.js
# ============================================================================

# Node.js via fnm (--pack fnm): ~1ms init, puts Node on PATH eagerly and
# switches on .nvmrc/.node-version. fnm's PATH entry is a per-shell symlink
# that long-lived children (agents, MCP servers, git hooks) inherit and that
# can outlive its shell's cleanup, so the default alias follows it as a
# fallback: when the link is gone, `node` is still the default version.
if (( $+commands[fnm] )); then
  # --shell zsh: fnm otherwise infers the shell from its parent processes, and
  # fails ("can't infer your shell") under launchd, a sandbox or an agent's shell.
  eval "$(fnm env --use-on-cd --shell zsh)"
  if [[ -n "$FNM_DIR" && -d "$FNM_DIR/aliases/default/bin" ]]; then
    _fnm_i=${path[(i)$FNM_MULTISHELL_PATH/bin]}
    path[_fnm_i+1,_fnm_i]=("$FNM_DIR/aliases/default/bin")
    unset _fnm_i
  fi
fi

# ============================================================================
# Editor
# ============================================================================
# A GUI editor locally, else (and over SSH) the first terminal editor found:
# nvim, vim, vi, nano. With none of them, EDITOR is left as it was. Override
# in ~/.zshrc.local.
if [[ -z "$SSH_CONNECTION" ]] && command -v code >/dev/null 2>&1; then
  export EDITOR='code --wait'
elif [[ -z "$SSH_CONNECTION" ]] && command -v cursor >/dev/null 2>&1; then
  export EDITOR='cursor --wait'
else
  for _ed in nvim vim vi nano; do
    if command -v "$_ed" >/dev/null 2>&1; then export EDITOR="$_ed"; break; fi
  done
  unset _ed
fi
[[ -n "$EDITOR" ]] && export VISUAL="$EDITOR"

# ============================================================================
# Optional pack shell fragments
# ============================================================================
# Each opt-in pack that needs shell hooks (e.g. `--pack nvim`) drops a
# *.zsh file into ~/.config/tuidev/shell.d/. Sourced last so PATH (node,
# cargo, brew) is fully resolved before any fragment's `command -v` guards run.
if [[ -d "$_tuidev_state/shell.d" ]]; then
  for _tuidev_frag in "$_tuidev_state"/shell.d/*.zsh(N); do
    source "$_tuidev_frag"
  done
  unset _tuidev_frag
fi

# ============================================================================
# End of Configuration
# ============================================================================

# Load local customizations (if any). An `if`, not `&&`: a missing file must
# not leave $? = 1 for the first prompt.
if [[ -f ~/.zshrc.local ]]; then source ~/.zshrc.local; fi
