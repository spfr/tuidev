#!/bin/bash
#
# Optional pack: cooling (Apple Silicon Macs)
#
# Keeps a MacBook cool to the touch: tuidev-fan (lib/fan/tuidev-fan.swift),
# built here with the Command Line Tools' swiftc, runs as the root
# LaunchDaemon dev.tuidev.fan and raises the fans with the SoC's sustained
# temperature, from 60 °C (fan minimum) to 95 °C (fan maximum) by default,
# long before macOS would. `agents cool` and the menu switch between cool,
# balanced (auto), quiet, max and off.
#
# The root step is the binary's own `install` (one sudo prompt): it copies
# itself to /Library/PrivilegedHelperTools, root-owned, so nothing you can
# write runs as root. It runs again only when the source changed or the
# daemon is gone, so `update --configs` doesn't ask for a password each time.
#
# Entrypoint: cooling_install
# Invoked via: ./install.sh --pack cooling

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/ui.sh disable=SC1091
. "$SCRIPT_DIR/../../lib/ui.sh"
# shellcheck source=../../lib/config_write.sh disable=SC1091
. "$SCRIPT_DIR/../../lib/config_write.sh"

COOLING_REPO="$(cd "$SCRIPT_DIR/../../.." && pwd)"
COOLING_SRC="$COOLING_REPO/lib/fan/tuidev-fan.swift"
# The daemon's own paths (Paths in tuidev-fan.swift).
COOLING_PLIST="/Library/LaunchDaemons/dev.tuidev.fan.plist"
COOLING_ROOT_BIN="/Library/PrivilegedHelperTools/dev.tuidev.fan"

# The source's sha256, as the stamp records it.
_cooling_src_sum() { shasum -a 256 "$COOLING_SRC" | awk '{ print $1 }'; }

# Apple Silicon, even from a Rosetta shell (where uname -m says x86_64).
_cooling_apple_silicon() { is_macos && [[ "$(sysctl -n hw.optional.arm64 2>/dev/null)" == 1 ]]; }

# swiftc from the Command Line Tools. /usr/bin/swiftc is a shim that offers
# to install them in a dialog, so ask xcode-select whether they are there.
_cooling_have_swiftc() { xcode-select -p >/dev/null 2>&1 && xcrun --find swiftc >/dev/null 2>&1; }

# _cooling_root_install BIN — run BIN's own install as root: without a
# prompt when sudo needs none, with one in a terminal, else print the
# command. Returns BIN's status (3: this Mac has no fans).
_cooling_root_install() {
    local bin="$1" rc=0
    if sudo -n true 2>/dev/null; then
        run_cmd sudo -n "$bin" install || rc=$?
    elif [[ -t 0 && -t 1 ]]; then
        print_step "installing the fan daemon as root (sudo asks for your password)"
        run_cmd sudo "$bin" install || rc=$?
    else
        print_warning "cooling: the fan daemon needs root; run: sudo '$bin' install"
        rc=1
    fi
    return "$rc"
}

cooling_install() {
    print_header "Pack: cooling"
    local dir="$TUIDEV_LIB_DIR/fan" bin stamp sum tmp
    bin="$dir/tuidev-fan" stamp="$dir/tuidev-fan.source.sha256"

    if ! _cooling_apple_silicon; then
        print_info "cooling: fan control is for Apple Silicon Macs; nothing to do here"
        return 0
    fi
    if ! _cooling_have_swiftc; then
        print_warning "cooling: swiftc not found; install the Command Line Tools (xcode-select --install), then run ./install.sh --pack cooling again"
        return 0
    fi

    sum="$(_cooling_src_sum)"
    if [[ -f "$COOLING_PLIST" && -x "$COOLING_ROOT_BIN" && -f "$stamp" && "$(cat "$stamp")" == "$sum" ]]; then
        print_info "cooling: the fan daemon is current (agents cool shows it)"
        print_success "cooling pack complete"
        return 0
    fi

    print_step "building tuidev-fan -> $bin"
    tmp="$(mktemp -d "${TMPDIR:-/tmp}/tuidev-fan.XXXXXX")"
    if ! run_cmd swiftc -O -swift-version 5 "$COOLING_SRC" -o "$tmp/tuidev-fan"; then
        rm -rf "$tmp"
        print_warning "cooling: tuidev-fan did not build (continuing without fan control)"
        return 0
    fi
    if [[ "$DRY_RUN" == true ]]; then
        rm -rf "$tmp"
        print_info "[dry run] would install $bin and run: sudo $bin install"
        return 0
    fi
    # A fanless Mac (a MacBook Air): nothing to run, and no sudo, now or on
    # any update. Reading the fans needs no root.
    local fans
    if fans="$("$tmp/tuidev-fan" status --tsv 2>/dev/null)" && [[ "$fans" != *$'\n'fan$'\t'* ]]; then
        rm -rf "$tmp"
        print_info "cooling: this Mac has no fans; nothing to run"
        return 0
    fi
    install_config "$bin" "$tmp/tuidev-fan" --overwrite
    if ! cmp -s "$bin" "$tmp/tuidev-fan"; then
        rm -rf "$tmp"
        print_warning "cooling: $bin was not replaced (continuing; the daemon is unchanged)"
        return 0
    fi
    chmod 0755 "$bin"

    local rc=0
    _cooling_root_install "$bin" || rc=$?
    case "$rc" in
        0)  printf '%s\n' "$sum" > "$tmp/stamp"
            install_config "$stamp" "$tmp/stamp" --overwrite
            print_info "cooling: fans follow the SoC's temperature now; 'agents cool' shows them, 'agents cool cool|auto|quiet|max|off' switches"
            print_info "cooling: the curve lives in /Library/Application Support/tuidev/fan/fan.conf (balanced: low=60, high=95 °C)" ;;
        3)  print_info "cooling: this Mac has no fans; nothing to run" ;;
        *)  if [[ -f "$COOLING_PLIST" ]]; then
                print_warning "cooling: the new build is not installed; the fan daemon keeps running the previous one"
            else
                print_warning "cooling: fan control is built but not running yet"
            fi ;;
    esac
    rm -rf "$tmp"
    print_success "cooling pack complete"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    cooling_install "$@"
fi
