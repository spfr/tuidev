#!/bin/bash
# Tests for bin/secret: every command on each backend (Keychain, secret-tool,
# pass), hostile names and values, import --remove and its backup, scan, the
# install, and what happens with no store at all.
# Run: bash scripts/lib/test_secret.sh  -> exit 0 on pass (also under /bin/bash).
#
# Nothing real is touched: a throwaway HOME, fake security / secret-tool / pass
# that keep their items in that HOME, and a PATH of logging wrappers only, so
# no real store can be reached by accident. Every external command records its
# argv, and no value may ever appear there.
#
# shellcheck disable=SC2015,SC2016,SC2012  # `a && b || fail` checks; shell code in single quotes on purpose; ls -l for modes

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
SECRET="$REPO_DIR/bin/secret"
SH="$BASH"   # the bash under test (CI also runs these under /bin/bash, 3.2)

tmp="$(mktemp -d "${TMPDIR:-/tmp}/tuidev-secret.XXXXXX")"
tmp="$(cd "$tmp" && pwd)"
trap '/bin/chmod -R u+rwx "$tmp" 2>/dev/null; /bin/rm -rf "$tmp"' EXIT

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "PASS: $1"; }

# Locate the real tools before PATH is narrowed.
real() { command -v "$1" || fail "test needs $1"; }
REAL_PATH="$PATH"
REAL_od="$(real od)" REAL_tr="$(real tr)" REAL_sort="$(real sort)" REAL_awk="$(real awk)" REAL_sed="$(real sed)"
REAL_date="$(real date)" REAL_wc="$(real wc)" REAL_cat="$(real cat)" REAL_env="$(real env)"
export REAL_sort REAL_awk REAL_sed REAL_date REAL_wc REAL_cat REAL_env   # read through ${!ref} below

export HOME="$tmp/home dir" FAKE_DIR="$tmp/fake"
export TUIDEV_SECRET_SECURITY="$tmp/fakes/security"   # never /usr/bin/security
export PASSWORD_STORE_DIR="$HOME/.password-store"
mkdir -p "$HOME" "$FAKE_DIR" "$tmp/sys" "$tmp/fakes" "$tmp/plat"
ARGV_LOG="$FAKE_DIR/argv.log"
: > "$ARGV_LOG"
unset TUIDEV_SECRET_BACKEND DBUS_SESSION_BUS_ADDRESS XDG_RUNTIME_DIR LC_ALL

# --- PATH: logging wrappers around the real tools -----------------------------
# sys/ holds the tools secret may run, each logging its argv first; fakes/ the
# secret stores; plat/ a uname that says what FAKE_UNAME says.
for t in od tr sort awk sed date wc cat env; do
    ref="REAL_$t"
    cat > "$tmp/sys/$t" <<EOF
#!/bin/bash
{ printf '%s' "$t"; printf ' [%s]' "\$@"; printf '\n'; } >> "\$FAKE_DIR/argv.log"
exec "${!ref}" "\$@"
EOF
done
ln -s "$SH" "$tmp/sys/bash"
cat > "$tmp/plat/uname" <<'EOF'
#!/bin/bash
{ printf 'uname'; printf ' [%s]' "$@"; printf '\n'; } >> "$FAKE_DIR/argv.log"
printf '%s\n' "${FAKE_UNAME:-Linux}"
EOF

# A fake `security`: generic passwords as files keychain/<service>.<account>.
# Like the real one, it prints a value with bytes outside printable ASCII as hex.
cat > "$tmp/fakes/security" <<'EOF'
#!/bin/bash
PATH=/usr/bin:/bin
{ printf 'security'; printf ' [%s]' "$@"; printf '\n'; } >> "$FAKE_DIR/argv.log"
store="$FAKE_DIR/keychain"; mkdir -p "$store"
unhex() { local h="$1" o="" c i; for ((i = 0; i < ${#h}; i += 2)); do printf -v c '\\0%03o' "$((16#${h:i:2}))"; o+="$c"; done; printf '%b' "$o"; }
op() {
    local sub="$1" a="" s="" x="" w=false; shift
    while (( $# )); do
        case "$1" in
            -a) a="$2"; shift 2 ;; -s) s="$2"; shift 2 ;; -X) x="$2"; shift 2 ;;
            -l) printf '%s\n' "$2" >> "$FAKE_DIR/labels"; shift 2 ;; -D) printf '%s\n' "$2" >> "$FAKE_DIR/kinds"; shift 2 ;;
            -w) w=true; shift ;; *) shift ;;
        esac
    done
    local f="$store/$s.$a"
    case "$sub" in
        add-generic-password)
            [[ -n "$FAKE_FAIL_PUT" && "$a" == "$FAKE_FAIL_PUT" ]] && { echo "fake: refused" >&2; return 1; }
            [[ -n "$x" ]] || { echo "fake: -X only, please" >&2; return 1; }
            unhex "$x" > "$f" ;;
        find-generic-password)
            [[ -f "$f" ]] || return 44
            [[ -n "$FAKE_LOCKED" ]] && return 51
            local v; v="$(cat "$f"; printf x)"; v="${v%x}"
            if LC_ALL=C; [[ "$v" == *[!\ -~]* ]]; then printf '%s' "$v" | od -An -v -tx1 | tr -d ' \n'; echo
            else printf '%s\n' "$v"; fi ;;
        delete-generic-password)
            [[ -f "$f" ]] || return 44
            rm -f "$f" ;;
        dump-keychain)
            for f in "$store"/*; do
                [[ -f "$f" ]] || continue
                local b="${f##*/}"
                printf 'keychain: "/fake/login.keychain-db"\nversion: 512\nclass: "genp"\nattributes:\n'
                printf '    "acct"<blob>="%s"\n    "svce"<blob>="%s"\n' "${b#*.}" "${b%%.*}"
            done
            printf 'keychain: "/fake/login.keychain-db"\nclass: "inet"\nattributes:\n    "acct"<blob>="WRONG_CLASS"\n    "svce"<blob>="tuidev"\n' ;;
        *) echo "fake security: $sub?" >&2; return 1 ;;
    esac
}
[[ "$1" == -q ]] && shift
if [[ "$1" == -i ]]; then
    while IFS= read -r line; do
        read -ra args <<< "$line"
        op "${args[@]}" || exit 0   # like the real one: -i exits 0
    done
    exit 0
