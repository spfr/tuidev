#!/bin/bash
# Add the shipped zsh to a demo home that demo-shell-setup.sh already built
# (docs/assets/tapes/README.md): demo-zsh-setup.sh HOME. Idempotent. It copies
# configs/zsh/.zshrc in, as an install would, and gives the shell a made-up
# past: a short ~/.zsh_history (for autosuggestions and atuin's Ctrl-R) and
# zoxide's directory ranking (for `z`). The cli tape then runs `exec zsh -i`.
set -eo pipefail

home="${1:?usage: demo-zsh-setup.sh HOME}"
tapes="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$tapes/../../.." && pwd)"

export HOME="$home"
unset XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME XDG_STATE_HOME ZDOTDIR HISTFILE

# (demo-setup.sh leaves a one-line placeholder rc for the sbx shot.)
cmp -s "$repo/configs/zsh/.zshrc" "$home/.zshrc" || cp "$repo/configs/zsh/.zshrc" "$home/.zshrc"

if [[ ! -f "$home/.zsh_history" ]]; then
    now="$(date +%s)" i=0
    while IFS= read -r line; do
        i=$((i + 1))
        printf ': %d:%d;%s\n' "$((now - 86400 + i * 1800))" "$(( (i * 7) % 5 ))" "$line"
    done > "$home/.zsh_history" <<'EOT'
z web
pnpm dev
z api
uv run pytest -q
git status
rg TODO src
make test
git diff --stat
claude -w fix-404
agents
sbx -- make test
git log --oneline -5
z myapp
npm test
z api
make test
EOT
fi

# atuin's database, from that history (Ctrl-R searches it).
if command -v atuin >/dev/null 2>&1 && [[ ! -d "$home/.local/share/atuin" ]]; then
    HISTFILE="$home/.zsh_history" SHELL=/bin/zsh atuin import zsh >/dev/null 2>&1 || echo "demo-zsh-setup: atuin import failed" >&2
fi

# zoxide's ranking: api first, so `z ap` lands there.
if command -v zoxide >/dev/null 2>&1; then
    for d in myapp web api api api; do zoxide add "$home/$d"; done
fi
