# tuidev shell fragment — OpenCode wrapper (installed by `--pack opencode`).
#
# Dropped into ~/.config/tuidev/shell.d/ and sourced last by the managed
# ~/.zshrc, once PATH is fully resolved.

# The official installer puts the binary in ~/.opencode/bin.
[[ -d "$HOME/.opencode/bin" ]] && path=("$HOME/.opencode/bin" $path)

unalias oc 2>/dev/null

if command -v opencode >/dev/null 2>&1; then
  oc() { command opencode "$@"; }
fi
