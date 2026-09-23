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
#   ui      - GUI apps (Rectangle, Stats, Maccy, Hidden Bar, Ghostty).
#             Never affects exit code.
#   extras  - atuin, dust, broot, bandwhich, etc.
#   packs   - extra packs listed in the tuidev profile
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

# shellcheck source=lib/ui.sh disable=SC1091
. "$SCRIPT_DIR/lib/ui.sh"
# shellcheck source=lib/packs.sh disable=SC1091
. "$SCRIPT_DIR/lib/packs.sh"
# shellcheck source=lib/pkg.sh disable=SC1091
. "$SCRIPT_DIR/lib/pkg.sh"

PROFILE_FILE="${TUIDEV_PROFILE_FILE:-$TUIDEV_PROFILE_FILE_DEFAULT}"

# ---------------------------------------------------------------------------
# Output. Colors come from ui.sh (so NO_COLOR / TUIDEV_NO_COLOR / non-TTY are
# honored); log() and print_header below tee everything into the log file.
# ---------------------------------------------------------------------------
if [[ -n "$NC" ]]; then DIM='\033[2m'; else DIM=''; fi

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

start_test() {
    # start_test NAME TAG
    local name="$1"
    local tag="${2:-core}"
    TESTS_RUN=$((TESTS_RUN + 1))
    CURRENT_TAG="$tag"
    CURRENT_NAME="$name"
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
}

skip_test() {
    local msg="${1:-$CURRENT_NAME}"
    TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
    log "${YELLOW}  SKIP${NC} $msg"
    log_plain "SKIP: $msg"
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
}

# ---------------------------------------------------------------------------
# Profile loading (scripts/lib/profile.sh). Missing file is fine — we just
# run core.
# ---------------------------------------------------------------------------
PROFILE_NAME=""
PROFILE_PACKS=()

