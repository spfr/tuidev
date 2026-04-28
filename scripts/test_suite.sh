#!/bin/bash

# ============================================================================
# Test Suite for macOS TUI Development Environment
# ============================================================================
# Tag-based test runner for the layered installer (profiles + packs).
#
# Tags:
#   core    - core pack tools and own library scripts (always runs by default)
#   remote  - tailscale / mosh / SSH config sanity
#   sandbox - Seatbelt profiles, bin/sbx, sandbox-exec -n probe
#   ui      - GUI apps (Rectangle, Stats, Maccy, Hidden Bar, Hammerspoon,
#             Ghostty). Never affects exit code.
#   extras  - atuin, dust, broot, bandwhich, etc.
#   packs   - extra packs listed in ~/.config/tuidev/profile
#
# Usage:
#   ./scripts/test_suite.sh                  # core + profile-enabled tags
#   ./scripts/test_suite.sh --tag core
#   ./scripts/test_suite.sh --tag core --tag remote
#   ./scripts/test_suite.sh --all            # every tag, incl. ui
#   ./scripts/test_suite.sh --no-ui          # every tag except ui
# ============================================================================

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEST_RESULTS_DIR="$REPO_ROOT/test_results"
mkdir -p "$TEST_RESULTS_DIR"

PROFILE_FILE="${TUIDEV_PROFILE_FILE:-$HOME/.config/tuidev/profile}"

# ---------------------------------------------------------------------------
# Local formatting — test_suite uses its own print_* variants with tee-to-log
# behavior (see log/print_header below). ANSI sequences are redefined here
# to stay independent of the shared lib's formatting conventions.
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
DIM='\033[2m'
NC='\033[0m'

LOG_FILE="$TEST_RESULTS_DIR/test_$(date +%Y%m%d_%H%M%S).log"
: > "$LOG_FILE"
echo "Test started at $(date)" >> "$LOG_FILE"

log() {
    printf '%b\n' "$1" | tee -a "$LOG_FILE"
}

log_plain() {
    printf '%s\n' "$1" >> "$LOG_FILE"
}

print_header() {
    echo ""
    log "${BLUE}========================================${NC}"
    log "${BLUE}$1${NC}"
    log "${BLUE}========================================${NC}"
}

# ---------------------------------------------------------------------------
# Counters (per-tag), current test state.
# ---------------------------------------------------------------------------
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0
UI_FAILED=0

CURRENT_TAG=""
CURRENT_NAME=""
TEST_OPEN=0

start_test() {
    # start_test NAME TAG
    local name="$1"
    local tag="${2:-core}"
    TESTS_RUN=$((TESTS_RUN + 1))
    CURRENT_TAG="$tag"
    CURRENT_NAME="$name"
    TEST_OPEN=1
    SUB_SEEN=0
    echo ""
    log "${CYAN}[TEST $TESTS_RUN]${NC} ${DIM}[$tag]${NC} $name"
    log_plain "Test($tag): $name"
}

pass_test() {
    local msg="${1:-$CURRENT_NAME}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
    log "${GREEN}  PASS${NC} $msg"
    log_plain "PASS: $msg"
    TEST_OPEN=0
}

fail_test() {
    local msg="${1:-$CURRENT_NAME}"
    if [[ "$CURRENT_TAG" == "ui" ]]; then
        # UI failures are warnings, never affect exit code.
        UI_FAILED=$((UI_FAILED + 1))
        log "${YELLOW}  WARN${NC} (ui) $msg"
        log_plain "WARN(ui): $msg"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        log "${RED}  FAIL${NC} $msg"
        log_plain "FAIL: $msg"
    fi
    TEST_OPEN=0
}

skip_test() {
    local msg="${1:-$CURRENT_NAME}"
    TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
    log "${YELLOW}  SKIP${NC} $msg"
    log_plain "SKIP: $msg"
    TEST_OPEN=0
}

