#!/bin/bash
# shellcheck disable=SC2015  # `A && B || fail`: fail when either check fails
# Unit tests for scripts/lib/release.sh and scripts/lib/herdr.sh, and the
# migration to Herdr's release binary. curl, ps, uname, sysctl, launchctl,
# plutil, systemctl and herdr itself are stubs: no network, no real server,
# and the real HOME is never touched.
# Run: bash scripts/lib/test_herdr.sh  -> exit 0 on pass.
set -eo pipefail
unset XDG_CONFIG_HOME HERDR_ENV HERDR_INSTALL_DIR HOMEBREW_PREFIX TUIDEV_HERDR_VERSION

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MIGRATION="$LIB_DIR/../migrations/202610161843_herdr_direct_install.sh"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/tuidev-test.XXXXXX")"; trap 'rm -rf "$tmp"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

if ! command -v jq >/dev/null 2>&1; then
    echo "SKIP: jq not installed (release.sh reads the release record with it)"
    exit 0
fi

export HOME="$tmp/home" TUIDEV_STATE_DIR="$tmp/home/.config/tuidev" TUIDEV_NO_COLOR=1
export TUIDEV_MANIFEST_FILE="$TUIDEV_STATE_DIR/manifest"
mkdir -p "$HOME/.local/bin" "$TUIDEV_STATE_DIR" "$tmp/bin" "$tmp/fix"
log="$tmp/calls.log"; : > "$log"

stub() {  # stub NAME BODY: logs "NAME args", then runs BODY
    printf '#!/bin/bash\necho "%s $*" >> "%s"\n%s\n' "$1" "$log" "$2" > "$tmp/bin/$1"
    chmod +x "$tmp/bin/$1"
}
ln -s "$(command -v jq)" "$tmp/bin/jq"
# shellcheck disable=SC2016  # stub bodies expand in the stub
stub uname 'case "$1" in -m) echo "${STUB_ARCH:-arm64}" ;; *) echo "${STUB_OS:-Darwin}" ;; esac'
# shellcheck disable=SC2016
stub sysctl 'echo "${STUB_ARM64:-0}"'
# The release record and the asset: curl serves them from the fixtures.
# shellcheck disable=SC2016
stub curl 'out="" url=""
while [[ $# -gt 0 ]]; do case "$1" in -o) out="$2"; shift 2 ;; https://*) url="$1"; shift ;; *) shift ;; esac; done
case "$url" in
    https://api.github.com/*) cat "'"$tmp"'/fix/release.json" ;;
    https://github.com/*) cp "'"$tmp"'/fix/asset" "$out"
        if [[ -n "${STUB_CURL_INT:-}" ]]; then kill -INT "$PPID"; exit 130; fi ;;
    *) exit 22 ;;
esac'
# shellcheck disable=SC2016
stub ps 'printf "%s\n" "${STUB_PS:-}"'
# shellcheck disable=SC2016
stub launchctl 'printf "%s\n" "${STUB_LAUNCHCTL:-}"'
# plutil -extract KEYPATH raw|xml1 -o - FILE, for the plists these tests
# write (one level of dict): raw prints a boolean, or a dictionary's keys
# one per line as plutil does; KEY.SUB looks inside KEY's dictionary.
# shellcheck disable=SC2016
stub plutil 'key="$2"; f="${!#}"; flat="$(tr -d " \t\n" < "$f")"
if [[ "$key" == *.* ]]; then
    case "$flat" in *"<key>${key%%.*}</key><dict>"*) ;; *) exit 1 ;; esac
    flat="${flat#*"<key>${key%%.*}</key><dict>"}"; flat="${flat%%"</dict>"*}"; key="${key#*.}"
fi
case "$flat" in
    *"<key>$key</key><true/>"*) v=true ;;
    *"<key>$key</key><false/>"*) v=false ;;
    *"<key>$key</key><dict>"*) d="${flat#*"<key>$key</key><dict>"}"; d="${d%%"</dict>"*}"
        v="$(printf "%s" "$d" | grep -o "<key>[^<]*</key>" | sed "s/<[^>]*>//g")" ;;
    *) exit 1 ;;
