#!/bin/bash
# ============================================================================
# scripts/theme.sh - single-palette theming for tuidev.
# ============================================================================
# One palette file per theme (configs/themes/<name>/palette.toml) is rendered
# into per-app snippets and written into the user's installed configs as
# managed blocks (block id: tuidev-theme). User content outside the markers is
# never touched.
#
#   theme.sh list                    list discovered themes
#   theme.sh show <name>             print the palette (with swatches on a TTY)
#   theme.sh apply <name> [--dry-run]  render + write the managed blocks
#
# Targets: tmux, ghostty, starship. Neovim is deliberately out of scope — its
# colorscheme is plugin-managed; see docs/theming.md.
# ============================================================================

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# shellcheck source=./lib/ui.sh disable=SC1091
. "$SCRIPT_DIR/lib/ui.sh"
# shellcheck source=./lib/config_write.sh disable=SC1091
. "$SCRIPT_DIR/lib/config_write.sh"

THEMES_DIR="${TUIDEV_THEMES_DIR:-$REPO_ROOT/configs/themes}"
THEME_BLOCK_ID="tuidev-theme"
THEME_STATE_FILE="$HOME/.config/tuidev/theme"

# The palette contract. Every theme must define exactly these keys; apply
# refuses to render if any are missing. Documented in docs/theming.md.
THEME_KEYS=(
    bg bg_dark bg_highlight
    fg fg_dim
    accent cursor selection_bg border border_active
    ansi_black ansi_red ansi_green ansi_yellow
    ansi_blue ansi_magenta ansi_cyan ansi_white
    ansi_bright_black ansi_bright_red ansi_bright_green ansi_bright_yellow
    ansi_bright_blue ansi_bright_magenta ansi_bright_cyan ansi_bright_white
)

# ============================================================================
# Palette parsing
# ============================================================================
# Deliberately no TOML parser: the palette format is constrained to
# `key = "#rrggbb"` lines precisely so a regex is a complete parser. Anything
# that does not match that shape is ignored, and the key contract check below
# turns a typo into a clear error rather than a silently missing color.

# _palette_meta FILE KEY -> prints a quoted string value ([theme] metadata).
_palette_meta() {
    sed -n -E "s/^[[:space:]]*$2[[:space:]]*=[[:space:]]*\"([^\"]*)\".*/\1/p" "$1" | head -n1
}

