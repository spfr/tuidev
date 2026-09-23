# tuidev shell fragment — Neovim aliases (installed by `--pack nvim`).
#
# Dropped into ~/.config/tuidev/shell.d/ and sourced last by the managed
# ~/.zshrc. $EDITOR is chosen there (a GUI editor locally, else the first of
# nvim, vim, vi, nano).

if (( $+commands[nvim] )); then
  alias vim='nvim'
  alias vi='nvim'
  alias v='nvim'
fi
