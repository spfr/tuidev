#!/bin/bash
# scripts/lib/pkg.sh - one package-manager dispatch for every pack.
#
# Sources ui.sh, brew.sh and manifest.sh itself. Idempotent; bash 3.2-clean.
#
#   . "$(dirname "${BASH_SOURCE[0]}")/pkg.sh"
#   pkg_install mosh || print_warning "mosh unavailable (continuing)"
#
# Exposes:
#   pkg_manager            print brew|apt|dnf|pacman, or return 1
#   pkg_install NAME...    install Homebrew-named packages with that manager
#   pkg_manual_hint NAME   upstream install page for a tool distros may lack
#   PKG_UNAVAILABLE        array: names the last pkg_install could not provide
#
# Names are Homebrew formula names; distro renames are mapped here. Order:
# Homebrew (macOS, or Linux when the user has it) → apt-get → dnf → pacman.
# System managers run as root or through `sudo -n` only — never a hidden
# password prompt. Without either, the exact commands are printed instead.
# Failures are soft: pkg_install warns, fills PKG_UNAVAILABLE and returns 1;
# the caller decides whether that matters. DRY_RUN is honored throughout, and
# every package actually installed is recorded in the manifest
# (`formula NAME` via brew.sh, `apt|dnf|pacman PKG` here).

if [[ -n "${_TUIDEV_PKG_LOADED:-}" ]]; then
    return 0
fi
_TUIDEV_PKG_LOADED=1

# shellcheck source=./brew.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/brew.sh"

PKG_UNAVAILABLE=()

pkg_manager() {
    if command_exists brew; then
        echo brew
    elif ! is_linux; then
        return 1
    elif command_exists apt-get; then
        echo apt
    elif command_exists dnf; then
        echo dnf
    elif command_exists pacman; then
        echo pacman
    else
        return 1
    fi
}

# Official install pointer for tools a distribution may not package.
# Instructions to print, never commands we run.
pkg_manual_hint() {
    case "$1" in
        eza)       echo "https://github.com/eza-community/eza/blob/main/INSTALL.md" ;;
        starship)  echo "https://starship.rs/guide/" ;;
        lazygit)   echo "https://github.com/jesseduffield/lazygit#installation" ;;
        git-delta) echo "https://dandavison.github.io/delta/installation.html" ;;
        gh)        echo "https://github.com/cli/cli/blob/trunk/docs/install_linux.md" ;;
        yq)        echo "https://github.com/mikefarah/yq#install" ;;
        zoxide)    echo "https://github.com/ajeetdsouza/zoxide#installation" ;;
        neovim)    echo "https://github.com/neovim/neovim/blob/master/INSTALL.md" ;;
        mosh)      echo "https://mosh.org/#getting" ;;
        podman)    echo "https://podman.io/docs/installation" ;;
        *)         echo "" ;;
    esac
}

# Distro package name for a Homebrew formula name.
_pkg_native_name() {
    case "$1:$2" in
        apt:fd|dnf:fd) echo "fd-find" ;;   # Debian/Fedora ship the binary as fdfind
        *)             echo "$2" ;;
    esac
}

# Same name, different tool: taking these is worse than skipping — a familiar
# command with foreign behavior. Debian's `yq` is kislyuk's Python jq-wrapper,
# not the mikefarah/yq v4 this repo expects.
_pkg_is_different_tool() {
    case "$1:$2" in
        apt:yq) return 0 ;;
        *)      return 1 ;;
    esac
}

_pkg_is_installed() {
    case "$1" in
        apt)    dpkg -s "$2" >/dev/null 2>&1 ;;
        dnf)    rpm -q "$2" >/dev/null 2>&1 ;;
        pacman) pacman -Qi "$2" >/dev/null 2>&1 ;;
    esac
}

# True when the manager has an installable candidate.
_pkg_is_available() {
    case "$1" in
        apt)
            local cand
            cand="$(apt-cache policy "$2" 2>/dev/null | awk -F': ' '/Candidate:/ {print $2; exit}')"
            [[ -n "$cand" && "$cand" != "(none)" ]]
            ;;
        dnf)    dnf -q info "$2" >/dev/null 2>&1 ;;
        pacman) pacman -Si "$2" >/dev/null 2>&1 ;;
    esac
}

# The install command, without any sudo prefix.
_pkg_install_cmd() {
    case "$1" in
        apt)    echo "apt-get install -y" ;;
        dnf)    echo "dnf install -y" ;;
        pacman) echo "pacman -S --noconfirm --needed" ;;
    esac
}

