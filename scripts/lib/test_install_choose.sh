#!/bin/bash
# Tests for install.sh's first-run question: `--choose` (asks, prints the flags,
# installs nothing), the menu on stderr and the flags alone on stdout, the
# no-terminal default, and that a choice made on a terminal gives the same
# dry-run plan as the same flags typed.
# Run: bash scripts/lib/test_install_choose.sh  -> exit 0 on pass (also under /bin/bash).
#
# shellcheck disable=SC2015,SC2016  # `a && b || fail` checks

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
INSTALL="$REPO_DIR/install.sh"
SH="$BASH"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/tuidev-choose.XXXXXX")"
tmp="$(cd "$tmp" && pwd)"
trap 'rm -rf "$tmp"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

export HOME="$tmp/home"
mkdir -p "$HOME"
unset TUIDEV_STATE_DIR TUIDEV_HOME XDG_DATA_HOME XDG_STATE_HOME XDG_CONFIG_HOME

if [[ "$(uname)" == Darwin ]]; then DEF="--profile full"; else DEF="--profile remote --pack ai-clis"; fi

# choose INPUT — run `install.sh --choose` with INPUT on stdin (no terminal).
# OUT is stdout, ERR is stderr, RC the exit status.
choose() {
    local rc=0
    printf '%s' "$1" | "$SH" "$INSTALL" --choose > "$tmp/out" 2> "$tmp/err" || rc=$?
    OUT="$(cat "$tmp/out")"; ERR="$(cat "$tmp/err")"; RC=$rc
}

# --- 1. every answer prints exactly its flags ------------------------------------
check() {  # check INPUT FLAGS
    choose "$1"
    [[ "$RC" == 0 ]] || fail "answer '$1': exit $RC"
    [[ "$OUT" == "$2" ]] || fail "answer '$1': stdout is '$OUT', want '$2'"
    [[ "$(wc -l < "$tmp/out" | tr -d ' ')" == 1 ]] || fail "answer '$1': stdout is not one line: $(cat "$tmp/out")"
    [[ "$ERR" == *"What should this machine get?"* && "$ERR" == *"1)"* && "$ERR" == *"4)"* ]] || fail "answer '$1': no menu on stderr: $ERR"
    [[ "$OUT" != *"What should"* ]] || fail "the menu leaked to stdout"
}
check $'1\n' "--profile full"
check $'2\n' "--profile desktop --pack ai-clis"
check $'3\n' "--profile remote --pack ai-clis"
check $'4\n' "--profile minimal"
check $'\n'  "$DEF"
check '2'    "--profile desktop --pack ai-clis"   # an answer with no newline at EOF still counts
pass "--choose: 1-4 print their flags alone on stdout, the menu is on stderr, Enter takes the OS default ($DEF)"

# --- 2. no answer is a refusal -----------------------------------------------------
for input in $'q\n' $'Q\n' '' $'5\n' $'0\n' $'full\n' $'--profile full\n' $'$(id)\n' $'1;2\n'; do
    choose "$input"
    [[ "$RC" == 1 && -z "$OUT" ]] || fail "answer '$input': exit $RC, stdout '$OUT' (want exit 1 and nothing on stdout)"
    [[ "$ERR" == *"What should this machine get?"* ]] || fail "answer '$input': no menu"
done
pass "--choose: q, EOF and anything else exit 1 with nothing on stdout"

# --- 3. --choose installs nothing ---------------------------------------------------
choose $'1\n'
[[ -z "$(find "$HOME" -type f 2>/dev/null | head -1)" ]] || fail "--choose wrote into HOME: $(find "$HOME" -type f | head -3)"
pass "--choose writes nothing under HOME"

# --- 4. no terminal: the old default, and never the menu ------------------------------
rc=0; "$SH" "$INSTALL" --dry-run < /dev/null > "$tmp/out" 2> "$tmp/err" || rc=$?
[[ "$rc" == 0 ]] || fail "--dry-run with no terminal: exit $rc: $(tail -3 "$tmp/err")"
if [[ "$(uname)" == Darwin ]]; then want=desktop; else want=minimal; fi
grep -q "defaulting to --profile $want" "$tmp/out" && grep -q "^.*profile:  $want" "$tmp/out" || fail "the non-interactive default is not $want: $(head -5 "$tmp/out")"
grep -q "What should this machine get" "$tmp/out" "$tmp/err" && fail "the menu was printed with no terminal"
rc=0; printf '2\n' | "$SH" "$INSTALL" --dry-run > "$tmp/out" 2> "$tmp/err" || rc=$?
grep -q "defaulting to --profile $want" "$tmp/out" && ! grep -q "What should this machine get" "$tmp/out" "$tmp/err" \
    || fail "a pipe on stdin was asked the question: $(head -5 "$tmp/out")"
