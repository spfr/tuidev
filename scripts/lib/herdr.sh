#!/bin/bash
# scripts/lib/herdr.sh - Herdr as a direct install: which kind of install a
# machine has, the release binary, and live upgrades with `--handoff`.
#
# Source after ui.sh. Idempotent; safe to source multiple times.
#
#   . "$(dirname "${BASH_SOURCE[0]}")/ui.sh"
#   . "$(dirname "${BASH_SOURCE[0]}")/herdr.sh"
#
# Herdr updates itself (`herdr update`, and `--handoff` to move a running
# server's panes onto the new binary) only when its binary isn't managed by a
# package manager: it refuses when the binary, or what it links to, sits in a
# Homebrew keg (…/Cellar/herdr/VERSION/bin/herdr), a mise install or the Nix
# store. So tuidev installs the release binary where Herdr's own installer
# puts it, ${HERDR_INSTALL_DIR:-~/.local/bin}/herdr, checked against the
# sha256 the release lists (release.sh).
#
# A handoff starts the new server as a detached process and then the old one
# exits. A supervisor that watches the old process reacts to that exit:
# launchd's KeepAlive starts `herdr server` again (it fails, "already
# running", every 10 s), and a systemd unit with the default KillMode stops
# every process left in it, the new server and the panes included. (With
# KillMode=process systemd keeps the panes but loses the server: it runs on,
# unsupervised, in the cgroup of a unit systemd thinks has stopped.) So
# `herdr update --handoff` runs only when no such supervisor runs the server
# (herdr_handoff_blocker). A systemd user unit hands its server over itself,
# through its own reload (herdr_systemd_update).
#
# Exposes:
#   herdr_direct_path        where the release binary lives
#   herdr_asset [OS] [ARCH]  its release asset (herdr-macos-aarch64, …)
#   herdr_install_kind       direct | brew | other | none
#   herdr_brew_installed     Homebrew still has the herdr formula
#   herdr_ensure_direct      install the release binary unless a herdr is in place
#   herdr_install_direct     download and install it (TUIDEV_HERDR_VERSION pins one)
#   herdr_server_pids        running `herdr server` processes
#   herdr_server_on_brew     a running server uses Homebrew's binary (or can't tell)
#   herdr_server_uses P      a running server uses binary P (or can't tell)
#   herdr_handoff_blocker P  why `herdr update --handoff` of server P is unsafe (status 0), or status 1
#   herdr_systemd_units      the running systemd user units that run a herdr server
#   herdr_systemd_update U   the release binary, then a reload of each unit that hands over
#   herdr_self_update        either of: herdr update (--handoff while a server runs), or the above
#   herdr_service_files      the user's LaunchAgents / systemd units that run herdr server
#   herdr_service_note F     what to change in one of them
#   herdr_path_note          when PATH doesn't find the release binary first
#   herdr_cutover_hint       when to `brew uninstall herdr`
#   herdr_switch_to_direct   Homebrew's herdr -> the release binary, then what is left by hand

if [[ -n "${_TUIDEV_HERDR_LOADED:-}" ]]; then
    return 0
fi
_TUIDEV_HERDR_LOADED=1

# shellcheck source=./ui.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/ui.sh"
# shellcheck source=./manifest.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/manifest.sh"
# shellcheck source=./release.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/release.sh"

HERDR_REPO="herdrdev/herdr"
# What a systemd unit needs before its server can be upgraded live.
HERDR_RELOAD_HINT="for live upgrades give the unit an ExecReload that runs a herdr-handoff wrapper, which hands the panes to a new server and reports it with systemd-notify MAINPID= (NotifyAccess=exec), see docs/agent-workflows.md (Herdr, practice 5)"
: "${_HERDR_PROC:=/proc}"   # tests point it at a fixture
# shellcheck disable=SC2034  # read by the herdr pack
HERDR_INSTALLED_NOW=false   # set by herdr_install_direct

herdr_direct_path() { printf '%s/herdr\n' "${HERDR_INSTALL_DIR:-$HOME/.local/bin}"; }

