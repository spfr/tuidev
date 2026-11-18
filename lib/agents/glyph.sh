# shellcheck shell=bash
# lib/agents/glyph.sh — one mark for each kind of thing that runs in a
# terminal, the same mark wherever it is shown: Herdr's tabs and sidebar, the
# map, the menu bar. A reader learns five shapes once and then sees what is a
# Claude session, a Codex one or a plain shell without reading a word.
#
# Plain Unicode on purpose: no icon font to install, and no vendor's logo.
# AGENTS_GLYPHS changes one ("codex=C"), several, or turns them off ("off").
# The board's mark for a session Herdr's phone app reaches is no kind (its
# default, with an ASCII one, is awk/lib_fmt.awk's gl("phone")), but a
# "phone=" word here replaces it too (awk/board_view.awk).
#
# Owns: the glyph table and its setting.
# Uses: config.sh (AGENTS_GLYPHS).
# Public: _agents_glyph, _agents_glyph_map, _agents_glyphs_tsv.

# KIND=GLYPH words. "shell" is a pane with no agent in it, "agent" any agent
# CLI without a mark of its own (AGENTS_NAMES can name more than these).
_AGENTS_GLYPHS_DEFAULT="claude=✳ codex=⬡ grok=✕ agy=▲ cursor-agent=◈ shell=❯ agent=◆"

# _agents_glyph_map — the table in effect, as "KIND=GLYPH ..." on one line:
# the defaults, each replaced by AGENTS_GLYPHS's word for that kind. Empty
# when AGENTS_GLYPHS is "off". awk takes it whole (-v glyphs=...).
_agents_glyph_map() {
    local w k out="" seen=" "
    [[ "${AGENTS_GLYPHS:-}" != off ]] || return 0
    for w in ${AGENTS_GLYPHS:-} $_AGENTS_GLYPHS_DEFAULT; do
        k="${w%%=*}"
        case "$seen" in *" $k "*) continue ;; esac
        seen+="$k "
        out+="${out:+ }$w"
    done
    printf '%s\n' "$out"
}

# _agents_glyph VAR KIND — set VAR to KIND's mark: an agent CLI's own, the
# "agent" mark for one without, the "shell" mark for "shell", "-" or nothing.
# Empty when the marks are off.
_agents_glyph() {
    local _w _k="$2" _g="" _any=""
    [[ -n "$_k" && "$_k" != - ]] || _k=shell
    for _w in $(_agents_glyph_map); do
        case "${_w%%=*}" in
            "$_k")  _g="${_w#*=}"; break ;;
            agent)  _any="${_w#*=}" ;;
        esac
    done
    [[ -n "$_g" || "$_k" == shell ]] || _g="$_any"
    printf -v "$1" '%s' "$_g"
}

# _agents_glyphs_tsv — "glyph<TAB>KIND<TAB>GLYPH" a mark, for `agents tsv`
# (the menu bar draws the same marks without reading this file).
_agents_glyphs_tsv() {
    local w
    for w in $(_agents_glyph_map); do printf 'glyph\t%s\t%s\n' "${w%%=*}" "${w#*=}"; done
}
