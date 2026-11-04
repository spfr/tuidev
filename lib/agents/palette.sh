# shellcheck shell=bash
# lib/agents/palette.sh — one palette: six semantic colors for every view.
#
# Owns: the tokens (need, done, run, warn, dim, accent) as SGR codes in C_*,
#   how many colors the terminal shows, reading a theme's palette.toml, and
#   the menu's palette row.
# Uses: config.sh (AGENTS_THEME, AGENTS_COLOR_*, _AGENTS_LIB).
# Public: _agents_colors, _agents_awk_colored, _agents_utf8, _agents_palette_row.
#
# A token is a palette key or #rrggbb. AGENTS_THEME picks where palette keys
# come from: auto (the default) reads the theme scripts/theme.sh applied, ansi
# none at all (the terminal's own 16 colors), none no color, any other word
# that palette. The palette files ship with the modules
# (themes/NAME/palette.toml; configs/themes/ in a checkout), so agents needs no
# repo, and no file means the 16 colors, never an error: the view must look
# right with nothing configured. No fork here: every command starts with this.

_AGENTS_TRUECOLOR=16777216
# _agents_color_depth — REPLY: how many colors the terminal shows: 0 (TERM=dumb,
# whatever else says), _AGENTS_TRUECOLOR (COLORTERM says so), 256 (TERM says so),
# or 16.
_agents_color_depth() {
    [[ "${TERM:-}" != dumb ]] || { REPLY=0; return; }
    case "${COLORTERM:-}" in truecolor|24bit) REPLY=$_AGENTS_TRUECOLOR; return ;; esac
    case "${TERM:-}" in
        *256color*) REPLY=256 ;;
        *)          REPLY=16 ;;
    esac
}

# _agents_palette_load — once per run, the theme's colors as _AP_<key>, and
# _AGENTS_PALETTE its name ("" when there is none to read). The file's format
# is theme.sh's: `key = "#rrggbb"`, one per line, so a regex is the whole parser.
_agents_palette_load() {
    [[ -z "${_AGENTS_PALETTE_LOADED:-}" ]] || return 0
    _AGENTS_PALETTE_LOADED=1 _AGENTS_PALETTE=""
    local name="$AGENTS_THEME" file line re='^[[:space:]]*([a-z0-9_]+)[[:space:]]*=[[:space:]]*"(#[0-9a-fA-F]{6})"'
    case "$name" in
        none|ansi) return 0 ;;
        auto) name=""
              { read -r name < "${TUIDEV_STATE_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/tuidev}/theme"; } 2>/dev/null ;;
    esac
    [[ "$name" =~ ^[a-z0-9][a-z0-9_-]*$ ]] || return 0
    for file in "$_AGENTS_LIB/themes/$name/palette.toml" "${_AGENTS_LIB%/lib/agents}/configs/themes/$name/palette.toml"; do
        [[ -r "$file" ]] || continue
        while IFS= read -r line || [[ -n "$line" ]]; do
            [[ "$line" =~ $re ]] && printf -v "_AP_${BASH_REMATCH[1]}" '%s' "${BASH_REMATCH[2]}"
        done < "$file"
        _AGENTS_PALETTE="$name"
        return 0
    done
}