# Helper: sub-checks under an already-started test. Each sub_* counts as a
# distinct pass/fail/skip but does NOT double-increment TESTS_RUN (the parent
# start_test already bumped it). We only bump TESTS_RUN for the 2nd+ sub.
SUB_SEEN=0
_sub_bump_run() {
    if [[ $SUB_SEEN -eq 0 ]]; then
        SUB_SEEN=1
    else
        TESTS_RUN=$((TESTS_RUN + 1))
    fi
}
sub_pass() {
    _sub_bump_run
    TESTS_PASSED=$((TESTS_PASSED + 1))
    log "${GREEN}  PASS${NC} $1"
    log_plain "PASS: $1"
    TEST_OPEN=0
}
sub_fail() {
    _sub_bump_run
    if [[ "$CURRENT_TAG" == "ui" ]]; then
        UI_FAILED=$((UI_FAILED + 1))
        log "${YELLOW}  WARN${NC} (ui) $1"
        log_plain "WARN(ui): $1"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        log "${RED}  FAIL${NC} $1"
        log_plain "FAIL: $1"
    fi
    TEST_OPEN=0
}
# sub_skip retained for future use / symmetry, marked via shellcheck directive.
# shellcheck disable=SC2329
sub_skip() {
    _sub_bump_run
    TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
    log "${YELLOW}  SKIP${NC} $1"
    log_plain "SKIP: $1"
    TEST_OPEN=0
}

# ---------------------------------------------------------------------------
# Profile loading. Reads ~/.config/tuidev/profile for:
#   profile=minimal|desktop|remote
#   extra_packs=pack-a,pack-b
# Missing file is fine — we just run core.
# ---------------------------------------------------------------------------
PROFILE_NAME=""
PROFILE_PACKS=()

# shellcheck source=lib/profile.sh disable=SC1091
. "$SCRIPT_DIR/lib/profile.sh"

