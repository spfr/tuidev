#!/bin/bash
# Tests for how agents is installed: the monitoring pack puts bin/agents in
# ~/.local/bin and lib/agents/ in ~/.local/lib/tuidev/agents, records every
# file, and uninstall.sh removes them all; the installed command runs on its
# own, without the repo, and says what is missing when a module is gone.
# Run: bash scripts/lib/test_agents_install.sh  -> exit 0 on pass.
#
# A throwaway HOME (with a space in its path) and stubbed ps, pmset, lsof and
# osascript: nothing real is read, signalled or asked for.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# As the installed agents will print it: macOS's TMPDIR ends in a slash, and
# mktemp keeps the "//" that makes, which a path agents resolves has not.
tmp="$(mktemp -d "${TMPDIR:-/tmp}/tuidev-test.XXXXXX")"
tmp="$(cd "$tmp" && pwd)"
trap 'rm -rf "$tmp"' EXIT

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "PASS: $1"; }

for v in $(compgen -v AGENTS_) XDG_CONFIG_HOME XDG_STATE_HOME; do unset "$v"; done
export HOME="$tmp/my home" TUIDEV_NO_COLOR=1 NO_COLOR=1 DRY_RUN=false AGENTS_NO_HERDR=1
export TUIDEV_STATE_DIR="$HOME/.config/tuidev" TUIDEV_MANIFEST_ENABLED=1   # recording on, as install.sh has it
mkdir -p "$HOME" "$tmp/stub" "$tmp/elsewhere"

# One claude session in the process table; no listeners, launchd jobs, pmset
# or admin dialog.
cat > "$tmp/stub/ps" <<'EOF'
#!/bin/sh
case "$*" in
    *axww*) printf '%s\n' \
        '    1     0     0 root   0.0  20000 10:00.00 13-16:00:00 Wed Sep 30 16:57:15 2026     /sbin/launchd' \
        ' 4242     1   501 me     3.0 300000  0:30.00    01:00:00 Wed Oct 14 08:00:00 2026     claude' ;;
