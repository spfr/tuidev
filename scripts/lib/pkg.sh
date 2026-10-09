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
# For update.sh on apt/dnf/pacman (brew has its own outdated/upgrade path):
#   pkg_native_tracked MGR NAME...   the NAMEs installed through MGR
#   pkg_native_outdated MGR NAME...  the tracked NAMEs with a newer version
#                                    (returns 2 when the probe failed)
#   pkg_native_refresh MGR           refresh apt lists when root is available
#   pkg_native_upgrade MGR NAME...   upgrade installed packages, or print how
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
        hunk)      echo "https://github.com/modem-dev/hunk#install" ;;
        uv)        echo "https://docs.astral.sh/uv/getting-started/installation/" ;;
        xh)        echo "https://github.com/ducaale/xh#installation" ;;
        podman)    echo "https://podman.io/docs/installation" ;;
        zsh-completions) echo "optional: Debian's zsh already ships most completions; https://github.com/zsh-users/zsh-completions" ;;
        *)         echo "" ;;
    esac
}

# Distro package name for a Homebrew formula name.
_pkg_native_name() {
    case "$1:$2" in
        apt:fd|dnf:fd) echo "fd-find" ;;   # Debian/Fedora ship the binary as fdfind
        apt:dust)      echo "du-dust" ;;   # binary is still dust
        apt:bottom)    echo "btm" ;;       # binary is still btm
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
        # Status, not mere presence: removed-but-configured ("rc") isn't installed.
        apt)    dpkg -s "$2" 2>/dev/null | grep -q '^Status: install ok installed' ;;
        dnf)    rpm -q "$2" >/dev/null 2>&1 ;;
        pacman) pacman -Qi "$2" >/dev/null 2>&1 ;;
    esac
}

# True when the manager has an installable candidate.
_pkg_is_available() {
    case "$1" in
        apt)
            local cand
            cand="$(LC_ALL=C apt-cache policy "$2" 2>/dev/null | awk -F': ' '/Candidate:/ {print $2; exit}')"
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

