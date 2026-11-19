#!/bin/bash
# scripts/lib/test_contract.sh - regression tests that guard cross-file contracts.
#
# Run: bash scripts/lib/test_contract.sh  -> exit 0 on pass.
#
# Rationale: the installer writes configs under specific block IDs and paths,
# and the updater reads them back. Those names must match or "drift detection"
# silently misreports. This test file enforces the contract so parallel edits
# can't quietly break it.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "PASS: $1"; }

# 1. Managed-block IDs: every ID install.sh writes must appear in
#    update.sh's MANAGED_BLOCKS list so drift-detection can find them.
INSTALL_IDS="$(grep -hE -- '--managed-block' "$REPO_DIR/install.sh" "$REPO_DIR/scripts/install/"*.sh "$REPO_DIR/scripts/install/packs/"*.sh 2>/dev/null \
    | grep -oE '\-\-managed-block [a-z][a-z0-9-]+' \
    | awk '{print $2}' | sort -u)"

for id in $INSTALL_IDS; do
    # Pack-owned blocks (Ghostty, SSH) are re-applied by re-running their
    # pack, not by update.sh's cross-cutting drift list.
    case "$id" in
        tuidev-ghostty|tuidev-remote) continue ;;
    esac
    if ! grep -qF "|$id\"" "$REPO_DIR/scripts/update.sh"; then
        fail "install.sh writes managed-block '$id' but update.sh MANAGED_BLOCKS doesn't list it"
    fi
done
pass "managed-block IDs are consistent between installer and updater"

# 2. Seatbelt paths: update.sh's security audit must compare the same source
#    and destination the sandbox pack installs.
if ! grep -qF 'configs/sandbox/profiles' "$REPO_DIR/scripts/update.sh"; then
    fail "update.sh should audit configs/sandbox/profiles (what install.sh writes)"
fi
for f in scripts/update.sh scripts/install/sandbox.sh; do
    # shellcheck disable=SC2016  # the literal variable name is what we grep for
    grep -qF '$TUIDEV_STATE_DIR/sandbox' "$REPO_DIR/$f" \
        || fail "$f should use \$TUIDEV_STATE_DIR/sandbox for the installed profiles"
done
pass "Seatbelt audit paths match installer"

# 3. Every pack name advertised in README/docs must have a script.
#    Packs live at scripts/install/packs/<name>.sh. The five "first-class"
#    packs (core/remote/sandbox/ui/extras) live at scripts/install/<name>.sh
#    and are invoked via --<name>, not --pack <name>, so they're excluded.
FIRSTCLASS_PACKS="core remote sandbox ui extras"

DOCS_PACKS="$(grep -hoE -- '--pack [a-z][a-z0-9-]+' "$REPO_DIR"/{README.md,install.sh,docs/profiles.md} 2>/dev/null \
    | awk '{print $2}' | sort -u)"

for pack in $DOCS_PACKS; do
    [[ "$pack" == "NAME" ]] && continue
    # Skip first-class packs that happen to also appear via --pack doc wording.
    case " $FIRSTCLASS_PACKS " in *" $pack "*) continue;; esac
    if [[ ! -f "$REPO_DIR/scripts/install/packs/$pack.sh" ]]; then
        fail "docs advertise --pack $pack but scripts/install/packs/$pack.sh is missing"
    fi
done
pass "every documented --pack NAME has a script"

# 4. TUIDEV_VALID_PACKS and scripts/install/packs/ agree, and every pack
#    defines the entrypoint packs.sh will call.
# shellcheck source=./packs.sh disable=SC1091
. "$SCRIPT_DIR/packs.sh"
for pack in "${TUIDEV_BUILTIN_PACKS[@]}" "${TUIDEV_VALID_PACKS[@]}"; do
    script="$(pack_script "$pack")" || fail "pack '$pack' has no script"
    grep -qE "^$(pack_entrypoint "$pack")\(\)" "$script" \
        || fail "$script does not define $(pack_entrypoint "$pack")()"
