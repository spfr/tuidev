#!/bin/bash
#
# Optional pack: release-age
#
# A minimum release age for the package managers agents install through:
# a version newer than TUIDEV_RELEASE_AGE_DAYS (default 3) isn't installed
# yet. Hijacked releases are usually caught and pulled within hours (LiteLLM
# 1.107.0 was live for about two), so a few days' wait keeps them off the
# machine while the rest of the registry stays available.
#
#   npm   ~/.npmrc                     min-release-age (days)
#   bun   ~/.bunfig.toml               [install] minimumReleaseAge (seconds)
#   uv    uv.toml [pip] + shell.d      uv pip, uvx and uv tool only
#
# pnpm (11+) already waits a day by default and checks lockfile entries too:
# `--frozen-lockfile` refuses a locked version younger than the age, so a
# longer one here would only block teammates' fresh dependencies longer. npm
# and bun apply the age to new resolutions only; `npm ci` and
# `bun install --frozen-lockfile` install what the lockfile pins.
#
# Each setting is a managed block written only for a tool on PATH (re-run the
# pack after installing another) and only where you haven't set it yourself.
# Project config wins over these user-level files. uv is kept out of project
# locks: a user-level exclude-newer is recorded in uv.lock and `--locked` then
# fails for teammates and CI without it.
#
# Entrypoint: release_age_install
# Invoked via: ./install.sh --pack release-age

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
# shellcheck source=../../lib/ui.sh disable=SC1091
. "$SCRIPT_DIR/../../lib/ui.sh"
# shellcheck source=../../lib/config_write.sh disable=SC1091
. "$SCRIPT_DIR/../../lib/config_write.sh"

RELEASE_AGE_BLOCK=tuidev-release-age

# The file's text outside our managed block, so a setting of the user's own
# is found and left alone.
_release_age_outside() {
    local file="$1" begin end
    [[ -f "$file" ]] || return 0
    begin="$(tuidev_block_begin "$RELEASE_AGE_BLOCK" "$file")"
    end="$(tuidev_block_end "$RELEASE_AGE_BLOCK" "$file")"
    awk -v b="$begin" -v e="$end" '$0 == b { skip = 1 } !skip { print } $0 == e { skip = 0 }' "$file"
}

# _release_age_write TOOL FILE CLASH_RE CONTENT: the block, unless TOOL is
# missing or FILE already matches CLASH_RE outside it (the user's own
# setting, or a table a second header would break).
_release_age_write() {
    local tool="$1" file="$2" clash="$3" content="$4"
    command_exists "$tool" || return 0
    if _release_age_outside "$file" | grep -qE "$clash"; then
        print_info "$tool: $file already has its own setting here; left as it is"
        return 0
    fi
    write_managed_block "$file" "$RELEASE_AGE_BLOCK" "$content"
}

_release_age_fragment() {
    local days="$1" src="$REPO_ROOT/configs/zsh/release-age.zsh" tmp
    command_exists uv || return 0
    [[ -f "$src" ]] || { print_warning "release-age fragment missing: $src"; return 0; }
    tmp="$(mktemp "${TMPDIR:-/tmp}/tuidev-release-age.XXXXXX")"
    sed "s/@DAYS@/$days/g" "$src" > "$tmp"
    install_config "$TUIDEV_STATE_DIR/shell.d/release-age.zsh" "$tmp" --overwrite
    rm -f "$tmp"
}

release_age_install() {
    print_header "Pack: release-age"
    local days="${TUIDEV_RELEASE_AGE_DAYS:-3}"
    if ! [[ "$days" =~ ^[1-9][0-9]*$ ]]; then
        print_warning "TUIDEV_RELEASE_AGE_DAYS must be a whole number of days, not '$days' (skipping)"
        return 0
    fi

    _release_age_write npm "$HOME/.npmrc" '^[[:space:]]*min-release-age[[:space:]]*=' \
        "min-release-age=$days"
    _release_age_write bun "$HOME/.bunfig.toml" '^[[:space:]]*\[install\]' \
        "$(printf '[install]\nminimumReleaseAge = %s' "$((days * 86400))")"
    _release_age_write uv "${XDG_CONFIG_HOME:-$HOME/.config}/uv/uv.toml" '^[[:space:]]*\[pip\]' \
        "$(printf '# Keep top-level keys above this table.\n[pip]\nexclude-newer = "%s days"' "$days")"
    _release_age_fragment "$days"

    print_info "Packages younger than $days days wait. To take one now:"
    print_info "    npm i --min-release-age=0 PKG | bun add --minimum-release-age=0 PKG | UV_EXCLUDE_NEWER=false uvx PKG"
    print_success "release-age pack complete"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    release_age_install "$@"
fi
