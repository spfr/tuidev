#!/bin/bash
# Migration: the shipped .zshrc no longer sets up personal toolchains (3.21.0).
#
# Homebrew's keg-only Ruby, jenv, Yarn's global bin, RVM, the Android SDK, the
# Google Cloud SDK under ~/tools and iTerm2's shell integration left the
# tuidev-zshrc block: they are not part of an agent terminal, every shell paid
# for them, and Ruby's global LDFLAGS/CPPFLAGS leaked into unrelated native
# builds. So nothing that worked stops working, each one whose tool is on this
# machine is carried into ~/.zshrc.local (sourced last), in one marked
# section. Skipped: a machine whose ~/.zshrc never had the block, and a tool
# the user already sets up (its line is in ~/.zshrc outside the block, or in
# ~/.zshrc.local). With nothing to carry, no file is created or touched.
#
# The section is the user's: it is not recorded in the manifest (uninstall
# leaves it) and nothing re-applies it. The block writer only supplies its
# markers, so a second run by hand adds a tool installed since, and nothing
# else.
#
# shellcheck disable=SC2016  # the sections are zsh, written out unexpanded

set -eo pipefail

MIGRATION_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/ui.sh disable=SC1091
. "$MIGRATION_DIR/../lib/ui.sh"
# shellcheck source=../lib/config_write.sh disable=SC1091
. "$MIGRATION_DIR/../lib/config_write.sh"

# install.sh exports manifest recording before it runs migrations.
tuidev_manifest_disable

ZSHRC="$HOME/.zshrc"
LOCAL_RC="$HOME/.zshrc.local"
BLOCK_ID=tuidev-moved-toolchains

# Only a ~/.zshrc that carries the shipped block ever ran these lines.
[[ -f "$ZSHRC" ]] && grep -qxF "$(tuidev_block_begin tuidev-zshrc)" "$ZSHRC" || exit 0

# What the user set up themselves: ~/.zshrc minus the shipped block (which
# still holds the old lines until --configs re-applies it), and ~/.zshrc.local.
user_lines() {
    awk -v b="$(tuidev_block_begin tuidev-zshrc)" -v e="$(tuidev_block_end tuidev-zshrc)" \
        '$0 == b { skip = 1; next } $0 == e { skip = 0; next } !skip' "$ZSHRC"
    if [[ -f "$LOCAL_RC" ]]; then cat "$LOCAL_RC"; fi
}
USER_LINES="$(user_lines)"
user_has() { [[ "$USER_LINES" == *"$1"* ]]; }

# The Homebrew prefix the shipped .zshrc used: brew's own variable, else the
# two standard installs, else the brew on PATH.
brew_prefix() {
    local p
    if [[ -n "${HOMEBREW_PREFIX:-}" ]]; then printf '%s\n' "$HOMEBREW_PREFIX"; return 0; fi
    for p in /opt/homebrew /usr/local; do
        [[ -x "$p/bin/brew" ]] && { printf '%s\n' "$p"; return 0; }
    done
    p="$(command -v brew 2>/dev/null)" || return 1
    dirname "$(dirname "$p")"
}

SECTIONS=""
MOVED=""
add() { # add NAME TEXT
    SECTIONS="$SECTIONS
$2
"
    MOVED="${MOVED:+$MOVED, }$1"
}

# Written as a literal path, so only a plain one (every real Homebrew prefix).
prefix="$(brew_prefix || true)"
if [[ "$prefix" =~ ^[A-Za-z0-9/._-]+$ && -d "$prefix/opt/ruby/bin" ]] && ! user_has 'opt/ruby/bin'; then
    add "Homebrew Ruby" "# Ruby: Homebrew's keg-only build, ahead of the system Ruby. The shipped
