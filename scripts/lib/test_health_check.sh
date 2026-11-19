#!/bin/bash
# Unit tests for scripts/health_check.sh: the compinit check
# (check_zshrc_compinit), the Seatbelt smoke probe run inside a sandbox (a
# stub sandbox-exec), and the pack probes (packs.sh pack_check and each
# pack's <pack>_check, against stub commands). Fixtures in a temp HOME,
# nothing real read.
# Run: bash scripts/lib/test_health_check.sh  -> exit 0 on pass.
# shellcheck disable=SC2016  # zsh text in single quotes on purpose
set -eo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/tuidev-test.XXXXXX")"; trap 'rm -rf "$tmp"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

export HOME="$tmp/home" TUIDEV_STATE_DIR="$tmp/home/.config/tuidev" TUIDEV_NO_COLOR=1
unset ZDOTDIR XDG_CONFIG_HOME FNM_DIR
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

# --- The Seatbelt smoke probe inside a sandbox ---------------------------------------
# A fake sandbox-exec: Seatbelt refusing to nest (rc 71), or another failure.
STUBS="$tmp/stubs"; mkdir -p "$STUBS"
cat > "$STUBS/sandbox-exec" <<'EOF'
#!/bin/bash
case "${SBX_STUB:-ok}" in
    nested) echo "sandbox-exec: sandbox_apply: Operation not permitted" >&2; exit 71 ;;
    broken) echo "sandbox-exec: invalid profile" >&2; exit 65 ;;
esac
EOF
chmod +x "$STUBS/sandbox-exec"
for f in check_required check_optional have_cmd check_sandbox; do
    body="$(sed -n "/^$f() [{]/,/^[}]/p" "$LIB_DIR/../health_check.sh")"   # in a variable first: bash 3.2
    eval "$body"
done
# shellcheck disable=SC2034  # TUIDEV_OS is read by check_sandbox
smoke() { ( PATH="$STUBS:/usr/bin:/bin" TUIDEV_OS=Darwin REQ_PASS=0 REQ_FAIL=0 OPT_WARN=0; SBX_STUB="$1" check_sandbox required 2>&1 || true; echo "fail=$REQ_FAIL pass=$REQ_PASS" ); }
out="$(smoke nested)"
[[ "$out" == *"sandbox-exec works (inline smoke profile): skipped, already inside a sandbox"* && "$out" != *"sandbox-exec works (inline smoke profile) (required)"* && "$out" == *"fail=2 pass=0" ]] \
    || fail "nested Seatbelt: the smoke probe must be skipped (the other two still fail here): $out"
out="$(smoke broken)"
[[ "$out" == *"sandbox-exec works (inline smoke profile) (required)"* && "$out" == *"fail=3 "* ]] || fail "another sandbox-exec failure must stay a required failure: $out"
out="$(smoke ok)"
[[ "$out" != *"skipped"* && "$out" == *"fail=2 pass=1" ]] || fail "a working sandbox-exec passes: $out"
pass "sandbox-exec refused for nesting is a skip; any other failure is still a required failure"

# --- Pack probes (scripts/lib/packs.sh pack_check, each pack's <pack>_check) ----------
# shellcheck source=packs.sh disable=SC1091
. "$LIB_DIR/packs.sh"
# shellcheck source=pkg.sh disable=SC1091
. "$LIB_DIR/pkg.sh"
PB="$tmp/pbin"; mkdir -p "$PB"
stub() { local c; for c in "$@"; do printf '#!/bin/bash\n' > "$PB/$c"; chmod +x "$PB/$c"; done; }
os() { printf '#!/bin/bash\necho %s\n' "$1" > "$PB/uname"; chmod +x "$PB/uname"; }
probe() { PATH="$PB:/usr/bin:/bin" RELEASE_AGE_TOOL_DIRS="$tmp/none" pack_check "$1" >/dev/null 2>&1; }
os Linux

# release-age (no binary of its own): passes when each installed tool waits.
probe release-age || fail "release-age with none of npm, bun, uv installed has nothing to wait for"
stub bun; ! probe release-age || fail "release-age: bun without a minimumReleaseAge passed"
printf '[install]\nminimumReleaseAge = 259200\n' > "$HOME/.bunfig.toml"; probe release-age || fail "release-age: bun waits"
stub npm; ! probe release-age || fail "release-age: npm without a setting or a record passed"
printf 'block tuidev-release-age %s\n' "$HOME/.npmrc" > "$TUIDEV_STATE_DIR/manifest"
probe release-age || fail "release-age: npm with our block recorded (the file is not read then)"
rm -f "$TUIDEV_STATE_DIR/manifest"; printf 'min-release-age=5\n' > "$HOME/.npmrc"
probe release-age || fail "release-age: npm with your own setting"
pass "release-age: each installed npm, bun and uv waits, by our block or your own setting"

# cooling: nothing to do off Apple Silicon, so it passes there.
probe cooling || fail "cooling on Linux has nothing to do"
pass "cooling: passes where the pack has nothing to do"

# herdr-core: the binary and the job that keeps it up.
! probe herdr-core || fail "herdr-core without herdr-core passed"
stub herdr-core; ! probe herdr-core || fail "herdr-core without its systemd timer passed"
mkdir -p "$HOME/.config/systemd/user"; : > "$HOME/.config/systemd/user/tuidev-hc.timer"
probe herdr-core || fail "herdr-core with its binary and timer"
pass "herdr-core: its binary and the job that keeps it up"

# The fallback, for packs with no probe of their own: what they declare.
! probe hunk || fail "hunk without hunk passed"
stub hunk; probe hunk || fail "hunk with hunk"
stub nvim; probe nvim || fail "nvim: the neovim formula's command is nvim"
stub actionlint zizmor; ! probe ci || fail "ci with two of its three tools passed"
stub betterleaks; probe ci || fail "ci with all three"
stub agents btm; probe monitoring || fail "monitoring on Linux needs no terminal-notifier"
stub tmux; ! probe tmux || fail "tmux without its config passed"
mkdir -p "$HOME/.config/tmux"; : > "$HOME/.config/tmux/tmux.conf"; probe tmux || fail "tmux with its config"
pass "the fallback looks for the declared commands (macOS-only ones skipped elsewhere); tmux checks its config too"

echo
echo "All health check tests passed."