# _palette_load FILE — sets _P_<key> for every color line in FILE.
_palette_load() {
    local file="$1" line key val
    _PALETTE_EXTRA=""

    for key in "${THEME_KEYS[@]}"; do
        unset "_P_$key"
    done

    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "$line" =~ ^[[:space:]]*(#|\[|$) ]] && continue
        [[ "$line" =~ ^[[:space:]]*([a-z0-9_]+)[[:space:]]*=[[:space:]]*\"(#[0-9a-f]{6})\"[[:space:]]*(#.*)?$ ]] || continue
        key="${BASH_REMATCH[1]}"
        # shellcheck disable=SC2034  # read back through eval / pc()'s indirection
        val="${BASH_REMATCH[2]}"
        if _is_contract_key "$key"; then
            eval "_P_${key}=\$val"
        else
            _PALETTE_EXTRA="$_PALETTE_EXTRA $key"
        fi
    done < "$file"
}

_is_contract_key() {
    local k
    for k in "${THEME_KEYS[@]}"; do
        [[ "$k" == "$1" ]] && return 0
    done
    return 1
}

# pc KEY -> "#rrggbb"   |   pcx KEY -> "rrggbb" (ghostty's un-prefixed form)
pc() {
    local ref="_P_$1"
    printf '%s' "${!ref}"
}
pcx() {
    local ref="_P_$1"
    printf '%s' "${!ref#\#}"
}

# _palette_validate NAME — every contract key present, else fail listing them.
_palette_validate() {
    local name="$1" missing="" k ref
    for k in "${THEME_KEYS[@]}"; do
        ref="_P_$k"
        [[ -n "${!ref:-}" ]] || missing="$missing $k"
    done

    if [[ -n "$missing" ]]; then
        print_error "theme '$name' is missing required palette keys:"
        for k in $missing; do
            echo "    - $k"
        done
        print_info 'every key must appear on its own line as: key = "#rrggbb" (see docs/theming.md)'
        return 1
    fi

    if [[ -n "$_PALETTE_EXTRA" ]]; then
        print_warning "theme '$name' defines keys outside the contract (ignored):$_PALETTE_EXTRA"
    fi
    return 0
}

# ============================================================================
# Theme discovery
# ============================================================================

theme_path() { printf '%s' "$THEMES_DIR/$1/palette.toml"; }

theme_names() {
    local dir
    for dir in "$THEMES_DIR"/*/; do
        [[ -f "$dir/palette.toml" ]] || continue
        basename "$dir"
    done
}

active_theme() {
    [[ -f "$THEME_STATE_FILE" ]] && head -n1 "$THEME_STATE_FILE"
}

# ============================================================================
# Renderers — each prints one managed-block body to stdout
# ============================================================================

render_tmux() {
    cat <<EOF
# tuidev theme: $1 — generated by scripts/theme.sh, do not edit by hand.
set-option -g status-style "bg=$(pc bg),fg=$(pc fg)"
set-option -g status-left "#[bg=$(pc accent),fg=$(pc bg),bold] #S #[bg=$(pc bg),fg=$(pc accent)] "
set-option -g status-right "#[fg=$(pc bg_highlight)]#[bg=$(pc bg_highlight),fg=$(pc fg)] %H:%M #[bg=$(pc bg_highlight),fg=$(pc accent)]#[bg=$(pc accent),fg=$(pc bg),bold] %d %b "
set-window-option -g window-status-format "#[fg=$(pc fg)] #I:#W "
set-window-option -g window-status-current-format "#[bg=$(pc bg_highlight),fg=$(pc accent),bold] #I:#W "
set-window-option -g window-status-activity-style "fg=$(pc ansi_yellow)"
set-option -g pane-border-style "fg=$(pc border)"
set-option -g pane-active-border-style "fg=$(pc border_active)"
set-option -g message-style "bg=$(pc bg_highlight),fg=$(pc accent)"
set-option -g message-command-style "bg=$(pc bg_highlight),fg=$(pc fg)"
set-window-option -g mode-style "bg=$(pc accent),fg=$(pc bg)"
EOF
}

render_ghostty() {
    cat <<EOF
# tuidev theme: $1 — generated by scripts/theme.sh, do not edit by hand.
background = $(pcx bg)
foreground = $(pcx fg)
cursor-color = $(pcx cursor)
selection-background = $(pcx selection_bg)
selection-foreground = $(pcx fg)
palette = 0=$(pc ansi_black)
palette = 1=$(pc ansi_red)
palette = 2=$(pc ansi_green)
palette = 3=$(pc ansi_yellow)
palette = 4=$(pc ansi_blue)
palette = 5=$(pc ansi_magenta)
palette = 6=$(pc ansi_cyan)
palette = 7=$(pc ansi_white)
palette = 8=$(pc ansi_bright_black)
palette = 9=$(pc ansi_bright_red)
palette = 10=$(pc ansi_bright_green)
palette = 11=$(pc ansi_bright_yellow)
palette = 12=$(pc ansi_bright_blue)
palette = 13=$(pc ansi_bright_magenta)
palette = 14=$(pc ansi_bright_cyan)
palette = 15=$(pc ansi_bright_white)
EOF
}

# Starship: emit a [palettes.tuidev] table that *overrides the standard color
# names* (green, cyan, purple, ...). That way the shipped module styles
# ("bold green", "bold cyan", "bright-black") re-theme themselves with no edit
# to any style string. Selecting it still needs a top-level `palette = "tuidev"`
# above the first table — apply() warns when that line is absent.
render_starship() {
    cat <<EOF
# tuidev theme: $1 — generated by scripts/theme.sh, do not edit by hand.
# Requires \`palette = "tuidev"\` at the top of starship.toml (before any table).
[palettes.tuidev]
black = "$(pc ansi_black)"
red = "$(pc ansi_red)"
green = "$(pc ansi_green)"
yellow = "$(pc ansi_yellow)"
blue = "$(pc ansi_blue)"
purple = "$(pc ansi_magenta)"
cyan = "$(pc ansi_cyan)"
white = "$(pc ansi_white)"
"bright-black" = "$(pc ansi_bright_black)"
"bright-red" = "$(pc ansi_bright_red)"
"bright-green" = "$(pc ansi_bright_green)"
"bright-yellow" = "$(pc ansi_bright_yellow)"
"bright-blue" = "$(pc ansi_bright_blue)"
"bright-purple" = "$(pc ansi_bright_magenta)"
"bright-cyan" = "$(pc ansi_bright_cyan)"
"bright-white" = "$(pc ansi_bright_white)"
tuidev_bg = "$(pc bg)"
tuidev_bg_dark = "$(pc bg_dark)"
tuidev_bg_highlight = "$(pc bg_highlight)"
tuidev_fg = "$(pc fg)"
tuidev_fg_dim = "$(pc fg_dim)"
tuidev_accent = "$(pc accent)"
EOF
}

# ============================================================================
# Commands
# ============================================================================

cmd_list() {
    local names active name desc marker
    names="$(theme_names)"
    [[ -n "$names" ]] || die "no themes found under $THEMES_DIR"
    active="$(active_theme || true)"

    echo "Themes in $THEMES_DIR:"
    echo ""
    while IFS= read -r name; do
        desc="$(_palette_meta "$(theme_path "$name")" description)"
        marker="  "
        [[ "$name" == "$active" ]] && marker="* "
        printf '%s%-18s %s\n' "$marker" "$name" "$desc"
    done <<< "$names"
    echo ""
    [[ -n "$active" ]] && print_info "active: $active"
    return 0
}

cmd_show() {
    local name="$1" file k swatch
    [[ -n "$name" ]] || die "usage: theme.sh show <name>"
    file="$(theme_path "$name")"
    [[ -f "$file" ]] || die "unknown theme '$name' (try: theme.sh list)"

    _palette_load "$file"
    _palette_validate "$name" || exit 1

    print_header "Theme: $name"
    _palette_meta "$file" description
    echo ""
    for k in "${THEME_KEYS[@]}"; do
        swatch=""
        # 24-bit swatch only on a TTY; NO_COLOR and pipes get plain hex.
        if [[ -t 1 && -z "${TUIDEV_NO_COLOR:-}${NO_COLOR:-}" ]]; then
            swatch="$(printf '\033[48;2;%d;%d;%dm    \033[0m' \
                "$((16#$(pcx "$k" | cut -c1-2)))" \
                "$((16#$(pcx "$k" | cut -c3-4)))" \
                "$((16#$(pcx "$k" | cut -c5-6)))")"
        fi
        printf '  %-22s %s %s\n' "$k" "$(pc "$k")" "$swatch"
    done
    echo ""
}

# _tmux_reload FILE — push the freshly rendered tmux snippet into a live
# server so open panes re-theme immediately. Best-effort: no server, no-op.
_tmux_reload() {
    command_exists tmux || return 0
    tmux list-sessions >/dev/null 2>&1 || return 0
    if tmux source-file "$1" 2>/dev/null; then
        print_success "reloaded theme into the running tmux server"
    else
        print_warning "tmux is running but source-file failed (restart tmux to pick up the theme)"
    fi
}

# ============================================================================
# Block ordering
# ============================================================================
# Both target formats are last-write-wins, and install.sh *appends* its own
# managed blocks when they are absent. So a theme applied before the installer
# ran ends up above the shipped config and loses. write_managed_block replaces
# a block where it stands, which would preserve the bad order — so when our
# block is not already last we drop it first and let the write re-append it.

_block_begin() { printf '# >>> tuidev managed (%s) >>>' "$1"; }
_block_end()   { printf '# <<< tuidev managed (%s) <<<' "$1"; }

_has_block() {
    [[ -f "$1" ]] || return 1
    grep -qF "$(_block_begin "$2")" "$1" 2>/dev/null
}

# _block_is_last FILE BLOCK_ID — true when the block's end marker is the final
# non-blank line, i.e. nothing can override it.
_block_is_last() {
    local end
    end="$(_block_end "$2")"
    _has_block "$1" "$2" || return 1
    [[ "$(grep -v '^[[:space:]]*$' "$1" | tail -n1)" == "$end" ]]
}

# _reserve_last_slot FILE — guarantee the theme block ends up last in FILE.
_reserve_last_slot() {
    local file="$1"
    _has_block "$file" "$THEME_BLOCK_ID" || return 0
    _block_is_last "$file" "$THEME_BLOCK_ID" && return 0

    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY RUN] would move the theme block to the end of $file"
        return 0
    fi
    print_step "theme block is no longer last in $(basename "$file") — moving it to the end"
    remove_managed_block "$file" "$THEME_BLOCK_ID" >/dev/null
}

# _starship_selector_is_top_level FILE — a `palette = "tuidev"` key only selects
# the palette when it sits above the first [table]; below one it is just a
# string inside that table.
_starship_selector_is_top_level() {
    [[ -f "$1" ]] || return 1
    awk '
        /^[[:space:]]*\[/ { exit 1 }
        /^[[:space:]]*palette[[:space:]]*=[[:space:]]*["'"'"']tuidev["'"'"']/ { found=1; exit 0 }
        END { exit (found ? 0 : 1) }
    ' "$1"
}

# _starship_writable FILE — may we append a [palettes.tuidev] table to FILE?
#
# Only if the installer's own block is already there. TOML has no way to close
# a table, so every key appended after ours lands *inside* it: writing our
# table into a starship.toml that install.sh has yet to populate would swallow
# the entire shipped prompt config on the next install. Refusing is the only
# safe answer — we will not edit outside our own block to prevent it.
_starship_writable() {
    local file="$1"
    if ! _has_block "$file" "tuidev-starship"; then
        print_warning "skipping starship: $file has no tuidev-starship block yet"
        print_info "run ./install.sh (or make install) first, then re-apply the theme —"
        print_info "appending a [palettes.tuidev] table now would swallow the config installed later"
        return 1
    fi
    if ! _starship_selector_is_top_level "$file"; then
        print_warning "skipping starship: no top-level 'palette = \"tuidev\"' in $file"
        print_info "add this line above the first [table] and re-apply:"
        echo '    palette = "tuidev"'
        return 1
    fi
    return 0
}

cmd_apply() {
    local name="$1"
    [[ -n "$name" ]] || die "usage: theme.sh apply <name> [--dry-run]"

    local file stage
    file="$(theme_path "$name")"
    [[ -f "$file" ]] || die "unknown theme '$name' (try: theme.sh list)"

    _palette_load "$file"
    _palette_validate "$name" || exit 1

    print_header "Applying theme: $name"

    # Stage every render first and sanity-check it, so a broken palette can
    # never leave the user's configs half-themed (omarchy's stage-then-swap,
    # scaled down to three snippets).
    stage="$(mktemp -d "${TMPDIR:-/tmp}/tuidev-theme.XXXXXX")"
    trap 'rm -rf "$stage"' EXIT

    render_tmux     "$name" > "$stage/tmux.conf"
    render_ghostty  "$name" > "$stage/ghostty.conf"
    render_starship "$name" > "$stage/starship.toml"

    local rendered
    for rendered in tmux.conf ghostty.conf starship.toml; do
        [[ -s "$stage/$rendered" ]] || die "internal error: rendered $rendered is empty"
        grep -qE '#[0-9a-f]{6}' "$stage/$rendered" \
            || die "internal error: rendered $rendered contains no colors"
    done
    print_success "rendered 3 snippets (tmux, ghostty, starship)"

    local tmux_dest="$HOME/.config/tmux/tmux.conf"
    local ghostty_dest="$HOME/.config/ghostty/config"
    local starship_dest="$HOME/.config/starship.toml"

    # Starship is gated: unlike tmux/ghostty, a mis-ordered TOML table does not
    # merely lose, it swallows whatever is appended after it.
    local do_starship=false
    if _starship_writable "$starship_dest"; then
        do_starship=true
    fi

    if [[ "$DRY_RUN" == true ]]; then
        _preview "$tmux_dest"    "$stage/tmux.conf"
        _preview "$ghostty_dest" "$stage/ghostty.conf"
        $do_starship && _preview "$starship_dest" "$stage/starship.toml"
    fi

    _reserve_last_slot "$tmux_dest"
    _reserve_last_slot "$ghostty_dest"
    write_managed_block "$tmux_dest"    "$THEME_BLOCK_ID" "$(cat "$stage/tmux.conf")"
    write_managed_block "$ghostty_dest" "$THEME_BLOCK_ID" "$(cat "$stage/ghostty.conf")"

    if $do_starship; then
        _reserve_last_slot "$starship_dest"
        write_managed_block "$starship_dest" "$THEME_BLOCK_ID" "$(cat "$stage/starship.toml")"
    fi

    if [[ "$DRY_RUN" == true ]]; then
        print_info "[DRY RUN] would record active theme '$name' in $THEME_STATE_FILE"
        print_info "[DRY RUN] nothing was written"
        return 0
    fi

    mkdir -p "$(dirname "$THEME_STATE_FILE")"
    echo "$name" > "$THEME_STATE_FILE"

    _tmux_reload "$stage/tmux.conf"

    print_success "theme '$name' applied"
    print_info "ghostty: reload with the config-reload keybind or restart the app"
    $do_starship && print_info "starship: takes effect in new shells"
    return 0
}

_preview() {
    echo ""
    echo -e "${BOLD}--- $1 (managed block: $THEME_BLOCK_ID) ---${NC}"
    cat "$2"
}

usage() {
    cat <<'EOF'
Usage: theme.sh <command> [args]

Commands:
  list                     list available themes (* marks the active one)
  show <name>              print a theme's palette with swatches
  apply <name> [--dry-run] write the theme into tmux/ghostty/starship configs

Themes live in configs/themes/<name>/palette.toml. See docs/theming.md.
EOF
}

main() {
    local cmd="${1:-}"
    [[ $# -gt 0 ]] && shift

    local args=()
    local a
    for a in "$@"; do
        case "$a" in
            --dry-run) DRY_RUN=true ;;
            -h|--help) usage; return 0 ;;
            -*) die "unknown flag: $a" ;;
            *) args+=("$a") ;;
        esac
    done

    case "$cmd" in
        list)          cmd_list ;;
        show)          cmd_show "${args[0]:-}" ;;
        apply)         cmd_apply "${args[0]:-}" ;;
        -h|--help|"")  usage ;;
        *)             usage; die "unknown command: $cmd" ;;
    esac
}

main "$@"