esac
[[ "$3" == xml1 ]] && v="<plist>$v</plist>"
printf "%s\n" "$v"'
# shellcheck disable=SC2016
stub systemctl 'case "$4" in KillMode) echo "${STUB_KILLMODE:-control-group}" ;; Restart) echo on-failure ;; esac'
export PATH="$tmp/bin:/usr/bin:/bin"

printf 'herdr 0.9.6 release binary\n' > "$tmp/fix/asset"
good="$(shasum -a 256 "$tmp/fix/asset" 2>/dev/null | cut -d' ' -f1 || sha256sum "$tmp/fix/asset" | cut -d' ' -f1)"
release_fixture() {  # release_fixture DIGEST [URL]
    local url="${2:-https://github.com/herdrdev/herdr/releases/download/v0.9.6/herdr-macos-aarch64}"
    cat > "$tmp/fix/release.json" <<EOF
{"tag_name": "v0.9.6", "assets": [
  {"name": "herdr-linux-x86_64", "digest": "sha256:$(printf '0%.0s' {1..64})", "browser_download_url": "https://github.com/herdrdev/herdr/releases/download/v0.9.6/herdr-linux-x86_64"},
  {"name": "herdr-macos-aarch64", "digest": $1, "browser_download_url": "$url"}
]}
EOF
}

# shellcheck source=./ui.sh disable=SC1091
. "$LIB_DIR/ui.sh"
# shellcheck source=./herdr.sh disable=SC1091
. "$LIB_DIR/herdr.sh"
DEST="$HOME/.local/bin/herdr"

# --- herdr_asset ------------------------------------------------------------
[[ "$(herdr_asset Darwin arm64)" == herdr-macos-aarch64 ]] || fail "Darwin arm64"
[[ "$(herdr_asset Darwin x86_64)" == herdr-macos-x86_64 ]] || fail "Darwin x86_64"
[[ "$(herdr_asset Linux aarch64)" == herdr-linux-aarch64 ]] || fail "Linux aarch64"
[[ "$(herdr_asset Linux amd64)" == herdr-linux-x86_64 ]] || fail "Linux amd64"
herdr_asset FreeBSD x86_64 >/dev/null && fail "FreeBSD has no asset"
herdr_asset Linux riscv64 >/dev/null && fail "riscv64 has no asset"
[[ "$(STUB_OS=Darwin STUB_ARCH=x86_64 STUB_ARM64=1 herdr_asset)" == herdr-macos-aarch64 ]] \
    || fail "a shell under Rosetta on Apple silicon should get the native build"
[[ "$(STUB_OS=Linux STUB_ARCH=x86_64 herdr_asset)" == herdr-linux-x86_64 ]] || fail "uname on Linux"
pass "herdr_asset maps OS and architecture to the release asset (and sees through Rosetta)"

# --- release_install --------------------------------------------------------
release_fixture "\"sha256:$good\""
: > "$log"
DRY_RUN=true release_install herdrdev/herdr latest herdr-macos-aarch64 "$DEST" >/dev/null || fail "dry run failed"
[[ -e "$DEST" ]] && fail "dry run wrote $DEST"
grep -q '^curl' "$log" && fail "dry run reached the network"
pass "dry run: no download, nothing written"

release_install herdrdev/herdr latest herdr-macos-aarch64 "$DEST" >/dev/null || fail "install failed"
cmp -s "$DEST" "$tmp/fix/asset" || fail "installed binary differs from the asset"
[[ -x "$DEST" && ! -L "$DEST" ]] || fail "not an executable file"
[[ "$RELEASE_TAG" == v0.9.6 ]] || fail "RELEASE_TAG: $RELEASE_TAG"
grep -q 'curl .*api.github.com/repos/herdrdev/herdr/releases/latest' "$log" || fail "latest not asked of the API"
pass "verified download replaces DEST and reports the tag"