fi
op "$@"
EOF

# A fake secret-tool: items as files st/<service>.<name>. `search` prints the
# secret too, as the real one does.
cat > "$tmp/fakes/secret-tool" <<'EOF'
#!/bin/bash
PATH=/usr/bin:/bin
{ printf 'secret-tool'; printf ' [%s]' "$@"; printf '\n'; } >> "$FAKE_DIR/argv.log"
store="$FAKE_DIR/st"; mkdir -p "$store"
sub="$1"; shift
[[ "$sub" == store ]] && shift   # --label=...
[[ "$sub" == search ]] && shift  # --all
svc="$2" name="$4"
case "$sub" in
    store) [[ -n "$FAKE_FAIL_PUT" && "$name" == "$FAKE_FAIL_PUT" ]] && exit 1; cat > "$store/$svc.$name" ;;
    lookup) [[ -f "$store/$svc.$name" ]] || exit 1; cat "$store/$svc.$name" ;;
    clear) rm -f "$store/$svc.$name" ;;
    search)
        for f in "$store/$svc".*; do
            [[ -f "$f" ]] || continue
            printf '[/org/freedesktop/secrets/collection/login/1]\nlabel = x\nsecret = %s\nattribute.name = %s\nattribute.service = %s\n' "$(cat "$f")" "${f##*/$svc.}" "$svc"
        done ;;
esac
EOF

# A fake pass: entries as plain files under $PASSWORD_STORE_DIR/<path>.gpg.
cat > "$tmp/fakes/pass" <<'EOF'
#!/bin/bash
PATH=/usr/bin:/bin
{ printf 'pass'; printf ' [%s]' "$@"; printf '\n'; } >> "$FAKE_DIR/argv.log"
sub="$1"; shift
while [[ "$1" == -* ]]; do shift; done
f="$PASSWORD_STORE_DIR/$1.gpg"
case "$sub" in
    insert) [[ -n "$FAKE_FAIL_PUT" && "$1" == */"$FAKE_FAIL_PUT" ]] && exit 1; mkdir -p "${f%/*}"; cat > "$f" ;;
    show) [[ -f "$f" ]] || { echo "Error: $1 is not in the password store." >&2; exit 1; }; cat "$f" ;;
    rm) rm -f "$f" ;;
