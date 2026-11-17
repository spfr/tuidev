#!/bin/bash
# Unit tests for scripts/health_check.sh's compinit check (check_zshrc_compinit):
# fixtures for ~/.zshrc and ~/.zshrc.local in a temp HOME, nothing real read.
# Run: bash scripts/lib/test_health_check.sh  -> exit 0 on pass.
# shellcheck disable=SC2016  # zsh text in single quotes on purpose
set -eo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/tuidev-test.XXXXXX")"; trap 'rm -rf "$tmp"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

export HOME="$tmp/home" TUIDEV_STATE_DIR="$tmp/home/.config/tuidev" TUIDEV_NO_COLOR=1
unset ZDOTDIR
mkdir -p "$HOME" "$TUIDEV_STATE_DIR"

# shellcheck source=../ui.sh disable=SC1091
. "$LIB_DIR/ui.sh"
# shellcheck source=config_write.sh disable=SC1091
. "$LIB_DIR/config_write.sh"
eval "$(sed -n '/^check_zshrc_compinit() {/,/^}/p' "$LIB_DIR/../health_check.sh")"

B="$(tuidev_block_begin tuidev-zshrc)"; E="$(tuidev_block_end tuidev-zshrc)"
# The shipped block: two compinit branches, one of which runs.
block() { printf '%s\n' "$B"; grep -v '^#' "$LIB_DIR/../../configs/zsh/.zshrc"; printf '%s\n' "$E"; }
run() { ( OPT_WARN=0; check_zshrc_compinit 2>&1; echo "end $OPT_WARN" ); }

# The shipped file alone: one compinit.
block > "$HOME/.zshrc"
[[ "$(grep -c 'compinit' "$HOME/.zshrc")" -gt 1 ]] || fail "fixture: the shipped block has no compinit branches"
out="$(run)"; [[ "$out" == "end 0" ]] || fail "the shipped block alone warns: $out"
pass "the tuidev block counts as one compinit however many branches it has"

# An installer's own call after it: two. Comments and autoload are not calls.
{ block; printf '%s\n' '# compinit is run above' 'autoload -Uz compinit' 'autoload -U compinit && compinit' ; } > "$HOME/.zshrc"
out="$(run)"
[[ "$out" == *"compinit runs 2 times"*"~/.zshrc: 2"*"never edits"*"end 1" ]] || fail "an added compinit: $out"
pass "an installer's compinit after the block: warned once, with the advice"

# Others: indented, after ;, &&, then; and ~/.zshrc.local is counted too.
{ printf '%s\n' 'if true; then' '  compinit -i' 'fi' 'x=1; compinit'; } > "$HOME/.zshrc"
printf '%s\n' '[[ -n $X ]] && compinit -C' > "$HOME/.zshrc.local"
out="$(run)"; [[ "$out" == *"3 times"*"~/.zshrc.local: 1"*"end 1" ]] || fail "forms of a call: $out"
pass "indented calls and calls after ; or && count, ~/.zshrc.local included"

# Not the file's own business otherwise: one call, none, no file, a trailing comment.
printf '%s\n' 'autoload -Uz compinit && compinit  # once' > "$HOME/.zshrc"; rm -f "$HOME/.zshrc.local"
out="$(run)"; [[ "$out" == "end 0" ]] || fail "one call warned: $out"
rm -f "$HOME/.zshrc"
out="$(run)"; [[ "$out" == "end 0" ]] || fail "no file warned: $out"
before="$(printf '%s\n' 'compinit' 'compinit')"; printf '%s\n' "$before" > "$HOME/.zshrc"; run >/dev/null
[[ "$(cat "$HOME/.zshrc")" == "$before" ]] || fail "the check edited the file"
pass "one call, no file: silent; the file is never edited"

echo
echo "All health check tests passed."