printf 'previous\n' > "$DEST"
release_fixture "\"sha256:$(printf 'a%.0s' {1..64})\""
out="$(release_install herdrdev/herdr latest herdr-macos-aarch64 "$DEST" 2>&1)" && fail "a checksum mismatch was accepted"
[[ "$out" == *"checksum mismatch"* ]] || fail "mismatch message: $out"
[[ "$(cat "$DEST")" == previous ]] || fail "a mismatch touched DEST"
[[ -z "$(find "$HOME/.local/bin" -name '.herdr-*')" ]] || fail "a mismatch left its temp file"
pass "digest mismatch refused, DEST untouched, temp file removed"

release_fixture null
out="$(release_install herdrdev/herdr latest herdr-macos-aarch64 "$DEST" 2>&1)" && fail "an asset without a digest was installed"
[[ "$out" == *"refusing to install it unverified"* ]] || fail "no-digest message: $out"
release_fixture "\"sha256:$good\"" "https://example.com/herdr"
release_install herdrdev/herdr latest herdr-macos-aarch64 "$DEST" >/dev/null 2>&1 && fail "a download outside the release was accepted"
[[ "$(cat "$DEST")" == previous ]] || fail "a refused install touched DEST"
: > "$log"
release_fixture "\"sha256:$good\""
release_install herdrdev/herdr v0.9.6 herdr-macos-aarch64 "$DEST" >/dev/null || fail "pinned install"
grep -q 'releases/tags/v0.9.6' "$log" || fail "a pinned tag should ask for that tag"
pass "no digest or a foreign URL refused; a pinned tag asks for that release"

# Ctrl-C mid-download: the temp file goes, DEST stays, and the shell still
# dies of the signal (no trap of its own) or runs its own trap (one set).
# A job started with SIGINT ignored (a CI or fleet runner) can't trap or
# receive it, so the case only runs where SIGINT is deliverable.
if [[ "$(trap -p INT)" == *"''"* ]]; then
    echo "SKIP: SIGINT is ignored in this environment; interrupted-download case not run"
else
    printf 'previous\n' > "$DEST"
    rc=0; ( STUB_CURL_INT=1 release_install herdrdev/herdr latest herdr-macos-aarch64 "$DEST" >/dev/null 2>&1; echo survived ) > "$tmp/int.out" || rc=$?
    [[ $rc -eq 130 ]] || fail "an interrupted download should end the shell by SIGINT (status $rc)"
    grep -q survived "$tmp/int.out" && fail "the shell carried on after Ctrl-C"
    [[ -z "$(find "$HOME/.local/bin" -name '.herdr-*')" ]] || fail "an interrupted download left its temp file"
    [[ "$(cat "$DEST")" == previous ]] || fail "an interrupted download touched DEST"
    : > "$tmp/trap.out"; export TRAP_LOG="$tmp/trap.out"
    out="$(trap 'echo caller-trap >> "$TRAP_LOG"' INT
        STUB_CURL_INT=1 release_install herdrdev/herdr latest herdr-macos-aarch64 "$DEST" >/dev/null 2>&1 || echo "rc=$?"
        trap -p INT)"
    [[ "$(cat "$tmp/trap.out")" == caller-trap ]] || fail "the caller's INT trap did not run: $(cat "$tmp/trap.out")"
    [[ "$out" == "rc=1"*"trap -- 'echo caller-trap"* ]] || fail "the caller's INT trap should be back: $out"
    [[ -z "$(find "$HOME/.local/bin" -name '.herdr-*')" ]] || fail "temp file left under a caller trap"
    out="$(trap 'echo t' TERM; release_install herdrdev/herdr latest herdr-macos-aarch64 "$DEST" >/dev/null; trap -p TERM; trap -p INT)"
    [[ "$out" == "trap -- 'echo t' SIGTERM" ]] || fail "traps not restored after a download: $out"
    pass "an interrupted download removes its temp file, leaves DEST, and re-raises the signal; the caller's traps come back"
fi

# --- herdr_server_pids ------------------------------------------------------
STUB_PS="  700 herdr server
  701 /Users/NAME/.local/bin/herdr --session work server
  702 herdr server --session=work
  703 herdr server stop
  704 herdr --session work server stop
  705 herdr server --handoff-import /tmp/h.sock tok
  706 /opt/server/bin/herdr
  707 herdr
  708 vim herdr server
  709 herdr --session server" 