esac
EOF
printf '#!/bin/sh\nexit 1\n' > "$tmp/stub/lsof"
printf '#!/bin/sh\nexit 1\n' > "$tmp/stub/osascript"
printf '#!/bin/sh\nexit 0\n' > "$tmp/stub/pmset"
printf '#!/bin/sh\nexit 0\n' > "$tmp/stub/launchctl"
chmod +x "$tmp/stub"/*
export PATH="$tmp/stub:$PATH"

bin="$HOME/.local/bin/agents"
lib="$HOME/.local/lib/tuidev/agents"
install_agents() {
    # shellcheck source=../install/packs/monitoring.sh disable=SC1091
    ( . "$REPO_DIR/scripts/install/packs/monitoring.sh"; _monitoring_agents )
}

# 1. The pack installs the command and every module, and records each file.
install_agents > "$tmp/install.log" 2>&1 || fail "install: $(cat "$tmp/install.log")"
if [[ ! -x "$bin" ]] || ! cmp -s "$bin" "$REPO_DIR/bin/agents"; then fail "agents not installed as $bin"; fi
n=0
while IFS= read -r src; do
    rel="${src#"$REPO_DIR/lib/agents/"}"
    cmp -s "$lib/$rel" "$src" || fail "module $rel not installed"
    grep -qxF "file $lib/$rel" "$TUIDEV_STATE_DIR/manifest" || fail "module $rel not in the manifest"
    n=$((n + 1))
done < <(find "$REPO_DIR/lib/agents" -type f | LC_ALL=C sort)
[[ $n -gt 20 ]] || fail "only $n module files found"
grep -qxF "file $bin" "$TUIDEV_STATE_DIR/manifest" || fail "agents not in the manifest"
install_agents > "$tmp/again.log" 2>&1 || fail "second install: $(cat "$tmp/again.log")"
! grep -q "overwrote" "$tmp/again.log" || fail "a second install rewrote files: $(grep overwrote "$tmp/again.log")"
pass "the monitoring pack installs agents and its $n module files, each in the manifest; a second run changes nothing"

# 2. The installed command runs from anywhere, on the installed modules only.
cd "$tmp/elsewhere"
out="$("$bin" --help 2>&1)" || fail "installed agents --help: $out"
[[ "$out" == "agents — "* && "$out" == *"AGENTS_ORPHAN_PATTERNS in $lib/config.sh"* ]] || fail "installed --help: $(printf '%s\n' "$out" | head -3)"
[[ "$(bash -c '. "$1"; printf "%s\n" "$_AGENTS_LIB"' _ "$bin")" == "$lib" ]] || fail "the installed agents loads modules from elsewhere"
out="$("$bin" tsv 2>&1)" || fail "installed agents tsv: $out"
[[ $'\n'"$out" == *$'\n'"agent"$'\t'"4242"$'\t'"claude"$'\t'* ]] || fail "installed tsv has no agent row: $out"
[[ "$out" == *$'\n'"conf"$'\t'"AGENTS_CONF"$'\t'"$HOME/.config/agents.conf"* ]] || fail "installed tsv has no conf rows: $out"
pass "the installed agents runs outside the repo: --help and tsv, from its own modules"

# 3. Through symlinks: to the installed command, and to a checkout's.
mkdir -p "$tmp/links"
ln -s "$bin" "$tmp/links/agents"
ln -s "../my home/.local/bin/agents" "$tmp/links/rel-agents"
ln -s "$REPO_DIR/bin/agents" "$tmp/links/repo-agents"
for l in agents rel-agents repo-agents; do
    "$tmp/links/$l" --help >/dev/null 2>&1 || fail "agents through the symlink $l"
done
[[ "$(bash -c '. "$1"; printf "%s\n" "$_AGENTS_LIB"' _ "$tmp/links/repo-agents")" == "$REPO_DIR/lib/agents" ]] \
    || fail "a symlink to the checkout's agents does not load the checkout's modules"
pass "symlinks to agents (absolute or relative) find its modules"

# 4. A missing module, or no modules at all: a clear error, nothing half loaded.
mv "$lib/tsv.sh" "$tmp/tsv.sh"
out="$("$bin" --help 2>&1)" && fail "agents ran without tsv.sh"
[[ "$out" == "agents: missing $lib/tsv.sh (reinstall: ./install.sh --pack monitoring)" ]] || fail "missing module message: $out"
mv "$tmp/tsv.sh" "$lib/tsv.sh"
mv "$lib" "$tmp/lib-away"
out="$("$bin" --help 2>&1)" && fail "agents ran without its modules"
[[ "$out" == "agents: missing $HOME/.local/lib/tuidev/agents/ (reinstall: ./install.sh --pack monitoring)" ]] || fail "missing modules message: $out"
# shellcheck source=/dev/null
( . "$bin" ) 2>/dev/null && fail "sourcing agents without its modules succeeded"
mv "$tmp/lib-away" "$lib"
pass "a missing module or module directory is named, and agents exits 1"

# 5. uninstall.sh removes the command, every module and their directories.
cd "$tmp"
bash "$REPO_DIR/uninstall.sh" --all </dev/null > "$tmp/uninstall.log" 2>&1 || fail "uninstall.sh: $(tail -20 "$tmp/uninstall.log")"
[[ ! -e "$bin" ]] || fail "uninstall left $bin"
[[ ! -e "$HOME/.local/lib/tuidev" ]] || fail "uninstall left $(find "$HOME/.local/lib/tuidev" | head -5)"
pass "uninstall.sh removes agents, its modules and their directories"

# 6. The agents history survives uninstall unless --purge-history; nothing else goes.
printf '#!/bin/sh\nexit 1\n' > "$tmp/stub/brew"; chmod +x "$tmp/stub/brew"   # no manifest now: uninstall probes brew
hist="$HOME/.local/state/tuidev/agents"
mkdir -p "$hist/sample" "$HOME/.local/state/other"
echo x > "$hist/history.tsv"; echo x > "$hist/sample/ledger"; echo keep > "$HOME/.local/state/other/f"
bash "$REPO_DIR/uninstall.sh" --all </dev/null > "$tmp/u.log" 2>&1 || fail "uninstall.sh --all: $(tail -5 "$tmp/u.log")"
[[ -f "$hist/history.tsv" ]] || fail "--all (no TTY, no flag) deleted the history"
grep -q "kept the agents history" "$tmp/u.log" || fail "no 'kept' note: $(tail -5 "$tmp/u.log")"
bash "$REPO_DIR/uninstall.sh" --all --purge-history --dry-run </dev/null > "$tmp/u.log" 2>&1 || fail "dry run: $(tail -5 "$tmp/u.log")"
[[ -f "$hist/history.tsv" ]] || fail "--dry-run deleted the history"
grep -q "rm -rf .*tuidev/agents" "$tmp/u.log" || fail "dry run does not show the removal: $(tail -8 "$tmp/u.log")"
mkdir -p "$tmp/outside/tuidev/agents"; ln -s "$tmp/outside" "$HOME/.local/state/link"
XDG_STATE_HOME="$tmp/outside" bash "$REPO_DIR/uninstall.sh" --all --purge-history </dev/null > "$tmp/u.log" 2>&1 || fail "outside: $(tail -5 "$tmp/u.log")"
[[ -d "$tmp/outside/tuidev/agents" ]] || fail "deleted a history dir outside HOME"
XDG_STATE_HOME="$HOME/.local/state/link" bash "$REPO_DIR/uninstall.sh" --all --purge-history </dev/null > "$tmp/u.log" 2>&1 || fail "symlink: $(tail -5 "$tmp/u.log")"
[[ -d "$tmp/outside/tuidev/agents" ]] || fail "deleted a history dir reached through a symlink out of HOME"
bash "$REPO_DIR/uninstall.sh" --all --purge-history </dev/null > "$tmp/u.log" 2>&1 || fail "purge: $(tail -5 "$tmp/u.log")"
[[ ! -e "$hist" ]] || fail "--purge-history left $hist"
[[ -f "$HOME/.local/state/other/f" ]] || fail "--purge-history touched a sibling"
pass "uninstall.sh keeps the agents history by default; --purge-history deletes only that directory, inside HOME, never via symlink; --dry-run deletes nothing"

echo ""
echo "All agents install tests passed."
