#!/bin/bash
#
# Optional pack: orchestration
#
# One multi-agent orchestration policy for Claude Code and Codex: the main
# session plans, delegates to tiered subagents, reviews and verifies, and stops
# review-ready. Installs, from configs/orchestration/:
#
#   - the always-on policy: ~/.claude/rules/tuidev-orchestration.md (a user
#     rule, which Claude Code loads every session; your ~/.claude/CLAUDE.md is
#     never touched) and the managed block `tuidev-orchestration` in
#     ~/.codex/AGENTS.md (Codex's copy adds a short mechanics section; your
#     own text outside the block is kept).
#   - the subagent tiers: ~/.claude/agents/*.md and ~/.codex/agents/*.toml
#   - the on-demand skills (delegation, verification): ~/.claude/skills/ and
#     ~/.agents/skills/ (where Codex reads user skills)
#
# Agent and skill files are tuidev-owned (--overwrite, backup first). The git
# and gh write gates live in --pack ai-clis, which owns the CLIs' settings.
# Replaces the symlinks the retired agents-orchestration installer left.
#
# Runs standalone, without the rest of tuidev (a team that only wants the
# agents, CI runners, sandboxes); ./uninstall.sh then removes only this pack:
#   bash scripts/install/packs/orchestration.sh
# See docs/orchestration.md.
#
# Entrypoint: orchestration_install
# Invoked via: ./install.sh --pack orchestration
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
# shellcheck source=../../lib/ui.sh disable=SC1091
. "$SCRIPT_DIR/../../lib/ui.sh"
# shellcheck source=../../lib/config_write.sh disable=SC1091
. "$SCRIPT_DIR/../../lib/config_write.sh"

ORCHESTRATION_SRC="$REPO_ROOT/configs/orchestration"
# Pack-owned block: re-applied by re-running this pack (update --configs does),
# so it is not in update.sh's cross-cutting MANAGED_BLOCKS list.
ORCHESTRATION_BLOCK="tuidev-orchestration"