export STUB_PS
[[ "$(herdr_server_pids | tr '\n' ' ')" == "700 701 702 705 " ]] || fail "server pids: $(herdr_server_pids | tr '\n' ' ')"
unset STUB_PS
pass "herdr_server_pids finds plain, --session and handoff servers; not clients, stop commands or a path named server"

# --- herdr_install_kind -----------------------------------------------------
keg="$tmp/brew/Cellar/herdr/0.9.5/bin"; mkdir -p "$keg" "$tmp/brew/bin" "$tmp/other"
printf 'brew herdr\n' > "$keg/herdr"; chmod +x "$keg/herdr"
ln -s ../Cellar/herdr/0.9.5/bin/herdr "$tmp/brew/bin/herdr"
rm -f "$DEST"
[[ "$(herdr_install_kind)" == none ]] || fail "none: $(herdr_install_kind)"
[[ "$(PATH="$tmp/brew/bin:$PATH" herdr_install_kind)" == brew ]] || fail "Homebrew's herdr on PATH is brew"
ln -s "$tmp/brew/bin/herdr" "$DEST"
[[ "$(herdr_install_kind)" == brew ]] || fail "a link into the keg is brew: $(herdr_install_kind)"
rm -f "$DEST"; printf 'x\n' > "$tmp/other/herdr"; ln -s "$tmp/other/herdr" "$DEST"
[[ "$(herdr_install_kind)" == other ]] || fail "a link elsewhere is other"
rm -f "$DEST"; cp "$tmp/fix/asset" "$DEST"
[[ "$(herdr_install_kind)" == direct ]] || fail "a file is direct"
herdr_is_brew_binary /opt/homebrew/bin/herdr || fail "/opt/homebrew/bin/herdr names Homebrew's, linked or not"
pass "herdr_install_kind tells direct, brew, other and none apart"

# --- herdr_ensure_direct ----------------------------------------------------
rm -f "$DEST"; ln -s "$tmp/brew/bin/herdr" "$DEST"
tuidev_manifest_enable
out="$(DRY_RUN=true herdr_ensure_direct 2>&1)" || fail "dry ensure: $out"
[[ -L "$DEST" ]] || fail "dry run replaced the link"
[[ -f "$TUIDEV_MANIFEST_FILE" ]] && grep -q herdr "$TUIDEV_MANIFEST_FILE" && fail "dry run recorded"
herdr_ensure_direct >/dev/null || fail "ensure over the Homebrew link"
[[ -f "$DEST" && ! -L "$DEST" ]] && cmp -s "$DEST" "$tmp/fix/asset" || fail "the link was not replaced by the release binary"
[[ -x "$keg/herdr" ]] || fail "Homebrew's binary must stay"
grep -qx "tool $DEST" "$TUIDEV_MANIFEST_FILE" || fail "binary not recorded in the manifest as a tool"
grep -qx "file $DEST" "$TUIDEV_MANIFEST_FILE" && fail "binary recorded as a file (uninstall would remove it unasked)"
tuidev_manifest_disable
: > "$log"
out="$(herdr_ensure_direct)" || fail "ensure on a direct install"
[[ "$out" == *"release binary at"* ]] && ! grep -q '^curl' "$log" || fail "a direct install was downloaded again"
pass "ensure replaces the Homebrew link (Homebrew's keg kept), records it, and leaves a direct install alone"

# --- herdr_self_update ------------------------------------------------------
# The direct binary logs its arguments and whether stdin is closed.
cat > "$DEST" <<EOF
#!/bin/bash
if read -r -t 1 _; then s=open; else s=closed; fi
echo "herdr \$* stdin=\$s" >> "$log"
EOF
chmod +x "$DEST"
server="  700 herdr server"
: > "$log"; STUB_PS="$server" herdr_self_update >/dev/null
grep -qx 'herdr update --handoff stdin=closed' "$log" || fail "server running: $(cat "$log")"
: > "$log"; STUB_PS="  701 herdr" herdr_self_update >/dev/null
grep -qx 'herdr update stdin=closed' "$log" || fail "no server (a client only): $(cat "$log")"
: > "$log"; HERDR_ENV=1 STUB_PS="$server" herdr_self_update >/dev/null
grep -q '^herdr' "$log" && fail "ran inside a Herdr pane"
: > "$log"; out="$(DRY_RUN=true STUB_PS="$server" herdr_self_update)"
[[ "$out" == *"$DEST update --handoff"* ]] && ! grep -q '^herdr' "$log" || fail "dry run: $out"
pass "self update: --handoff with a server, plain without, never inside Herdr, stdin closed, dry run prints"