esac
EOF
chmod +x "$tmp/sys"/* "$tmp/plat"/* "$tmp/fakes"/*

FAKES_PATH="$tmp/fakes:$tmp/plat:$tmp/sys"
run_secret() { PATH="${SPATH:-$FAKES_PATH}" "$SH" "$SECRET" "$@"; }
[[ "$(PATH="$FAKES_PATH" type -P security || true)" == "$tmp/fakes/security" ]] || fail "the fake security is not first on PATH"
[[ "$(PATH="$FAKES_PATH" type -P pass || true)" == "$tmp/fakes/pass" ]] || fail "the fake pass is not first on PATH"

# s ARGS...: run secret; stdout and stderr to $tmp/out and $tmp/err; sets rc.
s() { rc=0; run_secret "$@" > "$tmp/out" 2> "$tmp/err" || rc=$?; }
# set_value NAME (value on stdin)
set_value() { rc=0; run_secret set "$1" > "$tmp/out" 2> "$tmp/err" || rc=$?; }
out() { cat "$tmp/out"; }
err() { cat "$tmp/err"; }
# The exact value of `secret get` (its trailing newline dropped, any other kept).
got() { local v; v="$(run_secret get "$1"; printf x)"; v="${v%x}"; printf '%s' "${v%$'\n'}"; }
no_value_in_argv() {
    local v="$1" label="$2" hex
    if LC_ALL=C grep -qF -- "$v" "$ARGV_LOG"; then
        fail "$label: the value reached an external command's argv"
    fi
    hex="$(printf '%s' "$v" | "$REAL_od" -An -v -tx1 | "$REAL_tr" -d ' \n')"
    if (( ${#hex} >= 8 )) && LC_ALL=C grep -qiF -- "$hex" "$ARGV_LOG"; then
        fail "$label: the value's hex reached an external command's argv"
    fi
    return 0
}

# Values that break naive quoting. Each is checked byte for byte.
values=(
    "V1 it's \"quoted\" here"
    'V2 $(touch PWNED) and `touch PWNED` and ${HOME}'
    '  V3 leading and trailing spaces  '
    '-nV4 leading dash'
    'V5 päss–wörd ✓ 鍵'
    'V6 back\slash \\ \n \t %s %% *?[a]'
    'tuidev-hex:V7 looks like our own encoding'
    "V8 tab	inside"
    $'V9 high bytes \xff\xfe\x80'
    'V10 ;|&<>!#~ ^'
)

# ----------------------------------------------------------------------------
for backend in keychain secret-tool pass; do
    export TUIDEV_SECRET_BACKEND="$backend"
    : > "$ARGV_LOG"
    i=0
    for v in "${values[@]}"; do
        i=$((i + 1))
        set_value "HOSTILE_$i" < <(printf '%s\n' "$v")
        [[ $rc -eq 0 ]] || fail "$backend: set value $i (rc=$rc): $(err)"
        [[ "$(got "HOSTILE_$i")" == "$v" ]] || fail "$backend: value $i changed on the way: [$(got "HOSTILE_$i")]"
        if grep -qF -- "${v:0:12}" "$tmp/out" "$tmp/err"; then fail "$backend: set echoed value $i"; fi
    done
    [[ ! -e PWNED && ! -e "$HOME/PWNED" ]] || fail "$backend: a value was executed"
    pass "$backend: hostile values round-trip byte for byte"

    # export: eval its output in a fresh shell, the values come back exactly.
    names=(); for (( j = 1; j <= ${#values[@]}; j++ )); do names+=("HOSTILE_$j"); done
    s export "${names[@]}"
    [[ $rc -eq 0 ]] || fail "$backend: export rc=$rc: $(err)"
    for (( j = 1; j <= ${#values[@]}; j++ )); do
        want="${values[j-1]}"
        have="$(cd "$tmp" && "$SH" -c 'eval "$(cat "$1")"; v="HOSTILE_$2"; printf "%s" "${!v}"' _ "$tmp/out" "$j")"
        [[ "$have" == "$want" ]] || fail "$backend: export/eval changed value $j: [$have]"
    done
    [[ ! -e "$tmp/PWNED" ]] || fail "$backend: eval of export ran a command"
    pass "$backend: eval \"\$(secret export ...)\" assigns the exact values and runs nothing"

    # run: the command sees exactly the value; nothing else gets it.
    for (( j = 1; j <= ${#values[@]}; j++ )); do
        have="$(run_secret run -n "HOSTILE_$j" -- "$SH" -c 'v="HOSTILE_$1"; printf "%s" "${!v}"' _ "$j")"
        [[ "$have" == "${values[j-1]}" ]] || fail "$backend: run passed value $j as [$have]"
    done
    have="$(run_secret run -n HOSTILE_1 -n HOSTILE_5 -- "$SH" -c 'printf "%s|%s|%s" "$HOSTILE_1" "$HOSTILE_5" "${HOSTILE_2-unset}"')"
    [[ "$have" == "${values[0]}|${values[4]}|unset" ]] || fail "$backend: run gave more or less than asked: [$have]"
    have="$(run_secret run --all -- "$SH" -c 'printf "%s" "$HOSTILE_10"')"
    [[ "$have" == "${values[9]}" ]] || fail "$backend: run --all: [$have]"
    pass "$backend: secret run hands the command exactly the secrets named (or --all)"

    for v in "${values[@]}"; do no_value_in_argv "$v" "$backend"; done
    pass "$backend: no value or its hex in any external command's argv"

    # ls: names only, sorted; never a value.
    s ls
    [[ $rc -eq 0 ]] || fail "$backend: ls rc=$rc"
    [[ "$(out)" == "$(printf 'HOSTILE_%s\n' 1 10 2 3 4 5 6 7 8 9)" ]] || fail "$backend: ls printed: $(out)"
    if grep -qF 'V1 it' "$tmp/out"; then fail "$backend: ls printed a value"; fi
    pass "$backend: ls lists names only"

    # Update in place, then rm, then a missing name.
    set_value HOSTILE_1 < <(printf 'second\n')
    [[ $rc -eq 0 && "$(got HOSTILE_1)" == second ]] || fail "$backend: overwrite"
    grep -q 'updated HOSTILE_1' "$tmp/err" || fail "$backend: overwrite not reported: $(err)"
    s rm HOSTILE_1
    [[ $rc -eq 0 ]] || fail "$backend: rm rc=$rc"
    s get HOSTILE_1
    [[ $rc -eq 1 && -z "$(out)" ]] || fail "$backend: get after rm rc=$rc"
    grep -q 'no secret named HOSTILE_1' "$tmp/err" || fail "$backend: missing get message: $(err)"
    s rm HOSTILE_1
    [[ $rc -eq 1 ]] || fail "$backend: rm of a missing name rc=$rc"
    pass "$backend: set updates, rm deletes, a missing name exits 1"

    # run: a missing secret stops the command, unless --optional.
    rm -f "$tmp/ran"
    s run -n HOSTILE_1 -- "$SH" -c ': > "$1"' _ "$tmp/ran"
    [[ $rc -eq 1 && ! -e "$tmp/ran" ]] || fail "$backend: run started its command without a secret (rc=$rc)"
    s run --optional -n HOSTILE_1 -n HOSTILE_2 -- "$SH" -c 'printf "%s|%s" "${HOSTILE_1-unset}" "$HOSTILE_2" > "$1"' _ "$tmp/ran"
    [[ $rc -eq 0 && "$(cat "$tmp/ran")" == "unset|${values[1]}" ]] || fail "$backend: run --optional (rc=$rc): $(cat "$tmp/ran" 2>/dev/null)"
    # export: the ones it has, and exit 1 for the one it doesn't.
    s export HOSTILE_2 HOSTILE_1
    [[ $rc -eq 1 ]] && grep -q '^export HOSTILE_2=' "$tmp/out" && ! grep -q HOSTILE_1 "$tmp/out" \
        || fail "$backend: export with a missing name (rc=$rc): $(out)"
    pass "$backend: run refuses a missing secret (--optional runs anyway); export prints what it has"

    for (( j = 2; j <= ${#values[@]}; j++ )); do run_secret rm "HOSTILE_$j" 2>/dev/null; done
done

# run --all with nothing to add: an empty store runs CMD (nothing to add is no
# error); a listing that fails is a store error (exit 1, not usage), and
# --optional runs CMD anyway.
export TUIDEV_SECRET_BACKEND=pass
PD="$PASSWORD_STORE_DIR/tuidev"; mkdir -p "$PD"
s ls; [[ $rc -eq 0 && -z "$(out)" ]] || fail "pass: the store is not empty for the --all tests: $(out)"
for opt in "" --optional; do
    rm -f "$tmp/ran"
    s run ${opt:+"$opt"} --all -- "$SH" -c ': > "$1"' _ "$tmp/ran"
    [[ $rc -eq 0 && -e "$tmp/ran" ]] || fail "run $opt --all, empty store: rc=$rc, ran: $([[ -e "$tmp/ran" ]] && echo yes || echo no): $(err)"
done
chmod 000 "$PD"
if [[ -r "$PD" ]]; then
    echo "SKIP: a mode 000 directory is readable here (root): the failed listing is not testable"
else
    rm -f "$tmp/ran"
    s run --all -- "$SH" -c ': > "$1"' _ "$tmp/ran"
    [[ $rc -eq 1 && ! -e "$tmp/ran" ]] || fail "run --all, the listing failed: rc=$rc, or CMD ran"
    grep -q 'could not be listed' "$tmp/err" && ! grep -q 'name a secret' "$tmp/err" || fail "run --all, the listing failed: $(err)"
    s run --optional --all -- "$SH" -c ': > "$1"' _ "$tmp/ran"
    [[ $rc -eq 0 && -e "$tmp/ran" ]] || fail "run --optional --all, the listing failed: rc=$rc: $(err)"
    s ls; [[ $rc -eq 1 ]] || fail "ls, the listing failed: rc=$rc"
fi
chmod 700 "$PD"
pass "run --all: an empty store runs CMD; a failed listing stops it (exit 1, a store error), --optional runs it anyway"
unset TUIDEV_SECRET_BACKEND

# ----------------------------------------------------------------------------
# Values: line endings, NUL, empty, and never from argv.
export TUIDEV_SECRET_BACKEND=keychain
set_value A1 < <(printf 'abc\n');   [[ "$(got A1)" == abc ]] || fail "one trailing \\n is dropped"
set_value A2 < <(printf 'abc\r\n'); [[ "$(got A2)" == abc ]] || fail "a trailing \\r\\n is dropped"
set_value A3 < <(printf 'abc');     [[ "$(got A3)" == abc ]] || fail "no line ending"
set_value A4 < <(printf 'a\r');     [[ "$(got A4)" == a ]] || fail "a lone trailing \\r is a line ending too"
set_value B1 < <(printf 'a\nb\n')
[[ $rc -eq 1 ]] && grep -q 'more than one line' "$tmp/err" || fail "a two-line value was not refused (rc=$rc)"
set_value B2 < <(printf 'a\n\n');   [[ $rc -eq 1 ]] || fail "a value ending in a blank line was not refused"
set_value B3 < <(printf 'a\0b')
[[ $rc -eq 1 ]] && grep -q 'NUL' "$tmp/err" || fail "a NUL was not refused (rc=$rc)"
set_value B4 < <(printf '');        [[ $rc -eq 1 ]] || fail "an empty value was not refused"
set_value B5 < <(printf '\n');      [[ $rc -eq 1 ]] || fail "a bare newline was not refused"
: > "$ARGV_LOG"
s set C1 'Sup3rS3cretFromArgv' < /dev/null
[[ $rc -eq 2 ]] && grep -q 'never from arguments' "$tmp/err" || fail "a value in argv was not refused (rc=$rc)"
if grep -q 'Sup3rS3cretFromArgv' "$tmp/err" "$tmp/out" "$ARGV_LOG"; then fail "the argv value was echoed or passed on"; fi
s get C1; [[ $rc -eq 1 ]] || fail "the argv value was stored"
for n in B1 B2 B3 B4 B5; do s get "$n"; [[ $rc -eq 1 ]] || fail "$n was stored despite the refusal"; done
pass "a value is one line: \\n or \\r\\n dropped once; more lines, NUL, empty and argv refused"

# Names: only [A-Za-z_][A-Za-z0-9_]*, for every command that takes one.
for bad in '1ABC' 'A-B' '-n' 'A B' '$(touch PWNED)' 'A;B' 'ÜNI' 'A=B' '../x' ''; do
    for cmd in set get rm export; do
        s "$cmd" "$bad" < /dev/null
        [[ $rc -eq 2 ]] || fail "$cmd accepted the name [$bad] (rc=$rc)"
    done
    s run -n "$bad" -- true;  [[ $rc -eq 2 ]] || fail "run accepted the name [$bad]"
done
[[ ! -e PWNED && ! -e "$tmp/PWNED" ]] || fail "a name was executed"
s get; [[ $rc -eq 2 ]] || fail "get with no name"
s run -n A1; [[ $rc -eq 2 ]] || fail "run without -- CMD"
s run -- true; [[ $rc -eq 2 ]] || fail "run with no secret named"
s frobnicate; [[ $rc -eq 2 ]] || fail "unknown command"
s --help; [[ $rc -eq 0 ]] && grep -q 'secret run' "$tmp/out" || fail "--help"
pass "names are validated everywhere (hostile ones exit 2, nothing runs)"

# Keychain: the decoded prefix and the readback check.
set_value K1 < <(printf 'tuidev-hex:zz\n')
[[ "$(cat "$FAKE_DIR/keychain/tuidev.K1")" == tuidev-hex:* && "$(got K1)" == 'tuidev-hex:zz' ]] || fail "prefix collision"
[[ "$(cat "$FAKE_DIR/keychain/tuidev.A1")" == abc ]] || fail "a plain ASCII value is stored as is"
# In Keychain Access an item is listed under its own name, with the kind "secret".
grep -qx A1 "$FAKE_DIR/labels" && [[ "$(sort -u "$FAKE_DIR/kinds")" == secret ]] || fail "keychain items are not labelled with their name: $(cat "$FAKE_DIR/labels" 2>&1 | head -3)"
FAKE_FAIL_PUT=K2 ; export FAKE_FAIL_PUT
set_value K2 < <(printf 'never\n')
[[ $rc -eq 1 ]] && grep -q 'not stored correctly' "$tmp/err" || fail "a failed Keychain write went unnoticed (rc=$rc): $(err)"
unset FAKE_FAIL_PUT
FAKE_LOCKED=1 s get A1; rc_locked=$rc
[[ $rc_locked -eq 1 ]] && grep -q 'refused to read' "$tmp/err" || fail "a locked Keychain read (rc=$rc_locked): $(err)"
s ls; [[ "$(out)" != *WRONG_CLASS* ]] || fail "ls listed an internet password"
pass "keychain: non-ASCII stored as tuidev-hex:, writes are verified, a refused read is reported"
for n in A1 A2 A3 A4 K1; do run_secret rm "$n" 2>/dev/null; done
unset TUIDEV_SECRET_BACKEND

# ----------------------------------------------------------------------------
# Backend choice: macOS -> Keychain; Linux -> secret-tool with a session bus,
# else pass; nothing -> exit 3 and nothing written.
: > "$ARGV_LOG"
FAKE_UNAME=Darwin set_value PICK < <(printf 'x1234567\n')
grep -q '^security ' "$ARGV_LOG" || fail "macOS did not pick the Keychain"
: > "$ARGV_LOG"
DBUS_SESSION_BUS_ADDRESS=unix:path=/x set_value PICK < <(printf 'x1234567\n')
grep -q '^secret-tool ' "$ARGV_LOG" || fail "Linux with a session bus did not pick secret-tool"
: > "$ARGV_LOG"
set_value PICK < <(printf 'x1234567\n')
grep -q '^pass ' "$ARGV_LOG" && ! grep -q '^secret-tool ' "$ARGV_LOG" || fail "Linux without a session bus did not pick pass"
before="$(cd "$HOME" && find . | LC_ALL=C sort)"
for cmd in "set NOSTORE" "get NOSTORE" "ls" "export NOSTORE" "run -n NOSTORE -- true"; do
    read -ra words <<< "$cmd"
    rc=0; printf 'value123\n' | SPATH="$tmp/plat:$tmp/sys" run_secret "${words[@]}" > "$tmp/out" 2> "$tmp/err" || rc=$?
    [[ $rc -eq 3 ]] || fail "no store: '$cmd' exited $rc"
    grep -q 'pass' "$tmp/err" && grep -q 'libsecret' "$tmp/err" && grep -q 'never writes a plaintext file' "$tmp/err" \
        || fail "no store: '$cmd' did not say what to install: $(err)"
done
[[ "$(cd "$HOME" && find . | LC_ALL=C sort)" == "$before" ]] || fail "no store: something was written under HOME"
TUIDEV_SECRET_BACKEND=bogus s ls; [[ $rc -eq 2 ]] || fail "a bad TUIDEV_SECRET_BACKEND (rc=$rc)"
TUIDEV_SECRET_BACKEND=keychain TUIDEV_SECRET_SECURITY="$tmp/none" s ls; [[ $rc -eq 3 ]] || fail "a missing Keychain CLI (rc=$rc)"
pass "backend: Keychain on macOS, secret-tool with a session bus, else pass; none exits 3 and writes nothing"
run_secret rm PICK >/dev/null 2>&1 || true

# ----------------------------------------------------------------------------
# scan: names and line numbers, never a value.
export TUIDEV_SECRET_BACKEND=pass
rc_file="$tmp/zshrc fixture"
cat > "$rc_file" <<'EOF'
# a comment GITHUB_TOKEN=ghp_notreallyatokenbutlongenough12345
export GITHUB_TOKEN=ghp_01230000000000000000000000000000
export CACHE_TOKEN="abc def'12\"34567"
API_KEY='s3cr3t-v@lue!'
export EDITOR=nvim
export PATH="$HOME/bin:$PATH"
export FROM_STORE="$(secret get FROM_STORE)"
export SSH_AUTH_SOCK=/private/tmp/agent.sock
export DATABASE_URL=postgres://user:pw1234@db.internal/app
  export   SIGNING_KEY=abcdefgh12345678   # build signing
export DISABLE_AUTH=true
export RANDOMISH=abcdefghijklmnopqrstuvwxyz0123456789ABCD
export GPG_KEY_ID=ABCDEF0123456789
export LANG=en_US.UTF-8
export SHORT_TOKEN=abc
export CONCAT_TOKEN='abc'"def12345"
export NOCLOSE_TOKEN="abcdefgh12345
alias k=kubectl
EOF
s scan "$rc_file"
[[ $rc -eq 1 ]] || fail "scan rc=$rc on hits"
want="$(printf '%s\n' "$rc_file:2: GITHUB_TOKEN" "$rc_file:3: CACHE_TOKEN" "$rc_file:4: API_KEY" \
    "$rc_file:9: DATABASE_URL" "$rc_file:10: SIGNING_KEY" "$rc_file:12: RANDOMISH")"
[[ "$(out)" == "$want" ]] || fail "scan reported:
$(out)
wanted:
$want"
for v in ghp_0123 'abc def' "s3cr3t" pw1234 abcdefgh12345678 abcdefghijklmnop; do
    if grep -qF -- "$v" "$tmp/out" "$tmp/err"; then fail "scan printed a value ($v)"; fi
done
grep -q 'secret import --remove' "$tmp/err" || fail "scan gave no next step"
s scan "$REPO_DIR/configs/zsh/.zshrc"
[[ $rc -eq 0 && -z "$(out)" ]] || fail "scan flags the shipped .zshrc: $(out)"
pass "scan: FILE:LINE: NAME for token-looking literals only, never a value; the shipped .zshrc is clean"

# The default files: shell startup files and ~/.config/zsh/*.zsh.
mkdir -p "$HOME/.config/zsh"
printf 'export EDITOR=vim\nexport NPM_TOKEN=npm_abcdefghijklmnopqrstuvwxyz0123\n' > "$HOME/.zshrc"
printf 'export BUILD_CACHE_TOKEN="0123456789abcdef0123456789abcdef"\n' > "$HOME/.config/zsh/secrets.zsh"
printf 'export HF_TOKEN=hf_abcdefghijklmnopqrstuvwxyz\n' > "$HOME/.profile"
s scan
[[ $rc -eq 1 ]] || fail "default scan rc=$rc"
[[ "$(out)" == "$(printf '%s\n' "$HOME/.zshrc:2: NPM_TOKEN" "$HOME/.profile:1: HF_TOKEN" "$HOME/.config/zsh/secrets.zsh:1: BUILD_CACHE_TOKEN")" ]] \
    || fail "default scan: $(out)"
rm -f "$HOME/.zshrc" "$HOME/.profile" "$HOME/.config/zsh/secrets.zsh"
s scan; [[ $rc -eq 0 && -z "$(out)" ]] || fail "scan with no files: rc=$rc $(out)"
pass "scan: reads ~/.zshrc, ~/.profile, ~/.config/zsh/*.zsh and the rest by default"

# ----------------------------------------------------------------------------
# import --dry-run: the plan (names and line numbers), and nothing else.
: > "$ARGV_LOG"
cp "$rc_file" "$tmp/orig"
s import --dry-run --remove "$rc_file"
[[ $rc -eq 0 ]] || fail "import --dry-run rc=$rc: $(err)"
cmp -s "$rc_file" "$tmp/orig" || fail "import --dry-run changed the file"
ls "$rc_file".secret-backup-* >/dev/null 2>&1 && fail "import --dry-run wrote a backup"
if grep -q '^pass \|^security \|^secret-tool ' "$ARGV_LOG"; then fail "import --dry-run reached the store"; fi
grep -q 'would store, then remove from the file' "$tmp/err" || fail "import --dry-run plan header: $(err)"
for want in '  GITHUB_TOKEN  (line 2)' '  CACHE_TOKEN  (line 3)' '  API_KEY  (line 4)' '  DATABASE_URL  (line 9)' \
            '  SIGNING_KEY  (line 10)' '  RANDOMISH  (line 12)'; do
    grep -qxF -- "$want" "$tmp/err" || fail "import --dry-run plan lacks [$want]: $(err)"
done
for v in ghp_0123 'abc def' s3cr3t pw1234 abcdefgh12345678; do
    if grep -qF -- "$v" "$tmp/err" "$tmp/out"; then fail "import --dry-run printed a value ($v)"; fi
done
pass "import --dry-run lists names and line numbers, stores nothing, changes nothing"

# import: stores, and only with --remove takes the lines out.
s import "$rc_file"
[[ $rc -eq 0 ]] || fail "import rc=$rc: $(err)"
cmp -s "$rc_file" "$tmp/orig" || fail "import without --remove changed the file"
[[ "$(got GITHUB_TOKEN)" == ghp_01230000000000000000000000000000 ]] || fail "import GITHUB_TOKEN"
[[ "$(got CACHE_TOKEN)" == "abc def'12\"34567" ]] || fail "import unquoted CACHE_TOKEN wrongly: [$(got CACHE_TOKEN)]"
[[ "$(got API_KEY)" == 's3cr3t-v@lue!' ]] || fail "import API_KEY"
[[ "$(got SIGNING_KEY)" == abcdefgh12345678 ]] || fail "import SIGNING_KEY"
s get EDITOR; [[ $rc -eq 1 ]] || fail "import took EDITOR, which is no token"
for v in ghp_0123 's3cr3t' pw1234 abcdefgh12345678; do no_value_in_argv "$v" import; done
pass "import stores the token-looking literals and leaves the file alone"

# Explicit names; a name that isn't a literal assignment stops everything.
s import "$rc_file" EDITOR
[[ $rc -eq 0 && "$(got EDITOR)" == nvim ]] || fail "import of a named variable"
s import "$rc_file" FROM_STORE
[[ $rc -eq 1 ]] && grep -q 'no literal assignment of FROM_STORE' "$tmp/err" || fail "import of an expansion (rc=$rc)"
s import --remove "$rc_file" EDITOR PATH
[[ $rc -eq 1 ]] && cmp -s "$rc_file" "$tmp/orig" || fail "import --remove with a non-literal name touched the file"
pass "import NAME...: just those; an expansion is refused and the file is untouched"

# A store failure leaves the file as it was.
export FAKE_FAIL_PUT=API_KEY
s import --remove "$rc_file"
[[ $rc -eq 1 ]] && cmp -s "$rc_file" "$tmp/orig" || fail "a failed store still changed the file (rc=$rc)"
ls "$rc_file".secret-backup-* >/dev/null 2>&1 && fail "a failed import left a backup"
unset FAKE_FAIL_PUT
pass "import --remove: a failed store leaves the file and writes no backup"

# --remove through a symlink, keeping the target's mode.
mkdir -p "$tmp/dotfiles"
cp "$tmp/orig" "$tmp/dotfiles/zshrc"
chmod 640 "$tmp/dotfiles/zshrc"
ln -s "$tmp/dotfiles/zshrc" "$tmp/linked rc"
s import --remove "$tmp/linked rc"
[[ $rc -eq 0 ]] || fail "import --remove rc=$rc: $(err)"
[[ -L "$tmp/linked rc" ]] || fail "import --remove replaced the symlink"
[[ "$(ls -l "$tmp/dotfiles/zshrc" | cut -c1-10)" == "-rw-r-----" ]] || fail "import --remove changed the mode: $(ls -l "$tmp/dotfiles/zshrc")"
backup="$(ls "$tmp/linked rc".secret-backup-* 2>/dev/null)"
[[ -n "$backup" && -f "$backup" ]] || fail "no backup next to the file"
[[ "$(ls -l "$backup" | cut -c1-10)" == "-rw-------" ]] || fail "the backup is not mode 600: $(ls -l "$backup")"
for v in ghp_0123 "abc def" s3cr3t pw1234 abcdefgh12345678 abcdefghijklmnopqrstuvwxyz0123456789ABCD; do
    if grep -qF -- "$v" "$tmp/dotfiles/zshrc"; then fail "the value ($v) is still in the file"; fi
    if grep -qF -- "$v" "$backup"; then fail "the backup holds a value ($v)"; fi
done
for keep in 'export EDITOR=nvim' 'export PATH="$HOME/bin:$PATH"' 'export FROM_STORE="$(secret get FROM_STORE)"' \
            'export SSH_AUTH_SOCK=/private/tmp/agent.sock' 'export DISABLE_AUTH=true' 'alias k=kubectl' \
            '# a comment GITHUB_TOKEN=ghp_notreallyatokenbutlongenough12345'; do
    grep -qxF -- "$keep" "$tmp/dotfiles/zshrc" || fail "import --remove lost: $keep"
    grep -qxF -- "$keep" "$backup" || fail "the backup lost: $keep"
done
grep -q '^# GITHUB_TOKEN: moved to the secret store' "$tmp/dotfiles/zshrc" || fail "no note where GITHUB_TOKEN was"
grep -qx '# API_KEY=<removed by secret import; the value is in the secret store>' "$backup" || fail "backup marker"
[[ "$(wc -l < "$tmp/dotfiles/zshrc")" -eq "$(wc -l < "$tmp/orig")" ]] || fail "line count changed"
s scan "$tmp/dotfiles/zshrc"; [[ $rc -eq 0 ]] || fail "the file still scans dirty: $(out)"
[[ "$(got RANDOMISH)" == abcdefghijklmnopqrstuvwxyz0123456789ABCD ]] || fail "import RANDOMISH"
pass "import --remove: values out of the file and its backup (600), the rest kept, symlink and mode kept"

# The last assignment of a name wins, and every line of it goes.
printf 'export DUP_TOKEN=first1234567\nexport DUP_TOKEN=second123456\n' > "$tmp/dup"
s import --remove "$tmp/dup"
[[ $rc -eq 0 && "$(got DUP_TOKEN)" == second123456 ]] || fail "duplicate: last wins"
grep -qxF '  DUP_TOKEN  (line 1, 2)' "$tmp/err" || fail "duplicate: the plan names both lines: $(err)"
if grep -q 'first1234567\|second123456' "$tmp/dup"; then fail "duplicate: a value stayed"; fi
s import "$tmp/nonexistent"; [[ $rc -eq 1 ]] || fail "import of a missing file"
s import; [[ $rc -eq 2 ]] || fail "import with no file"
pass "import: last assignment wins, all its lines go; bad arguments refused"
unset TUIDEV_SECRET_BACKEND

# ----------------------------------------------------------------------------
# secret run gives the command the caller's locale, not secret's LC_ALL=C.
export TUIDEV_SECRET_BACKEND=pass
set_value LOC < <(printf 'loc1234567\n')
have="$(run_secret run -n LOC -- "$SH" -c 'printf "%s" "${LC_ALL-unset}"')"
[[ "$have" == unset ]] || fail "run leaked LC_ALL=$have"
have="$(LC_ALL=en_US.UTF-8 run_secret run -n LOC -- "$SH" -c 'printf "%s" "${LC_ALL-unset}"')"
[[ "$have" == en_US.UTF-8 ]] || fail "run changed LC_ALL to $have"
pass "secret run restores the caller's LC_ALL"
unset TUIDEV_SECRET_BACKEND

# ----------------------------------------------------------------------------
# The core pack installs it as ~/.local/bin/secret and records it.
export PATH="$REAL_PATH" TUIDEV_NO_COLOR=1 NO_COLOR=1 DRY_RUN=false
export TUIDEV_STATE_DIR="$HOME/.config/tuidev" TUIDEV_MANIFEST_ENABLED=1
(
    # shellcheck source=../install/core.sh disable=SC1091
    . "$REPO_DIR/scripts/install/core.sh"
    _core_install_secret
) > "$tmp/install.log" 2>&1 || fail "install: $(cat "$tmp/install.log")"
[[ -x "$HOME/.local/bin/secret" ]] && cmp -s "$HOME/.local/bin/secret" "$SECRET" || fail "secret not installed"
grep -qF "$HOME/.local/bin/secret" "$TUIDEV_STATE_DIR/manifest" || fail "the install is not in the manifest"
grep -q '_core_install_secret$' "$REPO_DIR/scripts/install/core.sh" || fail "core_install does not call _core_install_secret"
grep -qF '"secret:bin/secret"' "$REPO_DIR/uninstall.sh" || fail "uninstall.sh's helper list lacks secret"
pass "the core pack installs ~/.local/bin/secret and records it"

echo ""
echo "All secret tests passed."