done
for script in "$REPO_DIR"/scripts/install/packs/*.sh; do
    tuidev_is_valid_pack "$(basename "$script" .sh)" \
        || fail "$script is not registered in TUIDEV_VALID_PACKS (scripts/lib/profile.sh)"
done
pass "every pack is registered, has a script, and defines its entrypoint"

# 4b. `tuidev check` can tell whether each optional pack is in place: its own
#     <pack>_check, or packages declared for pack_check to look for.
for pack in "${TUIDEV_VALID_PACKS[@]}"; do
    script="$(pack_script "$pack")"
    grep -qE "^${pack//-/_}_check\(\)" "$script" \
        || [[ -n "$(pack_array "$pack" formulae)$(pack_array "$pack" casks)" ]] \
        || fail "$script has no ${pack//-/_}_check() and declares no packages: tuidev check cannot probe it"
done
pass "every optional pack has a health-check probe (its own, or its declared packages)"

# 4c. What the installer, update and packs tell you to run works without a
#     clone: the one-line install has no Makefile to `make` and no ./install.sh
#     in your directory (tuidev install, or "$(tuidev home)/scripts/...").
hints="$(cd "$REPO_DIR" && grep -nE '(print_[a-z]+|echo|die)[^#]*(\bmake [a-z]|\./install\.sh|\./uninstall\.sh)' \
    install.sh uninstall.sh scripts/update.sh scripts/health_check.sh scripts/install/*.sh scripts/install/packs/*.sh \
    scripts/migrations/*.sh scripts/lib/*.sh | grep -v '^scripts/lib/test_' || true)"
[[ -z "$hints" ]] || fail "hints that need a clone (use tuidev install, tuidev update or \"\$(tuidev home)/scripts/...\"): $hints"
pass "no printed hint needs a clone (make, ./install.sh)"

# 4d. Every job the packs install from configs/agents/ (a LaunchAgent's
#     plist, a systemd user unit) runs `agents`, so uninstall.sh stops and
#     removes it by name; and the plist's Label is its file's name, which
#     launchctl and the packs use.
for f in "$REPO_DIR"/configs/agents/*.plist "$REPO_DIR"/configs/agents/*.service "$REPO_DIR"/configs/agents/*.timer; do
    n="${f##*/}"
    case "$n" in
        *.plist)   n="${n%.plist}"
                   grep -qF "<string>$n</string>" "$f" || fail "$f: its Label is not $n" ;;
        *.service) [[ -f "${f%.service}.timer" ]] && n="${n%.service}.timer" ;;   # removed with its timer
    esac
    grep -qE "^for [a-z_]+ in (.* )?$n( |;)" "$REPO_DIR/uninstall.sh" || fail "uninstall.sh does not stop and remove ${f##*/} ($n)"
done
pass "uninstall.sh names every LaunchAgent and systemd user unit in configs/agents/"

# Every shipped config the installer upgrades-if-unmodified (install_config
# --upgrade-shipped) is fingerprinted, so it can tell an unmodified old copy
# (upgrade it) from one the user edited (leave it alone). Each hash file lists
# `<basename without extension> <sha256>` for every version ever shipped.
# shellcheck source=./ui.sh disable=SC1091
. "$SCRIPT_DIR/ui.sh"
check_fingerprinted() {
    local shipped="$1" src name; shift
    [[ -f "$shipped" ]] || fail "missing ${shipped#"$REPO_DIR"/}"
    for src in "$@"; do
        name="$(basename "$src")"; name="${name%.*}"
        grep -qx "$name $(file_sha256 "$src")" "$shipped" \
            || fail "${src#"$REPO_DIR"/} changed but its hash is not in ${shipped#"$REPO_DIR"/} (append: $name $(file_sha256 "$src"))"
    done
}
check_fingerprinted "$REPO_DIR/configs/sandbox/profiles/shipped.sha256" "$REPO_DIR"/configs/sandbox/profiles/*.sb
check_fingerprinted "$REPO_DIR/configs/claude/shipped.sha256" "$REPO_DIR/configs/claude/settings.json"
# settings.linux.json is installed with --shipped-name settings.
grep -qx "settings $(file_sha256 "$REPO_DIR/configs/claude/settings.linux.json")" "$REPO_DIR/configs/claude/shipped.sha256" \
    || fail "configs/claude/settings.linux.json changed but its hash is not in configs/claude/shipped.sha256 (append: settings $(file_sha256 "$REPO_DIR/configs/claude/settings.linux.json"))"
check_fingerprinted "$REPO_DIR/configs/codex/shipped.sha256"  "$REPO_DIR/configs/codex/config.toml"
check_fingerprinted "$REPO_DIR/configs/vim/shipped.sha256"    "$REPO_DIR/configs/vim/vimrc"
# nvim is a tree: keyed by path relative to configs/nvim (two init.lua files).
nvim_root="$REPO_DIR/configs/nvim"
while IFS= read -r src; do
    rel="${src#"$nvim_root"/}"
    [[ "$rel" == shipped.sha256 ]] && continue
    grep -qx "$rel $(file_sha256 "$src")" "$nvim_root/shipped.sha256" \
        || fail "configs/nvim/$rel changed but its hash is not in configs/nvim/shipped.sha256 (append: $rel $(file_sha256 "$src"))"
done < <(find "$nvim_root" -type f -not -name '.*')
# And every --upgrade-shipped call site points at one of those hash files.
while IFS= read -r ref; do
    [[ -f "$REPO_DIR/$ref" ]] || fail "--upgrade-shipped names $ref, which does not exist"
done < <(grep -rhoE 'configs/[a-z/]+/shipped\.sha256' "$REPO_DIR/scripts/install" | sort -u)
pass "every shipped-config version is fingerprinted (sandbox, claude, codex, vim, nvim)"

# Claude Code's Linux sandbox enforces literal paths and whole directories
# (a trailing /**). Any other glob in a Read/Edit rule makes it walk the whole
# project for matches, repeatedly, which stalls the TUI on a large repo. Only
# the macOS settings.json may keep the **/.env rules (Seatbelt matches them
# natively); settings.linux.json spells them as literal paths.
check_linux_safe_rules() {
    local file="$1" allow_env="$2" rule path
    while IFS= read -r rule; do
        path="${rule#*(}"; path="${path%)}"
        if [[ "$allow_env" == true ]]; then
            case "$path" in **/.env|**/.env.*) continue ;; esac
        fi
        path="${path%/\*\*}"
        case "$path" in *'*'*|*'?'*|*'['*) fail "${file#"$REPO_DIR"/}: $rule uses a glob Claude Code's Linux sandbox can't enforce (use literal paths or a trailing /**)" ;; esac
    done < <(grep -oE '"(Read|Edit)\([^)]*\)"' "$file" | tr -d '"')
}
check_linux_safe_rules "$REPO_DIR/configs/claude/settings.json" true
check_linux_safe_rules "$REPO_DIR/configs/claude/settings.linux.json" false
pass "Claude Read/Edit rules use only globs the Linux sandbox supports"

