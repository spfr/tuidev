#!/bin/bash
# scripts/lib/packs.sh - pack discovery: where a pack lives, what it is
# called, what it installs. Shared by install.sh, update.sh, uninstall.sh,
# health_check.sh and test_suite.sh so none of them re-derives it.
#
# Sources ui.sh and profile.sh itself. Idempotent; bash 3.2-clean.
#
# Exposes:
#   TUIDEV_BUILTIN_PACKS        core remote sandbox ui extras (--core, …)
#   pack_script NAME            path of the pack's script, or return 1
#   pack_entrypoint NAME        its entrypoint function (sandbox-container
#                               → sandbox_container_install)
#   pack_run NAME               source the pack here and call its entrypoint
#   pack_array NAME formulae|casks|jobs
#                               the pack's <PACK>_FORMULAE / <PACK>_CASKS /
#                               <PACK>_JOBS, one per line, read without
#                               installing anything
#   pack_binaries NAME          the commands its formulae put on PATH
#   pack_check NAME             is it in place? the pack's own <pack>_check,
#                               else what it declares (`tuidev check`'s probe)
#   pack_call NAME FN [ARG...]  source the pack in a subshell and run one of
#                               its functions (`tuidev check --fix` repairs
#                               with the pack's own step)
#   tuidev_formula_binary F     formula → command ("" for plugin-only formulae)
#   tuidev_cask_app C           cask → /Applications bundle name

if [[ -n "${_TUIDEV_PACKS_LOADED:-}" ]]; then
    return 0
fi
_TUIDEV_PACKS_LOADED=1

# shellcheck source=./profile.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/profile.sh"
# shellcheck source=./brew.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/brew.sh"   # tuidev_formula_binary

_TUIDEV_INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../install" && pwd)"

# The five packs selected by --core/--remote/--sandbox/--ui/--extras. They live
# at scripts/install/<name>.sh; the optional ones at scripts/install/packs/.
# shellcheck disable=SC2034  # public interface, read by consumers
TUIDEV_BUILTIN_PACKS=(core remote sandbox ui extras)

pack_script() {
    local name="$1" path
    case " ${TUIDEV_BUILTIN_PACKS[*]} " in
        *" $name "*) path="$_TUIDEV_INSTALL_DIR/$name.sh" ;;
        *)           path="$_TUIDEV_INSTALL_DIR/packs/$name.sh" ;;
    esac
    [[ -n "$name" && -f "$path" ]] || return 1
    printf '%s\n' "$path"
}

pack_entrypoint() { printf '%s_install\n' "${1//-/_}"; }

# Upper-snake array prefix: sandbox-container → SANDBOX_CONTAINER.
_pack_var_prefix() { printf '%s' "$1" | tr '[:lower:]-' '[:upper:]_'; }

# pack_run NAME — source in the CURRENT shell (brew caches and DRY_RUN carry
# across packs) and run the entrypoint. Wrap in ( ) to isolate. Returns the
# entrypoint's status; 1 when the script or entrypoint is missing.
pack_run() {
    local name="$1" script fn
    script="$(pack_script "$name")" || { print_warning "pack missing: $name"; return 1; }
    # shellcheck disable=SC1090
    . "$script"
    fn="$(pack_entrypoint "$name")"
    declare -F "$fn" >/dev/null || { print_warning "$script defines no $fn"; return 1; }
    "$fn"
}

# pack_array NAME formulae|casks|jobs
# Sources the pack in a subshell (it defines functions and arrays only; see
# the pack contract in docs/engineering.md) and prints the array. Silent when
# the pack or array is absent — cargo- or script-installed tools have none.
# A job is "KIND NAME [FN]": what the pack keeps running, which `tuidev check`
# asks launchd or systemd about. KIND: launchd (a LaunchAgent in
# ~/Library/LaunchAgents, loaded), launchd-system (a LaunchDaemon, loaded;
# only where its plist is), systemd (a user unit, enabled and active) or
# systemd-enabled (enabled; its process may end by choice). FN: the pack's
# own function that installs and starts it again (none: a command for you).
pack_array() {
    local name="$1" kind="$2" script var
    script="$(pack_script "$name")" || return 0
    case "$kind" in
        formulae) var="$(_pack_var_prefix "$name")_FORMULAE" ;;
        casks)    var="$(_pack_var_prefix "$name")_CASKS" ;;
        jobs)     var="$(_pack_var_prefix "$name")_JOBS" ;;
        *)        print_error "pack_array: kind must be formulae|casks|jobs"; return 2 ;;
    esac
    (
        set +eu
        # shellcheck disable=SC1090
        . "$script" >/dev/null 2>&1
        declare -p "$var" >/dev/null 2>&1 || exit 0
        local ref="${var}[@]" item
        for item in "${!ref}"; do
            [[ -n "$item" ]] && printf '%s\n' "$item"
        done
        exit 0
    )
}

# The .app bundle name a cask installs.
tuidev_cask_app() {
    printf '%s%s\n' "$(printf '%s' "${1:0:1}" | tr '[:lower:]' '[:upper:]')" "${1:1}"
}

# pack_binaries NAME — one command per line for the pack's formulae.
pack_binaries() {
    local formula bin
    while IFS= read -r formula; do
        [[ -n "$formula" ]] || continue
        bin="$(tuidev_formula_binary "$formula")"
        [[ -n "$bin" ]] && printf '%s\n' "$bin"
    done < <(pack_array "$1" formulae)
    return 0
}

# pack_check NAME — is the pack in place? `tuidev check`'s probe for it: the
# pack's own <pack>_check (hyphens as underscores) when its file defines one,
# which is read-only, quiet and cheap, and true where its platform gives it
# nothing to do. Else what it declares: every command its formulae put on
# PATH (a macOS-only formula is not looked for elsewhere) and, on macOS,
# every app its casks install. Sourced in a subshell, as pack_array does.
pack_check() {
    local name="$1" script fn
    script="$(pack_script "$name")" || return 1
    fn="${name//-/_}_check"
    (
        set +eu
        # shellcheck disable=SC1090
        . "$script" >/dev/null 2>&1
        set +e   # the pack's own `set -e` must not end a probe halfway
        if declare -F "$fn" >/dev/null; then "$fn"; exit; fi
        _pack_check_declared "$name"
    )
}

# pack_call NAME FN [ARG...] — FN, a function of the pack's file, run in a
# subshell with the pack sourced (DRY_RUN and manifest recording as the
# caller has them). False when the pack or FN is missing, else FN's status.
pack_call() {
    local name="$1" fn="$2" script
    shift 2
    script="$(pack_script "$name")" || return 1
    (
        set +u
        # shellcheck disable=SC1090
        . "$script" >/dev/null 2>&1 || exit 1
        set +e
        declare -F "$fn" >/dev/null || exit 1
        "$fn" "$@"
    )
}

# _pack_check_declared NAME — every formula's command and (macOS) cask's app
# NAME declares is here; true when it declares none for this platform.
_pack_check_declared() {
    local item bin app
    while IFS= read -r item; do
        if ! is_macos && declare -F _pkg_macos_only >/dev/null && _pkg_macos_only "$item"; then continue; fi
        bin="$(tuidev_formula_binary "$item")"
        [[ -z "$bin" ]] || command -v "$bin" >/dev/null 2>&1 || return 1
    done < <(pack_array "$1" formulae)
    is_macos || return 0
    while IFS= read -r item; do
        app="$(tuidev_cask_app "$item")"
        [[ -d "/Applications/$app.app" || -d "$HOME/Applications/$app.app" ]] || return 1
    done < <(pack_array "$1" casks)
    return 0
}