# _agents_color_token TOKEN — REPLY: what TOKEN is set to, a palette key or #rrggbb
# ("" for none: dim is SGR 2 until you name a color); REPLY_SLOT: its SGR code
# among the 16 colors.
_agents_color_token() {
    case "$1" in
        need)   REPLY="${AGENTS_COLOR_NEED:-ansi_red}"    REPLY_SLOT=31 ;;
        done)   REPLY="${AGENTS_COLOR_DONE:-ansi_blue}"   REPLY_SLOT=34 ;;
        run)    REPLY="${AGENTS_COLOR_RUN:-ansi_green}"   REPLY_SLOT=32 ;;
        warn)   REPLY="${AGENTS_COLOR_WARN:-ansi_yellow}" REPLY_SLOT=33 ;;
        dim)    REPLY="${AGENTS_COLOR_DIM:-}"             REPLY_SLOT=2 ;;
        accent) REPLY="${AGENTS_COLOR_ACCENT:-accent}"    REPLY_SLOT=34 ;;
    esac
    # A key naming an ANSI slot is that slot, palette or not.
    case "$REPLY" in
        ansi_black)   REPLY_SLOT=30 ;; ansi_red)     REPLY_SLOT=31 ;; ansi_green) REPLY_SLOT=32 ;;
        ansi_yellow)  REPLY_SLOT=33 ;; ansi_blue)    REPLY_SLOT=34 ;; ansi_magenta) REPLY_SLOT=35 ;;
        ansi_cyan)    REPLY_SLOT=36 ;; ansi_white)   REPLY_SLOT=37 ;;
        ansi_bright_black)  REPLY_SLOT=90 ;; ansi_bright_red)  REPLY_SLOT=91 ;; ansi_bright_green)   REPLY_SLOT=92 ;;
        ansi_bright_yellow) REPLY_SLOT=93 ;; ansi_bright_blue) REPLY_SLOT=94 ;; ansi_bright_magenta) REPLY_SLOT=95 ;;
        ansi_bright_cyan)   REPLY_SLOT=96 ;; ansi_bright_white) REPLY_SLOT=97 ;;
    esac
}

# _agents_color_hex TOKEN — REPLY: its #rrggbb ("" when only the terminal knows
# it); REPLY_SLOT as _agents_color_token.
_agents_color_hex() {
    _agents_color_token "$1"
    case "$REPLY" in
        \#*) ;;
        "")  ;;
        *)   local v="_AP_$REPLY"; REPLY="${!v-}" ;;
    esac
}

# _agents_rgb_256 R G B — REPLY: the xterm-256 index nearest that color: the
# nearer of its place in the 6x6x6 cube and on the gray ramp.
_agents_rgb_256() {
    local v i c=() cube=() gray gi gv dc dg
    for v in "$1" "$2" "$3"; do
        if [[ $v -lt 48 ]]; then i=0; elif [[ $v -lt 115 ]]; then i=1; else i=$(( (v - 35) / 40 )); fi
        c+=("$i"); if [[ $i -eq 0 ]]; then cube+=(0); else cube+=($((55 + 40 * i))); fi
    done
    gray=$(( ($1 + $2 + $3) / 3 ))
    if [[ $gray -gt 238 ]]; then gi=23; elif [[ $gray -lt 8 ]]; then gi=0; else gi=$(( (gray - 3) / 10 )); fi
    gv=$((8 + 10 * gi))
    dc=$(( ($1 - cube[0]) ** 2 + ($2 - cube[1]) ** 2 + ($3 - cube[2]) ** 2 ))
    dg=$(( ($1 - gv) ** 2 + ($2 - gv) ** 2 + ($3 - gv) ** 2 ))
    if [[ $dg -lt $dc ]]; then REPLY=$((232 + gi)); else REPLY=$((16 + 36 * c[0] + 6 * c[1] + c[2])); fi
}

# _agents_sgr TOKEN DEPTH — REPLY: the token's SGR parameters at that depth.
_agents_sgr() {
    local h
    _agents_color_hex "$1"; h="$REPLY"
    if [[ -z "$h" || $2 -lt 256 ]]; then REPLY="$REPLY_SLOT"; return; fi
    if [[ $2 -eq $_AGENTS_TRUECOLOR ]]; then
        REPLY="38;2;$((16#${h:1:2}));$((16#${h:3:2}));$((16#${h:5:2}))"
    else
        _agents_rgb_256 "$((16#${h:1:2}))" "$((16#${h:3:2}))" "$((16#${h:5:2}))"
        REPLY="38;5;$REPLY"
    fi
}

