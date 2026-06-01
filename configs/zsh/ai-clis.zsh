# tuidev shell fragment — AI CLI wrappers (installed by `--pack ai-clis`).
#
# Dropped into ~/.config/tuidev/shell.d/ and sourced last by the managed
# ~/.zshrc block, after PATH (node, cargo, brew) is fully set, so the
# `command -v` guards below see every CLI.
#
# Wrappers auto-route through the Seatbelt sandbox (sbx) when it's installed
# (--pack sandbox). Escape hatches:
#   CC_NO_SANDBOX=1 cc ...          one-shot, per invocation
#   sbx --profile off -- claude     explicit, documented profile bypass
#   unalias cc                      nuclear option
#
# Note: Gemini CLI is deprecated upstream (succeeded by Antigravity, `agy`).
# tuidev stays CLI-agnostic — add your own wrapper if you use it, e.g.:
#   command -v agy >/dev/null 2>&1 && agy() { _tuidev_run_ai agy "$@"; }

_tuidev_run_ai() {
  # Dispatch CLI through sbx unless the escape hatch is active.
  local cli="$1"; shift
  if [[ -n "${CC_NO_SANDBOX:-}" ]] || ! command -v sbx >/dev/null 2>&1; then
    command "$cli" "$@"
  else
    command sbx -- "$cli" "$@"
  fi
}

# Drop any pre-existing aliases of these names (zsh refuses to define a
# function whose name collides with an existing alias). Safe no-op when absent.
unalias cc cx oc 2>/dev/null

command -v claude   >/dev/null 2>&1 && cc() { _tuidev_run_ai claude   "$@"; }
command -v codex    >/dev/null 2>&1 && cx() { _tuidev_run_ai codex    "$@"; }
command -v opencode >/dev/null 2>&1 && oc() { _tuidev_run_ai opencode "$@"; }