# A server launchd runs with KeepAlive true: no handoff until the plist allows it.
mkdir -p "$HOME/Library/LaunchAgents"
plist="$HOME/Library/LaunchAgents/com.example.herdr.plist"
cat > "$plist" <<'EOF'
<plist version="1.0"><dict>
  <key>Label</key><string>com.example.herdr</string>
  <key>KeepAlive</key>
  <true/>
  <key>ProgramArguments</key><array><string>/bin/zsh</string><string>-lc</string><string>exec herdr server</string></array>
</dict></plist>
EOF
: > "$log"; out="$(STUB_PS="$server" STUB_LAUNCHCTL=$'700\t0\tcom.example.herdr' herdr_self_update 2>&1)"
grep -qx 'herdr update stdin=closed' "$log" || fail "KeepAlive job: expected plain update: $(cat "$log")"
[[ "$out" == *"launchd job com.example.herdr"*"AbandonProcessGroup"* ]] || fail "KeepAlive job message: $out"
sed -i.bak 's#<true/>#<dict><key>SuccessfulExit</key><false/></dict><key>AbandonProcessGroup</key><true/>#' "$plist" && rm -f "$plist.bak"
STUB_LAUNCHCTL=$'700\t0\tcom.example.herdr' herdr_handoff_blocker 700 >/dev/null \
    && fail "a job with SuccessfulExit false and AbandonProcessGroup is safe"
herdr_handoff_blocker 700 >/dev/null && fail "a server launchd doesn't run is not supervised"
pass "a launchd job with KeepAlive true blocks the handoff; SuccessfulExit false + AbandonProcessGroup allow it"

# Any other KeepAlive dictionary restarts a job that exits (SuccessfulExit
# true: a clean exit, the old server's in a handoff): it blocks, and the
# note says so. KeepAlive false, or none, is safe with AbandonProcessGroup.
safe_plist="$(cat "$plist")"
keepalive() {  # keepalive XML: the plist's KeepAlive value, AbandonProcessGroup true
    printf '<plist version="1.0"><dict>\n  <key>Label</key><string>com.example.herdr</string>\n%s  <key>AbandonProcessGroup</key><true/>\n  <key>ProgramArguments</key><array><string>%s</string><string>server</string></array>\n</dict></plist>\n' \
        "${1:+  <key>KeepAlive</key>$1
}" "$DEST" > "$plist"
}
for ka in '<dict><key>SuccessfulExit</key><true/></dict>' '<dict><key>Crashed</key><true/></dict>' \
          '<dict><key>Crashed</key><true/><key>SuccessfulExit</key><true/></dict>' '<true/>'; do
    keepalive "$ka"
    STUB_LAUNCHCTL=$'700\t0\tcom.example.herdr' herdr_handoff_blocker 700 >/dev/null || fail "KeepAlive $ka is not safe for a handoff"
    [[ "$(herdr_service_note "$plist" 2>&1)" == *"before a live handoff, set KeepAlive"* ]] || fail "no note for KeepAlive $ka"
done
for ka in '<dict><key>SuccessfulExit</key><false/></dict>' '<dict><key>Crashed</key><true/><key>SuccessfulExit</key><false/></dict>' '<false/>' ''; do
    keepalive "$ka"
    STUB_LAUNCHCTL=$'700\t0\tcom.example.herdr' herdr_handoff_blocker 700 >/dev/null && fail "KeepAlive '$ka' with AbandonProcessGroup is safe"
    [[ "$(herdr_service_note "$plist" 2>&1)" != *"before a live handoff"* ]] || fail "a note for the safe KeepAlive '$ka'"
