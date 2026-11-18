# tuidev shell fragment — claude and codex typed in a Herdr pane, hosted in
# herdr-core so Herdr's phone app lists them (installed by `--pack herdr-core`).
#
# Dropped into ~/.config/tuidev/shell.d/ and sourced by the managed ~/.zshrc.
# Opt-in: AGENTS_HC_AUTO=1 in agents.conf (or the environment). The functions
# exist only where that could apply: an interactive shell in a Herdr pane,
# not a terminal of herdr-core's, with agents and herdr-core installed and
# the setting on when the shell started. Elsewhere, and in an agent's own
# shell, claude and codex stay the real commands.
#
# Each call costs a few tests unless a person typed it (stdin and stdout are
# the terminal); then `agents hc auto` decides, and runs the command as typed
# whenever it does not host it. It finds the real binary on PATH: it is bash,
# where these functions do not exist.

() {
  setopt local_options no_bash_rematch no_re_match_pcre
  [[ -o interactive && -n ${HERDR_ENV-} && -z ${HC_TERMINAL_ID-} ]] || return 0
  [[ -x ${commands[agents]-} && -x ${commands[herdr-core]-} ]] || return 0
  local conf=${AGENTS_CONF:-${XDG_CONFIG_HOME:-$HOME/.config}/agents.conf} on=${AGENTS_HC_AUTO-}
  if [[ -z ${AGENTS_HC_AUTO+set} && -r $conf ]]; then
    # agents.conf's own rule (config.sh): KEY=value lines, the last one wins;
    # a quoted value is the rest of the line, a bare one may have a comment.
    local line
    local -a lines=("${(@f)$(<$conf)}")
    for line in "${(@M)lines:#*AGENTS_HC_AUTO=*}"; do
      if [[ $line =~ '^[[:space:]]*AGENTS_HC_AUTO=("([01]?)"|'\''([01]?)'\''|([01]?)([[:space:]]+#.*)?)[[:space:]]*$' ]]; then
        on=$match[2]$match[3]$match[4]
      fi
    done
  fi
  [[ $on == 1 ]] || return 0
  # An agents from before `hc auto` would print its usage where claude starts.
  command agents hc auto --supported 2>/dev/null || return 0

  _tuidev_hc_auto() {
    # -x, not $+commands: the hash outlives a removed file.
    if [[ -n ${HERDR_ENV-} && -z ${HC_TERMINAL_ID-} && -t 0 && -t 1 && -x ${commands[agents]-} ]]; then
      command agents hc auto "$@"
    else
      command "$@"
    fi
  }
  # `function NAME`: a claude or codex alias of yours would be expanded in
  # `NAME() {`, and the file would not parse.
  function claude { _tuidev_hc_auto claude "$@"; }
  function codex { _tuidev_hc_auto codex "$@"; }
}
