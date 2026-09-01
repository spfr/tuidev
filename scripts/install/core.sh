#!/bin/bash
# scripts/install/core.sh - install pack: essential CLI tools.
#
# Contract (shared by all pack scripts under scripts/install/):
#   - Source scripts/lib/ui.sh.
#   - Respect DRY_RUN=true|false from environment.
#   - Expose a function named after the pack (here: core_install).
#   - When sourced, only define functions; do nothing.
#   - When executed directly, call the entrypoint function.
#
# Scope of 'core':
#   terminal multiplexer, editor, search, nav, git UX, shell prompt, JSON/YAML,
#   shell plugins, shellcheck. No GUI apps, no remote stack, no sandbox tooling.
#   Ghostty is added on macOS only.
#
# Package managers:
#   macOS — Homebrew, required (as before).
#   Linux — Homebrew when present, else apt-get. Homebrew has no aarch64 Linux
#   build, so an apt fallback is the only way --profile minimal/remote works on
#   a Raspberry Pi or any arm64 Debian. Availability is probed per package
#   rather than hardcoded, because the core tools are spread unevenly across
#   Debian/Ubuntu releases (eza, starship, lazygit and git-delta are all
#   missing from bookworm). Anything apt cannot provide
#   is skipped with a pointer to its official install page — we never pipe a
#   remote installer into a shell (same policy as packs/herdr.sh).

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/ui.sh disable=SC1091
. "$SCRIPT_DIR/../lib/ui.sh"
# shellcheck source=../lib/brew.sh disable=SC1091
. "$SCRIPT_DIR/../lib/brew.sh"

# Formula list (Homebrew). Kept alphabetized for drift-diff friendliness.
CORE_FORMULAE=(
    bat
    eza
    fd
    fzf
    gh
    git
    git-delta
    httpie
    jq
    lazygit
    neovim
    ripgrep
    shellcheck
    starship
    tmux
    yq
    zoxide
    zsh-autosuggestions
    zsh-completions
    zsh-syntax-highlighting
)

# Formula that require --cask on macOS only.
CORE_CASKS_MACOS=(
    ghostty
)

# --- Linux / apt fallback -------------------------------------------------
#
# Kept bash-3.2-clean (no associative arrays) per docs/engineering.md.

# Debian/Ubuntu package name for a core formula. Most match one-for-one; the
# exceptions are renamed by Debian policy.
_core_apt_pkg() {
    case "$1" in
        fd) echo "fd-find" ;;   # ships the binary as `fdfind`
        *)  echo "$1" ;;
    esac
}

# Official install pointer, printed when apt has no candidate for a tool.
# Deliberately instructions, not commands we run.
_core_manual_hint() {
    case "$1" in
        eza)       echo "https://github.com/eza-community/eza/blob/main/INSTALL.md" ;;
        starship)  echo "https://starship.rs/guide/" ;;
        lazygit)   echo "https://github.com/jesseduffield/lazygit#installation" ;;
        git-delta) echo "https://dandavison.github.io/delta/installation.html" ;;
        gh)        echo "https://github.com/cli/cli/blob/trunk/docs/install_linux.md" ;;
        yq)        echo "https://github.com/mikefarah/yq#install" ;;
        zoxide)    echo "https://github.com/ajeetdsouza/zoxide#installation" ;;
        neovim)    echo "https://github.com/neovim/neovim/blob/master/INSTALL.md" ;;
        *)         echo "" ;;
    esac
}

# Echo the sudo prefix needed for apt ("" when already root, "sudo" when
# passwordless sudo works). Returns non-zero when apt would need a password —
# the caller prints instructions rather than hanging on a hidden prompt.
_core_sudo_prefix() {
    if [[ "$(id -u)" -eq 0 ]]; then
        echo ""
        return 0
    fi
    if command_exists sudo && sudo -n true 2>/dev/null; then
        echo "sudo"
        return 0
    fi
    return 1
}

# Some Debian packages carry the right name but are a DIFFERENT tool. Taking
# them would be worse than skipping: the user gets a familiar command with
# foreign behavior. Debian's `yq` is kislyuk's Python jq-wrapper, not the
# mikefarah/yq v4 this repo expects (the Dockerfile fetches v4 upstream for the
# same reason). Treat these as unavailable and point at the real project.
_core_apt_is_different_tool() {
    case "$1" in
        yq) return 0 ;;
        *)  return 1 ;;
    esac
}

# True when apt has an installable candidate for the package.
_core_apt_has() {
    local cand
    cand="$(apt-cache policy "$1" 2>/dev/null | awk -F': ' '/Candidate:/ {print $2; exit}')"
    [[ -n "$cand" && "$cand" != "(none)" ]]
}