done
printf '%s\n' "$safe_plist" > "$plist"
pass "a launchd KeepAlive dictionary is safe only with SuccessfulExit false; false or no KeepAlive is; the note agrees"

# systemd: the default KillMode would take the panes down with the old server.
mkdir -p "$tmp/proc/700"; export _HERDR_PROC="$tmp/proc"
printf '0::/user.slice/user-1000.slice/user@1000.service/app.slice/herdr.service\n' > "$tmp/proc/700/cgroup"
why="$(STUB_OS=Linux herdr_handoff_blocker 700)" || fail "control-group KillMode should block"
[[ "$why" == *"herdr.service"*"KillMode=process"* ]] || fail "systemd message: $why"
STUB_OS=Linux STUB_KILLMODE=process herdr_handoff_blocker 700 >/dev/null && fail "KillMode=process is safe"
printf '0::/user.slice/user-1000.slice/session-3.scope\n' > "$tmp/proc/700/cgroup"
STUB_OS=Linux herdr_handoff_blocker 700 >/dev/null && fail "a server in a login session is not supervised"
pass "a systemd unit blocks the handoff unless KillMode=process; a login-session server doesn't"

# --- the migration ----------------------------------------------------------
run_migration() { HOMEBREW_PREFIX="$tmp/brew" STUB_PS="$server" bash "$MIGRATION" 2>&1; }
rm -f "$DEST" "$TUIDEV_MANIFEST_FILE"; ln -s "$tmp/brew/bin/herdr" "$DEST"
printf 'profile=desktop\nextra_packs=tmux\n' > "$TUIDEV_STATE_DIR/profile"
run_migration >/dev/null || fail "migration without the pack"
[[ -L "$DEST" ]] || fail "acted without the herdr pack"
printf 'profile=desktop\nextra_packs=tmux herdr\n' > "$TUIDEV_STATE_DIR/profile"
before="$(cat "$plist")"
: > "$log"; out="$(DRY_RUN=true run_migration)" || fail "dry migration: $out"
[[ -L "$DEST" && ! -f "$TUIDEV_MANIFEST_FILE" ]] && ! grep -q '^curl' "$log" || fail "dry migration changed something"
out="$(run_migration)" || fail "migration: $out"
[[ -f "$DEST" && ! -L "$DEST" ]] || fail "migration did not install the release binary"
grep -qx "tool $DEST" "$TUIDEV_MANIFEST_FILE" || fail "migration did not record the binary"
[[ "$(cat "$plist")" == "$before" ]] || fail "migration edited the user's LaunchAgent"
[[ "$out" == *"brew uninstall herdr"* ]] || fail "no cutover hint: $out"
grep -q '^brew\|^launchctl .*\(unload\|bootout\|load\)' "$log" && fail "migration ran brew or changed launchd: $(cat "$log")"
: > "$log"; out="$(run_migration)" || fail "second run: $out"
grep -q '^curl' "$log" && fail "second run downloaded again"
pass "migration: only with the pack, dry run changes nothing, installs and records once, never edits the plist, runs no brew or launchctl load"

rm -rf "$tmp/brew/Cellar/herdr"
: > "$log"; out="$(run_migration)"
[[ -z "$out" ]] && ! grep -q '^curl' "$log" || fail "nothing left to do should be silent: $out"
pass "migration is a no-op once the direct install is in place and Homebrew's is gone"

# --- update.sh --packages ---------------------------------------------------
# No package manager on this PATH: Herdr still updates, by itself, never brew.
export TUIDEV_REPO="$tmp/repo"; git init -q "$TUIDEV_REPO"
cat > "$DEST" <<EOF2
#!/bin/bash
case "\$1" in --version) echo "herdr 0.9.6" ;; *) echo "herdr \$*" >> "$log" ;; esac
EOF2
chmod +x "$DEST"
: > "$log"; out="$(STUB_PS="$server" STUB_OS=Linux bash "$LIB_DIR/../update.sh" --check < /dev/null 2>&1)" || fail "update --check: $out"
[[ "$out" == *"herdr"*"0.9.6, release binary"* ]] && ! grep -q '^herdr update' "$log" || fail "--check: $out"
: > "$log"; out="$(STUB_PS="$server" STUB_OS=Linux bash "$LIB_DIR/../update.sh" --packages --yes < /dev/null 2>&1)" || fail "update --packages: $out"
grep -qx 'herdr update --handoff' "$log" || fail "--packages did not hand off: $(cat "$log") $out"
grep -q '^brew' "$log" && fail "--packages ran brew"
pass "update.sh: --check reports the release binary, --packages runs herdr update --handoff"