# _pkg_install_native MGR NAME... — skip what's present, probe, then one
# batched install. Root (or sudo -n) is needed only when something is missing.
_pkg_install_native() {
    local mgr="$1"; shift
    local sudo_prefix name pkg rc=0
    local -a missing=() wanted=()

    for name in "$@"; do
        pkg="$(_pkg_native_name "$mgr" "$name")"
        if _pkg_is_different_tool "$mgr" "$name"; then
            PKG_UNAVAILABLE+=("$name")
        elif _pkg_is_installed "$mgr" "$pkg"; then
            print_success "$name (already present)"
        else
            missing+=("$name")
        fi
    done

    local root=yes
    if [[ ${#missing[@]} -gt 0 ]]; then
        if sudo_prefix="$(_pkg_sudo_prefix)"; then
            _pkg_refresh_once "$mgr" "$sudo_prefix"
        else
            root=""
        fi
    fi

    # Without root the probe reads the cached lists; that still beats asking
    # the user to install a package the distribution doesn't ship.
    local -a wanted_names=()
    for name in ${missing[@]+"${missing[@]}"}; do
        pkg="$(_pkg_native_name "$mgr" "$name")"
        if _pkg_is_available "$mgr" "$pkg"; then
            wanted+=("$pkg")
            wanted_names+=("$name")
        else
            PKG_UNAVAILABLE+=("$name")
        fi
    done

    if [[ -z "$root" ]]; then
        _pkg_report_unavailable "not available from $mgr"
        if [[ ${#wanted[@]} -gt 0 ]]; then
            _pkg_root_hint "$mgr" "Run this yourself, then re-run the installer:" \
                "$(_pkg_install_cmd "$mgr")" "${wanted[@]}"
            PKG_UNAVAILABLE+=("${wanted_names[@]}")
        fi
        [[ ${#PKG_UNAVAILABLE[@]} -eq 0 ]]
        return
    fi

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

# pkg_native_tracked MGR NAME... — print the Homebrew NAMEs whose native
# package is installed and is the tool this repo means. Like the brew path,
# that includes packages that were there before tuidev.
pkg_native_tracked() {
    local mgr="$1" name; shift
    for name in "$@"; do
        _pkg_is_different_tool "$mgr" "$name" && continue
        _pkg_is_installed "$mgr" "$(_pkg_native_name "$mgr" "$name")" && printf '%s\n' "$name"
    done
    return 0
}

# _pkg_outdated_native MGR PKG... — print the native PKGs with a newer version
# in the current metadata (no refresh). Returns 2 when the probe failed.
_pkg_outdated_native() {
    local mgr="$1"; shift
    local pkg out rc=0 inst cand
    case "$mgr" in
        apt)
            for pkg in "$@"; do
                out="$(LC_ALL=C apt-cache policy "$pkg" 2>/dev/null)" || rc=2
                inst="$(awk -F': ' '/Installed:/ {print $2; exit}' <<<"$out")"
                cand="$(awk -F': ' '/Candidate:/ {print $2; exit}' <<<"$out")"
                if [[ -z "$inst" || "$inst" == "(none)" ]]; then
                    rc=2   # tracked means installed; no answer is a failed probe
                elif [[ -n "$cand" && "$cand" != "(none)" ]] \
                    && dpkg --compare-versions "$inst" lt "$cand"; then
                    printf '%s\n' "$pkg"
                fi
            done
            ;;
        dnf)
            # One call for all: exit 100 = updates listed, 0 = none, else error.
            out="$(LC_ALL=C dnf -q check-update "$@" 2>/dev/null)" || rc=$?
            case $rc in
                0)   return 0 ;;
                100) rc=0 ;;
                *)   return 2 ;;
            esac
            awk 'NF == 3 { sub(/\.[^.]*$/, "", $1); print $1 }' <<<"$out"
            ;;
        pacman)
            # -Qu exits 1 both for "nothing outdated" and on errors; tell
            # them apart by pacman's error: lines.
            out="$(LC_ALL=C pacman -Qu "$@" 2>&1)" || true
            grep -q '^error:' <<<"$out" && return 2
            awk '$3 == "->" { print $1 }' <<<"$out"
            ;;
        *) return 2 ;;
    esac
    return $rc
}

# pkg_native_outdated MGR NAME... — print the tracked NAMEs (pkg_native_tracked)
# with a newer version available. Returns 2 when the probe failed; the NAMEs
# it could check are still printed.
pkg_native_outdated() {
    local mgr="$1" name pkg rc=0 out; shift
    [[ $# -gt 0 ]] || return 0
    local -a pkgs=()
    for name in "$@"; do pkgs+=("$(_pkg_native_name "$mgr" "$name")"); done
    out="$(_pkg_outdated_native "$mgr" "${pkgs[@]}")" || rc=$?
    for name in "$@"; do
        pkg="$(_pkg_native_name "$mgr" "$name")"
        grep -qxF "$pkg" <<<"$out" && printf '%s\n' "$name"
    done
    return $rc
}

# pkg_native_refresh MGR — refresh package metadata when root or sudo -n is
# available (apt only; dnf refreshes expired metadata itself, and a bare
# `pacman -Sy` invites partial upgrades). Returns 1 when it could not.
pkg_native_refresh() {
    [[ "$1" == apt ]] || return 0
    local sudo_prefix
    sudo_prefix="$(_pkg_sudo_prefix)" || return 1
    _pkg_refresh_once apt "$sudo_prefix"
}

# _pkg_root_hint MGR LEAD CMD... — the "run this yourself" block for a
# manager that needs root we don't have.
_pkg_root_hint() {
    local mgr="$1" lead="$2"; shift 2
    print_warning "$mgr needs root and passwordless sudo is not available."
    print_info "$lead"
    [[ "$mgr" == apt ]] && print_info "    sudo apt-get update"
    print_info "    sudo $*"
}

# pkg_native_upgrade MGR NAME... — upgrade already-installed packages in one
# batch, or print the command when root is unavailable. Never installs
# anything new, and apt keeps each package's auto/manual mark. pacman only
# gets the full-system command: upgrading a subset is a partial upgrade,
# which Arch doesn't support. Returns 1 on failure or when only a hint was
# printed.
pkg_native_upgrade() {
    local mgr="$1"; shift
    [[ $# -gt 0 ]] || return 0
    local name cmd sudo_prefix auto
    local -a pkgs=()
    for name in "$@"; do pkgs+=("$(_pkg_native_name "$mgr" "$name")"); done
    case "$mgr" in
        apt)    cmd="apt-get install --only-upgrade -y" ;;
        dnf)    cmd="dnf upgrade -y" ;;
        pacman)
            print_info "pacman upgrades the whole system, not single packages. Run this yourself:"
            print_info "    sudo pacman -Syu"
            return 1
            ;;
        *)      return 1 ;;
    esac

    if ! sudo_prefix="$(_pkg_sudo_prefix)"; then
        _pkg_root_hint "$mgr" "Run this yourself:" "$cmd" "${pkgs[@]}"
        return 1
    fi
    # `apt-get install` marks what it touches as manual; put auto marks back
    # so `apt autoremove` still sees dependencies as dependencies.
    [[ "$mgr" == apt ]] && auto="$(apt-mark showauto "${pkgs[@]}" 2>/dev/null)"
    print_step "upgrading ${pkgs[*]} via $mgr"
    local rc=0
    # shellcheck disable=SC2086  # prefix and command word-split on purpose
    run_cmd $sudo_prefix $cmd "${pkgs[@]}" || rc=1
    if [[ -n "${auto:-}" ]]; then
        # shellcheck disable=SC2086
        run_cmd $sudo_prefix apt-mark auto $auto >/dev/null || true
    fi
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