# The Linux settings differ from the macOS ones only in the .env deny rules,
# and those are the full literal set (9 names, Read and Edit each).
env_rule='^[[:space:]]*"(Read|Edit)\((\*\*|\.)/\.env[^"]*\)",?$'
[[ "$(grep -cE '^[[:space:]]*"(Read|Edit)\(\./\.env[^"]*\)",?$' "$REPO_DIR/configs/claude/settings.linux.json")" == 18 ]] \
    || fail "configs/claude/settings.linux.json must deny the 18 literal ./.env* Read/Edit rules"
[[ "$(grep -vE "$env_rule" "$REPO_DIR/configs/claude/settings.json")" \
   == "$(grep -vE "$env_rule" "$REPO_DIR/configs/claude/settings.linux.json")" ]] \
    || fail "configs/claude/settings.linux.json drifted from settings.json beyond the .env rules"
pass "configs/claude/settings.linux.json mirrors settings.json apart from the .env rules"

# The shipped statusLine runs `agents statusline` only when agents is
# installed (else it shows nothing and never fails), and agents has it.
# shellcheck disable=SC2016  # the command as the JSON spells it
sl='[ -x "$HOME/.local/bin/agents" ] && exec "$HOME/.local/bin/agents" statusline; cat >/dev/null; exit 0'
sl_json="${sl//\"/\\\"}"
[[ "$(grep -A3 '"statusLine": {' "$REPO_DIR/configs/claude/settings.json")" == *'"type": "command",'*"\"command\": \"$sl_json\""* ]] \
    || fail "configs/claude/settings.json: statusLine must run agents statusline only when agents is installed"
grep -qE '^        statusline\)' "$REPO_DIR/lib/agents/cli.sh" || fail "agents has no statusline subcommand for the shipped statusLine"
[[ "$(echo '{}' | HOME=/nonexistent sh -c "$sl"; echo "rc=$?")" == "rc=0" ]] || fail "the shipped statusLine fails or prints without agents"
pass "the shipped statusLine runs agents statusline, and shows nothing without agents"

# Credential lockout: every copy denies exactly configs/sandbox/credential-paths.txt.
# Structured copies keep the dir/file distinction (trailing /); prose copies
# are compared without it.
cred_want="$(grep -vE '^(#|$)' "$REPO_DIR/configs/sandbox/credential-paths.txt" | sort)"
cred_want_flat="$(printf '%s\n' "$cred_want" | sed 's:/$::' | sort)"
check_creds() {
    local label="$1" want="$2" got="$3"
    got="$(printf '%s\n' "$got" | grep -v '^$' | sort)"
    [[ "$got" == "$want" ]] && return 0
    local missing extra
    missing="$(comm -23 <(printf '%s\n' "$want") <(printf '%s\n' "$got") | tr '\n' ' ')"
    extra="$(comm -13 <(printf '%s\n' "$want") <(printf '%s\n' "$got") | tr '\n' ' ')"
    fail "$label: credential paths drifted from configs/sandbox/credential-paths.txt (missing: ${missing:-none}; extra: ${extra:-none})"
}
for sb in strict standard; do
    check_creds "$sb.sb" "$cred_want" "$(awk '/CREDENTIAL LOCKOUT/{f=1} f' "$REPO_DIR/configs/sandbox/profiles/$sb.sb" \
        | sed -nE 's:.*\((subpath|literal) \(string-append \(param "HOME_DIR"\) "/([^"]+)"\).*:\1 ~/\2:p' \
        | sed -E 's:^subpath (.*):\1/:; s:^literal ::')"
done
for f in settings.json settings.linux.json; do
    check_creds "$f" "$cred_want" "$(grep -oE '"Read\(~/[^)]*\)"' "$REPO_DIR/configs/claude/$f" \
        | sed -E 's:^"Read\(::; s:\)"$::; s:/\*\*$:/:' | grep -v 'Application Support/')"
done
# Browser profiles have a list of their own: its paths have spaces.
browser_want="$(grep -vE '^(#|$)' "$REPO_DIR/configs/sandbox/browser-paths.txt" | sort)"
for sb in strict standard; do
    check_creds "$sb.sb browser profiles" "$browser_want" "$(sed -nE 's:.*\(subpath \(string-append \(param "HOME_DIR"\) "/(Library/Application Support/[^"]+)"\).*:~/\1/:p' "$REPO_DIR/configs/sandbox/profiles/$sb.sb")"
done
for f in settings.json settings.linux.json; do
    check_creds "$f browser profiles" "$browser_want" "$(grep -oE '"Read\(~/Library/Application Support/[^)]*\)"' "$REPO_DIR/configs/claude/$f" | sed -E 's:^"Read\(::; s:\)"$::; s:/\*\*$:/:')"
done
# Prose copies write the two cargo files as ~/.cargo/credentials[.toml].
prose_paths() {
    # shellcheck disable=SC2088  # a literal ~/ in the docs, not a path to expand
    grep -oE '~/[A-Za-z0-9._/-]+(\[\.toml\])?' \
        | awk '{ if (sub(/\[\.toml\]$/, "")) print $0 ".toml"; print }'
}
check_creds "bin/sbx --help" "$cred_want_flat" \
    "$(awk '/^CREDENTIALS/{f=1; next} f && /^$/{exit} f' "$REPO_DIR/bin/sbx" | prose_paths)"
check_creds "docs/sandboxing.md" "$cred_want_flat" \
    "$(awk '/^### Credentials: denied/{f=1} f && /^```$/{n++; if (n==2) exit; next} f && n==1' "$REPO_DIR/docs/sandboxing.md" | prose_paths)"
check_creds "AGENTS.md" "$cred_want_flat" \
    "$(grep -F "Denied under \`sbx\`" "$REPO_DIR/AGENTS.md" | sed 's/.*:\*\*//' | prose_paths)"
# agents runs without the repo, so it embeds the list (relative to $HOME)
# for the files whose last line it never reads.
check_creds "lib/agents/watched.sh _AGENTS_CRED_PATHS" "$cred_want" \
    "$(sed -n "s/^_AGENTS_CRED_PATHS='\(.*\)'$/\1/p" "$REPO_DIR/lib/agents/watched.sh" | tr ' ' '\n' | grep -v '^$' | sed 's:^:~/:')"
pass "credential lockout matches configs/sandbox/credential-paths.txt in every copy"

# Nothing inside sbx hands work to an app outside it.
for sb in strict standard; do
    for rule in '(deny appleevent-send)' 'com.apple.coreservices.launchservicesd'; do
        grep -qF "$rule" "$REPO_DIR/configs/sandbox/profiles/$sb.sb" || fail "$sb.sb lost $rule"
    done
done
pass "sbx profiles keep open and Apple Events out"

# Dependabot tracks the scanner images through .github/scanners/Dockerfile: the
# workflow has to run exactly those.
while read -r _ image; do
    grep -qF "$image" "$REPO_DIR/.github/workflows/security-scan-reusable.yml" \
        || fail "security-scan-reusable.yml does not run $image from .github/scanners/Dockerfile"
done < <(grep '^FROM ' "$REPO_DIR/.github/scanners/Dockerfile" | sed 's:docker\.io/::')
pass "the security scan runs the images Dependabot tracks"

# A parameter named like a function of the same program: gawk and BSD awk take
# it, mawk (Debian's awk) refuses the whole program, and the view doesn't run.
clash=""
while IFS= read -r files; do
    set --
    for f in $files; do set -- "$@" "$REPO_DIR/lib/agents/awk/$f.awk"; done
    found="$(cat "$@" | awk '
        /^[ \t]*function[ \t]/ {
            name = $0; sub(/^[ \t]*function[ \t]+/, "", name); sub(/[ \t]*\(.*/, "", name)
            args = $0; sub(/^[^(]*\(/, "", args); sub(/\).*/, "", args); gsub(/[ \t]/, "", args)
            fn[name] = 1; list[++n] = name "|" args
        }
        END {
            for (i = 1; i <= n; i++) {
                split(list[i], p, "|"); m = split(p[2], a, ",")
                for (j = 1; j <= m; j++) if (a[j] in fn) print p[1] "(" a[j] ")"
            }
        }')"
    [[ -z "$found" ]] || clash+=" [$files] $found"
done < <(grep -ohE '_agents_awk(_eval|_colored)? +"?[a-z_][a-z_ ]*"?' "$REPO_DIR"/lib/agents/*.sh "$REPO_DIR/bin/agents" \
    | sed -E 's/^_agents_awk(_eval|_colored)? +//; s/"//g; s/ +$//' | sort -u)
[[ -z "$clash" ]] || fail "awk parameters named like functions, which mawk refuses:$clash"
# The same for the awk programs written inline in a shell module: per module,
# its inline functions together with the library files that module loads.
clash=""
for sh in "$REPO_DIR"/lib/agents/*.sh; do
    grep -qE '^[ \t]+function[ \t]+[A-Za-z_][A-Za-z_0-9]*\(' "$sh" || continue
    set --
    for f in $(grep -ohE '_agents_awk(_eval|_colored)? +"[a-z_][a-z_ ]*"' "$sh" | sed -E 's/^[^"]*"//; s/"$//' | tr ' ' '\n' | sort -u); do
        [[ -f "$REPO_DIR/lib/agents/awk/$f.awk" ]] && set -- "$@" "$REPO_DIR/lib/agents/awk/$f.awk"
    done
    found="$(cat "$@" "$sh" | awk '
        /^[ \t]*function[ \t]+[A-Za-z_][A-Za-z_0-9]*[ \t]*\(/ {
            name = $0; sub(/^[ \t]*function[ \t]+/, "", name); sub(/[ \t]*\(.*/, "", name)
            args = $0; sub(/^[^(]*\(/, "", args); sub(/\).*/, "", args); gsub(/[ \t]/, "", args)
            fn[name] = 1; m = split(args, a, ",")
            for (j = 1; j <= m; j++) if (a[j] != "") par[a[j]] = name
        }
        END { for (x in par) if (x in fn) printf " %s (a parameter of %s)", x, par[x] }')"
    [[ -z "$found" ]] || clash+=" [${sh##*/}]$found"
done
[[ -z "$clash" ]] || fail "awk functions named like a parameter of a program they are loaded with, which mawk refuses:$clash"
pass "no awk parameter is named like a function"

# VERSION is what get.sh, dist.sh and `tuidev version` report: X.Y.Z, and not
# behind the newest released section of the changelog.
# shellcheck source=version.sh disable=SC1091
. "$SCRIPT_DIR/version.sh"
version="$(cat "$REPO_DIR/VERSION" 2>/dev/null)" || version=""
version_valid "$version" || fail "VERSION must be X.Y.Z (got '$version')"
newest="0.0.0"
while IFS= read -r h; do
    h="${h#\#\# \[}"; h="${h%%\]*}"
    ! { version_valid "$h" && version_newer "$h" "$newest"; } || newest="$h"
done < <(grep -E '^## \[' "$REPO_DIR/CHANGELOG.md")
! version_newer "$newest" "$version" || fail "VERSION $version is behind CHANGELOG.md's newest release, $newest"
pass "VERSION is X.Y.Z and not behind the changelog ($version, newest section $newest)"

# Copies kept in step. get.sh, bin/tuidev and lib/agents/release.sh run
# without scripts/lib, so each holds copies of a few of its functions; every
# copy is run here against its twin, and one that drifts fails.
# fn_from FILE NAME — top-level function NAME's text, out of a script that
# runs when sourced.
fn_from() {
    awk -v n="$2" 'index($0, n "() {") == 1 { print; if ($0 !~ /\{[[:space:]]*$/) exit; f = 1; next }
                   f { print; if (/^}/) exit }' "$1"
}
copies=""
for f in _tuidev_is_version _tuidev_newer _tuidev_managed _tuidev_release_home _tuidev_flip; do
    copies+="$(fn_from "$REPO_DIR/bin/tuidev" "$f")"$'\n'
done
copies+="$(fn_from "$REPO_DIR/get.sh" _get_flip)"$'\n'"$(fn_from "$REPO_DIR/get.sh" _get_sha256)"
[[ "$(grep -cE '^_[a-z0-9_]+\(\) \{' <<<"$copies")" == 7 ]] || fail "could not read the copies out of bin/tuidev and get.sh: $copies"
eval "$copies"
# shellcheck source=../../lib/agents/release.sh disable=SC1091
. "$REPO_DIR/lib/agents/release.sh"
# shellcheck source=ui.sh disable=SC1091
. "$SCRIPT_DIR/ui.sh"

for v in 1.2.3 0.0.0 10.20.30 03.09.0 v1.2.3 1.2 1.2.3.4 1.2.3-rc1 "" " 1.2.3" 1.2.x; do
    a=no b=no; version_valid "$v" && a=yes; _tuidev_is_version "$v" && b=yes
    [[ "$a" == "$b" ]] || fail "'$v' is a version to version_valid: $a, to bin/tuidev's _tuidev_is_version: $b"
done
cvt="$(mktemp -d "${TMPDIR:-/tmp}/tuidev-contract.XXXXXX")"
vers="0.0.0 0.0.1 1.0.0 1.0.1 3.08.0 3.9.0 3.10.0 3.99.99 4.0.0"
{ echo "# Changelog"; for v in $vers; do printf '\n## [%s] - 2026-01-01\n\n- %s\n' "$v" "$v"; done; } > "$cvt/CHANGELOG.md"
printf '#!/bin/bash\n' > "$cvt/install.sh"; chmod +x "$cvt/install.sh"
for b in $vers; do
    want=""
    for a in $vers; do
        x=no y=no z=no; version_newer "$a" "$b" && x=yes; _tuidev_newer "$a" "$b" && y=yes; _agents_release_newer "$a" "$b" && z=yes
        [[ "$x" == "$y" && "$x" == "$z" ]] || fail "is $a newer than $b? version_newer: $x, bin/tuidev: $y, lib/agents/release.sh: $z"
        [[ "$x" == no ]] || want+="$a "
    done
    got="$(TUIDEV_REPO="$cvt" HOME="$cvt" bash "$REPO_DIR/bin/tuidev" whatsnew "$b" | sed -n 's/^## \[\([^]]*\)\].*/\1/p' | tr '\n' ' ')"
    [[ "$(tr ' ' '\n' <<<"$got" | sort | tr '\n' ' ')" == "$(tr ' ' '\n' <<<"$want" | sort | tr '\n' ' ')" ]] \
        || fail "tuidev whatsnew $b lists '$got'; version_newer says '$want'"
done
pass "version_valid and version_newer agree with bin/tuidev's copies, lib/agents/release.sh's and the newer() in tuidev whatsnew"

mkdir -p "$cvt/r/versions/1.2.3" "$cvt/git" "$cvt/nogetsh" "$cvt/gitfile"
for d in "$cvt/r/versions/1.2.3" "$cvt/git" "$cvt/nogetsh" "$cvt/gitfile"; do echo 1.2.3 > "$d/VERSION"; : > "$d/get.sh"; done
mkdir "$cvt/git/.git"; : > "$cvt/gitfile/.git"; rm "$cvt/nogetsh/get.sh"
for d in "$cvt/r/versions/1.2.3" "$cvt/git" "$cvt/nogetsh" "$cvt/gitfile" "$cvt/none"; do
    a=no b=no; tuidev_is_release "$d" && a=yes; _tuidev_managed "$d" && b=yes
    [[ "$a" == "$b" ]] || fail "is $d a release? tuidev_is_release: $a, bin/tuidev's _tuidev_managed: $b"
done
for d in /h/current /h/x/versions/1.2.3 /h/versions/1.2 /h/versions/1.2.3/sub /h/versions/x/current /h/other /current; do
    a=no b=no; REPLY=""; tuidev_release_home "$d" && a="yes $REPLY"; REPLY=""; _tuidev_release_home "$d" && b="yes $REPLY"
    [[ "$a" == "$b" ]] || fail "the home of $d: tuidev_release_home says '$a', bin/tuidev's _tuidev_release_home '$b'"
done
pass "tuidev_is_release and tuidev_release_home agree with bin/tuidev's copies"

for fn in _get_flip _tuidev_flip; do
    h="$cvt/$fn"; mkdir -p "$h/versions/1.0.0" "$h/versions/2.0.0" "$h/dir/current"
    "$fn" "$h" 1.0.0 || fail "$fn: a first current failed"
    [[ "$(readlink "$h/current")" == versions/1.0.0 ]] || fail "$fn: a first current"
    "$fn" "$h" 2.0.0 || fail "$fn: a flip failed"
    [[ "$(readlink "$h/current")" == versions/2.0.0 && -z "$(find "$h" -name '.current.*')" ]] || fail "$fn: a flip"
    [[ -z "$(find "$h/versions" -type l)" ]] || fail "$fn: a link went into a version: $(find "$h/versions" -type l)"
    if "$fn" "$h/dir" 1.0.0 || [[ -n "$(ls -A "$h/dir/current")" ]]; then fail "$fn: a current that is a directory was replaced or written into"; fi
done
printf 'tuidev\n' > "$cvt/sum"
[[ "$(_get_sha256 "$cvt/sum")" == "$(file_sha256 "$cvt/sum")" && "$(file_sha256 "$cvt/sum")" =~ ^[0-9a-f]{64}$ ]] \
    || fail "get.sh's _get_sha256 and ui.sh's file_sha256 disagree"
rm -rf "$cvt"
pass "get.sh's _get_flip and _get_sha256 do what bin/tuidev's _tuidev_flip and ui.sh's file_sha256 do"

# bin/tuidev's _tuidev_excl and lock.sh's tuidev_excl: the same body.
[[ "$(fn_from "$REPO_DIR/bin/tuidev" _tuidev_excl | sed 1d)" == "$(fn_from "$SCRIPT_DIR/lock.sh" tuidev_excl | sed 1d)" \
   && -n "$(fn_from "$SCRIPT_DIR/lock.sh" tuidev_excl | sed 1d)" ]] || fail "bin/tuidev's _tuidev_excl and lock.sh's tuidev_excl differ"
pass "bin/tuidev's _tuidev_excl and lock.sh's tuidev_excl are the same"

# The update check's files: bin/tuidev writes them, lib/agents/release.sh
# reads them with builtins, uninstall.sh removes them. Same places, same names.
# shellcheck disable=SC2016  # the spellings, as the scripts write them
for spelling in '${XDG_CACHE_HOME:-$HOME/.cache}/tuidev' '${TUIDEV_STATE_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/tuidev}'; do
    for f in bin/tuidev lib/agents/release.sh; do
        grep -qF -- "$spelling" "$REPO_DIR/$f" || fail "$f does not spell its path as $spelling"
    done
done
# shellcheck disable=SC2016
grep -qF -- '${XDG_CACHE_HOME:-$HOME/.cache}/tuidev' "$REPO_DIR/uninstall.sh" || fail "uninstall.sh looks for the update check's cache elsewhere"
# shellcheck disable=SC2016
grep -qF -- ': "${TUIDEV_STATE_DIR:=${XDG_CONFIG_HOME:-$HOME/.config}/tuidev}"' "$SCRIPT_DIR/ui.sh" || fail "ui.sh's TUIDEV_STATE_DIR is not the one bin/tuidev and lib/agents/release.sh assume"
# shellcheck disable=SC2016  # literal $ in the patterns
writes="$(grep -oE '\$_TUIDEV_CACHE/[a-z]+' "$REPO_DIR/bin/tuidev" | sed 's|.*/||' | sort -u | tr '\n' ' ')"
# shellcheck disable=SC2016
removes="$(grep -oE '\$_tuidev_cache"?/[a-z]+' "$REPO_DIR/uninstall.sh" | sed 's|.*/||' | sort -u | tr '\n' ' ')"
[[ "$writes" == "latest lock notified " && "$removes" == "$writes" ]] || fail "bin/tuidev writes '$writes' in its cache, uninstall.sh removes '$removes'"
grep -qF 'tuidev/latest"' "$REPO_DIR/lib/agents/release.sh" || fail "lib/agents/release.sh does not read the cache's latest"
# shellcheck disable=SC2016
for pair in 'bin/tuidev|"$_TUIDEV_STATE/version"' 'lib/agents/release.sh|tuidev}/version"' 'scripts/lib/config_write.sh|"$TUIDEV_STATE_DIR/version"'; do
    grep -qF -- "${pair#*|}" "$REPO_DIR/${pair%%|*}" || fail "${pair%%|*} does not use the installed version tuidev_install_cli writes, ${pair#*|}"
done
for f in get.sh bin/tuidev configs/swiftbar/agents.10s.sh; do
    grep -qF 'https://github.com/spfr/tuidev/releases' "$REPO_DIR/$f" || fail "$f does not name the releases at https://github.com/spfr/tuidev/releases"
done
pass "the update check's cache and the installed version: one spelling of each path in bin/tuidev, lib/agents/release.sh, uninstall.sh and ui.sh; one releases URL"

# The release tooling is shellchecked, and bin/tuidev's usage lists every
# command its main handles.
shell_files="$(awk '/^SHELL_FILES/ {f=1} f {print} f && !/\\$/ {exit}' "$REPO_DIR/Makefile" | sed 's/[\\]//g' | tr -s '[:space:]' '\n')"
for f in get.sh bin/tuidev; do
    grep -qxF "$f" <<<"$shell_files" || fail "$f is not in the Makefile's SHELL_FILES"
done
usage_text="$(grep -E '^#   tuidev' "$REPO_DIR/bin/tuidev")"
commands="$(awk '/^main\(\) \{/ {f=1} f && /^    case "\$cmd" in/ {c=1; next} c && /^    esac/ {exit} c && /^        [A-Za-z"|-]+\)/ {print $1}' "$REPO_DIR/bin/tuidev" | tr -d ')"' | tr '|' '\n' | grep -E '^[a-z]+$' | grep -vx help || true)"
[[ "$(wc -w <<<"$commands")" -ge 10 ]] || fail "could not read the commands out of bin/tuidev's main (got: $commands)"
for c in $commands; do
    grep -qw -- "$c" <<<"$usage_text" || fail "bin/tuidev's usage does not mention the command '$c'"
done
pass "get.sh and bin/tuidev are shellchecked; bin/tuidev's usage mentions every command"

# CI's required-files job must list only files that exist, or a removal breaks CI
# while every local check stays green.
while IFS= read -r f; do
    [[ -e "$REPO_DIR/$f" ]] || fail ".github/workflows/ci.yml requires $f, which no longer exists"
done < <(awk '/^ *required=\($/{f=1; next} f && /^ *\)$/{exit} f {print $1}' "$REPO_DIR/.github/workflows/ci.yml")
pass "every file CI requires exists"

# A release carries three assets, named alike wherever they are built, signed,
# published and downloaded; a mismatch breaks get.sh and `tuidev update`.
rel_yml="$REPO_DIR/.github/workflows/release.yml"
want_assets="tuidev.tar.gz tuidev.tar.gz.sha256 get.sh"
got="$(sed -n 's/^ASSETS=(\(.*\))$/\1/p' "$REPO_DIR/scripts/release.sh")"
[[ "$got" == "$want_assets" ]] || fail "scripts/release.sh publishes '$got', not '$want_assets'"
# The workflows are not in the release archive or the test container: their
# checks run where .github is (a clone, CI).
have_workflows=false; [[ -f "$rel_yml" ]] && have_workflows=true
if $have_workflows; then
    got="$(awk '/subject-path: \|/ {f=1; next} f && /^ +dist\// {sub(/^ +dist\//, ""); printf "%s%s", s, $0; s=" "; next} f {exit}' "$rel_yml")"
    [[ "$got" == "$want_assets" ]] || fail "release.yml attests '$got', not '$want_assets'"
fi
# shellcheck disable=SC2016  # a literal $out, as dist.sh spells it
got="$(grep -oE '"\$out/[a-z0-9.]+"' "$REPO_DIR/scripts/dist.sh" | grep -oE '[a-z0-9.]+"$' | tr -d '"' | sort -u | tr '\n' ' ')"
[[ "$got" == "get.sh tuidev.tar.gz tuidev.tar.gz.sha256 " ]] || fail "scripts/dist.sh writes '$got'"
for a in tuidev.tar.gz tuidev.tar.gz.sha256; do
    grep -qF "\"\$from/$a\"" "$REPO_DIR/get.sh" || fail "get.sh does not download $a"
done
grep -qF 'latest/download/get.sh' "$REPO_DIR/bin/tuidev" || fail "bin/tuidev no longer names latest/download/get.sh"
if $have_workflows; then
    # The workflow runs the tested steps, after all of CI on the tagged commit.
    for step in 'uses: ./.github/workflows/ci.yml' 'needs: ci' 'scripts/release.sh check' 'scripts/dist.sh --release' \
                'scripts/release.sh notes' 'scripts/release.sh publish' 'persist-credentials: false'; do
        grep -qF -- "$step" "$rel_yml" || fail "release.yml no longer has: $step"
    done
    grep -qE '^  workflow_call:' "$REPO_DIR/.github/workflows/ci.yml" || fail "ci.yml cannot be called, and release.yml gates on it"
    # Least privilege: read-only at the top, write only in the job that publishes.
    [[ "$(awk '/^permissions:/ {f=1; next} f && /^[^ ]/ {exit} f' "$rel_yml" | tr -d ' ')" == "contents:read" ]] \
        || fail "release.yml's top-level permissions must be contents: read alone"
fi
pass "release assets are named alike in release.sh, release.yml, dist.sh and get.sh; release.yml runs CI and the tested steps"

# Every action a workflow uses is pinned to a commit, its version beside it.
unpinned="$(grep -hE '^[ -]+uses: ' "$REPO_DIR"/.github/workflows/*.yml 2>/dev/null | grep -vE 'uses: \./' \
    | grep -vE 'uses: [A-Za-z0-9_.-]+/[A-Za-z0-9_./-]+@[0-9a-f]{40} # v[0-9]+(\.[0-9]+)*$' || true)"
[[ -z "$unpinned" ]] || fail "actions not pinned to a full commit SHA with a '# vX.Y.Z' comment: $unpinned"
pass "every action in .github/workflows is pinned to a commit SHA"

echo ""
echo "All cross-file contract tests passed."