# Echo the privilege prefix ("" as root, "sudo -n" with passwordless sudo).
# Non-zero when a password would be needed.
_pkg_sudo_prefix() {
    if [[ "$(id -u)" -eq 0 ]]; then
        echo ""
    elif command_exists sudo && sudo -n true 2>/dev/null; then
        echo "sudo -n"
    else
        return 1
    fi
}

# apt's lists go stale on a fresh box and make every probe look unavailable;
# refresh once per process. dnf and pacman resolve metadata on install.
_pkg_refresh_once() {
    [[ "$1" == apt ]] || return 0
    [[ -n "${_TUIDEV_PKG_REFRESHED:-}" ]] && return 0
    _TUIDEV_PKG_REFRESHED=1
    print_step "updating apt package lists"
    # shellcheck disable=SC2086  # $2 is a deliberately word-split prefix
    run_cmd $2 apt-get update -y || print_warning "apt-get update failed (continuing with cached lists)"
}

# _pkg_report_unavailable WHY — list PKG_UNAVAILABLE with install pointers.
_pkg_report_unavailable() {
    [[ ${#PKG_UNAVAILABLE[@]} -gt 0 ]] || return 0
    print_warning "$1 — install these yourself if you want them:"
    local name hint
    for name in "${PKG_UNAVAILABLE[@]}"; do
        hint="$(pkg_manual_hint "$name")"
        print_info "    $name — ${hint:-check your distribution or the upstream project}"
    done
}

# _pkg_install_native MGR NAME... — probe, then one batched install.
_pkg_install_native() {
    local mgr="$1"; shift
    local sudo_prefix name pkg rc=0
    local -a wanted=()

    if ! sudo_prefix="$(_pkg_sudo_prefix)"; then
        print_warning "$mgr needs root and passwordless sudo is not available."
        print_info "Run this yourself, then re-run the installer:"
        [[ "$mgr" == apt ]] && print_info "    sudo apt-get update"
        for name in "$@"; do wanted+=("$(_pkg_native_name "$mgr" "$name")"); done
        print_info "    sudo $(_pkg_install_cmd "$mgr") ${wanted[*]}"
        PKG_UNAVAILABLE=("$@")
        return 1
    fi

    _pkg_refresh_once "$mgr" "$sudo_prefix"

    for name in "$@"; do
        pkg="$(_pkg_native_name "$mgr" "$name")"
        if _pkg_is_different_tool "$mgr" "$name"; then
            PKG_UNAVAILABLE+=("$name")
        elif _pkg_is_installed "$mgr" "$pkg"; then
            print_success "$name (already present)"
        elif _pkg_is_available "$mgr" "$pkg"; then
            wanted+=("$pkg")
        else
            PKG_UNAVAILABLE+=("$name")
        fi
    done

    if [[ ${#wanted[@]} -gt 0 ]]; then
        print_step "installing ${wanted[*]} via $mgr"
        # shellcheck disable=SC2046,SC2086  # prefix and command word-split on purpose
        if ! run_cmd $sudo_prefix $(_pkg_install_cmd "$mgr") "${wanted[@]}"; then
            print_warning "$mgr install returned an error (some packages may be missing)"
            rc=1
        fi
        # Record only what actually landed — same discipline as brew.sh.
        for pkg in "${wanted[@]}"; do
            _pkg_is_installed "$mgr" "$pkg" && tuidev_manifest_record "$mgr" "$pkg"
        done
    fi

    _pkg_report_unavailable "not available from $mgr"
    [[ ${#PKG_UNAVAILABLE[@]} -eq 0 ]] || rc=1
    return $rc
}

# pkg_install NAME... — see the header. Returns 1 when anything could not be
# provided (PKG_UNAVAILABLE lists it); never exits the caller.
pkg_install() {
    PKG_UNAVAILABLE=()
    [[ $# -gt 0 ]] || return 0

    local mgr
    if ! mgr="$(pkg_manager)"; then
        PKG_UNAVAILABLE=("$@")
        if is_macos; then
            _pkg_report_unavailable "Homebrew (https://brew.sh) is not installed"
        else
            _pkg_report_unavailable "no supported package manager (brew, apt-get, dnf, pacman)"
        fi
        return 1
    fi

    if [[ "$mgr" == brew ]]; then
        brew_update_once
        brew_install_formulae "$@"   # warns per failure; never fatal
        return 0
    fi
    _pkg_install_native "$mgr" "$@"
}