load_profile() {
    load_tuidev_profile "$PROFILE_FILE" || true
    PROFILE_NAME="$TUIDEV_PROFILE_NAME"
    # extra_packs, plus tmux for the remote profile (tuidev_extra_packs).
    PROFILE_PACKS=()
    local p
    while IFS= read -r p; do
        PROFILE_PACKS+=("$p")
    done < <(tuidev_extra_packs)
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

With no flags, runs `core` plus a tag for each built-in pack the recorded
profile enables (remote, sandbox, ui, extras), and `packs` when it lists
extra packs.
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
        # Default: core + a tag per built-in pack the profile records.
        ACTIVE_TAGS=(core)
        $TUIDEV_PACK_REMOTE  && ACTIVE_TAGS+=(remote)
        $TUIDEV_PACK_SANDBOX && ACTIVE_TAGS+=(sandbox)
        $TUIDEV_PACK_UI      && ACTIVE_TAGS+=(ui)
        $TUIDEV_PACK_EXTRAS  && ACTIVE_TAGS+=(extras)
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
    fi

    # --- Config files (TOML) --------------------------------------------
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

    # --- Core CLI tool presence (from core.sh's CORE_FORMULAE) -----------
    # On Linux without Homebrew a tool the distro may not package is a SKIP,
    # matching health_check.sh.
    local formula tool v
    while IFS= read -r formula; do
        tool="$(tuidev_formula_binary "$formula")"
        [[ -n "$tool" ]] || continue
        start_test "$tool installed" core
        if command -v "$tool" >/dev/null 2>&1; then
            v="$("$tool" --version 2>/dev/null | head -1)"
            pass_test "$tool ok${v:+ ($v)}"
        elif is_linux && ! command_exists brew && [[ -n "$(pkg_manual_hint "$formula")" ]]; then
            skip_test "$tool not installed (not packaged by every distro)"
        else
            fail_test "$tool not installed"
        fi
    done < <(pack_array core formulae)

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
    # install.sh sets core.pager only when the user has none, so another
    # pager is the user's choice, not a failure.
    start_test "Git delta pager integration" core
    local pager
    if ! command -v git >/dev/null 2>&1; then
        fail_test "git not installed"
    elif ! command -v delta >/dev/null 2>&1; then
        skip_test "delta not installed"
    else
        pager="$(git config --global core.pager 2>/dev/null || true)"
        case "$pager" in
            *delta*) pass_test "git core.pager uses delta" ;;
            "")      fail_test "git core.pager not configured (re-run install.sh)" ;;
            *)       skip_test "core.pager is '$pager' (your own setting; kept)" ;;
        esac
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

    # --- AI CLI presence (soft: SKIP when absent — opt-in --pack ai-clis) -
    local aitool
    local aipack
    for aitool in claude codex opencode; do
        start_test "AI CLI: $aitool" core
        case "$aitool" in opencode) aipack=opencode ;; *) aipack=ai-clis ;; esac
        if command -v "$aitool" >/dev/null 2>&1; then
            pass_test "$aitool on PATH"
        else
            skip_test "$aitool not installed (optional; --pack $aipack)"
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
            # Diagnostics go to the log. (Piping into sub_fail would count the
            # failures in a subshell and lose them.)
            shellcheck -x "${files[@]}" >>"$LOG_FILE" 2>&1
            fail_test "shellcheck findings (see $LOG_FILE)"
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
        fi
    else
        skip_test "scripts/lib/ not present yet"
    fi

    # Every scripts/lib/test_*.sh, so a new harness is picked up automatically
    # (the same glob CI and `make test-lib` use).
    local harness
    for harness in "$SCRIPT_DIR"/lib/test_*.sh; do
        [[ -f "$harness" ]] || continue
        start_test "lib harness: $(basename "$harness")" core
        if bash "$harness" >>"$LOG_FILE" 2>&1; then
            pass_test "$(basename "$harness") passed"
        else
            fail_test "$(basename "$harness") failed (see log)"
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
    local sb_dir="$TUIDEV_STATE_DIR/sandbox"
    if find "$sb_dir" -maxdepth 1 -name '*.sb' 2>/dev/null | grep -q .; then
        pass_test "Seatbelt profiles found in $sb_dir"
    else
        fail_test "no Seatbelt profiles (.sb) in $sb_dir"
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

    local cask app_name
    while IFS= read -r cask; do
        app_name="$(tuidev_cask_app "$cask")"
        start_test "$app_name present" ui
        if [[ -d "/Applications/$app_name.app" || -d "$HOME/Applications/$app_name.app" ]]; then
            pass_test "$app_name installed"
        else
            fail_test "$app_name not installed"
        fi
    done < <(pack_array ui casks; pack_array core casks)

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
    while IFS= read -r tool; do
        start_test "extras: $tool" extras
        if command -v "$tool" >/dev/null 2>&1; then
            pass_test "$tool installed"
        else
            skip_test "$tool not installed (optional)"
        fi
    done < <(pack_binaries extras)
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
    if _packs_contains tmux; then
        start_test "tmux configuration" packs
        if [[ -f "$HOME/.config/tmux/tmux.conf" ]] || [[ -f "$HOME/.tmux.conf" ]]; then
            pass_test "tmux.conf present"
        else
            fail_test "tmux.conf missing"
        fi
    fi

    if _packs_contains nvim; then
        start_test "Neovim configuration" packs
        if [[ -f "$HOME/.config/nvim/init.lua" ]]; then
            if command -v luac >/dev/null 2>&1; then
                if luac -p "$HOME/.config/nvim/init.lua" >/dev/null 2>&1; then
                    pass_test "init.lua parses"
                else
                    fail_test "init.lua failed to parse"
                fi
            else
                pass_test "init.lua present (luac unavailable to parse-check)"
            fi
        else
            fail_test "nvim init.lua missing"
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
        start_test "sandbox-container: a container runtime on PATH" packs
        if command -v container >/dev/null 2>&1 || command -v podman >/dev/null 2>&1 || command -v docker >/dev/null 2>&1; then
            pass_test "container runtime available (Apple container / podman / docker)"
        else
            fail_test "no container runtime found (Apple container, podman, or docker)"
        fi
    fi
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
