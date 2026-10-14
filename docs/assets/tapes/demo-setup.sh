#!/bin/bash
# Build the screenshot demo's throwaway home (docs/assets/tapes/README.md):
# demo-setup.sh DIR. Idempotent. Everything in it is made up: three projects
# (myapp, api, web), a fake SSH key for sbx to deny, and the state bin/agents
# reads (keep-awake record, Herdr socket, the stub symlinks).
set -eo pipefail

home="${1:?usage: demo-setup.sh DIR}"
tapes="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "$home/myapp/src" "$home/myapp/.claude/worktrees/agent-a3f9c1" "$home/myapp/.claude/worktrees/agent-7d20e4" \
    "$home/api" "$home/web" "$home/.ssh" "$home/.aws" "$home/.config/tuidev/run" "$home/.demo/stubs"

printf '# myapp\n\nA made-up project for the tuidev screenshots.\n' > "$home/myapp/README.md"
printf 'export const answer = 42;\n' > "$home/myapp/src/index.ts"
# `sbx -- make test` runs for real and prints a made-up passing result.
printf 'test:\n\t@echo "✓ 12 passed"\n' > "$home/myapp/Makefile"

# A fake key: sbx must refuse to read it, so nothing real is ever at stake.
if [[ ! -f "$home/.ssh/id_ed25519" ]]; then
    printf -- '-----BEGIN OPENSSH PRIVATE KEY-----\nnot a real key: tuidev screenshot fixture\n-----END OPENSSH PRIVATE KEY-----\n' > "$home/.ssh/id_ed25519"
    chmod 700 "$home/.ssh"; chmod 600 "$home/.ssh/id_ed25519"
fi

# More made-up files outside the project: an AWS credentials file, and a shell
# rc that sbx must not let anything append to.
if [[ ! -f "$home/.aws/credentials" ]]; then
    printf '[default]\naws_access_key_id = AKIAEXAMPLEFAKEKEY\naws_secret_access_key = not-a-real-secret\n' > "$home/.aws/credentials"
    chmod 700 "$home/.aws"; chmod 600 "$home/.aws/credentials"
fi
[[ -f "$home/.zshrc" ]] || printf '# made-up shell rc\n' > "$home/.zshrc"

# sbx keeps an agent's own settings read-only; the shot shows it.
mkdir -p "$home/.claude"
[[ -f "$home/.claude/settings.json" ]] || echo '{}' > "$home/.claude/settings.json"

# `agents awake agents` is on, held by pid 8800 in fixtures/ps.txt.
echo "8800 Wed_Oct_14_09:02:00_2026 agents 0" > "$home/.config/tuidev/run/awake"

# The background task api's polling loop (pid 2120) waits on: it finished 5h
# ago, so its last line is Claude Code's exit marker and the loop's
# `grep -qE "^(ok|FAIL)"` will never match. `agents why 2120` reads it.
task="$home/.demo/claude-501/tasks/b1.output"
if [[ ! -f "$task" ]]; then
    mkdir -p "$(dirname "$task")"
    printf '=== RUN   TestHealth\n--- PASS: TestHealth (0.00s)\nPASS\nok  \tapi/routes\t0.412s\n[exited with code 0]\n' > "$task"
    perl -e '$t = time - 5 * 3600; utime $t, $t, $ARGV[0]' "$task"
fi

# A made-up week of CPU samples and cleanups, for `agents report` and the menu.
bash "$tapes/demo-history.sh" "$home"

for tool in ps lsof launchctl sysctl memory_pressure pmset notifyutil herdr; do
    ln -sf "$tapes/demo-stub.sh" "$home/.demo/stubs/$tool"
done

# bin/agents asks Herdr only when its socket exists; the stub answers instead.
sock="$home/.demo/herdr.sock"
if [[ ! -S "$sock" ]] && command -v perl >/dev/null 2>&1; then
    perl -MIO::Socket::UNIX -e 'IO::Socket::UNIX->new(Local => $ARGV[0], Listen => 1) or exit 1' "$sock" 2>/dev/null \
        || echo "demo-setup: could not create $sock; sessions will show no Herdr status" >&2
fi
