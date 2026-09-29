#!/bin/bash
# Migration: the shipped .zshrc puts Node on PATH only through fnm (3.2.4).
#
# The nvm fallback is gone. Nothing is removed here: ~/.nvm, its Node versions
# and its global packages stay where they are. This only warns a machine that
# still relies on nvm, before the next shell loses node, npm and npx, and says
# how to move to fnm.

set -eo pipefail

MIGRATION_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/ui.sh disable=SC1091
. "$MIGRATION_DIR/../lib/ui.sh"

nvm_dir="${NVM_DIR:-$HOME/.nvm}"
[[ -s "$nvm_dir/nvm.sh" ]] || exit 0

if command -v fnm >/dev/null 2>&1; then
    print_info "fnm is installed; the shipped .zshrc now uses it for Node, not nvm ($nvm_dir is left alone)"
    exit 0
fi

print_warning "the shipped .zshrc no longer loads nvm: new shells get Node only through fnm"
print_info "Move over:  ./install.sh --pack fnm   (installs fnm and the latest LTS)"
print_info "Then reinstall global CLIs, e.g.:  npm i -g <package>   (list them: ls $nvm_dir/versions/node/*/lib/node_modules)"
print_info "Or keep nvm: source $nvm_dir/nvm.sh from ~/.zshrc.local"
