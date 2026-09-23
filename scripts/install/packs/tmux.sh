#!/bin/bash
#
# Optional pack: tmux
#
# Durable sessions for always-on nodes: agents keep running after you detach,
# and tmux-resurrect / tmux-continuum bring sessions back after a reboot. Part
# of --profile remote; opt-in anywhere else. This pack:
#   - installs tmux;
#   - writes ~/.config/tmux/tmux.conf as the managed block `tuidev-tmux`
#     (under install.sh --adopt-existing, or from update.sh into a tmux.conf
#     of your own without that block, only when the file is absent);
#   - bootstraps TPM and the resurrect/continuum plugins.
#
# The `t NAME` (attach-or-create) and `tls` helpers live in ~/.zshrc and only
# appear when tmux is on PATH.
#
# Entrypoint: tmux_install
# Invoked via: ./install.sh --pack tmux
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
# shellcheck source=../../lib/ui.sh disable=SC1091
. "$SCRIPT_DIR/../../lib/ui.sh"
# shellcheck source=../../lib/pkg.sh disable=SC1091
. "$SCRIPT_DIR/../../lib/pkg.sh"
# shellcheck source=../../lib/config_write.sh disable=SC1091
. "$SCRIPT_DIR/../../lib/config_write.sh"

TMUX_FORMULAE=(tmux)   # read by pack_array: update, health check, uninstall

# tmux.conf follows install.sh's write policy. WRITE_MODE is install.sh's:
#   managed-block   (the default) write or refresh the tuidev-tmux block;
#   adopt-existing  (--no-overwrite / --adopt-existing) only when absent.
# Run from update.sh (--configs) or on its own, WRITE_MODE is unset: the file
# is created when absent and an existing tuidev-tmux block is refreshed, but a
# tmux.conf of the user's own never gains a block — as update.sh treats every
# other managed block (a legacy file is reported, not appended to).
_tmux_install_conf() {
    local src="$REPO_ROOT/configs/tmux/tmux.conf" dest="$HOME/.config/tmux/tmux.conf"
    [[ -f "$src" ]] || return 0
    case "${WRITE_MODE:-}" in
        adopt-existing)
            install_config "$dest" "$src" --adopt-existing ;;
        managed-block)
            install_config "$dest" "$src" --managed-block tuidev-tmux ;;
        *)
            if [[ -e "$dest" ]] && ! grep -qxF "$(tuidev_block_begin tuidev-tmux)" "$dest" 2>/dev/null; then
                print_info "keeping your own $dest (no tuidev-tmux block; ./install.sh --pack tmux adds one)"
            else
                install_config "$dest" "$src" --managed-block tuidev-tmux
            fi
            ;;
    esac
}

# _tmux_tpm_run SECS CMD... — run one TPM step so it can never hang the installer:
#   - git may not prompt (GIT_TERMINAL_PROMPT=0) and uses no credential helper
#     (credential.helper reset through GIT_CONFIG_*, git 2.31+): with no TTY a
#     prompt waits forever, and so does `credential-osxkeychain store` when the
#     Keychain can't be reached. The plugins are public; nothing needs a login;
#   - stdin is /dev/null;
#   - the step runs in its own process group, and if it is still running after
#     SECS seconds (a stuck network, an ssh prompt on /dev/tty, a tmux server
#     that does not answer) the whole group is killed, including the git
#     clones TPM starts, so nothing is left behind.
# Returns CMD's status, non-zero on a kill.
_tmux_tpm_run() {
    local secs="$1" pid watchdog rc=0
    shift
    set -m   # background job gets its own process group (pgid = $pid)
    GIT_TERMINAL_PROMPT=0 GIT_CONFIG_COUNT=1 \
        GIT_CONFIG_KEY_0=credential.helper GIT_CONFIG_VALUE_0='' \
        "$@" </dev/null &
    pid=$!
    set +m
    # CONT after TERM: a member stopped on terminal input only sees the TERM
    # once it runs again.
    ( sleep "$secs" && kill -TERM -- "-$pid" && kill -CONT -- "-$pid" ) >/dev/null 2>&1 &
    watchdog=$!
    wait "$pid" 2>/dev/null || rc=$?
    kill "$watchdog" 2>/dev/null || true
    wait "$watchdog" 2>/dev/null || true
    return "$rc"
}

# Bootstrap TPM (tmux plugin manager) so tmux-resurrect / tmux-continuum — the
# durability layer — actually load. Idempotent and non-fatal: every failure
# (no network, a prompt, a timeout) only warns. Runs once tmux.conf is in
# place; previewed only under --dry-run.
_tmux_bootstrap_plugins() {
    command_exists tmux || return 0
    command_exists git  || return 0
    local tpm_dir="$HOME/.config/tmux/plugins/tpm"
    if [[ "$DRY_RUN" == true ]]; then
        [[ -d "$tpm_dir/.git" ]] || print_info "[DRY RUN] would run: git clone --depth 1 https://github.com/tmux-plugins/tpm $tpm_dir"
        print_info "[DRY RUN] would run: $tpm_dir/bin/install_plugins"
        return 0
    fi
    if [[ -d "$tpm_dir/.git" ]]; then
        print_success "tpm (already present)"
    else
        print_step "installing TPM (tmux plugin manager)"
        _tmux_tpm_run 120 git clone --quiet --depth 1 https://github.com/tmux-plugins/tpm "$tpm_dir" \
            || { print_warning "tpm clone failed (continuing)"; return 0; }
        tuidev_manifest_record dir "$tpm_dir"
    fi
    if [[ -x "$tpm_dir/bin/install_plugins" ]]; then
        local plugin plugins_dir="${tpm_dir%/tpm}" new_plugins=""
        for plugin in tmux-resurrect tmux-continuum; do
            [[ -d "$plugins_dir/$plugin" ]] || new_plugins="$new_plugins $plugin"
        done
        # `update --configs` re-runs this pack: stay offline once both are in.
        if [[ -z "$new_plugins" ]]; then
            print_success "tmux plugins (already present)"
            return 0
        fi
        print_step "installing tmux plugins (resurrect, continuum)"
        _tmux_tpm_run 120 "$tpm_dir/bin/install_plugins" >/dev/null 2>&1 \
            || print_warning "tmux plugin install failed (open tmux and press 'prefix + I' to retry)"
        # Record only the plugin dirs this run created, so uninstall removes
        # ours and never a plugin the user installed themselves.
        for plugin in $new_plugins; do
            if [[ -d "$plugins_dir/$plugin" ]]; then
                tuidev_manifest_record dir "$plugins_dir/$plugin"
            fi
        done
    fi
    # Non-fatal by contract: installer runs packs under `set -e`.
    return 0
}

tmux_install() {
    print_header "Pack: tmux"
    pkg_install "${TMUX_FORMULAE[@]}" || print_warning "tmux not installed (continuing)"
    _tmux_install_conf
    _tmux_bootstrap_plugins
    print_info "Open a new shell, then: t NAME (attach or create), tls (list sessions)."
    print_success "tmux pack complete"
}

# Run if executed directly.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    tmux_install "$@"
fi