# Debian renames some binaries to avoid collisions (fd-find → fdfind,
# bat → batcat). Put a correctly-named symlink on PATH so the shell config,
# aliases, and docs work unchanged.
_core_link_debian_binary() {
    local want="$1" have="$2" src bindir
    if command_exists "$want"; then
        return 0
    fi
    src="$(command -v "$have" 2>/dev/null || true)"
    if [[ -z "$src" ]]; then
        return 0
    fi
    bindir="$HOME/.local/bin"
    run_cmd mkdir -p "$bindir"
    run_cmd ln -sf "$src" "$bindir/$want"
    tuidev_manifest_record file "$bindir/$want"
    print_info "linked $want -> $have in $bindir (Debian renames this binary)"
}

# Split CORE_FORMULAE into apt package names this release can install and
# formulae it cannot. Sets the caller's `available` / `unavailable` arrays.
# Run this AFTER `apt-get update` where possible: an empty or stale package
# list would otherwise make every probe look unavailable.
_core_partition_apt() {
    available=()
    unavailable=()
    local formula pkg
    for formula in "${CORE_FORMULAE[@]}"; do
        pkg="$(_core_apt_pkg "$formula")"
        if _core_apt_is_different_tool "$formula"; then
            unavailable+=("$formula")
        elif _core_apt_has "$pkg"; then
            available+=("$pkg")
        else
            unavailable+=("$formula")
        fi
    done
}

_core_install_linux_apt() {
    local -a available=() unavailable=()
    local sudo_prefix

    if ! sudo_prefix="$(_core_sudo_prefix)"; then
        # No root and sudo would prompt. Never hang on a hidden password
        # prompt — probe the (possibly stale) lists and hand over the commands.
        _core_partition_apt
        print_warning "apt-get needs root and passwordless sudo is not available."
        print_info "Run this yourself, then re-run the installer:"
        print_info "    sudo apt-get update"
        if [[ ${#available[@]} -gt 0 ]]; then
            print_info "    sudo apt-get install -y ${available[*]}"
        fi
        _core_report_linux "${#available[@]}" "${unavailable[@]}"
        return 0
    fi

    local -a SUDO=()
    if [[ -n "$sudo_prefix" ]]; then
        SUDO=(sudo)
    fi

    print_step "updating apt package lists"
    run_cmd "${SUDO[@]}" apt-get update -y \
        || print_warning "apt-get update failed (continuing with cached lists)"

    _core_partition_apt

    if [[ ${#available[@]} -gt 0 ]]; then
        print_step "installing ${#available[@]} package(s) via apt"
        run_cmd "${SUDO[@]}" apt-get install -y "${available[@]}" \
            || print_warning "apt-get install returned an error (some packages may be missing)"
        # Record only packages that actually landed (dpkg confirms), same
        # "record what we actually installed" discipline as brew.sh. `apt` is
        # a new manifest kind uninstall.sh does not act on yet (it purges brew
        # formulae/casks only); tuidev_manifest_values filters by kind, so an
        # unread kind is inert rather than breaking manifest consumption.
        local pkg
        for pkg in "${available[@]}"; do
            dpkg -s "$pkg" >/dev/null 2>&1 && tuidev_manifest_record apt "$pkg"
        done
    fi

    # Restore the expected command names for Debian's renamed binaries.
    _core_link_debian_binary fd  fdfind
    _core_link_debian_binary bat batcat

    _core_report_linux "${#available[@]}" "${unavailable[@]}"
}

# End-of-run summary: what apt installed, and what needs a manual step.
_core_report_linux() {
    local installed_count="$1"; shift
    local -a skipped=("$@")

    print_success "apt had $installed_count of ${#CORE_FORMULAE[@]} core tool(s) available"

    if [[ ${#skipped[@]} -eq 0 ]]; then
        return 0
    fi

    print_warning "not packaged for this release — install these yourself if you want them:"
    local formula hint
    for formula in "${skipped[@]}"; do
        hint="$(_core_manual_hint "$formula")"
        if [[ -n "$hint" ]]; then
            print_info "    $formula — $hint"
        else
            print_info "    $formula — check your distribution or the upstream project"
        fi
    done
    print_info "The setup works without them; nothing else depends on these."
}

core_install() {
    print_header "Pack: core"

    if is_macos; then
        command_exists brew || die "Homebrew is required on macOS; install from https://brew.sh"
        brew_update_once
        brew_install_formulae "${CORE_FORMULAE[@]}"
        brew_install_casks "${CORE_CASKS_MACOS[@]}"
        print_success "core pack complete"
        return 0
    fi

    # Linux: brew if the user has it (x86_64 only upstream), else apt.
    if command_exists brew; then
        print_info "brew detected on Linux; using brew for formulae"
        brew_update_once
        brew_install_formulae "${CORE_FORMULAE[@]}"
    elif command_exists apt-get; then
        print_info "no Homebrew; using apt-get (Homebrew has no aarch64 Linux build)"
        _core_install_linux_apt
    else
        die "core needs Homebrew or apt-get. Install Homebrew (https://brew.sh) or use your distribution's package manager."
    fi

    print_success "core pack complete"
}

# Run if executed directly.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    core_install "$@"
fi