# A Homebrew herdr: --check names the switch, --packages makes it (retryable).
mkdir -p "$keg"; printf 'brew herdr\n' > "$keg/herdr"; chmod +x "$keg/herdr"
rm -f "$DEST"; ln -s "$tmp/brew/bin/herdr" "$DEST"
: > "$log"; out="$(HOMEBREW_PREFIX="$tmp/brew" STUB_OS=Linux bash "$LIB_DIR/../update.sh" --check < /dev/null 2>&1)" || fail "update --check (brew): $out"
[[ "$out" == *"--packages installs the release binary"* && -L "$DEST" ]] && ! grep -q '^curl' "$log" || fail "--check on Homebrew's herdr: $out"
[[ "$out" == *"--migrations"* ]] && fail "--check points at --migrations, which can't retry: $out"
release_fixture "\"sha256:$(printf 'a%.0s' {1..64})\""
out="$(HOMEBREW_PREFIX="$tmp/brew" bash "$LIB_DIR/../update.sh" --packages --yes < /dev/null 2>&1)" || fail "update --packages (failed download): $out"
[[ -L "$DEST" && "$out" == *"checksum mismatch"*"tries again"* ]] || fail "a failed switch: $out"
release_fixture "\"sha256:$good\""
out="$(HOMEBREW_PREFIX="$tmp/brew" bash "$LIB_DIR/../update.sh" --packages --yes < /dev/null 2>&1)" || fail "update --packages (brew): $out"
[[ -f "$DEST" && ! -L "$DEST" ]] && cmp -s "$DEST" "$tmp/fix/asset" || fail "--packages did not switch to the release binary: $out"
grep -qx "tool $DEST" "$TUIDEV_MANIFEST_FILE" || fail "--packages did not record the binary"
[[ "$out" == *"brew uninstall herdr"* ]] && ! grep -q '^brew' "$log" || fail "switch: no cutover hint, or ran brew: $out"
pass "update.sh: Homebrew's herdr is switched by --packages (a failed download retried next run); --check says so"

# A broken binary can't abort update.sh.
printf '#!/bin/sh\nexit 1\n' > "$DEST"; chmod +x "$DEST"
out="$(STUB_OS=Linux bash "$LIB_DIR/../update.sh" --check < /dev/null 2>&1)" || fail "a broken herdr aborted update --check: $out"
[[ "$out" == *"herdr"*"(unknown, release binary"* ]] || fail "broken binary: $out"
pass "update.sh survives a herdr that fails --version"

# --- health_check.sh: HERDR_LOG_WARN_MB -------------------------------------
eval "$(sed -n '/^check_herdr_logs() {/,/^}/p' "$LIB_DIR/../health_check.sh")"
mkdir -p "$tmp/herdrcfg"; head -c 2097152 /dev/zero > "$tmp/herdrcfg/herdr-server.log"
for bad in 50MB abc ""; do
    out="$(set -u; OPT_WARN=0; HERDR_CONFIG_DIR="$tmp/herdrcfg" HERDR_LOG_WARN_MB="$bad" check_herdr_logs 2>&1; echo "end $OPT_WARN")" \
        || fail "HERDR_LOG_WARN_MB=$bad aborted: $out"
    [[ "$out" == "end 0" ]] || fail "HERDR_LOG_WARN_MB=$bad should fall back to 50: $out"
done
out="$(OPT_WARN=0; HERDR_CONFIG_DIR="$tmp/herdrcfg" HERDR_LOG_WARN_MB=1 check_herdr_logs 2>&1; echo "end $OPT_WARN")"
[[ "$out" == *"herdr-server.log 2M"*"end 1" ]] || fail "a 2 MB log over a 1 MB bar: $out"
pass "check_herdr_logs: a bad HERDR_LOG_WARN_MB falls back to 50 instead of aborting"