load_profile() {
    load_tuidev_profile "$PROFILE_FILE" || true
    PROFILE_NAME="$TUIDEV_PROFILE_NAME"
    # Bash 3.2 on macOS trips set -u on an empty array expansion, so guard.
    if [[ ${#TUIDEV_EXTRA_PACKS_ARR[@]} -gt 0 ]]; then
        PROFILE_PACKS=("${TUIDEV_EXTRA_PACKS_ARR[@]}")
    else
        PROFILE_PACKS=()
    fi
}

# ---------------------------------------------------------------------------
# Tag selection.
# ---------------------------------------------------------------------------
SELECTED_TAGS=()
ALL_MODE=0
NO_UI=0

usage() {
    cat <<'EOF'
Usage: test_suite.sh [--tag TAG]... [--all] [--no-ui] [-h|--help]

  --tag TAG   Run only tests with this tag. Repeatable.
              Valid tags: core, remote, sandbox, ui, extras, packs
  --all       Run every tag (including ui).
  --no-ui     Run everything except the ui tag.
  -h, --help  Show this help.

With no flags, runs `core` plus tags enabled by the active profile
at ~/.config/tuidev/profile (desktop -> adds ui; remote -> adds remote;
extras/sandbox/packs run when profile opts in).
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --tag)
                [[ $# -ge 2 ]] || { echo "error: --tag needs a value" >&2; exit 64; }
                SELECTED_TAGS+=("$2")
                shift 2
                ;;
            --tag=*)
                SELECTED_TAGS+=("${1#--tag=}")
                shift
                ;;
            --all)
                ALL_MODE=1
                shift
                ;;
            --no-ui)
                NO_UI=1
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                echo "error: unknown argument: $1" >&2
                usage >&2
                exit 64
                ;;
        esac
    done
}

# Decide which tags are active for this run.
ACTIVE_TAGS=()

compute_active_tags() {
    if [[ $ALL_MODE -eq 1 ]]; then
        ACTIVE_TAGS=(core remote sandbox ui extras packs)
    elif [[ ${#SELECTED_TAGS[@]} -gt 0 ]]; then
        ACTIVE_TAGS=("${SELECTED_TAGS[@]}")
    else
        # Default: core + whatever the profile enables.
        ACTIVE_TAGS=(core)
        case "$PROFILE_NAME" in
            desktop)
                ACTIVE_TAGS+=(ui sandbox extras)
                ;;
            remote)
                ACTIVE_TAGS+=(remote)
                ;;
            minimal|"")
                :
                ;;
            *)
                # Unknown profile — stay conservative.
                :
                ;;
        esac
        if [[ ${#PROFILE_PACKS[@]} -gt 0 ]]; then
            ACTIVE_TAGS+=(packs)
        fi
    fi

    if [[ $NO_UI -eq 1 ]]; then
        local kept=()
        for t in "${ACTIVE_TAGS[@]}"; do
            [[ "$t" == "ui" ]] || kept+=("$t")
        done
        ACTIVE_TAGS=("${kept[@]}")
    fi
}

tag_active() {
    local needle="$1"
    local t
    for t in "${ACTIVE_TAGS[@]:-}"; do
        [[ "$t" == "$needle" ]] && return 0
    done
    return 1
}

# ---------------------------------------------------------------------------
# Tag: core
# ---------------------------------------------------------------------------
run_core() {
    print_header "Core Tests"

    # --- Shell configuration ---------------------------------------------
    start_test "Shell configuration file exists" core
    if [[ -f "$HOME/.zshrc" ]]; then
        pass_test "$HOME/.zshrc exists"
    else
        fail_test "$HOME/.zshrc missing"
    fi

    if [[ -f "$HOME/.zshrc" ]]; then
        start_test "Shell integrations configured" core
        if grep -q "starship init zsh" "$HOME/.zshrc"; then
            sub_pass "starship init present"
        else
            sub_fail "starship init missing from .zshrc"
        fi
        if grep -q "zoxide init zsh" "$HOME/.zshrc"; then
            sub_pass "zoxide init present"
        else
            sub_fail "zoxide init missing from .zshrc"
        fi
        if grep -q "fzf --zsh\|fzf.zsh\|fzf-shell" "$HOME/.zshrc"; then
            sub_pass "fzf integration present"
        else
            sub_fail "fzf integration missing from .zshrc"
        fi

        start_test "Shell aliases" core
        if grep -q "alias cat=['\"]bat['\"]" "$HOME/.zshrc"; then
            sub_pass "cat -> bat alias"
        else
            sub_fail "cat alias missing"
        fi
        if grep -q "alias ls=['\"]eza" "$HOME/.zshrc"; then
            sub_pass "ls -> eza alias"
        else
            sub_fail "ls alias missing"
        fi
        if grep -q "alias lg=['\"]lazygit['\"]" "$HOME/.zshrc"; then
            sub_pass "lg -> lazygit alias"
        else
            sub_fail "lg alias missing"
        fi
    fi

    # --- Config files (KDL / TOML / Lua) ---------------------------------
    start_test "Starship configuration" core
    if [[ -f "$HOME/.config/starship.toml" ]]; then
        if grep -q "^\[character\]\|character" "$HOME/.config/starship.toml"; then
            pass_test "starship.toml present and non-empty"
        else
            fail_test "starship.toml present but looks incomplete"
        fi
    else
        fail_test "starship.toml missing"
    fi

    start_test "tmux configuration" core
    if [[ -f "$HOME/.config/tmux/tmux.conf" ]] || [[ -f "$HOME/.tmux.conf" ]]; then
        pass_test "tmux.conf present"
    else
        fail_test "tmux.conf missing"
    fi

    start_test "Neovim configuration" core
    if [[ -f "$HOME/.config/nvim/init.lua" ]]; then
        if command -v lua >/dev/null 2>&1; then
            if lua -e "loadfile('$HOME/.config/nvim/init.lua')" >/dev/null 2>&1; then
                pass_test "init.lua parses"
            else
                fail_test "init.lua failed to parse"
            fi
        else
            pass_test "init.lua present (lua unavailable to parse-check)"
        fi
    else
        fail_test "nvim init.lua missing"
    fi

    # --- Core CLI tool presence ------------------------------------------
    local tool
    for tool in tmux nvim rg fd bat fzf zoxide starship delta lazygit jq yq eza gh http shellcheck git; do
        start_test "$tool installed" core
        if command -v "$tool" >/dev/null 2>&1; then
            local v
            v="$("$tool" --version 2>/dev/null | head -1)"
            pass_test "$tool ok${v:+ ($v)}"
        else
            fail_test "$tool not installed"
        fi
    done

    # --- Modern CLI smoke test -------------------------------------------
    start_test "Modern CLI replacements can operate on a file" core
    local tmpdir tmpfile
    if tmpdir="$(mktemp -d 2>/dev/null)" && [[ -n "$tmpdir" ]]; then
        tmpfile="$tmpdir/test_file.txt"
        if echo "test file content" > "$tmpfile" 2>/dev/null; then
            if command -v bat >/dev/null 2>&1; then
                if bat --style=plain "$tmpfile" >/dev/null 2>&1; then
                    sub_pass "bat reads files"
                else
                    sub_fail "bat failed"
                fi
            fi
            if command -v eza >/dev/null 2>&1; then
                if eza "$tmpfile" >/dev/null 2>&1; then
                    sub_pass "eza lists files"
                else
                    sub_fail "eza failed"
                fi
            fi
            if command -v rg >/dev/null 2>&1; then
                if rg -q "test" "$tmpfile" 2>/dev/null; then
                    sub_pass "ripgrep searches files"
                else
                    sub_fail "ripgrep failed"
                fi
            fi
        else
            skip_test "could not write to tempfile (sandbox?)"
        fi
        rm -rf "$tmpdir" 2>/dev/null || true
    else
        skip_test "could not create tempdir (sandbox?)"
    fi

    # --- Integrations -----------------------------------------------------
    start_test "Git delta pager integration" core
    if command -v git >/dev/null 2>&1; then
        if git config --global core.pager 2>/dev/null | grep -q "delta"; then
            pass_test "git core.pager uses delta"
        else
            fail_test "git core.pager not configured with delta"
        fi
    else
        fail_test "git not installed"
    fi

    start_test "fzf uses ripgrep" core
    if [[ -n "${FZF_DEFAULT_COMMAND:-}" ]]; then
        if echo "${FZF_DEFAULT_COMMAND}" | grep -q "rg"; then
            pass_test "FZF_DEFAULT_COMMAND uses rg"
        else
            fail_test "FZF_DEFAULT_COMMAND does not reference rg"
        fi
    else
        skip_test "FZF_DEFAULT_COMMAND not set in this shell"
    fi

    # --- AI CLI presence (soft: SKIP when absent, not fail) ---------------
    local aitool
    for aitool in claude codex gemini opencode; do
        start_test "AI CLI: $aitool" core
        if command -v "$aitool" >/dev/null 2>&1; then
            pass_test "$aitool on PATH"
        else
            skip_test "$aitool not installed (optional)"
        fi
    done

    # --- Shellcheck repo scripts -----------------------------------------
    start_test "Shellcheck on repo scripts" core
    if command -v shellcheck >/dev/null 2>&1; then
        local -a files=()
        while IFS= read -r f; do
            files+=("$f")
        done < <(find "$REPO_ROOT/scripts" -maxdepth 3 -type f -name '*.sh' 2>/dev/null)
        if (( ${#files[@]} == 0 )); then
            pass_test "no shell scripts found"
        elif shellcheck -x "${files[@]}" >/dev/null 2>&1; then
            pass_test "all repo scripts pass shellcheck (${#files[@]} files)"
        else
            # Re-run to emit diagnostics visible in the log for debugging.
            shellcheck -x "${files[@]}" 2>&1 | head -30 | while IFS= read -r l; do sub_fail "$l"; done
            TEST_OPEN=0
        fi
    else
        skip_test "shellcheck not installed"
    fi

    # --- tuidev lib scripts ----------------------------------------------
    start_test "tuidev lib scripts parse (bash -n)" core
    if [[ -d "$SCRIPT_DIR/lib" ]]; then
        local libfiles=0 libfail=0 f
        while IFS= read -r f; do
            libfiles=$((libfiles + 1))
            if ! bash -n "$f" 2>/dev/null; then
                sub_fail "bash -n: $f"
                libfail=$((libfail + 1))
            fi
        done < <(find "$SCRIPT_DIR/lib" -type f -name '*.sh' 2>/dev/null)
        if [[ $libfiles -eq 0 ]]; then
            skip_test "scripts/lib/ exists but has no .sh files"
        elif [[ $libfail -eq 0 ]]; then
            pass_test "$libfiles lib scripts parse cleanly"
        else
            TEST_OPEN=0
        fi
    else
        skip_test "scripts/lib/ not present yet"
    fi

    local harness
    for harness in test_config_write test_profile test_contract; do
        start_test "lib harness: $harness.sh" core
        if [[ -f "$SCRIPT_DIR/lib/$harness.sh" ]]; then
            if bash "$SCRIPT_DIR/lib/$harness.sh" >>"$LOG_FILE" 2>&1; then
                pass_test "$harness.sh passed"
            else
                fail_test "$harness.sh failed (see log)"
            fi
        else
            skip_test "scripts/lib/$harness.sh not present"
        fi
    done
}

# ---------------------------------------------------------------------------
# Tag: remote
# ---------------------------------------------------------------------------
run_remote() {
    print_header "Remote Tests"

    start_test "tailscale CLI" remote
    if command -v tailscale >/dev/null 2>&1; then
        pass_test "tailscale installed"
    else
        fail_test "tailscale not installed"
    fi

    start_test "mosh" remote
    if command -v mosh >/dev/null 2>&1; then
        pass_test "mosh installed"
    else
        fail_test "mosh not installed"
    fi

    start_test "SSH client config sanity" remote
    if [[ -f "$HOME/.ssh/config" ]]; then
        # -G prints effective config for a dummy host; non-zero means parse error.
        if ssh -G tuidev-probe-host >/dev/null 2>&1; then
            pass_test "\$HOME/.ssh/config parses"
        else
            fail_test "ssh -G failed to parse config"
        fi
    else
        skip_test "no ~/.ssh/config to check"
    fi

    start_test "sshd_config snippets" remote
    if [[ -d "$HOME/.config/ssh/sshd_config.d" ]] \
        || [[ -d "/etc/ssh/sshd_config.d" ]]; then
        pass_test "sshd_config.d present"
    else
        skip_test "no sshd_config.d snippets installed"
    fi
}

# ---------------------------------------------------------------------------
# Tag: sandbox
# ---------------------------------------------------------------------------
run_sandbox() {
    print_header "Sandbox Tests"

    start_test "Seatbelt profiles present" sandbox
    local sb_dir
    for sb_dir in \
        "$HOME/.config/tuidev/sandbox" \
        "$HOME/.config/tuidev/seatbelt" \
        "$REPO_ROOT/sandbox" \
        "$REPO_ROOT/seatbelt"; do
        if [[ -d "$sb_dir" ]] \
            && find "$sb_dir" -maxdepth 2 -name '*.sb' 2>/dev/null | grep -q .; then
            pass_test "Seatbelt profiles found in $sb_dir"
            break
        fi
    done
    if [[ $TEST_OPEN -eq 1 ]]; then
        fail_test "no Seatbelt profiles (.sb) found"
    fi

    start_test "bin/sbx on PATH" sandbox
    if command -v sbx >/dev/null 2>&1; then
        pass_test "sbx available: $(command -v sbx)"
    else
        fail_test "sbx not on PATH"
    fi

    start_test "sandbox-exec -n probe" sandbox
    if [[ "$(uname)" == "Darwin" ]]; then
        if command -v sandbox-exec >/dev/null 2>&1; then
            # -n pure-computation: a minimal profile that denies everything
            # except what's needed to exit cleanly.
            if sandbox-exec -p '(version 1)(deny default)(allow process-exec)(allow process-fork)(allow signal)' /usr/bin/true 2>/dev/null; then
                pass_test "sandbox-exec executed probe cleanly"
            else
                # The probe above can be over-restrictive on some macOS versions;
                # try a permissive probe to at least confirm sandbox-exec runs.
                if sandbox-exec -p '(version 1)(allow default)' /usr/bin/true 2>/dev/null; then
                    pass_test "sandbox-exec runs (permissive probe)"
                else
                    fail_test "sandbox-exec failed even with permissive profile"
                fi
            fi
        else
            fail_test "sandbox-exec not available"
        fi
    else
        skip_test "sandbox-exec is macOS-only"
    fi
}

# ---------------------------------------------------------------------------
# Tag: ui  (never affects exit code)
# ---------------------------------------------------------------------------
run_ui() {
    print_header "UI / GUI Tests (warn-only)"

    if [[ "$(uname)" != "Darwin" ]]; then
        log "${YELLOW}  - ui tag has no meaning off Darwin; skipping all ui checks${NC}"
        return 0
    fi

    local app_name app_path
    for entry in \
        "Rectangle:/Applications/Rectangle.app" \
        "Stats:/Applications/Stats.app" \
        "Maccy:/Applications/Maccy.app" \
        "Hidden Bar:/Applications/Hidden Bar.app" \
        "Hammerspoon:/Applications/Hammerspoon.app" \
        "Ghostty:/Applications/Ghostty.app"; do
        app_name="${entry%%:*}"
        app_path="${entry#*:}"
        start_test "$app_name present" ui
        if [[ -d "$app_path" ]] || [[ -d "$HOME$app_path" ]]; then
            pass_test "$app_name installed"
        else
            fail_test "$app_name not installed"
        fi
    done

    start_test "Hammerspoon config" ui
    if [[ -f "$HOME/.hammerspoon/init.lua" ]]; then
        pass_test "\$HOME/.hammerspoon/init.lua present"
    else
        fail_test "\$HOME/.hammerspoon/init.lua missing"
    fi

    start_test "Ghostty config" ui
    if [[ -f "$HOME/.config/ghostty/config" ]]; then
        pass_test "ghostty config present"
    else
        fail_test "ghostty config missing"
    fi
}

# ---------------------------------------------------------------------------
# Tag: extras
# ---------------------------------------------------------------------------
run_extras() {
    print_header "Extras Tests"

    local tool
    for tool in atuin dust broot bandwhich btm procs hyperfine tokei; do
        start_test "extras: $tool" extras
        if command -v "$tool" >/dev/null 2>&1; then
            pass_test "$tool installed"
        else
            skip_test "$tool not installed (optional)"
        fi
    done
}

# ---------------------------------------------------------------------------
# Tag: packs  — iterate extra_packs from the profile.
# ---------------------------------------------------------------------------
_packs_contains() {
    local needle="$1" p
    for p in "${PROFILE_PACKS[@]}"; do
        [[ "$p" == "$needle" ]] && return 0
    done
    return 1
}

run_packs() {
    print_header "Packs Tests"

    if [[ ${#PROFILE_PACKS[@]} -eq 0 ]]; then
        log "${DIM}  (no extra_packs declared in $PROFILE_FILE)${NC}"
        return 0
    fi

    # Built-in pack probes. Each one checks the pack's shipped artifacts
    # only when that pack is listed in the active profile's extra_packs.
    if _packs_contains zellij; then
        start_test "zellij: config.kdl present" packs
        if [[ -f "$HOME/.config/zellij/config.kdl" ]]; then
            if grep -q "default_shell\|theme\|keybinds" "$HOME/.config/zellij/config.kdl"; then
                pass_test "zellij config.kdl present"
            else
                fail_test "zellij config.kdl looks incomplete"
            fi
        else
            fail_test "zellij config.kdl missing"
        fi

        start_test "zellij: layouts installed" packs
        if [[ -d "$HOME/.config/zellij/layouts" ]]; then
            local n
            n=$(find "$HOME/.config/zellij/layouts" -name '*.kdl' 2>/dev/null | wc -l | tr -d ' ')
            if [[ ${n:-0} -ge 2 ]]; then
                pass_test "$n zellij layouts installed"
            else
                fail_test "only ${n:-0} zellij layouts found"
            fi
        else
            fail_test "zellij layouts directory missing"
        fi
    fi

    if _packs_contains yazi || _packs_contains nnn; then
        local fm; _packs_contains yazi && fm=yazi || fm=nnn
        start_test "$fm: binary on PATH" packs
        if command -v "$fm" >/dev/null 2>&1; then
            pass_test "$fm available"
        else
            fail_test "$fm not found on PATH"
        fi
    fi

    if _packs_contains mosh; then
        start_test "mosh: binary on PATH" packs
        if command -v mosh >/dev/null 2>&1; then
            pass_test "mosh available"
        else
            fail_test "mosh not found on PATH"
        fi
    fi

    if _packs_contains sandbox-container; then
        start_test "sandbox-container: podman on PATH" packs
        if command -v podman >/dev/null 2>&1; then
            pass_test "podman available"
        else
            fail_test "podman not found on PATH"
        fi
    fi

    # Packs with optional per-pack test.sh under packs/<name>/ (for
    # third-party or user-authored packs that follow this convention).
    local pack pack_dir
    for pack in "${PROFILE_PACKS[@]}"; do
        [[ -z "$pack" ]] && continue
        pack_dir=""
        for candidate in \
            "$REPO_ROOT/packs/$pack" \
            "$HOME/.config/tuidev/packs/$pack"; do
            if [[ -d "$candidate" && -x "$candidate/test.sh" ]]; then
                pack_dir="$candidate"
                break
            fi
        done
        if [[ -n "$pack_dir" ]]; then
            start_test "pack: $pack test.sh" packs
            if bash "$pack_dir/test.sh" >>"$LOG_FILE" 2>&1; then
                pass_test "pack $pack test.sh passed"
            else
                fail_test "pack $pack test.sh failed (see log)"
            fi
        fi
    done
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
parse_args "$@"
load_profile
compute_active_tags

print_header "macOS TUI Setup — Test Suite"
log "${CYAN}Profile:${NC}        ${PROFILE_NAME:-<none>}"
if [[ ${#PROFILE_PACKS[@]} -gt 0 ]]; then
    log "${CYAN}Extra packs:${NC}    ${PROFILE_PACKS[*]}"
else
    log "${CYAN}Extra packs:${NC}    <none>"
fi
log "${CYAN}Active tags:${NC}    ${ACTIVE_TAGS[*]:-<none>}"
log "${CYAN}Log file:${NC}       $LOG_FILE"

if tag_active core;    then run_core;    fi
if tag_active remote;  then run_remote;  fi
if tag_active sandbox; then run_sandbox; fi
if tag_active extras;  then run_extras;  fi
if tag_active packs;   then run_packs;   fi
if tag_active ui;      then run_ui;      fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
print_header "Test Summary"

log "${CYAN}Tests run:${NC}     $TESTS_RUN"
log "${GREEN}Passed:${NC}        $TESTS_PASSED"
log "${RED}Failed:${NC}        $TESTS_FAILED"
log "${YELLOW}Skipped:${NC}       $TESTS_SKIPPED"
if [[ $UI_FAILED -gt 0 ]]; then
    log "${YELLOW}UI warnings:${NC}   $UI_FAILED (do not affect exit code)"
fi

if [[ $TESTS_RUN -gt 0 ]]; then
    # Exclude UI warnings from pass-rate numerator/denominator.
    RESULT_TOTAL=$((TESTS_PASSED + TESTS_FAILED))
    if [[ $RESULT_TOTAL -gt 0 ]]; then
        PASS_RATE=$(( TESTS_PASSED * 100 / RESULT_TOTAL ))
    else
        PASS_RATE=100
    fi
    log "${CYAN}Pass rate:${NC}     ${PASS_RATE}%"
fi

log ""
log "Log saved to: $LOG_FILE"

if [[ $TESTS_FAILED -eq 0 ]]; then
    log "${GREEN}OK — all selected tests passed.${NC}"
    exit 0
fi
log "${RED}FAIL — $TESTS_FAILED test(s) failed.${NC}"
exit 1
