# shellcheck shell=bash
# Source this (bash, from the repo root) for the "modern shell" shots: the demo
# home from demo-env.sh, plus the real Starship prompt with the shipped config
# and palette, and the shipped eza and bat aliases, in its ~/api repo.
# See README.md next to it.
_shell_tapes="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_shell_repo="$(cd "$_shell_tapes/../../.." && pwd)"
# shellcheck source=demo-env.sh disable=SC1091
source "$_shell_tapes/demo-env.sh"

bash "$_shell_tapes/demo-shell-setup.sh" "$HOME"
shopt -s expand_aliases
# The aliases tuidev's .zshrc ships, read from it so they can't drift.
eval "$(grep -E '^alias (cat|ls|ll|la|lt|tree)=' "$_shell_repo/configs/zsh/.zshrc")"
# Two changes for a made-up, portable picture: the render font has no icon
# glyphs, and the owner column would show whoever renders it.
alias ll='eza -l --git --icons=never --no-user --no-permissions'
export TZ=UTC STARSHIP_CONFIG="$HOME/.config/starship.toml" STARSHIP_CACHE="$HOME/.cache/starship"
unset PS1 _shell_tapes _shell_repo
eval "$(starship init bash)"
cd "$HOME/api" || return
