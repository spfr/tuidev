#!/bin/bash
# Prints the social preview card, centred, then holds the screen so
# social-preview.tape can take docs/assets/social-preview.png. Edit the
# tagline here and run `make screenshots`.
cols="$(stty size 2>/dev/null </dev/tty)"; cols="${cols##* }"
[[ "$cols" =~ ^[0-9]+$ ]] || cols=60

title=(
    '████████╗██╗   ██╗██╗██████╗ ███████╗██╗   ██╗'
    '╚══██╔══╝██║   ██║██║██╔══██╗██╔════╝██║   ██║'
    '   ██║   ██║   ██║██║██║  ██║█████╗  ██║   ██║'
    '   ██║   ██║   ██║██║██║  ██║██╔══╝  ╚██╗ ██╔╝'
    '   ██║   ╚██████╔╝██║██████╔╝███████╗ ╚████╔╝ '
    '   ╚═╝    ╚═════╝ ╚═╝╚═════╝ ╚══════╝  ╚═══╝  '
)

# centre WIDTH STYLE TEXT — TEXT centred in the terminal, in STYLE.
centre() {
    local pad=$(( (cols - $1) / 2 ))
    [[ $pad -gt 0 ]] || pad=0
    printf '%*s%s%s\033[0m\n' "$pad" '' "$2" "$3"
}

printf '\033[?25l'          # no cursor in the picture
clear
echo
# Blocks in the accent blue, their shadow in the palette's dim grey.
for line in "${title[@]}"; do centre 46 $'\033[90m' "${line//█/$'\033[34m'█$'\033[90m'}"; done
echo
centre 39 $'\033[1m' "Run AI coding agents from the terminal:"
centre 34 $'\033[1;32m' "sandboxed, observable, reversible."
echo
centre 41 $'\033[37m' "Claude Code · Codex · macOS · Linux · MIT"
sleep "${1:-30}"
printf '\033[?25h'