# .zshrc also exported LDFLAGS/CPPFLAGS for it into every shell, which leaked
# into unrelated native builds (gems, Python wheels, node-gyp); they were not
# carried over. Pass them to the one build that needs them:
#   LDFLAGS=\"-L\$(brew --prefix ruby)/lib\" CPPFLAGS=\"-I\$(brew --prefix ruby)/include\" gem install NAME
if [[ -d \"$prefix/opt/ruby/bin\" ]]; then export PATH=\"$prefix/opt/ruby/bin:\$PATH\"; fi"
fi

if { [[ -d "${JENV_ROOT:-$HOME/.jenv}" ]] || command -v jenv >/dev/null 2>&1; } \
    && ! user_has 'jenv init' && ! user_has '.jenv/shims'; then
    add "jenv" '# Java (jenv). Shims go on PATH now; the full `jenv init` runs on the first
# `jenv` call, unless jenv plugins (export sets JAVA_HOME) need it at startup.
if [[ -d "$HOME/.jenv/bin" ]]; then export PATH="$HOME/.jenv/bin:$PATH"; fi
_jenv_plugins=("${JENV_ROOT:-$HOME/.jenv}"/plugins/*(N))
if (( $+commands[jenv] )); then
  if (( ${#_jenv_plugins} )); then
    eval "$(jenv init -)"
  else
    export PATH="${JENV_ROOT:-$HOME/.jenv}/shims:$PATH" JENV_SHELL=zsh JENV_LOADED=1
    unset JAVA_HOME JDK_HOME
    jenv() { unfunction jenv; eval "$(command jenv init - zsh)"; jenv "$@"; }
  fi
fi
unset _jenv_plugins'
fi

if [[ -d "$HOME/.yarn" ]] && ! user_has '.yarn/bin'; then
    add "Yarn" '# Yarn global bins.
if [[ -d "$HOME/.yarn" ]]; then export PATH="$HOME/.yarn/bin:$HOME/.config/yarn/global/node_modules/.bin:$PATH"; fi'
fi

if [[ -d "$HOME/.rvm/bin" ]] && ! user_has '.rvm/bin'; then
    add "RVM" '# RVM, after everything else on PATH.
if [[ -d "$HOME/.rvm/bin" ]]; then export PATH="$PATH:$HOME/.rvm/bin"; fi'
fi

# ANDROID_HOME from the environment counts too: the old block put its tools on
# PATH wherever it pointed. Skipped when the user's own lines put them there.
if { [[ -d "$HOME/Library/Android/sdk" ]] || [[ -n "${ANDROID_HOME:-}" && -d "${ANDROID_HOME:-}" ]]; } \
    && ! user_has 'platform-tools'; then
    add "Android SDK" '# Android SDK: adb, the emulator and sdkmanager on PATH.
if [[ -z "$ANDROID_HOME" && -d "$HOME/Library/Android/sdk" ]]; then export ANDROID_HOME="$HOME/Library/Android/sdk"; fi
if [[ -n "$ANDROID_HOME" ]]; then export PATH="$PATH:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$ANDROID_HOME/cmdline-tools/latest/bin"; fi'
fi

if [[ -f "$HOME/tools/google-cloud-sdk/path.zsh.inc" || -f "$HOME/tools/google-cloud-sdk/completion.zsh.inc" ]] \
    && ! user_has 'google-cloud-sdk/path.zsh.inc'; then
    add "Google Cloud SDK" '# Google Cloud SDK: gcloud on PATH, and its completions.
if [[ -f "$HOME/tools/google-cloud-sdk/path.zsh.inc" ]]; then . "$HOME/tools/google-cloud-sdk/path.zsh.inc"; fi
if [[ -f "$HOME/tools/google-cloud-sdk/completion.zsh.inc" ]]; then . "$HOME/tools/google-cloud-sdk/completion.zsh.inc"; fi'
fi

if [[ -f "$HOME/.iterm2_shell_integration.zsh" ]] && ! user_has 'iterm2_shell_integration'; then
    add "iTerm2 shell integration" '# iTerm2 shell integration, only inside iTerm2.
if [[ $TERM_PROGRAM == iTerm.app && -f "$HOME/.iterm2_shell_integration.zsh" ]]; then source "$HOME/.iterm2_shell_integration.zsh"; fi'
fi

[[ -n "$SECTIONS" ]] || exit 0

if existing="$(read_managed_block "$LOCAL_RC" "$BLOCK_ID")"; then
    content="$existing
$SECTIONS"
else
    content="# Moved here from tuidev's shipped .zshrc, which no longer sets up language
# toolchains, SDKs or other terminals: only the ones found on this machine.
# These lines are yours now: keep, edit or delete them, markers included.
# tuidev does not re-apply or uninstall them.
$SECTIONS"
fi
# One trailing newline: the writer adds its own before the end marker.
content="${content%
}"

# The writer backs an existing file up before it changes it, follows a symlink
# to the real file, and refuses (non-zero) if it cannot do either.
write_managed_block "$LOCAL_RC" "$BLOCK_ID" "$content" >/dev/null \
    || die "could not write $LOCAL_RC; nothing changed"
if [[ "$DRY_RUN" == true ]]; then
    print_info "[DRY RUN] would move to $LOCAL_RC: $MOVED"
    exit 0
fi
print_success "moved from the shipped .zshrc to $LOCAL_RC: $MOVED"
print_info "they are yours now: keep, edit or delete them there"
if [[ "$MOVED" == *Ruby* ]]; then
    print_info "Ruby's global LDFLAGS/CPPFLAGS were not carried over: they leaked into every native build"
fi