# True for a symlink the agents-orchestration installer placed: an absolute
# link (that installer only wrote absolute ones) to that repo's build/ output
# or its agent files, whose checkout is either gone (a dangling link) or still
# has core/00-orchestration.md.
_orchestration_is_legacy_link() {
    local dest="$1" target root
    [[ -L "$dest" ]] || return 1
    target="$(readlink "$dest")"
    case "$target" in
        /*) ;;
        *) return 1 ;;
    esac
    case "$target" in
        */build/CLAUDE.md|*/build/AGENTS.md|*/build/skills/*/SKILL.md)
            root="${target%/build/*}" ;;
        */claude/agents/*.md|*/codex/agents/*.toml)
            root="${target%/*/agents/*}" ;;
        *) return 1 ;;
    esac
    [[ ! -e "$target" || -f "$root/core/00-orchestration.md" ]]
}

# _orchestration_writable DEST
# Clears DEST for writing: removes a legacy agents-orchestration link (copying
# onto it would write into that checkout), and refuses any other symlink — it
# is yours (dotfiles, say), and neither a copy nor a backup through it is safe.
_orchestration_writable() {
    local dest="$1"
    if _orchestration_is_legacy_link "$dest"; then
        run_cmd rm -f "$dest"
        print_info "removed the agents-orchestration link $dest"
    elif [[ -L "$dest" ]]; then
        print_warning "skipping $dest: it is a symlink of yours; install $(basename "$dest") there yourself if you want it"
        return 1
    fi
}

# _orchestration_restore_backup DEST
# agents-orchestration moved a file it replaced with a link to DEST.bak. Once
# that link is gone, put the user's own file back.
_orchestration_restore_backup() {
    local dest="$1"
    [[ -f "$dest.bak" && ! -L "$dest.bak" ]] || return 0
    # A dry run leaves the legacy link in place: preview the restore anyway.
    if [[ -e "$dest" || -L "$dest" ]]; then
        [[ "${DRY_RUN:-false}" == true ]] && _orchestration_is_legacy_link "$dest" || return 0
    fi
    run_cmd mv "$dest.bak" "$dest"
    print_info "restored your $dest from before agents-orchestration"
}

# _orchestration_warn_plain_copy FILE
# A copy-mode agents-orchestration install left the policy as plain text: say
# so, instead of silently loading it twice.
_orchestration_warn_plain_copy() {
    local file="$1" outside
    # A link left in place (a dry run) is not the user's text.
    [[ -f "$file" && ! -L "$file" ]] || return 0
    outside="$(sed "/tuidev managed ($ORCHESTRATION_BLOCK) >>>/,/tuidev managed ($ORCHESTRATION_BLOCK) <<</d" "$file")"
    if grep -qF "The main thread is the orchestrator:" <<<"$outside"; then
        print_warning "$file holds the orchestration policy as plain text (an agents-orchestration copy?): delete it there, or it loads twice"
    fi
}

_orchestration_install_instructions() {
    local src="$ORCHESTRATION_SRC/global-instructions.md" dest

    # Claude Code: a rule file of its own, so CLAUDE.md stays entirely yours.
    dest="$HOME/.claude/CLAUDE.md"
    if _orchestration_is_legacy_link "$dest"; then
        _orchestration_writable "$dest"
        _orchestration_restore_backup "$dest"
    fi
    _orchestration_warn_plain_copy "$dest"
    _orchestration_install_file "$src" "$HOME/.claude/rules/tuidev-orchestration.md"

    # Codex reads only ~/.codex/AGENTS.md (or AGENTS.override.md) globally.
    dest="$HOME/.codex/AGENTS.md"
    _orchestration_writable "$dest" || return 0
    _orchestration_restore_backup "$dest"
    _orchestration_warn_plain_copy "$dest"
    if [[ -f "$HOME/.codex/AGENTS.override.md" ]]; then
        print_warning "$HOME/.codex/AGENTS.override.md exists, so Codex ignores $dest and the orchestration policy in it"
    fi
    write_managed_block "$dest" "$ORCHESTRATION_BLOCK" \
        "$(cat "$src"; echo; cat "$ORCHESTRATION_SRC/codex/global-instructions.md")"
}

# _orchestration_install_file SRC DEST
_orchestration_install_file() {
    _orchestration_writable "$2" || return 0
    install_config "$2" "$1" --overwrite
}

_orchestration_install_skills() {
    local skill_dir name root
    for skill_dir in "$ORCHESTRATION_SRC"/skills/*/; do
        skill_dir="${skill_dir%/}"
        name="$(basename "$skill_dir")"
        for root in "$HOME/.claude/skills" "$HOME/.agents/skills"; do
            # Only a folder this pack creates is ours to remove on uninstall.
            [[ -d "$root/$name" ]] || tuidev_manifest_record dir "$root/$name"
            _orchestration_install_file "$skill_dir/SKILL.md" "$root/$name/SKILL.md"
        done
    done
}

# agents-orchestration used to pin the Codex session model. The pack leaves
# the session model to Codex; flag a superseded pin rather than edit your file.
_orchestration_check_codex_model() {
    local cfg="$HOME/.codex/config.toml"
    [[ -f "$cfg" ]] || return 0
    if grep -qE '^[[:space:]]*model[[:space:]]*=[[:space:]]*"gpt-5\.6-' "$cfg"; then
        print_warning "$cfg pins a superseded gpt-5.6 model: delete the model line to follow Codex's default."
    fi
}

orchestration_install() {
    print_header "Pack: orchestration"
    _orchestration_install_instructions
    local f
    for f in "$ORCHESTRATION_SRC"/claude/agents/*.md; do
        _orchestration_install_file "$f" "$HOME/.claude/agents/$(basename "$f")"
    done
    for f in "$ORCHESTRATION_SRC"/codex/agents/*.toml; do
        _orchestration_install_file "$f" "$HOME/.codex/agents/$(basename "$f")"
    done
    _orchestration_install_skills
    _orchestration_check_codex_model
    if [[ ! -f "$HOME/.codex/rules/tuidev.rules" ]]; then
        print_info "git and gh writes prompt only with --pack ai-clis (Claude ask rules, Codex rules file)."
    fi
    print_success "orchestration pack complete"
}

# Run if executed directly. Record what it writes, as install.sh does, so
# ./uninstall.sh can remove it on a machine that has only this pack.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    tuidev_manifest_enable
    orchestration_install "$@"
fi