pass "no terminal: --dry-run takes the old default ($want) and prints no menu, even with input piped"

# Flags that name something never ask (checked through a pty below as well).
# --- 5. a terminal asks; the answer gives the plan the same flags give -----------------
with_tty() {  # CMD... ; $TTY_INPUT is typed into the pty (which is also stdin)
    python3 -I -c '
import os, pty, sys
pid, fd = pty.fork()
if pid == 0:
    os.execvp(sys.argv[1], sys.argv[1:])
os.write(fd, os.environ.get("TTY_INPUT", "").encode())
buf = b""
while True:
    try:
        d = os.read(fd, 4096)
        if not d: break
        buf += d
    except OSError: break
_, st = os.waitpid(pid, 0)
sys.stdout.write(buf.decode(errors="replace"))
sys.exit(os.waitstatus_to_exitcode(st))
' "$@"
}

# plan FILE — the lines that say what would be installed.
plan() { tr -d '\r' < "$1" | sed $'s/\033\\[[0-9;]*m//g' | grep -E '(profile:|packs:|--pack:) ' | sed -E 's/^[^a-z-]*//' | tr -s ' '; }

if ! command -v python3 >/dev/null 2>&1 || ! TTY_INPUT='' with_tty "$SH" -c '[[ -t 0 ]]' >/dev/null 2>&1; then
    echo "SKIP: no python3 pty to give install.sh a terminal (the interactive checks)"
else
    pair() {  # pair ANSWER FLAGS... — a terminal answering ANSWER plans what FLAGS plan
        local answer="$1"; shift
        TTY_INPUT="$answer" with_tty "$SH" "$INSTALL" --dry-run > "$tmp/tty.out" 2>&1 \
            || fail "terminal answer '$answer': $(tail -3 "$tmp/tty.out")"
        grep -q "What should this machine get" "$tmp/tty.out" || fail "terminal answer '$answer': no question asked"
        grep -q "defaulting to" "$tmp/tty.out" && fail "terminal answer '$answer': fell to the default"
        "$SH" "$INSTALL" "$@" --dry-run < /dev/null > "$tmp/flag.out" 2>&1 || fail "explicit flags '$*': $(tail -3 "$tmp/flag.out")"
        [[ -n "$(plan "$tmp/tty.out")" ]] || fail "terminal answer '$answer': no plan lines: $(head -20 "$tmp/tty.out")"
        [[ "$(plan "$tmp/tty.out")" == "$(plan "$tmp/flag.out")" ]] \
            || fail "terminal answer '$answer' plans:
$(plan "$tmp/tty.out")
but '$*' plans:
$(plan "$tmp/flag.out")"
    }
    pair $'1\n' --profile full
    pair $'2\n' --profile desktop --pack ai-clis
    pair $'3\n' --profile remote --pack ai-clis
    pair $'4\n' --profile minimal
    # shellcheck disable=SC2086  # DEF is a flag list on purpose
    pair $'\n' $DEF
    pass "on a terminal the answer plans exactly what the same flags plan (profile, packs, --pack lines)"

    # q quits with nothing planned, exit 0.
    rc=0; TTY_INPUT=$'q\n' with_tty "$SH" "$INSTALL" --dry-run > "$tmp/tty.out" 2>&1 || rc=$?
    [[ "$rc" == 0 ]] || fail "q on a terminal: exit $rc"
    grep -q "nothing installed" "$tmp/tty.out" && ! grep -q "dry-run:" "$tmp/tty.out" || fail "q on a terminal went on: $(cat "$tmp/tty.out")"
    # Garbage quits too.
    rc=0; TTY_INPUT=$'what\n' with_tty "$SH" "$INSTALL" --dry-run > "$tmp/tty.out" 2>&1 || rc=$?
    [[ "$rc" == 0 ]] && grep -q "nothing installed" "$tmp/tty.out" && ! grep -q "dry-run:" "$tmp/tty.out" || fail "garbage on a terminal went on: $(cat "$tmp/tty.out")"
    pass "on a terminal, q or anything else installs nothing"

    # Flags that name what to install are never second-guessed, terminal or not.
    for flags in "--core" "--profile minimal" "--pack tmux" "--extras"; do
        # shellcheck disable=SC2086
        TTY_INPUT='' with_tty "$SH" "$INSTALL" $flags --dry-run > "$tmp/tty.out" 2>&1 || fail "flags '$flags' on a terminal: $(tail -3 "$tmp/tty.out")"
        grep -q "What should this machine get" "$tmp/tty.out" && fail "'$flags' was asked the question"
    done
    pass "any profile or pack flag skips the question, even on a terminal"
fi

echo ""
echo "All install --choose tests passed."