# _agents_colors [--always] — the tokens as C_NEED C_DONE C_RUN C_WARN C_DIM
# C_ACC, with C_B (bold), C_0 (reset) and C_TINT (the row tint of Needs you, a
# background: truecolor only, since it needs need's color mixed into the
# palette's own background). All empty when output is no terminal (--always,
# for the status line, which Claude Code shows in color: it pipes it), under
# NO_COLOR, TUIDEV_NO_COLOR or AGENTS_THEME=none, and on a dumb terminal: the
# views keep their glyphs, so nothing depends on these.
_agents_colors() {
    local depth need
    C_B='' C_DIM='' C_NEED='' C_DONE='' C_RUN='' C_WARN='' C_ACC='' C_TINT='' C_0=''
    [[ "${1:-}" == --always || -t 1 ]] || return 0
    [[ -z "${NO_COLOR:-}" && -z "${TUIDEV_NO_COLOR:-}" && "$AGENTS_THEME" != none ]] || return 0
    _agents_color_depth; depth="$REPLY"
    [[ $depth -gt 0 ]] || return 0
    # The 16 colors take no palette: the terminal's own stand in for it.
    [[ $depth -lt 256 ]] || _agents_palette_load
    C_B=$'\033[1m' C_0=$'\033[0m'
    _agents_sgr need "$depth";   C_NEED=$'\033['"$REPLY"m
    _agents_sgr "done" "$depth"; C_DONE=$'\033['"$REPLY"m
    _agents_sgr run "$depth";    C_RUN=$'\033['"$REPLY"m
    _agents_sgr warn "$depth";   C_WARN=$'\033['"$REPLY"m
    _agents_sgr dim "$depth";    C_DIM=$'\033['"$REPLY"m
    _agents_sgr accent "$depth"; C_ACC=$'\033['"$REPLY"m
    [[ $depth -eq $_AGENTS_TRUECOLOR && -n "${_AP_bg:-}" ]] || return 0
    _agents_color_hex need; need="$REPLY"
    [[ -n "$need" ]] || return 0
    C_TINT=$'\033[48;2;'"$(( (16#${need:1:2} * 14 + 16#${_AP_bg:1:2} * 86) / 100 ));$(( (16#${need:3:2} * 14 + 16#${_AP_bg:3:2} * 86) / 100 ));$(( (16#${need:5:2} * 14 + 16#${_AP_bg:5:2} * 86) / 100 ))"m
}

# _agents_utf8 — true when the locale shows block glyphs. A Mac's terminals are
# UTF-8 whatever LANG says, so only an explicit other locale counts there.
_agents_utf8() {
    local l="${LC_ALL:-${LC_CTYPE:-${LANG:-}}}"
    case "$l" in
        *[Uu][Tt][Ff]-8*|*[Uu][Tt][Ff]8*) return 0 ;;
        "") [[ "$OSTYPE" == darwin* ]] ;;
        *)  return 1 ;;
    esac
}

# _agents_awk_colored "FILE..." [AWK_OPTION...] — _agents_awk with the tokens in
# its environment, and whether gauge() (lib_fmt) may draw blocks.
_agents_awk_colored() {
    local ascii=1
    ! _agents_utf8 || ascii=""
    B="$C_B" DIM="$C_DIM" NEED="$C_NEED" DONE="$C_DONE" RUN="$C_RUN" WARN="$C_WARN" ACC="$C_ACC" TINT="$C_TINT" N="$C_0" \
    AGENTS_ASCII="$ascii" _agents_awk "$@"
}

# _agents_palette_row — agents tsv's row for the menu's tints:
#   palette NAME NEED DONE RUN WARN ACCENT BG
# NAME "-" and a color "-" where there is none; no row when nothing but the
# terminal knows a color (AGENTS_THEME=ansi or none, no palette).
_agents_palette_row() {
    local t out="" any=""
    [[ "$AGENTS_THEME" != none ]] || return 0
    _agents_palette_load
    for t in need "done" run warn accent; do
        _agents_color_hex "$t"
        out+=$'\t'"${REPLY:--}"
        [[ -z "$REPLY" ]] || any=1
    done
    [[ -n "$any" ]] || return 0
    printf 'palette\t%s%s\t%s\n' "${_AGENTS_PALETTE:--}" "$out" "${_AP_bg:--}"
}