# --- health_check.sh: outdated integrations ---------------------------------
# Only a plain name goes into the suggested command: never shell syntax, never
# a word the shell would glob.
eval "$(sed -n '/^check_herdr_upgrade() {/,/^}/p' "$LIB_DIR/../health_check.sh")"
mkdir -p "$tmp/hc/bin" "$tmp/hc/cwd"; : > "$tmp/hc/cwd/GLOBBED"
cat > "$tmp/hc/bin/herdr" <<'EOF2'
#!/bin/bash
[[ "$1 $2" == "integration status" ]] && printf '%s\n' "claude: outdated" "pi (experimental): outdated" '$(touch x): outdated' "*: outdated" "codex: current"
exit 0
EOF2
chmod +x "$tmp/hc/bin/herdr"
out="$(cd "$tmp/hc/cwd" && OPT_WARN=0 PATH="$tmp/hc/bin:$PATH" HERDR_CONFIG_DIR="$tmp/hc" check_herdr_upgrade 2>&1)"
[[ "$out" == *"herdr integrations outdated: claude pi (run: herdr integration install claude; herdr integration install pi)"* \
    && "$out" != *"\$("* && "$out" != *GLOBBED* ]] || fail "outdated integration names: $out"
pass "check_herdr_upgrade: only plain integration names reach the suggested command"

# --- uninstall.sh -----------------------------------------------------------
# The binary is a tool: never removed in the helpers step, only when asked,
# and never while a server runs from it (or can't be told apart from it).
cp "$tmp/fix/asset" "$DEST"
uninstall() {  # uninstall MANIFEST-RECORDS [ARGS...] (stdin: the answers)
    local records="$1"; shift
    mkdir -p "$TUIDEV_STATE_DIR"; printf '%s\n' "$records" > "$TUIDEV_MANIFEST_FILE"
    STUB_OS=Linux bash "$LIB_DIR/../../uninstall.sh" "$@" 2>&1
}
printf '#!/bin/sh\n' > "$HOME/.local/bin/notify.sh"
out="$(printf 'ynnn' | uninstall "file $DEST
file $HOME/.local/bin/notify.sh")" || fail "uninstall (legacy record, declined): $out"
[[ ! -e "$HOME/.local/bin/notify.sh" ]] || fail "helpers step skipped notify.sh"
[[ -f "$DEST" && "$out" == *"kept $DEST (rm $DEST removes it)"* ]] || fail "a legacy file record removed herdr unasked: $out"
pass "uninstall: a herdr recorded as a file (older installs) is a tool too; declining keeps it and prints rm"

mkdir -p "$tmp/proc/700"; ln -sfn "$DEST" "$tmp/proc/700/exe"
out="$(STUB_PS="$server" uninstall "tool $DEST" --all < /dev/null)" || fail "uninstall (server running): $out"
[[ -f "$DEST" && "$out" == *"a Herdr server runs from it"*"rm $DEST"* ]] || fail "removed the binary a server runs: $out"
rm -f "$tmp/proc/700/exe"
out="$(STUB_PS="$server" uninstall "tool $DEST" --all < /dev/null)" || fail "uninstall (server, exe unknown): $out"
[[ -f "$DEST" ]] || fail "removed the binary while a server's binary was unknown"
ln -sfn "$keg/herdr" "$tmp/proc/700/exe"
out="$(STUB_PS="$server" uninstall "tool $DEST" --dry-run --all < /dev/null)" || fail "uninstall --dry-run: $out"
[[ -f "$DEST" && "$out" == *"rm -f $DEST"* ]] || fail "dry run: $out"
out="$(STUB_PS="$server" uninstall "tool $DEST" --all < /dev/null)" || fail "uninstall (server on another binary): $out"
[[ ! -e "$DEST" && -x "$keg/herdr" ]] || fail "uninstall --all kept an unused binary, or touched Homebrew's: $out"
pass "uninstall: removes the binary only when asked and no server runs from it (or can't tell); prints rm otherwise"