# An Apple silicon Mac reports x86_64 to a shell under Rosetta; the native
# build is the one to install there.
# shellcheck disable=SC2120 # OS and ARCH are optional; only the tests pass them
herdr_asset() {
    local os="${1:-$(uname -s)}" arch="${2:-}"
    if [[ -z "$arch" ]]; then
        arch="$(uname -m)"
        [[ "$os" == Darwin && "$arch" == x86_64 && "$(sysctl -n hw.optional.arm64 2>/dev/null)" == 1 ]] && arch=arm64
    fi
    case "$os" in Darwin) os=macos ;; Linux) os=linux ;; *) return 1 ;; esac
    case "$arch" in x86_64|amd64) arch=x86_64 ;; arm64|aarch64) arch=aarch64 ;; *) return 1 ;; esac
    printf 'herdr-%s-%s\n' "$os" "$arch"
}

# Follow symlinks without readlink -f (bash 3.2, older BSD readlink).
_herdr_resolve() {
    local p="$1" link n=0
    while [[ -L "$p" && $n -lt 16 ]]; do
        link="$(readlink "$p")"
        case "$link" in /*) p="$link" ;; *) p="$(dirname "$p")/$link" ;; esac
        n=$((n + 1))
    done
    printf '%s\n' "$p"
}

# Herdr's own test: the path, or what it resolves to, is in a keg. The bin
# links survive in a service file after `brew uninstall`, so name them too.
herdr_is_brew_binary() {
    case "$1" in
        */Cellar/herdr/*/bin/herdr|/opt/homebrew/bin/herdr|/home/linuxbrew/.linuxbrew/bin/herdr) return 0 ;;
    esac
    case "$(_herdr_resolve "$1")" in */Cellar/herdr/*/bin/herdr) return 0 ;; esac
    return 1
}

# direct: the release binary at herdr_direct_path. brew: that path, or the
# herdr on PATH, is Homebrew's. other: a herdr installed some other way (mise,
# Nix, a link elsewhere). none: no herdr.
herdr_install_kind() {
    local p found
    p="$(herdr_direct_path)"
    if [[ -e "$p" || -L "$p" ]]; then
        if herdr_is_brew_binary "$p"; then echo brew
        elif [[ -L "$p" || ! -f "$p" ]]; then echo other
        else echo direct
        fi
        return 0
    fi
    found="$(command -v herdr 2>/dev/null)" || found=""
    if [[ -z "$found" ]]; then echo none
    elif herdr_is_brew_binary "$found"; then echo brew
    else echo other
    fi
}

herdr_brew_installed() {
    local prefix="${HOMEBREW_PREFIX:-}"
    if [[ -z "$prefix" ]] && command_exists brew; then
        prefix="$(brew --prefix 2>/dev/null)" || prefix=""
    fi
    [[ -n "$prefix" && -d "$prefix/Cellar/herdr" ]]
}

herdr_install_direct() {
    local dest asset tag="${TUIDEV_HERDR_VERSION:-latest}"
    dest="$(herdr_direct_path)"
    if ! asset="$(herdr_asset)"; then
        print_warning "herdr publishes no release binary for $(uname -s) $(uname -m)"
        return 1
    fi
    case "$tag" in latest|v*) ;; *) tag="v$tag" ;; esac
    release_install "$HERDR_REPO" "$tag" "$asset" "$dest" || return 1
    # shellcheck disable=SC2034  # read by the herdr pack
    HERDR_INSTALLED_NOW=true
    # A `tool`, not a `file`: uninstall removes it only when asked, and never
    # while a server runs from it.
    tuidev_manifest_record tool "$dest"
    [[ "$DRY_RUN" == true ]] || print_success "herdr ${RELEASE_TAG:-} installed to $dest (sha256 checked)"
}

# Status 0 when a herdr is in place afterwards (the release binary, or one
# installed another way, which is left alone), 1 when none could be.
herdr_ensure_direct() {
    local dest kind
    dest="$(herdr_direct_path)"
    kind="$(herdr_install_kind)"
    case "$kind" in
        direct)
            print_info "herdr: release binary at $dest (herdr update keeps it current)"
            return 0 ;;
        other)
            print_info "herdr: $(command -v herdr 2>/dev/null || echo "$dest") is installed another way; left alone"
            return 0 ;;
        brew)
            print_step "herdr: installing the release binary to $dest, in place of Homebrew's" ;;
        none)
            print_step "herdr: installing the release binary to $dest" ;;
    esac
    herdr_install_direct
}

_herdr_timeout() {
    local secs="$1"; shift
    if command_exists timeout; then timeout "$secs" "$@"
    elif command_exists gtimeout; then gtimeout "$secs" "$@"
    else "$@"
    fi
}

# `herdr server`, a named session's (`herdr --session NAME server`, the flag
# goes anywhere), and the replacement a handoff starts (`… server
# --handoff-import`); not short-lived `herdr server stop` and friends.
# Status 1 when the process list can't be read.
herdr_server_pids() {
    local table
    table="$(ps -A -o pid= -o args= 2>/dev/null)" || return 1
    printf '%s\n' "$table" | awk '{
        n = split($2, p, "/")
        if (p[n] != "herdr") next
        k = 0
        for (i = 3; i <= NF; i++) {
            if ($i == "--session") { i++; continue }
            if ($i ~ /^--session=/) continue
            w[++k] = $i
        }
        if (k >= 1 && w[1] == "server" && (k == 1 || w[2] == "--handoff-import")) print $1
    }'
}

_herdr_server_exe() {
    if [[ -e "$_HERDR_PROC/$1/exe" ]]; then
        readlink "$_HERDR_PROC/$1/exe" 2>/dev/null | sed 's/ (deleted)$//'
    elif command_exists lsof; then
        lsof -a -p "$1" -d txt -Fn 2>/dev/null | awk '/^n/ { print substr($0, 2); exit }'
    fi
}

herdr_server_on_brew() {
    local pids pid exe
    pids="$(herdr_server_pids)" || return 0
    for pid in $pids; do
        exe="$(_herdr_server_exe "$pid")"
        [[ -z "$exe" ]] && return 0
        herdr_is_brew_binary "$exe" && return 0
    done
    return 1
}

herdr_server_uses() {
    local want pids pid exe
    want="$(_herdr_resolve "$1")"
    pids="$(herdr_server_pids)" || return 0
    for pid in $pids; do
        exe="$(_herdr_server_exe "$pid")"
        [[ -z "$exe" || "$exe" == "$1" || "$exe" == "$want" ]] && return 0
    done
    return 1
}

# _herdr_launchd_safe PLIST — succeeds when a LaunchAgent leaves a handoff
# alone: AbandonProcessGroup true (launchd doesn't kill the new server, left
# in the job's group), and KeepAlive missing, false, or a dictionary whose
# SuccessfulExit is false (the old server exits cleanly; any other
# dictionary, or true, restarts it). raw prints a dictionary's keys, so a
# dictionary is told by its SuccessfulExit alone; a KeepAlive raw can't read
# at all (an older plutil) is not safe.
_herdr_launchd_safe() {
    local f="$1" keep
    [[ -f "$f" && "$(plutil -extract AbandonProcessGroup raw -o - "$f" 2>/dev/null)" == true ]] || return 1
    plutil -extract KeepAlive xml1 -o - "$f" >/dev/null 2>&1 || return 0
    keep="$(plutil -extract KeepAlive raw -o - "$f" 2>/dev/null)" || return 1
    [[ "$keep" == false ]] && return 0
    [[ "$keep" != true && "$(plutil -extract KeepAlive.SuccessfulExit raw -o - "$f" 2>/dev/null)" == false ]]
}

herdr_handoff_blocker() {
    local pid="$1" label plist unit
    if is_macos; then
        label="$(launchctl list 2>/dev/null | awk -v p="$pid" '$1 == p { print $3; exit }')"
        [[ -n "$label" ]] || return 1
        plist="$HOME/Library/LaunchAgents/$label.plist"
        _herdr_launchd_safe "$plist" && return 1
        echo "the server is launchd job $label, which restarts it once the old server exits; in ${plist/#"$HOME"/\~} set KeepAlive to {SuccessfulExit: false} and AbandonProcessGroup to true (launchd reads it at your next login)"
        return 0
    fi
    # Every systemd unit blocks: whatever its KillMode, systemd keeps
    # watching the old server, which exits.
    unit="$(_herdr_server_unit "$pid")"
    [[ -n "$unit" ]] || return 1
    if [[ "$(_herdr_unit_reload "$unit")" == handoff ]]; then
        echo "the server is systemd unit $unit, which hands it over itself: systemctl --user reload $unit (update.sh --packages runs it)"
    else
        echo "the server is systemd unit $unit, which would stop the new server and its panes once the old one exits (or, with KillMode=process, lose track of it); $HERDR_RELOAD_HINT"
    fi
    return 0
}

# The systemd unit a server runs in, read from its cgroup; empty when it runs
# in a login session (session-N.scope) or /proc can't say.
_herdr_server_unit() {
    awk -F/ '$NF ~ /\.service$/ && $NF !~ /^user@/ { print $NF; exit }' "$_HERDR_PROC/$1/cgroup" 2>/dev/null || true
}

# _herdr_unit_reload UNIT — handoff: its ExecReload runs a program named
# herdr-handoff, and NotifyAccess=exec or all lets that wrapper's
# systemd-notify (run by the reload itself) name the new server as the unit's
# main process (with main or none systemd ignores the message, keeps watching
# the old server, and stops the new one with it). nonotify: that wrapper
# without NotifyAccess=exec or all. none: no such reload. The
# program's name is the contract: a reload can't otherwise be told to hand
# over (an ExecReload that sends a signal looks just the same).
_herdr_unit_reload() {
    local reload notify re='(^|[/[:space:]=])herdr-handoff([[:space:];]|$)'
    reload="$(systemctl --user show -p ExecReload --value "$1" 2>/dev/null)" || reload=""
    if ! [[ "$reload" =~ $re ]]; then echo none; return 0; fi
    notify="$(systemctl --user show -p NotifyAccess --value "$1" 2>/dev/null)" || notify=""
    case "$notify" in exec|all) echo handoff ;; *) echo nonotify ;; esac
}

# herdr.service and herdr-session@NAME.service, plus any other unit a running
# server's cgroup names; one per line. Nothing on macOS or without systemctl.
herdr_systemd_units() {
    local pid
    is_macos && return 0
    command_exists systemctl || return 0
    {
        systemctl --user list-units --plain --no-legend --state=running \
            herdr.service 'herdr-session@*.service' 2>/dev/null | awk '{ print $1 }'
        for pid in $(herdr_server_pids); do _herdr_server_unit "$pid"; done
    } | awk 'NF && !seen[$0]++'
}

# _herdr_unit_stale UNIT — its main process runs a binary that has since been
# replaced (/proc shows it "(deleted)"): an earlier install whose reload
# failed or was skipped. Status 1 otherwise, or when /proc can't say.
_herdr_unit_stale() {
    local pid exe
    pid="$(systemctl --user show -p MainPID --value "$1" 2>/dev/null)" || return 1
    [[ "$pid" =~ ^[0-9]+$ && "$pid" != 0 ]] || return 1
    exe="$(readlink "$_HERDR_PROC/$pid/exe" 2>/dev/null)" || return 1
    [[ "$exe" == *" (deleted)" ]]
}

# The release binary is put in place by tuidev's own verified download
# (release.sh: one rename, so each running server keeps the inode it runs)
# when it isn't the release asked for, never by `herdr update`, which, with
# stdin closed, installs nothing a running server would need a restart for.
# Then each unit whose server runs an older binary is reloaded, if its reload
# hands over (status 0 of systemctl: systemd follows the new server; anything
# else: the old server runs on, panes and all). The other units keep the old
# binary until their next start. Never runs `herdr update --handoff`.
herdr_systemd_update() {
    local units="$1" bin cur tag json unit kind rc installed=false
    bin="$(herdr_direct_path)"
    if [[ "$DRY_RUN" == true ]]; then
        herdr_install_direct
        for unit in $units; do
            case "$(_herdr_unit_reload "$unit")" in
                handoff) echo -e "${YELLOW}[DRY RUN]${NC} systemctl --user reload $unit (if its server runs an older binary)" ;;
                *) print_info "herdr: $unit would not be reloaded (no herdr-handoff ExecReload with NotifyAccess=exec or all); it keeps the old binary until its next start" ;;
            esac
        done
        return 0
    fi
    if ! command_exists curl || ! command_exists jq; then
        print_warning "herdr: installing a release needs curl and jq; nothing installed or reloaded"
        return 0
    fi
    cur="$("$bin" --version 2>/dev/null | awk '{ print $2 }')" || cur=""
    tag="${TUIDEV_HERDR_VERSION:-latest}"
    case "$tag" in latest|v*) ;; *) tag="v$tag" ;; esac
    if [[ "$tag" == latest ]]; then
        json="$(release_json "$HERDR_REPO" latest 2>/dev/null)" || json=""
        tag="$(printf '%s' "$json" | jq -r '.tag_name // empty' 2>/dev/null)" || tag=""
        if [[ -z "$tag" ]]; then
            print_warning "herdr: could not read the latest release from the GitHub API; nothing installed or reloaded"
            return 0
        fi
    fi
    if [[ -n "$cur" && "v$cur" == "$tag" ]]; then
        print_info "herdr $cur is the release asked for"
    else
        print_step "herdr: installing $tag to $bin (no handoff: systemd units hand over through their reload)"
        if ! TUIDEV_HERDR_VERSION="$tag" herdr_install_direct; then
            print_warning "herdr: $tag not installed; nothing reloaded (update.sh --packages tries again)"
            return 0
        fi
        installed=true
    fi
    for unit in $units; do
        [[ "$installed" == true ]] || _herdr_unit_stale "$unit" || continue
        kind="$(_herdr_unit_reload "$unit")"
        case "$kind" in
            handoff)
                print_step "herdr: handing $unit over to the new binary (systemctl --user reload $unit)"
                rc=0
                _herdr_timeout 300 systemctl --user reload "$unit" < /dev/null || rc=$?
                if [[ $rc -eq 0 ]]; then
                    print_success "herdr: $unit handed over; systemd follows the new server"
                else
                    print_warning "herdr: systemctl --user reload $unit failed (status $rc); its old server keeps running with its panes. Details: journalctl --user -u $unit -n 50 --no-pager"
                fi ;;
            nonotify)
                print_warning "herdr: $unit reloads through herdr-handoff, but without NotifyAccess=exec (or all) systemd can't follow the new server; not reloaded. Add NotifyAccess=exec to it, then systemctl --user daemon-reload" ;;
            *)
                print_info "herdr: $unit keeps the old binary until its next start (a restart stops its panes); $HERDR_RELOAD_HINT" ;;
        esac
    done
    return 0
}

# Never stops a server. With stdin not a terminal, herdr (src/update.rs)
# answers every "stop the old server?" prompt no: a plain update that would
# need a server restart installs nothing and says so; a handoff the old
# server can't take ends with an error, and a failed one keeps the old
# server and prints its stop command.
# A server a systemd user unit runs takes herdr_systemd_update instead, and
# then no server is handed over by `herdr update --handoff`, which would take
# every running session, the units' included.
herdr_self_update() {
    local bin pid why handoff=false args units
    bin="$(herdr_direct_path)"
    units="$(herdr_systemd_units)"
    if [[ "${HERDR_ENV:-}" == 1 ]]; then
        if [[ -n "$units" ]]; then
            print_warning "herdr: not upgraded from inside a Herdr pane: detach (Ctrl+b q), then run ./scripts/update.sh --packages from a plain shell (it reloads the systemd units)"
        else
            print_warning "herdr update refuses to run inside a Herdr pane: detach (Ctrl+b q), then run herdr update --handoff from a plain shell"
        fi
        return 0
    fi
    if [[ -n "$units" ]]; then
        herdr_systemd_update "$units"
        for pid in $(herdr_server_pids); do
            [[ -z "$(_herdr_server_unit "$pid")" ]] || continue
            print_info "herdr: server $pid runs outside systemd; it picks up the new binary at its next start (herdr update --handoff would hand the units' servers over too)"
        done
        return 0
    fi
    for pid in $(herdr_server_pids); do
        handoff=true
        if why="$(herdr_handoff_blocker "$pid")"; then
            print_warning "herdr: no live handoff, because $why. Running plain herdr update, which never stops the server: a release the server can keep using is installed (it moves over at its next start), one that needs a restart is not."
            handoff=false
            break
        fi
    done
    args=(update)
    [[ "$handoff" == true ]] && args+=(--handoff)
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${YELLOW}[DRY RUN]${NC} $bin ${args[*]} < /dev/null"
        return 0
    fi
    _herdr_timeout 600 "$bin" "${args[@]}" < /dev/null \
        || print_warning "herdr ${args[*]} did not finish cleanly (continuing; its output says what is left)"
    return 0
}

herdr_service_files() {
    local f
    for f in "$HOME"/Library/LaunchAgents/*.plist "${XDG_CONFIG_HOME:-$HOME/.config}"/systemd/user/*.service; do
        [[ -f "$f" ]] || continue
        grep -qE 'herdr( |</string>|$)' "$f" 2>/dev/null && grep -q 'server' "$f" 2>/dev/null && printf '%s\n' "$f"
    done
    return 0
}

# Prints what to change; never edits the file (it is the user's, not tuidev's).
herdr_service_note() {
    local f="$1" short tok brew="" direct
    short="${f/#"$HOME"/\~}"
    direct="$(herdr_direct_path)"
    while IFS= read -r tok; do
        herdr_is_brew_binary "$tok" && brew="$tok"
    done < <(grep -oE '/[^[:space:]<>"'"'"']*/herdr' "$f" 2>/dev/null | sort -u)
    if [[ -n "$brew" ]]; then
        print_warning "$short runs Homebrew's $brew: change it to $direct (it takes effect at the service's next start)"
    elif grep -qE '(exec |>)herdr( |<)' "$f" 2>/dev/null; then
        print_info "$short finds herdr on its login shell's PATH; to pin the release binary: exec \"$direct\" server"
    fi
    case "$f" in
        *.plist)
            _herdr_launchd_safe "$f" \
                || print_info "$short: before a live handoff, set KeepAlive to {SuccessfulExit: false} and AbandonProcessGroup to true, or launchd restarts the old server's job once it exits" ;;
        *.service)
            cat "$f" "$f.d"/*.conf 2>/dev/null | grep -qE '^ExecReload=.*herdr-handoff' \
                || print_info "$short: never herdr update --handoff its server; $HERDR_RELOAD_HINT" ;;
    esac
    return 0
}

herdr_path_note() {
    local dir found
    dir="$(dirname "$(herdr_direct_path)")"
    found="$(command -v herdr 2>/dev/null)" || found=""
    [[ -z "$found" || "$found" == "$(herdr_direct_path)" ]] && return 0
    print_info "herdr on this PATH is $found; put $dir first (the tuidev .zshrc does: path=(\"\$HOME/.local/bin\" \$path))"
}

herdr_cutover_hint() {
    herdr_brew_installed || return 0
    if [[ "$DRY_RUN" == true ]]; then
        print_info "herdr: once no server runs Homebrew's binary any more: brew uninstall herdr"
    elif herdr_server_on_brew; then
        print_info "herdr: a running server still uses Homebrew's binary. It moves to $(herdr_direct_path) at its next start, or live with herdr update --handoff once a newer release is out."
        print_info "  Then remove Homebrew's copy: brew uninstall herdr"
    else
        print_info "herdr: Homebrew's copy is no longer used: brew uninstall herdr"
    fi
}

# Puts the release binary in place of Homebrew's (or of none), then says what
# is left by hand: PATH order, service files that name Homebrew's binary or
# would upset a handoff, `brew uninstall herdr`. Never edits a service file,
# stops a server or uninstalls anything. Status 1 when the release binary
# couldn't be installed; running it again retries.
herdr_switch_to_direct() {
    local unit
    herdr_ensure_direct || return 1
    herdr_path_note
    while IFS= read -r unit; do
        [[ -n "$unit" ]] && herdr_service_note "$unit"
    done < <(herdr_service_files)
    herdr_cutover_hint
}
